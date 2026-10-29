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

module ss_cab_merge (
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
    output wire        coin1, coin2, start, test, hi_gear
);
    // ---- the wheel
    logic st2_q = 1'b1;
    logic signed [2:0] acc = '0;     // half-count remainder for gain 1
    wire up = !cab_lines[0] ^ rev;   // ST1 low when ST2 falls: counts up (rev: down)
    always_ff @(posedge clk) begin
        st2_q <= cab_lines[1];
        if (reset || !live) begin
            acc <= '0;
        end else if (st2_q && !cab_lines[1]) begin     // ST2 fell: one cycle
            case (gain)
                2'd1: begin                              // one count per two cycles in the same direction
                    if (up) begin
                        if (acc >= 3'sd1) begin wheel <= wheel + 8'd1; acc <= acc - 3'sd1; end
                        else acc <= acc + 3'sd1;
                    end else begin
                        if (acc <= -3'sd1) begin wheel <= wheel - 8'd1; acc <= acc + 3'sd1; end
                        else acc <= acc - 3'sd1;
                    end
                end
                2'd2:    wheel <= up ? wheel + 8'd2 : wheel - 8'd2;
                default: wheel <= up ? wheel + 8'd1 : wheel - 8'd1;
            endcase
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
    assign coin2   = live && !cab_lines[4];
    assign start   = live && !cab_lines[5];
    assign test    = live && !cab_lines[7];
    assign hi_gear = live && !cab_lines[2];
endmodule

`default_nettype wire
