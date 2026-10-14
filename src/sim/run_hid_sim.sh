#!/bin/bash
# Simulate hid_amiga.v (usb reports to Minimig keyboard / mouse events) with ISim.
set -e
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
mkdir -p build/hid
cd build/hid
cat > tb.prj <<PRJ
verilog work "../../../rtl/misc/amiga_keymap.v"
verilog work "../../../rtl/mcu/hid_amiga.v"
verilog work "../../tb_hid_amiga.v"
PRJ
fuse -prj tb.prj -top work.tb_hid_amiga -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "event|ERROR|errors" sim.log
grep -q "tb_hid_amiga: 0 errors" sim.log
