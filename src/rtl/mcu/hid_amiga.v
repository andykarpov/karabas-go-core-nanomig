`timescale 1ns / 1ps
`default_nettype wire

/*
 hid_amiga.v

 USB HID keyboard reports and mouse deltas from the mcu (mcu.vhd: KB_STATUS, KB_DAT0..5, MS_X/Y/B,
 MS_UPD) to the Minimig keyboard / mouse event interface (kbd_mouse_level, _type, _data).

 Keyboard:
 - the mcu sends a report as 7 frames (modifiers, then the 6 key slots), so a report is taken
   once it has not changed for SETTLE clocks;
 - it is compared with the previous one: changed modifiers, then released and pressed keys, in
   USB HID codes (modifiers as 0x68 + bit, as NanoMig's keymap expects);
 - keymap (misc/amiga_keymap.v) translates them to Amiga key codes, events go to a fifo;
 - caps lock toggles: down when it goes on, up when it goes off, like the Amiga key;
 - CIA-A has no keyboard buffer: an event is sent KEY_GAP clocks after the previous one, at
   about the rate of a real Amiga keyboard.
 Mouse: the deltas of each report are added up (saturated to +-127) and sent as an x event
 (type 0) and a y event (type 1). The buttons go straight through.
 F12 (no Amiga key) gives kbd_reset, held while the key is down.
*/

module hid_amiga #(
	parameter SETTLE = 5600,   // ~200 us at 28 MHz
	parameter KEY_GAP = 28000, // ~1 ms at 28 MHz
	parameter EVT_GAP = 16     // between any two events: 4 cycles of the 7 MHz receivers
) (
	input wire clk,
	input wire reset,

	input wire [7:0] kb_status,
	input wire [7:0] kb_dat0,
	input wire [7:0] kb_dat1,
	input wire [7:0] kb_dat2,
	input wire [7:0] kb_dat3,
	input wire [7:0] kb_dat4,
	input wire [7:0] kb_dat5,

	input wire [7:0] ms_x,
	input wire [7:0] ms_y,
	input wire [2:0] ms_b,
	input wire ms_upd,

	output reg kbd_mouse_level = 1'b0,
	output reg [1:0] kbd_mouse_type = 2'd0,
	output reg [7:0] kbd_mouse_data = 8'd0,
	output reg [2:0] mouse_buttons = 3'd0,
	output wire kbd_reset
);

//---------- report settle ------------

wire [55:0] report_in = { kb_status, kb_dat5, kb_dat4, kb_dat3, kb_dat2, kb_dat1, kb_dat0 };
reg [55:0] report_d = 56'd0;
reg [12:0] settle_cnt = 13'd0;

always @(posedge clk) begin
	report_d <= report_in;
	if (report_in != report_d)
		settle_cnt <= SETTLE;
	else if (settle_cnt != 0)
		settle_cnt <= settle_cnt - 13'd1;
end

wire report_stable = (settle_cnt == 0) && (report_in == report_d);

//---------- report diff ------------

reg [55:0] old_rep = 56'd0; // last processed report
reg [55:0] new_rep = 56'd0;
reg [4:0] step = 5'd0;      // 0-7 modifiers, 8-13 released keys, 14-19 pressed keys
reg busy = 1'b0;
reg caps_on = 1'b0;

wire [7:0] old_mod = old_rep[55:48];
wire [7:0] new_mod = new_rep[55:48];

function [7:0] key_slot(input [55:0] rep, input [2:0] n);
	case (n)
		3'd0: key_slot = rep[7:0];
		3'd1: key_slot = rep[15:8];
		3'd2: key_slot = rep[23:16];
		3'd3: key_slot = rep[31:24];
		3'd4: key_slot = rep[39:32];
		default: key_slot = rep[47:40];
	endcase
endfunction

function key_in(input [55:0] rep, input [7:0] k);
	key_in = (rep[7:0] == k) || (rep[15:8] == k) || (rep[23:16] == k) ||
	         (rep[31:24] == k) || (rep[39:32] == k) || (rep[47:40] == k);
endfunction

