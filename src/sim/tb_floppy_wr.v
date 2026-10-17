`timescale 1ns / 1ps

// paula_floppy.v writing a track: the MFM words of build/floppy_wr/track.hex (mfm_track.py: 11
// sectors of an ADF track, as trackdisk.device writes them) go in by disk dma (dmas -> DSKDAT,
// DMA_INTERVAL clocks apart). The sdc model takes each sector at once and then stays busy
// WRITE_TIME clocks, every 4th sector SLOW_TIME (the sd card of the mcu now and then takes long).
// Every sector written is compared with the ADF; all 11 have to come.
// Ends with "tb_floppy_wr: N errors".

module tb_floppy_wr;

parameter DMA_INTERVAL = 600;      // a real Amiga: 3 disk dma words per line
parameter WRITE_TIME = 140000;     // 5 ms
parameter SLOW_TIME = 2000000;     // 70 ms
parameter TRACK = 1;
parameter NWORDS = 6056;

reg clk = 1'b0;
always #17.65 clk = ~clk;

reg [1:0] ph = 2'd0;
always @(posedge clk) ph <= ph + 2'd1;
wire clk7_en = (ph == 2'd3);
wire clk7n_en = (ph == 2'd1);

reg reset = 1'b1;
reg [8:1] reg_addr = 8'hFF;
reg [15:0] reg_data = 16'h0000;
wire [15:0] data_out;
wire dmal, dmas, blckint, syncint;

reg [3:0] mounted = 4'd0;
wire [3:0] sdc_rd, sdc_wr;
wire [31:0] sdc_sector;
reg sdc_busy = 1'b0, sdc_done = 1'b0;
reg [8:0] sdc_addr = 9'd0;
wire [7:0] sdc_out;

paula_floppy dut(
	.clk(clk), .clk7_en(clk7_en), .clk7n_en(clk7n_en), .reset(reset), .ntsc(1'b0), .sof(1'b0),
	.enable(1'b1), .reg_address_in(reg_addr), .data_in(reg_data), .data_out(data_out),
	.dmal(dmal), .dmas(dmas),
	._step(1'b1), .direc(1'b0), ._sel(4'b1110), .side(TRACK % 2 ? 1'b0 : 1'b1), ._motor(1'b0),
	._track0(), ._change(), ._ready(), ._wprot(), .index(),
	.blckint(blckint), .syncint(syncint), .wordsync(1'b1),
	.fdd_led(), .floppy_drives(2'd1), .floppy_wrprot(1'b0),
	.sdc_image_mounted(mounted), .sdc_image_size(32'd901120),
	.sdc_rd(sdc_rd), .sdc_wr(sdc_wr), .sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done),
	.sdc_byte_in_strobe(1'b0), .sdc_byte_addr(sdc_addr), .sdc_byte_in_data(8'h00),
	.sdc_byte_out_data(sdc_out),
	.precomp(2'b00), .floppy_ext(8'd0), .floppy_ext_chg(4'd0), .fdd_in(4'd0), .fdd_out()
);

reg [7:0] adf [0:22527];        // tracks 0..3
initial $readmemh("adf.hex", adf);
reg [15:0] track [0:8191];
initial $readmemh("track.hex", track);

integer errors = 0;
integer nwritten = 0;
reg written [0:10];
integer k, sec, bad = 0;
reg [7:0] b;

// ---------------- sdc model (as img_sdc: copy at once, then the slow mcu write) ----------------
initial begin
	for (k = 0; k < 11; k = k + 1) written[k] = 0;
	forever begin
		@(posedge clk);
		if (sdc_wr[0]) begin
			sdc_busy <= 1'b1;
			sec = sdc_sector - TRACK * 11;
			for (k = 0; k < 512; k = k + 1) begin
				@(posedge clk) sdc_addr <= k;
				repeat (3) @(posedge clk);
				b = sdc_out;
				if (sec < 0 || sec > 10 || b !== adf[sdc_sector * 512 + k]) begin
					bad = bad + 1;
					if (errors < 10) $display("ERROR: sector %0d byte %0d %02x, adf %02x", sdc_sector, k, b, adf[sdc_sector * 512 + k]);
					errors = errors + 1;
				end
			end
			$display("%t sector %0d written (track sector %0d), %0d bad bytes", $time, sdc_sector, sec, bad);
			bad = 0;
			nwritten = nwritten + 1;
			if (sec >= 0 && sec <= 10) begin
				if (written[sec]) begin $display("ERROR: sector %0d twice", sec); errors = errors + 1; end
				written[sec] = 1;
			end
			repeat ((nwritten % 4 == 2) ? SLOW_TIME : WRITE_TIME) @(posedge clk);
			sdc_busy <= 1'b0;
			sdc_done <= 1'b1;
			@(posedge clk) sdc_done <= 1'b0;
		end
	end
end

// ---------------- register writes and disk dma (one 7 MHz cycle each) ----------------
task reg_write(input [8:0] a, input [15:0] d);
	begin
		@(posedge clk); while (!clk7_en) @(posedge clk);
		reg_addr <= a[8:1];
		reg_data <= d;
		@(posedge clk); while (!clk7_en) @(posedge clk);
		reg_addr <= 8'hFF;
	end
endtask

integer nwords = 0;
integer dma_wait = 0;
reg dma_on = 1'b0;
always @(posedge clk) begin
	if (dma_wait != 0) dma_wait <= dma_wait - 1;
	if (clk7_en) begin
		if (dma_on && dmas && reg_addr == 8'hFF && dma_wait == 0 && nwords < NWORDS) begin
			reg_addr <= 9'h026 >> 1; // DSKDAT
			reg_data <= track[nwords];
			nwords <= nwords + 1;
			dma_wait <= DMA_INTERVAL;
		end
		else if (reg_addr == (9'h026 >> 1))
			reg_addr <= 8'hFF;
	end
end

initial begin
	#1000;
	dut.cpu_wr_state = 4'd0; // no reset either (XST: 0, ISim: X)
	dut.fd_dma_buffer_trigger_wr = 1'b0;
	dut.dsktrack[0] = TRACK / 2; dut.dsktrack[1] = 7'd0; dut.dsktrack[2] = 7'd0; dut.dsktrack[3] = 7'd0;
	repeat (10) @(posedge clk);
	reset <= 1'b0;
	repeat (20) @(posedge clk);
	@(posedge clk) mounted <= 4'b0001;
	@(posedge clk) mounted <= 4'b0000;
	repeat (100) @(posedge clk);
	reg_write(9'h024, 16'h0000);
	reg_write(9'h024, 16'hC000 | NWORDS); // DSKLEN: write
	reg_write(9'h024, 16'hC000 | NWORDS); // the second write starts the dma
	dma_on = 1'b1;
	wait (blckint);
	$display("%t blckint, %0d words sent, %0d sectors written so far", $time, nwords, nwritten);
	dma_on = 1'b0;
	// the sector writes still going on after the dma
	repeat (8000000) @(posedge clk);
	for (k = 0; k < 11; k = k + 1)
		if (!written[k]) begin $display("ERROR: track sector %0d not written", k); errors = errors + 1; end
	$display("tb_floppy_wr: %0d errors", errors);
	$finish;
end

initial begin
	#2000000000;
	$display("ERROR: timeout, %0d words sent, %0d sectors written", nwords, nwritten);
	$display("tb_floppy_wr: 1 errors");
	$finish;
end

endmodule
