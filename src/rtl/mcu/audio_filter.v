`timescale 1ns / 1ps
`default_nettype wire

/*
 audio_filter.v

 The output stage of the Amiga 500 for the 15-bit Paula mix of minimig: a one-pole low-pass, as the
 RC filter after the Paula DACs of the A500 (about 4.5 kHz), and 16-bit signed samples for hdmi,
 the PCM5102 and the level meters.

 - Without it the steps of the Paula samples go straight to the 48 kHz hdmi samples and the 27.7 kHz
   of the PCM5102: aliasing, heard as distortion.
 - The level is that of NanoMig (the 15-bit mix sign extended, full scale -6 dB): two channels at
   the maximum volume reach +-16128, so a full-volume game does not drive hdmi and the DAC to 0 dBFS.
 - y += (x - y) / 2^K once every 2^D clocks: fc = 28.33 MHz / 2^D * -ln(1 - 2^-K) / 2pi, with
   D = 5, K = 5: 4.5 kHz.
*/

module audio_filter #(
	parameter D = 5,	// clocks per filter step: 2^D
	parameter K = 5		// filter coefficient: 2^-K
) (
	input wire clk,

	input wire signed [14:0] in_l,
	input wire signed [14:0] in_r,

	output wire signed [15:0] out_l,
	output wire signed [15:0] out_r
);

reg [D-1:0] div = 0;
always @(posedge clk) div <= div + 1'd1;

// the state has K fraction bits, so a step smaller than 2^K still moves it
reg signed [14+K:0] y_l = 0, y_r = 0;
wire signed [15+K:0] d_l = { in_l[14], in_l, {K{1'b0}} } - { y_l[14+K], y_l };
wire signed [15+K:0] d_r = { in_r[14], in_r, {K{1'b0}} } - { y_r[14+K], y_r };

always @(posedge clk) begin
	if (div == 0) begin
		y_l <= y_l + (d_l >>> K);
		y_r <= y_r + (d_r >>> K);
	end
end

assign out_l = { y_l[14+K], y_l[14+K:K] };
assign out_r = { y_r[14+K], y_r[14+K:K] };

endmodule
