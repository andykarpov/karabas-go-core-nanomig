`timescale 1ns / 1ps
`default_nettype wire

/*-------------------------------------------------------------------------------------------------------------------
--
-- https://github.com/andykarpov/karabas-go
--
-- NanoMig (Minimig, Amiga 500 OCS/ECS) core for Karabas-Go Mini (rev.C, before rev.G)
--
-- The core logic is the one of karabas_minig_top.v; only the board glue differs (see
-- karabas-go-core-profi rtl/karabas_mini_top.vhd and karabas_mini.ucf):
--   Audio: no I2S DAC on this board. AUDIO_L / AUDIO_R are sigma-delta outputs (rtl/dac/dac.vhd)
--     into an RC filter.
--   MCU link: MCU_IO is 4 bits ([0] burst cs_n, [1] burst ready, as rev.G). MCU_SCK is not on a
--     global clock pin, so the bursts run at the normal link clock (BURST_MAX_MHZ = 0).
--   Video: HDMI as on rev.G.
--   No ESP32 I2S / spi; ESP_RESET_N, ESP_BOOT_N, MIDI_CLK, MIDI_RESET_N, FT_RESET exist and are
--     held inactive.
--
-- Memory: the two 2Mx8 SRAM chips are used as one 2Mx16 SRAM (4 MB), like the async SRAM
-- of the original Minimig board:
--   Minimig ram_address[22:1] uses the 512 KB segments 0-3 (chip RAM, $000000) and 12-15
--   (slow RAM at $C00000, Kickstart at $F80000). MA = {ram_address[22], ram_address[20:1]}
--   folds them into the 8 segments of the SRAM: chip RAM 0-3, slow RAM 4-6, Kickstart 7.
-- Kickstart: loaded by the MCU from the SD card (an external rom of core_mini.json) to SRAM
--   byte address 0x380000 (segment 7). A 256 KB Kickstart (1.2, 1.3) is mirrored in the upper half
--   of the segment, as on the A500. The 68000 is big endian: even bytes go to the high byte
--   (MD[15:8]).
------------------------------------------------------------------------------------------------------------------*/

