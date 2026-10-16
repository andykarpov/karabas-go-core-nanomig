`timescale 1ns / 1ps

// audio_filter.v: the sign and level of the output (the 15-bit mix sign extended), no overflow at
// full scale, and a cutoff of about 4.5 kHz (the peak of a square wave at 500 Hz, 4.5 kHz, 20 kHz).

module tb_audio_filter;

reg clk = 1'b0;
always #17.647 clk = ~clk; // 28.33 MHz

reg signed [14:0] in_l = 0, in_r = 0;
wire signed [15:0] out_l, out_r;

audio_filter dut(.clk(clk), .in_l(in_l), .in_r(in_r), .out_l(out_l), .out_r(out_r));

integer errors = 0;
task check_range(input [255:0] what, input integer got, input integer lo, input integer hi);
	if (got < lo || got > hi) begin
		errors = errors + 1;
		$display("%t ERROR %0s: %0d, expected %0d..%0d", $time, what, got, lo, hi);
	end
	else
		$display("%t %0s: %0d", $time, what, got);
endtask

// a square wave of the full scale at f Hz on the left (the right gets its negation): the peak of
// the output after it settles
integer peak;
task square(input integer f);
	integer n, half;
	begin
		half = 500000000 / f; // ns
		peak = 0;
		for (n = 0; n < 40; n = n + 1) begin
			in_l = (n & 1) ? -15'sd16128 : 15'sd16128;
			in_r = -in_l;
			repeat (half / 35) begin
				@(posedge clk);
				if (n >= 20 && out_l > peak) peak = out_l;
				if (n >= 20 && (out_r + out_l > 3 || out_r + out_l < -3)) begin // the floor of >>> on each side
					errors = errors + 1;
					$display("%t ERROR right %0d, left %0d", $time, out_r, out_l);
				end
			end
		end
	end
endtask

initial begin
	// dc: the level and the sign
	in_l = 15'sd16128; in_r = -15'sd16128;
	#2000000;
	check_range("dc +full scale", out_l, 16120, 16128);
	check_range("dc -full scale", out_r, -16128, -16120);
	in_l = -15'sd1; in_r = 15'sd100;
	#2000000;
	check_range("dc -1", out_l, -2, 0);
	check_range("dc 100", out_r, 99, 100);

	// a square wave of the full scale: peak = A tanh(T/2 / 2 tau), tau = 1 / (2 pi fc) = 35 us
	square(500);   check_range("square 500 Hz", peak, 15500, 16128);
	square(4500);  check_range("square 4.5 kHz", peak, 14000, 15500);
	square(20000); check_range("square 20 kHz", peak, 4800, 6200);

	$display("tb_audio_filter: %0d errors", errors);
	$finish;
end

endmodule
