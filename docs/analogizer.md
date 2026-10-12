# The Analogizer

[Analogizer](https://github.com/RndMnkIII/Analogizer) is RndMnkIII's adapter
for the Pocket's cartridge slot. It gives analog video out of a VGA connector
(RGBS, RGsB, YPbPr, Y/C, and a scandoubled RGBHV) and takes native controllers
through SNAC adapters. Its wiki is the authority on the adapter itself:
[specifications](https://github.com/RndMnkIII/Analogizer/wiki/Analogizer-Specifications),
[how to configure it](https://github.com/RndMnkIII/Analogizer/wiki/Supported-Cores-and-How-to-Configure-Them).

This core supports it (`USE_ANALOGIZER = 1` in `core_top.sv`), added as
`docs/analogizer-retrofit.md` in the pocket-core-template describes. This page
is what the player needs to know, how it is put together, and what has been
proven.

## For the player

**Settings are in the core's own menu**, under the games' other options, like
RndMnkIII's own "Pocket Menu" Analogizer cores (the wiki's list calls the other
kind, which reads a shared `analogizer.bin`, "Analogizer File"; this core does
not read that file). The Pocket remembers them for this core.

| entry | options |
|---|---|
| Analogizer | Off (the default), On, On, Sharp, On, Pocket off, On, Sharp, Pocket off |
| Analogizer Video | RGBS, RGsB, YPbPr, Y/C NTSC, Scandoubler, Scandoubler HQ2x |
| SNAC Adapter | None, DB15, NES, SNES, PCE Multitap, PSX Digital, PSX Analog |
| SNAC Assignment | the six below |
| Analogizer H Position | -5 to +12 dots; + moves the picture right |
| Analogizer V Position | -40 to +27 lines; + moves the picture down |

With **Analogizer** off the core behaves exactly as it did without Analogizer
support. The adapter itself is set up as its wiki's
[How to use it](https://github.com/RndMnkIII/Analogizer/wiki/How-to-use-it%3F)
says: SNAC switch in position A, 5 V into its USB-C port, the cable's audio
jack in the Pocket's headphone socket.

To make room for these six entries under the Pocket's limit of 16, three the
menu had before are gone: Scanlines and Shadow Mask (the Pocket screen's
effects, now always off) and Sprint: Wrenches (now always the factory 3).

**Video: 15 kHz 192p, converted from the board's 25 kHz.** The board drives
a medium-resolution monitor: 512 × 384 visible, 640 × 416 dots at 16 MHz,
25.0 kHz lines, 60.1 Hz. A 15 kHz set cannot show that -- on a 15 kHz PVM the
first build, which sent it as it was, showed about seven interlaced copies of
the screen -- so the core converts it (`target/pocket/ana_15k.sv`) before
the adapter: **192 lines at 15.75 kHz and the board's own 60.1 Hz**,
progressive, each line one pair of the board's 384. "On" blends the pair
(each dot the average of the two, so nothing one line thin vanishes and
nothing flickers); "On, Sharp" shows the pair's even line. The 192 lines
sit in a 262-line frame as a console's 192-line mode does (27 blank lines
below the picture, 3 of vsync, 40 above), 512 dots in 53 µs of each 63.5 µs
line, so the picture keeps its shape. It is frame-locked to the game: never
interlaced, dropped or torn. The Pocket's own screen is unchanged.

| mode | SOG switch | line rate | for |
|---|---|---|---|
| RGBS | off | 15.75 kHz | a PVM, an arcade monitor, a TV with RGB (VGA-to-SCART or BNC) |
| RGsB | on | 15.75 kHz | as RGBS; R2/R3 adapters only |
| YPbPr | on | 15.75 kHz | a component input; R2/R3 adapters only |
| Y/C NTSC | off | 15.75 kHz | a TV's S-Video input; needs an active Y/C adapter on the VGA port |
| Scandoubler, Scandoubler HQ2x | off | 31.5 kHz | a VGA monitor |

Y/C PAL and the scandoubler's 25/50/75% scanline modes are not in the menu:
the firmware refuses a menu with more options than this one has.

The picture is not rotated: APB, a vertical game, comes out on its side, as
its cabinet's monitor was mounted. "On, Pocket off" turns the Pocket's own
picture black while the monitor keeps it.

**Position.** The two sliders move the picture on the monitor, in the 15 kHz
picture's dots and lines. They move the syncs, not the picture, so nothing is
cropped and every mode follows; the size is still the monitor's to adjust.
0 is the timing above. Its blanking sets the range: hsync may come 12 dots
earlier before it meets the picture and 5 later before the Y/C colour burst
does; vsync may move 27 lines earlier and 40 later.

**Controllers.** SNAC pads (DB15, NES, SNES, PC Engine 2/6-button and
multitap, PlayStation) replace the Pocket's controls according to the
**SNAC Assignment** chosen in the menu:

| assignment | player 1 | player 2 | player 3 |
|---|---|---|---|
| SNAC P1 → Pocket P1 | SNAC 1 | the Pocket's own controls | dock 3 |
| SNAC P1 → Pocket P2 | Pocket | SNAC 1 | dock 3 |
| SNAC P1,P2 → P1,P2 | SNAC 1 | SNAC 2 | dock 3 |
| SNAC P1,P2 → P2,P1 | SNAC 2 | SNAC 1 | dock 3 |
| SNAC P1,P2 → P3,P4 | Pocket | dock 2 | SNAC 1 |
| SNAC P1-P4 → P1-P4 | SNAC 1 | SNAC 2 | SNAC 3 |

Three-player Sprint from SNAC needs the PC Engine multitap. A pad's buttons
arrive as the Pocket's own, so they do what the Pocket's do in each game:
the d-pad steers (at the "Steering Speed" rate), points the 720 stick or
turns Paperboy's handlebars, and A, B, X and Y are the gas and buttons. The
analog-stick paths (a dock pad's left stick turning a wheel) are the dock's
own and are not fed from SNAC.

**Cart power is on for everyone.** `core.json` declares the cartridge adapter,
so the Pocket powers the slot whether or not an Analogizer is in it. Do not
leave a game cartridge in the slot while this core runs.

**The 15 kHz output has not been tried on hardware yet.** The build before it
sent the board's 25 kHz picture, which the 15 kHz PVM it was tried on showed
as about seven interlaced copies of the screen. What the benches prove is
listed under *What was measured* below. Send problems with the adapter itself to the
Analogizer project.

## For the developer

### The pieces

| file | what |
|---|---|
| `target/pocket/analogizer/` | RndMnkIII's `openFPGA_Pocket_Analogizer` and what it instantiates, **verbatim** (modules/VENDOR.md has the commit). Its `analogizer.qip` is ours: only what is used. |
| `target/pocket/ana_15k.sv` | this core's 25 → 15 kHz converter (below), in front of the wrapper. |
| `target/pocket/pocket_analogizer.sv` | the wrapper: clock hand-over, Y/C constants, picture position (and a width stage this core has no menu entry for), SNAC → controller words. Core-agnostic; the same file as the pocket-core-template's (2545276). |
| `target/pocket/core_top.sv` | `USE_ANALOGIZER`, the converter and the instance (`LINE_LEN` 609, `CLK_HZ` 48 MHz), Sharp decoded from bit 16 of the bridge's write to `0xF7000000`, `key1..key4` in place of `cont1..4_key` (the `gamepad` helper and player 3's direct read), the bridge read at `0xF7xxxxxx`, the Pocket-screen blank, and the cart pins' idle levels when it is off. |
| `core_pll` `outclk_4` | the Analogizer's 48 MHz, `clk_sys / 2` in phase (`general[4]`), in the SDC's PLL group. |
| `pkg/.../interact.json` | the entries above: ids 100–103, each a masked field of the word at `0xF7000000`, and 104–105, signed sliders at `0xF7000004` and `0xF7000008`. Not the template's 70–75: 73–75 are the Sprint switches here. 16 entries and 3 data slots, Analogue's limits (16, and 20 together). |
| `pkg/.../core.json` | `"cartridge_adapter": 0` (powers the slot) |
| `sim/run_ana15k.sh` | the converter's bench (below) |
| `sim/run_analogizer.sh` | the wrapper's bench (below), at the converter's raster, set at the top of `sim/tb_analogizer.sv` |
| `tools/check_json.py` | the template's (9233037): fails if an entry writes outside its mask, none sets the enable, a position slider is not signed within ±127, a data slot also writes `0xF7000000`, the slot is not powered, or the menu has more than 68 options or 80 options and entries; its size limit is this core's own released menu (11,568 bytes, which loads) |

### The settings word

One 32-bit word at `0xF7000000`, the layout RndMnkIII's adapter module (1.4)
decodes. Each menu entry is a list with a mask that keeps every bit but its
own field (or fields), so the four entries share the word:

| bits | field | values |
|---|---|---|
| 4:0 | SNAC type | 0 none, 1 DB15, 2 NES, 3 SNES, 4 PCE 2-button, 5 PCE 6-button, 6 PCE multitap, 9 DB15 fast, 0xB SNES A/B↔X/Y, 0xC–0xF PS/2 keyboard (+ pad; not in the menu, the wrapper does not wire the keyboard out), 0x10/0x11 PSX digital (125/250 kHz), 0x12/0x13 PSX analog. 16 and up select the adapter's B wiring. |
| 5 | enable | 0: the port stays idle and nothing else applies |
| 9:6 | SNAC assignment | 0–5 as in the table above |
| 13:10 | video | 0 RGBS, 1 RGsB, 2 YPbPr, 3 Y/C NTSC, (4 Y/C PAL: not offered), 5 scandoubler, (6–8 scandoubler 25/50/75%: not offered), 9 HQ2x |
| 14 | blank the Pocket screen | |
| 15 | OSD on the Analogizer output | not used; no menu entry |
| 16 | Sharp (this core's, not the adapter's) | 0 Blend, 1 the pair's even line; the adapter module ignores bits 16–30, so `core_top` decodes it from the bridge write, with the enable |

**Read-back.** The word is written as a number (the adapter module is told
`bridge_endian_little = 1`, so it does not byte-swap it as it would a file),
and `pocket_analogizer` keeps its own copy to read back, combinationally.
The Pocket's bridge (`io_bridge_peripheral.sv`) samples read data four clocks
after it presents the address and pulses `bridge_rd` only afterwards; the
adapter module updates its read-back on that pulse, so it would hand back
the *previous* read's value. The firmware merges a masked entry by reading
the word back (Analogue's interact.json docs: every entry not `writeonly` is
read back every frame), so that stale value would wipe the other fields.

**Picture position.** Two more words, each a whole signed slider value
(no mask): `0xF7000004` horizontal in dots, + right, and `0xF7000008`
vertical in lines, + down. `pocket_analogizer` reads the low 8 bits and
reads both words back. They move the syncs, not the picture: hsync n dots
earlier puts the picture n dots right, vsync n lines earlier puts it n
lines down, each re-made from the source's own rising edge after a delay
counted in dots, as wide as the source's. A re-made sync starts only once it
has been off at least as long as it is on, because the adapter module's
`sync_fix` re-decides each sync's polarity every period; a jump between
settings skips one pulse rather than turning csync inside out for a frame.

The range is the 15 kHz picture's blanking: dots 512–608 with hsync on
524–568 leave 12 dots before it and 40 after, of which the Y/C colour burst
needs all but 5; lines 192–261 with vsync on 219–221 leave 27 lines before
it and 40 after. The bench tries both ends of the range in `interact.json`
and fails if csync is low while a dot is drawn or the picture starts inside
the burst; one step past either end of either slider (+13 or -6 dots, +28 or
-41 lines) fails it.

**Menu size.** 16 entries and 64 options, 7,765 bytes. The firmware refused
this menu at 70 options (below); 64 with 16 entries is what MSX2's 68 and 80
allow. The size limit is this core's own 0.3.x menu (11,568 bytes, which
loads: Paperboy and 720 play on the Pocket with it).

### The 25 → 15 kHz converter

`ana_15k.sv` runs on `clk_sys` (96 MHz) and takes the board's picture as the
Pocket gets it, one dot per `ss_ce_pix`. Each pair of board lines becomes one
output line: the even line waits in a one-line buffer, and as the odd one
arrives each dot of the pair -- the two averaged per channel on the full 8
bits, or the even one -- goes into a ring, kept to the 6 bits a channel the
DAC shows. The output reads the ring at 10 clocks a dot (9.6 MHz).

A pair is 80 µs of source and an output line 63.5 µs, so the output runs
faster than the board and has to start late: its 192nd line can only be
shown after the board's 384th has arrived, so it starts about 40 pairs
behind and catches up over the frame. The ring holds 48 pairs (48 blocks of
RAM); the output frame starts `DELAY` = 336,000 clocks after the board's
first visible line, between the two limits the bench measures -- a dot is
read at least 29,825 clocks after it is written (the last pair is the
tightest) and at least 34,436 clocks before its slot is written again (pair
48, replacing pair 0, is the tightest).

The output frame is 262 lines that add up to exactly the board's 1,597,440
clocks, so it is locked to the game and vsync falls on the same line every
frame: every dot is 10 clocks but each line's last, in the back porch, which
is 17, or 18 on 26 lines a frame (a Bresenham spread). Lines are 6,097 or
6,098 clocks (63.5 µs, 15.75 kHz), never anything else; hsync is 45 dots
(4.7 µs), 12 dots after the picture.

### Clocks

`openFPGA_Pocket_Analogizer` runs its logic on `i_clk`, puts `video_clk` on the
cartridge pin that clocks the ADV7123, and assumes that is `i_clk` too. The
scandoubler halves the dot, so the clock has to be at least four times the
dot rate. The converter's dot is 9.6 MHz, so the Analogizer runs at 48 MHz,
five clocks a dot: the PLL's spare output, `clk_sys / 2` in phase, the rate
the shipped Analogizer cores use. (The first build sent the board's 16 MHz
dots and had to run it at 64 MHz, faster than any shipped core puts through
the cartridge's level translators.) `pocket_analogizer` takes each pixel
`PIX_LAG` (2) system clocks after the converter's enable (its outputs change
at the end of that cycle) into a holding register and hands it over with a
toggle; the Analogizer side picks it up two or three of its clocks later,
inside the five-clock dot. The lines' longer last dot only stretches one
dot of the back porch.

The Y/C encoder's subcarrier step and colour-burst window are computed in
integers from `CLK_HZ`.

### Using SNAC in the game's inputs

`pocket_analogizer` outputs `key1..key4`, the Pocket's controller words with
SNAC pads put in place by the assignment. SNAC's bit order is the Pocket's
(0 up, 1 down, 2 left, 3 right, 4 A, 5 B, 6 X, 7 Y, 8 L1, 9 R1, … 14 select,
15 start). They feed the `gamepad` helper, and player 3's wheel, which reads
its word directly, in place of `cont1..4_key`. The analog sticks (`cont*_joy`)
are the Pocket's either way.

### What was measured

- `sim/run_ana15k.sh`: the converter on its own, fed the board's raster (640
  × 416 dots, a dot every sixth 96 MHz clock) with a colour every dot and
  line can be told apart by, over six frames after it locks.
  - Every output line j shows pair j's 512 dots, in order, exactly: the
    average of lines 2j and 2j+1 per channel kept to 6 bits (Blend, 4
    frames), or line 2j's 6 bits (Sharp, 2 frames); 192 lines a frame.
  - Every hsync period is 6,097 or 6,098 clocks, 26 of the long a frame,
    hsync 450 clocks; vsync once a frame, on line 219 every time, its period
    the board's 1,597,440 clocks; every frame restart falls on the natural
    end of line 261.
  - The ring: all 589,824 picture-dot reads find the pair they should show;
    the least margins are 29,825 clocks from a write to its read and 34,436
    from a read to its slot's next write. At `DELAY` 300,000 the output
    overtakes the board (11,358 reads too early) and at 372,000 the board
    overwrites pairs before they are read (4,704): both runs fail, as the
    script requires.
