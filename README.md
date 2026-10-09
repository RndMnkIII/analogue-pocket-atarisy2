# Atari System 2 for Analogue Pocket

An openFPGA core for the **Atari System 2** arcade board (Atari Games,
1984-87), reimplementing it in gateware: a DEC T-11 main CPU behind an Atari
slapstic, the System 2 playfield / alphanumerics / motion object video, and
the sound board with its 6502, two POKEYs, a YM2151 and -- on the games that
carry one -- a TMS5220 speech chip. Five games run on it; nothing is emulated
in software.

> **ROMs are not included and never will be.** You supply your own MAME
> romsets; the core reads one image built from each.

## Games

| game | MAME set | status |
|---|---|---|
| Super Sprint (1986) | `ssprint` | plays on the Pocket; image byte-identical, T11 instruction- and cycle-exact, the video and boot gate frames pixel-identical to MAME, and the sound board matches MAME's 15 s log write for write |
| APB - All Points Bulletin (1987) | `apb` | plays on the Pocket (sound, speech and screen shape confirmed); image byte-identical, T11 cycle-exact, the attract mode and the start of a game pixel-identical to MAME; on the sound board the speech stream and POKEY 1 are MAME's and what is left are microsecond races between a T11 command and the 6502's interrupt handler |
| Championship Sprint (1986) | `csprint` | plays on the Pocket; image byte-identical, T11 cycle-exact, the video and boot gate frames MAME's, and the sound board's YM2151, POKEY and response streams match MAME's 15 s log (bar its last 5 ms, where MAME's own 6502 serviced an interrupt twice) |
| Paperboy (1984) | `paperboy` | plays on the Pocket; slapstic 105, speech, handlebars on two ADC channels: image byte-exact, T11 cycle-exact, the video gate states pixel-identical and the boot too but for one small element, the sound board's 15 s identical to MAME's log |
| 720 Degrees (1986) | `720` | plays on the Pocket; slapstic 107, speech, the rotating joystick on two LETA counters: image byte-exact, T11 cycle-exact over the boot and a park demo, the attract states in the video gate pixel-identical, the sound board's POKEYs and speech stream identical to MAME's log (the RANDOM bytes it reports differ because MAME's are its scheduler's, not the chip's) |

## Status (0.3.4)

0.3.3 and 0.3.4 fix the ROM recipes only (the core is 0.3.2's): the interleave
maps follow the MRA convention, and each part carries one CRC, current MAME's,
so standard MRA tools build every image from current merged romsets.

0.3.2 ships the platform's own image on the Pocket (the earlier one was a
placeholder).

0.3.1 feeds the pedals as MAME's port reads them when a player drives it,
0x3f up and 0x00 floored (0xff, what an untouched port reads in a headless
MAME, made APB's pedal calibration wrap and drive the car by itself at the
start of a game until the pedal had moved once), and gives the Sprints and
APB a half-throttle button: L is half gas, the face buttons and R floor it.

0.3.0 adds Paperboy and 720 Degrees and the sound-board fixes found while
matching their speech, and APB's, against MAME: the TMS5220's /READY now
stays inactive for 16 chip clocks after every write (a RESET command used to
let it return at once, so the idle stream fed the chip a third faster),
speech starts a frame earlier and the chip's frame timing restarts on a reset
as MAME's does (a stop frame's halt was up to 12 ms off), the sound IRQ's
phase follows the 6502's reset (every sound event was 0.6-1.8 ms late on the
games that reset the sound board late in their boot), and the POKEYs keep
running through the sound reset as on MAME. The sound bench now pairs each of
the T11's response reads with the response it consumed and replays it once
the RTL's 6502 has written that byte, instead of at MAME's logged time, which
MAME stamps with its own timeslice clock. Super Sprint's, Championship
Sprint's and Paperboy's sound boards match MAME's 15 s logs write for write.

Verified against MAME as the oracle (details and numbers in
`docs/verification.md`):

* the T-11 core is instruction-trace-exact against MAME over the boot and
  over 40 frames of play (358,220 instructions, every I/O read replayed,
  every interrupt taken at the same instruction boundary), and cycle-exact
  over the 618,185 instructions of the busiest attract stretch (10,649,457
  cycles in both); the other four games' boot traces are cycle-exact too,
  each on its own slapstic
* the video is pixel-identical to MAME on every frozen state in the gate
  (title, track select, three gameplay frames)
