// karabas: physical floppy drives on the Shugart connector of the Karabas Go
//
// Up to two drives: DS0 (connector pin 10) and DS1 (pin 12, a PC drive on a straight cable);
// the motor line (pin 16) is shared. Any Amiga drive DF0-DF3 can be one of them (map, set by the
// OSD). The read data go to MiSTerFloppyPLL in paula_floppy, this module makes the rest of an
// Amiga drive out of a PC / Shugart drive:
// - select: the drive of an Amiga drive follows its _SEL; motor: the motor latches of paula;
// - STEP waits DIR_SETUP clocks after a change of DIR (Kickstart 1.3 changes both at once) and is
//   at least STEP_W clocks long, 8 us each as the physical floppy of karabas-go-core-pcxt (a PC
//   drive on a Go missed shorter pulses there). The drive that steps stays selected until its
//   pulse is over: the Amiga may let it go right after its own (short) step pulse;
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
// - _CHNG with the DSKCHG hotfix of the board (pin 34 through U18 to RP2040 GPIO28, firmware
//   CMD_FDD_CHNG 49): the level of the drive is asked for. The Amiga selects a drive for a few
//   microseconds, too short for the link, so the module selects the drive itself (no motor, while
//   the Amiga selects no other physical drive), waits SETTLE and sends a request (chng_req);
//   the firmware answers with GPIO28 now (chng_in), and the drive stays selected until then (or
//   ANSWER). Answer 1 (changed / no disk): _CHNG low, no disk; 0: a disk, _CHNG high. A drive is
//   asked at reset, after a step of the Amiga on it while no disk is known, and when the Amiga
//   stops selecting it and the last answer is older than RECHECK. After an OSD event _CHNG stays
//   low until the Amiga steps (an answer 0 right away would hide the change from it). The first answer 0 / 1 turns the line
//   on: then no probe spins the motor. Answer 2 (no line) or NOANSWER timeouts in a row (older
//   firmware) turn the requests off until the core is loaded again, and the emulation stays.
// Times are in ticks of 2^TICK_BITS clk7_en cycles (1024: 144.6 us at 7.08 MHz).
//
// fdd_in / fdd_out are at the FPGA pins, high = active (the board has inverters to the connector).

module paula_floppy_ext #(
	parameter TICK_BITS = 10,
	parameter SPINUP    = 13'd3458,      // 500 ms
	parameter NOINDEX   = 13'd2766,      // 400 ms: two revolutions
	parameter PROBE     = 13'd6916,      // 1 s
	parameter DIR_SETUP = 6'd57,         // 8 us (clk7_en cycles)
	parameter STEP_W    = 6'd57,         // 8 us
	parameter SETTLE    = 8'd142,        // 20 us (clk7_en cycles): select to request
	parameter ANSWER    = 9'd346,        // 50 ms (ticks): the drive stays selected for an answer
	parameter RECHECK   = 13'd3458,      // 500 ms
	parameter NOANSWER  = 2'd3           // timeouts in a row without the line
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
	output           _dskrd,              // read data, synchronised, low = flux transition

	// DSKCHG of the board (kg_mcu CMD_FDD_CHNG): a request (one clock) for drive 1 DS0 / 2 DS1,
	// the answer { one clock, drive, value }
	output reg [2:0] chng_req = 3'd0,     // { req, drive }
	input      [4:0] chng_in,             // { wr, drive, value: 0 disk in, 1 changed, 2 no line }
	output    [31:0] dbg                  // state for the debug log of the firmware (kg_mcu DEBUG_*)
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

// DSKCHG requests
localparam Q_IDLE = 2'd0, Q_SETTLE = 2'd1, Q_WAIT = 2'd2, Q_DRAIN = 2'd3;
reg  [1:0] q_state = Q_IDLE;
wire       step_busy;                // a STEP pulse of a drive is on its way (no other select)
reg        q_k = 1'b0;               // the drive asked for
reg  [7:0] q_cnt = 8'd0;             // SETTLE (clk7_en cycles)
reg  [8:0] q_tmo = 9'd0;             // ANSWER (ticks)
reg  [1:0] q_miss = 2'd0;            // timeouts in a row
reg        line_on = 1'b0;           // the firmware answered with a level
reg        line_off = 1'b0;          // no line: no more requests
reg  [1:0] want = 2'b00;             // DS0 / DS1 should be asked
reg [12:0] age0 = 13'd0, age1 = 13'd0; // ticks since the last answer of DS0 / DS1
wire [1:0] q_ds = (q_state == Q_SETTLE || q_state == Q_WAIT) ? (q_k ? 2'b10 : 2'b01) : 2'b00;
wire [1:0] mapped = { |on_ds1, |on_ds0 };

