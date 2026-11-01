`timescale 1ns / 1ps
`default_nettype wire

/*-------------------------------------------------------------------------------------------------------------------
--
-- https://github.com/andykarpov/karabas-go
--
-- NanoMig (Minimig, Amiga 500 OCS/ECS) core for Karabas-Go Mini rev.G
--
-- Memory: the two 2Mx8 SRAM chips are used as one 2Mx16 SRAM (4 MB), like the async SRAM
-- of the original Minimig board:
--   Minimig ram_address[22:1] uses the 512 KB segments 0-3 (chip RAM, $000000) and 12-15
--   (slow RAM at $C00000, Kickstart at $F80000). MA = {ram_address[22], ram_address[20:1]}
--   folds them into the 8 segments of the SRAM: chip RAM 0-3, slow RAM 4-6, Kickstart 7.
-- Kickstart: any *.rom of the SD card, chosen in the OSD (the FL item Kickstart, /amiga/kick.rom
--   by default). The MCU sends it with the ioctl file loader at core start and when another file is
--   chosen; it goes to SRAM byte address 0x380000 + offset (segment 7) and the Amiga is held in
--   reset meanwhile. A 256 KB Kickstart (1.2, 1.3) is mirrored in the upper half of the segment,
--   as on the A500. The 68000 is big endian: even bytes go to the high byte (MD[15:8]).
-- Clock: the MSM6242B at $DC0000 (minimig.v); its time registers 0-12 are the RTC registers of
--   the mcu link (rtc_mode 3 in core_minig.json).
------------------------------------------------------------------------------------------------------------------*/

