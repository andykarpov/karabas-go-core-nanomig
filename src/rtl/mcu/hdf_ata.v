`timescale 1ns / 1ps
`default_nettype wire

/*
 hdf_ata.v

 An ATA hard disk on an image file (HDF) of the mcu file mounter, for the IDE bus of gayle_cf.v:
 it sits where the CF card is (cf_a, cf_cs_n, cf_rd_n, cf_wr_n, cf_dout -> din, dout -> cf_din),
 so gayle_cf with its emulated INTRQ works on it unchanged. The sectors go through img_sdc.v
 (sdc index 4).

 - device 0 only. With no image, or with device 1 selected, every register reads 0 (no device);
 - the bus is that of the card: DD7..0 is the first byte of a sector word, the registers are in
   DD7..0. A register access is done at the end of its strobe (rd_n / wr_n going high), as
   gayle_cf samples the read data in the last clock of the strobe;
 - the bus has no IORDY, so a data block has to be in the buffer before DRQ: one sector per block
   (IDENTIFY word 47 = 1). READ / WRITE MULTIPLE work with SET MULTIPLE 0 or 1;
 - commands: IDENTIFY, READ SECTORS, READ MULTIPLE, WRITE SECTORS, WRITE MULTIPLE, READ VERIFY,
   INITIALIZE DEVICE PARAMETERS (the CHS translation), SET MULTIPLE, the non-data commands that
   need no action (recalibrate, seek, power, flush, set features, diagnostics); others abort.
   CHS and LBA28 addressing;
 - the geometry: at mount the RDB in sector 0 (cylinders, sectors, heads as NanoMig takes them)
   if it fits CHS (heads 1-16, sectors 1-255, cylinders < 65536), else 16 heads, 63 sectors and
   the cylinders of the image size. Until it is known the device is busy (BSY, a spin-up);
 - a sector that img_sdc could not read or write ends the command with ERR (UNC on a read, ABRT
   on a write): img_sdc fills a failed read with zero bytes, which must not reach the disk as
   data;
 - the task file is updated per sector as ATA does (sector count, address of the last sector
   transferred, or of the failing one on an error).
*/

module hdf_ata #(
	parameter DEF_HEADS = 5'd16,
	parameter DEF_SPT = 8'd63
) (
	input wire clk,
	input wire reset,          // power on: forgets the image
	input wire ata_reset,      // the reset line of the bus (Amiga reset)

	// the IDE bus of gayle_cf
	input wire [2:0] a,
	input wire [1:0] cs_n,
	input wire rd_n,
	input wire wr_n,
	input wire [15:0] din,
	output reg [15:0] dout = 16'd0,

	// the image: one sdc index of img_sdc (busy, done, error and the strobe of this index only)
	input wire img_mounted,
	input wire [63:0] img_size,
	output reg sdc_rd = 1'b0,
	output reg sdc_wr = 1'b0,
	output reg [31:0] sdc_sector = 32'd0,
	input wire sdc_busy,
	input wire sdc_done,
	input wire sdc_error,
	input wire sdc_byte_in_strobe,
	input wire [8:0] sdc_byte_addr,
	input wire [7:0] sdc_byte_in_data,
	output wire [7:0] sdc_byte_out_data,

	output wire led
);

localparam ST_IDLE = 4'd0;
localparam ST_GEO = 4'd1;     // mount: read sector 0
localparam ST_GEO_DIV = 4'd2; // mount: cylinders of the default geometry
localparam ST_IDENT = 4'd3;   // IDENTIFY data into the buffer
localparam ST_CALC1 = 4'd4;   // CHS -> LBA
localparam ST_CALC2 = 4'd5;
localparam ST_CHECK = 4'd6;   // the LBA in the image?
localparam ST_FETCH = 4'd7;   // read: the sector into the buffer
localparam ST_DRQIN = 4'd8;   // read: the host takes the buffer
localparam ST_DRQOUT = 4'd9;  // write: the host fills the buffer
localparam ST_STORE = 4'd10;  // write: the buffer to the image

