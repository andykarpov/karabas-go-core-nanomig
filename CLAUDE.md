# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A work-in-progress port of [NanoMig](https://github.com/harbaum/NanoMig) (Minimig, based on MiSTer Minimig-AGA, OCS/ECS chipset only) to the Karabas Go / Mini / Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST). The first target is Mini G.

Mini G is the target that is built and tested on hardware. Go and Mini have their own tops, ucf/prj/xst/ut files, `build_go.sh` / `build_mini.sh` and `core.json` / `core_mini.json` (packed into `nanomig.kg1` / `kg2`). They build and meet timing (build 26101700: Go 92% slices, 2.3 ns slack, VGA instead of hdmi; Mini 99%, 1.9 ns), but are not tested on hardware. The board glue (MCU link, HDMI / VGA, DACs) comes from the sibling `karabas-go-core-profi` repo. A change to the core logic of `karabas_minig_top.v` goes into all three tops. The builds share their work directories in `src/`, so run one at a time. There is no ISE GUI project (`.xise`).

## Build

- `src/build_minig.sh` runs the ISE 14.7 command-line flow (it sources `/opt/Xilinx/14.7/ISE_DS/settings64.sh`). Run `./build_minig.sh xst`, `impl` or `core` for one step. With no argument it runs all of them. A full run takes about 30 min, mostly PAR.
- Inputs: `karabas_minig.prj` (source list, add new files here), `karabas_minig.xst`, `karabas_minig.ucf`, `karabas_minig.ut`.
- `core` packs `karabas_minig.bin` and the ROMs listed in `core_minig.json` into `nanomig.kg3` with `make_core.py`. The json order of the `osd` items is the index in the soft switch commands that `karabas_minig_top.v` decodes. Reset stays the last item, so a new item goes before it and moves its index.
- The Kickstart is the `FL` OSD item Kickstart (ioctl file loader, slot 7, `.rom`, default `/amiga/kick.rom`, `autoload`): any Kickstart of 256 or 512 KB on the SD card (1.3 for floppies, 2.05 / 3.1 of the A600 for the HDD). The firmware (branch `kick-menu-4df-rtc` and later) sends it at core start and when another file is chosen. `mcu.vhd` puts the ioctl frames on the `ROMLOAD_*` signals with the file offset as the address (`IOCTL_ACTIVE`, one write per data byte); the top maps them to segment 7, drops bytes past 512 KB and holds the Amiga in reset meanwhile. `roms` is empty: the firmware sends the `FL` files before the roms, so a rom there would overwrite the choice. So `nanomig.kg3` has no copyrighted data and is committed as a release. `make_core.py` could not build external roms (it read the file and wrote a str), and padded `dir` / `filename` of `F` / `FL` items with spaces (now NULs); fixed here, the copy in karabas-go-tools still has both bugs.
- A 256 KB Kickstart (1.2, 1.3) loaded only into the lower half of SRAM segment 7 is mirrored into the upper half (`kick_mirror` in the top), as on the A500. A 512 KB file writes both halves.
- Check timing in `karabas_minig.par` ("All constraints were met") and utilization in `karabas_minig_map.mrp`. The design fills about 99% of the slices (82% of the LUTs), so timing is route-dominated: clk_sys has about 0.4 ns of slack (build 26101700, with the ioctl Kickstart, 4 drives and the MSM6242B; 0.7 ns in 26101603).

## Simulation

- `src/sim/run_sim.sh [time]` (default 3 ms) runs `tb_minig.v` in ISim. It needs `src/roms/kick13.rom` (512 KB, not in git). The testbench preloads it into a model of the two SRAM chips, tests the rom loader over the mcu spi link, sends `CMD_INIT_DONE` and prints the cpu bus cycles, writes to the custom chips, sram writes and the video chain. About 1 ms of simulated time takes a few minutes. Check `src/sim/build/fuse.log` for `ERROR` first.
- The source list is `karabas_minig.prj` with these substitutions:
  - `fifo.v`/`dpram.v` are replaced by VHDL models;
  - `mcu.vhd` is wrapped by `mcu_sim_wrap.py`, because ISim leaves VHDL `buffer` ports undriven towards Verilog;
  - hdmi is a stub, because the TMDS encoders stop ISim on X data.
