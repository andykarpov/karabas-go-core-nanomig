`timescale 1ns / 1ps

// HDF drive: gayle_cf.v + hdf_ata.v + img_sdc.v, with a model of the mcu firmware on the IMG_*
// ports of img_sdc (the spi link itself is tested by tb_img.v) and a floppy requester on sdc
// index 0 that reads all the time, as paula_floppy does (it takes sdc_busy as the ack of its
// request, the bytes up to 511 as its sector). The sdc glue (per index busy / done / strobe,
// sector and write data by index) is that of the tops.
// - no image: the registers read 0; a mount: BSY until the RDB is read;
// - IDENTIFY with the RDB geometry; CHS reads across a head and a cylinder; LBA reads;
//   writes (CHS and LBA), READ / WRITE MULTIPLE with SET MULTIPLE 1; the task file after a
//   command; an interrupt per sector (gayle_cf);
// - a sector the mcu cannot read: ERR / UNC, no zero data; a write the mcu refuses: ERR / ABRT;
//   an address past the image: IDNF; device 1: no device; unknown command: ABRT;
// - INITIALIZE DEVICE PARAMETERS changes the CHS translation; a software reset;
// - an image without RDB, mounted while the bus is in reset: 16 heads, 63 sectors, cylinders of
//   its size;
// - all the while the floppy gets its own sectors.
// Ends with "tb_hdf: N errors".

module tb_hdf;

reg clk = 1'b0;
always #17.647 clk = ~clk; // 28.33 MHz

reg reset = 1'b1;
reg bus_reset = 1'b0; // the Amiga held in reset (the IDE reset line) while the firmware mounts
integer errors = 0;
task check(input [255:0] what, input [31:0] got, input [31:0] exp);
	if (got !== exp) begin
		errors = errors + 1;
		if (errors < 30) $display("%t ERROR %0s: %0x, expected %0x", $time, what, got, exp);
	end
endtask

// ---------------- gayle_cf + hdf_ata ----------------

reg [23:1] addr = 23'd0;
reg [15:0] data_in = 16'd0;
reg rd = 1'b0, wr = 1'b0;
reg cyc = 1'b0, rd_cyc = 1'b0;
reg sel_ide = 1'b0, sel_gayle = 1'b0;
wire [15:0] data_out;
wire irq, nrdy;

wire [2:0] cf_a;
wire [1:0] cf_cs_n;
wire cf_rd_n, cf_wr_n, cf_reset_n, cf_oe;
wire [15:0] cf_dout, hdf_dout;

gayle_cf gayle(
	.clk(clk), .reset(reset),
	.addr(addr), .data_in(data_in), .data_out(data_out), .rd(rd), .wr(wr),
	.sel_ide(sel_ide), .sel_gayle(sel_gayle), .irq(irq), .nrdy(nrdy), .longword(1'b0),
	.cyc(cyc), .rd_cyc(rd_cyc),
	.cf_a(cf_a), .cf_cs_n(cf_cs_n), .cf_rd_n(cf_rd_n), .cf_wr_n(cf_wr_n), .cf_reset_n(cf_reset_n),
	.cf_dout(cf_dout), .cf_oe(cf_oe), .cf_din(hdf_dout),
	.led()
);

// ---------------- sdc glue of the tops ----------------

wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, hdf_out_data;
reg [7:0] fdc_rd = 8'd0;
reg [31:0] fdc_sector = 32'd0;
wire hdf_rd, hdf_wr;
wire [31:0] hdf_sector;

wire hdf_own = (sdc_slot == 3'd4);
wire fdc_busy = sdc_busy & ~sdc_slot[2];
wire fdc_strobe = sdc_byte_in_strobe & ~sdc_slot[2];
wire [7:0] sdc_rd = { 3'b000, hdf_rd, fdc_rd[3:0] };
wire [7:0] sdc_wr = { 3'b000, hdf_wr, 4'b0000 };
wire [31:0] sdc_sector = (fdc_rd[3:0] != 4'd0) ? fdc_sector : hdf_sector;
wire [7:0] sdc_byte_out_data = hdf_own ? hdf_out_data : 8'h00;

hdf_ata hdf(
	.clk(clk), .reset(reset), .ata_reset(~cf_reset_n | bus_reset),
	.a(cf_a), .cs_n(cf_cs_n), .rd_n(cf_rd_n), .wr_n(cf_wr_n), .din(cf_dout), .dout(hdf_dout),
	.img_mounted(sdc_img_mounted[4]), .img_size(sdc_img_size),
	.sdc_rd(hdf_rd), .sdc_wr(hdf_wr), .sdc_sector(hdf_sector),
	.sdc_busy(sdc_busy & hdf_own), .sdc_done(sdc_done & hdf_own), .sdc_error(sdc_error),
	.sdc_byte_in_strobe(sdc_byte_in_strobe & hdf_own), .sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(hdf_out_data),
	.led()
);

// ---------------- img_sdc + mcu firmware model ----------------

reg [7:0] img_mounted = 8'd0;
reg [63:0] img_size = 64'd0;
reg img_data_wr = 1'b0, img_result_wr = 1'b0;
reg [8:0] img_data_addr = 9'd0;
reg [7:0] img_data = 8'd0, img_result = 8'd0;
reg [15:0] img_sum = 16'd0;
wire img_q_wr;
wire [23:0] img_q_di;
reg img_q_ack = 1'b0;

img_sdc #(.TIMEOUT(24'd20000)) img(
	.clk(clk), .reset(reset),
	.img_mounted(img_mounted), .img_size(img_size),
	.img_data_wr(img_data_wr), .img_data_addr(img_data_addr), .img_data(img_data),
	.img_result_wr(img_result_wr), .img_result(img_result), .img_sum(img_sum),
	.img_q_wr(img_q_wr), .img_q_di(img_q_di), .img_q_ack(img_q_ack),
	.sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size),
	.sdc_rd(sdc_rd), .sdc_wr(sdc_wr), .sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data),
	.active()
);

localparam DISK_SECTORS = 1200;
reg [7:0] disk [0:DISK_SECTORS*512-1];
integer bad_lba = -1;     // the mcu cannot read this sector
reg wprot = 1'b0;         // the mcu refuses writes
integer mcu_reads = 0, mcu_writes = 0;

function [7:0] fdc_byte(input [31:0] lba, input [8:0] i);
	fdc_byte = lba[7:0] ^ i[7:0] ^ 8'hC3 ^ { 7'd0, i[8] };
endfunction

// the frames of img_sdc, taken a few clocks after they are put up
reg [31:0] q_lba = 0;
reg [7:0] q_slot = 0, q_op = 0, q_bank = 0;
reg [7:0] q_buf [0:511];
reg [15:0] q_wsum = 0;
reg q_sec = 0, q_wend = 0;
always @(posedge clk) begin
	img_q_ack <= 1'b0;
	if (img_q_wr && !img_q_ack) begin
		img_q_ack <= 1'b1;
		case (img_q_di[23:16])
			8'h42: q_lba[img_q_di[9:8]*8 +: 8] = img_q_di[7:0];
			8'h43: begin q_slot = img_q_di[15:8]; q_op = img_q_di[7:0]; q_sec = 1; end
			8'h44: if (img_q_di[15:8] == 8'h10) q_wsum[7:0] = img_q_di[7:0];
			       else if (img_q_di[15:8] == 8'h11) begin q_wsum[15:8] = img_q_di[7:0]; q_wend = 1; end
			       else q_bank = img_q_di[7:0];
			8'h45: q_buf[{ q_bank[0], img_q_di[15:8] }] = img_q_di[7:0];
			default: ;
		endcase
	end
end

task mcu_result(input [7:0] r);
	begin
		@(posedge clk); img_result <= r; img_result_wr <= 1'b1;
		@(posedge clk); img_result_wr <= 1'b0;
	end
endtask

// the firmware: a request (IMG_SEC), the sector bytes and their sum, the result
reg [7:0] b;
integer k;
reg [15:0] s;
reg ok;
initial begin : mcu_model
	forever begin
		@(posedge clk);
		if (q_sec && q_op == 8'd1) begin
			q_sec = 0;
			#20000; // the answer of the mcu
			ok = (q_slot == 4) ? (q_lba < DISK_SECTORS && q_lba != bad_lba) : 1'b1;
			if (q_slot == 4) mcu_reads = mcu_reads + 1;
			if (ok) begin
				s = 0;
				for (k = 0; k < 512; k = k + 1) begin
					b = (q_slot == 4) ? disk[q_lba * 512 + k] : fdc_byte(q_lba, k);
					s = s + b;
					@(posedge clk); img_data_wr <= 1'b1; img_data_addr <= k; img_data <= b;
					@(posedge clk); img_data_wr <= 1'b0;
					repeat (2) @(posedge clk);
				end
				img_sum <= s;
				mcu_result(8'd1);
			end
			else
				mcu_result(8'd2);
		end
		else if (q_sec && q_op == 8'd2 && q_wend) begin
			q_sec = 0; q_wend = 0;
			#20000;
			s = 0;
			for (k = 0; k < 512; k = k + 1) s = s + q_buf[k];
			check("write sum", s, q_wsum);
			if (q_slot != 4) begin $display("%t ERROR write to slot %0d", $time, q_slot); errors = errors + 1; end
			if (!wprot && q_lba < DISK_SECTORS) begin
				for (k = 0; k < 512; k = k + 1) disk[q_lba * 512 + k] = q_buf[k];
				mcu_writes = mcu_writes + 1;
				mcu_result(8'd1);
			end
			else
				mcu_result(8'd2);
		end
	end
end

task mount(input [63:0] size);
	begin
		@(posedge clk); img_size <= size; img_mounted <= 8'h10;
		@(posedge clk); img_mounted <= 8'h00;
	end
endtask

// ---------------- floppy requester (paula_floppy) ----------------

reg fdc_on = 1'b0;
integer fdc_state = 0, fdc_count = 0, fdc_sectors = 0;
reg [31:0] fdc_next = 0;
always @(posedge clk) begin
	case (fdc_state)
		0: if (fdc_on && !fdc_busy) begin
			fdc_sector <= fdc_next;
			fdc_rd <= 8'h01;
			fdc_count = 0;
			fdc_state = 1;
		end
		1: if (fdc_busy) begin fdc_rd <= 8'h00; fdc_state = 2; end
		2: if (fdc_strobe) begin
			check("floppy byte", sdc_byte_in_data, fdc_byte(fdc_next, sdc_byte_addr));
			fdc_count = fdc_count + 1;
			if (sdc_byte_addr == 9'd511) begin
				check("floppy bytes", fdc_count, 512);
				fdc_sectors = fdc_sectors + 1;
				fdc_next = (fdc_next + 7) % 1760;
				fdc_state = 0; // the next request in the first clock without sdc_busy (paula state 4)
			end
		end
	endcase
end

// ---------------- cpu bus (minimig_m68k_bridge: rd / wr only after DTACK) ----------------

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
task cpu_wrb(input [23:0] a, input [7:0] v); cpu_access(a, 1'b1, { v, 8'h00 }); endtask
task cpu_ww(input [23:0] a, input [15:0] w); cpu_access(a, 1'b1, w); endtask

localparam TF = 24'hDA2000;
localparam ALT = 24'hDA3018;

integer nirq = 0;
always @(posedge irq) nirq = nirq + 1;

task wait_irq(input integer n);
	integer t;
	begin
		t = 0;
		while (nirq < n && t < 2000000) begin @(posedge clk); t = t + 1; end
		check("interrupts", nirq, n);
	end
endtask

task wait_ready; // alt status until not BSY
	integer t;
	begin
		t = 0;
		cpu_rd(ALT);
		while (rdata[15] && t < 20000) begin cpu_rd(ALT); t = t + 1; end
	end
endtask

task set_chs(input [15:0] c, input [3:0] h, input [7:0] sec, input [7:0] n);
	begin
		cpu_wrb(TF + 24, 8'hA0 | h);
		cpu_wrb(TF + 8, n);
		cpu_wrb(TF + 12, sec);
		cpu_wrb(TF + 16, c[7:0]);
		cpu_wrb(TF + 20, c[15:8]);
	end
endtask

task set_lba(input [27:0] l, input [7:0] n);
	begin
		cpu_wrb(TF + 24, 8'hE0 | l[27:24]);
		cpu_wrb(TF + 8, n);
		cpu_wrb(TF + 12, l[7:0]);
		cpu_wrb(TF + 16, l[15:8]);
		cpu_wrb(TF + 20, l[23:16]);
	end
endtask

// a read command of n sectors from lba: an interrupt and the data per sector
task read_cmd(input [7:0] c, input integer lba, input integer n);
	integer sct, w;
	begin
		nirq = 0;
		cpu_wrb(TF + 28, c);
		for (sct = 0; sct < n; sct = sct + 1) begin
			wait_irq(sct + 1);
			cpu_rd(TF + 28);
			check("status at a read block", rdata[15:8], 8'h58);
			for (w = 0; w < 256; w = w + 1) begin
				cpu_rd(TF);
				check("read data", rdata, { disk[(lba + sct) * 512 + 2*w], disk[(lba + sct) * 512 + 2*w + 1] });
			end
		end
		#30000;
		check("interrupts after the read", nirq, n);
		cpu_rd(TF + 28);
		check("status after the read", rdata[15:8], 8'h50);
	end
endtask

// a write command of n sectors: the first DRQ polled, an interrupt per sector written
task write_cmd(input [7:0] c, input integer n, input [7:0] seed);
	integer sct, w;
	begin
		nirq = 0;
		cpu_wrb(TF + 28, c);
		wait_ready;
		check("DRQ of the write", rdata[15:8], 8'h58);
		for (sct = 0; sct < n; sct = sct + 1) begin
			for (w = 0; w < 256; w = w + 1)
				cpu_ww(TF, { seed + sct[7:0], w[7:0] });
			wait_irq(sct + 1);
			cpu_rd(TF + 28);
			check("status after a written sector", rdata[15:8], (sct == n - 1) ? 8'h50 : 8'h58);
		end
	end
endtask

task check_written(input integer lba, input integer n, input [7:0] seed);
	integer sct, w;
	begin
		for (sct = 0; sct < n; sct = sct + 1)
			for (w = 0; w < 256; w = w + 1) begin
				check("written byte even", disk[(lba + sct) * 512 + 2*w], seed + sct[7:0]);
				check("written byte odd", disk[(lba + sct) * 512 + 2*w + 1], w[7:0]);
			end
	end
endtask

task check_tf(input [7:0] cnt, input [7:0] sec, input [15:0] c, input [7:0] dh);
	begin
		cpu_rd(TF + 8);  check("count", rdata[15:8], cnt);
		cpu_rd(TF + 12); check("sector", rdata[15:8], sec);
		cpu_rd(TF + 16); check("cyl lo", rdata[15:8], c[7:0]);
		cpu_rd(TF + 20); check("cyl hi", rdata[15:8], c[15:8]);
		cpu_rd(TF + 24); check("device / head", rdata[15:8], dh);
	end
endtask

// a hung test stops here
initial begin
	#2000000000;
	$display("%t ERROR watchdog", $time);
	$display("tb_hdf: %0d errors", errors + 1);
	$finish;
end

integer i, w, n0;
reg [15:0] ident [0:255];
initial begin
	// the image: an RDB with 16 cylinders, 2 heads, 32 sectors (1024 sectors) in a file of 1200
	for (i = 0; i < DISK_SECTORS * 512; i = i + 1) disk[i] = (i / 512) * 13 + (i % 512) * 7;
	for (i = 0; i < 512; i = i + 1) disk[i] = 8'h00;
	disk[0] = "R"; disk[1] = "D"; disk[2] = "S"; disk[3] = "K";
	disk[67] = 8'd16; disk[71] = 8'd32; disk[75] = 8'd2;

	repeat (10) @(posedge clk);
	reset <= 1'b0;
	repeat (10) @(posedge clk);
	cpu_ww(24'hDAA000, 16'h8000); // gayle interrupt enable

	// no image: no device
	cpu_rd(TF + 28); check("status without image", rdata[15:8], 8'h00);
	cpu_wrb(TF + 12, 8'h55);
	cpu_rd(TF + 12); check("register without image", rdata[15:8], 8'h00);

	// the floppy reads from now on
	fdc_on = 1'b1;

	// mount: BSY until the RDB is read
	mount(DISK_SECTORS * 512);
	repeat (20) @(posedge clk);
	cpu_rd(ALT); check("status while mounting", rdata[15:8], 8'h80);
	wait_ready;
	check("status after mount", rdata[15:8], 8'h50);

	// identify
	nirq = 0;
	cpu_wrb(TF + 24, 8'hA0);
	cpu_wrb(TF + 28, 8'hEC);
	wait_irq(1);
	cpu_rd(TF + 28); check("identify status", rdata[15:8], 8'h58);
	for (w = 0; w < 256; w = w + 1) begin
		cpu_rd(TF);
		ident[w] = { rdata[7:0], rdata[15:8] }; // the word of the card
	end
	#30000; check("interrupts after identify", nirq, 1);
	cpu_rd(TF + 28); check("status after identify", rdata[15:8], 8'h50);
	check("identify 0", ident[0], 16'h0040);
	check("identify cylinders", ident[1], 16);
	check("identify heads", ident[3], 2);
	check("identify sectors", ident[6], 32);
	check("identify model", ident[27], "KA");
	check("identify multiple", ident[47], 16'h8001);
	check("identify lba", ident[49], 16'h0200);
	check("identify lba sectors", { ident[61], ident[60] }, DISK_SECTORS);

	// CHS read: 3 sectors from c 0 h 1 s 31 (lba 62, 63, 64: over a head and a cylinder)
	set_chs(0, 1, 31, 3);
	read_cmd(8'h20, 62, 3);
	check_tf(8'd0, 8'd1, 16'd1, 8'hA0); // the last sector: c 1 h 0 s 1

	// LBA read: 2 from 100
	set_lba(100, 2);
	read_cmd(8'h20, 100, 2);
	check_tf(8'd0, 8'd101, 16'd0, 8'hE0);

	// set multiple 1, read multiple 2 from 300
	nirq = 0;
	cpu_wrb(TF + 8, 8'd1);
	cpu_wrb(TF + 28, 8'hC6);
	wait_irq(1);
	cpu_rd(TF + 28); check("status after set multiple 1", rdata[15:8], 8'h50);
	set_lba(300, 2);
	read_cmd(8'hC4, 300, 2);

	// set multiple 4: not supported
	nirq = 0;
	cpu_wrb(TF + 8, 8'd4);
	cpu_wrb(TF + 28, 8'hC6);
	wait_irq(1);
	cpu_rd(TF + 28); check("status after set multiple 4", rdata[15:8], 8'h51);
	cpu_rd(TF + 4); check("error after set multiple 4", rdata[15:8], 8'h04);
	nirq = 0; // back to 1 (gayle_cf took the 4 for its blocks)
	cpu_wrb(TF + 8, 8'd1);
	cpu_wrb(TF + 28, 8'hC6);
	wait_irq(1);

	// LBA write: 2 to 500; CHS write: 2 to c 3 h 1 s 32 (lba 3*64 + 32 + 31 = 255, 256)
	n0 = mcu_writes;
	set_lba(500, 2);
	write_cmd(8'h30, 2, 8'h40);
	check_written(500, 2, 8'h40);
	check_tf(8'd0, 8'd245, 16'd1, 8'hE0); // 501 = 0x1F5
	set_chs(3, 1, 32, 2);
	write_cmd(8'hC5, 2, 8'h80);
	check_written(255, 2, 8'h80);
	check_tf(8'd0, 8'd1, 16'd4, 8'hA0); // 256: c 4 h 0 s 1
	check("mcu writes", mcu_writes - n0, 4);
	// read them back
	set_lba(255, 2);
	read_cmd(8'h20, 255, 2);

	// a sector the mcu cannot read: ERR / UNC at its address, no data
	bad_lba = 401;
	set_lba(400, 3);
	nirq = 0;
	cpu_wrb(TF + 28, 8'h20);
	wait_irq(1);
	cpu_rd(TF + 28); check("status at sector 400", rdata[15:8], 8'h58);
	for (w = 0; w < 256; w = w + 1) cpu_rd(TF);
	wait_irq(2);
	cpu_rd(TF + 28); check("status at the bad sector", rdata[15:8], 8'h51);
	cpu_rd(TF + 4); check("error at the bad sector", rdata[15:8], 8'h40);
	check_tf(8'd2, 8'd145, 16'd1, 8'hE0); // 401 = 0x191
	bad_lba = -1;

	// a write the mcu refuses (a read only file): ERR / ABRT
	wprot = 1'b1;
	set_lba(600, 1);
	nirq = 0;
	cpu_wrb(TF + 28, 8'h30);
	wait_ready;
	for (w = 0; w < 256; w = w + 1) cpu_ww(TF, w);
	wait_irq(1);
	cpu_rd(TF + 28); check("status of a refused write", rdata[15:8], 8'h51);
	cpu_rd(TF + 4); check("error of a refused write", rdata[15:8], 8'h04);
	wprot = 1'b0;

	// past the end of the image: IDNF
	set_lba(DISK_SECTORS, 1);
	nirq = 0;
	cpu_wrb(TF + 28, 8'h20);
	wait_irq(1);
	cpu_rd(TF + 28); check("status past the end", rdata[15:8], 8'h51);
	cpu_rd(TF + 4); check("error past the end", rdata[15:8], 8'h10);

	// unknown command: ABRT
	nirq = 0;
	cpu_wrb(TF + 28, 8'hA1);
	wait_irq(1);
	cpu_rd(TF + 28); check("status of an unknown command", rdata[15:8], 8'h51);
	cpu_rd(TF + 4); check("error of an unknown command", rdata[15:8], 8'h04);

	// device 1: no device
	cpu_wrb(TF + 24, 8'hB0);
	cpu_rd(TF + 28); check("status of device 1", rdata[15:8], 8'h00);
	cpu_rd(ALT); check("alt status of device 1", rdata[15:8], 8'h00);
	cpu_wrb(TF + 24, 8'hA0);
	cpu_rd(TF + 28); check("status of device 0 again", rdata[15:8], 8'h51); // the abort before

	// INITIALIZE DEVICE PARAMETERS: 4 heads, 16 sectors; c 2 h 3 s 5 is lba (2*4+3)*16+4 = 180
	nirq = 0;
	cpu_wrb(TF + 8, 8'd16);
	cpu_wrb(TF + 24, 8'hA3);
	cpu_wrb(TF + 28, 8'h91);
	wait_irq(1);
	set_chs(2, 3, 5, 1);
	read_cmd(8'h20, 180, 1);

	// software reset: the signature, the geometry of the image again
	cpu_wrb(ALT, 8'h04);
	cpu_wrb(ALT, 8'h00);
	wait_ready;
	check_tf(8'd1, 8'd1, 16'd0, 8'h00);
	cpu_rd(TF + 4); check("error after reset", rdata[15:8], 8'h01);
	set_chs(0, 1, 31, 1);
	read_cmd(8'h20, 62, 1);

	// an image without an RDB: 16 heads, 63 sectors, 1200 / 1008 = 1 cylinder
	disk[0] = 8'h00;
	mount(64'd0);
	repeat (5) @(posedge clk);
	cpu_rd(TF + 28); check("status after eject", rdata[15:8], 8'h00);
	bus_reset = 1'b1;
	mount(DISK_SECTORS * 512);
	i = 0;
	while (hdf.geo_ok !== 1'b1 && i < 200000) begin @(posedge clk); i = i + 1; end
	check("geometry of a mount during a bus reset", hdf.geo_ok, 1'b1);
	bus_reset = 1'b0;
	wait_ready;
	nirq = 0;
	cpu_wrb(TF + 24, 8'hA0);
	cpu_wrb(TF + 28, 8'hEC);
	wait_irq(1);
	for (w = 0; w < 256; w = w + 1) begin
		cpu_rd(TF);
		ident[w] = { rdata[7:0], rdata[15:8] };
	end
	check("default cylinders", ident[1], 1);
	check("default heads", ident[3], 16);
	check("default sectors", ident[6], 63);
	// c 0 h 15 s 63 is lba 15*63+62 = 1007
	set_chs(0, 15, 63, 1);
	read_cmd(8'h20, 1007, 1);

	fdc_on = 1'b0;
	wait (fdc_state == 0);
	$display("floppy sectors read meanwhile: %0d", fdc_sectors);
	if (fdc_sectors < 20) begin $display("ERROR: the floppy read only %0d sectors", fdc_sectors); errors = errors + 1; end
	$display("tb_hdf: %0d errors", errors);
	$finish;
end

endmodule
