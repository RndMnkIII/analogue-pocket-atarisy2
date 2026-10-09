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
| Analogizer | Off (the default), On, On, Pocket off (the picture goes to the monitor only) |
| Analogizer Video | RGBS, RGsB, YPbPr, Scandoubler, Scandoubler 25% / 50% / 75%, Scandoubler HQ2x |
| SNAC Adapter | None, DB15, NES, SNES, PCE 2-button, PCE 6-button, PCE Multitap, DB15 Fast, SNES A,B<->X,Y, PSX Digital, PSX Digital Fast, PSX Analog, PSX Analog Fast |
| SNAC Assignment | the six below |
| Analogizer H Position | -32 to +32 dots; + moves the picture right |
| Analogizer V Position | -20 to +8 lines; + moves the picture down |

With **Analogizer** off the core behaves exactly as it did without Analogizer
support. The adapter itself is set up as its wiki's
[How to use it](https://github.com/RndMnkIII/Analogizer/wiki/How-to-use-it%3F)
says: SNAC switch in position A, 5 V into its USB-C port, the cable's audio
jack in the Pocket's headphone socket.

To make room for these six entries under the Pocket's limit of 16, three the
menu had before are gone: Scanlines and Shadow Mask (the Pocket screen's
effects, now always off) and Sprint: Wrenches (now always the factory 3).

**Video: this is not a 15 kHz picture.** The core sends the board's own
signal: 512 × 384 visible, 640 × 416 dots at 16 MHz, **25.0 kHz lines and
60.1 Hz** -- the medium-resolution monitor System 2 cabinets used. A 15 kHz
television, a consumer CRT or a 15 kHz PVM will not sync to it.

| mode | SOG switch | line rate | needs |
|---|---|---|---|
| RGBS | off | 25.0 kHz | a 25 kHz (medium-resolution) or tri-sync arcade monitor, a multisync broadcast monitor that takes 25 kHz, or a scaler that accepts it |
| RGsB | on | 25.0 kHz | as RGBS; R2/R3 adapters only |
| YPbPr | on | 25.0 kHz | a component input that takes 25 kHz; R2/R3 adapters only |
| Scandoubler 0% / 25% / 50% / 75% / HQ2x | off | 50.0 kHz, 832 lines | a multisync PC CRT that reaches 50 kHz at 60 Hz (most that do 1024 × 768 do) |

Y/C NTSC and PAL are not in the menu: no television takes 25 kHz lines, so
they could only ever give a rolling picture. (The module still has them; the
bench runs them.)

The picture is not rotated: APB, a vertical game, comes out on its side, as
its cabinet's monitor was mounted. "On, Pocket off" turns the Pocket's own
picture black while the monitor keeps it.

**Position.** The two sliders move the picture on the monitor, in the board's
own dots and lines. They move the syncs, not the picture, so nothing is
cropped and every mode follows; the size is still the monitor's to adjust.
0 is the board's own timing. The board's blanking sets the range: 32 dots
either side of hsync, 8 lines before vsync and 20 after.

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

**Not tried on hardware with this core yet.** What the bench proves is listed
under *What was measured* below. Send problems with the adapter itself to the
Analogizer project.

## For the developer

### The pieces

| file | what |
|---|---|
| `target/pocket/analogizer/` | RndMnkIII's `openFPGA_Pocket_Analogizer` and what it instantiates, **verbatim** (modules/VENDOR.md has the commit). Its `analogizer.qip` is ours: only what is used. |
| `target/pocket/pocket_analogizer.sv` | the wrapper: clock hand-over, Y/C constants, picture position, SNAC → controller words. Core-agnostic; the same file as the pocket-core-template's. |
| `target/pocket/core_top.sv` | `USE_ANALOGIZER`, the instance (`LINE_LEN` 640, `CLK_HZ` 64 MHz), `key1..key4` in place of `cont1..4_key` (the `gamepad` helper and player 3's direct read), the bridge read at `0xF7xxxxxx`, the Pocket-screen blank, and the cart pins' idle levels when it is off. |
| `core_pll` `outclk_4` | the Analogizer's 64 MHz (`general[4]`), in the SDC's PLL group. |
| `pkg/.../interact.json` | the entries above: ids 100–103, each a masked field of the word at `0xF7000000`, and 104–105, signed sliders at `0xF7000004` and `0xF7000008`. Not the template's 70–75: 73–75 are the Sprint switches here. 16 entries and 3 data slots, Analogue's limits (16, and 20 together). |
| `pkg/.../core.json` | `"cartridge_adapter": 0` (powers the slot) |
| `sim/run_analogizer.sh` | the bench (below); its raster is set at the top of `sim/tb_analogizer.sv` |
| `tools/check_json.py` | fails if an entry writes outside its mask, none sets the enable, a position slider is not signed within ±127, a data slot also writes `0xF7000000`, or the slot is not powered; its size limit is this core's own released menu (11,568 bytes), and it does not count options across the file (below) |

### The settings word

One 32-bit word at `0xF7000000`, the layout RndMnkIII's adapter module (1.4)
decodes. Each menu entry is a list with a mask that keeps every bit but its
own field (or fields), so the four entries share the word:

| bits | field | values |
|---|---|---|
| 4:0 | SNAC type | 0 none, 1 DB15, 2 NES, 3 SNES, 4 PCE 2-button, 5 PCE 6-button, 6 PCE multitap, 9 DB15 fast, 0xB SNES A/B↔X/Y, 0xC–0xF PS/2 keyboard (+ pad; not in the menu, the wrapper does not wire the keyboard out), 0x10/0x11 PSX digital (125/250 kHz), 0x12/0x13 PSX analog. 16 and up select the adapter's B wiring. |
| 5 | enable | 0: the port stays idle and nothing else applies |
| 9:6 | SNAC assignment | 0–5 as in the table above |
| 13:10 | video | 0 RGBS, 1 RGsB, 2 YPbPr, (3 Y/C NTSC, 4 Y/C PAL: not offered), 5–9 scandoubler 0/25/50/75%/HQ2x |
| 14 | blank the Pocket screen | |
| 15 | OSD on the Analogizer output | not used; no menu entry |

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

The range is this board's blanking: dots 512–639 with hsync on 544–607
leave 32 dots on each side, and lines 384–415 with vsync on 392–395 leave 8
lines before it and 20 after. With no Y/C on offer there is no colour burst
to keep clear of the picture. The bench tries both ends of the range in
`interact.json` and fails if csync is low while a dot is drawn; one step
past either end of either slider (±33 dots, -21 or +9 lines) fails it.

**Menu size.** The menu is 8,091 bytes with 70 options: more than the 52
options and 7,597 bytes the template's `check_json.py` had seen load on an
installed core. This core's own 0.3.x menu was 11,568 bytes and loads (Paperboy
and 720 play on the Pocket with it), so that is the size limit here. Analogue's
interact.json documentation says a list holds up to 16 options of its own and
that they do not count toward the overall limit, so the per-list 16 is checked
and the total is not. More than 52 options is documented, not yet seen on a
core that loads.

### Clocks

`openFPGA_Pocket_Analogizer` runs its logic on `i_clk`, puts `video_clk` on the
cartridge pin that clocks the ADV7123, and assumes that is `i_clk` too. The
scandoubler halves the dot, so the clock has to be at least four times the
dot rate. This board's dot is 16 MHz, so 64 MHz is the least that works: the
PLL's spare output, its 768 MHz VCO divided by 12 (`clk_sys` is the same VCO
divided by 8), two cycles to `clk_sys`'s three. That is faster than the 42.95–48 MHz the shipped Analogizer
cores put through the cartridge's level translators; whether the translators
and the DAC take 64 MHz cleanly is a hardware question this core is the first
to ask. `pocket_analogizer` takes each pixel `PIX_LAG` (2) system clocks after
the dot enable (the video module's outputs are registered on that enable;
the debug overlay is not built) into a holding register and hands it over
with a toggle; the Analogizer side picks it up two or three of its clocks
later, inside the four-clock dot.

