`timescale 1ns / 1ps

// The physical floppy drive through the whole Go top: the mcu makes DF1 the drive DS1
// (CMD_IMG_PHYS after the size 0 frames of slot 1); a 68000 program in place of the Kickstart code
// at $FC00D2 sets CIA-B PRB and DDRB, selects DF1 with the motor on, reads CIA-A PRA (_RDY, _TK0, _WPRO,
// _CHNG) to $C00000, steps out once, reads PRA to $C00001 and writes COLOR00.
// fdd_model.v (no disk, on cylinder 1) is on the FDC pins of DS1.
// Checks: the slot map and its change event, the drive count, the pins (DS1 only, motor, one step
// pulse with DIR = out), and the PRA bits: not ready (motor just on), not track 0 / track 0 after
// the step, write protected (no disk), disk changed.
// Ends with "tb_go_floppy: N errors".

module tb_go_floppy;

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
	// the test program at $FC00D2 (the reset pc), in both 256 KB halves:
	//   move.b  #$7F,$BFD100        ; PRB: _MTR low, no drive selected
	//   move.b  #$FF,$BFD300        ; CIA-B DDRB: outputs (after PRB, as Kickstart: PRB is 0 after reset)
	//   move.b  #$6F,$BFD100        ; _SEL1 low: DF1 with the motor on
	//   move.b  $BFE001,$C00000     ; CIA-A PRA
	//   move.b  #$6E,$BFD100        ; _STEP low (DIR = 1: out)
	//   move.b  #$6F,$BFD100        ; _STEP high
	//   move.b  $BFE001,$C00001     ; CIA-A PRA
	//   move.w  #$0F00,$DFF180      ; COLOR00: done
	//   bra.s   *
	sram_hi[21'h1C0069] = 8'h13; sram_lo[21'h1C0069] = 8'hFC;
	sram_hi[21'h1E0069] = 8'h13; sram_lo[21'h1E0069] = 8'hFC;
	sram_hi[21'h1C006A] = 8'h00; sram_lo[21'h1C006A] = 8'h7F;
	sram_hi[21'h1E006A] = 8'h00; sram_lo[21'h1E006A] = 8'h7F;
	sram_hi[21'h1C006B] = 8'h00; sram_lo[21'h1C006B] = 8'hBF;
	sram_hi[21'h1E006B] = 8'h00; sram_lo[21'h1E006B] = 8'hBF;
	sram_hi[21'h1C006C] = 8'hD1; sram_lo[21'h1C006C] = 8'h00;
	sram_hi[21'h1E006C] = 8'hD1; sram_lo[21'h1E006C] = 8'h00;
	sram_hi[21'h1C006D] = 8'h13; sram_lo[21'h1C006D] = 8'hFC;
	sram_hi[21'h1E006D] = 8'h13; sram_lo[21'h1E006D] = 8'hFC;
	sram_hi[21'h1C006E] = 8'h00; sram_lo[21'h1C006E] = 8'hFF;
	sram_hi[21'h1E006E] = 8'h00; sram_lo[21'h1E006E] = 8'hFF;
	sram_hi[21'h1C006F] = 8'h00; sram_lo[21'h1C006F] = 8'hBF;
	sram_hi[21'h1E006F] = 8'h00; sram_lo[21'h1E006F] = 8'hBF;
	sram_hi[21'h1C0070] = 8'hD3; sram_lo[21'h1C0070] = 8'h00;
	sram_hi[21'h1E0070] = 8'hD3; sram_lo[21'h1E0070] = 8'h00;
	sram_hi[21'h1C0071] = 8'h13; sram_lo[21'h1C0071] = 8'hFC;
	sram_hi[21'h1E0071] = 8'h13; sram_lo[21'h1E0071] = 8'hFC;
	sram_hi[21'h1C0072] = 8'h00; sram_lo[21'h1C0072] = 8'h6F;
	sram_hi[21'h1E0072] = 8'h00; sram_lo[21'h1E0072] = 8'h6F;
	sram_hi[21'h1C0073] = 8'h00; sram_lo[21'h1C0073] = 8'hBF;
	sram_hi[21'h1E0073] = 8'h00; sram_lo[21'h1E0073] = 8'hBF;
	sram_hi[21'h1C0074] = 8'hD1; sram_lo[21'h1C0074] = 8'h00;
	sram_hi[21'h1E0074] = 8'hD1; sram_lo[21'h1E0074] = 8'h00;
	sram_hi[21'h1C0075] = 8'h13; sram_lo[21'h1C0075] = 8'hF9;
	sram_hi[21'h1E0075] = 8'h13; sram_lo[21'h1E0075] = 8'hF9;
	sram_hi[21'h1C0076] = 8'h00; sram_lo[21'h1C0076] = 8'hBF;
	sram_hi[21'h1E0076] = 8'h00; sram_lo[21'h1E0076] = 8'hBF;
	sram_hi[21'h1C0077] = 8'hE0; sram_lo[21'h1C0077] = 8'h01;
	sram_hi[21'h1E0077] = 8'hE0; sram_lo[21'h1E0077] = 8'h01;
	sram_hi[21'h1C0078] = 8'h00; sram_lo[21'h1C0078] = 8'hC0;
	sram_hi[21'h1E0078] = 8'h00; sram_lo[21'h1E0078] = 8'hC0;
	sram_hi[21'h1C0079] = 8'h00; sram_lo[21'h1C0079] = 8'h00;
	sram_hi[21'h1E0079] = 8'h00; sram_lo[21'h1E0079] = 8'h00;
	sram_hi[21'h1C007A] = 8'h13; sram_lo[21'h1C007A] = 8'hFC;
	sram_hi[21'h1E007A] = 8'h13; sram_lo[21'h1E007A] = 8'hFC;
	sram_hi[21'h1C007B] = 8'h00; sram_lo[21'h1C007B] = 8'h6E;
	sram_hi[21'h1E007B] = 8'h00; sram_lo[21'h1E007B] = 8'h6E;
	sram_hi[21'h1C007C] = 8'h00; sram_lo[21'h1C007C] = 8'hBF;
	sram_hi[21'h1E007C] = 8'h00; sram_lo[21'h1E007C] = 8'hBF;
	sram_hi[21'h1C007D] = 8'hD1; sram_lo[21'h1C007D] = 8'h00;
	sram_hi[21'h1E007D] = 8'hD1; sram_lo[21'h1E007D] = 8'h00;
	sram_hi[21'h1C007E] = 8'h13; sram_lo[21'h1C007E] = 8'hFC;
	sram_hi[21'h1E007E] = 8'h13; sram_lo[21'h1E007E] = 8'hFC;
	sram_hi[21'h1C007F] = 8'h00; sram_lo[21'h1C007F] = 8'h6F;
	sram_hi[21'h1E007F] = 8'h00; sram_lo[21'h1E007F] = 8'h6F;
	sram_hi[21'h1C0080] = 8'h00; sram_lo[21'h1C0080] = 8'hBF;
	sram_hi[21'h1E0080] = 8'h00; sram_lo[21'h1E0080] = 8'hBF;
	sram_hi[21'h1C0081] = 8'hD1; sram_lo[21'h1C0081] = 8'h00;
	sram_hi[21'h1E0081] = 8'hD1; sram_lo[21'h1E0081] = 8'h00;
	sram_hi[21'h1C0082] = 8'h13; sram_lo[21'h1C0082] = 8'hF9;
	sram_hi[21'h1E0082] = 8'h13; sram_lo[21'h1E0082] = 8'hF9;
	sram_hi[21'h1C0083] = 8'h00; sram_lo[21'h1C0083] = 8'hBF;
	sram_hi[21'h1E0083] = 8'h00; sram_lo[21'h1E0083] = 8'hBF;
	sram_hi[21'h1C0084] = 8'hE0; sram_lo[21'h1C0084] = 8'h01;
	sram_hi[21'h1E0084] = 8'hE0; sram_lo[21'h1E0084] = 8'h01;
	sram_hi[21'h1C0085] = 8'h00; sram_lo[21'h1C0085] = 8'hC0;
	sram_hi[21'h1E0085] = 8'h00; sram_lo[21'h1E0085] = 8'hC0;
	sram_hi[21'h1C0086] = 8'h00; sram_lo[21'h1C0086] = 8'h01;
	sram_hi[21'h1E0086] = 8'h00; sram_lo[21'h1E0086] = 8'h01;
	sram_hi[21'h1C0087] = 8'h33; sram_lo[21'h1C0087] = 8'hFC;
	sram_hi[21'h1E0087] = 8'h33; sram_lo[21'h1E0087] = 8'hFC;
	sram_hi[21'h1C0088] = 8'h0F; sram_lo[21'h1C0088] = 8'h00;
	sram_hi[21'h1E0088] = 8'h0F; sram_lo[21'h1E0088] = 8'h00;
	sram_hi[21'h1C0089] = 8'h00; sram_lo[21'h1C0089] = 8'hDF;
	sram_hi[21'h1E0089] = 8'h00; sram_lo[21'h1E0089] = 8'hDF;
	sram_hi[21'h1C008A] = 8'hF1; sram_lo[21'h1C008A] = 8'h80;
	sram_hi[21'h1E008A] = 8'hF1; sram_lo[21'h1E008A] = 8'h80;
	sram_hi[21'h1C008B] = 8'h60; sram_lo[21'h1C008B] = 8'hFE;
	sram_hi[21'h1E008B] = 8'h60; sram_lo[21'h1E008B] = 8'hFE;
end

// ---------------- MCU spi (mode 0) ----------------

reg mcu_cs_n = 1'b1, mcu_sck = 1'b0, mcu_mosi = 1'b0;
wire mcu_miso;
wire [3:0] mcu_io;
assign mcu_io[1] = 1'b1; // burst cs_n
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

// ---------------- DUT ----------------

wire [2:0] cf_a;
wire [1:0] cf_cs_n;
wire cf_rd_n, cf_wr_n, cf_reset_n;
wire [15:0] cf_bus;
wire [15:0] sdr_dq;
wire [1:0] fdc_drive;
wire fdc_motor, fdc_dir, fdc_step, fdc_wdata, fdc_wgate, fdc_side_n;
wire fdc_index, fdc_tr00, fdc_wprt, fdc_rdata;

karabas_go_top #(.RESET_DELAY(16'd256)) dut(
	.CLK_50MHZ(clk50),
	.TAPE_IN(1'b1),
	.UART_RX(1'b1),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N),
	.MRD_N(MRD_N),
	.SDR_DQ(sdr_dq),
	.SD_DO(1'b1),
	.SD_DET_N(1'b1),
	.FDC_INDEX(fdc_index),
	.FDC_DRIVE(fdc_drive),
	.FDC_MOTOR(fdc_motor),
	.FDC_DIR(fdc_dir),
	.FDC_STEP(fdc_step),
	.FDC_WDATA(fdc_wdata),
	.FDC_WGATE(fdc_wgate),
	.FDC_TR00(fdc_tr00),
	.FDC_WPRT(fdc_wprt),
	.FDC_RDATA(fdc_rdata),
	.FDC_SIDE_N(fdc_side_n),
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

assign cf_bus = 16'hzzzz;
assign sdr_dq = 16'hzzzz;

fdd_model drive(
	.ds(fdc_drive[1]), .motor(fdc_motor), .dir(fdc_dir), .step(fdc_step), .side1(fdc_side_n),
	.wgate(fdc_wgate), .wdata(fdc_wdata),
	.index(fdc_index), .tr00(fdc_tr00), .wprt(fdc_wprt), .rdata(fdc_rdata)
);

integer errors = 0;
task check(input [255:0] what, input [15:0] got, input [15:0] exp);
	if (got !== exp) begin
		errors = errors + 1;
		$display("%t ERROR %0s: %04x, expected %04x", $time, what, got, exp);
	end
endtask

// XST starts every flip-flop at 0; ISim starts them at X. The Agnus beam counter and the head
// positions of paula_floppy have no reset.
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
	drive.cyl = 1;
end

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

integer n_chg = 0, n_step = 0, n_ds0 = 0, n_ds1 = 0, step_dir_in = 0;
always @(posedge dut.clk_sys) if (dut.floppy_ext_chg != 4'd0) begin
	n_chg = n_chg + 1;
	if (dut.floppy_ext_chg != 4'b0010) begin errors = errors + 1; $display("ERROR change event %b", dut.floppy_ext_chg); end
end
always @(posedge fdc_step) begin
	n_step = n_step + 1;
	if (fdc_dir) step_dir_in = step_dir_in + 1;
end
always @(posedge fdc_drive[0]) n_ds0 = n_ds0 + 1;
always @(posedge fdc_drive[1]) n_ds1 = n_ds1 + 1;

// ---------------- stimulus ----------------

integer w;
initial begin
	#200000; // pll lock
	frame(8'hFD, 8'h00, 8'h00);   // init start
	// slot 1: the size 0 frames, then drive DS1
	frame(8'h40, 8'h00, 8'h01);
	for (w = 0; w < 8; w = w + 1)
		frame(8'h41, w, 8'h00);
	frame(8'h46, 8'h01, 8'h02);
	check("floppy_ext", dut.floppy_ext, 8'h08);
	check("change events", n_chg, 1);
	frame(8'hFE, 8'h00, 8'h00);   // init done -> reset released
	$display("%t init done", $time);
	w = 0;
	while (!done && w < 4000) begin #1000; w = w + 1; end
	check("program done", done, 1'b1);
	check("drives - 1", dut.drives, 2'd1);
	check("PRA after the select: _RDY _TK0 _WPRO _CHNG", sram_hi[21'h100000] & 8'h3C, 8'h30);
	check("PRA after the step", sram_lo[21'h100000] & 8'h3C, 8'h20);
	check("DS0 never selected", n_ds0, 0);
	check("DS1 selected", n_ds1 > 0, 1'b1);
	check("motor on", fdc_motor, 1'b1);
	check("step pulses", n_step, 1);
	check("step pulses with DIR = in", step_dir_in, 0);
	check("drive on cylinder 0", drive.cyl, 0);
	check("DIR setup", drive.dir_err, 0);
	$display("tb_go_floppy: %0d errors", errors);
	$finish;
end

endmodule
