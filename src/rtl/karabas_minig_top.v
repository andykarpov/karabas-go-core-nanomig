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
-- Kickstart: loaded by the MCU from the core file (core_minig.json) to SRAM byte address
--   0x380000 (segment 7). The 68000 is big endian: even bytes go to the high byte (MD[15:8]).
------------------------------------------------------------------------------------------------------------------*/

module karabas_minig_top (
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
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire dvi_only;

// burst transfers from the mcu (karabas-go-firmware docs/burst_protocol.md)
wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

// Rev.G has MCU_SCK on a global clock pin: bursts at up to 32 MHz
mcu #(.BURST_MAX_MHZ(32)) mcu(
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

	.MATRIX_CMD(24'h000000),
	.MATRIX_CMD_WR(1'b0),

	.HWID(),
	.DVI_ONLY(dvi_only),

	.BUSY(mcu_busy)
);

//---------- Soft switches (the order of the osd items in core_minig.json) ------------

reg [1:0] sw_chipset = 2'd0;   // 0 = OCS-A500, 1 = OCS-A1000, 2 = ECS
reg [1:0] sw_chipmem = 2'd0;   // 0 = 512K, 1 = 1M, 2 = 1.5M, 3 = 2M
reg [1:0] sw_slowmem = 2'd1;   // 0 = none, 1 = 512K, 2 = 1M, 3 = 1.5M
reg       sw_ntsc = 1'b0;
reg       sw_reset = 1'b0;
reg [15:0] prev_softsw_command = 16'hFFFF;

always @(posedge clk_sys) begin
	if (prev_softsw_command != softsw_command) begin
		prev_softsw_command <= softsw_command;
		case (softsw_command[15:8])
			8'h00: sw_chipset <= softsw_command[1:0];
			8'h01: sw_chipmem <= softsw_command[1:0];
			8'h02: sw_slowmem <= softsw_command[1:0];
			8'h03: sw_ntsc <= softsw_command[0];
			8'h04: sw_reset <= softsw_command[0];
			default: ;
		endcase
	end
end

//---------- Reset ------------

// the Amiga is held in reset while the mcu loads the core roms
wire cpu_reset_req = areset | mcu_busy | romloader_act | sw_reset;
reg [15:0] reset_cnt = 16'hFFFF;
always @(posedge clk_sys) begin
	if (cpu_reset_req)
		reset_cnt <= 16'hFFFF;
	else if (reset_cnt != 0)
		reset_cnt <= reset_cnt - 16'd1;
end
wire cpu_reset = |reset_cnt;

//---------- NanoMig ------------

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
wire [3:0] floppy_config = 4'b0000; // 1 drive, no write protect, no turbo
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

	// no keyboard and mouse yet
	.mouse_buttons(3'b000),
	.kbd_mouse_level(1'b0),
	.kbd_mouse_type(2'b00),
	.kbd_mouse_data(8'h00),
	.joystick0(8'h00),
	.joystick1(8'h00),

	.uart_tx(UART_TX),
	.uart_rx(UART_RX),

	// no disk images yet
	.sdc_img_mounted(8'h00),
	.sdc_img_size(64'd0),
	.sdc_rd(),
	.sdc_wr(),
	.sdc_sector(),
	.sdc_busy(1'b0),
	.sdc_done(1'b0),
	.sdc_byte_in_strobe(1'b0),
	.sdc_byte_addr(9'd0),
	.sdc_byte_in_data(8'h00),
	.sdc_byte_out_data(),

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

//---------- SRAM ------------

// 28 MHz phase counter of the 7 MHz bus cycle, as NanoMig's sdram sync (cyc 0 follows clk7_en).
// Minimig drives the address and the read/write request at the start of the cycle and takes the
// read data at its end:
//   cyc 0 edge: address and read output enable
//   cyc 1 edge: write data and byte write strobes (low for two clocks)
//   cyc 2 edge: read data latched (address out for ~70 ns, 10 ns SRAM)
//   cyc 3 edge: write strobes released
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
				sram_a <= { ram_a[22], ram_a[20:1] };
				sram_rd_n <= _ram_oe ? 2'b11 : 2'b00;
				sram_drive <= 1'b0;
				sram_wr_n <= 2'b11;
			end
			2'd1: begin
				sram_d <= ram_dout;
				if (!_ram_we) begin
					sram_rd_n <= 2'b11;
					sram_drive <= 1'b1;
					sram_wr_n <= { _ram_bhe, _ram_ble };
				end
			end
			2'd2: begin
				if (sram_rd_n == 2'b00)
					ram_din <= MD;
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
	hdmi_rgb <= video_de ? { red, red, green, green, blue, blue } : 24'h000000;
	hdmi_hs <= hs;
	hdmi_vs <= vs;
	hdmi_de <= video_de;
end

//---------- Audio ------------

wire [15:0] audio_l = { audio_left, 1'b0 };
wire [15:0] audio_r = { audio_right, 1'b0 };

zhdmi_top #(.SAMPLERATE(48000)) zhdmi_top(
	.clk(clk_sys),
	.ds80(1'b0),
	.reset(areset),
	.vga_rgb(hdmi_rgb),
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
