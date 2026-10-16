//
// gayle_cf.v
//
// karabas: Gayle with the IDE task file on the CF card slot of the Karabas Go boards (a plain
// 16-bit IDE bus: WA[2:0], WCS_N[1:0], WRD_N, WWR_N, WRESET_N, WD[15:0]; no INTRQ, no IORDY).
// The Gayle registers (cs, irq, intena, cfg, id) are those of gayle.v (Jakub Bednarski, Alexey
// Melnikov, GPL v3); the emulated ide.v drives (sector buffers for the MiSTer HPS) are replaced
// by a bridge to the card:
//
// - $DA2000 + 4n (addr[12] = 0) is CS0 register n, $DA3000 + 4n (addr[12] = 1) CS1 register n
//   ($DA3018: alternate status / device control), as on the A600;
// - every cpu access to these registers is one PIO mode 0 cycle on the card (600 ns, no IORDY);
//   the cpu waits for it on nrdy (reads and writes). The access starts with the bus cycle (cyc,
//   rd_cyc of minimig_m68k_bridge), not with rd / wr: those come only after DTACK, and the bridge
//   takes the read data right then;
// - the bus is byte swapped as on the A600: IDE DD7..0 is cpu D15..8. The 8-bit registers are
//   at the even (high byte) addresses, and a sector is in memory in the byte order of the card;
// - INTRQ is emulated, as the slot has no INTRQ line: after a command and after each data block
//   the bridge polls the alternate status register (it does not clear the device interrupt) until
//   BSY is gone, then raises the interrupt as ATA does: a non-data command at its end; a PIO in
//   command (read, identify) at each block with DRQ (not after the last one); a PIO out command
//   (write) after each block written, not for the first DRQ. A block is 256 words, or the count
//   of SET MULTIPLE for READ / WRITE MULTIPLE (the last block can be shorter). The interrupt goes
//   away when the cpu reads the status register or writes a command, and is off while nIEN is set
//   in the device control;
// - the bridge counts the sectors left in a data command (sector count, 0 = 256; LBA48 counts are
//   not supported) and the data words of the block (from the first data access of a block, as the
//   cpu can see DRQ and move data before a poll gets a card cycle), so a poll waits for the state
//   it expects: DRQ while blocks are left, no DRQ after the last one (or ERR). A status read right
//   after a block, before the card has set BSY or cleared DRQ, does not count as its end.
//
// Copyright 2008, 2009 by Jakub Bednarski
// Copyright 2021 Alexey Melnikov
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

module gayle_cf #(
	// PIO mode 0 in clk_sys cycles (28 MHz, 35 ns): address setup >= 70 ns, DIOR/DIOW >= 165 ns,
	// cycle >= 600 ns
	parameter T_SETUP = 3,
	parameter T_PULSE = 6,
	parameter T_CYCLE = 18,
	// the poll after a data block starts this many clocks after its last word (2 us), so a card
	// that is slow to set BSY / clear DRQ is not seen in its state of the block before
	parameter T_SETTLE = 6'd57
) (
	input	        clk,
	input	        reset,

	input	 [23:1] addr,
	input	 [15:0] data_in,
	output [15:0] data_out,
	input         rd,
	input         wr,
	input         sel_ide,			// $DAxxxx
	input         sel_gayle,		// $DExxxx
	output        irq,
	output        nrdy,				// the card access of the cpu is not done
	input         longword,
	input         cyc,              // a cpu bus cycle (address strobe), before DTACK
	input         rd_cyc,           // ... a read cycle

	// CF card slot
	output reg [2:0]  cf_a = 3'd0,
	output reg [1:0]  cf_cs_n = 2'b11,
	output reg        cf_rd_n = 1'b1,
	output reg        cf_wr_n = 1'b1,
	output            cf_reset_n,
	output reg [15:0] cf_dout = 16'd0,
	output reg        cf_oe = 1'b0,
	input      [15:0] cf_din,

	output        led
);

