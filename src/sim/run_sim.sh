#!/bin/bash
# Simulate the Mini G top with ISim (Xilinx ISE 14.7): Kickstart boot from the SRAM model.
# Usage: src/sim/run_sim.sh [run time, default 3 ms]
# Needs src/roms/kick13.rom (512 KB).
set -e
TIME=${1:-3 ms}
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null

cd "$(dirname "$0")"
mkdir -p build
cd build

python3 - <<'EOF'
d = open("../../roms/kick13.rom", "rb").read()
assert len(d) == 524288
open("kick_hi.hex", "w").write("\n".join("%02x" % b for b in d[0::2]) + "\n")
open("kick_lo.hex", "w").write("\n".join("%02x" % b for b in d[1::2]) + "\n")
EOF


# the synthesis source list, with a behavioural VHDL model of dpram.v (the OSD; ISim cannot
# elaborate it from VHDL with open ports), and no hdmi
{
	echo 'vhdl work "../../../modules/sim/mcu/dpram_sim.vhd"'
	echo 'verilog work "../zhdmi_top_stub.v"'
	grep -v -e 'modules/rtl/mem/dpram.v' -e 'modules/rtl/video/hdmi/' ../../karabas_minig.prj | sed -e 's|"rtl/|"../../rtl/|' -e 's|"../modules/|"../../../modules/|'
	echo 'verilog work "../tb_minig.v"'
	echo "verilog work \"$XILINX/verilog/src/glbl.v\""
} > tb.prj

fuse -incremental -prj tb.prj -L unisims_ver -L unisim -top work.tb_minig -top work.glbl -o tb_minig.exe > fuse.log || { tail -30 fuse.log; exit 1; }
echo "run $TIME; quit" > run.tcl
./tb_minig.exe -tclbatch run.tcl > sim.log
grep -v -i -e "warning" -e "^ISim" -e "^This is a" -e "^Time resolution" -e "^Simulator is doing" -e "^Finished circuit" sim.log | head -300
