# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A work-in-progress port of [NanoMig](https://github.com/harbaum/NanoMig) (Minimig, based on MiSTer Minimig-AGA, OCS/ECS chipset only) to the Karabas Go / Mini / Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST). The first target is Mini G.

Only the Mini G build exists so far. Its board glue (MCU link, HDMI, I2S DAC) comes from the sibling `karabas-go-core-profi` repo. There is no simulation and no ISE GUI project (`.xise`) yet.

## Build

- `src/build_minig.sh` runs the ISE 14.7 command-line flow (it sources `/opt/Xilinx/14.7/ISE_DS/settings64.sh`). Run `./build_minig.sh xst`, `impl` or `core` for one step. With no argument it runs all of them. A full run takes about 30 min, mostly PAR.
- Inputs: `karabas_minig.prj` (source list, add new files here), `karabas_minig.xst`, `karabas_minig.ucf`, `karabas_minig.ut`.
- `core` packs `karabas_minig.bin` and the ROMs listed in `core_minig.json` into `nanomig.kg3` with `make_core.py`. The json order of the `osd` items is the index in the soft switch commands that `karabas_minig_top.v` decodes.
- The Kickstart is `src/roms/kick13.rom` (512 KB). It is not in git (copyright), so copy it there before `core`. `nanomig.kg3` contains it, so it is not committed either.
- Check timing in `karabas_minig.par` ("All constraints were met") and utilization in `karabas_minig_map.mrp`. The design fills about 92% of the slices, so timing is route-dominated.

## Layout

- `src/rtl/nanomig.v`: the Minimig wrapper (module `nanomig`). It holds the reset synchroniser, `amiga_clk`, `cpu_wrapper`, `minimig` and the Amber scan doubler (`dblscan` is tied to 1). Its ports are the interface a board top will connect to: `clk_sys` (28.6875 MHz, with `clk7_en`/`clk7n_en` enables), 4-bit RGB + sync, 15-bit audio, the config buses, keyboard/mouse/joysticks, a MiSTeryNano-style SD sector interface (`sdc_*`), the chip/slow RAM bus and the fast RAM bus.
- `src/rtl/minimig-aga/`: the Minimig chipset (Agnus, Denise, Paula, CIAs, Gary, Gayle/IDE) and `cpu_wrapper.v`.
- `src/rtl/tg68k/`: the TG68K CPU (VHDL), the CPU in use.
- `src/rtl/fx68k/`: fx68k, imported but not built (see below).
- `src/rtl/amber/`: the scan doubler.
- `src/rtl/misc/`: NanoMig's support modules (SD card, HID, OSD, SPI to the MCU, SDRAM, flash, ws2812, keymap). Most are written for the Tang Nano 20K and its companion MCU. They will need adapting or replacing for the Karabas Go MCU link before they go into a build. `ide_dpram.v` is the one written here (it replaces a Gowin primitive).
- `src/rtl/karabas_minig_top.v`: the Mini G top. It holds the PLL (50 MHz to `clk_sys` 28.333 MHz), the `mcu` link, soft switches, the reset (held while the MCU is busy or loads ROMs), the SRAM controller, the HDMI data-enable window and the audio outputs.
  - **SRAM:** the two 2Mx8 chips form one 2Mx16 async SRAM. `MA = {ram_address[22], ram_address[20:1]}` maps chip RAM to 512 KB segments 0-3, slow RAM to 4-6 and Kickstart to 7 (byte 0x380000, the ROM address in `core_minig.json`). The access follows NanoMig's sdram timing within the 7 MHz cycle (`cyc` 0-3 after `clk7_en`). Even bytes are the high byte (`MD[15:8]`, `MWR_N[1]`).
  - **Video:** the Amber output (908x625 at 28 MHz, about 576p50) goes straight to `zhdmi_top`. Only the 720x576 DE window (`H_START`/`V_START`) is generated here.
- Not wired yet: the keyboard/mouse/joysticks, the floppy/HDD images (the `sdc_*` interface) and the OSD overlay.
- `src/rtl/{mcu,spi,hdmi,zhdmi,dac,fifo,memory}`: copies of the Karabas Go board modules from `karabas-go-core-profi`.
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
