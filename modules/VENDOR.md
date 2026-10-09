# Vendored modules

These directories are third-party HDL cores vendored into the tree (no
submodules -- the whole point is a self-contained, reproducible build). Each
was copied from its upstream repository at the commit below (by way of the
S.T.U.N. Runner core's tree); their own LICENSE files are kept alongside the
sources.

| module | upstream | commit |
|---|---|---|
| cpu-t65 | https://github.com/mist-devel/T65 (via plasticbugs/punchout, plasticbugs/stunrunner) | vendored |
| sound-jt51 | https://github.com/jotego/jt51 | 985a573dcfc1ff135553a39f7eae21d18ba57cbe |
| sound-tms5220 | https://github.com/d18c7db/TMS5220_FPGA (GPL-3; from MAME's tms5220.cpp, "Speak External" only, which is all the System 2 board uses) | 5285e1eff99859ca25e9f2d6bdab10b9830dd0ff, with five local changes (each marked `(plasticbugs)` in `TMS5220.vhd`): the two FIFO bit-extraction slices whose width is `K_bits(m_PC-2)` are spelled out per width (5 / 4 / 3) so every slice bound is static for GHDL synth; /READY is timed as MAME's `tms5220.cpp` times it (inactive from the /WS falling edge, the write serviced 16 chip clocks later, a data byte entering the FIFO then or waiting while the FIFO is full); and a command is latched at /WS and takes effect when the write is serviced, its flag one chip clock wide (the original decoded at the edge and left a RESET holding the chip, and /READY active, until the next write); and MAME's `FAST_START_HACK`, TALK raised together with SPEN at the write that takes the FIFO past half full, so speech (and a stop frame's halt) starts one 25 ms frame earlier than the original model; and the timing generator (PHI phases, T, PC, IC) restarts on a reset -- the RESET command or the board's sound reset -- as MAME's device reset does, where the original free-ran from power-on (the halt after a stop frame depends on the frame phase: APB's was 24 ms in MAME and 36 ms in the model before) |

Under `target/pocket/` rather than here, because it is the Pocket's
cartridge port and not the machine:

| module | upstream | commit |
|---|---|---|
| `target/pocket/analogizer/` | RndMnkIII's Analogizer adapter module (`openFPGA_Pocket_Analogizer` 1.4) and the 14 files it instantiates, verbatim, via the pocket-core-template (d9503cc); `analogizer.qip` is ours | https://github.com/RndMnkIII/MiraxPocket, `src/fpga/analogizer/` | 9dfdd2b9bec79fe5ea10e154a0613a0c9d4fe37f; GPL-3.0-or-later (the host core's), `hq2x.sv`, `scandoubler_2.v`, `yc_out_legacy.sv` carry their own GPL headers |

`core.qip` includes its own `analogizer.qip`, and `sim/lint.sh` lints it
behind `target/pocket/pocket_analogizer.sv` with a stand-in for its one VHDL
file (`sim/ps2_keyboard_stub.v`).

`cpu-t65/gen/t65.v` and `sound-tms5220/gen/tms5220.v` are the GHDL
conversions of the VHDL (`tools/gen_vhdl_cores.sh`); that Verilog is what
both Quartus and Verilator compile.

To update one: re-copy from upstream at the new commit (do not add it as a
submodule) and record the commit here.
