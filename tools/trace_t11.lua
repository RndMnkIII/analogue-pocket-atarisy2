-- MAME debugger trace of the T11 for the RTL CPU bench (sim/run_t11.sh):
-- registers and PSW before every instruction plus the CPU's total cycle
-- count (CYC), so the bench compares the cycle cost of every instruction.
-- Run with:  mame ssprint -debug -debugger none -autoboot_script tools/trace_t11.lua
--   OUT=file       trace file (default artifacts/traces/t11.txt)
--   START=frame    frame to start tracing at (0 = from reset, default)
--   FRAMES=n       number of frames to trace (default 3)
-- Each line: "R0=.. R1=.. R2=.. R3=.. R4=.. R5=.. SP=.. PSW=.. PC: disassembly",
-- the register values being those BEFORE the instruction at PC executes.
local m = manager.machine
local dbg = m.debugger
local sp = m.devices[":maincpu"].spaces["program"]
-- every T11 read of the I/O page 1400-1fff, in execution order, for the
-- bench to replay (addr value); and every access the slapstic sees in its
-- 8000-81ff range, to compare bank decisions. Taps must be global (Lua
-- collects locals after their first event).
local iolog = io.open((os.getenv("OUT") or "artifacts/traces/t11.txt"):gsub("%.txt$", "") .. "_io.txt", "w")
local slog  = io.open((os.getenv("OUT") or "artifacts/traces/t11.txt"):gsub("%.txt$", "") .. "_slap.txt", "w")
local alog  = io.open((os.getenv("OUT") or "artifacts/traces/t11.txt"):gsub("%.txt$", "") .. "_adc.txt", "w")   -- ADC start strobes: offset pc
local tracing = false
local cpu = m.devices[":maincpu"]
-- start-of-window state for the bench: work RAM, palette, the video RAMs,
-- the two ROM bank numbers (inferred from the mapped contents) and the
-- slapstic's current video bank (inferred the same way)
local function dump_state(path)
  local f = io.open(path, "w")
  local function share(tag, name, n)
    local sh = m.memory.shares[tag]; f:write(name .. "\n")
    for i = 0, n - 1 do f:write(string.format("%04x\n", sh:read_u16(i * 2))) end
  end
  f:write("RAM\n"); for i = 0, 2047 do f:write(string.format("%04x\n", sp:read_u16(i * 2))) end
  share(":palette", "PALETTE", 256); share(":alpha", "ALPHA", 3072); share(":mob", "MOB", 1024)
  share(":playfieldt", "PFT", 4096); share(":playfieldb", "PFB", 4096)
  local reg = m.memory.regions[":maincpu"]
  local function findbank(base)
    for b = 0, 63 do
      local ok = true
      for i = 0, 63 do if sp:read_u16(base + i * 2) ~= reg:read_u16(0x10000 + b * 0x2000 + i * 2) then ok = false; break end end
      if ok then return b end
    end
    return -1
  end
  local b1, b2 = findbank(0x4000), findbank(0x6000)
  f:write(string.format("BANK %02x %02x\n", b1, b2))
  local v0 = sp:read_u16(0x2000); local slap = 1
  local a0, t0, b0 = m.memory.shares[":alpha"]:read_u16(0), m.memory.shares[":playfieldt"]:read_u16(0), m.memory.shares[":playfieldb"]:read_u16(0)
  local v2 = sp:read_u16(0x3800); local mo0 = m.memory.shares[":mob"]:read_u16(0)
  if v0 == a0 and v2 == mo0 then slap = 0 elseif v0 == t0 then slap = 2 elseif v0 == b0 then slap = 3 end
  f:write(string.format("SLAP %d\n", slap))
  -- the CPU registers at this instant: the window's trace may begin with an
  -- interrupt entry (frame_done sits right before the line-0 interrupt), in
  -- which case the first trace line is the handler and these are the state
  -- before the push
  f:write(string.format("REGS %04x %04x %04x %04x %04x %04x %04x %04x %02x\n",
    cpu.state["R0"].value, cpu.state["R1"].value, cpu.state["R2"].value, cpu.state["R3"].value,
    cpu.state["R4"].value, cpu.state["R5"].value, cpu.state["SP"].value, cpu.state["PC"].value, cpu.state["PSW"].value))
  f:close()
  print(string.format("state: banks %d %d slapstic bank %d", b1, b2, slap))
