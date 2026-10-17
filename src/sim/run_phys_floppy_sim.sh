#!/bin/bash
# Simulate paula_floppy.v with a physical drive (paula_floppy_ext.v, MiSTerFloppyPLL.v) against a
# model of a PC 3.5" DD drive with ISim (tb_phys_floppy.v). The disk is random data (4 tracks).
# Usage: src/sim/run_phys_floppy_sim.sh [drive slower by ppm, 15000] [flux jitter ns, 200]
set -e
SPEED_PPM=${1:-15000}
JITTER=${2:-200}
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
# BUILD / RTL: another build dir / rtl dir (mutation tests)
B=${BUILD:-build/phys_floppy}
R=$(realpath "${RTL:-../rtl}")
mkdir -p $B
python3 - $B <<'PY'
import random, sys
b = sys.argv[1]
random.seed(1)
adf = bytearray(random.getrandbits(8) for _ in range(4 * 11 * 512))
adfw = bytearray(adf)
adfw[11 * 512:22 * 512] = bytes(random.getrandbits(8) for _ in range(11 * 512))
open(b + "/disk.adf", "wb").write(adf)
open(b + "/diskw.adf", "wb").write(adfw)
open(b + "/adf.hex", "w").write("\n".join("%02x" % x for x in adf) + "\n")
open(b + "/adfw.hex", "w").write("\n".join("%02x" % x for x in adfw) + "\n")
PY
python3 mfm_track.py $B/disk.adf 0 $B/t0.hex 0 > /dev/null
python3 mfm_track.py $B/disk.adf 1 $B/t1.hex 3 > /dev/null
NW=$(python3 mfm_track.py $B/diskw.adf 1 $B/wtrack.hex 5)
# a turn of the drive is 6250 words: pad the tracks with the gap
for t in t0 t1; do
	python3 - $B/$t.hex <<'PY'
import sys
w = open(sys.argv[1]).read().split()
w += ["aaaa"] * (6250 - len(w))
open(sys.argv[1], "w").write("\n".join(w) + "\n")
PY
done
S=$(pwd)
cd $B
cat > tb.prj <<PRJ
verilog work "$R/minimig-aga/paula_floppy_fifo.v"
verilog work "$R/minimig-aga/MiSTerFloppyPLL.v"
verilog work "$R/minimig-aga/paula_floppy_ext.v"
verilog work "$R/minimig-aga/paula_floppy.v"
verilog work "$S/fdd_model.v"
verilog work "$S/tb_phys_floppy.v"
PRJ
fuse -prj tb.prj -top work.tb_phys_floppy -generic_top "SPEED_PPM=$SPEED_PPM" -generic_top "JITTER=$JITTER" -generic_top "NWWORDS=$NW" -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -v -e "^ISim" -e "^This is a" -e "^Time resolution" -e "^Simulator is doing" -e "^Finished circuit" -e "paula_floppy.v:" sim.log | head -60
grep -q "tb_phys_floppy: 0 errors" sim.log
