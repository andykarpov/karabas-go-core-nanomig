`timescale 1ns / 1ps

// Mini G top with a model of the two 2Mx8 SRAM chips.
// - the Kickstart is preloaded into the SRAM model (build/kick_hi.hex, build/kick_lo.hex);
// - a few rom loader bytes are sent over the mcu spi link and checked in the SRAM model;
// - then CMD_INIT_DONE releases the reset, and the cpu bus cycles and the first video colors
//   are printed.

module tb_minig;

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
	// shorten the start delay loop of Kickstart 1.3 (move.l #$20000,d0 at $FC00D8) to $10,
	// in both 256 KB halves
	sram_hi[21'h1C006D] = 8'h00; sram_lo[21'h1C006D] = 8'h00;
	sram_hi[21'h1C006E] = 8'h00; sram_lo[21'h1C006E] = 8'h10;
	sram_hi[21'h1E006D] = 8'h00; sram_lo[21'h1E006D] = 8'h00;
	sram_hi[21'h1E006E] = 8'h00; sram_lo[21'h1E006E] = 8'h10;
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

// ---------------- monitors ----------------

// cpu bus cycles on the chip bus
integer ncyc = 0;
reg as_d = 1'b1;
always @(posedge dut.clk_sys) begin
	as_d <= dut.nanomig.chip_as;
	if (as_d && !dut.nanomig.chip_as && ncyc < 60) begin
		ncyc = ncyc + 1;
		#1 $display("%t cpu %s %06x uds/lds %b%b dout %04x", $time,
			dut.nanomig.chip_rw ? "rd" : "wr", { dut.nanomig.chip_addr, 1'b0 },
			dut.nanomig.chip_uds, dut.nanomig.chip_lds, dut.nanomig.chip_din);
	end
end

// cpu writes to the custom chips
integer ncw = 0;
reg as_d3 = 1'b1;
always @(posedge dut.clk_sys) begin
	as_d3 <= dut.nanomig.chip_as;
	if (as_d3 && !dut.nanomig.chip_as && !dut.nanomig.chip_rw && dut.nanomig.chip_addr[23:12] == 12'hDFF && ncw < 60) begin
		ncw = ncw + 1;
		#1 $display("%t custom wr %06x %04x", $time, { dut.nanomig.chip_addr, 1'b0 }, dut.nanomig.chip_din);
	end
end

// data returned to the cpu at the end of each chip bus cycle
reg as_d2 = 1'b1;
integer nrd = 0;
always @(posedge dut.clk_sys) begin
	as_d2 <= dut.nanomig.chip_as;
	if (!as_d2 && dut.nanomig.chip_as && nrd < 0) begin
		nrd = nrd + 1;
		$display("%t cpu end, chip_dout %04x", $time, dut.nanomig.chip_dout);
	end
end

// first colors at the video output
reg [11:0] last_rgb = 12'h000;
integer ncol = 0;
always @(posedge dut.clk_sys) begin
	if ({ dut.red, dut.green, dut.blue } != last_rgb && ncol < 20) begin
		ncol = ncol + 1;
		last_rgb <= { dut.red, dut.green, dut.blue };
		$display("%t video rgb %03x", $time, { dut.red, dut.green, dut.blue });
	end
end

// mcu link and rom loader
always @(dut.mcu_busy) $display("%t mcu busy %b", $time, dut.mcu_busy);
always @(dut.romloader_act) $display("%t romloader active %b", $time, dut.romloader_act);
always @(posedge dut.clk_sys) if (dut.romloader_wr)
	$display("%t romloader wr %08x %02x", $time, dut.romloader_addr, dut.romloader_data);
integer nsw = 0;
always @(posedge MWR_N[1]) if (nsw < 40) begin nsw = nsw + 1; $display("%t sram wr hi %06x %02x", $time, MA, MD[15:8]); end
always @(posedge MWR_N[0]) if (nsw < 40) begin nsw = nsw + 1; $display("%t sram wr lo %06x %02x", $time, MA, MD[7:0]); end
always @(dut.cpu_reset) $display("%t cpu reset %b", $time, dut.cpu_reset);

// cpu state snapshots after the reset
always #2000 if (!dut.cpu_reset && $time < 240000)
	$display("%t rst %b clkena %b busstate %b req %b chipreq %b stage %d as %b dtack %b addr %08x ph1 %b ph2 %b ramsel %b cchip %b ckick %b zram %b", $time,
		dut.nanomig.cpu_wrapper.reset, dut.nanomig.cpu_wrapper.cpu_clkena, dut.nanomig.cpu_wrapper.cpustate,
		dut.nanomig.cpu_wrapper.cpu_req, dut.nanomig.cpu_wrapper.chipreq,
		dut.nanomig.cpu_wrapper.cpu_wrapper_blk460.stage, dut.nanomig.chip_as, dut.nanomig.chip_dtack,
		dut.nanomig.cpu_wrapper.cpu_addr, dut.nanomig.cpu_ph1, dut.nanomig.cpu_ph2,
		dut.nanomig.cpu_wrapper.ramsel, dut.nanomig.cpu_wrapper.cchip, dut.nanomig.cpu_wrapper.ckick,
		dut.nanomig.cpu_wrapper.sel_zram);

// minimig_syscontrol holds the reset for 4 frames (80 ms): count on every 7 MHz clock instead
initial begin
	wait (dut.cpu_reset === 1'b0);
	force dut.nanomig.minimig.CONTROL1.cnt = 1'b1;
	#5000;
	release dut.nanomig.minimig.CONTROL1.cnt;
end

// video chain: sync edges, denise color, blanking
integer nhs = 0, nvs = 0, nhs_out = 0;
reg hs_in_d = 1'b1, vs_in_d = 1'b1, hs_out_d = 1'b1;
always @(posedge dut.clk_sys) begin
	hs_in_d <= dut.nanomig.hs_in;
	vs_in_d <= dut.nanomig.vs_in;
	hs_out_d <= dut.hs;
	if (hs_in_d && !dut.nanomig.hs_in) nhs = nhs + 1;
	if (vs_in_d && !dut.nanomig.vs_in) nvs = nvs + 1;
	if (hs_out_d && !dut.hs) nhs_out = nhs_out + 1;
end
always #500000 $display("%t video: hs_in %0d vs_in %0d hs_out %0d hbl %b vbl %b denise %02x%02x%02x amber %h%h%h vcnt %0d hcnt %0d de %b",
	$time, nhs, nvs, nhs_out, dut.nanomig.hbl, dut.nanomig.vbl, dut.nanomig.red, dut.nanomig.green, dut.nanomig.blue,
	dut.red, dut.green, dut.blue, dut.vcnt, dut.hcnt, dut.video_de);
reg [23:0] last_denise = 24'h0;
integer nden = 0;
always @(posedge dut.clk_sys)
	if ({dut.nanomig.red, dut.nanomig.green, dut.nanomig.blue} != last_denise && nden < 10) begin
		nden = nden + 1;
		last_denise <= {dut.nanomig.red, dut.nanomig.green, dut.nanomig.blue};
		$display("%t denise rgb %06x hbl %b vbl %b", $time, {dut.nanomig.red, dut.nanomig.green, dut.nanomig.blue}, dut.nanomig.hbl, dut.nanomig.vbl);
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

always @(dut.kbd_mouse_level) $display("%t kbd/mouse event type %0d data %02x", $time, dut.kbd_mouse_type, dut.kbd_mouse_data);
always @(dut.kbd_reset) $display("%t kbd_reset %b", $time, dut.kbd_reset);

// ---------------- stimulus ----------------

initial begin
	#200000; // pll lock
	// rom loader test: 4 bytes at byte address 0x000100
	frame(8'h08, 8'h00, 8'h01);   // romloader on
	frame(8'h06, 8'h00, 8'h01);   // bank addr[15:8]
	frame(8'h06, 8'h01, 8'h00);   // bank addr[23:16]
	frame(8'h06, 8'h02, 8'h00);   // bank addr[31:24]
	frame(8'h07, 8'h00, 8'hA1);
	frame(8'h07, 8'h01, 8'hB2);
	frame(8'h07, 8'h02, 8'hC3);
	frame(8'h07, 8'h03, 8'hD4);
	// the first word of the Kickstart, written again: only the lower 256 KB of segment 7 loaded,
	// the upper half is read from the lower one (both halves of kick13.rom are the same)
	frame(8'h06, 8'h01, 8'h38);   // bank addr[23:16]: byte 0x380000
	frame(8'h06, 8'h00, 8'h00);   // bank addr[15:8]
	frame(8'h07, 8'h00, sram_hi[21'h1C0000]);
	frame(8'h07, 8'h01, sram_lo[21'h1C0000]);
	frame(8'h08, 8'h00, 8'h00);   // romloader off
	$display("%t loader check: %02x%02x %02x%02x (expected a1b2 c3d4) kick_mirror %b (expected 1)", $time,
		sram_hi[21'h80], sram_lo[21'h80], sram_hi[21'h81], sram_lo[21'h81], dut.kick_mirror);
	frame(8'hFE, 8'h00, 8'h00);   // init done -> reset released
	$display("%t init done", $time);
	// keyboard: F12 (keyboard reset), as the firmware sends a report
	#50000;
	frame(8'h01, 8'h00, 8'h00);
	frame(8'h01, 8'h01, 8'h45);
	frame(8'h01, 8'h02, 8'h00);
	frame(8'h01, 8'h03, 8'h00);
	frame(8'h01, 8'h04, 8'h00);
	frame(8'h01, 8'h05, 8'h00);
	frame(8'h01, 8'h06, 8'h00);
	#300000;
	$display("%t kb_status %02x kbd_reset %b cpu_reset %b", $time, dut.kb_status, dut.kbd_reset, dut.cpu_reset);
	frame(8'h01, 8'h01, 8'h00);
	// mouse: x +5, y -3, left button
	frame(8'h02, 8'h00, 8'h05);
	frame(8'h02, 8'h01, 8'hFD);
	frame(8'h02, 8'h02, 8'h00);
	frame(8'h02, 8'h03, 8'h01);
	#50000;
	$display("%t ms %02x %02x b %b upd %b buttons %b", $time, dut.ms_x, dut.ms_y, dut.ms_b, dut.ms_upd, dut.mouse_buttons);
	// joysticks: L up + A, R right + B + C
	frame(8'h03, 8'h00, 8'h43);
	frame(8'h03, 8'h02, 8'h91);
	frame(8'h03, 8'h03, 8'h01);
	#1000;
	$display("%t joy_l %04x joy0 %02x (expected 18) joy_r %04x joy1 %02x (expected 61) fire port2 %b (expected 0)", $time,
		dut.joy_l, dut.joy0, dut.joy_r, dut.joy1, dut.nanomig.minimig.USERIO1._fire1);
	frame(8'h03, 8'h00, 8'h01);
	frame(8'h03, 8'h02, 8'h01);
	frame(8'h03, 8'h03, 8'h00);
end

// kickstart reads from the upper 256 KB (Kickstart 1.3 runs at $FC0000): the mirror reads the lower half
integer nkick = 0;
always @(posedge dut.clk_sys)
	if (dut.cyc == 2'd1 && dut.MRD_N == 2'b00 && MA[20:18] == 3'b111 && dut.ram_a[18] && nkick < 3) begin
		nkick = nkick + 1;
		$display("%t kick read ram_a %06x MA %06x (MA[17] expected 0)", $time, {dut.ram_a, 1'b0}, MA);
	end

endmodule
