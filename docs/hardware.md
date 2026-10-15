# Super Sprint arcade hardware

Everything the core needs to know about the machine, taken from MAME 0.288
(`src/mame/atari/atarisy2.cpp`, `atarisy2_v.cpp`, `atarimo.cpp`,
`slapstic.cpp`, `devices/cpu/t11/*`, `devices/sound/pokey.cpp`,
`devices/machine/adc0808.cpp`, `devices/machine/eeprompar.cpp`, all vendored
under `ref/mame/`) and from interrogating the running driver with Lua. Written
first, per METHODOLOGY section 3 phase 1, and updated whenever a measurement
contradicts it.

Target set: **`ssprint`** -- Super Sprint (rev 4), Atari Games, 1986, on the
**Atari System 2** board (the Paperboy / 720 / Championship Sprint / APB
hardware). Addresses in this document are hex; MAME's driver writes the T11
map in octal.

---

## 1. Chips and clocks

| Part | Role | Clock | Source |
|---|---|---|---|
| DEC **T-11** (DCT11) | main CPU, PDP-11 instruction set, 16-bit little-endian bus | **10.000 MHz** (20 MHz XTAL / 2) | `T11(config, m_maincpu, MASTER_CLOCK/2)` |
| MOS **6502** | sound CPU | **1.789772 MHz** (14.318181 / 8) | `M6502(config, m_audiocpu, SOUND_CLOCK/8)` |
| Yamaha **YM2151** + YM3012 | FM music, stereo | **3.579545 MHz** (14.318181 / 4) | |
| 2x Atari **POKEY** (C012294) | effects; the DIP switches are read through their ALLPOT inputs | **1.789772 MHz** | |
| TMS5220 | speech -- **not fitted** on Super Sprint (`config.device_remove("tms")`) | | |
| ADC0809 | 8-channel 8-bit ADC: the three accelerator pedals | 625 kHz (20 MHz / 32) | |
| **LETA** (137304) | four 8-bit quadrature counters: the three steering wheels | | read through the 6502 |
| 2804 | 512-byte parallel EEPROM (settings, high scores), on the 6502 bus | | |
| Slapstic **137412-108** | security chip; on System 2 it selects which video RAM bank the T11 sees | | `SLAPSTIC(config, m_slapstic, 108)` |
| Watchdog | 10 MHz / 16 / 16 / 16 / 256 = **9.54 Hz** -> 105 ms | | |

**Display**: 32 MHz / 2 = **16.000 MHz pixel clock**, 640 clocks per line, 416
lines per frame: **512 x 384 visible, 60.096 Hz**, progressive, not rotated
(`screen.set_raw(VIDEO_CLOCK/2, 640, 0, 512, 416, 0, 384)`). Line rate 25 kHz.
VBLANK is lines 384-415, HBLANK is clocks 512-639.

---

## 2. T11 memory map (`main_map`)

16-bit words, little-endian, 64 KB. Unmapped reads return 0xffff
(`map.unmap_value_high()`). "mirror" means the address bits that are ignored.

```
0000-0fff  work RAM 4 KB
1000-11ff  palette RAM, 256 words, mirror 0x200 (1200-13ff is the same RAM)
1400       R  ADC0809 data (byte, D7:0; D15:8 read 0xff)         mirror 0x7e
1400-1403  W  bank select: 1400 = bank 1 (T11 4000-5fff), 1402 = bank 2 (6000-7fff); mirror 0x7c
1480-148f  W  ADC0809 channel select + start: channel = (addr >> 1) & 7; mirror 0x70
1580       W  IRQ0 acknowledge (sound-command-read interrupt)        mirror 0x1e
15a0       W  sound reset: bit 0 = 1 holds the 6502 in reset          mirror 0x1e
15c0       W  IRQ2 acknowledge (32V scanline interrupt)                mirror 0x1e
15e0       W  IRQ3 acknowledge (VBLANK interrupt)                      mirror 0x1e
1600       W  interrupt enable (bits 3:0, see section 3)              mirror 0x7e
1680       W  sound command byte -> 6502 latch, raises the 6502 NMI    mirror 0x7e
1700       W  playfield X scroll / tile bank 1 (section 5.2)           mirror 0x7e
1780       W  playfield Y scroll / tile bank 2                         mirror 0x7e
1800       R  IN0 (section 4)                                          mirror 0x3fe
1800       W  watchdog kick                                            mirror 0x3fe
1c00       R  sound response byte (D7:0, D15:8 = 0xff); clears IRQ1    mirror 0x3fe
2000-3fff  video RAM window, bank chosen by the slapstic (section 6):
             bank 0: 2000-37ff alphanumerics (3072 words), 3800-3fff motion objects (1024 words)
             bank 1: nothing (reads 0xffff)
             bank 2: playfield rows 0-31   (4096 words)
             bank 3: playfield rows 32-63  (4096 words)
4000-5fff  program ROM bank 1 (8 KB, one of 64)
6000-7fff  program ROM bank 2 (8 KB, one of 64)
8000-ffff  program ROM, fixed (7l = even bytes, 7n = odd bytes)
```

