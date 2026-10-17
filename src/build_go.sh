#!/bin/bash
# Command line build of the Karabas Go core (the same steps as the ISE 14.7 project navigator).
# Usage: ./build_go.sh [xst|impl|core]   (default: all steps)
set -e
cd "$(dirname "$0")"
STEP=${1:-all}
set --
source /opt/Xilinx/14.7/ISE_DS/settings64.sh > /dev/null

TOP=karabas_go
PART=xc6slx25-ftg256-2

if [ "$STEP" = all ] || [ "$STEP" = xst ]; then
	mkdir -p xst/projnav.tmp
	xst -intstyle ise -ifn $TOP.xst -ofn $TOP.syr
fi

if [ "$STEP" = all ] || [ "$STEP" = impl ]; then
	ngdbuild -intstyle ise -dd _ngo -nt timestamp -uc $TOP.ucf -p $PART $TOP.ngc $TOP.ngd
	# cost table 2: the placement of table 1 left par in router phase 4 for hours (build 26101701)
	map -intstyle ise -p $PART -w -logic_opt off -ol high -xe n -t 2 -xt 0 -register_duplication off -r 4 -global_opt off -mt 2 -detail -ir off -pr b -lc off -power off -o ${TOP}_map.ncd $TOP.ngd $TOP.pcf
	par -w -intstyle ise -ol high -xe n -mt 4 ${TOP}_map.ncd $TOP.ncd $TOP.pcf
	trce -intstyle ise -v 3 -s 2 -n 3 -fastpaths -xml $TOP.twx $TOP.ncd -o $TOP.twr $TOP.pcf -ucf $TOP.ucf
	bitgen -intstyle ise -f $TOP.ut $TOP.ncd
fi

if [ "$STEP" = all ] || [ "$STEP" = core ]; then
	python3 make_core.py core.json nanomig.kg1
fi
