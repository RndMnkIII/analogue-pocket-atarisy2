#!/bin/sh
# The cabinet adapter link: pp_cab_io at 96 MHz against a model of the adapter's
# frame, and ss_cab_merge's wheel, pedal and switch mapping (sim/tb_cab.sv).
set -e
cd "$(dirname "$0")/.."
iverilog -g2012 -o /tmp/tb_cab.vvp sim/tb_cab.sv target/pocket/pp_cab_io.sv target/pocket/ss_cab_merge.sv
vvp /tmp/tb_cab.vvp | tee /tmp/tb_cab.log
grep -q "tb_cab: PASS" /tmp/tb_cab.log
