# ==============================================================================
# Quartus Prime Synopsys Design Constraint File
# ==============================================================================
# Super Sprint core constraints.
#
# The Pocket BSP (platform/pocket/bsp/pocket/sys_constr.sdc) creates the APF
# clocks; this file describes what is specific to this core.
# ==============================================================================

# ==============================================================================
# Clock groups
#
# core_pll general[0] = clk_sys       96.0 MHz  machine, renderer, SDRAM
#          general[1] = clk_vid       16.0 MHz  dot clock, exactly clk_sys / 6
#          general[2] = clk_vid 90deg 16.0 MHz
#          general[3]                 96.0 MHz  SDRAM pin clock, phase shifted
#          general[4] = clk_ana       48.0 MHz  the Analogizer's (pocket_analogizer.sv):
#                                               clk_sys / 2, in phase, five clocks to
#                                               the 9.6 MHz dot of the 15 kHz picture
#                                               ana_15k.sv makes.  In this group:
#                                               the pixel hand-over into it is a held
#                                               register under a toggle, timed as the
#                                               related-clock path it is.  With
#                                               USE_ANALOGIZER = 0 it drives nothing and
#                                               its name here matches nothing.
#
# clk_sys and the two pixel clocks stay in ONE group on purpose. The renderer
# emits a pixel every sixth clk_sys cycle and the APF scaler samples it on
# clk_vid; they are integer-related outputs of the same PLL, so that crossing is
# synchronous by construction and should be verified rather than cut. Cutting it
# would let each build route it blind and make the picture depend on the fitter
# seed.
#
# clk_74a, clk_74b, the bridge SPI clock and the audio PLL are genuinely
# asynchronous to the machine. The one multi-bit bus that crosses into clk_74b
# -- the audio sample -- is handed over with a toggle flag in core_top, so the
# capture is always of a value that has been still for several cycles
# (METHODOLOGY 5.4).
# ==============================================================================
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|core_pll|core_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|core_pll|core_pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|pocket_audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|pocket_audio_mixer|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

