`timescale 1ns / 1ps

// The Kickstart ioctl loader and the MSM6242B clock through the whole Mini G top.
// - ioctl (FL osd item Kickstart): bytes at file offset n go to SRAM byte 0x380000 + n, a byte
//   past 512 KB is dropped, the cpu is held in reset meanwhile, a load of the lower 256 KB only
//   turns the Kickstart mirror on.
// - clock: the mcu sends the 13 time registers (CMD_RTC); a 68000 program in place of the
//   Kickstart code at $FC00D2 reads F, D and registers 0-12 at $DC0003 + 4n into slow ram, writes
//   registers 0, 5 and 13 (D), reads register 0 back and writes COLOR00. The writes of 0 and 5
//   must come to the mcu as CMD_RTC frames (once each), the one of D must not.
// Ends with "tb_rtc: N errors".

module tb_rtc;

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
	// kickstart (512 KB) at byte 0x380000 = word 0x1C0000
	$readmemh("kick_hi.hex", sram_hi, 21'h1C0000, 21'h1FFFFF);
	$readmemh("kick_lo.hex", sram_lo, 21'h1C0000, 21'h1FFFFF);
	// the test program at $FC00D2 (the reset pc), in both 256 KB halves, assembled by hand:
	//   lea     $DC0000,a0
	//   move.b  $3F(a0),d0          ; register F
	//   move.b  d0,$C00000
	//   move.b  $37(a0),$C00001     ; register D
	//   moveq   #12,d1
	//   lea     $C00010,a1
	//   lea     3(a0),a2
	// l1: move.b (a2),(a1)+         ; registers 0-12 to $C00010
	//   addq.l  #4,a2
	//   dbra    d1,l1
	//   move.b  #9,3(a0)            ; S1 = 9
	//   move.b  #2,$17(a0)          ; H10 = 2
	//   move.b  #1,$37(a0)          ; D = 1 (HOLD): not to the mcu
	//   move.b  3(a0),$C00002       ; S1 again
	//   move.w  #$0F00,$DFF180      ; COLOR00: done
	//   bra.s   *
	sram_hi[21'h1C0069] = 8'h41; sram_lo[21'h1C0069] = 8'hF9;
	sram_hi[21'h1E0069] = 8'h41; sram_lo[21'h1E0069] = 8'hF9;
	sram_hi[21'h1C006A] = 8'h00; sram_lo[21'h1C006A] = 8'hDC;
	sram_hi[21'h1E006A] = 8'h00; sram_lo[21'h1E006A] = 8'hDC;
	sram_hi[21'h1C006B] = 8'h00; sram_lo[21'h1C006B] = 8'h00;
	sram_hi[21'h1E006B] = 8'h00; sram_lo[21'h1E006B] = 8'h00;
	sram_hi[21'h1C006C] = 8'h10; sram_lo[21'h1C006C] = 8'h28;
	sram_hi[21'h1E006C] = 8'h10; sram_lo[21'h1E006C] = 8'h28;
	sram_hi[21'h1C006D] = 8'h00; sram_lo[21'h1C006D] = 8'h3F;
	sram_hi[21'h1E006D] = 8'h00; sram_lo[21'h1E006D] = 8'h3F;
	sram_hi[21'h1C006E] = 8'h13; sram_lo[21'h1C006E] = 8'hC0;
	sram_hi[21'h1E006E] = 8'h13; sram_lo[21'h1E006E] = 8'hC0;
	sram_hi[21'h1C006F] = 8'h00; sram_lo[21'h1C006F] = 8'hC0;
	sram_hi[21'h1E006F] = 8'h00; sram_lo[21'h1E006F] = 8'hC0;
	sram_hi[21'h1C0070] = 8'h00; sram_lo[21'h1C0070] = 8'h00;
	sram_hi[21'h1E0070] = 8'h00; sram_lo[21'h1E0070] = 8'h00;
	sram_hi[21'h1C0071] = 8'h13; sram_lo[21'h1C0071] = 8'hE8;
	sram_hi[21'h1E0071] = 8'h13; sram_lo[21'h1E0071] = 8'hE8;
	sram_hi[21'h1C0072] = 8'h00; sram_lo[21'h1C0072] = 8'h37;
	sram_hi[21'h1E0072] = 8'h00; sram_lo[21'h1E0072] = 8'h37;
	sram_hi[21'h1C0073] = 8'h00; sram_lo[21'h1C0073] = 8'hC0;
	sram_hi[21'h1E0073] = 8'h00; sram_lo[21'h1E0073] = 8'hC0;
	sram_hi[21'h1C0074] = 8'h00; sram_lo[21'h1C0074] = 8'h01;
	sram_hi[21'h1E0074] = 8'h00; sram_lo[21'h1E0074] = 8'h01;
	sram_hi[21'h1C0075] = 8'h72; sram_lo[21'h1C0075] = 8'h0C;
	sram_hi[21'h1E0075] = 8'h72; sram_lo[21'h1E0075] = 8'h0C;
	sram_hi[21'h1C0076] = 8'h43; sram_lo[21'h1C0076] = 8'hF9;
	sram_hi[21'h1E0076] = 8'h43; sram_lo[21'h1E0076] = 8'hF9;
	sram_hi[21'h1C0077] = 8'h00; sram_lo[21'h1C0077] = 8'hC0;
	sram_hi[21'h1E0077] = 8'h00; sram_lo[21'h1E0077] = 8'hC0;
	sram_hi[21'h1C0078] = 8'h00; sram_lo[21'h1C0078] = 8'h10;
	sram_hi[21'h1E0078] = 8'h00; sram_lo[21'h1E0078] = 8'h10;
	sram_hi[21'h1C0079] = 8'h45; sram_lo[21'h1C0079] = 8'hE8;
	sram_hi[21'h1E0079] = 8'h45; sram_lo[21'h1E0079] = 8'hE8;
	sram_hi[21'h1C007A] = 8'h00; sram_lo[21'h1C007A] = 8'h03;
	sram_hi[21'h1E007A] = 8'h00; sram_lo[21'h1E007A] = 8'h03;
	sram_hi[21'h1C007B] = 8'h12; sram_lo[21'h1C007B] = 8'hD2;
	sram_hi[21'h1E007B] = 8'h12; sram_lo[21'h1E007B] = 8'hD2;
	sram_hi[21'h1C007C] = 8'h58; sram_lo[21'h1C007C] = 8'h8A;
	sram_hi[21'h1E007C] = 8'h58; sram_lo[21'h1E007C] = 8'h8A;
	sram_hi[21'h1C007D] = 8'h51; sram_lo[21'h1C007D] = 8'hC9;
	sram_hi[21'h1E007D] = 8'h51; sram_lo[21'h1E007D] = 8'hC9;
	sram_hi[21'h1C007E] = 8'hFF; sram_lo[21'h1C007E] = 8'hFA;
	sram_hi[21'h1E007E] = 8'hFF; sram_lo[21'h1E007E] = 8'hFA;
	sram_hi[21'h1C007F] = 8'h11; sram_lo[21'h1C007F] = 8'h7C;
	sram_hi[21'h1E007F] = 8'h11; sram_lo[21'h1E007F] = 8'h7C;
	sram_hi[21'h1C0080] = 8'h00; sram_lo[21'h1C0080] = 8'h09;
	sram_hi[21'h1E0080] = 8'h00; sram_lo[21'h1E0080] = 8'h09;
	sram_hi[21'h1C0081] = 8'h00; sram_lo[21'h1C0081] = 8'h03;
	sram_hi[21'h1E0081] = 8'h00; sram_lo[21'h1E0081] = 8'h03;
	sram_hi[21'h1C0082] = 8'h11; sram_lo[21'h1C0082] = 8'h7C;
	sram_hi[21'h1E0082] = 8'h11; sram_lo[21'h1E0082] = 8'h7C;
	sram_hi[21'h1C0083] = 8'h00; sram_lo[21'h1C0083] = 8'h02;
	sram_hi[21'h1E0083] = 8'h00; sram_lo[21'h1E0083] = 8'h02;
	sram_hi[21'h1C0084] = 8'h00; sram_lo[21'h1C0084] = 8'h17;
	sram_hi[21'h1E0084] = 8'h00; sram_lo[21'h1E0084] = 8'h17;
	sram_hi[21'h1C0085] = 8'h11; sram_lo[21'h1C0085] = 8'h7C;
	sram_hi[21'h1E0085] = 8'h11; sram_lo[21'h1E0085] = 8'h7C;
	sram_hi[21'h1C0086] = 8'h00; sram_lo[21'h1C0086] = 8'h01;
	sram_hi[21'h1E0086] = 8'h00; sram_lo[21'h1E0086] = 8'h01;
	sram_hi[21'h1C0087] = 8'h00; sram_lo[21'h1C0087] = 8'h37;
	sram_hi[21'h1E0087] = 8'h00; sram_lo[21'h1E0087] = 8'h37;
	sram_hi[21'h1C0088] = 8'h13; sram_lo[21'h1C0088] = 8'hE8;
	sram_hi[21'h1E0088] = 8'h13; sram_lo[21'h1E0088] = 8'hE8;
	sram_hi[21'h1C0089] = 8'h00; sram_lo[21'h1C0089] = 8'h03;
	sram_hi[21'h1E0089] = 8'h00; sram_lo[21'h1E0089] = 8'h03;
	sram_hi[21'h1C008A] = 8'h00; sram_lo[21'h1C008A] = 8'hC0;
	sram_hi[21'h1E008A] = 8'h00; sram_lo[21'h1E008A] = 8'hC0;
	sram_hi[21'h1C008B] = 8'h00; sram_lo[21'h1C008B] = 8'h02;
	sram_hi[21'h1E008B] = 8'h00; sram_lo[21'h1E008B] = 8'h02;
	sram_hi[21'h1C008C] = 8'h33; sram_lo[21'h1C008C] = 8'hFC;
	sram_hi[21'h1E008C] = 8'h33; sram_lo[21'h1E008C] = 8'hFC;
	sram_hi[21'h1C008D] = 8'h0F; sram_lo[21'h1C008D] = 8'h00;
	sram_hi[21'h1E008D] = 8'h0F; sram_lo[21'h1E008D] = 8'h00;
	sram_hi[21'h1C008E] = 8'h00; sram_lo[21'h1C008E] = 8'hDF;
	sram_hi[21'h1E008E] = 8'h00; sram_lo[21'h1E008E] = 8'hDF;
	sram_hi[21'h1C008F] = 8'hF1; sram_lo[21'h1C008F] = 8'h80;
	sram_hi[21'h1E008F] = 8'hF1; sram_lo[21'h1E008F] = 8'h80;
	sram_hi[21'h1C0090] = 8'h60; sram_lo[21'h1C0090] = 8'hFE;
	sram_hi[21'h1E0090] = 8'h60; sram_lo[21'h1E0090] = 8'hFE;
end

// ---------------- MCU spi (mode 0) ----------------

reg mcu_cs_n = 1'b1, mcu_sck = 1'b0, mcu_mosi = 1'b0;
wire mcu_miso;
wire [5:0] mcu_io;
assign mcu_io[0] = 1'b1; // burst cs_n
assign mcu_io[2] = 1'b1; // sd2 cs_n
assign mcu_io[3] = 1'b1; // ft cs_n

task spi_byte(input [7:0] b);
	integer k;
	begin
		for (k = 7; k >= 0; k = k - 1) begin
			mcu_mosi = b[k];
			#31;
			mcu_sck = 1'b1;
			#31;
			mcu_sck = 1'b0;
		end
	end
endtask

task frame(input [7:0] c, input [7:0] a, input [7:0] d);
	begin
		mcu_cs_n = 1'b0;
		#100;
		spi_byte(c);
		spi_byte(a);
		spi_byte(d);
		#50;
		mcu_cs_n = 1'b1;
		#500;
	end
endtask

// the reply of the fpga in the same frame
reg [23:0] miso_word;
always @(posedge mcu_sck) if (!mcu_cs_n) miso_word <= { miso_word[22:0], mcu_miso };

// ---------------- DUT ----------------

wire [2:0] cf_a;
wire [1:0] cf_cs_n;
wire cf_rd_n, cf_wr_n, cf_reset_n;
wire [15:0] cf_bus;

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
	.FLASH_DO(1'b1),
	.WA(cf_a),
	.WCS_N(cf_cs_n),
	.WRD_N(cf_rd_n),
	.WWR_N(cf_wr_n),
	.WRESET_N(cf_reset_n),
	.WD(cf_bus)
);

integer errors = 0;
task check(input [255:0] what, input [15:0] got, input [15:0] exp);
	if (got !== exp) begin
		errors = errors + 1;
		$display("%t ERROR %0s: %04x, expected %04x", $time, what, got, exp);
	end
endtask

// XST starts every flip-flop at 0; ISim starts them at X. The Agnus beam counter has no reset.
initial begin
	#1;
	dut.nanomig.minimig.AGNUS1.bc1.hpos[8:1] = 8'd0;
	dut.nanomig.minimig.AGNUS1.bc1.vpos = 11'd0;
	dut.nanomig.minimig.AGNUS1.bc1.end_of_line = 1'b0;
	dut.nanomig.minimig.AGNUS1.bc1.vpos_inc = 1'b0;
	dut.nanomig.minimig.AGNUS1.bc1.long_line = 1'b0;
end

// XST starts every flip-flop at 0; ISim starts them at X. The Agnus beam counter has no reset.
initial begin
	#1;
	dut.nanomig.minimig.AGNUS1.bc1.hpos[8:1] = 8'd0;
	dut.nanomig.minimig.AGNUS1.bc1.vpos = 11'd0;
	dut.nanomig.minimig.AGNUS1.bc1.end_of_line = 1'b0;
	dut.nanomig.minimig.AGNUS1.bc1.vpos_inc = 1'b0;
	dut.nanomig.minimig.AGNUS1.bc1.long_line = 1'b0;
end

assign cf_bus = 16'hzzzz;

// ---------------- monitors ----------------

// minimig_syscontrol holds the reset for 4 frames (80 ms): count on every 7 MHz clock instead
initial begin
	wait (dut.cpu_reset === 1'b0);
	force dut.nanomig.minimig.CONTROL1.cnt = 1'b1;
	#5000;
	release dut.nanomig.minimig.CONTROL1.cnt;
end

reg done = 1'b0;
always @(posedge dut.clk_sys)
	if (dut.nanomig.chip_as == 1'b0 && dut.nanomig.chip_rw == 1'b0 && { dut.nanomig.chip_addr, 1'b0 } == 24'hDFF180 && !done) begin
		done = 1'b1;
		$display("%t COLOR00 written: the program got to its end", $time);
	end

always @(posedge dut.clk_sys)
	if (dut.rtc_wr) $display("%t rtc write: register %0d = %0d", $time, dut.rtc_a, dut.rtc_wdata);

// ---------------- stimulus ----------------

// time registers 0-12: 12:34:56, 17.10.(20)26, Saturday (6)
reg [3:0] t [0:12];
integer w, n, n_s1, n_h10, n_d;
reg reset_held;
initial begin
	t[0] = 6; t[1] = 5; t[2] = 4; t[3] = 3; t[4] = 2; t[5] = 1; t[6] = 7; t[7] = 1;
	t[8] = 0; t[9] = 1; t[10] = 6; t[11] = 2; t[12] = 6;
	#200000; // pll lock
	frame(8'hFD, 8'h00, 8'h00);   // init start

	// the Kickstart file: 4 bytes at offset 0x10000, one at 0x80010 (past 512 KB)
	frame(8'h55, 8'h00, 8'h01);   // ioctl start
	frame(8'h50, 8'h00, 8'h07);   // slot 7 (not used by the core)
	frame(8'h52, 8'h00, 8'h00);   // bank: offset bits 15..8
	frame(8'h52, 8'h01, 8'h01);   //       bits 23..16
	frame(8'h52, 8'h02, 8'h00);   //       bits 31..24
	frame(8'h53, 8'h00, 8'hA1);
	frame(8'h53, 8'h01, 8'hB2);
	frame(8'h53, 8'h02, 8'hC3);
	frame(8'h53, 8'h03, 8'hD4);
	reset_held = dut.cpu_reset;
	frame(8'h52, 8'h01, 8'h08);   // offset 0x080010
	frame(8'h53, 8'h10, 8'hEE);
	frame(8'h55, 8'h00, 8'h00);   // ioctl end
	check("cpu reset during ioctl", reset_held, 1'b1);
	check("ioctl byte 0", sram_hi[21'h1C8000], 8'hA1);
	check("ioctl byte 1", sram_lo[21'h1C8000], 8'hB2);
	check("ioctl byte 2", sram_hi[21'h1C8001], 8'hC3);
	check("ioctl byte 3", sram_lo[21'h1C8001], 8'hD4);
	check("ioctl byte past 512K dropped", sram_hi[21'h1C0008], 8'h00);
	check("kick mirror on (lower 256K only)", dut.kick_mirror, 1'b1);

	for (w = 0; w < 13; w = w + 1)
		frame(8'hFA, w, t[w]);
	frame(8'hFE, 8'h00, 8'h00);   // init done -> reset released
	$display("%t init done", $time);
	w = 0;
	while (!done && w < 4000) begin #1000; w = w + 1; end
	check("program done", done, 1'b1);
	check("register F", sram_hi[21'h100000] & 8'h0F, 8'h04);
	check("register D", sram_lo[21'h100000] & 8'h0F, 8'h00);
	for (w = 0; w < 13; w = w + 1)
		check("time register", (w & 1 ? sram_lo[21'h100008 + w / 2] : sram_hi[21'h100008 + w / 2]) & 8'h0F, t[w]);
	check("S1 after the write", sram_hi[21'h100001] & 8'h0F, 8'h09);

	// the writes come to the mcu in the reply frames
	n_s1 = 0; n_h10 = 0; n_d = 0;
	for (n = 0; n < 64; n = n + 1) begin
		frame(8'hFF, 8'h00, 8'h00);
		if (miso_word[23:16] == 8'hFA) begin
			$display("%t mcu got CMD_RTC %02x %02x", $time, miso_word[15:8], miso_word[7:0]);
			if (miso_word[15:0] == 16'h0009) n_s1 = n_s1 + 1;
			else if (miso_word[15:0] == 16'h0502) n_h10 = n_h10 + 1;
			else if (miso_word[15:8] == 8'h0D) n_d = n_d + 1;
			else begin errors = errors + 1; $display("ERROR unexpected CMD_RTC"); end
		end
	end
	check("CMD_RTC S1 = 9 once", n_s1, 1);
	check("CMD_RTC H10 = 2 once", n_h10, 1);
	check("no CMD_RTC for D", n_d, 0);
	$display("tb_rtc: %0d errors", errors);
	$finish;
end

endmodule
