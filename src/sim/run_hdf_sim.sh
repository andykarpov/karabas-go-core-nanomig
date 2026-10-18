#!/bin/bash
# Simulate the HDF drive (gayle_cf.v + hdf_ata.v + img_sdc.v) against a model of the mcu firmware
# and a floppy reading at the same time, with ISim.
set -e
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
mkdir -p build/hdf
cd build/hdf
cat > tb.prj <<PRJ
verilog work "../../../rtl/minimig-aga/gayle_cf.v"
verilog work "../../../../modules/rtl/mcu/img_sdc.v"
verilog work "../../../rtl/mcu/hdf_ata.v"
verilog work "../../tb_hdf.v"
PRJ
fuse -prj tb.prj -top work.tb_hdf -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "ERROR|errors|floppy sectors" sim.log | head -40
grep -q "tb_hdf: 0 errors" sim.log