- ISim also differs from the FPGA in these ways:
  - XST starts every flip-flop at 0, ISim at X, so registers without a reset have to be set in the testbench. The Agnus beam counter is the known case.
  - Verilog constants on VHDL ports are illegal, so connect them through a wire.
  - Undriven nets and open inputs are X. Tie them off in the RTL.
- The testbench shortens two delays that are real on hardware: the `minimig_syscontrol` reset (4 frames) and the Kickstart 1.3 start delay loop (patched in the SRAM model only).

## Layout

- `src/rtl/nanomig.v`: the Minimig wrapper (module `nanomig`). It holds the reset synchroniser, `amiga_clk`, `cpu_wrapper`, `minimig` and the Amber scan doubler (`dblscan` is tied to 1). Its ports are the interface a board top will connect to: `clk_sys` (28.6875 MHz, with `clk7_en`/`clk7n_en` enables), 4-bit RGB + sync, 15-bit audio, the config buses, keyboard/mouse/joysticks, a MiSTeryNano-style SD sector interface (`sdc_*`), the chip/slow RAM bus and the fast RAM bus.
- `src/rtl/minimig-aga/`: the Minimig chipset (Agnus, Denise, Paula, CIAs, Gary, Gayle/IDE) and `cpu_wrapper.v`.
- `src/rtl/tg68k/`: the TG68K CPU (VHDL), the CPU in use.
- `src/rtl/fx68k/`: fx68k, imported but not built (see below).
- `src/rtl/amber/`: the scan doubler.
- `src/rtl/misc/`: NanoMig's support modules (SD card, HID, OSD, SPI to the MCU, SDRAM, flash, ws2812, keymap). Most are written for the Tang Nano 20K and its companion MCU. They will need adapting or replacing for the Karabas Go MCU link before they go into a build. `ide_dpram.v` is the one written here (it replaces a Gowin primitive).
- `src/rtl/karabas_minig_top.v`: the Mini G top. It holds the PLL (50 MHz to `clk_sys` 28.333 MHz), the `mcu` link, soft switches, the reset (held while the MCU is busy or loads ROMs), the SRAM controller, the HDMI data-enable window and the audio outputs.
  - **SRAM:** the two 2Mx8 chips form one 2Mx16 async SRAM. `MA = {ram_address[22], ram_address[20:1]}` maps chip RAM to 512 KB segments 0-3, slow RAM to 4-6 and Kickstart to 7 (byte 0x380000, the ROM address in `core_minig.json`). The access follows NanoMig's sdram timing within the 7 MHz cycle (`cyc` 0-3 after `clk7_en`). Minimig takes the read data at the cyc 2 edge, so it is latched at the cyc 1 edge. A clock later and the cpu gets the previous word (black screen). Even bytes are the high byte (`MD[15:8]`, `MWR_N[1]`).
  - **Video:** the Amber output (908x625 at 28 MHz, about 576p50) goes straight to `zhdmi_top`. Only the 720x576 DE window (`H_START`/`V_START`) is generated here.
  - **Keyboard and mouse:** `rtl/mcu/hid_amiga.v` turns the USB reports of the `mcu` link (`KB_STATUS`, `KB_DAT0..5`, `MS_*`) into Minimig `kbd_mouse_*` events.
    - Keyboard: the report is compared with the previous one once it is stable for 200 us. The mcu sends a report as 7 frames. Codes go through NanoMig's `misc/amiga_keymap.v`.
    - Key events are spaced about 1 ms apart, because CIA-A has no keyboard buffer. The PS/2 and XT scancodes of the mcu are not used: they carry typematic repeats, and AmigaOS repeats keys itself.
    - Caps lock toggles like the Amiga key. F12 (no Amiga key) resets the Amiga while it is held.
    - `src/sim/run_hid_sim.sh` is its unit test (seconds).
  - **OSD:** `rtl/osd/overlay.vhd` (from karabas-go-core-tsconf) draws the mcu menus (`OSD_COMMAND`) over the 31 kHz picture, just before hdmi. It scales its counters by the measured line length. Its position is the `H_OFFSET` / `V_OFFSET` generics (tsconf: 120 / 72; here 4 characters left and one row up).
  - **Joysticks:** `JOY_L` of the mcu link is nanomig `joystick0`, Amiga port 2 (the joystick port); `JOY_R` is `joystick1`, port 1, shared with the usb mouse (userio switches to the joystick on its fire button, back to the mouse on the left mouse button). Fire = A, fire2 = B, fire3 = C, fire4 = start.
  - **Audio:** `rtl/mcu/audio_filter.v` takes the 15-bit Paula mix (signed) to the 16-bit signed samples of hdmi, the PCM5102 and the peaks: sign extended (NanoMig level; the earlier `{audio, 1'b0}` hit 0 dBFS at full volume) and a one-pole 4.5 kHz low-pass like the RC filter of the A500 (without it the Paula steps alias in the 48 kHz / 27.7 kHz samples). `src/sim/run_audio_sim.sh` is its unit test.
  - **Audio peaks:** `rtl/mcu/audio_peaks.v` sends the peak of each channel every 2^19 clocks (18.5 ms) as `CMD_AUDIO_PEAKS_L/_R` through `MATRIX_CMD` of `mcu.vhd`, for the level meters of the firmware.
  - **Disk images:** `rtl/mcu/img_sdc.v` connects the file mounter of the mcu link (the `IMG_*` ports added to `mcu.vhd`, protocol in karabas-go-firmware `docs/protocol.md`, firmware branch `filemounter`) to the `sdc_*` sector interface of NanoMig.
    - Slot n is sdc index n: 0-3 floppies, 4-5 IDE. `core_minig.json` has DF0-DF3 (`F` items, slots 0-3, `.adf`) and Kickstart (`FL`) as the first five OSD items, so the soft switch indices start at 5 (Drives: `floppy_config[3:2]` = drives - 1).
    - One request at a time. Write data is read `OUT_LATENCY` clocks after `sdc_byte_addr`. A request ends after a timeout if the firmware has no file mounter.
    - Lost link frames, the causes found so far: short low spikes on the mcu chip selects (the sram outputs switch next to them) reset the spi receivers in the middle of a frame, so the top lets a chip select go high only after 3 clocks; `spi_slave.vhd` took a reply word from the queue in idle when sck ran without its chip select (bursts, those spikes), so it asks for a word only inside a frame now (`run_img_sim.sh` has spikes during bursts), and `mcu.vhd` deselects it during a burst; the firmware had to keep the reply order across its tasks; `mcu.vhd` took a reply word on each rising edge of `di_req`, a combinational decode of the sck-domain state of `spi_slave` sampled without a synchroniser, so a glitch took two words in one frame. It takes one word per frame on `do_valid` now.
    - Requests are still checked end to end: the firmware needs all 4 LBA bytes; reads carry the 16-bit sum of the sector and need 512 bytes; writes carry their sum. A failed request is sent again (`RETRIES`, `TIMEOUT` 200 ms); a read that still fails gives the floppy 512 zero bytes so it does not hang. The firmware sends the sector of a read as a burst.
    - A read sector goes into the `img_sdc` buffer and on to the floppy only once it is checked: `paula_floppy` takes its first byte 511 as the end of the sector and builds the MFM checksum from what it got, so the bytes of a failed try would reach the Amiga as a good sector. `run_img_sim.sh` models this.
    - `paula_floppy.v` (karabas change): a write dma goes on after `lenzero` until the fifo is empty. With the slow mcu writes the fifo holds the end of the track, which NanoMig dropped (lost sectors and a DSKBLK that never came).
    - Tests: `run_img_sim.sh` (`mcu.vhd` + `img_sdc.v` against a model of the firmware, incl. lost frames), `run_floppy_sim.sh <adf>` (track read at the real dma rate), `run_floppy_wr_sim.sh <adf>` (track write; `mfm_track.py` encodes the ADF track as trackdisk does, the sd model is slow now and then).
  - **HDD (CF card):** the OSD item HDD = CF card turns Gayle on (`ide_config[0]`). `minimig-aga/gayle_cf.v` replaces `gayle.v` + `ide.v`: the Gayle registers stay, and every cpu access to the task file ($DA2000 + 4n CS0, $DA3000 + 4n CS1) is one PIO mode 0 cycle on the CF slot (`WA`, `WCS_N`, `WRD_N`, `WWR_N`, `WRESET_N`, `WD`), the cpu waits on `nrdy` (for writes too, so `minimig.v` no longer masks it with `rd_cyc`). The bus is byte swapped as on the A600 (IDE DD7..0 = cpu D15..8). The slot has no INTRQ, so the interrupt is emulated by polling the alternate status after a command / a data block (rules in the header of `gayle_cf.v`). The bridge counts the sectors of a command (0 = 256, short last block of READ / WRITE MULTIPLE) and the words of a block from the data accesses themselves, not from its poll: the cpu can see DRQ and move data before a poll gets a card cycle. A poll after a block starts 2 us after its last word and waits for the state expected (DRQ while sectors are left, else no DRQ). Needs a Kickstart with scsi.device for Gayle (A600 2.05 / 3.1), 1.3 has none. Tests: `run_gayle_cf_sim.sh` (unit test against an ATA model, a minute), `run_hdd_sim.sh` (the whole top, a 68000 program does IDENTIFY and WRITE SECTORS, a minute).
  - **Clock (MSM6242B):** `minimig.v` (karabas block) answers $DC0000, register n at $DC0003 + 4n: registers 0-12 (time digits) come from the RTC dpram of `mcu.vhd` (`RTC_A` = n), D = 0, E = 0, F = 4 (24 h). A cpu write of 0-12 is one `rtc_wr` clock: the dpram and a `CMD_RTC` frame to the firmware (`rtc_mode` 3), which sets the clock chip once the writes stop. battclock (Kickstart 3.1, disassembled) reads F: F & 15 = 4 is a running MSM6242B; it reads the time with HOLD (D = 1) and waits for BUSY (D bit 1) = 0. Kickstart 1.3 has no battclock (SetClock of Workbench). Test: `run_rtc_sim.sh` (the whole top: ioctl loader, a 68000 program reads and writes the clock, seconds).