wire       motor = |(motor_on & ext_drv) | probe_on;
wire [1:0] probe_ds = (probe_on && amiga_ds == 2'b00 && !step_busy) ? (probe_k ? 2'b10 : 2'b01) : 2'b00;
// STEP (below): the drive that steps is held selected until its pulse is over
reg        step_pend = 1'b0;         // a step pulse waits for DIR to settle
reg        step_q = 1'b0;
reg  [1:0] step_ds = 2'b00;          // the drive(s) the Amiga stepped
wire [1:0] hold_ds = (step_pend | step_q) ? step_ds : 2'b00;
wire [1:0] ds = amiga_ds | probe_ds | q_ds | hold_ds;

reg [12:0] spin_cnt = 13'd0;
wire       spun = (spin_cnt == SPINUP);

reg  [1:0] present = 2'b00;          // a disk was seen in DS0 / DS1
reg  [1:0] _chng = 2'b00;            // emulated _CHNG of DS0 / DS1
reg [12:0] noidx_cnt0 = 13'd0, noidx_cnt1 = 13'd0;
reg  [1:0] sel_age0 = 2'd0, sel_age1 = 2'd0;  // ticks the drive has been selected (up to 2)
reg        index_d = 1'b0;
reg        _step_d = 1'b1;
reg  [1:0] amiga_ds_d = 2'b00;

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

// the answer of the firmware (any clock), taken at the next clk7_en
reg  [2:0] ans = 3'd0;               // { valid, value }
reg        ans_k = 1'b0;
always @(posedge clk) begin
	if (chng_in[4] && (q_state == Q_WAIT || q_state == Q_DRAIN) && chng_in[3:2] == (q_k ? 2'd2 : 2'd1)) begin
		ans <= { 1'b1, chng_in[1:0] };
		ans_k <= q_k;
	end else if (clk7_en)
		ans <= 3'd0;
end

always @(posedge clk) begin
	chng_req <= 3'd0;
	if (clk7_en) begin
		index_d <= index_s;
		_step_d <= _step;
		amiga_ds_d <= amiga_ds;

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
			// the Amiga looks for a disk: ask the drive after the step
			if (amiga_ds[0] && !present[0]) want[0] <= 1'b1;
			if (amiga_ds[1] && !present[1]) want[1] <= 1'b1;
			if (!line_on && !probe_on && q_state == Q_IDLE && !motor && amiga_ds != 2'b00 && !(amiga_ds[1] ? present[1] : present[0])) begin
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

		// DSKCHG of the board: the age of the answers; ask again when the Amiga lets a drive go
		if (tick) begin
			if (age0 != RECHECK) age0 <= age0 + 13'd1;
			if (age1 != RECHECK) age1 <= age1 + 13'd1;
		end
		if (amiga_ds_d[0] && !amiga_ds[0] && age0 == RECHECK) want[0] <= 1'b1;
		if (amiga_ds_d[1] && !amiga_ds[1] && age1 == RECHECK) want[1] <= 1'b1;

		case (q_state)
		Q_IDLE:
			// one drive at a time, and only while the Amiga selects no other physical drive
			if (!line_off && !probe_on && !step_busy && (want & mapped) != 2'b00) begin
				if ((want[0] & mapped[0]) && !amiga_ds[1]) begin
					q_k <= 1'b0;
					q_state <= Q_SETTLE;
					q_cnt <= 8'd0;
				end else if ((want[1] & mapped[1]) && !amiga_ds[0]) begin
					q_k <= 1'b1;
					q_state <= Q_SETTLE;
					q_cnt <= 8'd0;
				end
			end
		Q_SETTLE:
			if (q_k ? amiga_ds[0] : amiga_ds[1])
				q_state <= Q_IDLE;          // the Amiga took the other drive: later
			else if (q_cnt == SETTLE) begin
				chng_req <= { 1'b1, q_k ? 2'd2 : 2'd1 };
				want[q_k] <= 1'b0;
				// the age counts from the request: a deselect by the Amiga while the answer is on
				// its way asks no second time
				if (q_k) age1 <= 13'd0; else age0 <= 13'd0;
				q_tmo <= 9'd0;
				q_state <= Q_WAIT;
			end else
				q_cnt <= q_cnt + 8'd1;
		Q_WAIT:
			if (ans[2]) begin
				q_state <= Q_IDLE;
				q_miss <= 2'd0;
				if (ans[1:0] == 2'd2)
					line_off <= 1'b1;
				else begin
					line_on <= 1'b1;
					probe_on <= 1'b0;
					// 1: changed or no disk; 0: a disk that was stepped since it went in
					present[ans_k] <= ~ans[0];
					_chng[ans_k] <= ~ans[0];
					if (ans_k) age1 <= 13'd0; else age0 <= 13'd0;
				end
			end else if (q_k ? amiga_ds[0] : amiga_ds[1]) begin
				// the Amiga took the other drive: the line is its now. The answer that is on its way
				// may be of either drive: wait for it (or the timeout) and ask again.
				q_state <= Q_DRAIN;
				want[q_k] <= 1'b1;
			end else if (tick) begin
				if (q_tmo == ANSWER) begin
					// ask again (a lost frame), until NOANSWER in a row
					q_state <= Q_IDLE;
					want[q_k] <= 1'b1;
					q_miss <= q_miss + 2'd1;
					if (q_miss + 2'd1 == NOANSWER)
						line_off <= 1'b1;
				end else
					q_tmo <= q_tmo + 9'd1;
			end
		Q_DRAIN:
			if (ans[2] || (tick && q_tmo == ANSWER))
				q_state <= Q_IDLE;
			else if (tick)
				q_tmo <= q_tmo + 9'd1;
		endcase

		// a new disk chosen in the OSD: changed, and looked for again. A request of the drive
		// on its way is dropped: its answer (a disk in) would hide the change from the Amiga.
		if (chg_k[0]) begin
			present[0] <= 1'b0;
			_chng[0] <= 1'b0;
			want[0] <= 1'b0;
		end
		if (chg_k[1]) begin
			present[1] <= 1'b0;
			_chng[1] <= 1'b0;
			want[1] <= 1'b0;
		end
		if (chg_k[q_k]) begin
			if (q_state == Q_SETTLE) q_state <= Q_IDLE;
			if (q_state == Q_WAIT) q_state <= Q_DRAIN;
		end

		if (reset) begin
			_chng <= 2'b00;
			probe_on <= 1'b0;
			want <= 2'b11;
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
reg [5:0] dir_age = 6'd0;            // clocks since DIR changed
reg [5:0] step_w = 6'd0;             // minimum width
assign step_busy = step_pend | step_q;

always @(posedge clk) begin
	if (clk7_en) begin
		dir_q <= direc;
		if (direc != dir_q)
			dir_age <= 6'd0;
		else if (dir_age != 6'd63)
			dir_age <= dir_age + 6'd1;

		// a step of the Amiga on a physical drive: that drive steps, held selected
		if (!_step && _step_d && amiga_ds != 2'b00) begin
			step_pend <= 1'b1;
			step_ds <= amiga_ds;
		end else if (step_busy && (amiga_ds & ~step_ds) != 2'b00) begin
			// the Amiga took another physical drive: the pulse is dropped
			step_pend <= 1'b0;
			step_q <= 1'b0;
		end else if (step_pend && !step_q && dir_age >= DIR_SETUP && direc == dir_q) begin
			step_q <= 1'b1;
			step_pend <= 1'b0;
			step_w <= STEP_W;
		end else if (step_q) begin
			if (step_w != 6'd0)
				step_w <= step_w - 6'd1;
			else if (_step)
				step_q <= 1'b0;
		end
	end
end

// ---------------- debug ----------------

// DEBUG_ADDR { line_on, line_off, q_miss, q_state, q_k, probe_on, _chng, present, want, mapped }
// DEBUG_DATA { answers, last answer { drive, value }, timeouts } (mod 256 / 16)
reg [7:0] n_ans = 8'd0;
reg [3:0] last_ans = 4'd0;
reg [3:0] n_tmo = 4'd0;
always @(posedge clk) begin
	if (chng_in[4]) begin
		n_ans <= n_ans + 8'd1;
		last_ans <= chng_in[3:0];
	end
	if (clk7_en && tick && q_state == Q_WAIT && q_tmo == ANSWER && !ans[2])
		n_tmo <= n_tmo + 4'd1;
end
assign dbg = { line_on, line_off, q_miss, q_state, q_k, probe_on, _chng, present, want, mapped,
	n_ans, last_ans, n_tmo };

// ---------------- outputs ----------------

wire wgate = ~_write_gate & ext_sel;
assign fdd_out = {
	wgate & ~_write_data,             // WDATA
	wgate,                            // WGATE
	~side,                            // SIDE1: head 1 (side = 0 is the upper head)
	step_q,                           // STEP (of step_ds, held selected)
	~dir_q,                           // DIR: high = in (direc = 0)
	motor,                            // MOTOR
	ds[1],                            // DS1
	ds[0]                             // DS0
};

endmodule