- `sim/run_analogizer.sh`: the wrapper and the vendored module at the
  converter's raster (609 × 262, 10 clocks a dot -- the bench's dots are all
  10 clocks; the converter's long last dot is measured above) and the 48 MHz
  Analogizer clock, read at the cartridge pins as the DAC reads them.
  - With the menu at its defaults, every pin sits as on a core without the
    adapter, and the controller words pass through.
  - Every option of the four Analogizer list entries in the package's
    `interact.json` (24), set as the firmware sets a masked entry -- read
    back the word as the bridge samples it, merged and written: the word, the
    adapter's copy and the enable each followed.
  - RGBS: all 98,304 visible dots of a frame reach the DAC pins, in raster
    order, as their top six bits per channel, with 0 differing. Csync is one
    45-dot pulse a line.
  - Scandoubler: 524 lines per frame (twice 262) at 1,523 clocks, half the
    line within the half clock an odd line leaves.
  - Position at +12,+27 and -5,-40: csync moves by exactly the dots and
    lines asked, never low while a dot is drawn, the picture never inside
    the colour burst; back at 0, csync where it started; jumps at once leave
    csync out of the picture. One step past each end fails.
  - The width stage (no menu entry here) at +3%, the most this raster has
    room for, and -10%: every dot, in order, centred within a clock.
  - YPbPr and Y/C NTSC/PAL: no unknown on any pin for a frame. SNAC
    assignments, the blank bit, and enable off returning the port to idle.