module karabas_minig_top #(
	parameter RESET_DELAY = 16'hFFFF // clk_sys cycles of cpu reset after the mcu is ready
) (
	input wire CLK_50MHZ,

	input wire TAPE_IN,
	output wire TAPE_OUT,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,

	output wire ADC_CLK,
	output wire ADC_BCK,
	output wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire UART_RX,
	output wire UART_TX,
	output wire UART_CTS,

	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

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

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_CLK_OUT,
	input wire FT_DE,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	input wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

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
assign ESP32_SPI_CS_N = 1'b1;
assign SD_CS_N = 1'b1;
assign SD_DI = 1'b1;
assign SD_CLK = 1'b0;
assign FT_SPI_CS_N = 1'b1;
assign FT_SPI_SCK = 1'b0;
assign FT_SPI_MOSI = 1'b0;
assign FT_CLK_OUT = 1'b0;
assign MIDI_TX = 1'b1;
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
wire ioctl_act;
wire [3:0] rtc_a, rtc_wdata; // the MSM6242B registers of minimig (rtc_a 0-12 in the mcu dpram)
wire rtc_wr;
wire [7:0] rtc_rdata8;
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


// burst transfers from the mcu (karabas-go-firmware docs/burst_protocol.md)
wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

// Rev.G has MCU_SCK on a global clock pin: bursts at up to 32 MHz
// mcu chip selects: kg_mcu lets a low through at once and a high only after 3 clocks high
// (CS_FILTER). A short spike on a chip select (the sram outputs switch next to them all the
// time) reset the spi receivers in the middle of a frame: the frame got lost in both directions.
kg_mcu #(.BURST_MAX_MHZ(32), .CS_FILTER(3), .ENABLE_IMG(1)) mcu(
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(MCU_SCK),
	.MCU_SS(MCU_CS_N),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),
	.MCU_BURST_CS_N(MCU_IO[0]),
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

	.RTC_A({ 4'h0, rtc_a }),
	.RTC_DI({ 4'h0, rtc_wdata }),
	.RTC_DO(rtc_rdata8),
	.RTC_CS(rtc_wr),
	.RTC_WR_N(~rtc_wr),

	.UART_RX_DATA(),
	.UART_RX_IDX(),
	.UART_TX_DATA(8'h00),
	.UART_TX_WR(1'b0),
	.UART_TX_MODE(1'b0),
	.UART_DLM(8'h00),
	.UART_DLL(8'h00),
	.UART_DLM_WR(1'b0),
	.UART_DLL_WR(1'b0),
	.DEBUG_ADDR(16'h0000),
	.DEBUG_DATA(16'h0000),

	.ROMLOADER_ACTIVE(romloader_act),
	.ROMLOAD_ADDR(romloader_addr),
	.ROMLOAD_DATA(romloader_data),
	.ROMLOAD_WR(romloader_wr),
	.IOCTL_ACTIVE(ioctl_act),

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

//---------- Soft switches (the order of the osd items in core_minig.json) ------------
// items 0-3 are the file mounters DF0-DF3, items 5-6 the HDF files HDF0 / HDF1 and item 7 the
// Kickstart file (no switches); Reset is always the last item

reg [1:0] sw_hdd = 2'd0;       // IDE device 0 (Gayle): 0 = off, 1 = the CF card, 2 = the HDF0 image
reg [1:0] sw_chipset = 2'd0;   // 0 = OCS-A500, 1 = OCS-A1000, 2 = ECS
reg [1:0] sw_chipmem = 2'd0;   // 0 = 512K, 1 = 1M, 2 = 1.5M, 3 = 2M
reg [1:0] sw_slowmem = 2'd1;   // 0 = none, 1 = 512K, 2 = 1M, 3 = 1.5M
reg [1:0] sw_fastmem = 2'd0;   // Zorro II fast RAM (sdram): 0 = none, 1 = 2M, 2 = 4M, 3 = 8M
reg       sw_ntsc = 1'b0;
reg       sw_reset = 1'b0;
reg [15:0] prev_softsw_command = 16'hFFFF;

always @(posedge clk_sys) begin
	if (prev_softsw_command != softsw_command) begin
		prev_softsw_command <= softsw_command;
		case (softsw_command[15:8])
			8'h04: sw_hdd <= softsw_command[1:0];
			8'h08: sw_chipset <= softsw_command[1:0];
			8'h09: sw_chipmem <= softsw_command[1:0];
			8'h0A: sw_slowmem <= softsw_command[1:0];
			8'h0B: sw_fastmem <= softsw_command[1:0];
			8'h0C: sw_ntsc <= softsw_command[0];
			8'h0D: sw_reset <= softsw_command[0];
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

// the Amiga is held in reset while the mcu loads the core roms or the Kickstart file, by F12 and
// until the sdram (fast ram) is initialised
wire fastram_init_done;
wire cpu_reset_req = areset | mcu_busy | romloader_act | ioctl_act | sw_reset | kbd_reset | ~fastram_init_done;
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
wire sdc_error;
wire [2:0] sdc_slot;           // the sdc index img_sdc serves
wire [7:0] fdc_rd, fdc_wr;     // nanomig: the floppies, sdc index 0-3
wire [31:0] fdc_sector;
wire [7:0] fdc_out_data;
wire [1:0] hdf_rd, hdf_wr;     // hdf_ata: sdc index 4 (HDF0, IDE device 0), 5 (HDF1, device 1)
wire [31:0] hdf_sector;
wire [7:0] hdf_out_data;
wire [15:0] hdf_dout;
wire hdf_dev;                  // the IDE device the host talks to (DEV)
wire hdf_dev1_here;            // HDF1 has an image
wire [1:0] cf_cs_n;
wire fastram_sel, fastram_lds, fastram_uds, fastram_wr, fastram_ready;
wire [23:1] fastram_addr;
wire [15:0] fastram_dout, fastram_din;

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
wire [2:0] fastram_config = { 1'b0, sw_fastmem };
wire [3:0] floppy_config = { drives, 2'b00 }; // drives - 1, no write protect, no turbo
wire [3:0] video_config = 4'b0000; // Amber filters off, scanlines not built
wire [15:0] cf_dout;
wire cf_oe;
// Gayle on: device 0 is the CF card or HDF0, or HDF1 has an image. hdf_ata serves both devices on
// the IDE bus of gayle_cf (device 0 only when it is HDF0); the CF card gets the cycles when it is
// device 0, and its data are taken while device 0 is selected
wire [5:0] ide_config = { 5'b00000, sw_hdd != 2'd0 || hdf_dev1_here };
wire cf_sel = (sw_hdd == 2'd1);
wire cf_data = cf_sel && !hdf_dev;

// the floppy drives the Amiga finds: DF0 up to the highest DF with an image, taken while the Amiga
// is in reset (it looks for the drives once, at its start)
reg [3:1] df_img = 3'b000;
reg [1:0] drives = 2'd0;       // drives - 1
always @(posedge clk_sys) begin : drives_blk
	integer n;
	for (n = 1; n < 4; n = n + 1)
		if (sdc_img_mounted[n])
			df_img[n] <= (sdc_img_size != 64'd0);
	if (cpu_reset)
		drives <= df_img[3] ? 2'd3 : df_img[2] ? 2'd2 : df_img[1] ? 2'd1 : 2'd0;
end

// img_sdc serves one sdc index at a time; each requester takes busy, done and the bytes of its own
// index only (paula_floppy would take the ack of the HDF request as its own)
wire fdc_own = (sdc_slot[2] == 1'b0);
wire hdf_own = (sdc_slot[2:1] == 2'b10);
assign sdc_rd = { 2'b00, hdf_rd, fdc_rd[3:0] };
assign sdc_wr = { 2'b00, hdf_wr, fdc_wr[3:0] };
assign sdc_sector = (fdc_rd[3:0] != 4'd0 || fdc_wr[3:0] != 4'd0) ? fdc_sector : hdf_sector; // the lowest index first, as img_sdc
assign sdc_byte_out_data = hdf_own ? hdf_out_data : fdc_out_data;

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
	.floppy_ext(8'd0),             // no floppy connector
	.floppy_ext_chg(4'd0),
	.fdd_in(4'd0),
	.fdd_out(),
	.fdd_chng_req(),
	.fdd_chng_in(5'd0),
	.fdd_dbg(),
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

	// the floppies only: the IDE drives of nanomig.v (sdc index 4-5) are not used, hdf_ata is
	.sdc_img_mounted({ 4'b0000, sdc_img_mounted[3:0] }),
	.sdc_img_size(sdc_img_size),
	.sdc_rd(fdc_rd),
	.sdc_wr(fdc_wr),
	.sdc_sector(fdc_sector),
	.sdc_busy(sdc_busy & fdc_own),
	.sdc_done(sdc_done & fdc_own),
	.sdc_byte_in_strobe(sdc_byte_in_strobe & fdc_own),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(fdc_out_data),

	.ram_data(ram_dout),
	.ramdata_in(ram_din),
	.chip48(48'd0),
	.refresh(),
	.ram_address(ram_a),
	._ram_bhe(_ram_bhe),
	._ram_ble(_ram_ble),
	._ram_we(_ram_we),
	._ram_oe(_ram_oe),

	// Zorro II fast ram on the sdram
	.fastram_sel(fastram_sel),
	.fastram_addr(fastram_addr),
	.fastram_lds(fastram_lds),
	.fastram_uds(fastram_uds),
	.fastram_dout(fastram_dout),
	.fastram_din(fastram_din),
	.fastram_wr(fastram_wr),
	.fastram_ready(fastram_ready),

	// the CF card slot: the IDE drive of Gayle (minimig-aga/gayle_cf.v)
	.cf_a(WA),
	.cf_cs_n(cf_cs_n),
	.cf_rd_n(WRD_N),
	.cf_wr_n(WWR_N),
	.cf_reset_n(WRESET_N),
	.cf_dout(cf_dout),
	.cf_oe(cf_oe),
	.cf_din(cf_data ? WD : hdf_dout),

	.rtc_a(rtc_a),
	.rtc_wr(rtc_wr),
	.rtc_wdata(rtc_wdata),
	.rtc_rdata(rtc_rdata8[3:0])
);

assign WCS_N = cf_sel ? cf_cs_n : 2'b11;
assign WD = (cf_oe && cf_sel) ? cf_dout : 16'bzzzzzzzzzzzzzzzz;

//---------- HDF images: ATA devices 0 and 1 on the IDE bus of gayle_cf (sdc index 4, 5) ------------

hdf_ata hdf_ata(
	.clk(clk_sys),
	.reset(areset),
	.ata_reset(~WRESET_N),
	.dev0_en(sw_hdd == 2'd2),
	.dev(hdf_dev),
	.dev1_here(hdf_dev1_here),

	.a(WA),
	.cs_n(cf_cs_n),
	.rd_n(WRD_N),
	.wr_n(WWR_N),
	.din(cf_dout),
	.dout(hdf_dout),

	.img_mounted(sdc_img_mounted[5:4]),
	.img_size(sdc_img_size),
	.sdc_rd(hdf_rd),
	.sdc_wr(hdf_wr),
	.sdc_sector(hdf_sector),
	.sdc_busy(sdc_busy & hdf_own),
	.sdc_done(sdc_done & hdf_own),
	.sdc_error(sdc_error),
	.sdc_byte_in_strobe(sdc_byte_in_strobe & hdf_own),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(hdf_out_data),

	.led()
);

//---------- Fast RAM: the sdram at clk_sys, its clock inverted ------------

fastram_sdram fastram_sdram(
	.clk(clk_sys),
	.reset(areset),

	.sel(fastram_sel),
	.addr(fastram_addr),
	.lds(fastram_lds),
	.uds(fastram_uds),
	.wr(fastram_wr),
	.din(fastram_din),
	.dout(fastram_dout),
	.ready(fastram_ready),
	.init_done(fastram_init_done),

	.sd_ba(SDR_BA),
	.sd_a(SDR_A),
	.sd_dqm(SDR_DQM),
	.sd_ras_n(SDR_RAS_N),
	.sd_cas_n(SDR_CAS_N),
	.sd_we_n(SDR_WE_N),
	.sd_dq(SDR_DQ)
);

// a command put out at a rising edge of clk_sys is in the middle of its sdram clock
ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) u_sdr_clk (
	.Q(SDR_CLK),
	.C0(clk_sys),
	.C1(~clk_sys),
	.CE(1'b1),
	.D0(1'b0),
	.D1(1'b1),
	.R(1'b0),
	.S(1'b0)
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
	.sdc_error(sdc_error),
	.sdc_slot(sdc_slot),
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

// rom loader: one byte per ROMLOAD_WR, at least ~250 ns apart. The ioctl loader (the Kickstart
// file) uses the same signals with the file offset as the address: it goes to segment 7, and a
// byte past 512 KB is dropped (it would wrap onto the start of the rom).
reg [1:0] ld_cnt = 2'd0;
wire ld_act = romloader_act | ioctl_act;
wire [21:0] ld_addr = { romloader_addr[21:19] | {3{ioctl_act}}, romloader_addr[18:0] };
wire ld_wr = romloader_wr & ~(ioctl_act & |romloader_addr[31:19]);

// a Kickstart loaded into the lower 256 KB of segment 7 only (1.2, 1.3) is mirrored into the
// upper 256 KB: the A500 sees a 256 KB rom at both $F80000 and $FC0000. A 512 KB rom writes both
// halves.
reg kick_lo = 1'b0, kick_hi = 1'b0;
wire kick_mirror = kick_lo & ~kick_hi;
reg ld_act_d = 1'b0;
always @(posedge clk_sys) begin
	ld_act_d <= ld_act;
	if (ld_act && !ld_act_d) begin
		kick_lo <= 1'b0;
		kick_hi <= 1'b0;
	end
	else if (ld_act && ld_wr && ld_addr[21:19] == 3'b111) begin
		if (ld_addr[18])
			kick_hi <= 1'b1;
		else
			kick_lo <= 1'b1;
	end
end

always @(posedge clk_sys) begin
	if (ld_act) begin
		sram_rd_n <= 2'b11;
		if (ld_wr) begin
			sram_a <= ld_addr[21:1];
			sram_d <= { romloader_data, romloader_data };
			sram_drive <= 1'b1;
			ld_cnt <= 2'd3;
		end
		else if (ld_cnt != 2'd0)
			ld_cnt <= ld_cnt - 2'd1;

		if (ld_cnt == 2'd3)
			sram_wr_n <= ld_addr[0] ? 2'b10 : 2'b01; // even byte -> high byte
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

reg [23:0] hdmi_rgb;
reg hdmi_hs, hdmi_vs, hdmi_de;
always @(posedge clk_sys) begin
	hdmi_rgb <= !video_de ? 24'h000000 : { red, red, green, green, blue, blue };
	hdmi_hs <= hs;
	hdmi_vs <= vs;
	hdmi_de <= video_de;
end

//---------- Audio ------------

// the A500 low-pass (4.5 kHz) and 16-bit signed samples at the NanoMig level (full scale -6 dB)
wire [15:0] audio_l, audio_r;
audio_filter audio_filter(
	.clk(clk_sys),
	.in_l(audio_left),
	.in_r(audio_right),
	.out_l(audio_l),
	.out_r(audio_r)
);

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

PCM5102 #(.DAC_CLK_DIV_BITS(2)) pcm5102(
	.clk(clk_sys),
	.reset(areset),
	.left(audio_l),
	.right(audio_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);

endmodule
