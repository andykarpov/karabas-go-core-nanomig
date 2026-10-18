#!/bin/bash
# Usage: src/sim/run_img_sim.sh [ns between mcu frames, default 500]
# Simulate the file mounter (mcu.vhd + img_sdc.v) with a model of the mcu firmware, ISim.
set -e
FRAME_GAP=${1:-500}
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null
cd "$(dirname "$0")"
mkdir -p build/img
cd build/img
python3 ../../mcu_sim_wrap.py ../../../../modules/rtl/mcu/mcu.vhd mcu_sim.vhd
cat > tb.prj <<PRJ
vhdl work "../../fifo_sim.vhd"
vhdl work "../../dpram_sim.vhd"
vhdl work "../../../../modules/rtl/mcu/spi_slave.vhd"
vhdl work "../../../../modules/rtl/mcu/burst_rx.vhd"
vhdl work "mcu_sim.vhd"
verilog work "../../../../modules/rtl/mcu/img_sdc.v"
verilog work "../../tb_img.v"
PRJ
fuse -prj tb.prj -top work.tb_img -generic_top "FRAME_GAP=$FRAME_GAP" -o tb.exe > fuse.log || { grep -E "ERROR" fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "mounted|mcu:|sdc_done|ERROR|errors" sim.log
grep -q "tb_img: 0 errors" sim.log
