#!/bin/bash
# Simulate paula_floppy_fifo.v (the disk fifo of paula_floppy) against a queue model with ISim.
set -e
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
mkdir -p build/floppy_fifo
cd build/floppy_fifo
cat > tb.prj <<PRJ
verilog work "../../../rtl/minimig-aga/paula_floppy_fifo.v"
verilog work "../../tb_floppy_fifo.v"
PRJ
fuse -prj tb.prj -top work.tb_floppy_fifo -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "out |ERROR|tb_floppy_fifo" sim.log
grep -q "tb_floppy_fifo: 0 errors" sim.log
