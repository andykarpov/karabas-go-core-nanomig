`timescale 1ns / 1ps

// hid_amiga: usb reports in 7 frames as the mcu sends them, events out. Short gaps.
// Prints the events and ends with "tb_hid_amiga: N errors".

module tb_hid_amiga;

reg clk = 1'b0;
always #17.6 clk = ~clk;

reg [7:0] st = 0, d0 = 0, d1 = 0, d2 = 0, d3 = 0, d4 = 0, d5 = 0;
reg [7:0] mx = 0, my = 0;
reg [2:0] mb = 0;
reg mupd = 0;

wire level;
wire [1:0] typ;
wire [7:0] data;
wire [2:0] buttons;
wire kreset;

hid_amiga #(.SETTLE(100), .KEY_GAP(200), .EVT_GAP(16)) dut(
	.clk(clk), .reset(1'b0),
	.kb_status(st), .kb_dat0(d0), .kb_dat1(d1), .kb_dat2(d2), .kb_dat3(d3), .kb_dat4(d4), .kb_dat5(d5),
	.ms_x(mx), .ms_y(my), .ms_b(mb), .ms_upd(mupd),
	.kbd_mouse_level(level), .kbd_mouse_type(typ), .kbd_mouse_data(data),
	.mouse_buttons(buttons), .kbd_reset(kreset)
);

// expected events: {type, data}
reg [9:0] expect [0:63];
integer nexp = 0, ngot = 0, errors = 0;

reg level_d = 1'b0;
always @(posedge clk) begin
	level_d <= level;
	if (level != level_d) begin
		$display("%t event type %0d data %02x", $time, typ, data);
		if (ngot >= nexp || expect[ngot] != {typ, data}) begin
			$display("  ERROR: expected %03x", (ngot < nexp) ? expect[ngot] : 10'h3ff);
			errors = errors + 1;
		end
		ngot = ngot + 1;
	end
end

task exp(input [1:0] t, input [7:0] d);
	begin
		expect[nexp] = {t, d};
		nexp = nexp + 1;
	end
endtask

// a report as 7 spi frames, 2 us apart
task report(input [7:0] s, input [7:0] k0, input [7:0] k1, input [7:0] k2);
	begin
		st = s; #2000;
		d0 = k0; #2000;
		d1 = k1; #2000;
		d2 = k2; #2000;
		d3 = 0; #2000;
		d4 = 0; #2000;
		d5 = 0; #2000;
		#30000;
	end
endtask

task mouse(input [7:0] x, input [7:0] y, input [2:0] b);
	begin
		mx = x; my = y; mb = b; mupd = ~mupd;
		#100;
	end
endtask

initial begin
	#1000;
	// a: down, shift: down, a: up, shift: up
	exp(2, 8'h20); report(8'h00, 8'h04, 0, 0);
	exp(2, 8'h60); report(8'h02, 8'h04, 0, 0);
	exp(2, 8'ha0); report(8'h02, 8'h00, 0, 0);
	exp(2, 8'he0); report(8'h00, 8'h00, 0, 0);
	// b, c down; b up while c stays (c moves to slot 0)
	exp(2, 8'h35); exp(2, 8'h33); report(8'h00, 8'h05, 8'h06, 0);
	exp(2, 8'hb5); report(8'h00, 8'h06, 0, 0);
	exp(2, 8'hb3); report(8'h00, 0, 0, 0);
	// caps lock: on (down), release ignored, off (up)
	exp(2, 8'h62); report(8'h00, 8'h39, 0, 0);
	report(8'h00, 0, 0, 0);
	exp(2, 8'he2); report(8'h00, 8'h39, 0, 0);
	report(8'h00, 0, 0, 0);
	// unmapped key (F11) is dropped
	report(8'h00, 8'h44, 0, 0);
	report(8'h00, 0, 0, 0);
	// mouse: the first report is sent at once, the next ones are added up (saturated) while the
	// x/y pair is being sent
	exp(0, 8'd5); exp(1, -8'sd3); exp(0, 8'd127); exp(1, -8'sd4);
	mouse(8'd5, -8'sd3, 3'b001);
	mouse(8'd100, -8'sd2, 3'b001);
	mouse(8'd100, -8'sd2, 3'b000);
	#5000;
	if (buttons != 3'b000) begin $display("ERROR: buttons %b", buttons); errors = errors + 1; end
	// F12 -> keyboard reset while held (no key event: F12 is not an Amiga key)
	report(8'h00, 8'h45, 0, 0);
	#20000;
	if (!kreset) begin $display("ERROR: no kbd_reset"); errors = errors + 1; end
	report(8'h00, 0, 0, 0);
	#20000;
	if (kreset) begin $display("ERROR: kbd_reset stays"); errors = errors + 1; end
	if (ngot != nexp) begin $display("ERROR: %0d events, expected %0d", ngot, nexp); errors = errors + 1; end
	$display("tb_hid_amiga: %0d errors", errors);
	$finish;
end

endmodule