* the whole machine boots from the ROM image to the title screen, identical
  to MAME's frame at the same frame number
* the sound board's 6502 drives the POKEYs and the YM2151 with MAME's
  register write sequence, byte for byte, through 15 s of boot, coin, start
  and race (18,626 YM2151 writes, 32,708 POKEY writes, 1,484 responses),
  and the audio envelope matches MAME's within 0.01 dB
* a played race runs end to end in the whole-machine bench with the
  arcade's inputs; its frames differ from MAME's only in the cars' positions
  by a few pixels, a 2-frame lead traced to MAME's own CPU scheduling (see
  the verification notes), not to the core
* the core fits the Pocket's Cyclone V and closes timing: the compile
  recorded in `docs/verification.md` is 46 % of the ALMs, 156 of 308 M10K
  blocks and +0.99 ns on the 96 MHz clock at the slow 85 C corner, with no
  negative slack at any corner
* one core, listed on the Pocket as "Atari System 2" with each game under
  its own name (instance files), per-game saves, one image format for all
* it runs on a Pocket: all five games boot, take a coin and play with sound.
  The D-pad's steering direction was checked on hardware; a dock pad's analog
  stick has not been, and a menu entry reverses it

## Installing

1. Download the SD-card package from the releases page --
   https://github.com/plasticbugs/analogue-pocket-atarisy2, built by CI from
   `v*` tags -- and copy `Cores/`, `Platforms/` and `Assets/` from it onto
   the root of the Pocket's SD card.
2. Build the ROM image for each game you have and copy it to
   `Assets/atarisy2/common/`:

   ```sh
   python3 tools/mra_build.py ssprint.mra ssprint.zip     # -> ssprint.rom
   python3 tools/mra_build.py apb.mra apb.zip             # -> apb.rom
   python3 tools/mra_build.py csprint.mra csprint.zip     # -> csprint.rom
   python3 tools/mra_build.py paperboy.mra paperboy.zip   # -> paperboy.rom
   python3 tools/mra_build.py 720.mra 720.zip             # -> 720.rom
   ```

   The release zip ships `mra_build.py` and the five `.mra` files side by
   side at its top level, so there it is `python3 mra_build.py <game>.mra
   <game>.zip`. Nothing but Python 3 is needed: it checks every ROM's CRC32
   and the finished image's md5. Every image is 2,196,480 bytes (format 2,
   `docs/hardware.md` section 9; images built by 0.1.x must be rebuilt). An
   already-extracted romset works too -- pass the directory instead of the
   zip.

The Pocket lists the platform as "Atari System 2" and each game under it by
name; a game whose image is missing simply will not start.

## Controls

Player 1 is the Pocket's own controls (or dock pad 1); the Sprints' other
players are dock pads 2 and 3. The Sprints map the cabinet directly:

| Pocket | Arcade |
|---|---|
| D-pad left / right, or the left stick | steering wheel |
| A, B, X, Y or R | accelerator, floored |
| L | accelerator, half way |
| Select | coin |
| Start | start |
| dock pads 2 and 3 | players 2 and 3 (their own wheel, pedal, coin and start) |

Per game:

* **Super Sprint** -- the table above, for its three players.
* **Championship Sprint** -- Super Sprint for two players on the same
  controls (dock pad 2 is player 2); it shares the "Sprint:" switches.
* **APB** -- D-pad or stick steers; B, X or R floor the accelerator and L is half throttle; A is the
  siren, which also starts the game and picks the day; Y is the game's other
  button; Select is the coin.
* **Paperboy** -- the D-pad or stick is the handlebars (left / right steer,
  up / down set the speed); A and B throw papers left and right, and A also
  starts the game; Select is the coin.
* **720 Degrees** -- the D-pad or stick points the rotating joystick, which
  turns toward that direction at the "Steering Speed" rate; L and R spin it
  left and right for the game's spins; A and B are its two buttons, and A
  also starts the game; Select is the coin.

