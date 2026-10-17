// karabas: physical floppy drives on the Shugart connector of the Karabas Go
//
// Up to two drives: DS0 (connector pin 10) and DS1 (pin 12, a PC drive on a straight cable);
// the motor line (pin 16) is shared. Any Amiga drive DF0-DF3 can be one of them (map, set by the
// OSD). The read data go to MiSTerFloppyPLL in paula_floppy, this module makes the rest of an
// Amiga drive out of a PC / Shugart drive:
// - select: the drive of an Amiga drive follows its _SEL; motor: the motor latches of paula;
// - STEP waits DIR_SETUP clocks after a change of DIR (Kickstart 1.3 changes both at once) and is
//   at least ~1 us long;
// - _RDY: with the motor off the ID of a 3.5" DD drive (all ones, _RDY low); with the motor on low
//   once the motor runs SPINUP and a disk was seen;
// - _CHNG: the connector has no DSKCHG (pin 34), so it is emulated. It goes low (disk changed) at
//   reset, at an OSD event (the drive was chosen again), and when a selected drive with the motor
//   at speed gives no index for NOINDEX (the disk was taken out). A step pulse sets it high again
//   when the drive has a disk. A disk is seen by its index pulses (no disk, no index). The Amiga
//   looks for a new disk with step pulses and the motor off: such a step on a drive without a disk
//   starts a probe, the motor runs for up to PROBE and the drive is selected (while the Amiga
//   selects no physical drive); two index pulses mean a disk, and the next step of the Amiga
//   clears _CHNG.
// Times are in ticks of 2^TICK_BITS clk7_en cycles (1024: 144.6 us at 7.08 MHz).
//
// fdd_in / fdd_out are at the FPGA pins, high = active (the board has inverters to the connector).

module paula_floppy_ext #(
	parameter TICK_BITS = 10,
	parameter SPINUP    = 13'd3458,      // 500 ms
	parameter NOINDEX   = 13'd2766,      // 400 ms: two revolutions
	parameter PROBE     = 13'd6916,      // 1 s
	parameter DIR_SETUP = 5'd20          // 2.8 us
)
(
	input            clk,
	input            clk7_en,
	input            reset,

	input      [3:0] _sel,                // from the CIAs
	input      [3:0] motor_on,            // motor latches of paula
	input            _step,
	input            direc,
	input            side,

	input      [7:0] map,                 // DFn: [2n+1:2n] = 0 none, 1 DS0, 2 DS1
	input      [3:0] chg,                 // one clock: DFn was chosen again in the OSD

	input      [3:0] fdd_in,              // { rdata, wprt, tr00, index }, asynchronous
	input            _write_gate,         // from MiSTerFloppyPLL
	input            _write_data,
	output     [7:0] fdd_out,             // { wdata, wgate, side1, step, dir, motor, ds1, ds0 }

	output     [3:0] ext_drv,             // DFn is a physical drive
	output           ext_sel,             // the selected drive (paula's priority) is physical
	output     [3:0] _change_v,           // _CHNG / _RDY of each DFn (for the physical ones)
	output     [3:0] _ready_v,
	output           _wprot_x,            // of the selected physical drive
	output           _track0_x,
	output           index_x,             // one clk7_en cycle: index pulse of the selected drive
	output           _dskrd               // read data, synchronised, low = flux transition
);

// ---------------- inputs ----------------

reg [3:0] in_s1 = 4'd0, in_s2 = 4'd0;
always @(posedge clk) begin
	in_s1 <= fdd_in;
	in_s2 <= in_s1;
end
wire rdata_s = in_s2[3];
wire wprt_s  = in_s2[2];
wire tr00_s  = in_s2[1];
wire index_s = in_s2[0];
assign _dskrd = ~rdata_s;

// ---------------- selection ----------------

wire [1:0] m0 = map[1:0], m1 = map[3:2], m2 = map[5:4], m3 = map[7:6];
assign ext_drv = { m3 != 2'd0, m2 != 2'd0, m1 != 2'd0, m0 != 2'd0 };

// the drive (DS0 / DS1) of DFn
wire [3:0] on_ds0 = { m3 == 2'd1, m2 == 2'd1, m1 == 2'd1, m0 == 2'd1 };
wire [3:0] on_ds1 = { m3 == 2'd2, m2 == 2'd2, m1 == 2'd2, m0 == 2'd2 };

