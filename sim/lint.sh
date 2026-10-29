#!/bin/sh
# Lint every RTL file the core synthesises. The vendored cores (T65, jt51, TMS5220)
# are waived by path in sim/waivers.vlt; nothing under rtl/ is waived wholesale.
set -e
cd "$(dirname "$0")/.."
verilator --version >/dev/null 2>&1 || { echo "verilator not found"; exit 2; }
FLAGS="-Wall -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-PINMISSING -Wno-GENUNNAMED +1364-2005ext+v sim/waivers.vlt"
RTL="rtl/ssprint_pkg.sv $(ls rtl/*.sv rtl/t11/*.sv | grep -v ssprint_pkg)"
VENDOR="modules/cpu-t65/gen/t65.v modules/sound-tms5220/gen/tms5220.v $(ls modules/sound-jt51/hdl/*.v)"
for top in t11 slapstic pokey ssprint_video ssprint_sound ssprint_main; do
    echo "--- $top ---"
    verilator --lint-only $FLAGS --top-module $top $RTL $VENDOR
done
echo "--- whole machine ---"
verilator --lint-only $FLAGS --top-module ssprint_core $RTL $VENDOR
# the Analogizer wrapper, with the adapter's vendored module behind it and a
# stand-in for its one VHDL file.  The vendored files are kept as upstream
# wrote them, so their warnings are dropped by path -- their errors are not,
# but for one: hq2x.sv (MiSTer's) assigns its output wire in an always block,
# which Quartus takes and Verilator calls an error.  The wrapper is the
# template's, the same in every core; under this file's -Wall its unused bits
# (the held pixel's two syncs, which it re-makes, and the sticks' upper halves)
# and the stub's unused ports are by design, and the vendored files' `timescale
# against the wrapper's none is theirs -- those three warnings are off here.
# yc_out_legacy.sv goes through sim/yc_out_legacy_stub.v (its sine table, a
# wire array with an initial value, is past CI's Verilator 5.020), and
# BLKANDNBLK in the vendored SNAC module is waived (5.020 cannot lint it).
echo "--- analogizer ---"
A=target/pocket/analogizer
out=$(verilator --lint-only $FLAGS -Wno-PROCASSWIRE -Wno-BLKANDNBLK -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-TIMESCALEMOD \
      --top-module pocket_analogizer \
      target/pocket/pocket_analogizer.sv platform/pocket/helpers/synch_3.sv \
      $A/*.v $(ls $A/*.sv | grep -v /yc_out_legacy.sv) sim/yc_out_legacy_stub.v sim/ps2_keyboard_stub.v 2>&1 \
      | grep -E '^%(Error|Warning)' | grep -v 'Exiting due to' \
      | grep -v -E '^%Warning[^ ]*: [^ ]*(target/pocket/analogizer|platform/pocket)/' || true)
if [ -n "$out" ]; then echo "$out"; exit 1; fi
# the 25 -> 15 kHz converter in front of it, ours, under the full -Wall
echo "--- cabinet adapter link ---"
verilator --lint-only $FLAGS --top-module ss_cab_merge target/pocket/ss_cab_merge.sv
verilator --lint-only $FLAGS -Wno-UNUSEDSIGNAL --top-module pp_cab_io target/pocket/pp_cab_io.sv   # the Pole Position core's file, unchanged
echo "--- ana_15k ---"
verilator --lint-only $FLAGS --top-module ana_15k target/pocket/ana_15k.sv
echo "lint clean"