The wheel turns while a direction is held, at the rate the "Steering Speed"
entry sets. A dock pad's left stick turns it in proportion to its deflection;
the "Analog Stick" entry makes it half or twice as reactive and reverses it
if it steers the wrong way (the D-pad's direction was checked on hardware,
the stick's has not been yet).

The core settings menu has 16 entries, the most the Pocket shows: Reset
Core, Screen Shape, Steering Speed, Analog Stick, the games' switches --
"Sprint: Difficulty" and "Sprint: Obstacles" (both Sprints share them),
"APB: Difficulty", "Paperboy: Difficulty", "720: Difficulty" and "720: Bonus
Life" -- and six for the Analogizer (below). To make room for those, three
entries earlier versions had are gone: **Scanlines** and **Shadow Mask**
(the Pocket screen's effects, now always off) and **Sprint: Wrenches**
(both Sprints now always need the factory 3 wrenches for an upgrade, MAME's
default, which is the DIP register's 0). That is all of it: every game is one coin
per play, so coinage, the coin multiplier and bonus coins are held at their
factory settings and are not in the menu (APB starts and continues on one
coin, with 199 continues), and neither is the self-test switch. "Screen
Shape" is "Wide" (the cabinet's 4:3, or 3:4 rotated) or "Tall" (the Pocket's
10:9). APB's screen is the vertical one, and the Pocket's scaler rotates it.

## Analogizer

The core supports RndMnkIII's [Analogizer](https://github.com/RndMnkIII/Analogizer)
adapter: the board's own picture out of the VGA port, and SNAC controllers
in place of the Pocket's. **The picture is the board's medium-resolution
signal: 512x384 visible, 25.0 kHz lines, 60.1 Hz** -- a System 2 cabinet's
monitor, which no 15 kHz television or PVM syncs to. What each video mode
needs:

| Analogizer Video | line rate | needs |
|---|---|---|
| RGBS, RGsB, YPbPr | 25.0 kHz | a medium-resolution (25 kHz) or tri-sync arcade monitor, a multisync broadcast monitor that takes 25 kHz, or a scaler that accepts it |
| Scandoubler (and 25/50/75%, HQ2x) | 50.0 kHz, 832 lines at 60.1 Hz | a multisync PC CRT that reaches 50 kHz (most 1024x768-class ones do) |

Y/C is not offered: no television takes 25 kHz lines. It is set up in the
core's own menu (Analogizer, Analogizer Video, SNAC Adapter, SNAC
Assignment, and H and V Position to centre the picture); with "Analogizer"
off, the default, the core is unchanged. The picture is not rotated: APB
comes out on its side, as its cabinet's monitor was mounted. Because the
core declares a cartridge adapter, the Pocket powers the slot: take any game
cartridge out first. SNAC pads replace the D-pad and buttons; steering,
handlebars and the 720 stick then come from the pad's d-pad (the steering
rate from "Steering Speed"), and a dock pad's analog stick is not involved.
`docs/analogizer.md` has the modes, the controller assignments, and what has
and has not been checked (the path is proven in simulation only).

