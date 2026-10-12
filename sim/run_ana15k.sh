#!/bin/sh
# The Analogizer's 25 -> 15 kHz converter on its own (sim/tb_ana15k.sv):
# every output dot against its source pair, Blend and Sharp, the 192p
# raster's line, vsync and frame timing, and the ring it reads from.  Then
# the same bench at a DELAY too early (the output overtakes the source) and
# one too late (the source overwrites a pair before it is read): both must
# fail, or the bench is not seeing the ring.  A few minutes.
set -e
here=$(cd "$(dirname "$0")" && pwd)
cd "$here"
verilator --version >/dev/null 2>&1 || { echo "verilator not found" >&2; exit 2; }
build() {   # build <dir> <DELAY>
    verilator --binary --timing -j "${JOBS:-8}" -O2 -Wno-fatal -Wno-lint -Wno-style \
        --top-module tb_ana15k -GDELAY="$2" -Mdir "$1" \
        ../target/pocket/ana_15k.sv tb_ana15k.sv > "$1.log" 2>&1 \
        || { tail -40 "$1.log"; exit 1; }
}
build obj_ana15k 336000
./obj_ana15k/Vtb_ana15k | tee obj_ana15k.run.log
grep -q "^PASS" obj_ana15k.run.log
for d in 300000 372000; do
    build obj_ana15k_m "$d"
    ./obj_ana15k_m/Vtb_ana15k > obj_ana15k_m.run.log 2>&1 || true
    if grep -q "^PASS" obj_ana15k_m.run.log; then
        echo "MUTATION NOT CAUGHT: DELAY $d passed"; exit 1
    fi
    echo "mutation DELAY $d: $(grep -E '^ring:' obj_ana15k_m.run.log)"
    grep '^FAIL' obj_ana15k_m.run.log | head -3 | sed 's/^/    /'
done
echo "both mutations caught"
