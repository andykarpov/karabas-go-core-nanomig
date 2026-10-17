`timescale 1ns / 1ps
`default_nettype wire

/*
 fastram_sdram.v

 The Zorro II fast RAM of nanomig (fastram_* of cpu_wrapper, up to 8 MB at $200000-$9FFFFF) on
 the SDRAM of the board (MT48LC16M16A2, 4 banks x 8192 rows x 512 columns x 16 bit), at clk_sys:

 - one port, one word per access, ACTIVE then READ / WRITE with auto precharge, CAS latency 2;
   nothing stays open, so a refresh can come between any two accesses;
 - the sdram clock is clk_sys inverted (SDR_CLK of the top, ODDR2): a command put out at a rising
   edge of clk_sys is in the middle of its sdram clock. The read data come 2 sdram clocks after
   READ and are taken at the rising edge of clk_sys half a clock later;
 - the request (as NanoMig's sdram.sv port 2): sel stays up until ready toggles; the address,
   data, uds / lds (active low) and wr are valid while sel is up. The read data stay on dout until
   the next access. A request is taken again only 2 clocks after the toggle (nanomig drops sel
   one clock after it);
 - an access takes 7 clocks (~250 ns), a refresh 4; a refresh every 7.6 us (8192 rows in 64 ms)
   goes before a request;
 - the address is the cpu word address: column a[9:1], bank a[11:10], row a[23:12].

 Cycle of an access (clock edges of clk_sys):
   0 ACTIVE (row)   1 READ / WRITE (column, A10 = auto precharge, the write data)
   2, 3 NOP         4 the read data into dq_in   5 dout, ready toggles   6 NOP, then idle
 tRCD 20 ns, tRAS 44 ns, tRC 66 ns, tRP 20 ns and tWR 1 clk + 7.5 ns all fit in 35 ns clocks.
*/

module fastram_sdram #(
	parameter INIT_WAIT = 16'd6000,   // >= 100 us of clocks after power-up before the init
	parameter REFRESH = 10'd210       // clocks between refreshes (7.4 us at 28.4 MHz)
) (
	input wire clk,
	input wire reset,                 // power-on (pll not locked)

	// nanomig fastram_*
	input wire sel,
	input wire [23:1] addr,
	input wire lds,
	input wire uds,
	input wire wr,
	input wire [15:0] din,
	output reg [15:0] dout = 16'd0,
	output reg ready = 1'b0,          // toggles at the end of an access

	output wire init_done,

	// the sdram (CS_N and CKE are tied on the board)
	output reg [1:0] sd_ba = 2'b00,
	output reg [12:0] sd_a = 13'd0,
	output reg [1:0] sd_dqm = 2'b11,  // [1] DQ[15:8]
	output reg sd_ras_n = 1'b1,
	output reg sd_cas_n = 1'b1,
	output reg sd_we_n = 1'b1,
	inout wire [15:0] sd_dq
);

// commands: { ras_n, cas_n, we_n }
localparam CMD_NOP = 3'b111;
localparam CMD_ACTIVE = 3'b011;
localparam CMD_READ = 3'b101;
localparam CMD_WRITE = 3'b100;
localparam CMD_PRECHARGE = 3'b010;
localparam CMD_REFRESH = 3'b001;
localparam CMD_MODE = 3'b000;

// mode register: single location write, CAS latency 2, sequential, burst length 1
localparam [12:0] MODE = 13'b000_0_00_010_0_000;

localparam ST_INIT = 3'd0;
localparam ST_IDLE = 3'd1;
localparam ST_ACCESS = 3'd2;
localparam ST_REFRESH = 3'd3;

reg [2:0] state = ST_INIT;
reg [2:0] step = 3'd0;
reg [15:0] wait_cnt = 16'd0;
reg [3:0] init_step = 4'd0;
reg [9:0] ref_cnt = 10'd0;
reg ref_due = 1'b0;
reg acc_wr = 1'b0;

reg [15:0] dq_out = 16'd0;
reg dq_oe = 1'b0;
reg [15:0] dq_in = 16'd0;
assign sd_dq = dq_oe ? dq_out : 16'bzzzzzzzzzzzzzzzz;

assign init_done = (state != ST_INIT);

task cmd;
	input [2:0] c;
	begin
		{ sd_ras_n, sd_cas_n, sd_we_n } <= c;
	end
endtask

always @(posedge clk) begin
	dq_in <= sd_dq;
	cmd(CMD_NOP);
	dq_oe <= 1'b0;

	if (ref_cnt == REFRESH) begin
		ref_cnt <= 10'd0;
		ref_due <= 1'b1;
	end
	else
		ref_cnt <= ref_cnt + 10'd1;

	if (reset) begin
		state <= ST_INIT;
		init_step <= 4'd0;
		wait_cnt <= 16'd0;
		ref_due <= 1'b0;
		sd_dqm <= 2'b11;
	end
	else case (state)
		ST_INIT: begin
			// power-up wait, PRECHARGE ALL, 2 x AUTO REFRESH, LOAD MODE REGISTER; 8 clocks between
			wait_cnt <= wait_cnt + 16'd1;
			if ((init_step == 4'd0 && wait_cnt == INIT_WAIT) || (init_step != 4'd0 && wait_cnt[2:0] == 3'd7)) begin
				wait_cnt <= 16'd0;
				init_step <= init_step + 4'd1;
				case (init_step)
					4'd0: begin
						cmd(CMD_PRECHARGE);
						sd_a <= 13'b0_0100_0000_0000; // A10: all banks
					end
					4'd1, 4'd2: cmd(CMD_REFRESH);
					4'd3: begin
						cmd(CMD_MODE);
						sd_ba <= 2'b00;
						sd_a <= MODE;
					end
					default: begin
						ref_due <= 1'b0;
						state <= ST_IDLE;
					end
				endcase
			end
		end

		ST_IDLE:
			if (ref_due) begin
				ref_due <= 1'b0;
				cmd(CMD_REFRESH);
				step <= 3'd0;
				state <= ST_REFRESH;
			end
			else if (sel) begin
				cmd(CMD_ACTIVE);
				sd_ba <= addr[11:10];
				sd_a <= { 1'b0, addr[23:12] };
				acc_wr <= wr;
				step <= 3'd1;
				state <= ST_ACCESS;
			end

		ST_ACCESS: begin
			step <= step + 3'd1;
			case (step)
				3'd1: begin
					cmd(acc_wr ? CMD_WRITE : CMD_READ);
					sd_a <= { 4'b0010, addr[9:1] }; // A10: auto precharge
					sd_dqm <= acc_wr ? { uds, lds } : 2'b00;
					dq_out <= din;
					dq_oe <= acc_wr;
				end
				3'd2: sd_dqm <= 2'b11;
				3'd5: begin
					dout <= dq_in;
					ready <= ~ready;
				end
				3'd6: state <= ST_IDLE;
				default: ;
			endcase
		end

		ST_REFRESH: begin
			// tRFC 66 ns
			step <= step + 3'd1;
			if (step == 3'd2)
				state <= ST_IDLE;
		end

		default: state <= ST_INIT;
	endcase
end

endmodule
