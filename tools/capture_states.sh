#!/bin/sh
# Regenerate the frozen MAME states and snapshots used by the reference
# renderer and the RTL video bench. Needs the romset in ./<game> (or set
# ROMPATH). Output: artifacts/states/<name>.txt and artifacts/snap/<name>.png
#   tools/capture_states.sh [prefix]     PREFIX names the set (default: attract)
#   env: GAME=ssprint|apb FRAMES=600,1000 COIN=n START=n WHEEL=n PEDAL=n START_FIELD=name
set -e
cd "$(dirname "$0")/.."
ROMPATH=${ROMPATH:-.}
GAME=${GAME:-ssprint}
PREFIX=${1:-attract}
FRAMES=${FRAMES:-400,700,1000,1500,2500}
W=$(mktemp -d)
mkdir -p artifacts/states artifacts/snap "$W/cfg" "$W/nvram"
# Headless, always: MAME's own defaults are fullscreen, and on macOS a run
# that opens a window makes the desktop jump to a new Space.  -video none does
# not stop the window being created; SDL_VIDEODRIVER=dummy (read before MAME
# parses anything) and -videodriver dummy stop it, and -window -nomaximize
# keep it small if one is created regardless.  dumpstate.lua ends the run a
# few frames after the last one asked for; -seconds_to_run is the backstop
# if it does not (a Lua exit has proved unreliable in other cores).
LAST=$(echo "$FRAMES" | tr ',' '\n' | sort -n | tail -1)
SECS=$((LAST / 60 + 10))
OUTDIR=artifacts/states FRAMES="$FRAMES" SDL_VIDEODRIVER=dummy mame $GAME -rompath "$ROMPATH" \
    -video none -videodriver dummy -window -nomaximize -sound none -nothrottle \
    -skip_gameinfo -seconds_to_run "$SECS" \
    -cfg_directory "$W/cfg" -nvram_directory "$W/nvram" -snapshot_directory "$W/snap" \
    -autoboot_script tools/dumpstate.lua 2>&1 | grep -v "^Warning\|^Average"
i=0
for f in $(echo "$FRAMES" | tr ',' ' '); do
    n=$(printf %05d $f)
    mv "$W/snap/$GAME/$(printf %04d $i).png" "artifacts/snap/${PREFIX}_f$n.png"
    mv "artifacts/states/f$n.txt" "artifacts/states/${PREFIX}_f$n.txt"
    i=$((i+1))
done
rm -rf "$W"
ls -la artifacts/states artifacts/snap
