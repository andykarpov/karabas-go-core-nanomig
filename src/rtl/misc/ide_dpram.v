// ide_dpram: 4096 x 16 true dual port RAM for the IDE sector buffers (minimig-aga/ide.v).
// NanoMig uses a Gowin DPB primitive here; this is the same interface as an inferred block RAM
// for ISE (registered reads, read-first). The clock enables, output enables and resets are tied
// off by ide.v and are ignored.
module ide_dpram (
	input             clka,
	input             reseta,
	input             cea,
	input             ocea,
	input      [11:0] ada,
	input             wrea,
	input      [15:0] dina,
	output reg [15:0] douta,

	input             clkb,
	input             resetb,
	input             ceb,
	input             oceb,
	input      [11:0] adb,
	input             wreb,
	input      [15:0] dinb,
	output reg [15:0] doutb
);

reg [15:0] mem [0:4095];

always @(posedge clka) begin
	if (wrea) mem[ada] <= dina;
	douta <= mem[ada];
end

always @(posedge clkb) begin
	if (wreb) mem[adb] <= dinb;
	doutb <= mem[adb];
end

endmodule