**Byte lanes**: every 8-bit register in this map (ADC start, the four
interrupt acknowledges, sound reset, interrupt enable, sound command, the
watchdog) is a byte handler on the **even** byte; a write to the odd byte
alone reaches nothing. The game relies on it: a sound command is `MOVB
x,@#1680` followed by `CLRB @#1681`, and only the first byte is the
command. The scroll registers are 16-bit with byte-merging writes.

**Bank select** (`bankselect_w`): with `b = ((data >> 10) & 0x3f) ^ 3`, the
bank number is `{b5, b4, b1, b0, b3, b2}`; the bank's data is MAME region
offset `0x10000 + bank * 0x2000`. The region holds 64 KB pairs of 32 KB ROMs
copied twice (`init_ssprint`), and banks 16-31 (`0x30000-0x4ffff`) are empty
(read as 0x00, verified with Lua). `tools/mra_build.py` lays the image out
exactly like the region.

**Reset**: the T11's mode word is 0x36ff, so the initial PC is **0x8000**,
SP = 0x00fe, PSW = 0xe0 (priority 7). The boot code runs its RAM tests from
0xbb02 for the first five frames and reaches the main loop by frame 6 (MAME
smoke run).

---

## 3. T11 interrupts

The T11 has four coded interrupt inputs CP0-CP3. Their state is read as a
4-bit number `cp = {CP3, CP2, CP1, CP0}` and looked up in a fixed table:

| cp | priority | vector | | cp | priority | vector |
|---|---|---|---|---|---|---|
| 1 | 4 | 0x38 | | 8 | 6 | 0x4c |
| 2 | 4 | 0x34 | | 9 | 6 | 0x48 |
| 3 | 4 | 0x30 | | 10 | 6 | 0x44 |
| 4 | 5 | 0x5c | | 11 | 6 | 0x40 |
| 5 | 5 | 0x58 | | 12 | 7 | 0x6c |
| 6 | 5 | 0x54 | | 13 | 7 | 0x68 |
| 7 | 5 | 0x50 | | 14 | 7 | 0x64 |
| | | | | 15 | 7 | 0x60 |

The interrupt is taken between instructions when `priority > PSW[7:5]`. The
board has no vector callback, so these table vectors are used (nonvectored
mode). Taking one pushes PSW then PC and loads PC and PSW from the vector
(`take_interrupt`, 114 cycles in MAME). Vector reads are words at
`vector` and `vector + 2`.

The four lines are level signals held by the board's own flip-flops:

| line | meaning | set | cleared |
|---|---|---|---|
| CP0 | sound command read | 6502 reads 1860, if enable bit 0 | T11 writes 1580 |
| CP1 | sound response written | 6502 writes 1874, if enable bit 1 | T11 reads 1c00 |
| CP2 | 32V | at scanlines 0, 64, 128, ..., 384 (every 64 lines), if enable bit 2 | T11 writes 15c0 |
| CP3 | VBLANK | at the start of VBLANK (line 384), if enable bit 3 | T11 writes 15e0 |

"if enable bit n" means the flip-flop is clocked from the enable register at
the event: an interrupt disabled at the moment of its event is not remembered
(`m_scanline_int_state = BIT(m_interrupt_enable, 2)`).

Other traps (vectors): illegal instruction 0x08, BPT 0x0c, IOT 0x10, EMT
0x18, TRAP 0x1c, bus timeout 0x04 (for JSR/JMP with register mode, MAME's
`illegal4`). HALT pushes PSW/PC and restarts at initial PC + 4 = 0x8004.

---

## 4. Inputs

**IN0** (T11 1800, 16 bits; MAME idle value 0xffcf):

| bit | | |
|---|---|---|
| 15 | service / self-test switch | 1 = off |
| 14:8 | unused | 1 |
| 7 | player 1 start | active low |
| 6 | player 2 start | active low |
| 5 | P1TALK: sound command latch full (T11 wrote, 6502 has not read) | active high |
| 4 | P2TALK: sound response latch full (6502 wrote, T11 has not read) | active high |
| 3 | player 3 start | active low |
| 2 | unused | 1 |
| 1:0 | unused | 1 |

**IN1** (6502 1840; idle 0xf4):

| bit | | |
|---|---|---|
| 7 | coin 3 (right) | active low |
| 6 | coin 2 (centre) | active low |
| 5 | coin 1 (left) | active low |
| 4 | self-test (same switch as IN0 bit 15) | 1 = off |
| 3 | unused | 0 |
| 2 | TMS5220 ready: not fitted, reads 1 | |
| 1 | P2TALK (response latch full) | active high |
| 0 | P1TALK (command latch full) | active high |

