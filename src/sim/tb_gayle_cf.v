`timescale 1ns / 1ps

// gayle_cf.v against a model of an ATA device (CF card in true IDE mode, PIO, no INTRQ line):
// - cpu accesses wait on nrdy and see the registers byte swapped (IDE DD7..0 = cpu D15..8);
// - the PIO timing on the card bus (address setup, DIOR/DIOW width, cycle);
// - the emulated INTRQ: identify, read sectors (an interrupt per sector, none after the last),
//   set multiple + read multiple (an interrupt per block), write sectors (none for the first DRQ,
//   one per sector written), a non-data command, nIEN;
// - a card that changes its status only some time after the last word of a block (LAG_NS: on a
//   read BSY = DRQ = 0 for a while, on a write DRQ stays set): the bridge must not take that for
//   the end of the block; write multiple with a short last block; a sector count of 0 (256);
// - the sector data in both directions, in the byte order of the card.

module tb_gayle_cf;

reg clk = 1'b0;
always #17.647 clk = ~clk; // 28.33 MHz

reg reset = 1'b1;
reg [23:1] addr = 23'd0;
reg [15:0] data_in = 16'd0;
reg rd = 1'b0, wr = 1'b0;
reg cyc = 1'b0, rd_cyc = 1'b0; // the bus cycle of minimig_m68k_bridge, before DTACK
reg sel_ide = 1'b0, sel_gayle = 1'b0;
wire [15:0] data_out;
wire irq, nrdy;

wire [2:0] cf_a;
wire [1:0] cf_cs_n;
wire cf_rd_n, cf_wr_n, cf_reset_n, cf_oe;
wire [15:0] cf_dout;
wire [15:0] cf_bus = cf_oe ? cf_dout : 16'bzzzzzzzzzzzzzzzz;

gayle_cf dut(
	.clk(clk), .reset(reset),
	.addr(addr), .data_in(data_in), .data_out(data_out), .rd(rd), .wr(wr),
	.sel_ide(sel_ide), .sel_gayle(sel_gayle), .irq(irq), .nrdy(nrdy), .longword(1'b0),
	.cyc(cyc), .rd_cyc(rd_cyc),
	.cf_a(cf_a), .cf_cs_n(cf_cs_n), .cf_rd_n(cf_rd_n), .cf_wr_n(cf_wr_n), .cf_reset_n(cf_reset_n),
	.cf_dout(cf_dout), .cf_oe(cf_oe), .cf_din(cf_bus),
	.led()
);

integer errors = 0;
task check(input [255:0] what, input [15:0] got, input [15:0] exp);
	if (got !== exp) begin
		errors = errors + 1;
		$display("%t ERROR %0s: %04x, expected %04x", $time, what, got, exp);
	end
endtask

// ---------------- ATA device model ----------------

localparam BUSY_NS = 3000;
reg [7:0] disk [0:300*512-1];
integer lag = 0; // ns from the last word of a block to the status change
reg [7:0] r_err = 8'h00, r_count = 8'h01, r_sector = 8'h01, r_cyl_lo = 8'h00, r_cyl_hi = 8'h00, r_head = 8'h00;
reg [7:0] r_status = 8'h50;
reg [15:0] rd_word;
reg drive = 1'b0;
integer lba, left, blk, wpos, mult = 1, i;
reg [7:0] cmd;
reg [15:0] ident [0:255];

assign cf_bus = drive ? rd_word : 16'bzzzzzzzzzzzzzzzz;

initial begin
	for (i = 0; i < 300*512; i = i + 1) disk[i] = (i / 512) * 7 + i;
	for (i = 0; i < 256; i = i + 1) ident[i] = 16'h1000 + i;
	ident[0] = 16'h848A; // CF
end

// PIO timing of the host
time t_addr, t_low;
reg [4:0] bus_a_prev;
always @({cf_cs_n, cf_a}) t_addr = $time;
always @(negedge cf_rd_n or negedge cf_wr_n) begin
	t_low = $time;
	if ($time - t_addr < 70) begin errors = errors + 1; $display("%t ERROR address setup %0t ns", $time, $time - t_addr); end
end
always @(posedge cf_rd_n or posedge cf_wr_n)
	if ($time - t_low < 165) begin errors = errors + 1; $display("%t ERROR strobe %0t ns", $time, $time - t_low); end
time t_cyc = 0;
always @(negedge cf_rd_n or negedge cf_wr_n) begin
	if (t_cyc != 0 && $time - t_cyc < 600) begin errors = errors + 1; $display("%t ERROR cycle %0t ns", $time, $time - t_cyc); end
	t_cyc = $time;
end

function [15:0] data_word(input integer pos); // DD7..0 = first byte
	data_word = { disk[pos + 1], disk[pos] };
endfunction

// read: data valid 50 ns after DIOR
always @(negedge cf_rd_n) begin
	#50;
	if (!cf_cs_n[0]) begin
		case (cf_a)
			3'd0: begin
				if (cmd == 8'hEC) rd_word = ident[wpos / 2];
				else rd_word = data_word(lba * 512 + wpos);
			end
			3'd1: rd_word = { 8'h00, r_err };
			3'd2: rd_word = { 8'h00, r_count };
			3'd3: rd_word = { 8'h00, r_sector };
			3'd4: rd_word = { 8'h00, r_cyl_lo };
			3'd5: rd_word = { 8'h00, r_cyl_hi };
			3'd6: rd_word = { 8'h00, r_head };
			3'd7: rd_word = { 8'h00, r_status };
		endcase
	end
	else if (cf_a == 3'd6)
		rd_word = { 8'h00, r_status }; // alternate status
	else
		rd_word = 16'hFFFF;
	drive = 1'b1;
end
always @(posedge cf_rd_n) begin
	#5 drive = 1'b0;
	if (!cf_cs_n[0] && cf_a == 3'd0 && r_status[3]) begin
		wpos = wpos + 2;
		if (wpos == blk * 512) next_block_in;
	end
end

always @(posedge cf_wr_n) begin
	if (!cf_cs_n[0]) begin
		case (cf_a)
			3'd0: if (r_status[3]) begin
				disk[lba * 512 + wpos] = cf_bus[7:0];
				disk[lba * 512 + wpos + 1] = cf_bus[15:8];
				wpos = wpos + 2;
				if (wpos == blk * 512) next_block_out;
			end
			3'd2: r_count = cf_bus[7:0];
			3'd3: r_sector = cf_bus[7:0];
			3'd4: r_cyl_lo = cf_bus[7:0];
			3'd5: r_cyl_hi = cf_bus[7:0];
			3'd6: r_head = cf_bus[7:0];
			3'd7: command(cf_bus[7:0]);
		endcase
	end
end

task command(input [7:0] c);
	begin
		cmd = c;
		lba = r_sector;
		left = (r_count == 0) ? 256 : r_count;
		wpos = 0;
		r_status = 8'h80; // BSY
		case (c)
			8'hEC: begin blk = 1; #(BUSY_NS) r_status = 8'h58; end
			8'h20: begin blk = 1; #(BUSY_NS) r_status = 8'h58; end
			8'hC4: begin blk = (left < mult) ? left : mult; #(BUSY_NS) r_status = 8'h58; end
			8'h30: begin blk = 1; #(BUSY_NS/10) r_status = 8'h58; end // write: DRQ at once
			8'hC5: begin blk = (left < mult) ? left : mult; #(BUSY_NS/10) r_status = 8'h58; end
			8'hC6: begin mult = r_count; #(BUSY_NS) r_status = 8'h50; end
			default: begin #(BUSY_NS) r_status = 8'h50; end
		endcase
	end
endtask

task next_block_in;
	begin
		lba = lba + blk;
		left = left - blk;
		wpos = 0;
		if (left == 0 || cmd == 8'hEC)
			r_status = 8'h50;
		else begin
			blk = (cmd == 8'hC4 && left < mult) ? left : (cmd == 8'hC4 ? mult : 1);
			if (lag != 0) begin r_status = 8'h50; #(lag); end // neither BSY nor DRQ yet
			r_status = 8'hD0; // BSY
			#(BUSY_NS) r_status = 8'h58;
		end
	end
endtask

task next_block_out;
	begin
		lba = lba + blk;
		left = left - blk;
		wpos = 0;
		if (lag != 0) #(lag); // DRQ still set
		r_status = 8'hD0;
		blk = (cmd == 8'hC5 && left < mult) ? left : (cmd == 8'hC5 ? mult : 1);
		#(BUSY_NS) r_status = (left == 0) ? 8'h50 : 8'h58;
	end
endtask

// ---------------- cpu bus ----------------

// as minimig_m68k_bridge: the cycle (address strobe) first, DTACK once nrdy is low, rd / wr only
// after DTACK, the read data taken in that clock; the write data a clock after the cycle start
reg [15:0] rdata;
task cpu_access(input [23:0] a, input w, input [15:0] d);
	begin
		@(posedge clk);
		addr <= a[23:1];
		sel_ide <= (a[23:16] == 8'hDA);
		sel_gayle <= (a[23:12] == 12'hDE1);
		data_in <= 16'hXXXX;
		cyc <= 1'b1;
		rd_cyc <= ~w;
		@(posedge clk);
		data_in <= d;
		repeat (2) @(posedge clk);
		while (nrdy) @(posedge clk);
		rd <= ~w;
		wr <= w;
		@(posedge clk);
		rdata = data_out;
		@(posedge clk);
		rd <= 1'b0;
		wr <= 1'b0;
		cyc <= 1'b0;
		rd_cyc <= 1'b0;
		sel_ide <= 1'b0;
		sel_gayle <= 1'b0;
		repeat (4) @(posedge clk);
	end
endtask
task cpu_rd(input [23:0] a); cpu_access(a, 1'b0, 16'h0000); endtask
task cpu_wrb(input [23:0] a, input [7:0] b); cpu_access(a, 1'b1, { b, 8'h00 }); endtask // byte at an even address
task cpu_ww(input [23:0] a, input [15:0] w); cpu_access(a, 1'b1, w); endtask

localparam TF = 24'hDA2000;
localparam ALT = 24'hDA3018;

integer nirq = 0;
always @(posedge irq) nirq = nirq + 1;

task wait_irq(input integer n);
	integer k;
	begin
		k = 0;
		while (nirq < n && k < 20000) begin @(posedge clk); k = k + 1; end
		check("interrupts", nirq, n);
	end
endtask

task read_sectors(input integer first, input integer n);
	integer s, w;
	begin
		for (s = 0; s < n; s = s + 1) begin
			wait_irq(nirq_base + s + 1);
			cpu_rd(TF + 28);
			check("status (data)", rdata[15:8], 8'h58);
			for (w = 0; w < 256; w = w + 1) begin
				cpu_rd(TF);
				// cpu D15..8 = the first byte of the word on the card
				check("sector data", rdata, { disk[(first + s) * 512 + 2*w], disk[(first + s) * 512 + 2*w + 1] });
			end
		end
	end
endtask
integer nirq_base;

// a hung test (a wait that never ends) stops here
initial begin
	#300000000;
	$display("%t ERROR watchdog", $time);
	$display("tb_gayle_cf: %0d errors", errors + 1);
	$finish;
end

integer w;
initial begin
	repeat (10) @(posedge clk);
	reset <= 1'b0;
	repeat (10) @(posedge clk);

	// gayle id: 1, 1, 0, 1
	cpu_ww(24'hDE1000, 16'h0000);
	cpu_rd(24'hDE1000); check("gayle id 0", rdata[15], 1'b1);
	cpu_rd(24'hDE1000); check("gayle id 1", rdata[15], 1'b1);
	cpu_rd(24'hDE1000); check("gayle id 2", rdata[15], 1'b0);
	cpu_rd(24'hDE1000); check("gayle id 3", rdata[15], 1'b1);
	cpu_ww(24'hDAA000, 16'h8000); // interrupt enable

	// registers, byte swapped
	cpu_wrb(TF + 12, 8'h05);
	cpu_rd(TF + 12); check("sector register", rdata[15:8], 8'h05);
	check("card register", r_sector, 8'h05);

	// identify: one interrupt, 256 words
	nirq = 0;
	cpu_wrb(TF + 24, 8'hE0);
	cpu_wrb(TF + 28, 8'hEC);
	wait_irq(1);
	cpu_rd(TF + 28); check("status", rdata[15:8], 8'h58);
	#100; check("irq after status read", irq, 1'b0);
	for (w = 0; w < 256; w = w + 1) begin
		cpu_rd(TF);
		check("identify", rdata, { ident[w][7:0], ident[w][15:8] });
	end
	#20000; check("interrupts after identify", nirq, 1);
	cpu_rd(TF + 28); check("status after identify", rdata[15:8], 8'h50);

	// read sectors: 3 sectors from 5, an interrupt per sector, none after the last
	nirq = 0; nirq_base = 0;
	cpu_wrb(TF + 8, 8'd3);
	cpu_wrb(TF + 12, 8'd5);
	cpu_wrb(TF + 28, 8'h20);
	read_sectors(5, 3);
	#20000; check("interrupts after read", nirq, 3);

	// set multiple 2 (non-data: one interrupt), read multiple 4 sectors from 10: 2 interrupts
	nirq = 0;
	cpu_wrb(TF + 8, 8'd2);
	cpu_wrb(TF + 28, 8'hC6);
	wait_irq(1);
	cpu_rd(TF + 28); check("status after set multiple", rdata[15:8], 8'h50);
	nirq = 0;
	cpu_wrb(TF + 8, 8'd4);
	cpu_wrb(TF + 12, 8'd10);
	cpu_wrb(TF + 28, 8'hC4);
	wait_irq(1);
	cpu_rd(TF + 28);
	for (w = 0; w < 512; w = w + 1) begin
		cpu_rd(TF);
		check("multiple data", rdata, { disk[10 * 512 + 2*w], disk[10 * 512 + 2*w + 1] });
	end
	wait_irq(2);
	cpu_rd(TF + 28);
	for (w = 0; w < 512; w = w + 1) begin
		cpu_rd(TF);
		check("multiple data", rdata, { disk[12 * 512 + 2*w], disk[12 * 512 + 2*w + 1] });
	end
	#20000; check("interrupts after read multiple", nirq, 2);

	// write sectors: 2 sectors to 20; no interrupt for the first DRQ (polled), one per sector
	nirq = 0;
	cpu_wrb(TF + 8, 8'd2);
	cpu_wrb(TF + 12, 8'd20);
	cpu_wrb(TF + 28, 8'h30);
	cpu_rd(ALT); w = 0;
	while (rdata[15:8] != 8'h58 && w < 100) begin cpu_rd(ALT); w = w + 1; end
	check("DRQ of the write", rdata[15:8], 8'h58);
	#20000; check("interrupts at the first DRQ of a write", nirq, 0);
	for (w = 0; w < 256; w = w + 1) cpu_ww(TF, 16'hA000 + w);
	wait_irq(1);
	cpu_rd(TF + 28); check("status after sector 1", rdata[15:8], 8'h58);
	for (w = 0; w < 256; w = w + 1) cpu_ww(TF, 16'hB000 + w);
	wait_irq(2);
	cpu_rd(TF + 28); check("status after the write", rdata[15:8], 8'h50);
	check("written byte 0", disk[20*512], 8'hA0);  // cpu D15..8 first
	check("written byte 1", disk[20*512+1], 8'h00);
	check("written byte 510", disk[21*512+510], 8'hB0);
	check("written byte 511", disk[21*512+511], 8'hFF);

	// nIEN: no interrupt for a command
	nirq = 0;
	cpu_wrb(ALT, 8'h02);
	cpu_wrb(TF + 28, 8'h91);
	#20000; check("interrupts with nIEN", nirq, 0);
	cpu_wrb(ALT, 8'h00);

	// a card slow to change its status after a block
	lag = 1500;

	// read sectors: 3 from 30
	nirq = 0; nirq_base = 0;
	cpu_wrb(TF + 8, 8'd3);
	cpu_wrb(TF + 12, 8'd30);
	cpu_wrb(TF + 28, 8'h20);
	read_sectors(30, 3);
	#20000; check("interrupts after the slow read", nirq, 3);

	// write sectors: 2 to 40, the interrupt only at the real end
	nirq = 0;
	cpu_wrb(TF + 8, 8'd2);
	cpu_wrb(TF + 12, 8'd40);
	cpu_wrb(TF + 28, 8'h30);
	cpu_rd(ALT); w = 0;
	while (rdata[15:8] != 8'h58 && w < 100) begin cpu_rd(ALT); w = w + 1; end
	for (w = 0; w < 256; w = w + 1) cpu_ww(TF, 16'hC000 + w);
	wait_irq(1);
	cpu_rd(TF + 28); check("status after slow write sector 1", rdata[15:8], 8'h58);
	for (w = 0; w < 256; w = w + 1) cpu_ww(TF, 16'hD000 + w);
	wait_irq(2);
	cpu_rd(TF + 28); check("status at the interrupt after the slow write", rdata[15:8], 8'h50);
	check("slow write byte 511", disk[41*512+511], 8'hFF);
	check("slow write byte 510", disk[41*512+510], 8'hD0);

	// set multiple 4, write multiple 6 sectors to 50: blocks of 4 and 2, an interrupt after each
	nirq = 0;
	cpu_wrb(TF + 8, 8'd4);
	cpu_wrb(TF + 28, 8'hC6);
	wait_irq(1);
	cpu_rd(TF + 28);
	nirq = 0;
	cpu_wrb(TF + 8, 8'd6);
	cpu_wrb(TF + 12, 8'd50);
	cpu_wrb(TF + 28, 8'hC5);
	cpu_rd(ALT); w = 0;
	while (rdata[15:8] != 8'h58 && w < 100) begin cpu_rd(ALT); w = w + 1; end
	for (w = 0; w < 1024; w = w + 1) cpu_ww(TF, w);
	wait_irq(1);
	cpu_rd(TF + 28); check("status after write multiple block 1", rdata[15:8], 8'h58);
	for (w = 1024; w < 1536; w = w + 1) cpu_ww(TF, w);
	wait_irq(2);
	cpu_rd(TF + 28); check("status after write multiple", rdata[15:8], 8'h50);
	check("write multiple last byte", disk[55*512+511], 8'hFF);
	check("write multiple last byte-1", disk[55*512+510], 8'h05);

	// read multiple, sector count 0 = 256 sectors from 1 (multiple 4 -> 64 blocks), slow card
	nirq = 0;
	cpu_wrb(TF + 8, 8'd0);
	cpu_wrb(TF + 12, 8'd1);
	cpu_wrb(TF + 28, 8'hC4);
	for (i = 0; i < 64; i = i + 1) begin
		wait_irq(i + 1);
		cpu_rd(TF + 28);
		check("status in the 256 sector read", rdata[15:8], 8'h58);
		for (w = 0; w < 1024; w = w + 1) begin
			cpu_rd(TF);
			check("256 sector data", rdata, { disk[(1 + 4*i) * 512 + 2*w], disk[(1 + 4*i) * 512 + 2*w + 1] });
		end
	end
	#20000; check("interrupts after the 256 sector read", nirq, 64);
	cpu_rd(TF + 28); check("status after the 256 sector read", rdata[15:8], 8'h50);

	$display("tb_gayle_cf: %0d errors", errors);
	$finish;
end

endmodule
