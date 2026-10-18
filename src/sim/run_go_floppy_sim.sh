#!/bin/bash
# Simulate the Go top with ISim: a physical floppy drive (fdd_model.v) on the floppy connector,
# set over the mcu link, used by a 68000 program through the CIAs (tb_go_floppy.v). A minute or two.
# Needs src/roms/kick13.rom (512 KB).
set -e
TIME="${1:-6 ms}"
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null

cd "$(dirname "$0")"
mkdir -p build/go_floppy
cd build/go_floppy

python3 - <<'EOF'
d = open("../../../roms/kick13.rom", "rb").read()
assert len(d) == 524288
open("kick_hi.hex", "w").write("\n".join("%02x" % b for b in d[0::2]) + "\n")
open("kick_lo.hex", "w").write("\n".join("%02x" % b for b in d[1::2]) + "\n")
EOF
# the drive model reads the flux of cylinder 0 (not used here)
python3 -c "open('t0.hex','w').write('aaaa\n'*6250); open('t1.hex','w').write('aaaa\n'*6250)"

python3 ../../mcu_sim_wrap.py ../../../../modules/rtl/mcu/mcu.vhd mcu_sim.vhd

# the synthesis source list as in run_rtc_sim.sh (models of fifo.v / dpram.v, mcu.vhd with 'out'
# ports)
{
	echo 'vhdl work "../../fifo_sim.vhd"'
	echo 'vhdl work "../../dpram_sim.vhd"'
	grep -v -e 'modules/rtl/mem/fifo.v' -e 'modules/rtl/mem/dpram.v' ../../../karabas_go.prj | sed -e 's|"../modules/rtl/mcu/mcu.vhd"|"mcu_sim.vhd"|' -e 's|"rtl/|"../../../rtl/|' -e 's|"../modules/|"../../../../modules/|'
	echo 'verilog work "../../fdd_model.v"'
	echo 'verilog work "../../tb_go_floppy.v"'
	echo "verilog work \"$XILINX/verilog/src/glbl.v\""
} > tb.prj

fuse -incremental -prj tb.prj -L unisims_ver -L unisim -top work.tb_go_floppy -top work.glbl -o tb.exe > fuse.log || { tail -30 fuse.log; exit 1; }
echo "run $TIME; quit" > run.tcl
./tb.exe -tclbatch run.tcl > sim.log
grep -E "ERROR|errors|COLOR00|init done" sim.log | head -60
grep -q "tb_go_floppy: 0 errors" sim.log