**DSW0** (POKEY 1 ALLPOT, 6502 1808): coinage. **DSW1** (POKEY 2 ALLPOT,
6502 1838): difficulty etc. Both are read as the raw switch byte; MAME's
defaults are DSW0 = 0x00, DSW1 = 0xc0. Bits are "inverted" in the DIP
location sense only; the values below are what the 6502 reads.

| DSW0 | | DSW1 | |
|---|---|---|---|
| 1:0 coinage | 0 = 1C/1C, 1 = 2C/1C, 2 = 3C/1C, 3 = 4C/1C | 1:0 difficulty | 1 easy, 0 medium, 2 medium hard, 3 hard |
| 4:2 coin multiplier | 0..7 = x1..x8 | 3:2 obstacles | 1 easy, 0 medium, 2 medium hard, 3 hard |
| 7:5 bonus coins | 0 none, 4 "1 each 5", 2 "1 each 4", 5 "1 each 3", 3 "2 each 4", 1 "1 each 2", 6 "1 each ?", 7 free play | 5:4 wrenches | 1 = 2, 0 = 3, 2 = 4, 3 = 5 |
| | | 7:6 unused | 1 |

**Pedals** (ADC0809 channels 0, 1, 2 = players 1, 2, 3): released reads
**0xff**, fully pressed **0xc0**. MAME's field is `IPT_PEDAL`,
`PORT_MINMAX(0,0x3f) PORT_INVERT`: a key press ramps the raw value 0 -> 0x3f
and the port inverts it, 0xff -> 0xc0, so the game never sees less than
0xc0. (An earlier note here said 0x3f, measured with Lua's `set_value(63)`
-- which writes the port's final value with no inversion, so the traces
and benches that use `PEDAL=63` feed the game 0x3f. Super Sprint takes
that as pressed; APB, which reads the pedal as a throttle, takes anything
below 0xc0 as a hard brake and creeps on its own at 0xff, which is how the
Pocket showed the mistake. `PEDAL=192` does not give 0xc0: `set_value` clamps it to 0x3f (7.6) -- a floored pedal either way.) Channels 3-7 read 0xff. A conversion takes
`1 + 1 + 64` ADC clocks (~106 us at 625 kHz) after the start write; the T11
reads the result at 1400 later. MAME's ADC0808 loads its SAR with the
selected input one ADC clock after the start (`STATE_CONVERSION_READY`)
and again at the end, so a read during the conversion already returns the
new channel's sample; the core does the same (it first latched only at
the end, which returns the previous channel's sample -- for APB, whose
pedal is channel 1, that is channel 0's 0xff, "released"). APB's pedal:
channel 1 (`ADC1`), Super Sprint's three: channels 0, 1, 2.

**Steering wheels** (LETA channels 0, 1, 2 = players 1, 2, 3, 6502
1810-1812): free-running 8-bit position counters, one count per encoder step,
wrapping. In MAME, +180 counts moved the track-select pointer from 12
o'clock to about 8 o'clock (counter-clockwise), which the core first took
to mean that turning the wheel right decreases the count; on the Pocket
that steered the car the wrong way, so **turning right increases the
count** (`target/pocket/steer_wheel.sv`, verified with the D-pad) and the
pointer simply turns against the wheel. The analog stick's mapping was left
as first built (stick right counts down) behind a core-settings toggle,
"Analog Stick" (Reversed), until a dock pad has been tried. Channel 3 (1813)
reads 0xff. Bit 4 of the 6502's 187c
("LETA resolution") is ignored by MAME.

---

## 5. Video

### 5.1 Palette

256 entries of 16 bits, `RRRR GGGG BBBB IIII`. MO colours use entries 0-63
(4 palettes of 16), alphanumerics 64-95 (8 of 4), playfield 128-255 (8 of
16). Conversion (`RRRRGGGGBBBBIIII`), with the two tables below:

```
i = intensity[I]
r = (colour[R] * i) >> 4,  g = (colour[G] * i) >> 4,  b = (colour[B] * i) >> 4
intensity[16] = 0, 124, 132, 141, 152, 161, 169, 178, 193, 202, 210, 219, 230, 239, 247, 256
colour[16]    = 0, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 14, 15, 15
```

(intensity: ZB = 115, Z3 = 78, Z2 = 37, Z1 = 17, Z0 = 9, summed per set bit,
0 for I = 0.)

### 5.2 Playfield

128 x 64 tiles of 8 x 8, 4 bpp; rows 0-31 in bank 2 of the video window,
rows 32-63 in bank 3, one word per tile, row-major (`TILEMAP_SCAN_ROWS`).

