-- Sound-side log for the sound board bench (sim/run_sound.sh): with the
-- machine time in microseconds, every T11 command byte (1680), sound reset
-- write (15a0), 6502 command read (1860), response write (1874), YM2151
-- write (1850/1851), POKEY write (1800-180f, 1830-183f), mixer (187a), sound
-- enable (187e) and IRQ ack (1878). Run with -wavwrite for the audio.
--   OUT=file FRAMES=n COIN=frame STARTBTN=frame PEDAL=n (written with set_value: clamped to 0..0x3f, no inversion, so 63, 192 and 255 all feed 0x3f -- a floored pedal to the Sprints; docs/hardware.md 7.6) WHEEL=n START_FIELD=name (the start button, "1 Player Start"; APB has none: its buttons are "P1 Button 2" / "P1 Button 3")
local m = manager.machine
local main = m.devices[":maincpu"].spaces["program"]
local snd = m.devices[":audiocpu"].spaces["program"]
local out = io.open(os.getenv("OUT") or "artifacts/traces/sound.txt", "w")
local frames, nframes = 0, tonumber(os.getenv("FRAMES") or "600")
local ports = m.ioport.ports
local coin_f, start_f = tonumber(os.getenv("COIN") or "-1"), tonumber(os.getenv("STARTBTN") or "-1")
local pedal, wheel = tonumber(os.getenv("PEDAL") or "-1"), tonumber(os.getenv("WHEEL") or "-1")
local function us() return string.format("%.3f", m.time:as_double() * 1e6) end
taps = {}
local function wtap(space, lo, hi, name, tag)
  -- the mask (byte lanes) is logged too: the T11's byte write to the odd
  -- byte of a register does not reach the 8-bit latch on the even byte
  taps[#taps+1] = space:install_write_tap(lo, hi, name, function(offset, data, mask)
    out:write(string.format("%s %s %04x %02x %04x\n", us(), tag, offset, data & 0xff, mask)) end)
end
local function rtap(space, lo, hi, name, tag)
  taps[#taps+1] = space:install_read_tap(lo, hi, name, function(offset, data, mask)
    out:write(string.format("%s %s %04x %02x\n", us(), tag, offset, data & 0xff)) end)
end
wtap(main, 0x1680, 0x1681, "cmd",  "CMD")     -- T11 -> sound command (word write, byte in D7:0)
wtap(main, 0x15a0, 0x15a1, "srst", "SRST")    -- T11 sound reset
rtap(main, 0x1c00, 0x1c01, "resp", "RRD")     -- T11 reads the response
rtap(snd, 0x1860, 0x1860, "crd",  "CRD")      -- 6502 reads the command
wtap(snd, 0x1874, 0x1874, "resp", "RESP")     -- 6502 writes the response
wtap(snd, 0x1850, 0x1851, "ym",   "YM")
wtap(snd, 0x1800, 0x180f, "pk1",  "PK1")
wtap(snd, 0x1830, 0x183f, "pk2",  "PK2")
wtap(snd, 0x187a, 0x187a, "mix",  "MIX")
wtap(snd, 0x187e, 0x187e, "sen",  "SEN")
wtap(snd, 0x187c, 0x187c, "sw",   "SW")
wtap(snd, 0x1878, 0x1878, "ack",  "ACK")
wtap(snd, 0x1870, 0x1870, "tms",  "TMS")      -- TMS5220 data latch (games with speech)
wtap(snd, 0x1872, 0x1873, "tmss", "TMSS")     -- TMS5220 /WS: 1872 high, 1873 low (MAME tms5220_strobe_w)
-- IN1_FROM=frame IN1_TO=frame: also log the 6502's IN1 reads (1840: bit 2
-- is the TMS5220's /READY) between those frames, to see the chip's handshake
local in1_from, in1_to = tonumber(os.getenv("IN1_FROM") or "-1"), tonumber(os.getenv("IN1_TO") or "-1")
if in1_from >= 0 then
  taps[#taps+1] = snd:install_read_tap(0x1840, 0x1840, "in1", function(offset, data, mask)
    if frames >= in1_from and frames < in1_to then out:write(string.format("%s IN1 %04x %02x\n", us(), offset, data & 0xff)) end end)
end
emu.register_frame_done(function()
  frames = frames + 1
  out:write(string.format("%s FRAME %d\n", us(), frames))
  for k = 0, tonumber(os.getenv("COINS") or "1") - 1 do   -- COINS=n: n coins, 20 frames apart
    if frames == coin_f + 20 * k then ports[":IN1"].fields["Coin 1"]:set_value(1) end
    if frames == coin_f + 20 * k + 10 then ports[":IN1"].fields["Coin 1"]:clear_value() end
  end
  for k = 0, tonumber(os.getenv("STARTS") or "1") - 1 do   -- STARTS=n: n presses, 60 frames apart (APB: siren for start, then day select)
    if frames == start_f + 60 * k then ports[":IN0"].fields[os.getenv("START_FIELD") or "1 Player Start"]:set_value(1) end
    if frames == start_f + 60 * k + 10 then ports[":IN0"].fields[os.getenv("START_FIELD") or "1 Player Start"]:clear_value() end
  end
  if pedal >= 0 and frames == start_f + 60 then for _, p in ipairs({":ADC0", ":ADC1", ":ADC2"}) do if ports[p] then for _, fl in pairs(ports[p].fields) do fl:set_value(pedal) end end end end
  if wheel >= 0 and frames == start_f + 60 then for _, fl in pairs(ports[":LETA0"].fields) do fl:set_value(wheel) end end
  if frames >= nframes then out:close(); m:exit() end
end)
