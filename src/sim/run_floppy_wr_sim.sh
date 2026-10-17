#!/bin/bash
# Simulate paula_floppy.v writing a track of an ADF (MFM from mfm_track.py) with ISim.
# Usage: src/sim/run_floppy_wr_sim.sh <file.adf> [write time clocks] [slow write clocks] [dma interval clocks]
set -e
ADF="$(realpath "$1")"
WRITE_TIME=${2:-140000}
SLOW_TIME=${3:-2000000}
DMA_INTERVAL=${4:-100}
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
mkdir -p build/floppy_wr
NW=$(python3 mfm_track.py "$ADF" 1 build/floppy_wr/track.hex 5)
python3 - "$ADF" build/floppy_wr/adf.hex <<'PY'
import sys
d = open(sys.argv[1], "rb").read()[:22528]
open(sys.argv[2], "w").write("\n".join("%02x" % b for b in d) + "\n")
PY
cd build/floppy_wr
cat > tb.prj <<PRJ
verilog work "../../../rtl/minimig-aga/paula_floppy_fifo.v"
verilog work "../../../rtl/minimig-aga/MiSTerFloppyPLL.v"
verilog work "../../../rtl/minimig-aga/paula_floppy_ext.v"
verilog work "../../../rtl/minimig-aga/paula_floppy.v"
verilog work "../../tb_floppy_wr.v"
PRJ
fuse -prj tb.prj -top work.tb_floppy_wr -generic_top "NWORDS=$NW" -generic_top "WRITE_TIME=$WRITE_TIME" -generic_top "SLOW_TIME=$SLOW_TIME" -generic_top "DMA_INTERVAL=$DMA_INTERVAL" -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "written|blckint|ERROR|errors|checksum|mismatch|marker" sim.log | head -60
grep -q "tb_floppy_wr: 0 errors" sim.log
