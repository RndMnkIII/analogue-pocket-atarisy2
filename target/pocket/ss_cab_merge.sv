//------------------------------------------------------------------------------
// The Pole Position cabinet adapter's controls, as Atari System 2 wants them.
//
// The adapter (hw/cabinet_adapter, RndMnkIII/PocketPolePositionII) sends a
// 40-bit frame over the Analogizer's SNAC port that pp_cab_io decodes into
//   lines   ST1 ST2 SFT COIN1 COIN2 START SERVICE TEST (bit 0..7, 0 = closed)
//   gas     the pedal as an ADC0804 reads it, 0x00 released .. 0x90 floored
//   ble     the brake: not used here
// This module turns those into what the Sprints, APB and the LETA / ADC0809
// of the System 2 board read (docs/hardware.md section 4):
//
//   wheel   the two quadrature phases become the LETA's free-running 8-bit
//           position.  The Pole Position encoder gives 24 x 30/7 = 102.9
//           cycles a turn of its wheel; one cycle is one count, counted on the
//           fall of ST2, up with ST1 low (the 53xx's own rule, vwheel.h).
//           Turning right counts up, as steer_wheel.sv (`rev` flips it).  `gain` scales it:
//           0 one count per cycle, 1 one per two cycles, 2 two per cycle.
//           WHEEL_Q8 is the counts per cycle in Q8 (256 = one): the Super Sprint's own
//           disc gives N cycles a turn, so WHEEL_Q8 = round(256 x 103 / N) makes it turn the
//           LETA as the Pole Position wheel does. The default is for N = 30 (the estimate
//           from the photo: count the teeth on the real disc); 256 is the 1:1 of before.
//   pedal   0..0x90 (the cabinet's travel) is 0..0x3f, 7/16 -- exactly the
//           Sprints' 0xff .. 0xc0 and APB's 0x3f .. 0x00 once subtracted.
//   coin 1, coin 2, start, test    closed (active high here)
//   hi_gear    the gear lever's HI position, which APB gets as its button 2
//
// `live` (the menu's Cabinet adapter and good frames arriving) says whether
// the cabinet is there; with it low the module outputs the idle state and
// core_top keeps the Pocket's own controls.
//------------------------------------------------------------------------------
`default_nettype none

module ss_cab_merge #(
    parameter WHEEL_Q8 = 879        // counts per cycle, Q8: 256 x 103 / N with N = 30 (see the header)
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        live,
    /* verilator lint_off UNUSEDSIGNAL */   // bit 6, SERVICE: a credit on Pole Position, nothing on a System 2
    input  wire  [7:0] cab_lines,    // 0 ST1, 1 ST2, 2 SFT, 3 COIN1, 4 COIN2, 5 START, 6 SERVICE, 7 TEST (0 = closed)
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire  [7:0] cab_gas,
    input  wire  [1:0] gain,         // steering: 0 x1, 1 x1/2, 2 x2 (3 = x1)
    input  wire        rev,          // reverse the wheel (the menu's Analog Stick: Reversed)

    output logic [7:0] wheel,        // LETA position, turning right counts up
    output wire  [7:0] pedal_sprint, // 0xff released .. 0xc0 floored
    output wire  [7:0] pedal_apb,    // 0x3f released .. 0x00 floored
    output wire        coin1, action, start, test, hi_gear   // action: the COIN2 line, the G25's red 3
);
    // ---- the wheel
    logic st2_q = 1'b1;
    wire up = !cab_lines[0] ^ rev;   // ST1 low when ST2 falls: counts up (rev: down)
    // counts per cycle in Q8: the ratio, halved for gain 1 and doubled for gain 2. The fraction left
    // over (0..255, in 1/256 of a count) is carried to the next cycle, signed by the direction, so a
    // turn back takes back what a half count gave.
    wire [15:0] fac = (gain == 2'd1) ? (WHEEL_Q8 >> 1) : (gain == 2'd2) ? (WHEEL_Q8 << 1) : WHEEL_Q8;
    logic [7:0] wfrac = '0;
    wire signed [16:0] wdlt = up ? $signed({1'b0, fac}) : -$signed({1'b0, fac});
    wire signed [16:0] wsum = $signed({9'd0, wfrac}) + wdlt;
    /* verilator lint_off UNUSEDSIGNAL */   // the top bits: the count is 8 bits
    wire signed [16:0] wcnt = wsum >>> 8;           // whole counts this cycle (floor)
    /* verilator lint_on UNUSEDSIGNAL */
    always_ff @(posedge clk) begin
        st2_q <= cab_lines[1];
        if (reset || !live) begin
            wfrac <= '0;
        end else if (st2_q && !cab_lines[1]) begin     // ST2 fell: one cycle
            wfrac <= wsum[7:0];
            wheel <= wheel + wcnt[7:0];
        end
        if (reset) wheel <= 8'h00;
    end

    // ---- the pedal: 0..0x90 -> 0..0x3f (x7/16), held at 0x3f
    /* verilator lint_off UNUSEDSIGNAL */   // the product's low four bits are the /16
    wire [10:0] g7     = {3'b000, cab_gas} * 11'd7;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [6:0]  scaled = (g7[10:4] > 7'd63) ? 7'd63 : g7[10:4];
    assign pedal_sprint = live ? 8'hff - {1'b0, scaled} : 8'hff;
    assign pedal_apb    = live ? 8'h3f - {1'b0, scaled} : 8'h3f;

    // ---- the switches (the adapter's lines are low when closed)
    assign coin1   = live && !cab_lines[3];
    // the COIN2 line is the cabinet's action button: the G25 shifter's red 3 (Super Sprint has one coin slot a player)
    assign action  = live && !cab_lines[4];
    assign start   = live && !cab_lines[5];
    assign test    = live && !cab_lines[7];
    assign hi_gear = live && !cab_lines[2];
endmodule

`default_nettype wire
