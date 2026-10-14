// zhdmi_top for simulation: no hdmi output (the tmds encoders stop ISim on X data)
module zhdmi_top(
	input wire clk,
	input wire ds80,
	input wire reset,
	input wire [23:0] vga_rgb,
	input wire vga_hs,
	input wire vga_vs,
	input wire vga_de,
	input wire audio_en,
	input wire [15:0] audio_l,
	input wire [15:0] audio_r,
	output wire [3:0] tmds_p,
	output wire [3:0] tmds_n
);
parameter SAMPLERATE = 32000;
assign tmds_p = 4'b0000;
assign tmds_n = 4'b1111;
endmodule