# ==============================================================================
# SDRAM
#
# The chip is clocked from core_pll general[3]: the same 96 MHz as the
# controller, phase-shifted. The phase and the exception below are DERIVED from
# the analyser's own numbers on a real fit, not assumed:
#
#   clock network, PLL output -> dram_clk pin          12.56 ns
#   clock network, PLL output -> dq_in register clock   7.9 ns
#   dram_dq pin -> dq_in register                        2.84 ns
#   chip access time tAC (max) + board                   7.0 ns
#   chip output hold tOH (min)                           2.5 ns
#
# The pin edge therefore trails the same nominal PLL edge by 4.66 ns more than
# the register's clock does. With phase 3650 ps the chip's edge at its pin
# lands about 1.2 ns BEFORE the controller's internal edge, which puts every
# transfer near the middle of its window:
#
#   command launched on our edge E: at the pin E+3, sampled by the chip at its
#     edge E+8.3 -- 5.3 ns setup; the previous chip edge was E-2.1 and the old
#     command holds until E+3 -- 5.1 ns hold.
#   read data: the chip drives it 7.0 ns after its edge, it reaches dq_in 9.84
#     after, i.e. 7.7 ns after our edge -- captured on our NEXT edge with 2.7 ns
#     to spare; the following word cannot arrive before 13.3 -- 2.9 ns hold.
#
# That capture is one full internal period after the chip's edge, but the
# nominal relationship between the two clocks is only 6.76 ns, because the
# extra 4.66 ns of network delay to the pin is not part of the waveform. So the
# analyser's default pairing checks a capture edge the data cannot possibly
# meet, and a multicycle of 2 (hold 1) moves it to the edge the RTL actually
# uses -- READ+4 at the pins, rd_late=1 in sdram16. This is the exception the
# first build lacked a basis for: it had the same numbers on a clock inverted
# by hand, and there the second edge was still 5.2 ns short.
#
# The original controller clocked the chip on an inverted copy of our clock and
# captured on the first edge, leaving 5.2 ns for a 7 ns access. With the
# exception that hid it removed, every dram_dq input missed by 7.5 ns, and on
# the Pocket every sprite was garbage while the block-RAM backgrounds were
# perfect.
#
# The clock is named dram_clk because the BSP (sys_constr.sdc) applies the
# chip's tDS/tDH to a clock of that name -- though it runs before this file and
# never finds it, so those two lines are repeated below.
# ==============================================================================
create_generated_clock -name dram_clk -source \
    [get_pins {ic|core_pll|core_pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    [get_ports {dram_clk}]

set_input_delay -max -clock dram_clk 7.0 [get_ports {dram_dq[*]}]
set_input_delay -min -clock dram_clk 2.5 [get_ports {dram_dq[*]}]

# The BSP's sys_constr.sdc carries these same two lines, but it is read before
# this file -- it has to be, it creates the PLL clocks -- so dram_clk does not
# exist yet when it runs and they are silently ignored. Repeated here, after
# the clock is created. tDS 1.5 ns, tDH 0.8 ns from the datasheet.
set SDRAM_OUT [get_ports {dram_a[*] dram_ba[*] dram_cke dram_dqm[*] dram_dq[*] dram_ras_n dram_cas_n dram_we_n}]
set_output_delay -max -clock dram_clk  1.5 $SDRAM_OUT
set_output_delay -min -clock dram_clk -0.8 $SDRAM_OUT

# Read capture is on the second internal edge after the chip's -- see above.
#
# Setup only. The usual "-hold N-1" that accompanies a -setup N is for a path
# whose source launches once per N cycles; the chip launches a new word on
# EVERY edge, and the hazard is the next word arriving before this capture.
# That is the analyser's default hold edge for a -setup 2 path, one period
# before the setup edge. A -hold 1 moved the check back to the edge coincident
# with the launch, which cannot fail, and reported +11 ns where the real margin
# is about +3.
set_multicycle_path -setup 2 -from [get_clocks {dram_clk}] -to [get_registers {*|sdram_ctrl:*|dq_in[*]}]

# --- controller round-robin arbiter ------------------------------------------
# A client's `req` is a genuinely single-cycle input -- it can rise on the clock
# before the controller happens to be sitting in S_IDLE -- so req -> SDRAM_A can
# never be multicycled. It measured 15.3 ns (rom_req, the last failing path
# outside the CPU cores) and was fixed in the RTL instead: the S_ARB state now
# splits the accept from the address drive, leaving req -> pick -> cur (~5.5 ns)
# and c_addr -> mux -> SDRAM_A (~9 ns) as two honest single-cycle paths.
#
# `last` is different. It is the index of the client served last and is written
# only when S_IDLE accepts a client. Everything it feeds -- the round-robin
# scan, hence pick -> cur, any_req -> state, and the burst branch's
# (b_yield && any_req) gate -- is read only in S_IDLE, and after an acceptance
# the controller cannot be back in S_IDLE for 7 clocks (ARB, OPEN1, OPEN2,
# WAIT3..WAIT1 on a write; 9 on a read). 3/2 is well inside that.
set_multicycle_path -setup 3 -from [get_registers {*|sdram_ctrl:*|last[*]}] -to [get_registers {*|sdram_ctrl:*|*}]
set_multicycle_path -hold  2 -from [get_registers {*|sdram_ctrl:*|last[*]}] -to [get_registers {*|sdram_ctrl:*|*}]

# ==============================================================================
# CPU cores that step on clock enables.
#
# T65 runs on the 1.79 MHz 6502 enable (53 clocks): 8 as in the Punch-Out!! and
# S.T.U.N. Runner cores. The T11 (rtl/t11/t11.sv) is a per-clock FSM whose bus
# accesses complete on any clock, so nothing in it is multicycled; the same
# for the video engines and the POKEYs.
# ==============================================================================
set_multicycle_path -setup 8 -from [get_registers {*|T65:*|*}] -to [get_registers {*|T65:*|*}]
set_multicycle_path -hold  7 -from [get_registers {*|T65:*|*}] -to [get_registers {*|T65:*|*}]

# ==============================================================================
# jt51 (YM2151). Every state register advances on cen (cen_ym, 3.58 MHz = one
# pulse per ~26.8 clocks) or cen_p1 (half that): jt51_reg_ch, jt51_reg and
# jt51_pg are all `always @(posedge clk) if(cen)` blocks (checked in the
# sources for the failing kf -> keycode_II cone, 14.7 ns in the first fit).
# The only per-clock writes are the MMR / CSR register-file commits, driven
# exclusively by ym_wr_p/ym_a0_p/ym_d_p, which ssprint_sound registers ONLY on
# cen_cpu -- so even those change solely in the clock after a cen boundary,
# >=26 clocks before the next cen-gated capture. Every jt51-internal path
# therefore has a full cen period; 8 is a third of the provable margin (the
# same argument and the same figure as the S.T.U.N. Runner core's).
# ==============================================================================
set_multicycle_path -setup 8 -from [get_registers {*|jt51:*|*}] -to [get_registers {*|jt51:*|*}]
set_multicycle_path -hold  7 -from [get_registers {*|jt51:*|*}] -to [get_registers {*|jt51:*|*}]

# The two POKEYs (rtl/pokey.sv) step on the same 1.79 MHz enable as the
# 6502 (cen_cpu, one pulse per 53-54 clocks), and their register writes are
# gated on it too (`we` is cen_cpu & wr & select in ssprint_sound), so every
# register in the block -- the AUDF/AUDC/AUDCTL/SKCTL registers, the four
# counters, the polynomial counters, the prescalers and the summed output --
# changes only in a cen_cpu clock and is captured only in the next one, 53
# clocks later. The whole MAME step_one_clock (four counters, four LFSRs,
# the filters and the 6-bit sum) is one combinational chain inside that
# window; it measured 14.7 ns (counter -> sum, -4.30 ns at 96 MHz), so 8/7
# as for the T65 is conservative. The read mux (rdata, combinational) and
# the reset are cross-block and stay single-cycle.
set_multicycle_path -setup 8 -from [get_registers {*|pokey:*|*}] -to [get_registers {*|pokey:*|*}]
set_multicycle_path -hold  7 -from [get_registers {*|pokey:*|*}] -to [get_registers {*|pokey:*|*}]
# ... and from the 6502 into the POKEYs: their we / addr / wdata are the T65's
# registers (address, data out, R/W) through the board decode, and every T65
# register changes only in a cen_cpu clock, the same enable the POKEY captures
# on -- so the write decode that gates the step (a STIMER or SKCTL write in
# the cen clock takes precedence over the step) has the same 53-clock window.
# It measured 10.9 ns (T65 address -> we -> step -> borrow, -0.55 ns). The
# jt51 is NOT covered by anything like this: its write interface samples
# cs_n / wr_n on every clock, so T65 -> jt51 stays single-cycle (and passes).
# The TMS5220 (modules/sound-tms5220, GHDL-converted VHDL): all 19 of its
# clocked processes are gated by I_ENA, the 625 / 833 kHz chip clock enable
# (one pulse per 115-154 clocks), so its internal paths get the same 8/7. Its
# inputs are the sound board's data / strobe latches (6502-cycle registers)
# and stay single-cycle.
set_multicycle_path -setup 8 -from [get_registers {*|TMS5220:*|*}] -to [get_registers {*|TMS5220:*|*}]
set_multicycle_path -hold  7 -from [get_registers {*|TMS5220:*|*}] -to [get_registers {*|TMS5220:*|*}]
set_multicycle_path -setup 8 -from [get_registers {*|T65:*|*}] -to [get_registers {*|pokey:*|*}]
set_multicycle_path -hold  7 -from [get_registers {*|T65:*|*}] -to [get_registers {*|pokey:*|*}]