wire [2:0] slot = (step >= 5'd14) ? step - 5'd14 : step - 5'd8;
wire [7:0] old_key = key_slot(old_rep, slot);
wire [7:0] new_key = key_slot(new_rep, slot);

// the usb code of this step and whether it is an event: 1 = key, 0 = none
reg [6:0] step_code;
reg       step_event;
reg       step_release;
always @(*) begin
	step_code = 7'h00;
	step_event = 1'b0;
	step_release = 1'b0;
	if (step < 5'd8) begin
		step_code = 7'h68 + step[2:0];
		step_event = old_mod[step[2:0]] != new_mod[step[2:0]];
		step_release = ~new_mod[step[2:0]];
	end
	else if (step < 5'd14) begin
		step_code = old_key[6:0];
		step_event = (old_key >= 8'h04) && (old_key < 8'h68) && !key_in(new_rep, old_key);
		step_release = 1'b1;
	end
	else begin
		step_code = new_key[6:0];
		step_event = (new_key >= 8'h04) && (new_key < 8'h68) && !key_in(old_rep, new_key);
		step_release = 1'b0;
	end
end

wire [6:0] amiga_code;
keymap keymap(
	.code(step_code),
	.amiga(amiga_code)
);

wire caps_key = (step_code == 7'h39) && (step >= 5'd8);

// key event fifo: { release, amiga code }
reg [7:0] fifo [0:15];
reg [3:0] fifo_wp = 4'd0, fifo_rp = 4'd0;
wire fifo_empty = (fifo_wp == fifo_rp);
wire fifo_full = (fifo_wp + 4'd1 == fifo_rp);

always @(posedge clk) begin
	if (reset) begin
		busy <= 1'b0;
		old_rep <= 56'd0;
		caps_on <= 1'b0;
		fifo_wp <= 4'd0;
	end
	else if (!busy) begin
		if (report_stable && report_in != old_rep) begin
			new_rep <= report_in;
			step <= 5'd0;
			busy <= 1'b1;
		end
	end
	else if (!fifo_full) begin
		if (step_event && amiga_code != 7'h7f) begin
			if (caps_key) begin
				// caps lock: a press toggles, the release is not sent
				if (!step_release) begin
					caps_on <= ~caps_on;
					fifo[fifo_wp] <= { caps_on, amiga_code };
					fifo_wp <= fifo_wp + 4'd1;
				end
			end
			else begin
				fifo[fifo_wp] <= { step_release, amiga_code };
				fifo_wp <= fifo_wp + 4'd1;
			end
		end
		if (step == 5'd19) begin
			busy <= 1'b0;
			old_rep <= new_rep;
		end
		else
			step <= step + 5'd1;
	end
end

assign kbd_reset = key_in(old_rep, 8'h45); // F12 (not an Amiga key)

//---------- mouse ------------

reg ms_upd_d = 1'b0;
reg signed [7:0] acc_x = 8'sd0, acc_y = 8'sd0;
wire mouse_take; // the sender takes the accumulated deltas in this clock

function signed [7:0] sat_add(input signed [7:0] a, input signed [7:0] b);
	reg signed [8:0] s;
	begin
		s = a + b;
		if (s > 9'sd127) sat_add = 8'sd127;
		else if (s < -9'sd127) sat_add = -8'sd127;
		else sat_add = s[7:0];
	end
endfunction

wire ms_new = (ms_upd != ms_upd_d);
wire signed [7:0] add_x = ms_new ? $signed(ms_x) : 8'sd0;
wire signed [7:0] add_y = ms_new ? $signed(ms_y) : 8'sd0;

always @(posedge clk) begin
	ms_upd_d <= ms_upd;
	if (ms_new)
		mouse_buttons <= ms_b;
	if (reset) begin
		acc_x <= 8'sd0;
		acc_y <= 8'sd0;
	end
	else if (mouse_take) begin
		acc_x <= add_x;
		acc_y <= add_y;
	end
	else begin
		acc_x <= sat_add(acc_x, add_x);
		acc_y <= sat_add(acc_y, add_y);
	end
end

//---------- event sender ------------

reg [14:0] key_gap = 15'd0;
reg [4:0] evt_gap = 5'd0;
reg y_pending = 1'b0;
reg [7:0] y_data = 8'd0;

wire send_key = !fifo_empty && key_gap == 0;
assign mouse_take = !reset && evt_gap == 0 && !y_pending && !send_key && (acc_x != 0 || acc_y != 0);

always @(posedge clk) begin
	if (key_gap != 0) key_gap <= key_gap - 15'd1;
	if (evt_gap != 0) evt_gap <= evt_gap - 5'd1;

	if (reset) begin
		fifo_rp <= 4'd0;
		y_pending <= 1'b0;
		key_gap <= 15'd0;
	end
	else if (evt_gap == 0) begin
		if (y_pending) begin
			kbd_mouse_type <= 2'd1;
			kbd_mouse_data <= y_data;
			kbd_mouse_level <= ~kbd_mouse_level;
			y_pending <= 1'b0;
			evt_gap <= EVT_GAP;
		end
		else if (send_key) begin
			kbd_mouse_type <= 2'd2;
			kbd_mouse_data <= fifo[fifo_rp];
			kbd_mouse_level <= ~kbd_mouse_level;
			fifo_rp <= fifo_rp + 4'd1;
			key_gap <= KEY_GAP;
			evt_gap <= EVT_GAP;
		end
		else if (mouse_take) begin
			kbd_mouse_type <= 2'd0;
			kbd_mouse_data <= acc_x;
			kbd_mouse_level <= ~kbd_mouse_level;
			y_data <= acc_y;
			y_pending <= 1'b1;
			evt_gap <= EVT_GAP;
		end
	end
end

endmodule