localparam OP_READ = 2'd0;
localparam OP_WRITE = 2'd1;
localparam OP_VERIFY = 2'd2;
localparam OP_IDENT = 2'd3;

//---------- Bus ------------

reg rd_n_d = 1'b1, wr_n_d = 1'b1;
always @(posedge clk) begin
	rd_n_d <= rd_n;
	wr_n_d <= wr_n;
end
wire rd_end = rd_n & ~rd_n_d;
wire wr_end = wr_n & ~wr_n_d;
wire cs0 = !cs_n[0] && cs_n[1];
wire cs1 = !cs_n[1] && cs_n[0];

//---------- Image and geometry ------------

reg        present = 1'b0;    // an image is mounted
reg        geo_ok = 1'b0;     // its geometry is known
reg        mnt = 1'b0;        // a new image to examine
reg [31:0] total = 32'd0;     // sectors of the image
reg [15:0] id_cyl = 16'd0;
reg [4:0]  id_heads = 5'd16;
reg [7:0]  id_spt = 8'd63;
reg [4:0]  cur_heads = 5'd16; // CHS translation (INITIALIZE DEVICE PARAMETERS)
reg [7:0]  cur_spt = 8'd63;
reg        rdb_ok = 1'b0;     // sector 0 is an RDB with a CHS geometry
reg [31:0] rdb_cyl = 32'd0, rdb_spt = 32'd0, rdb_heads = 32'd0;
reg [31:0] div_rem = 32'd0;

//---------- Task file ------------

reg [7:0] r_err = 8'h01;
reg [7:0] r_count = 8'h01;
reg [7:0] r_sector = 8'h01;
reg [7:0] r_cyl_lo = 8'h00;
reg [7:0] r_cyl_hi = 8'h00;
reg [7:0] r_head = 8'h00;     // device / head
reg [7:0] r_status = 8'h00;
reg       r_srst = 1'b0;      // device control SRST

wire       dev1 = r_head[4];
wire       lba_mode = r_head[6];
wire       here = present && !dev1;
wire [7:0] status = !geo_ok ? 8'h80 : r_status;

//---------- Sector buffer (block ram, one write port, one synchronous read port) ------------

reg  [15:0] mem [0:255];
reg  [15:0] q = 16'd0;
reg         we = 1'b0;
reg  [7:0]  wa = 8'd0;
reg  [15:0] wd = 16'd0;
reg  [7:0]  ptr = 8'd0;       // word of the host
reg  [3:0]  state = ST_IDLE;
wire [7:0]  ra = (state == ST_STORE) ? sdc_byte_addr[8:1] : ptr;
always @(posedge clk) begin
	q <= mem[ra];
	if (we)
		mem[wa] <= wd;
end

reg out_hi = 1'b0;
always @(posedge clk)
	out_hi <= sdc_byte_addr[0];
assign sdc_byte_out_data = out_hi ? q[15:8] : q[7:0];

//---------- IDENTIFY data ------------

