#!/bin/bash
# Simulate audio_filter.v (A500 low-pass and level of the Paula mix) with ISim.
set -e
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
mkdir -p build/audio
cd build/audio
cat > tb.prj <<PRJ
verilog work "../../../rtl/mcu/audio_filter.v"
verilog work "../../tb_audio_filter.v"
PRJ
fuse -prj tb.prj -top work.tb_audio_filter -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "ERROR|errors" sim.log
grep -q "tb_audio_filter: 0 errors" sim.log