Settings and high scores (the board's EEPROM) are saved to
`Saves/atarisy2/plasticbugs.atarisy2/<game>.sav`, one file per game.

## Repository layout

| Path | What |
|---|---|
| `docs/hardware.md` | the machine, from MAME's driver and Lua probes -- read first |
| `docs/rtl-conventions.md` | clocks, memory interfaces, block interfaces |
| `docs/verification.md` | what has been checked against MAME, how, with what result |
| `rtl/` | the core: `ssprint_core.sv` (machine), `ssprint_main.sv` (T11 board), `t11/t11.sv` (the CPU), `slapstic.sv` (types 105-110, MAME's table selected by the image header), `ssprint_video.sv`, `ssprint_sound.sv`, `pokey.sv`, `sdram_ctrl.sv`, `clk_enables.sv`, `dpram_be.sv` / `sdpram.sv` |
| `modules/` | vendored cores: T65 (6502) and the TMS5220 speech chip, both GHDL-converted VHDL, and jt51 (YM2151) -- `modules/VENDOR.md` |
| `target/pocket/` | the Pocket top level `core_top.sv` and the controllers built for it: `steer_wheel.sv`, `ctrl_720.sv`; the Analogizer wrapper `pocket_analogizer.sv` and RndMnkIII's module under `analogizer/` (`docs/analogizer.md`) |
| `sim/` | Verilator benches: `run_t11.sh`, `run_video.sh`, `run_sound.sh`, `run_system.sh`, `run_analogizer.sh`, `lint.sh` |
| `tools/` | `mra_build.py` (ROM image) and `check_rom.lua` (checks it against MAME's regions), `render_model.py` (reference frame renderer), MAME Lua probes (`dumpstate.lua`, `trace_t11.lua`, `trace_sound.lua`) and the capture script `capture_states.sh`, `compare_sound.py`, `diff_png.py` / `diff_frames.py`, the two machines' event timelines (`wipe_events.py`, `compare_events.py`), `gen_vhdl_cores.sh` |
| `*.mra` | the ROM recipes: `ssprint.mra`, `apb.mra`, `csprint.mra`, `paperboy.mra`, `720.mra` |
| `ref/mame/` | the MAME sources the RTL was written from |
| `platform/pocket/`, `projects/`, `pkg/pocket/`, `package-pocket.py` | Pocket integration framework, Quartus project, core package and the packaging script |
| `artifacts/` | scratch outputs (MAME snapshots, state dumps, traces, diffs); gitignored |

## Building

```sh
./build-local.sh map      # quartus_map only, ~2 min: catches syntax/inference errors
./build-local.sh          # full compile in Docker (raetro/quartus:pocket) + package
./sim/lint.sh             # Verilator lint of everything that synthesises
```

CI (`.github/workflows/compile.yml`) lints the RTL with Verilator, compiles
with Quartus 18.1 in the `raetro/quartus:pocket` image, checks that timing
closed and that the block RAM still fits, and uploads the SD-card package. It
runs on pushes to `main` and `multigame` and on `v*` tags, which publish the
package as a release.

## Credits

The Atari System 2-specific RTL and verification harness are original; the
rest of the core is built on other people's work.

**Platform & toolchain**

* the **Analogue Pocket** openFPGA framework (APF) -- Analogue Enterprises
  Limited
* **boogermann (Marcus Andrade)** / OpenGateware -- the Pocket integration
  framework `platform/pocket/` is built from, and the `raetro/quartus:pocket`
  Docker image; the hiscore/NVRAM support carries earlier copyright from Alan
  Steremberg and Jim Gregory
* the S.T.U.N. Runner and Xenophobe Pocket cores (plasticbugs) -- the
  platform tree, the SDRAM controller (whose pin-level timing comes from the
  Punch-Out!! core's `sdram16.sv`), the bench and release tooling, and the
  method in `METHODOLOGY.md`
* **RndMnkIII** -- the [Analogizer](https://github.com/RndMnkIII/Analogizer)
  adapter and its `openFPGA_Pocket_Analogizer` module
  (`target/pocket/analogizer/`, taken verbatim from his MiraxPocket core by
  way of the pocket-core-template), with the parts it gathers from others:
  the Y/C encoder by **Mike Simone** (MiSTerFPGA_YC_Encoder), the
  scandoubler and HQ2x by **Sorgelig** and **Ludvig Strigeus** (MiSTer), the
  PlayStation controller interface after **pgate1**'s psPAD, and the SNAC
  game-controller readers he credits to **@MikeSimonson**, the **MiST**
  project, **@RandyS**, **jotego**, **Scott Larson** (the PS/2 receiver) and
  **@tomasz**
* **GHDL** -- converts the vendored VHDL cores to Verilog
* **Verilator** -- every simulation bench in `sim/`

**Vendored cores** (`modules/`, see `modules/VENDOR.md` for the commits and
the local changes)

* **T65**, the 6502 core from FPGAARCADE (Daniel Wallner, Mike Johnson,
  Wolfgang Scherr and other contributors) -- `modules/cpu-t65`
* **JT51** (YM2151) by Jose Tejada (jotego) -- `modules/sound-jt51`
* the **TMS5220** speech model by **d18c7db** (TMS5220_FPGA, GPL-3, itself
  written from MAME's `tms5220.cpp`) -- `modules/sound-tms5220`, vendored with
  five local changes: the FIFO bit-extraction slices spelled out per width so
  GHDL can synthesise them, MAME's /READY timing, a command latched at /WS and
  taking effect when the write is serviced, MAME's `FAST_START_HACK`, and a
  timing generator that restarts on a reset as MAME's device reset does

**Reference & verification**

* **MAME** -- the `atarisy2` driver, `atarimo`, `slapstic`, the T11 CPU core,
  the POKEY emulator and `tms5220.cpp` are the behavioural reference the RTL
  was written from and verified against (`docs/hardware.md`,
  `docs/verification.md`, `METHODOLOGY.md`)
