#!/bin/bash
# Simulate gayle_cf.v (Gayle + CF card bridge) against an ATA device model with ISim.
set -e
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
mkdir -p build/gayle_cf
cd build/gayle_cf
cat > tb.prj <<PRJ
verilog work "../../../rtl/minimig-aga/gayle_cf.v"
verilog work "../../tb_gayle_cf.v"
PRJ
fuse -prj tb.prj -top work.tb_gayle_cf -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "ERROR|errors" sim.log | head -40
grep -q "tb_gayle_cf: 0 errors" sim.log
