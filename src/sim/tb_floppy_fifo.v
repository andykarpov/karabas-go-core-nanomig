`timescale 1ns / 1ps

// paula_floppy_fifo against a queue model: random writes and reads at clk7_en, as the PLL of a
// physical drive (a word now and then, the fifo mostly empty or with one word) and the disk dma
// (reads in bursts). The input holds the next word until it is written, as ext_rx of the PLL.
// out has to be the head of the queue whenever rd comes with a word in the fifo.
module tb_floppy_fifo;

reg clk = 1'b0;
always #17.4 clk = ~clk;
reg [1:0] div = 2'd0;
reg clk7_en = 1'b0;
always @(posedge clk) begin
	div <= div + 2'd1;
	clk7_en <= (div == 2'd3);
end

reg reset = 1'b1;
reg rd = 1'b0, wr = 1'b0;
reg [15:0] in = 16'd0;
wire [15:0] out;
wire empty, full;

paula_floppy_fifo dut (
	.clk(clk), .clk7_en(clk7_en), .reset(reset), .in(in), .out(out),
	.rd(rd), .wr(wr), .empty(empty), .full(full)
);

reg [15:0] q [0:4095];
integer head = 0, tail = 0;
integer errors = 0, nrd = 0, nboth = 0, phase, n;

always @(posedge clk) begin
	if (clk7_en && !reset) begin
		if (rd && !empty) begin
			if (head == tail) begin
				errors = errors + 1;
				$display("%t: read of an empty model", $time);
			end else if (out !== q[head % 4096]) begin
				if (errors < 10) $display("%t: out %h, expected %h (words in the fifo %0d, wr %b)",
					$time, out, q[head % 4096], tail - head, wr);
				errors = errors + 1;
			end
			head = head + 1;
			nrd = nrd + 1;
			if (wr && !full) nboth = nboth + 1;
		end
		if (wr && !full) begin
			q[tail % 4096] = in;
			tail = tail + 1;
		end
	end
end

// the stimulus changes after the clk7_en edge
always @(posedge clk) begin
	if (clk7_en) begin
		#1;
		if (wr && !full) in = in + 16'd1;
		case (phase)
		0: begin                     // PLL rate: a word every 1..20 cycles, reads now and then
			wr = ($random % 8) == 0;
			rd = ($random % 6) == 0;
		end
		1: begin                     // both often: the one-word case with a write in the same cycle
			wr = ($random % 2) == 0;
			rd = ($random % 2) == 0;
		end
		default: begin               // a burst in, a burst out (image)
			wr = ($random % 4) != 0;
			rd = ($random % 5) == 0;
		end
		endcase
	end
end

initial begin
	phase = 0;
	#200 reset = 1'b0;
	for (n = 0; n < 3; n = n + 1) begin
		phase = n;
		#3000000;
	end
	$display("tb_floppy_fifo: %0d words read, %0d with a write in the same cycle", nrd, nboth);
	$display("tb_floppy_fifo: %0d errors", errors);
	$finish;
end

endmodule