end
taps = {}
taps.io = sp:install_read_tap(0x1400, 0x1fff, "io", function(offset, data, mask)
  if tracing then iolog:write(string.format("%04x %04x %04x\n", offset, data, cpu.state["PC"].value)) end
end)
taps.sr = sp:install_read_tap(0x8000, 0x81ff, "slr", function(offset, data, mask)
  if tracing then slog:write(string.format("r %04x %04x\n", offset, cpu.state["PC"].value)) end
end)
taps.adc = sp:install_write_tap(0x1480, 0x14ff, "adcs", function(offset, data, mask)
  if tracing then alog:write(string.format("%04x %04x\n", offset, cpu.state["PC"].value)) end
end)
taps.sw = sp:install_write_tap(0x8000, 0x81ff, "slw", function(offset, data, mask)
  if tracing then slog:write(string.format("w %04x %04x\n", offset, cpu.state["PC"].value)) end
end)
local out = os.getenv("OUT") or "artifacts/traces/t11.txt"
local start_f = tonumber(os.getenv("START") or "0")
local nframes = tonumber(os.getenv("FRAMES") or "3")
local frames = 0
-- optional inputs so a window can cover gameplay: COIN=frame START=frame PEDAL=n (written with set_value: clamped to 0..0x3f, no inversion, so 63, 192 and 255 all feed 0x3f -- a floored pedal to the Sprints; docs/hardware.md 7.6) WHEEL=n
local ports = m.ioport.ports
local coin_f  = tonumber(os.getenv("COIN") or "-1")
local startb_f = tonumber(os.getenv("STARTBTN") or "-1")
local pedal   = tonumber(os.getenv("PEDAL") or "-1")
local wheel   = tonumber(os.getenv("WHEEL") or "-1")
local fmt = string.format("trace %s,:maincpu,noloop,{tracelog \"R0=%%04X R1=%%04X R2=%%04X R3=%%04X R4=%%04X R5=%%04X SP=%%04X PSW=%%02X CYC=%%d \",r0,r1,r2,r3,r4,r5,sp,psw,totalcycles}", out)
if start_f == 0 then dbg:command(fmt); tracing = true end
dbg:command("go")
emu.register_frame_done(function()
  frames = frames + 1
  for k = 0, tonumber(os.getenv("COINS") or "1") - 1 do   -- COINS=n: n coins, 20 frames apart (as trace_sound.lua / dumpstate.lua)
    if frames == coin_f + 20 * k then ports[":IN1"].fields["Coin 1"]:set_value(1) end
    if frames == coin_f + 20 * k + 10 then ports[":IN1"].fields["Coin 1"]:clear_value() end
  end
  for k = 0, tonumber(os.getenv("STARTS") or "1") - 1 do   -- STARTS=n: n presses, 60 frames apart
    if frames == startb_f + 60 * k then ports[":IN0"].fields[os.getenv("START_FIELD") or "1 Player Start"]:set_value(1) end
    if frames == startb_f + 60 * k + 10 then ports[":IN0"].fields[os.getenv("START_FIELD") or "1 Player Start"]:clear_value() end
  end
  if pedal >= 0 and frames == startb_f + 60 then for _, p in ipairs({":ADC0", ":ADC1", ":ADC2"}) do if ports[p] then for _, fl in pairs(ports[p].fields) do fl:set_value(pedal) end end end end
  if wheel >= 0 and frames == startb_f + 60 then for _, fl in pairs(ports[":LETA0"].fields) do fl:set_value(wheel) end end
  if frames == start_f and start_f > 0 then
    dump_state((os.getenv("OUT") or "artifacts/traces/t11.txt"):gsub("traces/", "states/"):gsub("%.txt$", "") .. ".txt")
    dbg:command(fmt); dbg:command("go"); tracing = true
  end
  if frames == start_f + nframes then dbg:command("trace off,:maincpu"); dbg:command("go"); tracing = false; iolog:close(); slog:close(); alog:close(); m:exit() end
end)
