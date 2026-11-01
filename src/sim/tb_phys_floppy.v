`timescale 1ns / 1ps

// paula_floppy.v with a physical drive (paula_floppy_ext.v + MiSTerFloppyPLL.v) against a model
// of a PC 3.5" DD drive on the Karabas Go connector: DF1 is drive DS1, DF0 an ADF image (sdc
// model). The tb is the CIA (_SEL, _MOTOR, _STEP, DIR, SIDE), the register bus and the disk dma
// (DMA_INTERVAL clocks between two words, a real Amiga: 3 words per line).
//
// The drive model (fdd_model below) turns at 300 rpm minus SPEED_PPM, keeps the flux of cylinder 0
// (both heads) in 250 ns slots and gives each transition JITTER ns of random delay; it writes the
// flux at the angle it comes; its outputs are those of a selected drive only; it has no DSKCHG and
// no READY; without a disk it has no index and shows write protect. It counts STEP pulses with
// less than 1 us of DIR setup.
//
// Checks: drive ID / _RDY with the motor off; steps of DF0 never reach the drive; a step of DF1
// without a disk starts a probe (motor + DS1) that finds nothing; a disk put in is found by the
// probe and the next step clears _CHNG; DIR setup and TR00 on a seek; _RDY only after the spin-up;
// DSKBYTR (DSKBYT, cleared by a read; data); a track dma read with word sync: the 11 sectors of
// cylinder 0 head 0, no sdc request; a track dma write on head 1 and its read back; write protect;
// an OSD change event (_CHNG low, found again); the disk taken out with the motor on (_CHNG low,
// _RDY high); DF0 from the ADF still reads.
// FW = 0: a firmware without CMD_FDD_CHNG (no answers: three timeouts after the reset turn the
// requests off, then the checks above). FW = 1: the DSKCHG hotfix (the model has DSKCHG, a
// firmware model answers each request after FW_DELAY with the level then): _CHNG follows the
// line, no probe ever spins the motor, a disk put in is seen after the step that clears DSKCHG,
// an OSD event keeps _CHNG low until a step, a disk taken out with the motor off is seen at the
// next look of the Amiga, and each request keeps its drive (and no other one) selected until the
// answer.
// Ends with "tb_phys_floppy: N errors".

module tb_phys_floppy;

parameter SECTOR_DELAY = 2000;
parameter DMA_INTERVAL = 600;
parameter SPEED_PPM = 15000;
parameter JITTER = 200;
parameter NWWORDS = 6056;
parameter FW = 0;
parameter FW_DELAY = 400000;     // ns from a request to the answer

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

// CIA side
reg [3:0] _sel = 4'b1111;
reg _motor = 1'b1, _step = 1'b1, direc = 1'b0, side = 1'b1;
wire _track0, _change, _ready, _wprot, index;

wire [2:0] chng_req;
reg [4:0] chng_in = 5'd0;
reg [7:0] floppy_ext = 8'd0;
reg [3:0] floppy_ext_chg = 4'd0;
wire [7:0] fdd_out;
wire [3:0] fdd_in;

reg [3:0] mounted = 4'd0;
wire [3:0] sdc_rd, sdc_wr;
wire [31:0] sdc_sector;
reg sdc_busy = 1'b0, sdc_done = 1'b0, sdc_strobe = 1'b0;
reg [8:0] sdc_addr = 9'd0;
reg [7:0] sdc_data = 8'd0;

paula_floppy #(.FLOPPY_EXT(1)) dut(
	.clk(clk), .clk7_en(clk7_en), .clk7n_en(clk7n_en), .reset(reset), .ntsc(1'b0), .sof(1'b0),
	.enable(1'b1), .reg_address_in(reg_addr), .data_in(reg_data), .data_out(data_out),
	.dmal(dmal), .dmas(dmas),
	._step(_step), .direc(direc), ._sel(_sel), .side(side), ._motor(_motor),
	._track0(_track0), ._change(_change), ._ready(_ready), ._wprot(_wprot), .index(index),
	.blckint(blckint), .syncint(syncint), .wordsync(1'b1),
	.fdd_led(), .floppy_drives(2'd1), .floppy_wrprot(1'b0),
	.sdc_image_mounted(mounted), .sdc_image_size(32'd901120),
	.sdc_rd(sdc_rd), .sdc_wr(sdc_wr), .sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done),
	.sdc_byte_in_strobe(sdc_strobe), .sdc_byte_addr(sdc_addr), .sdc_byte_in_data(sdc_data),
	.sdc_byte_out_data(),
	.precomp(2'b00), .floppy_ext(floppy_ext), .floppy_ext_chg(floppy_ext_chg),
	.fdd_in(fdd_in), .fdd_out(fdd_out), .fdd_chng_req(chng_req), .fdd_chng_in(chng_in)
);
// shorter than on the board: spin-up 100 ms, probe 700 ms (no index: 400 ms as on the board)
defparam dut.paula_floppy_ext_on.ext.SPINUP = 13'd692;
defparam dut.paula_floppy_ext_on.ext.PROBE = 13'd4840;
// FW = 0: the three timeouts are over in 1 ms
defparam dut.paula_floppy_ext_on.ext.ANSWER = (FW == 0) ? 9'd2 : 9'd346;

wire f_wdata = fdd_out[7], f_wgate = fdd_out[6], f_side1 = fdd_out[5], f_step = fdd_out[4];
wire f_dir = fdd_out[3], f_motor = fdd_out[2], f_ds1 = fdd_out[1], f_ds0 = fdd_out[0];

// DS1 has the drive, DS0 nothing: the inputs are the outputs of the selected drive (wired-or)
wire d_index, d_tr00, d_wprt, d_rdata, d_dskchg;
fdd_model #(.SPEED_PPM(SPEED_PPM), .JITTER(JITTER)) drive(
	.ds(f_ds1), .motor(f_motor), .dir(f_dir), .step(f_step), .side1(f_side1),
	.wgate(f_wgate), .wdata(f_wdata),
	.index(d_index), .tr00(d_tr00), .wprt(d_wprt), .rdata(d_rdata), .dskchg(d_dskchg)
);

// the firmware: answers 49 d 00 with GPIO28 (DSKCHG of the selected drives) FW_DELAY later
integer nask = 0, nans = 0, nask_bad = 0;
reg [1:0] ask_d = 2'd0;
always @(posedge clk) begin
	if (chng_req[2]) begin
		nask = nask + 1;
		ask_d = chng_req[1:0];
	end
end
initial begin
	forever begin
		wait (nask > nans);
		nans = nans + 1;
		#(FW_DELAY);
		// the core keeps the drive selected until the answer, and no other one
		if (!(ask_d == 2'd2 ? f_ds1 : f_ds0) || (ask_d == 2'd2 ? f_ds0 : f_ds1)) nask_bad = nask_bad + 1;
		if (FW == 1) begin
			@(posedge clk) chng_in <= { 1'b1, ask_d, 1'b0, d_dskchg };
			@(posedge clk) chng_in <= 5'd0;
		end
	end
end
assign fdd_in = { d_rdata, d_wprt, d_tr00, d_index };

integer errors = 0;

// ---------------- adf, sdc model (DF0) ----------------

reg [7:0] adf [0:22527];         // tracks 0..3 of the disk
reg [7:0] adfw [0:22527];        // the same, track 1 as written
reg [15:0] wtrack [0:8191];      // track 1 of adfw as mfm (mfm_track.py)
initial begin
	$readmemh("adf.hex", adf);
	$readmemh("adfw.hex", adfw);
	$readmemh("wtrack.hex", wtrack);
end

integer nreq = 0;
integer k;
initial begin
	forever begin
		@(posedge clk);
		if (sdc_rd[0]) begin
			nreq = nreq + 1;
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
		if (sdc_rd[3:1] != 3'd0 || sdc_wr != 4'd0) begin
			$display("ERROR: %t sdc request rd %b wr %b", $time, sdc_rd, sdc_wr);
			errors = errors + 1;
			@(posedge clk);
		end
	end
end

// ---------------- register bus and disk dma ----------------

task reg_write(input [8:0] a, input [15:0] d);
	begin
		@(posedge clk); while (!clk7_en) @(posedge clk);
		reg_addr <= a[8:1];
		reg_data <= d;
		@(posedge clk); while (!clk7_en) @(posedge clk);
		reg_addr <= 8'hFF;
	end
endtask

reg [15:0] rdval;
task reg_read(input [8:0] a);
	begin
		@(posedge clk); while (!clk7_en) @(posedge clk);
		reg_addr <= a[8:1];
		@(posedge clk); while (!clk7_en) @(posedge clk);
		rdval = data_out;
		reg_addr <= 8'hFF;
	end
endtask

reg [15:0] words [0:8191];
integer nwords = 0, nw = 0;
reg dma_on = 1'b0, dma_write = 1'b0;
integer dma_wait = 0;
always @(posedge clk) begin
	if (dma_wait != 0) dma_wait <= dma_wait - 1;
	if (clk7_en) begin
		if (dma_on && dmal && reg_addr == 8'hFF && dma_wait == 0) begin
			dma_wait <= DMA_INTERVAL;
			if (dma_write) begin
				reg_addr <= 9'h026 >> 1; // DSKDAT
				reg_data <= wtrack[nw];
				nw <= nw + 1;
			end else
				reg_addr <= 9'h008 >> 1; // DSKDATR
		end
		else if (reg_addr == (9'h008 >> 1)) begin
			words[nwords] <= data_out;
			nwords <= nwords + 1;
			reg_addr <= 8'hFF;
		end
		else if (reg_addr == (9'h026 >> 1))
			reg_addr <= 8'hFF;
	end
end

integer nsync = 0;
always @(posedge clk) if (clk7_en && syncint) nsync = nsync + 1;

// ---------------- CIA actions ----------------

// select DFn; the motor latch takes _MOTOR at the select
task select(input integer n, input motor);
	begin
		_motor = !motor;
		#2000;
		_sel = ~(4'b0001 << n);
		#2000;
	end
endtask

task deselect;
	begin
		#2000;
		_sel = 4'b1111;
		#2000;
	end
endtask

// a step pulse; DIR changes with its leading edge, as Kickstart 1.3 does
task step(input d);
	begin
		direc = d;
		_step = 1'b0;
		#3000;
		_step = 1'b1;
		#3000;
	end
endtask

task check(input cond, input [8*64-1:0] what);
	begin
		if (!cond) begin
			$display("ERROR: %t %0s", $time, what);
			errors = errors + 1;
		end
	end
endtask

task wait_ms(input integer ms);
	integer i;
	begin
		for (i = 0; i < ms; i = i + 1) #1000000;
	end
endtask

// ---------------- mfm decode ----------------

function [31:0] decode(input [31:0] odd, input [31:0] even);
	decode = ((odd & 32'h55555555) << 1) | (even & 32'h55555555);
endfunction

// the sectors of track trk in words[0..nwords-1]; with splice a sector with a bad checksum (the
// end of a written track over the old one) is no error. All 11 have to be there, with the data of
// adf (written = 0) or adfw (written = 1).
integer i, j, s, found, sec, trk, base, nbad;
reg [31:0] hdr, hcs, dcs, csum, o, e, refw;
integer kk;
reg seen [0:10];
task decode_track(input integer t, input splice, input written);
	begin
		for (s = 0; s < 11; s = s + 1) seen[s] = 0;
		found = 0;
		nbad = 0;
		for (i = 0; i + 544 < nwords; i = i + 1) begin
			if (words[i] == 16'h4489 && words[i+1] != 16'h4489) begin
				base = i + 1;
				hdr = decode({words[base], words[base+1]}, {words[base+2], words[base+3]});
				trk = hdr[23:16];
				sec = hdr[15:8];
				csum = 0;
				for (j = 0; j < 10; j = j + 1) csum = csum ^ {words[base+2*j], words[base+2*j+1]};
				csum = csum & 32'h55555555;
				hcs = decode({words[base+20], words[base+21]}, {words[base+22], words[base+23]});
				dcs = decode({words[base+24], words[base+25]}, {words[base+26], words[base+27]});
				if (hdr[31:24] != 8'hFF || trk != t || sec > 10 || hcs != csum) begin
					nbad = nbad + 1;
					if (splice) $display("splice: header %08x at word %0d", hdr, i);
					if (!splice) begin
						$display("ERROR: header %08x (track %0d, sector %0d) csum %08x calc %08x at word %0d", hdr, trk, sec, hcs, csum, i);
						errors = errors + 1;
					end
				end else begin
					csum = 0;
					for (j = 0; j < 256; j = j + 1) csum = csum ^ {words[base+28+2*j], words[base+29+2*j]};
					csum = csum & 32'h55555555;
					if (dcs != csum) begin
						nbad = nbad + 1;
						if (splice) $display("splice: sector %0d data checksum at word %0d", sec, i);
						if (!splice) begin
							$display("ERROR: sector %0d data csum %08x calc %08x", sec, dcs, csum);
							errors = errors + 1;
						end
					end else begin
						for (j = 0; j < 128; j = j + 1) begin
							o = {words[base+28+2*j], words[base+29+2*j]};
							e = {words[base+284+2*j], words[base+285+2*j]};
							kk = (t * 11 + sec) * 512 + 4 * j;
							refw = written ? {adfw[kk], adfw[kk+1], adfw[kk+2], adfw[kk+3]} : {adf[kk], adf[kk+1], adf[kk+2], adf[kk+3]};
							if (decode(o, e) != refw) begin
								if (errors < 20) $display("ERROR: sector %0d long %0d %08x, expected %08x", sec, j, decode(o, e), refw);
								errors = errors + 1;
							end
						end
						if (!seen[sec]) found = found + 1;
						seen[sec] = 1;
						i = i + 540;     // only after a good sector: a bad one can be the start of a good one
					end
				end
			end
		end
		$display("%t track %0d: %0d sectors, %0d bad (splice %0d), %0d words", $time, t, found, nbad, splice, nwords);
		if (found != 11) begin
			$display("ERROR: track %0d: %0d sectors found", t, found);
			errors = errors + 1;
		end
		if (splice && nbad > 1) begin
			$display("ERROR: track %0d: %0d bad sectors", t, nbad);
			errors = errors + 1;
		end
	end
endtask

task dma_read(input integer t, input splice, input written);
	begin
		nwords = 0;
		reg_write(9'h07e, 16'h4489);            // DSKSYNC
		reg_write(9'h024, 16'h0000);
		reg_write(9'h024, 16'h8000 | 16'h1900); // DSKLEN: 6400 words, a bit more than a turn
		reg_write(9'h024, 16'h8000 | 16'h1900);
		dma_on = 1'b1;
		wait (blckint);
		dma_on = 1'b0;
		reg_write(9'h024, 16'h0000);
		// word sync: the dma starts with the word after the first sync word (the second sync)
		check(words[0] == 16'h4489, "dma read: does not start after a sync word");
		decode_track(t, splice, written);
	end
endtask

// ---------------- the test ----------------

integer steps0, n, nbyt, nclr, bval, nmotor0;
integer nmotor = 0;
always @(posedge f_motor) nmotor = nmotor + 1;
reg probed;
initial begin
	#1000;
	// XST starts flip-flops at 0, ISim at X: the head positions have no reset
	dut.dsktrack[0] = 7'd0; dut.dsktrack[1] = 7'd0; dut.dsktrack[2] = 7'd0; dut.dsktrack[3] = 7'd0;
	repeat (10) @(posedge clk);
	reset <= 1'b0;
	repeat (20) @(posedge clk);
	// DF0: an ADF; DF1: drive DS1 (an OSD event)
	@(posedge clk) mounted <= 4'b0001;
	@(posedge clk) mounted <= 4'b0000;
	@(posedge clk) begin floppy_ext <= 8'b0000_1000; floppy_ext_chg <= 4'b0010; end
	@(posedge clk) floppy_ext_chg <= 4'b0000;
	#10000;
	wait_ms(2);
	if (FW == 0)
		check(dut.paula_floppy_ext_on.ext.line_off && !dut.paula_floppy_ext_on.ext.line_on, "no answers: requests not off");
	else
		check(dut.paula_floppy_ext_on.ext.line_on && nask == 1, "line: not on after the first answer");

	// drive ID: _RDY low with the motor off, _CHNG low (no disk yet)
	select(1, 0);
	check(_ready == 1'b0, "DF1 motor off: _RDY not low (drive ID)");
	check(_change == 1'b0, "DF1: _CHNG not low after reset");
	check(f_ds1 && !f_ds0 && !f_motor, "DF1 select: DS1 only, motor off");
	deselect;
	check(!f_ds1, "DF1 deselect: DS1 still on");

	// steps of DF0 (the ADF) do not reach the drive
	steps0 = drive.nsteps;
	select(0, 0);
	step(1'b0); step(1'b1);
	check(!f_ds0 && !f_ds1, "DF0 select: a physical drive selected");
	deselect;
	check(drive.nsteps == steps0, "DF0 steps reached the drive");

	if (FW == 0) begin
		// no disk: a step of DF1 starts a probe that finds nothing
		select(1, 0);
		step(1'b1);
		deselect;
		#1000000;
		check(f_motor && f_ds1, "no probe after a step without a disk");
		wait_ms(750);
		check(!f_motor && !f_ds1, "probe not over");
		select(1, 0);
		check(_change == 1'b0, "no disk: _CHNG not low");
		deselect;

		// a disk put in: found by the probe after the next step, the step after that clears _CHNG
		drive.disk_in = 1'b1;
		select(1, 0);
		step(1'b1);
		deselect;
		probed = 1'b0;
		for (n = 0; n < 800 && !probed; n = n + 1) begin
			#1000000;
			probed = !f_motor;
		end
		$display("%t probe found the disk after %0d ms", $time, n);
		check(dut.paula_floppy_ext_on.ext.present[1] == 1'b1, "probe: disk not found");
		select(1, 0);
		check(_change == 1'b0, "_CHNG cleared without a step");
		step(1'b1);
		check(_change == 1'b1, "disk in, step: _CHNG still low");
		deselect;
	end else begin
	// no disk: a step of DF1 asks the drive (DSKCHG 1), no probe
	select(1, 0);
	step(1'b1);
	deselect;
	wait_ms(2);
	check(!f_motor && !f_ds1, "line: motor or DS1 on after a step without a disk");
	select(1, 0);
	check(_change == 1'b0, "line, no disk: _CHNG not low");
	deselect;

	// a disk put in: the step clears DSKCHG of the drive, the answer after it _CHNG
	drive.disk_in = 1'b1;
	select(1, 0);
	step(1'b1);
	deselect;
	wait_ms(2);
	select(1, 0);
	check(_change == 1'b1, "line, disk in, step: _CHNG still low");
	check(dut.paula_floppy_ext_on.ext.present[1] == 1'b1, "line: disk not seen");
	deselect;
	check(nmotor == 0, "line: the motor ran (a probe)");
	end

	// seek to cylinder 0 (from 3): DIR changes with the first step
	select(1, 0);
	for (n = 0; n < 6; n = n + 1) step(1'b1);
	check(_track0 == 1'b0, "seek: no _TRK0");
	check(drive.cyl == 0, "seek: drive not on cylinder 0");
	step(1'b0);
	check(_track0 == 1'b1 && drive.cyl == 1, "step in: cylinder not 1");
	step(1'b1);
	check(_track0 == 1'b0 && drive.cyl == 0, "step out: cylinder not 0");
	deselect;

	// motor on: _RDY only after the spin-up
	select(1, 1);
	check(f_motor, "motor latch: motor off");
	#10000000;
	check(_ready == 1'b1, "_RDY low 10 ms after motor on");
	wait_ms(250);
	check(_ready == 1'b0, "_RDY not low after the spin-up");
	check(_wprot == 1'b1, "_WPROT low (not protected)");

	// DSKBYTR: DSKBYT set by the bytes from the disk, cleared by a read
	nbyt = 0; nclr = 0; bval = 0;
	for (n = 0; n < 4000; n = n + 1) begin
		reg_read(9'h01a);
		if (rdval[15]) begin
			nbyt = nbyt + 1;
			if (rdval[7:0] != 8'h00 && rdval[7:0] != 8'hAA) bval = bval + 1;
			reg_read(9'h01a);
			if (!rdval[15]) nclr = nclr + 1;
		end
		#2000;
	end
	$display("%t DSKBYTR: %0d bytes, %0d cleared by the read, %0d not 00/aa", $time, nbyt, nclr, bval);
	check(nbyt > 300 && nclr == nbyt && bval > 100, "DSKBYTR");

	// track read: cylinder 0 head 0 = track 0
	side = 1'b1;
	#100000;
	nsync = 0;
	dma_read(0, 0, 0);
	$display("%t sync interrupts: %0d", $time, nsync);
	check(nsync >= 11, "sync interrupts");

	// track write on head 1 (track 1), then read back
	side = 1'b0;
	#100000;
	nw = 0;
	reg_write(9'h024, 16'h4000);
	reg_write(9'h024, 16'hC000 | NWWORDS);  // DSKLEN write
	reg_write(9'h024, 16'hC000 | NWWORDS);
	dma_write = 1'b1;
	dma_on = 1'b1;
	wait (blckint);
	dma_on = 1'b0;
	dma_write = 1'b0;
	reg_write(9'h024, 16'h0000);
	$display("%t track write: %0d words, %0d flux transitions written", $time, nw, drive.nwflux);
	check(nw == NWWORDS, "write dma: words");
	check(drive.nwflux > 30000, "write: no flux");
	#100000;
	dma_read(1, 1, 1);

	// write protect
	drive.wp = 1'b1;
	#10000;
	check(_wprot == 1'b0, "_WPROT not low (protected)");
	drive.wp = 1'b0;
	deselect;

	if (FW == 0) begin
		// OSD event (the drive chosen again): _CHNG low, the disk is found again
		floppy_ext_chg = 4'b0010;
		#1000;
		floppy_ext_chg = 4'b0000;
		select(1, 0);
		check(_change == 1'b0, "OSD change: _CHNG not low");
		step(1'b0);
		deselect;
		probed = 1'b0;
		for (n = 0; n < 800 && !probed; n = n + 1) begin
			#1000000;
			probed = !f_motor;
		end
		select(1, 0);
		step(1'b1);
		check(_change == 1'b1, "OSD change: _CHNG still low after the probe and a step");
		deselect;
	end else begin
	// OSD event: _CHNG low until a step, then the answer (disk in) clears it, no probe
	nmotor0 = nmotor;
	floppy_ext_chg = 4'b0010;
	#1000;
	floppy_ext_chg = 4'b0000;
	wait_ms(2);
	select(1, 0);
	check(_change == 1'b0, "line, OSD change: _CHNG not low");
	step(1'b0);
	deselect;
	wait_ms(2);
	select(1, 0);
	check(_change == 1'b1, "line, OSD change: _CHNG still low after a step");
	deselect;

	// the disk taken out with the motor off: seen when the Amiga looks again (RECHECK after the
	// last answer)
	drive.disk_in = 1'b0;
	wait_ms(600);
	select(1, 0);
	deselect;
	wait_ms(2);
	select(1, 0);
	check(_change == 1'b0, "line, disk out, motor off: _CHNG not low");
	deselect;
	check(nmotor == nmotor0, "line: the motor ran (a probe)");
	// and in again
	drive.disk_in = 1'b1;
	select(1, 0);
	step(1'b1);
	deselect;
	wait_ms(2);
	select(1, 0);
	check(_change == 1'b1, "line, disk in again: _CHNG still low");
	deselect;
	end

	// the disk taken out with the motor on: _CHNG low after two turns without an index
	select(1, 1);
	wait_ms(150);
	check(_ready == 1'b0, "motor on: _RDY not low");
	drive.disk_in = 1'b0;
	wait_ms(450);
	check(_change == 1'b0, "disk out, motor on: _CHNG not low");
	check(_ready == 1'b1, "disk out, motor on: _RDY low");
	deselect;
	select(1, 0);
	deselect;

	// DF0 (the ADF) still reads
	select(0, 1);
	side = 1'b1;
	nreq = 0;
	dma_read(0, 0, 0);
	check(nreq > 0, "DF0: no sdc request");
	check(!f_ds0 && !f_ds1 && !f_motor, "DF0: a physical drive selected");
	deselect;

	$display("drive: %0d steps, %0d with DIR setup < 1 us", drive.nsteps, drive.dir_err);
	check(drive.dir_err == 0, "DIR setup");
	$display("DSKCHG: %0d requests, %0d answered (FW %0d), %0d without their drive selected", nask, nans, FW, nask_bad);
	if (FW == 1) check(nask_bad == 0, "line: a request without its drive selected until the answer");
	$display("tb_phys_floppy: %0d errors", errors);
	$finish;
end

initial begin
	repeat (6000) #1000000;
	$display("ERROR: timeout");
	$display("tb_phys_floppy: 1 errors");
	$finish;
end

endmodule