module karabas_mini_top #(
	parameter RESET_DELAY = 16'hFFFF // clk_sys cycles of cpu reset after the mcu is ready
) (
	input wire CLK_50MHZ,

	input wire UART_RX,
	output wire UART_TX,
	output wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_DI,
	input wire SD_DO,
	output wire SD_CLK,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	inout wire FT_SPI_MISO,
	inout wire FT_SPI_MOSI,
	inout wire FT_INT_N,
	inout wire FT_CLK,
	input wire FT_AUDIO,
	input wire FT_DE,
	input wire FT_DISP,
	output wire FT_RESET,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	input wire TAPE_IN,
	output wire TAPE_OUT,
	output wire AUDIO_L,
	output wire AUDIO_R,

	output wire ADC_CLK,
	output wire ADC_BCK,
	output wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	input wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [3:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

//---------- Unused peripherals ------------

assign TAPE_OUT = 1'b0;
assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'b0;
assign ADC_LRCK = 1'b0;
assign UART_CTS = 1'b0;
assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b0;
assign WD = 16'bzzzzzzzzzzzzzzzz;
assign SDR_BA = 2'b00;
assign SDR_A = 13'd0;
assign SDR_CLK = 1'b0;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bzzzzzzzzzzzzzzzz;
assign SD_CS_N = 1'b1;
assign SD_DI = 1'b1;
assign SD_CLK = 1'b0;
// FT812 not used (no clock on FT_CLK_OUT, as on rev.G); FT_RESET high as in the other cores
// that do not use it
assign FT_SPI_CS_N = 1'b1;
assign FT_SPI_SCK = 1'b0;
assign FT_SPI_MISO = 1'bz;
assign FT_SPI_MOSI = 1'bz;
assign FT_INT_N = 1'bz;
assign FT_CLK = 1'bz;
assign FT_RESET = 1'b1;
assign FT_CLK_OUT = 1'b0;
assign MIDI_TX = 1'b1;
assign MIDI_CLK = 1'b1;
assign MIDI_RESET_N = 1'b1;
assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

//---------- Clock ------------

// 50 MHz * 17 / 30 = 28.333 MHz (PAL Amiga: 28.375 MHz)
wire clk_in, clkfb, clkfb_buf, clkout0, locked;
wire clk_sys;

IBUFG u_clk_in (.I(CLK_50MHZ), .O(clk_in));

PLL_BASE #(
	.BANDWIDTH("OPTIMIZED"),
	.CLK_FEEDBACK("CLKFBOUT"),
	.COMPENSATION("SYSTEM_SYNCHRONOUS"),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(17),
	.CLKFBOUT_PHASE(0.000),
	.CLKOUT0_DIVIDE(30),
	.CLKOUT0_PHASE(0.000),
	.CLKOUT0_DUTY_CYCLE(0.500),
	.CLKIN_PERIOD(20.000),
	.REF_JITTER(0.010)
) u_pll (
	.CLKFBOUT(clkfb),
	.CLKOUT0(clkout0),
	.CLKOUT1(),
	.CLKOUT2(),
	.CLKOUT3(),
	.CLKOUT4(),
	.CLKOUT5(),
	.LOCKED(locked),
	.RST(1'b0),
	.CLKFBIN(clkfb_buf),
	.CLKIN(clk_in)
);

BUFG u_clkfb_buf (.I(clkfb), .O(clkfb_buf));
BUFG u_clk_sys (.I(clkout0), .O(clk_sys));

wire areset = ~locked;

//---------- MCU ------------

wire romloader_act;
wire [31:0] romloader_addr;
wire [7:0] romloader_data;
wire romloader_wr;
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire dvi_only;
wire [7:0] kb_status, kb_dat0, kb_dat1, kb_dat2, kb_dat3, kb_dat4, kb_dat5;
wire [7:0] ms_x, ms_y;
wire [7:0] img_mounted;
wire [63:0] img_size;
wire img_data_wr, img_result_wr, img_q_wr, img_q_ack;
wire [8:0] img_data_addr;
wire [7:0] img_data, img_result;
wire [15:0] img_sum;
wire [23:0] img_q_di;
wire [2:0] ms_b;
wire ms_upd;
wire [12:0] joy_l, joy_r;
wire matrix_cmd_wr;
wire [23:0] matrix_cmd;

// mcu chip selects: low goes through at once, high only after 3 clocks high. A short spike on a
// chip select (the sram outputs switch next to them all the time) reset the spi receivers in
// the middle of a frame: the frame got lost in both directions.
reg [2:0] mcu_cs_sync = 3'b111, mcu_burst_cs_sync = 3'b111;
always @(posedge clk_sys) begin
	mcu_cs_sync <= { mcu_cs_sync[1:0], MCU_CS_N };
	mcu_burst_cs_sync <= { mcu_burst_cs_sync[1:0], MCU_IO[0] };
end
wire mcu_cs_n = MCU_CS_N & (&mcu_cs_sync);
wire mcu_burst_cs_n = MCU_IO[0] & (&mcu_burst_cs_sync);

// burst transfers from the mcu (karabas-go-firmware docs/burst_protocol.md)
wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[3:2] = 2'bzz;

// Mini (before rev.G): MCU_SCK (C3) is not on a global clock pin (CLOCK_DEDICATED_ROUTE = FALSE in
// the ucf), so no faster bursts are announced: BURST_MAX_MHZ = 0, bursts at the normal link clock
mcu #(.BURST_MAX_MHZ(0)) mcu(
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(MCU_SCK),
	.MCU_SS(mcu_cs_n),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),
	.MCU_BURST_CS_N(mcu_burst_cs_n),
	.MCU_BURST_READY(mcu_burst_ready),

	.MS_X(ms_x),
	.MS_Y(ms_y),
	.MS_B(ms_b),
	.MS_Z(),
	.MS_UPD(ms_upd),

	.KB_STATUS(kb_status),
	.KB_DAT0(kb_dat0),
	.KB_DAT1(kb_dat1),
	.KB_DAT2(kb_dat2),
	.KB_DAT3(kb_dat3),
	.KB_DAT4(kb_dat4),
	.KB_DAT5(kb_dat5),

	.JOY_L(joy_l),
	.JOY_R(joy_r),

	.RTC_A(8'h00),
	.RTC_DI(8'h00),
	.RTC_DO(),
	.RTC_CS(1'b0),
	.RTC_WR_N(1'b1),

	.UART_RX_DATA(),
	.UART_RX_IDX(),
	.UART_TX_DATA(8'h00),
	.UART_TX_WR(1'b0),

	.ROMLOADER_ACTIVE(romloader_act),
	.ROMLOAD_ADDR(romloader_addr),
	.ROMLOAD_DATA(romloader_data),
	.ROMLOAD_WR(romloader_wr),

	.SOFTSW_COMMAND(softsw_command),
	.OSD_COMMAND(osd_command),

	.FT_MISO(1'b1),
	.SD2_MISO(1'b1),

	.MATRIX_CMD(matrix_cmd),
	.MATRIX_CMD_WR(matrix_cmd_wr),

	.IMG_MOUNTED(img_mounted),
	.IMG_SIZE(img_size),
	.IMG_DATA_WR(img_data_wr),
	.IMG_DATA_ADDR(img_data_addr),
	.IMG_DATA(img_data),
	.IMG_RESULT_WR(img_result_wr),
	.IMG_RESULT(img_result),
	.IMG_SUM(img_sum),
	.IMG_Q_WR(img_q_wr),
	.IMG_Q_DI(img_q_di),
	.IMG_Q_ACK(img_q_ack),

	.HWID(),
	.DVI_ONLY(dvi_only),

	.BUSY(mcu_busy)
);

//---------- Soft switches (the order of the osd items in core_mini.json) ------------
// items 0 and 1 are the file mounters DF0 / DF1 (no switch); Reset is always the last item

reg [1:0] sw_chipset = 2'd0;   // 0 = OCS-A500, 1 = OCS-A1000, 2 = ECS
reg [1:0] sw_chipmem = 2'd0;   // 0 = 512K, 1 = 1M, 2 = 1.5M, 3 = 2M
reg [1:0] sw_slowmem = 2'd1;   // 0 = none, 1 = 512K, 2 = 1M, 3 = 1.5M
reg       sw_ntsc = 1'b0;
reg       sw_debug = 1'b0;     // input debug bar
reg       sw_wprot = 1'b1;     // floppy write protect
reg       sw_reset = 1'b0;
reg [15:0] prev_softsw_command = 16'hFFFF;

always @(posedge clk_sys) begin
	if (prev_softsw_command != softsw_command) begin
		prev_softsw_command <= softsw_command;
		case (softsw_command[15:8])
			8'h02: sw_chipset <= softsw_command[1:0];
			8'h03: sw_chipmem <= softsw_command[1:0];
			8'h04: sw_slowmem <= softsw_command[1:0];
			8'h05: sw_ntsc <= softsw_command[0];
			8'h06: sw_debug <= softsw_command[0];
			8'h07: sw_wprot <= ~softsw_command[0]; // 0 = On
			8'h08: sw_reset <= softsw_command[0];
			default: ;
		endcase
	end
end

//---------- Keyboard and mouse ------------

wire kbd_mouse_level;
wire [1:0] kbd_mouse_type;
wire [7:0] kbd_mouse_data;
wire [2:0] mouse_buttons;
wire kbd_reset;

hid_amiga hid_amiga(
	.clk(clk_sys),
	.reset(areset),

	.kb_status(kb_status),
	.kb_dat0(kb_dat0),
	.kb_dat1(kb_dat1),
	.kb_dat2(kb_dat2),
	.kb_dat3(kb_dat3),
	.kb_dat4(kb_dat4),
	.kb_dat5(kb_dat5),

	.ms_x(ms_x),
	.ms_y(ms_y),
	.ms_b(ms_b),
	.ms_upd(ms_upd),

	.kbd_mouse_level(kbd_mouse_level),
	.kbd_mouse_type(kbd_mouse_type),
	.kbd_mouse_data(kbd_mouse_data),
	.mouse_buttons(mouse_buttons),
	.kbd_reset(kbd_reset)
);

//---------- Joysticks ------------

// mcu JOY_L / JOY_R: [0] connected, [1] up, [2] down, [3] left, [4] right, [5] start, [6] A,
// [7] B, [8] C, [9] X, [10] Y, [11] Z, [12] mode.
// nanomig joystick0 / joystick1: [7:0] fire4, fire3, fire2, fire, up, down, left, right.
// joystick0 is Amiga port 2 (the joystick port), joystick1 port 1, which the usb mouse shares:
// userio switches port 1 to the joystick on its fire button and back to the mouse on the left
// mouse button.
wire [7:0] joy0 = { joy_l[5], joy_l[8], joy_l[7], joy_l[6], joy_l[1], joy_l[2], joy_l[3], joy_l[4] };
wire [7:0] joy1 = { joy_r[5], joy_r[8], joy_r[7], joy_r[6], joy_r[1], joy_r[2], joy_r[3], joy_r[4] };

//---------- Reset ------------

// the Amiga is held in reset while the mcu loads the core roms, and by Ctrl + Amiga + Amiga
wire cpu_reset_req = areset | mcu_busy | romloader_act | sw_reset | kbd_reset;
reg [15:0] reset_cnt = 16'hFFFF;
always @(posedge clk_sys) begin
	if (cpu_reset_req)
		reset_cnt <= RESET_DELAY;
	else if (reset_cnt != 0)
		reset_cnt <= reset_cnt - 16'd1;
end
wire cpu_reset = |reset_cnt;

//---------- NanoMig ------------

wire [7:0] sdc_img_mounted, sdc_rd, sdc_wr;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector;
wire sdc_busy, sdc_done, sdc_byte_in_strobe;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, sdc_byte_out_data;
wire img_active;

wire clk7_en, clk7n_en;
wire hs, vs;
wire [3:0] red, green, blue;
wire [14:0] audio_left, audio_right;

wire [15:0] ram_dout;
wire [23:1] ram_a;
wire _ram_bhe, _ram_ble, _ram_we, _ram_oe;
reg  [15:0] ram_din;

wire [5:0] chipset_config = { 1'b0, sw_chipset, sw_ntsc, 1'b0 };
wire [7:0] memory_config = { 4'b0000, sw_slowmem, sw_chipmem };
wire [2:0] fastram_config = 3'b000;
wire [3:0] floppy_config = { 2'b01, sw_wprot, 1'b0 }; // 2 drives (DF0, DF1), write protect, no turbo
wire [3:0] video_config = 4'b0000; // Amber filters off, scanlines not built
wire [5:0] ide_config = 6'b000000;

nanomig nanomig(
	.clk_sys(clk_sys),
	.reset(cpu_reset),
	.por(areset),

	.clk7_en(clk7_en),
	.clk7n_en(clk7n_en),
	.cpu_nrst_out(),

	.pwr_led(),
	.fdd_led(),
	.hdd_led(),

	.hs(hs),
	.vs(vs),
	.r(red),
	.g(green),
	.b(blue),

	.memory_config(memory_config),
	.fastram_config(fastram_config),
	.chipset_config(chipset_config),
	.floppy_config(floppy_config),
	.video_config(video_config),
	.ide_config(ide_config),

	.audio_left(audio_left),
	.audio_right(audio_right),

	.mouse_buttons(mouse_buttons),
	.kbd_mouse_level(kbd_mouse_level),
	.kbd_mouse_type(kbd_mouse_type),
	.kbd_mouse_data(kbd_mouse_data),
	.joystick0(joy0),
	.joystick1(joy1),

	.uart_tx(UART_TX),
	.uart_rx(UART_RX),

	.sdc_img_mounted(sdc_img_mounted),
	.sdc_img_size(sdc_img_size),
	.sdc_rd(sdc_rd),
	.sdc_wr(sdc_wr),
	.sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy),
	.sdc_done(sdc_done),
	.sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(sdc_byte_out_data),

	.ram_data(ram_dout),
	.ramdata_in(ram_din),
	.chip48(48'd0),
	.refresh(),
	.ram_address(ram_a),
	._ram_bhe(_ram_bhe),
	._ram_ble(_ram_ble),
	._ram_we(_ram_we),
	._ram_oe(_ram_oe),

	// no fast ram (fastram_config = 0)
	.fastram_sel(),
	.fastram_addr(),
	.fastram_lds(),
	.fastram_uds(),
	.fastram_dout(16'h0000),
	.fastram_din(),
	.fastram_wr(),
	.fastram_ready(1'b0)
);

//---------- Disk images (file mounter of the mcu) ------------

img_sdc img_sdc(
	.clk(clk_sys),
	.reset(areset),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_data_wr(img_data_wr),
	.img_data_addr(img_data_addr),
	.img_data(img_data),
	.img_result_wr(img_result_wr),
	.img_result(img_result),
	.img_sum(img_sum),
	.img_q_wr(img_q_wr),
	.img_q_di(img_q_di),
	.img_q_ack(img_q_ack),

	.sdc_img_mounted(sdc_img_mounted),
	.sdc_img_size(sdc_img_size),
	.sdc_rd(sdc_rd),
	.sdc_wr(sdc_wr),
	.sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy),
	.sdc_done(sdc_done),
	.sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(sdc_byte_out_data),

	.active(img_active)
);

//---------- SRAM ------------

// 28 MHz phase counter of the 7 MHz bus cycle, as NanoMig's sdram sync (cyc 0 follows clk7_en).
// Minimig drives the address and the read/write request at the start of the cycle and takes the
// read data at its end:
//   cyc 0 edge: address and read output enable
//   cyc 1 edge: read data latched (address out for ~35 ns, 10 ns SRAM); write data and byte
//               write strobes (low for two clocks)
//   cyc 3 edge: write strobes released
// Minimig takes the read data at the cyc 2 edge (one clock later the cpu gets the data of the
// previous read).
reg [1:0] cyc = 2'd0;
always @(posedge clk_sys) begin
	if (clk7_en)
		cyc <= 2'd0;
	else
		cyc <= cyc + 2'd1;
end

reg [20:0] sram_a = 21'd0;
reg [15:0] sram_d = 16'd0;
reg        sram_drive = 1'b0;
reg [1:0]  sram_wr_n = 2'b11; // [1] high byte MD[15:8], [0] low byte MD[7:0]
reg [1:0]  sram_rd_n = 2'b11;

// rom loader: one byte per ROMLOAD_WR, at least ~250 ns apart
reg [1:0] ld_cnt = 2'd0;

// a Kickstart loaded into the lower 256 KB of segment 7 only (1.2, 1.3) is mirrored into the
// upper 256 KB: the A500 sees a 256 KB rom at both $F80000 and $FC0000. A 512 KB rom writes both
// halves.
reg kick_lo = 1'b0, kick_hi = 1'b0;
wire kick_mirror = kick_lo & ~kick_hi;
reg romloader_act_d = 1'b0;
always @(posedge clk_sys) begin
	romloader_act_d <= romloader_act;
	if (romloader_act && !romloader_act_d) begin
		kick_lo <= 1'b0;
		kick_hi <= 1'b0;
	end
	else if (romloader_act && romloader_wr && romloader_addr[21:19] == 3'b111) begin
		if (romloader_addr[18])
			kick_hi <= 1'b1;
		else
			kick_lo <= 1'b1;
	end
end

always @(posedge clk_sys) begin
	if (romloader_act) begin
		sram_rd_n <= 2'b11;
		if (romloader_wr) begin
			sram_a <= romloader_addr[21:1];
			sram_d <= { romloader_data, romloader_data };
			sram_drive <= 1'b1;
			ld_cnt <= 2'd3;
		end
		else if (ld_cnt != 2'd0)
			ld_cnt <= ld_cnt - 2'd1;

		if (ld_cnt == 2'd3)
			sram_wr_n <= romloader_addr[0] ? 2'b10 : 2'b01; // even byte -> high byte
		else if (ld_cnt == 2'd1)
			sram_wr_n <= 2'b11;
	end
	else begin
		ld_cnt <= 2'd0;
		case (cyc)
			2'd0: begin
				sram_a <= { ram_a[22], ram_a[20:19], ram_a[18] & ~(kick_mirror & ram_a[22] & ram_a[20] & ram_a[19]), ram_a[17:1] };
				sram_rd_n <= _ram_oe ? 2'b11 : 2'b00;
				sram_drive <= 1'b0;
				sram_wr_n <= 2'b11;
			end
			2'd1: begin
				if (sram_rd_n == 2'b00)
					ram_din <= MD;
				sram_d <= ram_dout;
				if (!_ram_we) begin
					sram_rd_n <= 2'b11;
					sram_drive <= 1'b1;
					sram_wr_n <= { _ram_bhe, _ram_ble };
				end
			end
			2'd3: begin
				sram_wr_n <= 2'b11;
			end
		endcase
	end
end

assign MA = sram_a;
assign MD = sram_drive ? sram_d : 16'bzzzzzzzzzzzzzzzz;
assign MWR_N = sram_wr_n;
assign MRD_N = sram_rd_n;

//---------- Video ------------

// Amber doubles the Amiga lines: 908 x 625 (PAL) at 28 MHz, about 576p 50 Hz. The visible
// 720 x 576 window starts 162 clocks after the hsync and 46 lines after the vsync (falling
// edges), as NanoMig's video_analyzer places the HDMI frame.
localparam H_START = 162;
localparam V_START = 46;

reg hs_d = 1'b1, vs_d = 1'b1;
reg [10:0] hcnt = 11'd0;
reg [9:0] vcnt = 10'd0;
always @(posedge clk_sys) begin
	hs_d <= hs;
	if (hs_d && !hs) begin
		hcnt <= 11'd0;
		vs_d <= vs;
		if (vs_d && !vs)
			vcnt <= 10'd0;
		else if (vcnt != 10'h3FF)
			vcnt <= vcnt + 10'd1;
	end
	else if (hcnt != 11'h7FF)
		hcnt <= hcnt + 11'd1;
end

wire video_de = (hcnt >= H_START) && (hcnt < H_START + 720) && (vcnt >= V_START) && (vcnt < V_START + 576);

// input debug bar in the top left corner: 16 squares, green = 1
//   0-7  usb modifiers: lctrl lshift lalt lgui rctrl rshift ralt rgui
//   8    a key in the usb report       9  kbd_mouse_level (toggles per event)
//   10   mouse report (toggles)        11-13 mouse buttons l r m
//   14   kbd_reset                     15 cpu reset
wire [15:0] dbg_bits = { cpu_reset, kbd_reset, mouse_buttons[2], mouse_buttons[1], mouse_buttons[0], ms_upd,
	kbd_mouse_level, (kb_dat0 != 8'h00), kb_status[7], kb_status[6], kb_status[5], kb_status[4],
	kb_status[3], kb_status[2], kb_status[1], kb_status[0] };
wire [10:0] dbg_x = hcnt - (H_START + 8);
wire [9:0] dbg_y = vcnt - (V_START + 8);
wire dbg_area = sw_debug && (hcnt >= H_START + 8) && (dbg_x < 11'd256) && (vcnt >= V_START + 8) && (dbg_y < 10'd12)
	&& (dbg_x[3:0] < 4'd12);
wire dbg_on = dbg_bits[dbg_x[7:4]];

reg [23:0] hdmi_rgb;
reg hdmi_hs, hdmi_vs, hdmi_de;
always @(posedge clk_sys) begin
	hdmi_rgb <= !video_de ? 24'h000000 :
	            dbg_area ? (dbg_on ? 24'h00E000 : 24'h602020) :
	            { red, red, green, green, blue, blue };
	hdmi_hs <= hs;
	hdmi_vs <= vs;
	hdmi_de <= video_de;
end

//---------- Audio ------------

wire [15:0] audio_l = { audio_left, 1'b0 };
wire [15:0] audio_r = { audio_right, 1'b0 };

// level meters of the mcu
audio_peaks audio_peaks(
	.clk(clk_sys),
	.audio_l(audio_l),
	.audio_r(audio_r),
	.cmd_wr(matrix_cmd_wr),
	.cmd(matrix_cmd)
);

// osd overlay (menus of the mcu), on the 31 kHz picture before hdmi; 4 characters left of and one
// row above the tsconf position (120 / 72)
wire [23:0] osd_rgb;
overlay #(.H_OFFSET(120 - 4*8), .V_OFFSET(72 - 8)) overlay(
	.CLK(clk_sys),
	.RGB_I(hdmi_rgb),
	.RGB_O(osd_rgb),
	.HSYNC_I(hdmi_hs),
	.VSYNC_I(hdmi_vs),
	.OSD_COMMAND(osd_command)
);

zhdmi_top #(.SAMPLERATE(48000)) zhdmi_top(
	.clk(clk_sys),
	.ds80(1'b0),
	.reset(areset),
	.vga_rgb(osd_rgb),
	.vga_hs(hdmi_hs),
	.vga_vs(hdmi_vs),
	.vga_de(hdmi_de),
	.audio_en(~dvi_only),
	.audio_l(audio_l),
	.audio_r(audio_r),
	.tmds_p(TMDS_P),
	.tmds_n(TMDS_N)
);

// Mini has no I2S DAC: sigma-delta outputs into an RC filter (profi karabas_mini_top.vhd), offset
// binary input
dac dac_l(
	.I_CLK(clk_sys),
	.I_RESET(areset),
	.I_DATA({ ~audio_l[15], audio_l[14:0] }),
	.O_DAC(AUDIO_L)
);

dac dac_r(
	.I_CLK(clk_sys),
	.I_RESET(areset),
	.I_DATA({ ~audio_r[15], audio_r[14:0] }),
	.O_DAC(AUDIO_R)
);

endmodule