The Y/C encoder's subcarrier step and colour-burst window are computed in
integers from `CLK_HZ`, though Y/C is not offered here.

### Using SNAC in the game's inputs

`pocket_analogizer` outputs `key1..key4`, the Pocket's controller words with
SNAC pads put in place by the assignment. SNAC's bit order is the Pocket's
(0 up, 1 down, 2 left, 3 right, 4 A, 5 B, 6 X, 7 Y, 8 L1, 9 R1, … 14 select,
15 start). They feed the `gamepad` helper, and player 3's wheel, which reads
its word directly, in place of `cont1..4_key`. The analog sticks (`cont*_joy`)
are the Pocket's either way.

### What was measured

- `sim/run_analogizer.sh`: the wrapper and the vendored module at this board's
  raster (640 × 416, one dot per 6 clocks of 96 MHz) and the 64 MHz Analogizer
  clock (4 clocks a dot), read at the cartridge pins as the DAC reads them.
  - With the menu at its defaults, every pin sits as on a core without the
    adapter, and the controller words pass through.
  - Every option of the four Analogizer list entries in the package's
    `interact.json` (30), set as the firmware sets a masked entry -- read
    back the word as the bridge samples it, merged and written: the word, the
    adapter's copy and the enable each followed.
  - RGBS: all 196,608 visible dots of a frame reach the DAC pins, in raster
    order, as their top six bits per channel, with 0 differing. Csync is one
    64-dot pulse a line.
  - Scandoubler: 832 lines per frame (twice 416) at 1280 clocks, half the
    board's line, frame period unchanged.
  - Position at +32,+8 and -32,-20: csync moves by exactly 128 clocks (32
    dots) and by 8 and 20 lines; every dot still there with 0 differing;
    csync never low while a dot is drawn; the scandoubler unchanged; back at
    0, csync where it started. Jumps written just after a pulse that would
    put the next right after it (V +8 to +3, H +32 to -32) leave csync out
    of the picture over three frames. One step wider fails.
  - YPbPr and Y/C NTSC/PAL: no unknown on any pin for a frame.
  - All six SNAC assignments, the analog stick, and type "none" map as
    tabled; the blank bit, and enable off again returning the port to idle.
