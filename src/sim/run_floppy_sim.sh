#!/bin/bash
# Simulate paula_floppy.v reading track 0 of an ADF with ISim.
# Usage: src/sim/run_floppy_sim.sh <file.adf> [sector delay clocks, 28000 = 1 ms] [dma interval clocks, 600]
set -e
ADF="$(realpath "$1")"
SECTOR_DELAY=${2:-28000}
DMA_INTERVAL=${3:-600}
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
mkdir -p build/floppy
python3 - "$ADF" build/floppy/adf.hex <<'PY'
import sys
d = open(sys.argv[1], "rb").read()[:11264]
open(sys.argv[2], "w").write("\n".join("%02x" % b for b in d) + "\n")
PY
cd build/floppy
cat > tb.prj <<PRJ
verilog work "../../../rtl/minimig-aga/paula_floppy_fifo.v"
verilog work "../../../rtl/minimig-aga/paula_floppy.v"
verilog work "../../tb_floppy.v"
PRJ
fuse -prj tb.prj -top work.tb_floppy -generic_top "SECTOR_DELAY=$SECTOR_DELAY" -generic_top "DMA_INTERVAL=$DMA_INTERVAL" -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -v -e "^ISim" -e "^This is a" -e "^Time resolution" -e "^Simulator is doing" -e "^Finished circuit" -e "paula_floppy.v:" sim.log | head -60
grep -q "tb_floppy: 0 errors" sim.log