wire [1:0] amiga_ds = { |(~_sel & on_ds1), |(~_sel & on_ds0) };

// paula's priority encoder: the lowest selected drive
wire [1:0] sel = !_sel[0] ? 2'd0 : !_sel[1] ? 2'd1 : !_sel[2] ? 2'd2 : 2'd3;
wire       _selx = &_sel;
wire [1:0] sel_map = (sel == 2'd0) ? m0 : (sel == 2'd1) ? m1 : (sel == 2'd2) ? m2 : m3;
assign ext_sel = !_selx && sel_map != 2'd0;
wire       sel_k = (sel_map == 2'd2);      // the physical drive of the selected DFn

// ---------------- timer ticks ----------------

reg [TICK_BITS-1:0] prescale = 0;
reg tick = 1'b0;
always @(posedge clk) begin
	if (clk7_en) begin
		prescale <= prescale + 1'd1;
		tick <= &prescale;
	end
end

// ---------------- motor, probe, disk detection ----------------

reg        probe_on = 1'b0;
reg        probe_k = 1'b0;
reg [12:0] probe_cnt = 13'd0;
reg  [1:0] probe_idx = 2'd0;

wire       motor = |(motor_on & ext_drv) | probe_on;
wire [1:0] probe_ds = (probe_on && amiga_ds == 2'b00) ? (probe_k ? 2'b10 : 2'b01) : 2'b00;
wire [1:0] ds = amiga_ds | probe_ds;

reg [12:0] spin_cnt = 13'd0;
wire       spun = (spin_cnt == SPINUP);

reg  [1:0] present = 2'b00;          // a disk was seen in DS0 / DS1
reg  [1:0] _chng = 2'b00;            // emulated _CHNG of DS0 / DS1
reg [12:0] noidx_cnt0 = 13'd0, noidx_cnt1 = 13'd0;
reg  [1:0] sel_age0 = 2'd0, sel_age1 = 2'd0;  // ticks the drive has been selected (up to 2)
reg        index_d = 1'b0;
reg        _step_d = 1'b1;

wire index_rise = index_s & ~index_d;
// an index pulse of a drive that has been selected for a while (one that is low at the select
// is no pulse)
wire [1:0] idx_ok = { index_rise && ds[1] && sel_age1 == 2'd2, index_rise && ds[0] && sel_age0 == 2'd2 };
wire step_end = _step & ~_step_d;

// OSD events of the DFn of each drive (one clk, kept until the next clk7_en)
wire [1:0] chg_now = { |(chg & on_ds1), |(chg & on_ds0) };
reg  [1:0] chg_p = 2'b00;
always @(posedge clk)
	chg_p <= clk7_en ? 2'b00 : chg_p | chg_now;
wire [1:0] chg_k = chg_p | chg_now;

always @(posedge clk) begin
	if (clk7_en) begin
		index_d <= index_s;
		_step_d <= _step;

		if (!motor)
			spin_cnt <= 13'd0;
		else if (tick && !spun)
			spin_cnt <= spin_cnt + 13'd1;

		sel_age0 <= !ds[0] ? 2'd0 : (tick && sel_age0 != 2'd2) ? sel_age0 + 2'd1 : sel_age0;
		sel_age1 <= !ds[1] ? 2'd0 : (tick && sel_age1 != 2'd2) ? sel_age1 + 2'd1 : sel_age1;

		// the Amiga uses a drive with its motor on: an index means a disk, none for NOINDEX
		// (selected and at speed) means that the disk was taken out
		if (amiga_ds[0] && motor && idx_ok[0]) begin
			present[0] <= 1'b1;
			noidx_cnt0 <= 13'd0;
		end else if (amiga_ds[0] && spun && tick) begin
			if (noidx_cnt0 == NOINDEX) begin
				present[0] <= 1'b0;
				_chng[0] <= 1'b0;
			end else
				noidx_cnt0 <= noidx_cnt0 + 13'd1;
		end
		if (amiga_ds[1] && motor && idx_ok[1]) begin
			present[1] <= 1'b1;
			noidx_cnt1 <= 13'd0;
		end else if (amiga_ds[1] && spun && tick) begin
			if (noidx_cnt1 == NOINDEX) begin
				present[1] <= 1'b0;
				_chng[1] <= 1'b0;
			end else
				noidx_cnt1 <= noidx_cnt1 + 13'd1;
		end
		if (!motor) begin
			noidx_cnt0 <= 13'd0;
			noidx_cnt1 <= 13'd0;
		end

		// a step of the Amiga: clears _CHNG of a drive with a disk, starts a probe of one without
		if (step_end) begin
			if (amiga_ds[0] && present[0]) _chng[0] <= 1'b1;
			if (amiga_ds[1] && present[1]) _chng[1] <= 1'b1;
			if (!probe_on && !motor && amiga_ds != 2'b00 && !(amiga_ds[1] ? present[1] : present[0])) begin
				probe_on <= 1'b1;
				probe_k <= amiga_ds[1];
				probe_cnt <= 13'd0;
				probe_idx <= 2'd0;
			end
		end

		if (probe_on) begin
			if (idx_ok[probe_k] && probe_ds != 2'b00) begin
				if (probe_idx == 2'd1) begin
					present[probe_k] <= 1'b1;
					probe_on <= 1'b0;
				end
				probe_idx <= probe_idx + 2'd1;
			end
			if (tick) begin
				if (probe_cnt == PROBE)
					probe_on <= 1'b0;
				probe_cnt <= probe_cnt + 13'd1;
			end
		end

		// a new disk chosen in the OSD: changed, and looked for again
		if (chg_k[0]) begin
			present[0] <= 1'b0;
			_chng[0] <= 1'b0;
		end
		if (chg_k[1]) begin
			present[1] <= 1'b0;
			_chng[1] <= 1'b0;
		end

		if (reset) begin
			_chng <= 2'b00;
			probe_on <= 1'b0;
		end
	end
end

// ---------------- Amiga drive signals ----------------

// _RDY of a DFn on a physical drive: low with the motor off (drive ID: 3.5" DD), with the motor
// on low once at speed with a disk
wire [1:0] rdy_k = { spun & present[1], spun & present[0] };
genvar n;
generate
	for (n = 0; n < 4; n = n + 1) begin : paula_floppy_ext_drv
		wire k = (map[2*n+1:2*n] == 2'd2);
		assign _change_v[n] = k ? _chng[1] : _chng[0];
		assign _ready_v[n] = motor_on[n] & ~(k ? rdy_k[1] : rdy_k[0]);
	end
endgenerate

assign _wprot_x = ~wprt_s;
assign _track0_x = ~tr00_s;
assign index_x = index_rise & ext_sel & (sel_k ? ds[1] : ds[0]);

// ---------------- STEP / DIR ----------------

reg       dir_q = 1'b0;
reg [4:0] dir_age = 5'd0;            // clocks since DIR changed
reg       step_pend = 1'b0;          // a step pulse waits for DIR to settle
reg       step_q = 1'b0;
reg [2:0] step_w = 3'd0;             // minimum width

always @(posedge clk) begin
	if (clk7_en) begin
		dir_q <= direc;
		if (direc != dir_q)
			dir_age <= 5'd0;
		else if (dir_age != 5'd31)
			dir_age <= dir_age + 5'd1;

		if (!_step && _step_d)
			step_pend <= 1'b1;
		if (step_pend && !step_q && dir_age >= DIR_SETUP && direc == dir_q) begin
			step_q <= 1'b1;
			step_pend <= 1'b0;
			step_w <= 3'd7;          // 1 us
		end else if (step_q) begin
			if (step_w != 3'd0)
				step_w <= step_w - 3'd1;
			else if (_step)
				step_q <= 1'b0;
		end
	end
end

// ---------------- outputs ----------------

wire wgate = ~_write_gate & ext_sel;
assign fdd_out = {
	wgate & ~_write_data,             // WDATA
	wgate,                            // WGATE
	~side,                            // SIDE1: head 1 (side = 0 is the upper head)
	step_q & (amiga_ds != 2'b00),     // STEP
	~dir_q,                           // DIR: high = in (direc = 0)
	motor,                            // MOTOR
	ds[1],                            // DS1
	ds[0]                             // DS0
};

endmodule