| word bits | |
|---|---|
| 15:14 | priority category, **inverted**: `category = ~bits & 3` |
| 13:11 | colour (palette 128 + colour * 16) |
| 10 | selects tile bank register 0 (xscroll bits 3:0) or 1 (yscroll bits 3:0) |
| 9:0 | tile code low bits; `code = bank << 10 | bits 9:0` (14 bits) |

Tile graphics (`pflayout`): 16 bytes per tile in each half of the 512 KB
"tiles" region: planes 0 and 1 in the first half (`code * 16`), planes 2 and
3 in the second (`0x40000 + code * 16`). A tile row is 2 bytes per half,
byte k covering pixels 4k..4k+3; within a byte the **high nibble is the
lower-numbered plane and the low nibble the higher**, pixel 0 at the
nibble's MSB. MAME numbers plane 0 as the MOST significant pen bit
(`decode_tile`: `pen |= bit << (planes - 1 - plane)`), so

```
pen = {half0 byte bit 7-i, half0 byte bit 3-i, half1 byte bit 7-i, half1 byte bit 3-i}   (i = pixel & 3)
```

This cost an afternoon: with the planes the intuitive way round every
non-uniform tile rendered wrong while the flat backgrounds and the text
looked right (`tools/render_model.py` found it by searching the ROM for the
bitplane bytes MAME's frame implied).

**Scroll**: xscroll register bits 15:6 = X scroll (0-1023), bits 3:0 = tile
bank 0. yscroll bits 15:6 = Y scroll (0-511), bits 3:0 = tile bank 1, **bit 4
= 1: the new Y scroll takes effect at the top of the next frame; 0: takes
effect immediately, so that the current beam line shows playfield line
`yscroll`** (MAME `set_scrolly((newscroll >> 6) - vpos)`). Attract mode writes
it with bit 4 set, at a fixed line each frame.

### 5.3 Alphanumerics

64 x 48 tiles of 8 x 8, 2 bpp, bank 0 words 0x2000-0x37ff, row-major. Bits
9:0 = code (1024 chars, 16 bytes each in the 16 KB "chars" region), bits 15:13
= colour (palette 64 + colour * 4). Pen 0 transparent. Drawn last, over
everything. `anlayout`: a row is 2 bytes, byte k covering pixels 4k..4k+3; the high
nibble is plane 0 (pen bit 1), the low nibble plane 1 (pen bit 0), pixel 0
at the MSB.

### 5.4 Motion objects (`atarimo`, config `atarisy2`)

256 entries of 4 words at bank 0 0x3800-0x3fff, a **linked list** starting at
entry 0 and following each entry's link until an entry is revisited (MAME
keeps a `visited` set; at most 256 entries). Entries are drawn in list order
and later ones overwrite earlier ones (`m_reverse = 0`).

| word | bits | |
|---|---|---|
| 0 | 14:6 | Y position (9 bits) |
| 0 | 2:0 | tile code bits 13:11 |
| 1 | 15 | hold: X = previous object's X + 16 (this entry's own X is ignored) |
| 1 | 14 | horizontal flip |
| 1 | 13:11 | height in tiles minus 1 (1-8 tiles of 16 lines) |
| 1 | 10:0 | tile code bits 10:0 |
| 2 | 15:6 | X position (10 bits) |
| 3 | 15:14 | priority |
| 3 | 13:12 | colour (palette colour * 16) |
| 3 | 10:3 | link to the next entry |

Width is always one tile (16 px). Coordinates: `ypos = (-Y - height*16) & 511`,
`xpos = X & 1023`; if `xpos >= 512` then `xpos -= 1024`, if `ypos >= 384`
then `ypos -= 512` (so objects wrap in from the left/top). Tile `t` of the
object (0 = top) is drawn at `ypos + 16 t`, code `code + t`. With hflip the
tile's pixels are mirrored (single column, so nothing else changes). Pen 15 is
transparent. Tile graphics (`molayout`): 64 bytes per tile per half (half 1 at
`0x20000`), planes and nibbles exactly as for the playfield but 16 wide: a
row is 4 bytes, byte k covering pixels 4k..4k+3. The whole "sprites" region
is **inverted** (`ROMREGION_INVERT`: every byte XOR 0xff before decoding).

The MO layer is rendered into its own 16-bit buffer holding
`palette index | priority << 12` (0xffff = nothing).

### 5.5 Priority (`screen_update`)

```
for each pixel:
    pf   = playfield palette index (128 + colour*16 + pen), always opaque
    cat  = playfield tile category (0-3)
    if MO present:
        if ((mo_priority + cat) & 2):      # "high priority PF"
            if (pf & 8) == 0: pixel = mo   # PF pen < 8 loses to the MO
        else:
            pixel = mo
    if alpha pen != 0: pixel = alpha
```

`(mo_priority + cat) & 2` is a 2-bit add of the two 2-bit fields with bit 1
of the sum tested. The playfield is opaque (no transparent pen).

