`timescale 1ns / 1ps

// paula_floppy.v reading track 0 of a real ADF (build/floppy/adf.hex, first 2 tracks) through
// the sdc_* sector interface, as trackdisk.device does: DSKSYNC 4489, DSKLEN written twice,
// words taken by disk DMA (dmal -> DSKDATR). The MFM stream is decoded: sector headers,
// header / data checksums and the data against the ADF.
// Ends with "tb_floppy: N errors".

module tb_floppy;

// sector service time of the mcu model (clocks before the bytes) and disk dma interval (clocks
// between two dma words; a real Amiga: 3 words per line, ~600 clocks at 28 MHz)
parameter SECTOR_DELAY = 28000;
parameter DMA_INTERVAL = 600;

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
reg sdc_busy = 1'b0, sdc_done = 1'b0, sdc_strobe = 1'b0;
reg [8:0] sdc_addr = 9'd0;
reg [7:0] sdc_data = 8'd0;

paula_floppy dut(
	.clk(clk), .clk7_en(clk7_en), .clk7n_en(clk7n_en), .reset(reset), .ntsc(1'b0), .sof(1'b0),
	.enable(1'b1), .reg_address_in(reg_addr), .data_in(reg_data), .data_out(data_out),
	.dmal(dmal), .dmas(dmas),
	._step(1'b1), .direc(1'b0), ._sel(4'b1110), .side(1'b1), ._motor(1'b0),
	._track0(), ._change(), ._ready(), ._wprot(), .index(),
	.blckint(blckint), .syncint(syncint), .wordsync(1'b1),
	.fdd_led(), .floppy_drives(2'd1), .floppy_wrprot(1'b0),
	.sdc_image_mounted(mounted), .sdc_image_size(32'd901120),
	.sdc_rd(sdc_rd), .sdc_wr(sdc_wr), .sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done),
	.sdc_byte_in_strobe(sdc_strobe), .sdc_byte_addr(sdc_addr), .sdc_byte_in_data(sdc_data),
	.sdc_byte_out_data()
);

// ---------------- adf, sdc model ----------------

reg [7:0] adf [0:11263]; // tracks 0 and 1
initial $readmemh("adf.hex", adf);

integer nreq = 0;
integer k;
initial begin
	forever begin
		@(posedge clk);
		if (sdc_rd[0]) begin
			nreq = nreq + 1;
			if (nreq <= 30) $display("%t sdc read sector %0d", $time, sdc_sector);
			sdc_busy <= 1'b1;
			repeat (SECTOR_DELAY) @(posedge clk);
			for (k = 0; k < 512; k = k + 1) begin
				sdc_addr <= k;
				sdc_data <= adf[sdc_sector * 512 + k];
				sdc_strobe <= 1'b1;
				@(posedge clk);
				sdc_strobe <= 1'b0;
				repeat (6) @(posedge clk);
			end
			repeat (20) @(posedge clk);
			sdc_busy <= 1'b0;
			sdc_done <= 1'b1;
			@(posedge clk);
			sdc_done <= 1'b0;
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

reg [15:0] words [0:8191];
integer nwords = 0;
reg dma_on = 1'b0;

integer dma_wait = 0;
always @(posedge clk) begin
	if (dma_wait != 0) dma_wait <= dma_wait - 1;
	if (clk7_en) begin
		if (dma_on && dmal && reg_addr == 8'hFF && dma_wait == 0) begin
			dma_wait <= DMA_INTERVAL;
			reg_addr <= 9'h008 >> 1; // DSKDATR
		end
		else if (reg_addr == (9'h008 >> 1)) begin
			words[nwords] <= data_out;
			nwords <= nwords + 1;
			reg_addr <= 8'hFF;
		end
	end
end

// ---------------- mfm decode ----------------

integer errors = 0;

function [31:0] decode(input [31:0] odd, input [31:0] even);
	decode = ((odd & 32'h55555555) << 1) | (even & 32'h55555555);
endfunction

integer i, j, s, found, sec, trk, base;
reg [31:0] hdr, hcs, dcs, csum, o, e;
reg seen [0:10];

initial begin
	#1000;
	// XST starts flip-flops at 0, ISim at X: the head positions have no reset
	dut.dsktrack[0] = 7'd0; dut.dsktrack[1] = 7'd0; dut.dsktrack[2] = 7'd0; dut.dsktrack[3] = 7'd0;
	repeat (10) @(posedge clk);
	reset <= 1'b0;
	repeat (20) @(posedge clk);
	@(posedge clk) mounted <= 4'b0001;
	@(posedge clk) mounted <= 4'b0000;
	repeat (100) @(posedge clk);
	reg_write(9'h07e, 16'h4489);   // DSKSYNC
	reg_write(9'h024, 16'h0000);
	reg_write(9'h024, 16'h8000 | 16'h1900); // DSKLEN, dma on
	reg_write(9'h024, 16'h8000 | 16'h1900); // second write starts the dma
	dma_on = 1'b1;
	wait (blckint);
	$display("%t blckint, %0d words, %0d sector reads", $time, nwords, nreq);
	dma_on = 1'b0;
	$display("first words %04x %04x %04x %04x %04x %04x", words[0], words[1], words[2], words[3], words[4], words[5]);
	for (s = 0; s < 11; s = s + 1) seen[s] = 0;
	found = 0;
	for (i = 0; i + 544 < nwords; i = i + 1) begin
		// a sector starts after its sync word(s); the dma starts after the first sync word
		if (words[i] == 16'h4489 && words[i+1] != 16'h4489) begin
			base = i + 1;
			hdr = decode({words[base], words[base+1]}, {words[base+2], words[base+3]});
			trk = hdr[23:16];
			sec = hdr[15:8];
			// header checksum: xor of the 10 raw longs of header and label
			csum = 0;
			for (j = 0; j < 10; j = j + 1) csum = csum ^ {words[base+2*j], words[base+2*j+1]};
			csum = csum & 32'h55555555;
			hcs = decode({words[base+20], words[base+21]}, {words[base+22], words[base+23]});
			dcs = decode({words[base+24], words[base+25]}, {words[base+26], words[base+27]});
			if (hdr[31:24] != 8'hFF || trk != 0 || sec > 10 || hcs != csum) begin
				$display("ERROR: header %08x (format, track %0d, sector %0d) csum %08x calc %08x at word %0d",
					hdr, trk, sec, hcs, csum, i);
				errors = errors + 1;
			end
			else begin
				csum = 0;
				for (j = 0; j < 256; j = j + 1) csum = csum ^ {words[base+28+2*j], words[base+29+2*j]};
				csum = csum & 32'h55555555;
				if (dcs != csum) begin
					$display("ERROR: sector %0d data csum %08x calc %08x", sec, dcs, csum);
					errors = errors + 1;
				end
				for (j = 0; j < 128; j = j + 1) begin
					o = {words[base+28+2*j], words[base+29+2*j]};
					e = {words[base+284+2*j], words[base+285+2*j]};
					if (decode(o, e) != {adf[sec*512+4*j], adf[sec*512+4*j+1], adf[sec*512+4*j+2], adf[sec*512+4*j+3]}) begin
						if (errors < 20) $display("ERROR: sector %0d long %0d %08x adf %02x%02x%02x%02x", sec, j, decode(o, e),
							adf[sec*512+4*j], adf[sec*512+4*j+1], adf[sec*512+4*j+2], adf[sec*512+4*j+3]);
						errors = errors + 1;
					end
				end
				if (!seen[sec]) found = found + 1;
				seen[sec] = 1;
			end
			i = i + 540;
		end
	end
	$display("sectors found %0d", found);
	if (found != 11) errors = errors + 1;
	$display("tb_floppy: %0d errors", errors);
	$finish;
end

initial begin
	#400000000;
	$display("ERROR: timeout, %0d words, %0d sector reads", nwords, nreq);
	$display("tb_floppy: 1 errors");
	$finish;
end

endmodule
