#!/bin/bash
# Simulate the Mini G top with ISim (Xilinx ISE 14.7): Zorro II fast RAM on the sdram (tb_fastmem.v).
# Usage: src/sim/run_fastmem_sim.sh [run time, default 4 ms] (about a minute)
# Needs src/roms/kick13.rom (512 KB).
set -e
TIME="${1:-4 ms}"
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null

cd "$(dirname "$0")"
mkdir -p build/fastmem
cd build/fastmem

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
	echo 'verilog work "../../tb_fastmem.v"'
	echo "verilog work \"$XILINX/verilog/src/glbl.v\""
} > tb.prj

fuse -incremental -prj tb.prj -L unisims_ver -L unisim -top work.tb_fastmem -top work.glbl -o tb_fastmem.exe > fuse.log || { tail -30 fuse.log; exit 1; }
echo "run $TIME; quit" > run.tcl
./tb_fastmem.exe -tclbatch run.tcl > sim.log
grep -E "ERROR|errors|COLOR00|init done|sdram" sim.log | head -60
grep -q "tb_fastmem: 0 errors" sim.log
