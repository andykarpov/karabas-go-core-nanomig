`timescale 1ns / 1ps
`default_nettype wire

/*
 img_sdc.v

 The file mounter of the mcu link (mcu.vhd IMG_* ports, karabas-go-firmware docs/protocol.md)
 as the sd card sector interface of NanoMig (sdc_*). Slot n of the mcu is sdc index n:
 0-3 floppy drives DF0-DF3, 4-5 IDE drives.

 - mount: IMG_MOUNTED[n] with IMG_SIZE gives sdc_img_mounted[n] with sdc_img_size (0 = no image);
 - one request at a time, the lowest index first: sdc_busy goes up when it is taken (the
   requester drops sdc_rd / sdc_wr then), and down with the sdc_done pulse at its end;
 - the request goes to the mcu as reply frames: IMG_LBA 0..3, IMG_SEC (slot, 1 read / 2 write);
 - read: the sector bytes of the mcu go into a buffer here; only a checked sector (below) is passed
   on as sdc_byte_in_strobe / addr / data, in ~50 us. The floppy takes the first byte 511 as the
   end of the sector and builds its MFM checksum from what it got: the bytes of a failed try
   would reach the Amiga as a good sector;
 - write: the sector is first copied from sdc_byte_out_data (OUT_LATENCY clocks after
   sdc_byte_addr) into a buffer here, in ~70 us: the floppy refills its only sector buffer with
   the next sector of the track as soon as sdc_busy is up, long before the mcu has taken the
   sector. Then the request goes out and the buffer is queued as IMG_BUF_BANK (at offset 0 and
   256) + IMG_BUF_DATA frames;
 - the end is the IMG_SEC answer of the mcu. Without an answer in TIMEOUT the whole request is
   sent again (RETRIES times; a reply frame of the fpga can get lost on the link), then the request
   ends without data (a firmware without the file mounter). Each retry is counted in
   CMD_DEBUG_ADDRESS (the firmware logs it);
 - the link can lose a frame now and then, so a request is checked end to end and sent again
   (RETRIES times) when it fails: a read needs all 512 bytes and the 16-bit sum the mcu sends
   before its result (IMG_LBA 0/1, mcu -> fpga); a write sends the sum of its bytes after them
   (IMG_BUF_BANK 10/11) and the mcu answers an error if it got less or a different sum. A read
   that still fails gives the requester 512 zero bytes, so it does not wait forever;
 - debug: after a read, the 16-bit sum of the received bytes goes to the mcu as CMD_DEBUG_DATA.
*/

module img_sdc #(
	parameter OUT_LATENCY = 3,      // clocks from sdc_byte_addr to sdc_byte_out_data (floppy: 2)
	parameter TIMEOUT = 24'd5600000, // ~200 ms at 28 MHz (the mcu answers in 5-15 ms, its main loop can stall ~40 ms)
	parameter RETRIES = 2'd3
) (
	input wire clk,
	input wire reset,

	// mcu.vhd
	input wire [7:0] img_mounted,
	input wire [63:0] img_size,
	input wire img_data_wr,
	input wire [8:0] img_data_addr,
	input wire [7:0] img_data,
	input wire img_result_wr,
	input wire [7:0] img_result,
	input wire [15:0] img_sum,
	output reg img_q_wr = 1'b0,
	output reg [23:0] img_q_di = 24'd0,
	input wire img_q_ack,
	input wire [15:0] dbg_rx_frames,
	input wire [15:0] dbg_pops,
	input wire [15:0] dbg_cs_falls,
	input wire [15:0] dbg_cut,
	input wire [15:0] dbg_burst_pops,

	// nanomig
	output reg [7:0] sdc_img_mounted = 8'd0,
	output reg [63:0] sdc_img_size = 64'd0,
	input wire [7:0] sdc_rd,
	input wire [7:0] sdc_wr,
	input wire [31:0] sdc_sector,
	output reg sdc_busy = 1'b0,
	output reg sdc_done = 1'b0,
	output reg sdc_byte_in_strobe = 1'b0,
	output reg [8:0] sdc_byte_addr = 9'd0,
	output reg [7:0] sdc_byte_in_data = 8'd0,
	input wire [7:0] sdc_byte_out_data,

	output wire active, // a request is in progress (activity led / osd)
	output wire [7:0] dbg // debug: state, tries
);

