`timescale 1ns / 1ps

// The CF card slot through the whole Mini G top: HDD = CF card (soft switch 12), and a 68000
// program in place of the Kickstart code at $FC00D2 (in the SRAM model) talks to the Gayle IDE
// registers: IDENTIFY, waits for the Gayle interrupt, reads the 256 words into slow ram, then
// writes them back to LBA 3 with WRITE SECTORS (waits for DRQ on the alternate status, then for
// the interrupt) and writes COLOR00 = $F00. The CF card is an ATA device model (as tb_gayle_cf).
// Checks the byte order in memory and on the card, and that the program gets to its end.
// Ends with "tb_hdd: N errors".

module tb_hdd;

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
	// the test program at $FC00D2 (the reset pc), in both 256 KB halves (no rom loader, so no
	// Kickstart mirror), assembled by hand:
	//   lea     $DA8000,a0          ; Gayle, signed displacements reach $DA0000-$DAFFFF
	//   move.w  #$8000,$2000(a0)    ; $DAA000 intena
	//   move.b  #$E0,$A018(a0)      ; $DA2018 device/head: LBA, master
	//   move.b  #$EC,$A01C(a0)      ; $DA201C command: IDENTIFY
	// w1: btst  #7,$1000(a0)        ; $DA9000 intreq
	//   beq.s   w1
	//   move.b  $A01C(a0),d0        ; status (clears the interrupt)
	//   lea     $C00000,a1          ; slow ram
	//   move.w  #255,d1
	// l1: move.w $A000(a0),(a1)+    ; $DA2000 data
	//   dbra    d1,l1
	//   move.b  d0,(a1)             ; status at $C00200
	//   move.b  #1,$A008(a0)        ; sector count 1
	//   move.b  #3,$A00C(a0)        ; LBA 3
	//   move.b  #$30,$A01C(a0)      ; WRITE SECTORS
	// w2: move.b $B018(a0),d0       ; $DA3018 alternate status
	//   btst    #3,d0               ; DRQ (no interrupt for the first one)
	//   beq.s   w2
	//   lea     $C00000,a1
	//   move.w  #255,d1
	// l2: move.w (a1)+,$A000(a0)
	//   dbra    d1,l2
	// w3: btst  #7,$1000(a0)        ; the interrupt after the sector
	//   beq.s   w3
	//   move.w  #$0F00,$DFF180      ; COLOR00: done
	//   bra.s   *
	sram_hi[21'h1C0069] = 8'h41; sram_lo[21'h1C0069] = 8'hF9;
	sram_hi[21'h1E0069] = 8'h41; sram_lo[21'h1E0069] = 8'hF9;
	sram_hi[21'h1C006A] = 8'h00; sram_lo[21'h1C006A] = 8'hDA;
	sram_hi[21'h1E006A] = 8'h00; sram_lo[21'h1E006A] = 8'hDA;
	sram_hi[21'h1C006B] = 8'h80; sram_lo[21'h1C006B] = 8'h00;
	sram_hi[21'h1E006B] = 8'h80; sram_lo[21'h1E006B] = 8'h00;
	sram_hi[21'h1C006C] = 8'h31; sram_lo[21'h1C006C] = 8'h7C;
	sram_hi[21'h1E006C] = 8'h31; sram_lo[21'h1E006C] = 8'h7C;
	sram_hi[21'h1C006D] = 8'h80; sram_lo[21'h1C006D] = 8'h00;
	sram_hi[21'h1E006D] = 8'h80; sram_lo[21'h1E006D] = 8'h00;
	sram_hi[21'h1C006E] = 8'h20; sram_lo[21'h1C006E] = 8'h00;
	sram_hi[21'h1E006E] = 8'h20; sram_lo[21'h1E006E] = 8'h00;
	sram_hi[21'h1C006F] = 8'h11; sram_lo[21'h1C006F] = 8'h7C;
	sram_hi[21'h1E006F] = 8'h11; sram_lo[21'h1E006F] = 8'h7C;
	sram_hi[21'h1C0070] = 8'h00; sram_lo[21'h1C0070] = 8'hE0;
	sram_hi[21'h1E0070] = 8'h00; sram_lo[21'h1E0070] = 8'hE0;
	sram_hi[21'h1C0071] = 8'hA0; sram_lo[21'h1C0071] = 8'h18;
	sram_hi[21'h1E0071] = 8'hA0; sram_lo[21'h1E0071] = 8'h18;
	sram_hi[21'h1C0072] = 8'h11; sram_lo[21'h1C0072] = 8'h7C;
	sram_hi[21'h1E0072] = 8'h11; sram_lo[21'h1E0072] = 8'h7C;
	sram_hi[21'h1C0073] = 8'h00; sram_lo[21'h1C0073] = 8'hEC;
	sram_hi[21'h1E0073] = 8'h00; sram_lo[21'h1E0073] = 8'hEC;
	sram_hi[21'h1C0074] = 8'hA0; sram_lo[21'h1C0074] = 8'h1C;
	sram_hi[21'h1E0074] = 8'hA0; sram_lo[21'h1E0074] = 8'h1C;
	sram_hi[21'h1C0075] = 8'h08; sram_lo[21'h1C0075] = 8'h28;
	sram_hi[21'h1E0075] = 8'h08; sram_lo[21'h1E0075] = 8'h28;
	sram_hi[21'h1C0076] = 8'h00; sram_lo[21'h1C0076] = 8'h07;
	sram_hi[21'h1E0076] = 8'h00; sram_lo[21'h1E0076] = 8'h07;
	sram_hi[21'h1C0077] = 8'h10; sram_lo[21'h1C0077] = 8'h00;
	sram_hi[21'h1E0077] = 8'h10; sram_lo[21'h1E0077] = 8'h00;
	sram_hi[21'h1C0078] = 8'h67; sram_lo[21'h1C0078] = 8'hF8;
	sram_hi[21'h1E0078] = 8'h67; sram_lo[21'h1E0078] = 8'hF8;
	sram_hi[21'h1C0079] = 8'h10; sram_lo[21'h1C0079] = 8'h28;
	sram_hi[21'h1E0079] = 8'h10; sram_lo[21'h1E0079] = 8'h28;
	sram_hi[21'h1C007A] = 8'hA0; sram_lo[21'h1C007A] = 8'h1C;
	sram_hi[21'h1E007A] = 8'hA0; sram_lo[21'h1E007A] = 8'h1C;
	sram_hi[21'h1C007B] = 8'h43; sram_lo[21'h1C007B] = 8'hF9;
	sram_hi[21'h1E007B] = 8'h43; sram_lo[21'h1E007B] = 8'hF9;
	sram_hi[21'h1C007C] = 8'h00; sram_lo[21'h1C007C] = 8'hC0;
	sram_hi[21'h1E007C] = 8'h00; sram_lo[21'h1E007C] = 8'hC0;
	sram_hi[21'h1C007D] = 8'h00; sram_lo[21'h1C007D] = 8'h00;
	sram_hi[21'h1E007D] = 8'h00; sram_lo[21'h1E007D] = 8'h00;
	sram_hi[21'h1C007E] = 8'h32; sram_lo[21'h1C007E] = 8'h3C;
	sram_hi[21'h1E007E] = 8'h32; sram_lo[21'h1E007E] = 8'h3C;
	sram_hi[21'h1C007F] = 8'h00; sram_lo[21'h1C007F] = 8'hFF;
	sram_hi[21'h1E007F] = 8'h00; sram_lo[21'h1E007F] = 8'hFF;
	sram_hi[21'h1C0080] = 8'h32; sram_lo[21'h1C0080] = 8'hE8;
	sram_hi[21'h1E0080] = 8'h32; sram_lo[21'h1E0080] = 8'hE8;
	sram_hi[21'h1C0081] = 8'hA0; sram_lo[21'h1C0081] = 8'h00;
	sram_hi[21'h1E0081] = 8'hA0; sram_lo[21'h1E0081] = 8'h00;
	sram_hi[21'h1C0082] = 8'h51; sram_lo[21'h1C0082] = 8'hC9;
	sram_hi[21'h1E0082] = 8'h51; sram_lo[21'h1E0082] = 8'hC9;
	sram_hi[21'h1C0083] = 8'hFF; sram_lo[21'h1C0083] = 8'hFA;
	sram_hi[21'h1E0083] = 8'hFF; sram_lo[21'h1E0083] = 8'hFA;
	sram_hi[21'h1C0084] = 8'h12; sram_lo[21'h1C0084] = 8'h80;
	sram_hi[21'h1E0084] = 8'h12; sram_lo[21'h1E0084] = 8'h80;
	sram_hi[21'h1C0085] = 8'h11; sram_lo[21'h1C0085] = 8'h7C;
	sram_hi[21'h1E0085] = 8'h11; sram_lo[21'h1E0085] = 8'h7C;
	sram_hi[21'h1C0086] = 8'h00; sram_lo[21'h1C0086] = 8'h01;
	sram_hi[21'h1E0086] = 8'h00; sram_lo[21'h1E0086] = 8'h01;
	sram_hi[21'h1C0087] = 8'hA0; sram_lo[21'h1C0087] = 8'h08;
	sram_hi[21'h1E0087] = 8'hA0; sram_lo[21'h1E0087] = 8'h08;
	sram_hi[21'h1C0088] = 8'h11; sram_lo[21'h1C0088] = 8'h7C;
	sram_hi[21'h1E0088] = 8'h11; sram_lo[21'h1E0088] = 8'h7C;
	sram_hi[21'h1C0089] = 8'h00; sram_lo[21'h1C0089] = 8'h03;
	sram_hi[21'h1E0089] = 8'h00; sram_lo[21'h1E0089] = 8'h03;
	sram_hi[21'h1C008A] = 8'hA0; sram_lo[21'h1C008A] = 8'h0C;
	sram_hi[21'h1E008A] = 8'hA0; sram_lo[21'h1E008A] = 8'h0C;
	sram_hi[21'h1C008B] = 8'h11; sram_lo[21'h1C008B] = 8'h7C;
	sram_hi[21'h1E008B] = 8'h11; sram_lo[21'h1E008B] = 8'h7C;
	sram_hi[21'h1C008C] = 8'h00; sram_lo[21'h1C008C] = 8'h30;
	sram_hi[21'h1E008C] = 8'h00; sram_lo[21'h1E008C] = 8'h30;
	sram_hi[21'h1C008D] = 8'hA0; sram_lo[21'h1C008D] = 8'h1C;
	sram_hi[21'h1E008D] = 8'hA0; sram_lo[21'h1E008D] = 8'h1C;
	sram_hi[21'h1C008E] = 8'h10; sram_lo[21'h1C008E] = 8'h28;
	sram_hi[21'h1E008E] = 8'h10; sram_lo[21'h1E008E] = 8'h28;
	sram_hi[21'h1C008F] = 8'hB0; sram_lo[21'h1C008F] = 8'h18;
	sram_hi[21'h1E008F] = 8'hB0; sram_lo[21'h1E008F] = 8'h18;
	sram_hi[21'h1C0090] = 8'h08; sram_lo[21'h1C0090] = 8'h00;
	sram_hi[21'h1E0090] = 8'h08; sram_lo[21'h1E0090] = 8'h00;
	sram_hi[21'h1C0091] = 8'h00; sram_lo[21'h1C0091] = 8'h03;
	sram_hi[21'h1E0091] = 8'h00; sram_lo[21'h1E0091] = 8'h03;
	sram_hi[21'h1C0092] = 8'h67; sram_lo[21'h1C0092] = 8'hF6;
	sram_hi[21'h1E0092] = 8'h67; sram_lo[21'h1E0092] = 8'hF6;
	sram_hi[21'h1C0093] = 8'h43; sram_lo[21'h1C0093] = 8'hF9;
	sram_hi[21'h1E0093] = 8'h43; sram_lo[21'h1E0093] = 8'hF9;
	sram_hi[21'h1C0094] = 8'h00; sram_lo[21'h1C0094] = 8'hC0;
	sram_hi[21'h1E0094] = 8'h00; sram_lo[21'h1E0094] = 8'hC0;
	sram_hi[21'h1C0095] = 8'h00; sram_lo[21'h1C0095] = 8'h00;
	sram_hi[21'h1E0095] = 8'h00; sram_lo[21'h1E0095] = 8'h00;
	sram_hi[21'h1C0096] = 8'h32; sram_lo[21'h1C0096] = 8'h3C;
	sram_hi[21'h1E0096] = 8'h32; sram_lo[21'h1E0096] = 8'h3C;
	sram_hi[21'h1C0097] = 8'h00; sram_lo[21'h1C0097] = 8'hFF;
	sram_hi[21'h1E0097] = 8'h00; sram_lo[21'h1E0097] = 8'hFF;
	sram_hi[21'h1C0098] = 8'h31; sram_lo[21'h1C0098] = 8'h59;
	sram_hi[21'h1E0098] = 8'h31; sram_lo[21'h1E0098] = 8'h59;
	sram_hi[21'h1C0099] = 8'hA0; sram_lo[21'h1C0099] = 8'h00;
	sram_hi[21'h1E0099] = 8'hA0; sram_lo[21'h1E0099] = 8'h00;
	sram_hi[21'h1C009A] = 8'h51; sram_lo[21'h1C009A] = 8'hC9;
	sram_hi[21'h1E009A] = 8'h51; sram_lo[21'h1E009A] = 8'hC9;
	sram_hi[21'h1C009B] = 8'hFF; sram_lo[21'h1C009B] = 8'hFA;
	sram_hi[21'h1E009B] = 8'hFF; sram_lo[21'h1E009B] = 8'hFA;
	sram_hi[21'h1C009C] = 8'h08; sram_lo[21'h1C009C] = 8'h28;
	sram_hi[21'h1E009C] = 8'h08; sram_lo[21'h1E009C] = 8'h28;
	sram_hi[21'h1C009D] = 8'h00; sram_lo[21'h1C009D] = 8'h07;
	sram_hi[21'h1E009D] = 8'h00; sram_lo[21'h1E009D] = 8'h07;
	sram_hi[21'h1C009E] = 8'h10; sram_lo[21'h1C009E] = 8'h00;
	sram_hi[21'h1E009E] = 8'h10; sram_lo[21'h1E009E] = 8'h00;
	sram_hi[21'h1C009F] = 8'h67; sram_lo[21'h1C009F] = 8'hF8;
	sram_hi[21'h1E009F] = 8'h67; sram_lo[21'h1E009F] = 8'hF8;
	sram_hi[21'h1C00A0] = 8'h33; sram_lo[21'h1C00A0] = 8'hFC;
	sram_hi[21'h1E00A0] = 8'h33; sram_lo[21'h1E00A0] = 8'hFC;
	sram_hi[21'h1C00A1] = 8'h0F; sram_lo[21'h1C00A1] = 8'h00;
	sram_hi[21'h1E00A1] = 8'h0F; sram_lo[21'h1E00A1] = 8'h00;
	sram_hi[21'h1C00A2] = 8'h00; sram_lo[21'h1C00A2] = 8'hDF;
	sram_hi[21'h1E00A2] = 8'h00; sram_lo[21'h1E00A2] = 8'hDF;
	sram_hi[21'h1C00A3] = 8'hF1; sram_lo[21'h1C00A3] = 8'h80;
	sram_hi[21'h1E00A3] = 8'hF1; sram_lo[21'h1E00A3] = 8'h80;
	sram_hi[21'h1C00A4] = 8'h60; sram_lo[21'h1C00A4] = 8'hFE;
	sram_hi[21'h1E00A4] = 8'h60; sram_lo[21'h1E00A4] = 8'hFE;
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

// ---------------- ATA device model ----------------

localparam BUSY_NS = 3000;
reg [7:0] disk [0:64*512-1];
reg [7:0] r_err = 8'h00, r_count = 8'h01, r_sector = 8'h01, r_cyl_lo = 8'h00, r_cyl_hi = 8'h00, r_head = 8'h00;
reg [7:0] r_status = 8'h50;
reg [15:0] rd_word;
reg drive = 1'b0;
integer lba, left, blk, wpos, mult = 1, k;
reg [7:0] cmd;
reg [15:0] ident [0:255];

assign cf_bus = drive ? rd_word : 16'bzzzzzzzzzzzzzzzz;

initial begin
	for (k = 0; k < 64*512; k = k + 1) disk[k] = (k / 512) * 7 + k;
	for (k = 0; k < 256; k = k + 1) ident[k] = 16'h1000 + k;
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
				if (wpos == 512) next_block_out;
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
			r_status = 8'hD0; // BSY
			#(BUSY_NS) r_status = 8'h58;
		end
	end
endtask

task next_block_out;
	begin
		lba = lba + 1;
		left = left - 1;
		wpos = 0;
		r_status = 8'hD0;
		#(BUSY_NS) r_status = (left == 0) ? 8'h50 : 8'h58;
	end
endtask


// ---------------- monitors ----------------

// minimig_syscontrol holds the reset for 4 frames (80 ms): count on every 7 MHz clock instead
initial begin
	wait (dut.cpu_reset === 1'b0);
	force dut.nanomig.minimig.CONTROL1.cnt = 1'b1;
	#5000;
	release dut.nanomig.minimig.CONTROL1.cnt;
end

// the first cpu bus cycles after the reset
integer ncyc = 0;
reg as_d = 1'b1;
always @(posedge dut.clk_sys) begin
	as_d <= dut.nanomig.chip_as;
	if (as_d && !dut.nanomig.chip_as && !dut.cpu_reset && ncyc < 80) begin
		ncyc = ncyc + 1;
		#1 $display("%t cpu %s %06x uds/lds %b%b dout %04x", $time,
			dut.nanomig.chip_rw ? "rd" : "wr", { dut.nanomig.chip_addr, 1'b0 },
			dut.nanomig.chip_uds, dut.nanomig.chip_lds, dut.nanomig.chip_din);
	end
end

integer ncf = 0;
always @(negedge cf_rd_n or negedge cf_wr_n) if (ncf < 30) begin
	ncf = ncf + 1;
	#60 $display("%t cf %s cs %b a %0d data %04x", $time, cf_rd_n ? "wr" : "rd", cf_cs_n, cf_a, cf_bus);
end
always @(dut.nanomig.minimig.GAYLE1.intrq) $display("%t gayle intrq %b", $time, dut.nanomig.minimig.GAYLE1.intrq);

reg done = 1'b0;
always @(posedge dut.clk_sys)
	if (dut.nanomig.chip_as == 1'b0 && dut.nanomig.chip_rw == 1'b0 && { dut.nanomig.chip_addr, 1'b0 } == 24'hDFF180 && !done) begin
		done = 1'b1;
		$display("%t COLOR00 written: the program got to its end", $time);
	end

// ---------------- stimulus ----------------

integer w;
initial begin
	#200000; // pll lock
	frame(8'h05, 8'h0C, 8'h01);   // HDD = CF card (osd item 12)
	frame(8'hFE, 8'h00, 8'h00);   // init done -> reset released
	$display("%t init done, sw_hdd %b", $time, dut.sw_hdd);
	w = 0;
	while (!done && w < 4000) begin #1000; w = w + 1; end
	check("program done", done, 1'b1);
	check("status after identify", sram_hi[21'h100100], 8'h58);
	for (w = 0; w < 256; w = w + 1) begin
		check("identify in memory hi", sram_hi[21'h100000 + w], ident[w][7:0]);
		check("identify in memory lo", sram_lo[21'h100000 + w], ident[w][15:8]);
		check("card byte 0", disk[3*512 + 2*w], ident[w][7:0]);
		check("card byte 1", disk[3*512 + 2*w + 1], ident[w][15:8]);
	end
	$display("tb_hdd: %0d errors", errors);
	$finish;
end

endmodule