- `sim/run_video.sh` (the frozen-state video gate, five states): 0 differing
  pixels, as before -- the Pocket's picture does not pass through the
  converter.
- `sim/lint.sh`: clean under Verilator 5.050 here and under CI's 5.020 (in
  the `verilator/verilator:v5.020` container), the converter under the full
  `-Wall`.
- Quartus 18.1: compiles, every `ssprint_pocket.sdc` constraint applied (the
  three ignored are the platform's own `sys_constr.sdc` output delays), no
  negative slack at any corner. Without the Analogizer (0.3.4) → the 25 kHz
  build (27cbfd92) → this one: 8,817 → 10,404 → 10,877 ALMs (59%); 156 →
  182 → 242 RAM blocks of 308 (the ring's 48, the even-line buffer, and the
  scandoubler's and HQ2x's buffers at 609 dots); 52 → 54 → 58 DSP blocks of
  66. Worst setup +0.613 → +0.984 → +0.976 ns (slow 0C, `clk_sys`); worst
  hold +0.068 → +0.087 → +0.105 ns (fast 0C, inside jt51). SDRAM capture
  (`dram_dq` → `dq_in`) holds +0.11 ns at fast 0C: the SDRAM clock phase is
  unchanged.

**Not proven:** anything on hardware with the 15 kHz output (the 25 kHz
build's one run was on a 15 kHz PVM, which cannot show it); a 15 kHz set's
response to the 192p raster and its 15.75 kHz lines (NTSC's are 15.734); that
the firmware writes a signed slider value as a two's-complement word; that a
16-entry, 64-option menu loads (it is under what MSX2 loads); the SNAC serial
protocols, which are the adapter module's and are forced at its outputs in
the bench rather than driven over the pins. The YPbPr and Y/C encodings have
no reference to compare against, only a run without unknowns.

### Trying it on hardware

1. **"Analogizer: Off"** (the default). The games must play exactly as
   0.3.4 did, Pocket screen and controls. If not, the cart port is not idle:
   stop there.
2. **Analogizer On, Video RGBS, SNAC Adapter None**, on the 15 kHz PVM or TV:
   one steady, upright, blended picture (APB on its side), the set reporting
   about 15.7 kHz / 60 Hz. Then "On, Sharp": the same, crisper, with thin
   lines that may come and go as they move. Nothing at all: say whether the
   set reports a signal.
3. **The other modes**: RGsB and YPbPr (SOG switch on), Y/C NTSC on a TV's
   S-Video, Scandoubler and HQ2x on a VGA monitor.
4. **SNAC**: one pad, assignment "SNAC P1 -> P1"; the Pocket's own controls
   are then player 2.
5. **The menu's memory**: change Video, quit the core and load it again;
   the settings should still be there. Then change one entry and check the
   others did not move.
6. **Position**: + on "V Position" moves the picture down by that many
   lines, + on "H Position" right, and both are kept across a reload. Try a
   negative value early: no installed core has shown that the firmware
   writes one as this core reads it.

### Turning it off

Set `USE_ANALOGIZER = 0` in `core_top.sv`, take `general[4]` out of the PLL
group in the SDC (it would match nothing), and take the six menu entries and
`cartridge_adapter: 0` out of the JSON.

**The menu's size, measured on hardware (2026-10-09).** The first build of
this menu had over 68 options in all and the Pocket refused it ("Error in
interact" at core setup); MSX2 loads with 68, Cadash and Cloak with 54.
Analogue's docs say a list's options count toward no limit; this firmware
disagrees. The Analogizer's lists were trimmed to keep the whole menu at 64
(SNAC types a one- or two-player game has no use for); the 15 kHz build keeps
64, trading the scandoubler's 25/50/75% modes for Sharp and Y/C NTSC.
`tools/check_json.py` refuses more than 68 options, or more than 80 options
and entries together.