localparam CMD_IMG_LBA = 8'h42;
localparam CMD_IMG_SEC = 8'h43;
localparam CMD_IMG_BUF_BANK = 8'h44;
localparam CMD_IMG_BUF_DATA = 8'h45;
localparam CMD_DEBUG_ADDRESS = 8'h30;
localparam CMD_DEBUG_DATA = 8'h31;

localparam S_IDLE = 5'd0;
localparam S_REQ = 5'd1;    // queue IMG_LBA 0..3, IMG_SEC
localparam S_READ = 5'd2;   // sector bytes from the mcu into the buffer, until the result
localparam S_WADDR = 5'd3;  // write: buffer address out
localparam S_WDATA = 5'd4;  // write: queue the byte (and the bank before it)
localparam S_WAIT = 5'd5;   // wait for the result
localparam S_DBG = 5'd6;    // queue the sum of the bytes read
localparam S_CADDR = 5'd7;  // write: copy the sector of the requester, address out
localparam S_CDATA = 5'd8;  // write: copy, wait for the data and store it
localparam S_RETRY = 5'd9;  // queue the retry count, then the request again
localparam S_RETRY2 = 5'd10; // debug: queue the number of frames the mcu.vhd queue took
localparam S_WSUM = 5'd11;   // write: queue the sum of the sector (2 frames)
localparam S_FILL = 5'd12;   // read failed: 512 zero bytes to the requester
localparam CMD_DEBUG_FRAMES = 8'h32;
localparam CMD_DEBUG_RX = 8'h33;    // debug: frames the mcu.vhd spi slave received
localparam CMD_DEBUG_POPS = 8'h34;  // debug: reply words it took from the queue
localparam S_RETRY3 = 5'd13;
localparam S_RETRY4 = 5'd14;
localparam S_OADDR = 5'd15;  // read: the checked sector to the requester, buffer address out
localparam S_ODATA = 5'd16;  // read: wait for the buffer, pass the byte on
localparam S_RETRY5 = 5'd17;
localparam S_RETRY6 = 5'd18;
localparam S_RETRY7 = 5'd19;
localparam CMD_DEBUG_CS_FALLS = 8'h35;   // debug: falls of the mcu chip select (spikes too)
localparam CMD_DEBUG_CUT = 8'h36;        // debug: frames cut short
localparam CMD_DEBUG_BURST_POPS = 8'h37; // debug: reply words taken during a burst

reg [4:0] state = S_IDLE;
reg [2:0] slot = 3'd0;
reg write = 1'b0;
reg [31:0] lba = 32'd0;
reg [2:0] step = 3'd0;
reg [9:0] wpos = 10'd0;
reg [1:0] wlat = 2'd0;
reg bank_sent = 1'b0;
reg [23:0] timeout = 24'd0;
reg [15:0] rd_sum = 16'd0;
reg [9:0] rd_cnt = 10'd0;    // bytes of the sector read
reg [15:0] wr_sum = 16'd0;   // sum of the sector written
reg [1:0] tries = 2'd0;
reg [15:0] retry_count = 16'd0;
reg [15:0] q_count = 16'd0; // debug: frames taken by the mcu.vhd reply queue

// sector buffer of a read or a write (block ram, one write port, synchronous read)
reg [7:0] wbuf [0:511];
reg [8:0] wbuf_ra = 9'd0;
reg [7:0] wbuf_q = 8'd0;
reg wbuf_we = 1'b0;
reg [8:0] wbuf_wa = 9'd0;
reg [7:0] wbuf_wd = 8'd0;
always @(posedge clk) begin
	wbuf_q <= wbuf[wbuf_ra];
	if (wbuf_we)
		wbuf[wbuf_wa] <= wbuf_wd;
end