- `sim/run_video.sh` (the frozen-state video gate, five states): 0 differing
  pixels, as before -- nothing under `rtl/` changed.
- `sim/lint.sh`: clean, the wrapper included (under this file's `-Wall`, its
  by-design unused bits are waived for it; the vendored files' warnings are
  dropped by path, their errors are not).
- Quartus 18.1: compiles, every `ssprint_pocket.sdc` constraint applied (the
  three ignored are the platform's own `sys_constr.sdc` output delays), no
  negative slack at any corner. Before → after: 8,817 → 10,404 ALMs (48% →
  56%), 156 → 182 RAM blocks of 308 (the scandoubler's and HQ2x's 640-dot
  line buffers), 52 → 54 DSP blocks of 66; worst setup +0.613 → +0.984 ns
  (slow 0C, `clk_sys`); worst hold +0.068 → +0.087 ns (fast 0C, inside
  jt51). SDRAM capture (`dram_dq` → `dq_in`) holds +0.11 ns at fast 0C, so
  the SDRAM clock phase is unchanged. The 64 MHz domain's worst setup is
  +1.221 ns (slow 85C), its worst hold +0.124 ns (fast 0C).

**Not proven:** anything on hardware with this core; that the cartridge's
level translators and the DAC take the 64 MHz clock (the shipped cores use
48 MHz or less); that the firmware writes a signed slider value as a
two's-complement word; any monitor's response to the 25 kHz and 50 kHz
signals; and the SNAC serial protocols, which are the adapter module's and
are forced at its outputs in the bench rather than driven over the pins. The
YPbPr encoding has no reference to compare against, only a run without
unknowns.

### Trying it on hardware

This repository has no bring-up log of its own; the order, for the first
person with an adapter and a monitor that takes 25 or 50 kHz, each step's
reading telling the next where to look:

1. **"Analogizer: Off"** (the default). The games must play exactly as
   0.3.4 did, Pocket screen and controls. If not, the cart port is not idle:
   stop there.
2. **Analogizer On, Video Scandoubler, SNAC Adapter None**, on a multisync
   PC CRT: the same picture as the Pocket, the monitor reporting about
   50 kHz / 60 Hz. Nothing at all: say whether the monitor reports a signal
   (sync but no colour points at the 64 MHz DAC clock; nothing points at
   sync).
3. **RGBS** on a 25 kHz monitor, then RGsB and YPbPr where there is one
   (SOG switch on).
4. **SNAC**: one pad, assignment "SNAC P1 -> P1"; the Pocket's own controls
   are then player 2.
5. **The menu's memory**: change Video, quit the core and load it again;
   the setting, and Analogizer On, should still be there. Then change one
   entry and check the others did not move.
6. **Position**: + on "V Position" moves the picture down by that many
   lines, + on "H Position" right, and both are kept across a reload. A
   slider showing a value other than the one set means the firmware is not
   reading 0xF7000004/8 back as written. Try a negative value early: no
   installed core has shown that the firmware writes one as this core reads
   it.

### Turning it off

Set `USE_ANALOGIZER = 0` in `core_top.sv`, take `general[4]` out of the PLL
group in the SDC (it would match nothing), and take the six menu entries and
`cartridge_adapter: 0` out of the JSON.

**The menu's size, measured on hardware (2026-10-09).** The first build of
this menu had over 68 options in all and the Pocket refused it ("Error in
interact" at core setup); MSX2 loads with 68, Cadash and Cloak with 54.
Analogue's docs say a list's options count toward no limit; this firmware
disagrees. The Analogizer's lists were trimmed to keep the whole menu at 64
(SNAC types a one- or two-player game has no use for, and the rarer
Pocket-off variants); `tools/check_json.py` now refuses more than 68
options, or more than 80 options and entries together.
