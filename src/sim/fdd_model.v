`timescale 1ns / 1ps

// A PC 3.5" DD drive at the FPGA pins (high = active). Flux of cylinder 0 in 250 ns slots
// (t0.hex, t1.hex: 6250 mfm words of head 0 / 1, a bit cell = 8 slots).
module fdd_model #(
	parameter SPEED_PPM = 0,         // slower than 300 rpm by this
	parameter JITTER = 0             // ns of random delay of a flux transition
)
(
	input ds, motor, dir, step, side1, wgate, wdata,
	output index, tr00, wprt, rdata,
	output dskchg                    // pin 34 through the inverter of the Go hotfix: high = changed
);

localparam NSLOT = 800000;           // 200 ms
reg trk [0:2*NSLOT-1];
reg [15:0] w [0:6249];

reg disk_in = 1'b0;
reg chg_latch = 1'b1;                // DSKCHG: set at power on and when the disk goes out, cleared
                                     // by a step with a disk in
reg wp = 1'b0;
integer cyl = 3;
integer nsteps = 0, dir_err = 0, nwflux = 0;
integer pos = 0;
integer t, b, idx;
time motor_t = 0, dir_t = 0;
real slot_ns;
reg index_r = 1'b0, rdata_r = 1'b0;
reg wflag = 1'b0;
integer jit;
event rd_ev;

initial begin
	slot_ns = 250.0 * (1.0 + SPEED_PPM / 1000000.0);
	for (t = 0; t < 2 * NSLOT; t = t + 1) trk[t] = 1'b0;
	$readmemh("t0.hex", w);
	for (t = 0; t < 6250 * 16; t = t + 1) trk[t * 8] = w[t / 16][15 - t % 16];
	$readmemh("t1.hex", w);
	for (t = 0; t < 6250 * 16; t = t + 1) trk[NSLOT + t * 8] = w[t / 16][15 - t % 16];
end

reg spinning = 1'b0;                 // 50 ms after the motor, with a disk
reg writing = 1'b0;

always @(posedge motor) motor_t = $time;
always @(dir) dir_t = $time;
always @(negedge disk_in) chg_latch = 1'b1;
always @(posedge step) begin
	if (ds && disk_in) chg_latch = 1'b0;
	if (ds) begin
		nsteps = nsteps + 1;
		if ($time - dir_t < 1000) dir_err = dir_err + 1;
		if (dir) cyl = cyl + 1;
		else if (cyl > 0) cyl = cyl - 1;
	end
end
always @(posedge wdata) if (writing) wflag = 1'b1;

initial begin
	forever begin
		#(slot_ns);
		spinning = motor && disk_in && ($time - motor_t >= 50000000);
		if (spinning) begin
			idx = (side1 ? NSLOT : 0) + pos;
			if (writing) begin
				if (cyl == 0) trk[idx] = wflag;
				if (wflag) nwflux = nwflux + 1;
				wflag = 1'b0;
			end
			pos = (pos + 1) % NSLOT;
			writing = ds && wgate && !wp;
			index_r = (pos < 8000);   // 2 ms
			idx = (side1 ? NSLOT : 0) + pos;
			if (!writing && cyl == 0 && trk[idx]) begin
				jit = JITTER ? {$random} % JITTER : 0;
				-> rd_ev;
			end
		end else begin
			index_r = 1'b0;
			writing = 1'b0;
		end
	end
end

always @(rd_ev) begin
	#(jit);
	rdata_r = 1'b1;
	#400;
	rdata_r = 1'b0;
end

assign index = ds & index_r;
assign tr00 = ds & (cyl == 0);
assign wprt = ds & (wp | !disk_in);
assign rdata = ds & rdata_r;
assign dskchg = ds & chg_latch;

endmodule