### 5.6 Video timing

Nothing in the frame is double-buffered: the CPU writes video RAM whenever it
likes, and MAME renders in bands (partial updates at every scroll write and
every 64 lines for the MOs). The reference renderer works from one frozen
state; states where that differs from MAME's frame are excluded from the gate
(docs/verification.md lists which).

---

## 6. Slapstic 137412-108 (video RAM bank select)

The chip sees **every T11 bus cycle** (instruction fetches included) with
address lines A1-A14 on its A0-A13, and its two bank-select outputs choose
the bank of the 2000-3fff video window. Its 512-byte "/CS" range is
**8000-81ff** of the T11 space (fixed program ROM). Bank at power-up: **3**.
The state machine, with `addr` the T11 byte address (bit 0 ignored), from
`ref/mame/slapstic.cpp` and the 108 table:

```
reset(addr):      addr & 0xfffe == 0x8000        (the range's first word)
bank(b):          addr & 0xfffe == 0x8050 | b<<2    b = 0..3  -> 0x8050 0x8054 0x8058 0x805c
alt1:             addr & 0x00fe == 0x003e        (anywhere in memory)
alt2:             addr & 0xfffe == 0xeee4
alt3:             addr & 0xfff8 == 0xeec8        bank = addr[2:1]
alt4:             addr & 0xfff2 == 0x8050
bit1:             addr & 0xffe0 == 0x80c0
bit2:             addr & 0xfff2 == 0x8050
bit3c0/s0/c1/s1:  addr & 0xffe6 == 0x80c0 / 0x80c2 / 0x80c4 / 0x80c6
bit4:             addr & 0xfff0 == 0x80e0

IDLE:        reset -> ACTIVE
ACTIVE:      bank(b) -> current = b, IDLE
             alt1 -> ALT_VALID
             bit1 -> BIT_LOAD
ALT_VALID:   reset -> ACTIVE; alt2 -> ALT_SELECT; anything else -> ACTIVE
ALT_SELECT:  reset -> ACTIVE; alt3 -> loaded = addr[2:1], ALT_COMMIT; else -> ACTIVE
ALT_COMMIT:  reset -> ACTIVE; alt4 -> current = loaded, IDLE
BIT_LOAD:    reset -> ACTIVE; bit2 -> loaded = current, BIT_SET_ODD
BIT_SET_ODD: reset -> ACTIVE; bit3c0 -> loaded &= ~1; s0 -> |= 1; c1 -> &= ~2; s1 -> |= 2 (each -> BIT_SET_EVEN)
             bit4 -> current = loaded, IDLE
BIT_SET_EVEN: as ODD with the roles swapped: c0 tests bit3s1, s0 tests bit3c1,
             c1 tests bit3s0, s1 tests bit3c0 (each -> BIT_SET_ODD); bit4 -> commit, IDLE
```

Tests are evaluated in the order listed within a state; the first match
wins. In practice the game reads 0x8000 then one of the four bank words to
switch views.

---

## 7. Sound board

### 7.1 6502 memory map (`sound_map`)

```
0000-0fff  RAM 4 KB                               mirror 0x2000
1000-11ff  2804 EEPROM (512 bytes)                mirror 0x2600
1800-180f  POKEY 1  (ALLPOT = DSW0)               mirror 0x2780
1810-1813  LETA counters 0-3 (read)               mirror 0x278c
1830-183f  POKEY 2  (ALLPOT = DSW1)               mirror 0x2780
1840       IN1 (read)                             mirror 0x278f
1850-1851  YM2151 (1850 address, 1851 data)       mirror 0x278e
1860       sound command byte from the T11 (read); sets IRQ0 to the T11 if enabled; clears the 6502 NMI
1870-1873  TMS5220 data / strobes: not fitted, writes ignored
1874       sound response byte to the T11 (write); sets IRQ1 to the T11 if enabled
1876       coin counters (bits 1:0)
1878       timed IRQ acknowledge (write)
187a       mixer: bits 2:0 YM2151 volume, 4:3 POKEY volume, 7:5 TMS volume
187c       bits 3:2 LEDs, bit 4 LETA resolution, bit 5 TMS clock
187e       bit 0: 0 = hold the YM2151 in reset; the 0->1 edge also writes mixer 0
4000-ffff  program ROM; Super Sprint fits 8000-ffff (two 16 KB), 4000-7fff reads 0x00
```

### 7.2 6502 interrupts

