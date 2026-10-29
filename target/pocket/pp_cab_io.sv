//------------------------------------------------------------------------------
// Pole Position cabinet controls through the Analogizer SNAC port: the FPGA
// side of the Raspberry Pi Pico adapter (hw/cabinet_adapter, docs/cabinet_io.md).
//
// The core is the master. It raises LATCH (SNAC OUT1): the Pico's PIO samples
// the cabinet's eight digital lines at that instant and shifts a 40-bit frame
// out on DATA (SNAC IN4), one bit per CLK (SNAC OUT2) pulse, MSB first:
//
//   39..32  D      TEST SERVICE START COIN2 COIN1 SFT ST2 ST1 (bit 0 = ST1),
//                  the levels on the adapter's inputs, as the board's input
//                  networks deliver them (not inverted, not decoded)
//   31..24  ~D     the same sample inverted
//   23..16  GAS    the code the board's ADC0804 would read
//   15..8   BLE
//    7..0   CHK    GAS ^ BLE ^ 0x5A
//
// A frame is accepted only if both checks hold; otherwise the outputs keep the
// last good frame and err_count counts it. `present` drops if no good frame
// arrives for TIMEOUT frames (adapter unplugged or off).
//
// Two lanes: the adapter's second board (rev 2) sends every frame on IN7 as
// well, from a second state machine, so that with a crossed A-A cable (USB 3
// pins 6 and 9 swapped) a copy still arrives on IN4. Reading both lanes here
// also makes a first board (DATA on IN4 only) work through a crossed cable,
// where its frames arrive on IN7. Each lane is shifted and checked on its
// own; lane A (IN4) is taken when it is good, lane B (IN7) otherwise. A lane
// with nothing on it (a line held low or high) never passes the D / ~D check.
// DUAL = 0 leaves lane B out.
//
// Timing (defaults, 49.152 MHz clk): CLK 3.072 MHz (HALF = 8 clocks per
// phase), LATCH high ~1 us, ~1 us before the first CLK, so a frame takes
// about 15 us: some 65,000 samples of the wheel a second, far faster than the
// 53xx's program reads it. DATA is sampled, through two flip-flops, in the
// last clock of each CLK high phase; the Pico changes it only after CLK falls.
//
// Copied unchanged from the Pole Position core (RndMnkIII/PocketPolePositionII,
// rtl/pp_cab_io.sv). This core runs it on clk_sys, 96 MHz, so core_top gives
// it HALF = 16, LATCH_W = 96 and GAP = 96: the same 3 MHz CLK and ~1 us gaps.
//------------------------------------------------------------------------------
`default_nettype none

module pp_cab_io #(
    parameter int HALF    = 8,      //! clk cycles per CLK phase
    parameter int LATCH_W = 48,     //! clk cycles LATCH is high
    parameter int GAP     = 48,     //! clk cycles from LATCH falling to the first CLK rise
    parameter int TIMEOUT = 64,     //! frames without a good one before `present` drops
    parameter bit DUAL    = 1       //! 1: also read the frame copy on IN7 (sdata_b)
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,      //! run the link (cabinet controls selected)

    // ---- SNAC lines ------------------------------------------------------------
    output logic       latch,       //! OUT1
    output logic       sclk,        //! OUT2
    input  wire        sdata,       //! IN4 (asynchronous)
    input  wire        sdata_b,     //! IN7 (asynchronous): the same frame, from a rev 2 adapter or through a crossed cable

    // ---- the last good frame ---------------------------------------------------
    output logic [7:0] lines,       //! D: bit 0 ST1, 1 ST2, 2 SFT, 3 COIN1, 4 COIN2, 5 START, 6 SERVICE, 7 TEST
    output logic [7:0] gas,
    output logic [7:0] ble,
    output logic       present,     //! good frames are arriving
    output logic       frame_ok,    //! one clock per accepted frame
    output logic       lane_b,      //! the last accepted frame came from IN7 (lane A was not good)
    output logic [15:0] err_count   //! rejected frames (saturates)
);
    // ---------------------------------------------------------- DATA synchronisers
    logic [1:0] sd_q = 2'b00, sdb_q = 2'b00;
    always_ff @(posedge clk) begin
        sd_q  <= {sd_q[0], sdata};
        sdb_q <= {sdb_q[0], DUAL ? sdata_b : 1'b0};
    end
    wire sd = sd_q[1], sdb = sdb_q[1];

    // ---------------------------------------------------------- sequencer
    typedef enum logic [1:0] { S_IDLE, S_LATCH, S_GAP, S_BITS } st_t;
    st_t st = S_IDLE;

    localparam int CW = $clog2((LATCH_W > GAP ? LATCH_W : GAP) + 2 * HALF + 1);
    logic [CW-1:0] cnt = '0;
    logic [5:0]    nbit = '0;       // bits taken in this frame
    logic          phase_hi = 1'b0; // CLK high phase
    logic [39:0]   sh = '0, shb = '0;
    logic [$clog2(TIMEOUT+1)-1:0] miss = '0;

    function automatic logic good(input logic [39:0] f);
        good = (f[39:32] == ~f[31:24]) && (f[7:0] == (f[23:16] ^ f[15:8] ^ 8'h5A));
    endfunction
    wire        good_a = good(sh);
    wire        good_b = DUAL && good(shb);
    wire [39:0] f      = good_a ? sh : shb;     // the frame taken

    always_ff @(posedge clk) begin
        frame_ok <= 1'b0;
        if (reset || !enable) begin
            st <= S_IDLE; latch <= 1'b0; sclk <= 1'b0; cnt <= '0; nbit <= '0;
            phase_hi <= 1'b0;
            if (reset) begin
                lines <= 8'hFF; gas <= 8'h00; ble <= 8'h00; lane_b <= 1'b0;
                present <= 1'b0; err_count <= '0; miss <= '0;
            end
        end else begin
            case (st)
            S_IDLE: begin
                latch <= 1'b1; cnt <= '0; st <= S_LATCH;
            end
            S_LATCH: if (cnt == CW'(LATCH_W - 1)) begin
                latch <= 1'b0; cnt <= '0; st <= S_GAP;
            end else cnt <= cnt + 1'b1;
            S_GAP: if (cnt == CW'(GAP - 1)) begin
                sclk <= 1'b1; phase_hi <= 1'b1; cnt <= '0; nbit <= '0; st <= S_BITS;
            end else cnt <= cnt + 1'b1;
            S_BITS: begin
                if (cnt == CW'(HALF - 1)) begin
                    cnt <= '0;
                    if (phase_hi) begin                 // end of the high phase: take the bit
                        sh  <= {sh[38:0], sd};
                        shb <= {shb[38:0], sdb};
                        nbit <= nbit + 1'b1;
                        sclk <= 1'b0; phase_hi <= 1'b0;
                    end else if (nbit == 6'd40) begin  // frame complete
                        st <= S_IDLE;
                        if (good_a || good_b) begin
                            lines <= f[39:32]; gas <= f[23:16]; ble <= f[15:8]; lane_b <= !good_a;
                            frame_ok <= 1'b1; present <= 1'b1; miss <= '0;
                        end else begin
                            if (err_count != 16'hFFFF) err_count <= err_count + 1'b1;
                            if (miss == ($bits(miss))'(TIMEOUT)) present <= 1'b0;
                            else miss <= miss + 1'b1;
                        end
                    end else begin
                        sclk <= 1'b1; phase_hi <= 1'b1;
                    end
                end else cnt <= cnt + 1'b1;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
