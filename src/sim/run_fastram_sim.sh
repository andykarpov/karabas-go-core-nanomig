#!/bin/bash
# Simulate the fast RAM sdram controller (fastram_sdram.v) against an MT48LC16M16 model with ISim.
set -e
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
mkdir -p build/fastram
cd build/fastram
cat > tb.prj <<PRJ
verilog work "../../../rtl/memory/fastram_sdram.v"
verilog work "../../tb_fastram.v"
PRJ
fuse -prj tb.prj -top work.tb_fastram -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "ERROR|errors|reads|init done" sim.log | head -40
grep -q "tb_fastram: 0 errors" sim.log
