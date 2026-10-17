`timescale 1ns / 1ps

// fastram_sdram.v against a model of the MT48LC16M16A2 on SDR_CLK = clk_sys inverted (the ODDR2
// of the tops) and a requester that behaves as nanomig: sel up at a clock, address / data / ds /
// wr valid while it is up, sel down one clock after ready toggled (frr_d).
// The model checks: the init (100 us, PRECHARGE ALL, 2 refreshes, mode CL2 BL1), commands only on
// idle / active banks as they need, tRCD, tRAS, tRP, tRC, tWR, tRFC, the refresh interval
// (<= 7.8 us); it puts out read data 2 sdram clocks after READ with tAC 5.4 ns and tOH 2.7 ns
// (X in between), so a read taken at the wrong edge gets X.
// Random reads and writes (byte masks) over 8 MB, against a reference memory; back-to-back
// requests and requests that wait for a refresh.
// Ends with "tb_fastram: N errors".

module tb_fastram;

reg clk = 1'b0;
always #17.647 clk = ~clk; // 28.33 MHz
wire sdr_clk = ~clk;

integer errors = 0;
task check(input [255:0] what, input [31:0] got, input [31:0] exp);
	if (got !== exp) begin
		errors = errors + 1;
		if (errors < 30) $display("%t ERROR %0s: %0x, expected %0x", $time, what, got, exp);
	end
endtask
task fail(input [255:0] what);
	begin
		errors = errors + 1;
		if (errors < 30) $display("%t ERROR %0s", $time, what);
	end
endtask

reg reset = 1'b1;
reg sel = 1'b0;
reg [23:1] addr = 0;
reg lds = 1'b1, uds = 1'b1, wr = 1'b0;
reg [15:0] din = 0;
wire [15:0] dout;
wire ready, init_done;

wire [1:0] ba, dqm;
wire [12:0] a;
wire ras_n, cas_n, we_n;
wire [15:0] dq;

fastram_sdram dut(
	.clk(clk), .reset(reset),
	.sel(sel), .addr(addr), .lds(lds), .uds(uds), .wr(wr), .din(din), .dout(dout), .ready(ready),
	.init_done(init_done),
	.sd_ba(ba), .sd_a(a), .sd_dqm(dqm), .sd_ras_n(ras_n), .sd_cas_n(cas_n), .sd_we_n(we_n),
	.sd_dq(dq)
);

// ---------------- SDRAM model ----------------

reg [15:0] mem [0:(1<<22)-1]; // 8 MB is what the test uses: bank 2 bits, row 11 bits, col 9 bits
reg        b_act [0:3];
reg [12:0] b_row [0:3];
time       b_act_t [0:3];
time       b_pre_t [0:3];    // when the bank is precharged (idle) at the earliest
time       last_ref = 0, last_ref_end = 0;
reg        mode_ok = 1'b0;
integer    n_ref = 0, n_init_ref = 0;
reg        init_pre = 1'b0;
time       max_ref_gap = 0;

reg [15:0] rd_q [0:2];   // read pipeline: data, valid
reg        rd_v [0:2];
reg [15:0] dq_drv = 16'hzzzz;
assign dq = dq_drv;

localparam tRCD = 20, tRAS = 42, tRP = 20, tRC = 60, tWR = 15, tRFC = 66;
localparam tAC = 5.4, tOH = 2.7;

integer k;
initial for (k = 0; k < 4; k = k + 1) begin b_act[k] = 0; b_pre_t[k] = 0; b_act_t[k] = 0; end

function [21:0] maddr(input [1:0] b, input [12:0] r, input [8:0] c);
	maddr = { r[10:0], b, c };
endfunction

reg [2:0] c3;
always @(posedge sdr_clk) begin
	// read pipeline (CL 2): data of a READ at edge n are driven after edge n+2
	if (rd_v[1]) begin
		#(tOH) dq_drv = 16'hxxxx;
		#(tAC - tOH) dq_drv = rd_q[1];
	end
	else begin
		#(tOH) dq_drv = 16'hzzzz;
	end
end
always @(posedge sdr_clk) begin
	rd_v[1] <= rd_v[0]; rd_q[1] <= rd_q[0];
	rd_v[0] <= 1'b0;
	c3 = { ras_n, cas_n, we_n };
	case (c3)
		3'b011: begin // ACTIVE
			if (!mode_ok) fail("ACTIVE before the mode register");
			if (b_act[ba]) fail("ACTIVE on an active bank");
			if ($time < b_pre_t[ba]) fail("ACTIVE before tRP");
			if ($time - b_act_t[ba] < tRC && b_act_t[ba] != 0) fail("ACTIVE before tRC");
			if ($time < last_ref_end) fail("ACTIVE before tRFC");
			b_act[ba] = 1; b_row[ba] = a; b_act_t[ba] = $time;
		end
		3'b101, 3'b100: begin // READ / WRITE
			if (!b_act[ba]) fail("READ / WRITE on an idle bank");
			if ($time - b_act_t[ba] < tRCD) fail("READ / WRITE before tRCD");
			if (!a[10]) fail("READ / WRITE without auto precharge");
			if (c3 == 3'b100) begin
				if (!dqm[1]) mem[maddr(ba, b_row[ba], a[8:0])][15:8] = dq[15:8];
				if (!dqm[0]) mem[maddr(ba, b_row[ba], a[8:0])][7:0] = dq[7:0];
				if (!dqm[1] && ^dq[15:8] === 1'bx) fail("write data X");
				if (!dqm[0] && ^dq[7:0] === 1'bx) fail("write data X");
				// auto precharge after tWR, done tRP later; tRAS from ACTIVE
				b_pre_t[ba] = (($time + tWR > b_act_t[ba] + tRAS) ? $time + tWR : b_act_t[ba] + tRAS) + tRP;
			end
			else begin
				if (dqm != 2'b00) fail("read with dqm");
				rd_v[0] <= 1'b1; rd_q[0] <= mem[maddr(ba, b_row[ba], a[8:0])];
				b_pre_t[ba] = (($time + 35 > b_act_t[ba] + tRAS) ? $time + 35 : b_act_t[ba] + tRAS) + tRP;
			end
			b_act[ba] = 0;
		end
		3'b010: begin // PRECHARGE
			if (!a[10]) fail("PRECHARGE of one bank");
			for (k = 0; k < 4; k = k + 1) begin b_act[k] = 0; b_pre_t[k] = $time + tRP; end
			if ($time < 100000) fail("init before 100 us");
			init_pre = 1;
		end
		3'b001: begin // AUTO REFRESH
			for (k = 0; k < 4; k = k + 1) begin
				if (b_act[k]) fail("REFRESH with an active bank");
				if ($time < b_pre_t[k]) fail("REFRESH before tRP");
			end
			if ($time < last_ref_end) fail("REFRESH before tRFC");
			if (!init_pre) fail("REFRESH before PRECHARGE ALL");
			if (mode_ok && last_ref != 0 && $time - last_ref > max_ref_gap) max_ref_gap = $time - last_ref;
			last_ref = $time; last_ref_end = $time + tRFC;
			n_ref = n_ref + 1;
			if (!mode_ok) n_init_ref = n_init_ref + 1;
		end
		3'b000: begin // LOAD MODE REGISTER
			if (n_init_ref < 2) fail("mode register before 2 refreshes");
			check("mode register", a, 13'h020);
			mode_ok = 1;
		end
		default: ;
	endcase
end

// ---------------- requester (nanomig) ----------------

reg [15:0] refm [0:(1<<22)-1];
reg [21:0] ra;
reg frr_d = 1'b0;
always @(posedge clk) frr_d <= ready;

integer n_rd = 0, n_wr = 0;
time t0, t_max = 0;
task access(input w, input [22:0] wa, input [1:0] ds_n, input [15:0] d);
	begin
		@(posedge clk);
		sel <= 1'b1; addr <= wa; wr <= w; din <= d; { uds, lds } <= ds_n;
		t0 = $time;
		@(posedge clk);
		while (ready == frr_d) @(posedge clk);
		// nanomig: sel drops at the clock after the toggle; the data are taken there
		sel <= 1'b0; wr <= 1'b0; din <= 16'hxxxx; { uds, lds } <= 2'b11; addr <= 23'hxxxxxx;
		if ($time - t0 > t_max) t_max = $time - t0;
		if (w) begin
			if (!ds_n[1]) refm[wa][15:8] = d[15:8];
			if (!ds_n[0]) refm[wa][7:0] = d[7:0];
			n_wr = n_wr + 1;
		end
		else begin
			check("read data", dout, refm[wa]);
			n_rd = n_rd + 1;
		end
	end
endtask

integer i, j;
reg [22:0] wa;
initial begin
	for (i = 0; i < (1 << 22); i = i + 1) begin mem[i] = i[15:0] ^ 16'h5A5A; refm[i] = mem[i]; end
	repeat (10) @(posedge clk);
	reset <= 1'b0;
	wait (init_done);
	if ($time < 100000) fail("init done before 100 us");
	$display("%t init done", $time);

	// the address mapping: column a[9:1], bank a[11:10], row a[23:12]
	access(1'b1, 23'h000001, 2'b00, 16'h1234);
	check("mapped column", mem[maddr(2'd0, 13'd0, 9'd1)], 16'h1234);
	access(1'b1, 23'h1FFE02, 2'b00, 16'hBEEF); // word 0x1FFE02: row 0x3FF, bank 3, col 2
	check("mapped bank / row", mem[maddr(2'd3, 13'h3FF, 9'd2)], 16'hBEEF);
	access(1'b0, 23'h1FFE02, 2'b00, 0);
	// byte writes
	access(1'b1, 23'h000010, 2'b01, 16'hAABB); // upper only
	access(1'b1, 23'h000011, 2'b10, 16'hCCDD); // lower only
	access(1'b0, 23'h000010, 2'b00, 0);
	access(1'b0, 23'h000011, 2'b00, 0);

	// random, some back to back, some with gaps
	for (i = 0; i < 4000; i = i + 1) begin
		wa = { 1'b0, $random } & 23'h3FFFFF;
		if (i % 3 == 0) wa = (wa & 23'h3FF000) | (i & 15); // the same rows again
		case ($random & 3)
			0: access(1'b1, wa, 2'b00, $random);
			1: access(1'b1, wa, ($random & 1) ? 2'b01 : 2'b10, $random);
			default: access(1'b0, wa, 2'b00, 0);
		endcase
		j = $random & 31;
		if (j > 24) repeat (j) @(posedge clk);
	end

	// idle for a while: refreshes go on
	#50000;
	check("refreshes keep going", n_ref > 0, 1);
	$display("reads %0d writes %0d refreshes %0d, longest refresh gap %0d ns, longest access %0d ns",
	         n_rd, n_wr, n_ref, max_ref_gap, t_max);
	if (max_ref_gap > 7800) fail("refresh gap over 7.8 us");
	$display("tb_fastram: %0d errors", errors);
	$finish;
end

initial begin
	#200000000;
	$display("%t ERROR watchdog", $time);
	$display("tb_fastram: %0d errors", errors + 1);
	$finish;
end

endmodule
