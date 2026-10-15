`timescale 1ns / 1ps

// Disk DMA through the whole Mini G top: a 68000 program in place of the Kickstart code at
// $FC00D2 (in the SRAM model) switches DF0 on and reads 600 words of track 0 by disk DMA into
// chip RAM at $10000, then writes COLOR00 = $F00. A model of the mcu firmware mounts the ADF in
// slot 0 and serves the sector requests (classic frames). The MFM words in the SRAM model are
// decoded and compared with the ADF. Ends with "tb_disk: N errors".

module tb_disk;

reg clk50 = 1'b0;
always #10 clk50 = ~clk50;

// ---------------- SRAM model: 10 ns async read, write on the rising edge of MWR_N ----------------

wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N, MRD_N;

reg [7:0] sram_hi [0:2097151]; // MD[15:8], MWR_N[1], MRD_N[1]
reg [7:0] sram_lo [0:2097151]; // MD[7:0],  MWR_N[0], MRD_N[0]

assign #10 MD[15:8] = (!MRD_N[1] && MWR_N[1]) ? sram_hi[MA] : 8'bzzzzzzzz;
assign #10 MD[7:0]  = (!MRD_N[0] && MWR_N[0]) ? sram_lo[MA] : 8'bzzzzzzzz;

always @(posedge MWR_N[1]) sram_hi[MA] <= MD[15:8];
always @(posedge MWR_N[0]) sram_lo[MA] <= MD[7:0];

integer i;
initial begin
	for (i = 0; i < 2097152; i = i + 1) begin
		sram_hi[i] = 8'h00;
		sram_lo[i] = 8'h00;
	end
	$readmemh("kick_hi.hex", sram_hi, 21'h1C0000, 21'h1FFFFF);
	$readmemh("kick_lo.hex", sram_lo, 21'h1C0000, 21'h1FFFFF);
	// the test program at $FC00D2 (the reset pc), in both 256 KB halves
	sram_hi[21'h1C0069] = 8'h41; sram_lo[21'h1C0069] = 8'hF9;
	sram_hi[21'h1C006A] = 8'h00; sram_lo[21'h1C006A] = 8'hDF;
	sram_hi[21'h1C006B] = 8'hF0; sram_lo[21'h1C006B] = 8'h00;
	sram_hi[21'h1C006C] = 8'h31; sram_lo[21'h1C006C] = 8'h7C;
	sram_hi[21'h1C006D] = 8'h7F; sram_lo[21'h1C006D] = 8'hFF;
	sram_hi[21'h1C006E] = 8'h00; sram_lo[21'h1C006E] = 8'h9A;
	sram_hi[21'h1C006F] = 8'h31; sram_lo[21'h1C006F] = 8'h7C;
	sram_hi[21'h1C0070] = 8'h7F; sram_lo[21'h1C0070] = 8'hFF;
	sram_hi[21'h1C0071] = 8'h00; sram_lo[21'h1C0071] = 8'h96;
	sram_hi[21'h1C0072] = 8'h31; sram_lo[21'h1C0072] = 8'h7C;
	sram_hi[21'h1C0073] = 8'h7F; sram_lo[21'h1C0073] = 8'hFF;
	sram_hi[21'h1C0074] = 8'h00; sram_lo[21'h1C0074] = 8'h9C;
	sram_hi[21'h1C0075] = 8'h13; sram_lo[21'h1C0075] = 8'hFC;
	sram_hi[21'h1C0076] = 8'h00; sram_lo[21'h1C0076] = 8'hFF;
	sram_hi[21'h1C0077] = 8'h00; sram_lo[21'h1C0077] = 8'hBF;
	sram_hi[21'h1C0078] = 8'hD3; sram_lo[21'h1C0078] = 8'h00;
	sram_hi[21'h1C0079] = 8'h13; sram_lo[21'h1C0079] = 8'hFC;
	sram_hi[21'h1C007A] = 8'h00; sram_lo[21'h1C007A] = 8'h7F;
	sram_hi[21'h1C007B] = 8'h00; sram_lo[21'h1C007B] = 8'hBF;
	sram_hi[21'h1C007C] = 8'hD1; sram_lo[21'h1C007C] = 8'h00;
	sram_hi[21'h1C007D] = 8'h13; sram_lo[21'h1C007D] = 8'hFC;
	sram_hi[21'h1C007E] = 8'h00; sram_lo[21'h1C007E] = 8'h77;
	sram_hi[21'h1C007F] = 8'h00; sram_lo[21'h1C007F] = 8'hBF;
	sram_hi[21'h1C0080] = 8'hD1; sram_lo[21'h1C0080] = 8'h00;
	sram_hi[21'h1C0081] = 8'h21; sram_lo[21'h1C0081] = 8'h7C;
	sram_hi[21'h1C0082] = 8'h00; sram_lo[21'h1C0082] = 8'h01;
	sram_hi[21'h1C0083] = 8'h00; sram_lo[21'h1C0083] = 8'h00;
	sram_hi[21'h1C0084] = 8'h00; sram_lo[21'h1C0084] = 8'h20;
	sram_hi[21'h1C0085] = 8'h31; sram_lo[21'h1C0085] = 8'h7C;
	sram_hi[21'h1C0086] = 8'h44; sram_lo[21'h1C0086] = 8'h89;
	sram_hi[21'h1C0087] = 8'h00; sram_lo[21'h1C0087] = 8'h7E;
	sram_hi[21'h1C0088] = 8'h31; sram_lo[21'h1C0088] = 8'h7C;
	sram_hi[21'h1C0089] = 8'h95; sram_lo[21'h1C0089] = 8'h00;
	sram_hi[21'h1C008A] = 8'h00; sram_lo[21'h1C008A] = 8'h9E;
	sram_hi[21'h1C008B] = 8'h31; sram_lo[21'h1C008B] = 8'h7C;
	sram_hi[21'h1C008C] = 8'h82; sram_lo[21'h1C008C] = 8'h10;
	sram_hi[21'h1C008D] = 8'h00; sram_lo[21'h1C008D] = 8'h96;
	sram_hi[21'h1C008E] = 8'h31; sram_lo[21'h1C008E] = 8'h7C;
	sram_hi[21'h1C008F] = 8'h40; sram_lo[21'h1C008F] = 8'h00;
	sram_hi[21'h1C0090] = 8'h00; sram_lo[21'h1C0090] = 8'h24;
	sram_hi[21'h1C0091] = 8'h31; sram_lo[21'h1C0091] = 8'h7C;
	sram_hi[21'h1C0092] = 8'h82; sram_lo[21'h1C0092] = 8'h58;
	sram_hi[21'h1C0093] = 8'h00; sram_lo[21'h1C0093] = 8'h24;
	sram_hi[21'h1C0094] = 8'h31; sram_lo[21'h1C0094] = 8'h7C;
	sram_hi[21'h1C0095] = 8'h82; sram_lo[21'h1C0095] = 8'h58;
	sram_hi[21'h1C0096] = 8'h00; sram_lo[21'h1C0096] = 8'h24;
	sram_hi[21'h1C0097] = 8'h30; sram_lo[21'h1C0097] = 8'h28;
	sram_hi[21'h1C0098] = 8'h00; sram_lo[21'h1C0098] = 8'h1E;
	sram_hi[21'h1C0099] = 8'h08; sram_lo[21'h1C0099] = 8'h00;
	sram_hi[21'h1C009A] = 8'h00; sram_lo[21'h1C009A] = 8'h01;
	sram_hi[21'h1C009B] = 8'h67; sram_lo[21'h1C009B] = 8'hF6;
	sram_hi[21'h1C009C] = 8'h31; sram_lo[21'h1C009C] = 8'h7C;
	sram_hi[21'h1C009D] = 8'h0F; sram_lo[21'h1C009D] = 8'h00;
	sram_hi[21'h1C009E] = 8'h01; sram_lo[21'h1C009E] = 8'h80;
	sram_hi[21'h1C009F] = 8'h60; sram_lo[21'h1C009F] = 8'hFE;
	sram_hi[21'h1E0069] = 8'h41; sram_lo[21'h1E0069] = 8'hF9;
	sram_hi[21'h1E006A] = 8'h00; sram_lo[21'h1E006A] = 8'hDF;
	sram_hi[21'h1E006B] = 8'hF0; sram_lo[21'h1E006B] = 8'h00;
	sram_hi[21'h1E006C] = 8'h31; sram_lo[21'h1E006C] = 8'h7C;
	sram_hi[21'h1E006D] = 8'h7F; sram_lo[21'h1E006D] = 8'hFF;
	sram_hi[21'h1E006E] = 8'h00; sram_lo[21'h1E006E] = 8'h9A;
	sram_hi[21'h1E006F] = 8'h31; sram_lo[21'h1E006F] = 8'h7C;
	sram_hi[21'h1E0070] = 8'h7F; sram_lo[21'h1E0070] = 8'hFF;
	sram_hi[21'h1E0071] = 8'h00; sram_lo[21'h1E0071] = 8'h96;
	sram_hi[21'h1E0072] = 8'h31; sram_lo[21'h1E0072] = 8'h7C;
	sram_hi[21'h1E0073] = 8'h7F; sram_lo[21'h1E0073] = 8'hFF;
	sram_hi[21'h1E0074] = 8'h00; sram_lo[21'h1E0074] = 8'h9C;
	sram_hi[21'h1E0075] = 8'h13; sram_lo[21'h1E0075] = 8'hFC;
	sram_hi[21'h1E0076] = 8'h00; sram_lo[21'h1E0076] = 8'hFF;
	sram_hi[21'h1E0077] = 8'h00; sram_lo[21'h1E0077] = 8'hBF;
	sram_hi[21'h1E0078] = 8'hD3; sram_lo[21'h1E0078] = 8'h00;
	sram_hi[21'h1E0079] = 8'h13; sram_lo[21'h1E0079] = 8'hFC;
	sram_hi[21'h1E007A] = 8'h00; sram_lo[21'h1E007A] = 8'h7F;
	sram_hi[21'h1E007B] = 8'h00; sram_lo[21'h1E007B] = 8'hBF;
	sram_hi[21'h1E007C] = 8'hD1; sram_lo[21'h1E007C] = 8'h00;
	sram_hi[21'h1E007D] = 8'h13; sram_lo[21'h1E007D] = 8'hFC;
	sram_hi[21'h1E007E] = 8'h00; sram_lo[21'h1E007E] = 8'h77;
	sram_hi[21'h1E007F] = 8'h00; sram_lo[21'h1E007F] = 8'hBF;
	sram_hi[21'h1E0080] = 8'hD1; sram_lo[21'h1E0080] = 8'h00;
	sram_hi[21'h1E0081] = 8'h21; sram_lo[21'h1E0081] = 8'h7C;
	sram_hi[21'h1E0082] = 8'h00; sram_lo[21'h1E0082] = 8'h01;
	sram_hi[21'h1E0083] = 8'h00; sram_lo[21'h1E0083] = 8'h00;
	sram_hi[21'h1E0084] = 8'h00; sram_lo[21'h1E0084] = 8'h20;
	sram_hi[21'h1E0085] = 8'h31; sram_lo[21'h1E0085] = 8'h7C;
	sram_hi[21'h1E0086] = 8'h44; sram_lo[21'h1E0086] = 8'h89;
	sram_hi[21'h1E0087] = 8'h00; sram_lo[21'h1E0087] = 8'h7E;
	sram_hi[21'h1E0088] = 8'h31; sram_lo[21'h1E0088] = 8'h7C;
	sram_hi[21'h1E0089] = 8'h95; sram_lo[21'h1E0089] = 8'h00;
	sram_hi[21'h1E008A] = 8'h00; sram_lo[21'h1E008A] = 8'h9E;
	sram_hi[21'h1E008B] = 8'h31; sram_lo[21'h1E008B] = 8'h7C;
	sram_hi[21'h1E008C] = 8'h82; sram_lo[21'h1E008C] = 8'h10;
	sram_hi[21'h1E008D] = 8'h00; sram_lo[21'h1E008D] = 8'h96;
	sram_hi[21'h1E008E] = 8'h31; sram_lo[21'h1E008E] = 8'h7C;
	sram_hi[21'h1E008F] = 8'h40; sram_lo[21'h1E008F] = 8'h00;
	sram_hi[21'h1E0090] = 8'h00; sram_lo[21'h1E0090] = 8'h24;
	sram_hi[21'h1E0091] = 8'h31; sram_lo[21'h1E0091] = 8'h7C;
	sram_hi[21'h1E0092] = 8'h82; sram_lo[21'h1E0092] = 8'h58;
	sram_hi[21'h1E0093] = 8'h00; sram_lo[21'h1E0093] = 8'h24;
	sram_hi[21'h1E0094] = 8'h31; sram_lo[21'h1E0094] = 8'h7C;
	sram_hi[21'h1E0095] = 8'h82; sram_lo[21'h1E0095] = 8'h58;
	sram_hi[21'h1E0096] = 8'h00; sram_lo[21'h1E0096] = 8'h24;
	sram_hi[21'h1E0097] = 8'h30; sram_lo[21'h1E0097] = 8'h28;
	sram_hi[21'h1E0098] = 8'h00; sram_lo[21'h1E0098] = 8'h1E;
	sram_hi[21'h1E0099] = 8'h08; sram_lo[21'h1E0099] = 8'h00;
	sram_hi[21'h1E009A] = 8'h00; sram_lo[21'h1E009A] = 8'h01;
	sram_hi[21'h1E009B] = 8'h67; sram_lo[21'h1E009B] = 8'hF6;
	sram_hi[21'h1E009C] = 8'h31; sram_lo[21'h1E009C] = 8'h7C;
	sram_hi[21'h1E009D] = 8'h0F; sram_lo[21'h1E009D] = 8'h00;
	sram_hi[21'h1E009E] = 8'h01; sram_lo[21'h1E009E] = 8'h80;
	sram_hi[21'h1E009F] = 8'h60; sram_lo[21'h1E009F] = 8'hFE;
end

reg [7:0] adf [0:11263]; // tracks 0 and 1
initial $readmemh("adf.hex", adf);

// ---------------- MCU spi (mode 0) ----------------

reg mcu_cs_n = 1'b1, mcu_sck = 1'b0, mcu_mosi = 1'b0;
wire mcu_miso;
wire [5:0] mcu_io;
assign mcu_io[0] = 1'b1; // burst cs_n
assign mcu_io[2] = 1'b1; // sd2 cs_n
assign mcu_io[3] = 1'b1; // ft cs_n

task spi_byte(input [7:0] tx, output [7:0] rx);
	integer k;
	begin
		for (k = 7; k >= 0; k = k - 1) begin
			mcu_mosi = tx[k];
			#31;
			mcu_sck = 1'b1;
			rx[k] = mcu_miso;
			#31;
			mcu_sck = 1'b0;
		end
	end
endtask

reg [31:0] req_lba = 0;
reg [7:0] req_slot = 0, req_op = 0;
reg req_pending = 0;
reg [7:0] rc, ra, rd;

task frame(input [7:0] c, input [7:0] a, input [7:0] d);
	begin
		mcu_cs_n = 1'b0;
		#100;
		spi_byte(c, rc);
		spi_byte(a, ra);
		spi_byte(d, rd);
		#50;
		mcu_cs_n = 1'b1;
		#300;
		case (rc)
			8'h42: req_lba[ra*8 +: 8] = rd;
			8'h43: begin req_slot = ra; req_op = rd; req_pending = 1; end
			default: ;
		endcase
	end
endtask

// ---------------- DUT ----------------

wire [3:0] tmds_p, tmds_n;

karabas_minig_top #(.RESET_DELAY(16'd256)) dut(
	.CLK_50MHZ(clk50),
	.TAPE_IN(1'b1),
	.ADC_DOUT(1'b0),
	.UART_RX(1'b1),
	.ESP32_PCM_BCK(1'b0),
	.ESP32_PCM_RLCK(1'b0),
	.ESP32_PCM_DAT(1'b0),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N),
	.MRD_N(MRD_N),
	.SD_DO(1'b1),
	.SD_DET_N(1'b1),
	.FT_SPI_MISO(1'b1),
	.FT_INT_N(1'b1),
	.FT_CLK(1'b0),
	.FT_DE(1'b0),
	.VGA_R(8'h00),
	.VGA_G(8'h00),
	.VGA_B(8'h00),
	.VGA_HS(1'b0),
	.VGA_VS(1'b0),
	.TMDS_P(tmds_p),
	.TMDS_N(tmds_n),
	.MCU_CS_N(mcu_cs_n),
	.MCU_SCK(mcu_sck),
	.MCU_MOSI(mcu_mosi),
	.MCU_MISO(mcu_miso),
	.MCU_IO(mcu_io),
	.FLASH_DO(1'b1)
);

// ---------------- ISim start values ----------------

// XST starts every flip-flop at 0; ISim starts them at X: the registers without a reset
initial begin
	#1;
	dut.nanomig.minimig.AGNUS1.bc1.hpos[8:1] = 8'd0;
	dut.nanomig.minimig.AGNUS1.bc1.vpos = 11'd0;
	dut.nanomig.minimig.AGNUS1.bc1.end_of_line = 1'b0;
	dut.nanomig.minimig.AGNUS1.bc1.vpos_inc = 1'b0;
	dut.nanomig.minimig.AGNUS1.bc1.long_line = 1'b0;
	dut.nanomig.minimig.PAULA1.pf1.dsktrack[0] = 7'd0;
	dut.nanomig.minimig.PAULA1.pf1.dsktrack[1] = 7'd0;
	dut.nanomig.minimig.PAULA1.pf1.dsktrack[2] = 7'd0;
	dut.nanomig.minimig.PAULA1.pf1.dsktrack[3] = 7'd0;
end

// minimig_syscontrol holds the reset for 4 frames: count on every 7 MHz clock instead
initial begin
	wait (dut.cpu_reset === 1'b0);
	force dut.nanomig.minimig.CONTROL1.cnt = 1'b1;
	#5000;
	release dut.nanomig.minimig.CONTROL1.cnt;
end

// floppy turbo (7 disk dma slots per line instead of 3), to keep the simulation short
initial force dut.floppy_config = 4'b0101;

// ---------------- monitors ----------------

reg done = 1'b0;
reg as_d = 1'b1;
always @(posedge dut.clk_sys) begin
	as_d <= dut.nanomig.chip_as;
	if (as_d && !dut.nanomig.chip_as && !dut.nanomig.chip_rw && dut.nanomig.chip_addr[23:12] == 12'hDFF) begin
		#1 $display("%t custom wr %06x %04x", $time, { dut.nanomig.chip_addr, 1'b0 }, dut.nanomig.chip_din);
		if ({ dut.nanomig.chip_addr, 1'b0 } == 24'hDFF180 && dut.nanomig.chip_din == 16'h0F00) done = 1'b1;
	end
end

integer ndma = 0;
always @(negedge MWR_N[1]) if (MA >= 21'h8000 && MA < 21'h8300) ndma = ndma + 1;

// ---------------- test ----------------

integer errors = 0, n, j, base, sec, trk;
reg [15:0] w [0:599];
reg [31:0] hdr, csum, hcs, dcs, o, e;

function [31:0] decode(input [31:0] odd, input [31:0] even);
	decode = ((odd & 32'h55555555) << 1) | (even & 32'h55555555);
endfunction

initial begin
	#200000;
	frame(8'hFE, 8'h00, 8'h00);   // init done -> reset released
	// mount slot 0: an adf
	frame(8'h40, 8'h00, 8'h00);
	for (n = 0; n < 8; n = n + 1) frame(8'h41, n, 8'h00);
	for (n = 0; n < 8; n = n + 1) frame(8'h41, n, (64'd901120 >> (8 * n)) & 8'hFF);
	$display("%t mounted", $time);
	// the mcu main loop: poll, serve sector reads
	while (!done && $time < 64'd30000000000) begin
		frame(8'hFF, 0, 0);
		if (req_pending) begin
			req_pending = 0;
			$display("%t mcu: read slot %0d lba %0d", $time, req_slot, req_lba);
			for (n = 0; n < 512; n = n + 1) begin
				if (n % 256 == 0) frame(8'h44, 8'h00, n / 256);
				frame(8'h45, n % 256, adf[req_lba * 512 + n]);
			end
			frame(8'h43, req_slot, 8'h01);
		end
	end
	$display("%t done %b, %0d dma writes to $10000+", $time, done, ndma);
	if (!done) errors = errors + 1;
	for (n = 0; n < 600; n = n + 1) w[n] = { sram_hi[21'h8000 + n], sram_lo[21'h8000 + n] };
	$display("first words %04x %04x %04x %04x %04x %04x", w[0], w[1], w[2], w[3], w[4], w[5]);
	base = (w[0] == 16'h4489) ? 1 : 0;
	hdr = decode({w[base], w[base+1]}, {w[base+2], w[base+3]});
	trk = hdr[23:16];
	sec = hdr[15:8];
	csum = 0;
	for (j = 0; j < 10; j = j + 1) csum = csum ^ {w[base+2*j], w[base+2*j+1]};
	csum = csum & 32'h55555555;
	hcs = decode({w[base+20], w[base+21]}, {w[base+22], w[base+23]});
	dcs = decode({w[base+24], w[base+25]}, {w[base+26], w[base+27]});
	$display("header %08x: track %0d sector %0d, header csum %08x calc %08x", hdr, trk, sec, hcs, csum);
	if (hdr[31:24] != 8'hFF || trk != 0 || sec > 10 || hcs != csum) errors = errors + 1;
	else begin
		csum = 0;
		for (j = 0; j < 256; j = j + 1) csum = csum ^ {w[base+28+2*j], w[base+29+2*j]};
		csum = csum & 32'h55555555;
		if (dcs != csum) begin $display("ERROR: data csum %08x calc %08x", dcs, csum); errors = errors + 1; end
		for (j = 0; j < 128; j = j + 1) begin
			o = {w[base+28+2*j], w[base+29+2*j]};
			e = {w[base+284+2*j], w[base+285+2*j]};
			if (decode(o, e) != {adf[sec*512+4*j], adf[sec*512+4*j+1], adf[sec*512+4*j+2], adf[sec*512+4*j+3]}) begin
				if (errors < 10) $display("ERROR: long %0d %08x adf %02x%02x%02x%02x", j, decode(o, e),
					adf[sec*512+4*j], adf[sec*512+4*j+1], adf[sec*512+4*j+2], adf[sec*512+4*j+3]);
				errors = errors + 1;
			end
		end
	end
	$display("tb_disk: %0d errors", errors);
	$finish;
end

endmodule