function [15:0] ident;
	input [7:0] w;
	input [15:0] cyl;
	input [4:0] heads;
	input [7:0] spt;
	input [4:0] c_heads;
	input [7:0] c_spt;
	input [31:0] cap;
	begin
		case (w)
			8'd0:  ident = 16'h0040;                // fixed disk
			8'd1:  ident = cyl;
			8'd3:  ident = { 11'd0, heads };
			8'd6:  ident = { 8'd0, spt };
			8'd10, 8'd11, 8'd12, 8'd13, 8'd14, 8'd15, 8'd16, 8'd17, 8'd18:
			       ident = "00";                    // serial number
			8'd19: ident = "01";
			8'd23: ident = "1.";                    // firmware revision
			8'd24: ident = "0 ";
			8'd25, 8'd26: ident = "  ";
			8'd27: ident = "KA";                    // model
			8'd28: ident = "RA";
			8'd29: ident = "BA";
			8'd30: ident = "S ";
			8'd31: ident = "HD";
			8'd32: ident = "F ";
			8'd33, 8'd34, 8'd35, 8'd36, 8'd37, 8'd38, 8'd39, 8'd40, 8'd41, 8'd42, 8'd43, 8'd44,
			8'd45, 8'd46:
			       ident = "  ";
			8'd47: ident = 16'h8001;                // one sector per READ / WRITE MULTIPLE block
			8'd49: ident = 16'h0200;                // LBA
			8'd51: ident = 16'h0200;                // PIO mode 2
			8'd53: ident = 16'h0001;                // words 54-58 valid
			8'd54: ident = cyl;
			8'd55: ident = { 11'd0, c_heads };
			8'd56: ident = { 8'd0, c_spt };
			8'd57: ident = cap[15:0];
			8'd58: ident = cap[31:16];
			8'd60: ident = cap[15:0];               // LBA28 sectors
			8'd61: ident = { 4'd0, cap[27:16] };
			default: ident = 16'h0000;
		endcase
	end
endfunction