* **IRQ**: a timer at 10 MHz / 16 / 16 / 16 / 10 = **244.14 Hz** (4096 us)
  asserts the line; a write to 1878 clears it. (The YM2151's IRQ pin is not
  connected in MAME's configuration.) In MAME it is the 6502 device's
  periodic interrupt, which restarts whenever the device is reset: the first
  IRQ comes one period after the T11 releases the sound reset (15a0 bit 0
  1->0), and every later one at that phase. The core restarts its divider
  at the same edge (`irq_sync`); the phase matters because the 6502 lives
  in its IRQ handler, so every sound event is stamped by it (before this
  the benches ran 0.57 ms (Paperboy) and 1.8 ms (720) late, the difference
  between each game's reset time and the divider's free-running phase).
* **NMI**: the sound command latch: a T11 write to 1680 raises NMI (the
  6502 takes it on the edge); the 6502's read of 1860 empties the latch.
* **Reset**: T11 write to 15a0 bit 0. Held in reset at power-up until the
  T11 releases it (`machine_reset` -> `sound_reset_w(1)`). The T11's reset
  write also performs `sndrst_6502_w(0)` (YM2151 into reset), `coincount_w(0)`,
  `switch_6502_w(0)`.

### 7.3 EEPROM 2804 lock

MAME's `EEPROM_2804` is configured without `lock_after_write`, so on this
board the EEPROM is plain read/write memory on the 6502 bus (writes are
instantaneous). It holds the settings and high-score table; the Pocket keeps
it in a save file.

### 7.4 Mixing (MAME's routing)

```
ym_gain(v)   = 1                                    v = mixer bits 2:0 == 7
             = (1/rb) / (50 + 1/rb)                 rb = sum over clear bits of 1/100 (bit0), 1/47 (bit1), 1/22 (bit2)
pokey_gain(v)= 1                                    v = bits 4:3 == 3
             = (1/rb) / (50 + 1/rb)                 rb = sum over clear bits of 1/47 (bit3), 1/22 (bit4)
left  = 0.60 * ym_gain * YM_L + 1.35 * pokey_gain * POKEY1
right = 0.60 * ym_gain * YM_R + 1.35 * pokey_gain * POKEY2
```

so mixer value 0 gives YM gain 0.207 and POKEY gain 0.252; the gains rise as
bits are set. POKEY output (MAME `LEGACY_LINEAR`): sum of the four channels'
volume nibbles (0-60) times `32767/11/4` = 744.7, clipped at 32767 (so 44
volume units already saturate).

### 7.6 TMS5220 speech (Paperboy, 720, APB; not fitted on the Sprints)

MAME's `atarisy2` base config fits a TMS5220C at MASTER_CLOCK/4/4/2 =
625 kHz and Super Sprint / Championship Sprint remove it (`device_remove("tms")`).
The image header's flags bit 0 says whether the board has one; the core
instantiates it always (`modules/sound-tms5220`, d18c7db's VHDL from MAME's
`tms5220.cpp`, GHDL-converted) and mutes and ignores it when not fitted.

* **1870** write: the data latch (the chip's D0-7).
* **1872 / 1873** write: /WS. MAME's `tms5220_strobe_w` does
  `wsq_w(1 - (offset & 1))`: 1872 raises /WS, 1873 lowers it (the driver's
  memory-map comment says the opposite; the code is what MAME runs and what
  the core follows). /RS is tied high (`init_apb`: `rsq_w(1)`).
* **187a** bits 7:5: the chip's volume, 100k / 47k / 22k against 100k||100k,
  as the YM and POKEY gains (7.4); MAME routes it at 0.75 to both channels.
* **187c** bit 5: "frequency control", `divider = 16 - (12 | bit5)`, so the
  chip clock is 20 MHz / 4 / 4 / 2 = 625 kHz (bit clear) or 20 / 4 / 3 / 2
  = 833.3 kHz (bit set); the sample rate is the chip clock / 80.
* **IN1 bit 2** (1840): the chip's /READY (`readyq_r`, 1 = not ready; reads
  1 with no chip). It goes inactive at the /WS falling edge and returns 16 chip clocks
  later (25.6 us at 625 kHz), when the byte enters the FIFO -- or stays
  inactive while the FIFO is full -- or the command takes effect (MAME's
  ready timer; a RESET command included). Paperboy's 6502 leans on this: its
  sound IRQ handler makes three back-to-back write attempts of its idle
  0xff stream, each only if /READY is active, and the second always finds
  the chip busy; a model that let /READY return at once accepted one byte
  more per interrupt and fed the chip a third faster than MAME.
* **The pedals** (ADC 0-2; APB's on ADC 1): MAME's port is `PORT_MINMAX
  (0x00, 0x3f) PORT_INVERT` over mask 0xff, so the game reads **0xff with the
  pedal up and 0xc0 floored** (measured: the untouched port reads 0xff). A
  Lua `set_value(n)` is not a key press: it writes n clamped to 0..0x3f with
  **no** inversion, so `PEDAL=63`, `192` and `255` in a trace all feed 0x3f --
  and **the Sprints take 0x3f as a floored pedal** (measured: held at any of
  the three, Super Sprint's track-select screen starts the race by itself;
  untouched, it waits at "PRESS PEDAL TO START RACE"). 0.3.1 read those
  traces as "0x3f is the pedal up" and fed every game 0x3f up / 0x00 floored;
  on the Pocket that pinned the Sprints' gas (0.3.1-0.3.4). The core now feeds
  the Sprints 0xff up, 0xc0 floored, 0xe0 half (as 0.3.0, which was played
  and confirmed), and APB alone 0x3f up / 0x00 floored / 0x20 half. APB's
  pedal code (`053142` octal, `BISB @#012000`) keeps 255 - ADC and tracks the
  smallest and largest values seen since the game started; with 0xff the
  pedal is 0 and its `pedal - 1` wraps to 0xffff, which reads as "above the
  minimum", so the game writes full gas until the pedal has moved once -- the
  car drives itself and crashes (MAME's frame 1240 with an untouched port
  shows the demerit card at 48 MPH; with the port set to 0x3f it sits parked
  at 0 MPH). A press before the game starts does not count; the range is
  tracked per game.
* **sound reset** (T11 15a0) 0->1 edge: MAME calls `tms5220->reset()` in
  place of the stream of 0xff the board really feeds the chip; the core holds
  /WS and /RS low for 16 chip clocks, which the chip takes as a reset. A
  reset (this one, or the RESET command every idle 0xff becomes once the
  chip has halted) is MAME's device reset: it restarts the frame timing, so
  the time a stop frame takes to halt the chip after the next Speak External
  (one frame plus the remainder of the current one, 25-50 ms) is measured
  from the last reset, and the model restarts its timing generator the same
  way.
* output: MAME's `clip_analog`: the 14-bit lattice output clipped to
  +-2048, low 4 bits dropped, upshifted to 16 bits with range extension
  (`{c[11:4], c[10:4], c[10]}`), then the mixer gain.

The chip is only ever driven in "Speak External" mode on this board (the
6502 streams LPC frames through the FIFO); the vendored model implements
exactly that, plus NOP and RESET, and not the VSM ROM commands.

### 7.5 POKEY (audio subset used here)

The POKEYs are reset with the board, not by the T11's sound reset (15a0):
MAME's `sound_reset_w` resets the 6502, the YM2151 and the TMS5220 and
leaves the POKEYs running. Their polynomial counters restart when the 6502
writes SKCTL with bits 1:0 clear (the boot does) and run from its release.
720 reads RANDOM (180a) and sends two bytes to the T11 (command 0x18); the
core's bytes are the 17-bit polynomial at the read, but MAME's are not
reproducible: its POKEY is an executing device whose counters sit wherever
the scheduler's timeslice left them, and `pokey_device::read` only resyncs
the scheduler, so the value is stale by up to a slice.


Registers (offset & 15): 0/2/4/6 AUDF1-4, 1/3/5/7 AUDC1-4, 8 AUDCTL, 9
STIMER, 0xa SKREST, 0xb POTGO, 0xd SEROUT, 0xe IRQEN, 0xf SKCTL; reads: 8 =
ALLPOT (the DIP switches), 0xa = RANDOM, 0xe = IRQST, 0xf = SKSTAT. The chip
runs from the 1.789772 MHz clock:

* polynomial counters 4, 5, 9 and 17 bits advance every clock when SKCTL bits
  1:0 are non-zero (`SK_RESET`); with them zero everything is held.
* prescalers: `CLK_28` fires every 28 clocks (63.9 kHz), `CLK_114` every 114
  (15.7 kHz); the base clock is CLK_114 if AUDCTL bit 0 else CLK_28.
* channel counters count up from `AUDF ^ 0xff` (`reset_channel`) and borrow
  on wrapping to 0; a borrow takes 1 cycle at the base clock, 4 at 1.79 MHz
  (AUDCTL bits 6 / 5 = channel 1 / 3 at 1.79 MHz), 7 when joined 16-bit
  (AUDCTL bit 4 = 1+2, bit 3 = 3+4). Channel 1's borrow clocks channel 2 when
  joined, 3's clocks 4.
* on a borrow the channel reloads and its output is updated (`process_channel`):
  if AUDC bit 7 (no poly5) or poly5's current bit: pure tone (AUDC bit 5) toggles
  the output; poly4 (bit 6) copies poly4's bit; otherwise poly9 (AUDCTL bit 7)
  or poly17's bit.
* high-pass filters: AUDCTL bit 2 = channel 1 filtered by 3, bit 1 = channel 2
  by 4: on the filter channel's borrow, `filter_sample = output` of the filtered
  channel; the channel contributes `output ^ filter_sample`. Unfiltered
  channels have `filter_sample = 1`.
* output: each channel contributes its volume (AUDC bits 3:0) when
  `output ^ filter_sample` is 1 or AUDC bit 4 (volume-only) is set.
* IRQEN/IRQST and the serial port are unused by this game beyond reset writes.

---

## 8. Frame timeline (MAME, factory EEPROM, no inputs)

| frame | |
|---|---|
| 1-5 | T11 RAM / ROM tests at 0xbb02-0xbb2a; the 6502 is released in frame 1 |
| 6 | main program (0x8534) |
| 7 | first scroll register writes (xscroll 0000, yscroll 0011: tile banks 0/1, hold bit set) |
| ~33 | tile banks 4/5: title screen |
| 400 | high-score table (banks 12/13) |
| 700 | track 2 attract (banks 0/1) |
| 2500 | track 3 attract (banks 6/7) |

MAME's `frame_done` (where `tools/dumpstate.lua` samples) is at line 415,
the last line of vertical blank; the game writes the scroll/bank registers
at lines 388-391 (inside vblank), acknowledges the 32V interrupt at lines
1, 32, 96, ... and writes motion object RAM during the visible frame (lines
35-227 in gameplay), which is why some frozen states differ from MAME's
frame in the motion objects (docs/verification.md).

**Slapstic**: the game switches the video bank through the "direct" path
(a read of 0x8000 then of one of the four bank words); MAME's Lua taps see
the T11's instruction fetches, so the boot code running at 0x8000-0x81ff
also drives the chip's state machine, as it does in the RTL.

---

## 9. The ROM image (format 2)

One image per game, built from the MAME romset by `tools/mra_build.py` from
the game's `.mra` (`ssprint.mra`, `apb.mra`), and checked byte for byte
against MAME's loaded regions by `tools/check_rom.lua`. The core reads every
image the same way: a 512-byte header, then fixed slots sized for the largest
Atari System 2 game. Each slot holds the MAME memory region as loaded (gaps
read 0x00 in both), except that a graphics region smaller than its slot is
placed so its two bit-plane halves sit where the full-size region's would
(`RGN_FRAC(1,2)` of the slot), and the header says where the tile codes wrap.

| offset | size | contents |
|---|---|---|
| 0x000000 | 512 | header, below |
| 0x000200 | 32 KB | T11 fixed program 0x8000-0xffff (7l even byte, 7n odd) |
| 0x008200 | 512 KB | T11 banked program, MAME region 0x10000-0x8ffff: 64 banks of 8 KB |
| 0x088200 | 48 KB | 6502 program 0x4000-0xffff (Super Sprint's ROMs start at 0x8000; below is 0x00) |
| 0x094200 | 512 KB | playfield tiles, MAME "tiles" region, plane halves 0x40000 apart |
| 0x114200 | 1 MB | motion object tiles, MAME "sprites" region as dumped (the core inverts, ROMREGION_INVERT); plane halves 0x80000 apart |
| 0x214200 | 16 KB | alphanumerics, MAME "chars" region |
| 0x218200 | 512 | 2804 EEPROM factory contents (0xff when MAME has none: the game initialises it) |
| 0x218400 | | total: 2,196,480 bytes |

Header (little-endian bytes; `rtl/ssprint_pkg.sv`, latched by the loader in
`ssprint_core`):

| byte | field | Super Sprint | APB | Championship Sprint | Paperboy | 720 Degrees |
|---|---|---|---|---|---|---|
| 0-3 | magic `ASY2` | | | | | |
| 4 | format | 2 | 2 | 2 | 2 | 2 |
| 5 | game id | 1 | 2 | 3 | 4 | 5 |
| 6 | slapstic type | 108 | 110 | 109 | 105 | 107 |
| 7 | flags: bit 0 TMS5220 fitted, bit 1 vertical screen | 0x00 | 0x03 | 0x00 | 0x01 | 0x01 |
| 8 | playfield tile code bits (codes wrap at 2^n, MAME's element count) | 14 | 14 | 14 | 12 | 13 |
| 9 | motion object code bits | 11 | 13 | 11 | 11 | 13 |
| 16-47 | name, ASCII, zero padded | SUPER SPRINT | APB | CHAMPIONSHIP SPRINT | PAPERBOY | 720 DEGREES |

Paperboy's 128 KB tile region sits in the 512 KB slot with its plane halves
at 0 and 0x40000 (as the sprite slot's convention), and its 8 KB character
ROM is stored twice in the 16 KB slot so codes wrap at 512 as in MAME.
720's 256 KB tile region is placed the same way (128 KB halves at 0 and
0x40000); its 1 MB sprite region fills the slot, with each ROM's second
32 KB placed below its first, as MAME's `ROM_CONTINUE` loads it.

Sizes across the System 2 games (MAME): the T11 regions and the chars are
the same for all; the 6502 ROM is 32 KB (Super Sprint, Championship Sprint)
or 48 KB (Paperboy, 720, APB); tiles 512 KB; sprites from 256 KB (Super
Sprint) to 1 MB (APB). The image slots are those maxima.