// address decoding
wire sel_gayleid= (sel_gayle && addr[15:12]==4'b0001);  // GAYLEID, $DE1xxx
wire sel_tfr    = (sel_ide   && addr[15:14]==2'b00);    // $DA0xxx, $DA1xxx, $DA2xxx, $DA3xxx
wire sel_cs     = (sel_ide   && addr[15:12]==4'b1000);  // GAYLE_CS_1200,  $DA8xxx
wire sel_intreq = (sel_ide   && addr[15:12]==4'b1001);  // GAYLE_IRQ_1200, $DA9xxx
wire sel_intena = (sel_ide   && addr[15:12]==4'b1010);  // GAYLE_INT_1200, $DAAxxx
wire sel_cfg    = (sel_ide   && addr[15:12]==4'b1011);  // GAYLE_CFG_1200, $DABxxx

reg  old_wr;
wire wr_stb = ~old_wr & wr;
always @(posedge clk) old_wr <= wr;

//===============================================================================================//

reg [1:0] cs;
reg [5:0] cs_mask;

// gayle cs
always @ (posedge clk) begin
	if (reset) begin
		cs_mask <= 0;
		cs      <= 0;
	end else if (wr_stb && sel_cs) begin
		cs_mask <= data_in[15:10];
		cs      <= data_in[9:8];
	end
end

// gayle cfg
reg [3:0] cfg;
always @ (posedge clk) begin
	if (reset) cfg <= 0;
	if (wr_stb && sel_cfg) cfg <= data_in[15:12];
end

// gayle id register: reads 1->1->0->1 on MSB
reg [1:0] gayleid_cnt;	// sequence counter
reg old_rd_id;
always @(posedge clk) begin
	old_rd_id <= rd & sel_gayleid;

	if (wr_stb & sel_gayleid)            gayleid_cnt <= 0; // a write resets sequence counter
	if (old_rd_id & ~(rd & sel_gayleid)) gayleid_cnt <= gayleid_cnt + 1'd1;
end

// IDE interrupt enable register
reg intena;
always @(posedge clk) begin
	if (reset) intena <= 0;
	else if (sel_intena && wr_stb) intena <= data_in[15];
end

//===============================================================================================//
// CF card bridge

assign cf_reset_n = ~reset;

localparam REG_DATA = 3'd0;
localparam REG_COUNT = 3'd2;
localparam REG_STATUS = 3'd7; // CS0: status (read) / command (write); CS1: -
localparam REG_ALT = 3'd6;    // CS1: alternate status (read) / device control (write)

localparam CL_NODATA = 2'd0;
localparam CL_IN = 2'd1;
localparam CL_OUT = 2'd2;

reg        busy = 1'b0;       // a card cycle is running
reg [4:0]  t = 5'd0;          // clock of the card cycle
reg        cyc_cpu = 1'b0;    // the cycle is the access of the cpu (else a poll)
reg        cyc_rd = 1'b0;
reg        cpu_done = 1'b0;   // the access of the cpu is done, until rd / wr goes away
reg [15:0] rd_data = 16'd0;   // card data of the cpu read, cpu byte order

reg        poll = 1'b0;       // waiting for BSY to go away
reg        first_poll = 1'b0; // the poll after the command (not after a data block)
reg [5:0]  settle = 6'd0;     // clocks until the poll after a block starts
reg [1:0]  cls = CL_NODATA;   // class of the running command
reg [7:0]  multiple = 8'd1;   // sectors per block of READ / WRITE MULTIPLE (SET MULTIPLE)
reg [7:0]  count = 8'd0;      // last sector count written
reg [7:0]  blk_sec = 8'd1;    // sectors per block of the running command
reg [8:0]  sec_left = 9'd0;   // sectors of the running command whose block has not started
reg [15:0] words = 16'd0;     // data words left in the block
reg        nien = 1'b0;       // device control nIEN
reg        intrq = 1'b0;      // emulated INTRQ of the card

wire cpu_acc = sel_tfr && cyc && !cpu_done;

// poll: the state the bridge waits for (BSY gone; DRQ while sectors are left, else no DRQ, or ERR)
wire       more = (cls != CL_NODATA) && (sec_left != 9'd0);
wire       poll_end = !cf_din[7] && (cls == CL_NODATA || cf_din[0] || cf_din[3] == more);
wire [7:0] blk_now = (sec_left < { 1'b0, blk_sec }) ? sec_left[7:0] : blk_sec; // sectors of the next block
assign nrdy = cpu_acc;

// command class from its opcode
function [1:0] cmd_class(input [7:0] c);
	casez (c)
		8'h2?, 8'hC4, 8'hE4, 8'hEC: cmd_class = CL_IN;  // read sectors (dma 0xC8 not here), read multiple, read buffer, identify
		8'h3?, 8'hC5, 8'hE8:        cmd_class = CL_OUT; // write sectors, write multiple, write buffer
		default:                    cmd_class = CL_NODATA;
	endcase
endfunction

always @(posedge clk) begin
	if (!(sel_tfr && cyc))
		cpu_done <= 1'b0;
	if (settle != 6'd0)
		settle <= settle - 6'd1;

	if (reset) begin
		busy <= 1'b0;
		cf_cs_n <= 2'b11;
		cf_rd_n <= 1'b1;
		cf_wr_n <= 1'b1;
		cf_oe <= 1'b0;
		poll <= 1'b0;
		intrq <= 1'b0;
		nien <= 1'b0;
		multiple <= 8'd1;
		words <= 16'd0;
	end
	else if (!busy) begin
		// a new cycle: the cpu first, then a poll
		t <= 5'd0;
		if (cpu_acc) begin
			busy <= 1'b1;
			cyc_cpu <= 1'b1;
			cyc_rd <= rd_cyc;
			cf_a <= addr[4:2];
			cf_cs_n <= addr[12] ? 2'b01 : 2'b10;
			cf_dout <= { data_in[7:0], data_in[15:8] };
		end
		else if (poll && settle == 6'd0) begin
			busy <= 1'b1;
			cyc_cpu <= 1'b0;
			cyc_rd <= 1'b1;
			cf_a <= REG_ALT;
			cf_cs_n <= 2'b01;
		end
	end
	else begin
		t <= t + 5'd1;
		if (t == T_SETUP - 1) begin
			if (cyc_cpu)
				cf_dout <= { data_in[7:0], data_in[15:8] }; // write data of the cpu, valid by now
			cf_rd_n <= ~cyc_rd;
			cf_wr_n <= cyc_rd;
			cf_oe <= ~cyc_rd;
		end
		if (t == T_SETUP + T_PULSE - 1) begin
			cf_rd_n <= 1'b1;
			cf_wr_n <= 1'b1;
			if (cyc_cpu)
				rd_data <= { cf_din[7:0], cf_din[15:8] };

			if (cyc_cpu) begin
				// task file bookkeeping for the emulated INTRQ
				if (!cf_cs_n[0]) begin // CS0
					if (cf_a == REG_STATUS) begin
						intrq <= 1'b0; // status read / command write
						if (!cyc_rd) begin
							cls <= cmd_class(cf_dout[7:0]);
							blk_sec <= (cf_dout[7:0] == 8'hC4 || cf_dout[7:0] == 8'hC5) ? multiple : 8'd1;
							first_poll <= 1'b1;
							words <= 16'd0;
							if (cf_dout[7:0] == 8'hEC || cf_dout[7:0] == 8'hE4 || cf_dout[7:0] == 8'hE8)
								sec_left <= 9'd1; // identify, read / write buffer: one sector
							else
								sec_left <= (count == 8'd0) ? 9'd256 : { 1'b0, count };
							poll <= 1'b1;
							if (cf_dout[7:0] == 8'hC6) // SET MULTIPLE
								multiple <= (count == 8'd0) ? 8'd1 : count;
						end
					end
					else if (cf_a == REG_COUNT && !cyc_rd)
						count <= cf_dout[7:0];
					else if (cf_a == REG_DATA && words != 16'd0) begin
						// the last word of a block: wait for the next block / the end
						if (words == 16'd1) begin
							poll <= 1'b1;
							settle <= T_SETTLE;
							first_poll <= 1'b0;
						end
						words <= words - 16'd1;
					end
					else if (cf_a == REG_DATA && more) begin
						// the first word of a block (counted here, not by the poll: the cpu can
						// see DRQ and move data before a poll gets a card cycle)
						words <= { blk_now, 8'd0 } - 16'd1;
						sec_left <= sec_left - blk_now;
					end
				end
				else if (cf_a == REG_ALT && !cyc_rd) begin // device control
					nien <= cf_dout[1];
					if (cf_dout[2]) begin // software reset
						poll <= 1'b0;
						intrq <= 1'b0;
					end
				end
			end
			else if (poll_end) begin
				// poll: BSY is gone and the card is in the state expected
				poll <= 1'b0;
				first_poll <= 1'b0;
				// in: each block with DRQ, or the end (an error) of the command without data;
				// out: each block written, or the end of the command without DRQ (an error)
				case (cls)
					CL_IN:   intrq <= cf_din[3] | first_poll | cf_din[0];
					CL_OUT:  intrq <= ~first_poll | ~cf_din[3];
					default: intrq <= 1'b1;
				endcase
			end
		end
		if (t == T_SETUP + T_PULSE) begin
			cf_oe <= 1'b0;
			cf_cs_n <= 2'b11;
			if (cyc_cpu)
				cpu_done <= 1'b1;
		end
		if (t == T_CYCLE - 1)
			busy <= 1'b0;
	end
end

assign led = busy & cyc_cpu;
assign irq = intrq & ~nien & intena;

wire intreq = intrq & ~nien;
wire gayleid = ~gayleid_cnt[1] | gayleid_cnt[0];

//data_out multiplexer
assign data_out = (sel_tfr     & rd ? rd_data                                           : 16'h0000)
                | (sel_cs      & rd ? {(cs_mask[5] || intreq), cs_mask[4:0], cs, 8'h0}  : 16'h0000)
                | (sel_intreq  & rd ? {intreq, 15'b000_0000_0000_0000}                  : 16'h0000)
                | (sel_intena  & rd ? {intena, 15'b000_0000_0000_0000}                  : 16'h0000)
                | (sel_gayleid & rd ? {gayleid,15'b000_0000_0000_0000}                  : 16'h0000)
                | (sel_cfg     & rd ? {cfg,        12'b0000_0000_0000}                  : 16'h0000);

endmodule
