# Karabas NanoMig (Amiga) core

Work in progress: a port of [NanoMig](https://github.com/harbaum/NanoMig) (Minimig, based on MiSTer
Minimig-AGA, OCS/ECS chipset) to the Karabas Go / Mini / Mini G boards (Xilinx Spartan-6 XC6SLX25,
ISE 14.7). The first target is Mini G.

`upstream/` keeps the NanoMig Tang Nano 20K top and README as a reference; they are not part of the
build. See `src/rtl/minimig-aga`, `src/rtl/tg68k` (CPU) and `src/rtl/nanomig.v` (the Minimig wrapper).
