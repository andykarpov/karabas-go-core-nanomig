#!/bin/bash
# Simulate a disk DMA read through the Mini G top with ISim (tb_disk.v).
# Usage: src/sim/run_disk_sim.sh <file.adf>
# Needs src/roms/kick13.rom (512 KB).
set -e
ADF="$(realpath "$1")"
TIME="40 ms"
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null

cd "$(dirname "$0")"
mkdir -p build/disk
cd build/disk
python3 - "$ADF" adf.hex <<'PY'
import sys
d = open(sys.argv[1], "rb").read()[:11264]
open(sys.argv[2], "w").write("\n".join("%02x" % b for b in d) + "\n")
PY

python3 - <<'EOF'
d = open("../../../roms/kick13.rom", "rb").read()
assert len(d) == 524288
open("kick_hi.hex", "w").write("\n".join("%02x" % b for b in d[0::2]) + "\n")
open("kick_lo.hex", "w").write("\n".join("%02x" % b for b in d[1::2]) + "\n")
EOF

python3 ../../../../modules/sim/mcu/mcu_sim_wrap.py ../../../../modules/rtl/mcu/mcu.vhd mcu_sim.vhd

# the synthesis source list, with behavioural VHDL models of fifo.v / dpram.v
# (ISim cannot elaborate them from VHDL with open ports), mcu.vhd with 'out' in place of the
# 'buffer' ports (ISim leaves those undriven towards verilog), and no hdmi
{
	echo 'vhdl work "../../../../modules/sim/mcu/fifo_sim.vhd"'
	echo 'vhdl work "../../../../modules/sim/mcu/dpram_sim.vhd"'
	echo 'verilog work "../../zhdmi_top_stub.v"'
	grep -v -e 'modules/rtl/mem/fifo.v' -e 'modules/rtl/mem/dpram.v' -e 'modules/rtl/video/hdmi/' ../../../karabas_minig.prj | sed -e 's|"../modules/rtl/mcu/mcu.vhd"|"mcu_sim.vhd"|' -e 's|"rtl/|"../../../rtl/|' -e 's|"../modules/|"../../../../modules/|'
	echo 'verilog work "../../tb_disk.v"'
	echo "verilog work \"$XILINX/verilog/src/glbl.v\""
} > tb.prj

fuse -incremental -prj tb.prj -L unisims_ver -L unisim -top work.tb_disk -top work.glbl -o tb.exe > fuse.log || { tail -30 fuse.log; exit 1; }
echo "run $TIME; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -v -i -e "warning" -e "^ISim" -e "^This is a" -e "^Time resolution" -e "^Simulator is doing" -e "^Finished circuit" sim.log | head -300
grep -q "tb_disk: 0 errors" sim.log
