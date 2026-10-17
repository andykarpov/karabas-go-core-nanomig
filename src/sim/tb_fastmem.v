`timescale 1ns / 1ps

// Fast RAM through the whole Mini G top: OSD Fast RAM = 8M (soft switch 11), the sdram of the
// board as a model of the MT48LC16M16A2 on SDR_CLK (the commands checked as in tb_fastram.v, the
// read data with tAC / tOH). A 68000 program in place of the Kickstart code at $FC00D2 (in the
// SRAM model) does the autoconfig (the Toccata card first, then the Zorro II RAM at $200000),
// writes a long to $200000, a word to $9FFFFE (the end of 8 MB, a23 set) and a byte to $200011,
// writes a routine into fast ram and runs it there (instruction fetch, addq.w on memory, a long
// copy), copies the results back into slow ram ($C00000) and writes COLOR00.
// Checks the sdram contents (byte order: even byte = DQ[15:8]) and what the cpu read back.
// Ends with "tb_fastmem: N errors".

module tb_fastmem;

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
	//   lea     $E80000,a0
	//   move.b  #$E9,$48(a0)        ; the Toccata card (first)
	//   move.b  #$20,$48(a0)        ; the Zorro II RAM at $200000
	//   lea     $200000,a1
	//   lea     $9FFFFE,a2
	//   move.l  #$12345678,(a1)
	//   move.w  #$ABCD,(a2)
	//   move.b  #$5A,$11(a1)        ; odd byte
	//   lea     $200100,a3          ; a routine in fast ram:
	//   move.l  #$52690010,(a3)+    ;   addq.w #1,$10(a1)
	//   move.l  #$20112340,(a3)+    ;   move.l (a1),d0
	//   move.l  #$00044EF9,(a3)+    ;   move.l d0,4(a1)
	//   move.l  #$00FC0124,(a3)+    ;   jmp    back
	//   jmp     $200100
	// back:
	//   move.l  (a1),$C00000
	//   move.w  (a2),$C00004
	//   move.w  $10(a1),$C00006
	//   move.l  4(a1),$C00008
	//   move.w  #$0F00,$DFF180      ; COLOR00: done
	//   bra.s   *
	sram_hi[21'h1C0069] = 8'h41; sram_lo[21'h1C0069] = 8'hF9;
	sram_hi[21'h1E0069] = 8'h41; sram_lo[21'h1E0069] = 8'hF9;
	sram_hi[21'h1C006A] = 8'h00; sram_lo[21'h1C006A] = 8'hE8;
	sram_hi[21'h1E006A] = 8'h00; sram_lo[21'h1E006A] = 8'hE8;
	sram_hi[21'h1C006B] = 8'h00; sram_lo[21'h1C006B] = 8'h00;
	sram_hi[21'h1E006B] = 8'h00; sram_lo[21'h1E006B] = 8'h00;
	sram_hi[21'h1C006C] = 8'h11; sram_lo[21'h1C006C] = 8'h7C;
	sram_hi[21'h1E006C] = 8'h11; sram_lo[21'h1E006C] = 8'h7C;
	sram_hi[21'h1C006D] = 8'h00; sram_lo[21'h1C006D] = 8'hE9;
	sram_hi[21'h1E006D] = 8'h00; sram_lo[21'h1E006D] = 8'hE9;
	sram_hi[21'h1C006E] = 8'h00; sram_lo[21'h1C006E] = 8'h48;
	sram_hi[21'h1E006E] = 8'h00; sram_lo[21'h1E006E] = 8'h48;
	sram_hi[21'h1C006F] = 8'h11; sram_lo[21'h1C006F] = 8'h7C;
	sram_hi[21'h1E006F] = 8'h11; sram_lo[21'h1E006F] = 8'h7C;
	sram_hi[21'h1C0070] = 8'h00; sram_lo[21'h1C0070] = 8'h20;
	sram_hi[21'h1E0070] = 8'h00; sram_lo[21'h1E0070] = 8'h20;
	sram_hi[21'h1C0071] = 8'h00; sram_lo[21'h1C0071] = 8'h48;
	sram_hi[21'h1E0071] = 8'h00; sram_lo[21'h1E0071] = 8'h48;
	sram_hi[21'h1C0072] = 8'h43; sram_lo[21'h1C0072] = 8'hF9;
	sram_hi[21'h1E0072] = 8'h43; sram_lo[21'h1E0072] = 8'hF9;
	sram_hi[21'h1C0073] = 8'h00; sram_lo[21'h1C0073] = 8'h20;
	sram_hi[21'h1E0073] = 8'h00; sram_lo[21'h1E0073] = 8'h20;
	sram_hi[21'h1C0074] = 8'h00; sram_lo[21'h1C0074] = 8'h00;
	sram_hi[21'h1E0074] = 8'h00; sram_lo[21'h1E0074] = 8'h00;
	sram_hi[21'h1C0075] = 8'h45; sram_lo[21'h1C0075] = 8'hF9;
	sram_hi[21'h1E0075] = 8'h45; sram_lo[21'h1E0075] = 8'hF9;
	sram_hi[21'h1C0076] = 8'h00; sram_lo[21'h1C0076] = 8'h9F;
	sram_hi[21'h1E0076] = 8'h00; sram_lo[21'h1E0076] = 8'h9F;
	sram_hi[21'h1C0077] = 8'hFF; sram_lo[21'h1C0077] = 8'hFE;
	sram_hi[21'h1E0077] = 8'hFF; sram_lo[21'h1E0077] = 8'hFE;
	sram_hi[21'h1C0078] = 8'h22; sram_lo[21'h1C0078] = 8'hBC;
	sram_hi[21'h1E0078] = 8'h22; sram_lo[21'h1E0078] = 8'hBC;
	sram_hi[21'h1C0079] = 8'h12; sram_lo[21'h1C0079] = 8'h34;
	sram_hi[21'h1E0079] = 8'h12; sram_lo[21'h1E0079] = 8'h34;
	sram_hi[21'h1C007A] = 8'h56; sram_lo[21'h1C007A] = 8'h78;
	sram_hi[21'h1E007A] = 8'h56; sram_lo[21'h1E007A] = 8'h78;
	sram_hi[21'h1C007B] = 8'h34; sram_lo[21'h1C007B] = 8'hBC;
	sram_hi[21'h1E007B] = 8'h34; sram_lo[21'h1E007B] = 8'hBC;
	sram_hi[21'h1C007C] = 8'hAB; sram_lo[21'h1C007C] = 8'hCD;
	sram_hi[21'h1E007C] = 8'hAB; sram_lo[21'h1E007C] = 8'hCD;
	sram_hi[21'h1C007D] = 8'h13; sram_lo[21'h1C007D] = 8'h7C;
	sram_hi[21'h1E007D] = 8'h13; sram_lo[21'h1E007D] = 8'h7C;
	sram_hi[21'h1C007E] = 8'h00; sram_lo[21'h1C007E] = 8'h5A;
	sram_hi[21'h1E007E] = 8'h00; sram_lo[21'h1E007E] = 8'h5A;
	sram_hi[21'h1C007F] = 8'h00; sram_lo[21'h1C007F] = 8'h11;
	sram_hi[21'h1E007F] = 8'h00; sram_lo[21'h1E007F] = 8'h11;
	sram_hi[21'h1C0080] = 8'h47; sram_lo[21'h1C0080] = 8'hF9;
	sram_hi[21'h1E0080] = 8'h47; sram_lo[21'h1E0080] = 8'hF9;
	sram_hi[21'h1C0081] = 8'h00; sram_lo[21'h1C0081] = 8'h20;
	sram_hi[21'h1E0081] = 8'h00; sram_lo[21'h1E0081] = 8'h20;
	sram_hi[21'h1C0082] = 8'h01; sram_lo[21'h1C0082] = 8'h00;
	sram_hi[21'h1E0082] = 8'h01; sram_lo[21'h1E0082] = 8'h00;
	sram_hi[21'h1C0083] = 8'h26; sram_lo[21'h1C0083] = 8'hFC;
	sram_hi[21'h1E0083] = 8'h26; sram_lo[21'h1E0083] = 8'hFC;
	sram_hi[21'h1C0084] = 8'h52; sram_lo[21'h1C0084] = 8'h69;
	sram_hi[21'h1E0084] = 8'h52; sram_lo[21'h1E0084] = 8'h69;
	sram_hi[21'h1C0085] = 8'h00; sram_lo[21'h1C0085] = 8'h10;
	sram_hi[21'h1E0085] = 8'h00; sram_lo[21'h1E0085] = 8'h10;
	sram_hi[21'h1C0086] = 8'h26; sram_lo[21'h1C0086] = 8'hFC;
	sram_hi[21'h1E0086] = 8'h26; sram_lo[21'h1E0086] = 8'hFC;
	sram_hi[21'h1C0087] = 8'h20; sram_lo[21'h1C0087] = 8'h11;
	sram_hi[21'h1E0087] = 8'h20; sram_lo[21'h1E0087] = 8'h11;
	sram_hi[21'h1C0088] = 8'h23; sram_lo[21'h1C0088] = 8'h40;
	sram_hi[21'h1E0088] = 8'h23; sram_lo[21'h1E0088] = 8'h40;
	sram_hi[21'h1C0089] = 8'h26; sram_lo[21'h1C0089] = 8'hFC;
	sram_hi[21'h1E0089] = 8'h26; sram_lo[21'h1E0089] = 8'hFC;
	sram_hi[21'h1C008A] = 8'h00; sram_lo[21'h1C008A] = 8'h04;
	sram_hi[21'h1E008A] = 8'h00; sram_lo[21'h1E008A] = 8'h04;
	sram_hi[21'h1C008B] = 8'h4E; sram_lo[21'h1C008B] = 8'hF9;
	sram_hi[21'h1E008B] = 8'h4E; sram_lo[21'h1E008B] = 8'hF9;
	sram_hi[21'h1C008C] = 8'h26; sram_lo[21'h1C008C] = 8'hFC;
	sram_hi[21'h1E008C] = 8'h26; sram_lo[21'h1E008C] = 8'hFC;
	sram_hi[21'h1C008D] = 8'h00; sram_lo[21'h1C008D] = 8'hFC;
	sram_hi[21'h1E008D] = 8'h00; sram_lo[21'h1E008D] = 8'hFC;
	sram_hi[21'h1C008E] = 8'h01; sram_lo[21'h1C008E] = 8'h24;
	sram_hi[21'h1E008E] = 8'h01; sram_lo[21'h1E008E] = 8'h24;
	sram_hi[21'h1C008F] = 8'h4E; sram_lo[21'h1C008F] = 8'hF9;
	sram_hi[21'h1E008F] = 8'h4E; sram_lo[21'h1E008F] = 8'hF9;
	sram_hi[21'h1C0090] = 8'h00; sram_lo[21'h1C0090] = 8'h20;
	sram_hi[21'h1E0090] = 8'h00; sram_lo[21'h1E0090] = 8'h20;
	sram_hi[21'h1C0091] = 8'h01; sram_lo[21'h1C0091] = 8'h00;
	sram_hi[21'h1E0091] = 8'h01; sram_lo[21'h1E0091] = 8'h00;
	sram_hi[21'h1C0092] = 8'h23; sram_lo[21'h1C0092] = 8'hD1;
	sram_hi[21'h1E0092] = 8'h23; sram_lo[21'h1E0092] = 8'hD1;
	sram_hi[21'h1C0093] = 8'h00; sram_lo[21'h1C0093] = 8'hC0;
	sram_hi[21'h1E0093] = 8'h00; sram_lo[21'h1E0093] = 8'hC0;
	sram_hi[21'h1C0094] = 8'h00; sram_lo[21'h1C0094] = 8'h00;
	sram_hi[21'h1E0094] = 8'h00; sram_lo[21'h1E0094] = 8'h00;
	sram_hi[21'h1C0095] = 8'h33; sram_lo[21'h1C0095] = 8'hD2;
	sram_hi[21'h1E0095] = 8'h33; sram_lo[21'h1E0095] = 8'hD2;
	sram_hi[21'h1C0096] = 8'h00; sram_lo[21'h1C0096] = 8'hC0;
	sram_hi[21'h1E0096] = 8'h00; sram_lo[21'h1E0096] = 8'hC0;
	sram_hi[21'h1C0097] = 8'h00; sram_lo[21'h1C0097] = 8'h04;
	sram_hi[21'h1E0097] = 8'h00; sram_lo[21'h1E0097] = 8'h04;
	sram_hi[21'h1C0098] = 8'h33; sram_lo[21'h1C0098] = 8'hE9;
	sram_hi[21'h1E0098] = 8'h33; sram_lo[21'h1E0098] = 8'hE9;
	sram_hi[21'h1C0099] = 8'h00; sram_lo[21'h1C0099] = 8'h10;
	sram_hi[21'h1E0099] = 8'h00; sram_lo[21'h1E0099] = 8'h10;
	sram_hi[21'h1C009A] = 8'h00; sram_lo[21'h1C009A] = 8'hC0;
	sram_hi[21'h1E009A] = 8'h00; sram_lo[21'h1E009A] = 8'hC0;
	sram_hi[21'h1C009B] = 8'h00; sram_lo[21'h1C009B] = 8'h06;
	sram_hi[21'h1E009B] = 8'h00; sram_lo[21'h1E009B] = 8'h06;
	sram_hi[21'h1C009C] = 8'h23; sram_lo[21'h1C009C] = 8'hE9;
	sram_hi[21'h1E009C] = 8'h23; sram_lo[21'h1E009C] = 8'hE9;
	sram_hi[21'h1C009D] = 8'h00; sram_lo[21'h1C009D] = 8'h04;
	sram_hi[21'h1E009D] = 8'h00; sram_lo[21'h1E009D] = 8'h04;
	sram_hi[21'h1C009E] = 8'h00; sram_lo[21'h1C009E] = 8'hC0;
	sram_hi[21'h1E009E] = 8'h00; sram_lo[21'h1E009E] = 8'hC0;
	sram_hi[21'h1C009F] = 8'h00; sram_lo[21'h1C009F] = 8'h08;
	sram_hi[21'h1E009F] = 8'h00; sram_lo[21'h1E009F] = 8'h08;
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

// ---------------- SDRAM model (MT48LC16M16A2) ----------------

wire [1:0] sdr_ba, sdr_dqm;
wire [12:0] sdr_a;
wire sdr_clk, sdr_we_n, sdr_cas_n, sdr_ras_n;
wire [15:0] sdr_dq;

integer errors = 0;
task check(input [255:0] what, input [31:0] got, input [31:0] exp);
	if (got !== exp) begin
		errors = errors + 1;
		$display("%t ERROR %0s: %0x, expected %0x", $time, what, got, exp);
	end
endtask
task fail(input [255:0] what);
	begin
		errors = errors + 1;
		if (errors < 30) $display("%t ERROR sdram: %0s", $time, what);
	end
endtask

reg [15:0] sdmem [0:(1<<23)-1]; // word address { row[11:0], bank, column }
reg        b_act [0:3];
reg [12:0] b_row [0:3];
time       b_act_t [0:3];
time       b_pre_t [0:3];
time       last_ref_end = 0;
reg        mode_ok = 1'b0;
integer    n_init_ref = 0, n_rd = 0, n_wr = 0;
reg [15:0] rd_q0, rd_q1;
reg        rd_v0 = 1'b0, rd_v1 = 1'b0;
reg [15:0] dq_drv = 16'hzzzz;
assign sdr_dq = dq_drv;
localparam tRCD = 20, tRAS = 42, tRP = 20, tRC = 60, tWR = 15, tRFC = 66;

integer k;
initial for (k = 0; k < 4; k = k + 1) begin b_act[k] = 0; b_pre_t[k] = 0; b_act_t[k] = 0; end
initial for (k = 0; k < (1<<23); k = k + 1) sdmem[k] = 16'h0000;

function [22:0] maddr(input [1:0] b, input [12:0] r, input [8:0] c);
	maddr = { r[11:0], b, c };
endfunction

always @(posedge sdr_clk) begin
	if (rd_v1) begin
		#2.7 dq_drv = 16'hxxxx;
		#2.7 dq_drv = rd_q1;
	end
	else
		#2.7 dq_drv = 16'hzzzz;
end
reg [2:0] c3;
always @(posedge sdr_clk) begin
	rd_v1 <= rd_v0; rd_q1 <= rd_q0;
	rd_v0 <= 1'b0;
	c3 = { sdr_ras_n, sdr_cas_n, sdr_we_n };
	case (c3)
		3'b011: begin
			if (!mode_ok) fail("ACTIVE before the mode register");
			if (b_act[sdr_ba]) fail("ACTIVE on an active bank");
			if ($time < b_pre_t[sdr_ba]) fail("ACTIVE before tRP");
			if (b_act_t[sdr_ba] != 0 && $time - b_act_t[sdr_ba] < tRC) fail("ACTIVE before tRC");
			if ($time < last_ref_end) fail("ACTIVE before tRFC");
			b_act[sdr_ba] = 1; b_row[sdr_ba] = sdr_a; b_act_t[sdr_ba] = $time;
		end
		3'b101, 3'b100: begin
			if (!b_act[sdr_ba]) fail("READ / WRITE on an idle bank");
			if ($time - b_act_t[sdr_ba] < tRCD) fail("READ / WRITE before tRCD");
			if (!sdr_a[10]) fail("no auto precharge");
			if (c3 == 3'b100) begin
				if (!sdr_dqm[1]) sdmem[maddr(sdr_ba, b_row[sdr_ba], sdr_a[8:0])][15:8] = sdr_dq[15:8];
				if (!sdr_dqm[0]) sdmem[maddr(sdr_ba, b_row[sdr_ba], sdr_a[8:0])][7:0] = sdr_dq[7:0];
				$display("%t sdram write %06x = %04x dqm %b", $time, maddr(sdr_ba, b_row[sdr_ba], sdr_a[8:0]), sdr_dq, sdr_dqm);
				n_wr = n_wr + 1;
				b_pre_t[sdr_ba] = (($time + tWR > b_act_t[sdr_ba] + tRAS) ? $time + tWR : b_act_t[sdr_ba] + tRAS) + tRP;
			end
			else begin
				rd_v0 <= 1'b1; rd_q0 <= sdmem[maddr(sdr_ba, b_row[sdr_ba], sdr_a[8:0])];
				$display("%t sdram read %06x = %04x", $time, maddr(sdr_ba, b_row[sdr_ba], sdr_a[8:0]), sdmem[maddr(sdr_ba, b_row[sdr_ba], sdr_a[8:0])]);
				n_rd = n_rd + 1;
				b_pre_t[sdr_ba] = (($time + 35 > b_act_t[sdr_ba] + tRAS) ? $time + 35 : b_act_t[sdr_ba] + tRAS) + tRP;
			end
			b_act[sdr_ba] = 0;
		end
		3'b010: for (k = 0; k < 4; k = k + 1) begin b_act[k] = 0; b_pre_t[k] = $time + tRP; end
		3'b001: begin
			for (k = 0; k < 4; k = k + 1) if (b_act[k] || $time < b_pre_t[k]) fail("REFRESH with a bank open");
			if ($time < last_ref_end) fail("REFRESH before tRFC");
			last_ref_end = $time + tRFC;
			if (!mode_ok) n_init_ref = n_init_ref + 1;
		end
		3'b000: begin
			if (n_init_ref < 2) fail("mode register before 2 refreshes");
			check("mode register", sdr_a, 13'h020);
			mode_ok = 1;
		end
		default: ;
	endcase
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
	.WD(cf_bus),
	.SDR_BA(sdr_ba),
	.SDR_A(sdr_a),
	.SDR_CLK(sdr_clk),
	.SDR_DQM(sdr_dqm),
	.SDR_WE_N(sdr_we_n),
	.SDR_CAS_N(sdr_cas_n),
	.SDR_RAS_N(sdr_ras_n),
	.SDR_DQ(sdr_dq)
);

// XST starts every flip-flop at 0; ISim starts them at X. The Agnus beam counter has no reset.
initial begin
	#1;
	dut.nanomig.minimig.AGNUS1.bc1.hpos[8:1] = 8'd0;
	dut.nanomig.minimig.AGNUS1.bc1.vpos = 11'd0;
	dut.nanomig.minimig.AGNUS1.bc1.end_of_line = 1'b0;
	dut.nanomig.minimig.AGNUS1.bc1.vpos_inc = 1'b0;
	dut.nanomig.minimig.AGNUS1.bc1.long_line = 1'b0;
end

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

// ---------------- stimulus ----------------

integer w;
initial begin
	#200000; // pll lock
	frame(8'hFD, 8'h00, 8'h00);   // init start
	frame(8'h05, 8'h0B, 8'h03);   // Fast RAM = 8M (osd item 11)
	frame(8'hFE, 8'h00, 8'h00);   // init done -> reset released
	$display("%t init done, fastram_config %b", $time, dut.fastram_config);
	wait (dut.cpu_reset === 1'b0);
	check("sdram ready before the cpu", mode_ok, 1'b1);
	w = 0;
	while (!done && w < 4000) begin #1000; w = w + 1; end
	check("program done", done, 1'b1);
	check("z2 ram on", dut.nanomig.cpu_wrapper.z2ram_ena, 1'b1);
	// $200000 is word 0x100000, $9FFFFE word 0x4FFFFF
	check("sdram $200000", sdmem[23'h100000], 16'h1234);
	check("sdram $200002", sdmem[23'h100001], 16'h5678);
	check("sdram $9FFFFE", sdmem[23'h4FFFFF], 16'hABCD);
	check("sdram $200010 (byte $200011, addq)", sdmem[23'h100008], 16'h005B);
	check("sdram $200004 (copied in fast ram)", { sdmem[23'h100002], sdmem[23'h100003] }, 32'h12345678);
	check("read back $200000", { sram_hi[21'h100000], sram_lo[21'h100000], sram_hi[21'h100001], sram_lo[21'h100001] }, 32'h12345678);
	check("read back $9FFFFE", { sram_hi[21'h100002], sram_lo[21'h100002] }, 16'hABCD);
	check("read back $200010", { sram_hi[21'h100003], sram_lo[21'h100003] }, 16'h005B);
	check("read back $200004", { sram_hi[21'h100004], sram_lo[21'h100004], sram_hi[21'h100005], sram_lo[21'h100005] }, 32'h12345678);
	$display("sdram writes %0d reads %0d", n_wr, n_rd);
	$display("tb_fastmem: %0d errors", errors);
	$finish;
end

endmodule