wire [31:0] cap = (total[31:28] != 4'd0) ? 32'h0FFFFFFF : total;

//---------- Commands ------------

reg  [1:0]  op = OP_READ;
reg  [8:0]  left = 9'd0;      // sectors of the command, this one included
reg  [31:0] lba = 32'd0;
reg  [20:0] chs_t = 21'd0;
reg         pend_reset = 1'b0;
reg         sdc_wait = 1'b0;  // the request of this index is with img_sdc
reg         geo_rd = 1'b0;    // the request is the sector 0 of a mount

localparam [7:0] ST_OK = 8'h50;
localparam [7:0] ST_DRQ = 8'h58;
localparam [7:0] ST_ERR = 8'h51;
localparam [7:0] ST_BSY = 8'h80;

assign led = sdc_wait;

// CHS: next sector of the task file
wire       chs_last_sec = (r_sector >= cur_spt);
wire       chs_last_head = ({ 1'b0, r_head[3:0] } >= cur_heads - 5'd1);
wire [27:0] lba_next = { r_head[3:0], r_cyl_hi, r_cyl_lo, r_sector } + 28'd1;

// cylinder * heads + head
function [20:0] id_mul1;
	input [7:0] cyl_hi;
	input [7:0] cyl_lo;
	input [4:0] heads;
	input [3:0] head;
	begin
		id_mul1 = { cyl_hi, cyl_lo } * heads + head;
	end
endfunction

// the task file to the next sector (the address of the last sector transferred at the end)
task next_sector_regs;
	begin
		r_count <= r_count - 8'd1;
		if (lba_mode)
			{ r_head[3:0], r_cyl_hi, r_cyl_lo, r_sector } <= lba_next;
		else if (!chs_last_sec)
			r_sector <= r_sector + 8'd1;
		else begin
			r_sector <= 8'd1;
			if (!chs_last_head)
				r_head[3:0] <= r_head[3:0] + 4'd1;
			else begin
				r_head[3:0] <= 4'd0;
				{ r_cyl_hi, r_cyl_lo } <= { r_cyl_hi, r_cyl_lo } + 16'd1;
			end
		end
	end
endtask

// a command can start when no command runs, or one waits for the host (it is dropped)
wire cmd_ok = (state == ST_IDLE || state == ST_DRQIN || state == ST_DRQOUT) && !mnt && geo_ok;

always @(posedge clk) begin
	we <= 1'b0;

	// register reads (any state: the host sees BSY while a command runs)
	if (!here)
		dout <= 16'h0000;
	else if (cs0) begin
		case (a)
			3'd0: dout <= q;
			3'd1: dout <= { 8'h00, r_err };
			3'd2: dout <= { 8'h00, r_count };
			3'd3: dout <= { 8'h00, r_sector };
			3'd4: dout <= { 8'h00, r_cyl_lo };
			3'd5: dout <= { 8'h00, r_cyl_hi };
			3'd6: dout <= { 8'h00, r_head };
			default: dout <= { 8'h00, status };
		endcase
	end
	else if (cs1 && a == 3'd6)
		dout <= { 8'h00, status };
	else
		dout <= 16'h0000;

	// mount: size 0 is an eject
	if (img_mounted) begin
		present <= (img_size[40:9] != 32'd0);
		total <= img_size[40:9];
		geo_ok <= 1'b0;
		mnt <= (img_size[40:9] != 32'd0);
	end

	// the request is taken: drop it
	if (sdc_busy) begin
		sdc_rd <= 1'b0;
		sdc_wr <= 1'b0;
	end

	// sector bytes from img_sdc into the buffer, and the RDB of a mount
	if (sdc_byte_in_strobe && sdc_wait) begin
		if (sdc_byte_addr[0]) begin
			we <= 1'b1;
			wa <= sdc_byte_addr[8:1];
			wd <= { sdc_byte_in_data, wd[7:0] };
		end
		else
			wd[7:0] <= sdc_byte_in_data;
		if (geo_rd) begin
			case (sdc_byte_addr)
				9'd0: rdb_ok <= (sdc_byte_in_data == "R");
				9'd1: if (sdc_byte_in_data != "D") rdb_ok <= 1'b0;
				9'd2: if (sdc_byte_in_data != "S") rdb_ok <= 1'b0;
				9'd3: if (sdc_byte_in_data != "K") rdb_ok <= 1'b0;
				9'd64, 9'd65, 9'd66, 9'd67: rdb_cyl <= { rdb_cyl[23:0], sdc_byte_in_data };
				9'd68, 9'd69, 9'd70, 9'd71: rdb_spt <= { rdb_spt[23:0], sdc_byte_in_data };
				9'd72, 9'd73, 9'd74, 9'd75: rdb_heads <= { rdb_heads[23:0], sdc_byte_in_data };
				default: ;
			endcase
		end
	end

	// task file writes
	if (wr_end && cs0 && cmd_ok && a != 3'd0 && a != 3'd7) begin
		case (a)
			3'd2: r_count <= din[7:0];
			3'd3: r_sector <= din[7:0];
			3'd4: r_cyl_lo <= din[7:0];
			3'd5: r_cyl_hi <= din[7:0];
			3'd6: r_head <= din[7:0];
			default: ; // features
		endcase
	end
	if (wr_end && cs1 && a == 3'd6) begin
		r_srst <= din[2];
		if (din[2] && !r_srst)
			pend_reset <= 1'b1;
	end
	if (ata_reset)
		pend_reset <= 1'b1;

	if (reset) begin
		state <= ST_IDLE;
		present <= 1'b0;
		geo_ok <= 1'b0;
		mnt <= 1'b0;
		sdc_rd <= 1'b0;
		sdc_wr <= 1'b0;
		sdc_wait <= 1'b0;
		pend_reset <= 1'b1;
	end
	else begin
	// a reset of the bus waits for a request of img_sdc to end; it ends a command, not the
	// examination of a new image (the firmware mounts while the Amiga is held in reset)
	if (pend_reset && !sdc_wait) begin
		pend_reset <= ata_reset || r_srst;
		if (state != ST_GEO_DIV)
			state <= ST_IDLE;
		r_err <= 8'h01;   // diagnostics passed, signature of a disk
		r_count <= 8'h01;
		r_sector <= 8'h01;
		r_cyl_lo <= 8'h00;
		r_cyl_hi <= 8'h00;
		r_head <= 8'h00;
		r_status <= ST_OK;
		cur_heads <= id_heads;
		cur_spt <= id_spt;
	end
	if (!(pend_reset && !sdc_wait) || state == ST_IDLE || state == ST_GEO_DIV) case (state)
		ST_IDLE:
			if (mnt) begin
				// a new image: read its sector 0 for the RDB
				mnt <= 1'b0;
				rdb_ok <= 1'b0;
				sdc_sector <= 32'd0;
				sdc_rd <= 1'b1;
				sdc_wait <= 1'b1;
				geo_rd <= 1'b1;
				state <= ST_GEO;
			end

		ST_GEO:
			if (sdc_done) begin
				sdc_wait <= 1'b0;
				geo_rd <= 1'b0;
				if (rdb_ok && !sdc_error && rdb_cyl[31:16] == 16'd0 && rdb_cyl[15:0] != 16'd0 &&
				    rdb_spt[31:8] == 24'd0 && rdb_spt[7:0] != 8'd0 &&
				    rdb_heads[31:5] == 27'd0 && rdb_heads[4:0] != 5'd0 && rdb_heads[4:0] <= 5'd16) begin
					id_cyl <= rdb_cyl[15:0];
					id_heads <= rdb_heads[4:0];
					id_spt <= rdb_spt[7:0];
					cur_heads <= rdb_heads[4:0];
					cur_spt <= rdb_spt[7:0];
					geo_ok <= 1'b1;
					state <= ST_IDLE;
				end
				else begin
					id_cyl <= 16'd0;
					id_heads <= DEF_HEADS;
					id_spt <= DEF_SPT;
					cur_heads <= DEF_HEADS;
					cur_spt <= DEF_SPT;
					div_rem <= total;
					state <= ST_GEO_DIV;
				end
			end

		ST_GEO_DIV:
			// cylinders = sectors / (heads * spt), by subtraction (at most 65535 steps)
			if (div_rem >= DEF_HEADS * DEF_SPT && id_cyl != 16'hFFFF) begin
				div_rem <= div_rem - DEF_HEADS * DEF_SPT;
				id_cyl <= id_cyl + 16'd1;
			end
			else begin
				geo_ok <= 1'b1;
				state <= ST_IDLE;
			end

		ST_IDENT: begin
			we <= 1'b1;
			wa <= ptr;
			wd <= ident(ptr, id_cyl, id_heads, id_spt, cur_heads, cur_spt, cap);
			ptr <= ptr + 8'd1;
			if (ptr == 8'd255) begin
				r_status <= ST_DRQ;
				state <= ST_DRQIN;
			end
		end

		ST_CALC1: begin
			chs_t <= id_mul1(r_cyl_hi, r_cyl_lo, cur_heads, r_head[3:0]);
			state <= ST_CALC2;
		end

		ST_CALC2: begin
			if (lba_mode)
				lba <= { 4'd0, r_head[3:0], r_cyl_hi, r_cyl_lo, r_sector };
			else
				lba <= chs_t * cur_spt + r_sector - 32'd1;
			state <= ST_CHECK;
		end

		ST_CHECK:
			if (lba >= total || (!lba_mode && (r_sector == 8'd0 || r_sector > cur_spt ||
			                                   { 1'b0, r_head[3:0] } >= cur_heads))) begin
				r_err <= 8'h10; // IDNF
				r_status <= ST_ERR;
				state <= ST_IDLE;
			end
			else if (op == OP_VERIFY) begin
				r_status <= ST_OK;
				state <= ST_IDLE;
			end
			else if (op == OP_WRITE) begin
				ptr <= 8'd0;
				r_status <= ST_DRQ;
				state <= ST_DRQOUT;
			end
			else begin
				sdc_sector <= lba;
				sdc_rd <= 1'b1;
				sdc_wait <= 1'b1;
				state <= ST_FETCH;
			end

		ST_FETCH:
			if (sdc_done) begin
				sdc_wait <= 1'b0;
				ptr <= 8'd0;
				if (sdc_error) begin
					r_err <= 8'h40; // UNC
					r_status <= ST_ERR;
					state <= ST_IDLE;
				end
				else begin
					r_status <= ST_DRQ;
					state <= ST_DRQIN;
				end
			end

		ST_DRQIN:
			if (rd_end && cs0 && a == 3'd0 && here) begin
				ptr <= ptr + 8'd1;
				if (ptr == 8'd255) begin
					if (op == OP_IDENT || left == 9'd1) begin
						if (op != OP_IDENT)
							r_count <= r_count - 8'd1;
						r_status <= ST_OK;
						state <= ST_IDLE;
					end
					else begin
						next_sector_regs;
						lba <= lba + 32'd1;
						left <= left - 9'd1;
						r_status <= ST_BSY;
						state <= ST_CHECK;
					end
				end
			end

		ST_DRQOUT:
			if (wr_end && cs0 && a == 3'd0 && here) begin
				we <= 1'b1;
				wa <= ptr;
				wd <= din;
				ptr <= ptr + 8'd1;
				if (ptr == 8'd255) begin
					sdc_sector <= lba;
					sdc_wr <= 1'b1;
					sdc_wait <= 1'b1;
					r_status <= ST_BSY;
					state <= ST_STORE;
				end
			end

		ST_STORE:
			if (sdc_done) begin
				sdc_wait <= 1'b0;
				if (sdc_error) begin
					r_err <= 8'h04; // ABRT
					r_status <= ST_ERR;
					state <= ST_IDLE;
				end
				else if (left == 9'd1) begin
					r_count <= r_count - 8'd1;
					r_status <= ST_OK;
					state <= ST_IDLE;
				end
				else begin
					next_sector_regs;
					lba <= lba + 32'd1;
					left <= left - 9'd1;
					state <= ST_CHECK;
				end
			end

		default: state <= ST_IDLE;
	endcase
	end

	// a command (after the state machine: it takes over from a block the host left)
	if (!reset && !(pend_reset && !sdc_wait) && wr_end && cs0 && a == 3'd7 && here && cmd_ok) begin
		r_err <= 8'h00;
		left <= (r_count == 8'd0) ? 9'd256 : { 1'b0, r_count };
		casez (din[7:0])
			8'hEC: begin // IDENTIFY DEVICE
				op <= OP_IDENT;
				ptr <= 8'd0;
				r_status <= ST_BSY;
				state <= ST_IDENT;
			end
			8'h20, 8'h21, 8'hC4: begin // READ SECTORS, READ MULTIPLE
				op <= OP_READ;
				r_status <= ST_BSY;
				state <= ST_CALC1;
			end
			8'h30, 8'h31, 8'hC5: begin // WRITE SECTORS, WRITE MULTIPLE
				op <= OP_WRITE;
				r_status <= ST_BSY;
				state <= ST_CALC1;
			end
			8'h40, 8'h41: begin // READ VERIFY SECTORS
				op <= OP_VERIFY;
				r_status <= ST_BSY;
				state <= ST_CALC1;
			end
			8'h91: begin // INITIALIZE DEVICE PARAMETERS
				cur_spt <= r_count;
				cur_heads <= { 1'b0, r_head[3:0] } + 5'd1;
				r_status <= ST_OK;
				state <= ST_IDLE;
			end
			8'hC6: begin // SET MULTIPLE MODE: blocks of one sector only
				r_status <= (r_count[7:1] == 7'd0) ? ST_OK : ST_ERR;
				r_err <= (r_count[7:1] == 7'd0) ? 8'h00 : 8'h04;
				state <= ST_IDLE;
			end
			8'h1?, 8'h7?, 8'hE0, 8'hE1, 8'hE2, 8'hE3, 8'hE6, 8'hE7, 8'hEA, 8'hEF: begin
				// recalibrate, seek, power modes, flush cache, set features: nothing to do
				r_status <= ST_OK;
				state <= ST_IDLE;
			end
			8'hE5: begin // CHECK POWER MODE: active
				r_count <= 8'hFF;
				r_status <= ST_OK;
				state <= ST_IDLE;
			end
			8'h90: begin // EXECUTE DEVICE DIAGNOSTIC: passed
				r_err <= 8'h01;
				r_status <= ST_OK;
				state <= ST_IDLE;
			end
			default: begin
				r_err <= 8'h04; // ABRT
				r_status <= ST_ERR;
				state <= ST_IDLE;
			end
		endcase
	end
end

endmodule