- Not wired yet: IDE images (the same path, `sdc` index 4-5, writes need a check of the IDE data latch).
- `src/rtl/{mcu,spi,hdmi,zhdmi,dac,fifo,memory}`: copies of the Karabas Go board modules from `karabas-go-core-profi`. `src/rtl/osd` comes from `karabas-go-core-tsconf`.
- `upstream/`: the NanoMig Tang Nano 20K top (`tang_nano20k_top.sv`) and README. They are a reference for how `nanomig` is wired up, not part of the build.

## Constraints that drive the changes

- **XST parses Verilog-2001 only.** Code that goes into the build must avoid SystemVerilog:
  - No declarations in unnamed blocks. Name the block `<file>_blk<line>` (for example `begin : nanomig_blk101`), the convention used for all the existing fixes.
  - No `'1` literals, no `[N]` array sizes, no `` `default_nettype none `` headers.
  - `.sv` files (`misc/sdram.sv`, the fx68k `.sv`) cannot be used as is.
- **The XC6SLX25 is small.** Upstream code that ISE maps to flip-flops and LUTs instead of block RAM can be larger than the whole FPGA. The Paula floppy code was 9.7k LUTs until its sector buffer and MFM fifo were rewritten as inferred block RAMs. When resources blow up, look for memories read or written from several places, or read asynchronously, and restructure them into one write port and one synchronous read port.
- **The CPU is TG68K as a plain 68000.** `cpu_wrapper.v` defines `ENABLE_TG68K` only, and the `TG68KdotC_Kernel` generics turn off the 68020 features (32-bit MUL/DIV, bitfields, extended addressing, VBR). fx68k is SystemVerilog and is not enabled. An Amiga 500 needs only a 68000.
- **The TG68K ALU does not fit one 28 MHz clock.** `cpu_wrapper.v` never activates the cpu clock enable on two clocks in a row, and `TS_CPU_MC` in the ucf gives the TG68K-internal paths 70 ns. This holds only while every TG68K register updates under `clkena_in`.

## Conventions

- Local changes to the imported sources are marked with a `// karabas:` comment that says why. Keep upstream code otherwise untouched, so it can still be compared with NanoMig/MiSTer.
- Commit messages explain why a change was needed and what it costs or changes in behaviour (for example a changed latency, or LUT counts before and after), and say "No functional change." when that is the case.