assign active = sdc_busy;
assign dbg = { 2'b00, tries, state[3:0] };

wire [7:0] req = sdc_rd | sdc_wr;
wire [2:0] req_slot = req[0] ? 3'd0 : req[1] ? 3'd1 : req[2] ? 3'd2 : req[3] ? 3'd3 :
                      req[4] ? 3'd4 : req[5] ? 3'd5 : req[6] ? 3'd6 : 3'd7;

// a queued frame is taken with img_q_ack; the next one is put up after it
wire q_free = !img_q_wr || img_q_ack;

always @(posedge clk) begin
	sdc_img_mounted <= img_mounted;
	if (|img_mounted)
		sdc_img_size <= img_size;

	sdc_done <= 1'b0;
	sdc_byte_in_strobe <= 1'b0;
	wbuf_we <= 1'b0;
	if (img_q_ack) begin
		img_q_wr <= 1'b0;
		q_count <= q_count + 16'd1;
	end

	if (timeout != 0)
		timeout <= timeout - 24'd1;

	if (reset) begin
		state <= S_IDLE;
		sdc_busy <= 1'b0;
		img_q_wr <= 1'b0;
	end
	else case (state)
		S_IDLE:
			if (req != 8'd0) begin
				slot <= req_slot;
				write <= sdc_wr[req_slot];
				lba <= sdc_sector;
				sdc_busy <= 1'b1;
				step <= 3'd0;
				wpos <= 10'd0;
				tries <= 2'd0;
				state <= sdc_wr[req_slot] ? S_CADDR : S_REQ;
			end

		S_CADDR:
			if (wpos == 10'd512)
				state <= S_REQ;
			else begin
				sdc_byte_addr <= wpos[8:0];
				wlat <= OUT_LATENCY - 1;
				state <= S_CDATA;
			end

		S_CDATA:
			if (wlat != 0)
				wlat <= wlat - 2'd1;
			else begin
				wbuf_we <= 1'b1;
				wbuf_wa <= wpos[8:0];
				wbuf_wd <= sdc_byte_out_data;
				wpos <= wpos + 10'd1;
				state <= S_CADDR;
			end

		S_REQ:
			if (q_free) begin
				img_q_wr <= 1'b1;
				if (step < 3'd4)
					img_q_di <= { CMD_IMG_LBA, 6'd0, step[1:0], lba[step[1:0]*8 +: 8] };
				else
					img_q_di <= { CMD_IMG_SEC, 5'd0, slot, write ? 8'd2 : 8'd1 };
				step <= step + 3'd1;
				rd_sum <= 16'd0;
				rd_cnt <= 10'd0;
				wr_sum <= 16'd0;
				if (step == 3'd4) begin
					timeout <= TIMEOUT;
					wpos <= 10'd0;
					bank_sent <= 1'b0;
					state <= write ? S_WADDR : S_READ;
				end
			end

		S_READ: begin
			if (img_data_wr) begin
				wbuf_we <= 1'b1;
				wbuf_wa <= img_data_addr;
				wbuf_wd <= img_data;
				rd_sum <= rd_sum + img_data;
				rd_cnt <= rd_cnt + 10'd1;
			end
			if (img_result_wr && img_result == 8'd1 && rd_cnt == 10'd512 && rd_sum == img_sum) begin
				wpos <= 10'd0;
				state <= S_OADDR;
			end
			else if ((img_result_wr || timeout == 24'd1) && tries == RETRIES) begin
				// no good answer after the retries (a lost frame, no file, past its end): the
				// requester still needs 512 bytes to go on
				wpos <= 10'd0;
				state <= S_FILL;
			end
			else if (img_result_wr || timeout == 24'd1)
				state <= S_RETRY;
		end

		S_OADDR:
			if (wpos == 10'd512) begin
				sdc_busy <= 1'b0;
				sdc_done <= 1'b1;
				state <= S_DBG;
			end
			else begin
				wbuf_ra <= wpos[8:0];
				wlat <= 2'd1; // wbuf_q one clock after wbuf_ra
				state <= S_ODATA;
			end

		S_ODATA:
			if (wlat != 0)
				wlat <= wlat - 2'd1;
			else begin
				sdc_byte_addr <= wpos[8:0];
				sdc_byte_in_data <= wbuf_q;
				sdc_byte_in_strobe <= 1'b1;
				wpos <= wpos + 10'd1;
				state <= S_OADDR;
			end

		S_FILL:
			if (wpos == 10'd512) begin
				sdc_busy <= 1'b0;
				sdc_done <= 1'b1;
				state <= S_DBG;
			end
			else begin
				sdc_byte_addr <= wpos[8:0];
				sdc_byte_in_data <= 8'h00;
				sdc_byte_in_strobe <= 1'b1;
				wpos <= wpos + 10'd1;
			end

		S_RETRY:
			if (q_free) begin
				img_q_wr <= 1'b1;
				img_q_di <= { CMD_DEBUG_ADDRESS, retry_count + 16'd1 };
				retry_count <= retry_count + 16'd1;
				tries <= tries + 2'd1;
				step <= 3'd0;
				state <= S_RETRY2;
			end

		S_RETRY2:
			if (q_free) begin
				img_q_wr <= 1'b1;
				// the frames taken before this one (the ack of the retry count frame is counted)
				img_q_di <= { CMD_DEBUG_FRAMES, q_count + { 15'd0, img_q_ack } };
				state <= S_RETRY3;
			end

		S_RETRY3:
			if (q_free) begin
				img_q_wr <= 1'b1;
				img_q_di <= { CMD_DEBUG_RX, dbg_rx_frames };
				state <= S_RETRY4;
			end

		S_RETRY4:
			if (q_free) begin
				img_q_wr <= 1'b1;
				img_q_di <= { CMD_DEBUG_POPS, dbg_pops };
				state <= S_RETRY5;
			end

		S_RETRY5:
			if (q_free) begin
				img_q_wr <= 1'b1;
				img_q_di <= { CMD_DEBUG_CS_FALLS, dbg_cs_falls };
				state <= S_RETRY6;
			end

		S_RETRY6:
			if (q_free) begin
				img_q_wr <= 1'b1;
				img_q_di <= { CMD_DEBUG_CUT, dbg_cut };
				state <= S_RETRY7;
			end

		S_RETRY7:
			if (q_free) begin
				img_q_wr <= 1'b1;
				img_q_di <= { CMD_DEBUG_BURST_POPS, dbg_burst_pops };
				state <= S_REQ;
			end

		S_DBG:
			if (q_free) begin
				img_q_wr <= 1'b1;
				img_q_di <= { CMD_DEBUG_DATA, rd_sum };
				state <= S_IDLE;
			end

		S_WADDR: begin
			if (wpos == 10'd512) begin
				step <= 3'd0;
				state <= S_WSUM;
			end
			else begin
				wbuf_ra <= wpos[8:0];
				wlat <= 2'd1; // wbuf_q one clock after wbuf_ra
				state <= S_WDATA;
			end
		end

		S_WDATA:
			if (wlat != 0)
				wlat <= wlat - 2'd1;
			else if (q_free) begin
				img_q_wr <= 1'b1;
				if (wpos[7:0] == 8'd0 && !bank_sent) begin
					img_q_di <= { CMD_IMG_BUF_BANK, 8'd0, 7'd0, wpos[8] };
					bank_sent <= 1'b1;
				end
				else begin
					img_q_di <= { CMD_IMG_BUF_DATA, wpos[7:0], wbuf_q };
					wr_sum <= wr_sum + wbuf_q;
					bank_sent <= 1'b0;
					wpos <= wpos + 10'd1;
					state <= S_WADDR;
				end
				timeout <= TIMEOUT;
			end

		S_WSUM:
			if (q_free) begin
				img_q_wr <= 1'b1;
				img_q_di <= { CMD_IMG_BUF_BANK, step[0] ? 8'h11 : 8'h10, step[0] ? wr_sum[15:8] : wr_sum[7:0] };
				step <= step + 3'd1;
				if (step[0]) begin
					timeout <= TIMEOUT;
					state <= S_WAIT;
				end
			end

		S_WAIT:
			if ((img_result_wr && img_result == 8'd1) || ((img_result_wr || timeout == 24'd1) && tries == RETRIES)) begin
				sdc_busy <= 1'b0;
				sdc_done <= 1'b1;
				state <= S_IDLE;
			end
			else if (img_result_wr || timeout == 24'd1)
				state <= S_RETRY; // the sector is still in wbuf

		default: state <= S_IDLE;
	endcase
end

endmodule
