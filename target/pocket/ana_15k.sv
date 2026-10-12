//------------------------------------------------------------------------------
// 25 kHz -> 15 kHz for the Analogizer: Atari System 2's 512 x 384 progressive
// frame (640 x 416 dots at 16 MHz, 25.0 kHz, 60.1 Hz -- a medium-resolution
// monitor's) as a progressive 192p picture a 15 kHz monitor or television
// takes (609 x 262 dots at 9.6 MHz, 15.75 kHz, the same 60.1 Hz).  The
// Pocket's own picture does not pass through here.  Modelled on Xenophobe's
// ana_15k.sv (31 kHz 480 lines to 240p); what differs is below.
//
//   * Each output line shows one of the game's line pairs (source lines 2j
//     and 2j+1 on output line j), its 512 dots at 10 clocks a dot, 53.3 us
//     of a 63.5 us line, so the picture keeps its shape.  Blend (the
//     default): each dot is the average of the pair's two, per channel, on
//     the full 8 bits ((a + b) >> 1), kept to the 6 the DAC shows, so
//     nothing one line thin vanishes and nothing flickers.  Sharp: the
//     pair's even line, unblended.
//   * Frame-locked: the output frame restarts DELAY clocks after the
//     source's first visible line starts, every frame, and its 262 lines add
//     up to exactly the source's 1,597,440 clocks, so it never drops, repeats
//     or tears a frame and vsync lands on the same output line every frame.
//     Every dot is 10 clocks but each line's last (deep in the back porch),
//     which is 17, and 18 on 26 of the 262 lines (a Bresenham spread): lines
//     are 6097 or 6098 clocks, never anything else.
//   * A pair (80 us of source) is longer than an output line (63.5 us), so
//     the output runs faster than the source and has to start late: it can
//     only finish its 192nd line after the source's 384th, so it starts
//     about 40 pairs behind and catches up over the frame.  Pairs go into a
//     ring of RING slots the output reads; DELAY sits between the two limits
//     (sim/run_ana15k.sh measures both margins and fails a DELAY outside
//     them): late enough that the output never reads a dot before it is
//     written (the last pair is the tightest), early enough that the source
//     never overwrites a slot before it is read (pair RING, overwriting pair
//     0, is the tightest).  With RING = 48 the window is about 306,000 to
//     367,000 clocks; DELAY = 336,000 is near its middle.  Slots are numbered
//     modulo 48 from each frame's pair 0, and 192 pairs are four rings.
//   * The even line of a pair waits in a one-line buffer while the odd one
//     arrives, as in Xenophobe's.
//
// Every output changes at the end of the cycle its enable (o_ce) is high,
// as the core's own video does, so a consumer may sample one clock after.
//------------------------------------------------------------------------------
`default_nettype none

module ana_15k #(
    parameter int SW = 512,                  // source visible dots
    parameter int SH = 384,                  // source visible lines
    parameter int SRC_FRAME = 1_597_440,     // source clocks a frame (640 * 6 * 416)
    parameter int DOT   = 10,                // clocks an output dot
    parameter int DOTS  = 609,               // output dots a line
    parameter int LINES = 262,               // output lines a frame
    parameter int HS0 = 524, HS1 = 569,      // output hsync [HS0, HS1): 4.7 us
    parameter int VS0 = 219, VS1 = 222,      // output vsync [VS0, VS1)
    parameter int RING  = 48,                // pairs the ring holds
    parameter int DELAY = 336_000            // source line 0 -> output line 0, clocks
) (
    input  wire         clk,
    input  wire         sharp,               // 1: the even line of each pair (any domain)

    // the core's picture, values changing on src_ce
    input  wire         src_ce,
    input  wire  [23:0] src_rgb,
    input  wire         src_hb,
    input  wire         src_vb,

    // the 15 kHz picture
    output logic        o_ce,
    output logic [23:0] o_rgb,
    output logic        o_hs,
    output logic        o_vs,
    output logic        o_hb,
    output logic        o_vb
);
    localparam int LINE_CLK = SRC_FRAME / LINES;            // 6097
    localparam int PAD  = LINE_CLK - DOTS * DOT;            // the last dot's extra clocks, 7
    localparam int LONG = SRC_FRAME - LINES * LINE_CLK;     // lines one clock longer, 26
    localparam int SLW  = $clog2(RING);
    localparam int XW   = $clog2(SW);

    // initial values in initial blocks, and plain always: always_ff may not
    // share them (lint)
    logic [1:0] sharp_s;
    initial sharp_s = 2'b00;
    always @(posedge clk) sharp_s <= {sharp_s[0], sharp};

    // ------------------------------------------------------------ the source
    logic          p_hb, p_vb;
    logic [XW-1:0] sx;
    logic [8:0]    sy;
    logic [SLW-1:0] w_slot;                               // this pair's ring slot
    initial begin p_hb = 1'b1; p_vb = 1'b1; sx = '0; sy = '0; w_slot = '0; end
    wire           lstart = p_hb && !src_hb;              // a line's first dot
    wire           fstart = lstart && p_vb && !src_vb;    // the frame's first line
    wire [XW-1:0]  x_now = lstart ? '0 : sx;
    wire [8:0]     y_now = !lstart ? sy : fstart ? 9'd0 : sy + 9'd1;
    wire           vis = !src_hb && !src_vb;
    always @(posedge clk) if (src_ce) begin
        p_hb <= src_hb;
        p_vb <= src_vb;
        if (lstart) begin
            sy <= y_now;
            if (fstart) w_slot <= '0;
            else if (!y_now[0]) w_slot <= (w_slot == SLW'(RING - 1)) ? '0 : w_slot + 1'd1;
        end
        if (vis) sx <= x_now + 1'd1;
    end

    // the even line of a pair, held while the odd one comes
    logic [23:0] ebuf [0:SW-1];
    logic [23:0] e_q;
    always_ff @(posedge clk) begin
        if (src_ce && vis && !y_now[0]) ebuf[x_now] <= src_rgb;
        e_q <= ebuf[x_now];
    end

    // ...and with it, one clock later, the pair's dot into the ring
    logic                st_v;
    logic [SLW+XW-1:0]   st_a;
    logic [23:0]         st_rgb;
    initial st_v = 1'b0;
    always @(posedge clk) begin
        st_v   <= src_ce && vis && y_now[0];
        st_a   <= {w_slot, x_now};
        st_rgb <= src_rgb;
    end
    function automatic [5:0] avg6(input [7:0] a, input [7:0] b);
        return 6'(({1'b0, a} + {1'b0, b}) >> 3);          // (a + b) >> 1, top 6 bits
    endfunction
    wire [17:0] pair = sharp_s[1] ? {e_q[23:18], e_q[15:10], e_q[7:2]}
                     : {avg6(e_q[23:16], st_rgb[23:16]), avg6(e_q[15:8], st_rgb[15:8]),
                        avg6(e_q[7:0], st_rgb[7:0])};
    logic [17:0]       ring [0:RING*SW-1];
    logic [SLW+XW-1:0] p_ra;
    logic [17:0]       p_q;
    always_ff @(posedge clk) begin
        if (st_v) ring[st_a] <= pair;
        p_q <= ring[p_ra];
    end

    // ------------------------------------------------------------ the output
    // frame start: DELAY clocks after the source's first visible line starts
    logic [19:0] dly;
    logic        dly_on;
    initial begin dly = '0; dly_on = 1'b0; end
    wire         go = dly_on && (dly == 20'd0);
    always @(posedge clk) begin
        if (src_ce && fstart) begin dly <= 20'(DELAY - 1); dly_on <= 1'b1; end
        else if (dly_on) begin
            if (dly == 20'd0) dly_on <= 1'b0;
            else dly <= dly - 20'd1;
        end
    end

    logic [4:0]     cc;                      // clock within the dot
    logic [9:0]     od;                      // dot within the line
    logic [8:0]     ol;                      // line within the frame
    logic [SLW-1:0] r_slot;                  // the ring slot of this line's pair
    logic [8:0]     acc;                     // Bresenham
    logic           long_l;                  // this line's last dot is a clock longer
    initial begin cc = '0; od = '0; ol = 9'(LINES - 1); r_slot = '0; acc = '0; long_l = 1'b0; end
    wire  [4:0]     dot_last = (od != 10'(DOTS - 1)) ? 5'(DOT - 1)
                             : long_l ? 5'(DOT + PAD) : 5'(DOT + PAD - 1);
    wire  [9:0]     acc_n = 10'(acc) + 10'(LONG);
    always @(posedge clk) begin
        o_ce <= (cc == 5'd1);
        if (cc == 5'd0)                      // this dot's pixel: address, then data
            p_ra <= {r_slot, od[XW-1:0]};
        if (cc == 5'd2) begin                // and show it
            o_rgb <= (od < 10'(SW) && ol < 9'(SH / 2))
                   ? {p_q[17:12], 2'b00, p_q[11:6], 2'b00, p_q[5:0], 2'b00} : 24'h0;
            o_hb  <= (od >= 10'(SW));
            o_vb  <= (ol >= 9'(SH / 2));
            o_hs  <= (od >= 10'(HS0)) && (od < 10'(HS1));
            o_vs  <= (ol >= 9'(VS0)) && (ol < 9'(VS1));
        end
        if (go) begin                        // frame start (the natural wrap, once locked)
            cc <= '0; od <= '0; ol <= '0; r_slot <= '0;
            long_l <= (10'(LONG) >= 10'(LINES));
            acc <= 9'((10'(LONG) >= 10'(LINES)) ? 10'(LONG) - 10'(LINES) : 10'(LONG));
        end else if (cc == dot_last) begin
            cc <= '0;
            if (od == 10'(DOTS - 1)) begin
                od <= '0;
                if (ol == 9'(LINES - 1)) begin
                    ol <= 9'd0; r_slot <= '0;
                end else begin
                    ol <= ol + 9'd1;
                    if (ol < 9'(SH / 2))     // past a picture line: the next pair's slot
                        r_slot <= (r_slot == SLW'(RING - 1)) ? '0 : r_slot + 1'd1;
                end
                long_l <= (acc_n >= 10'(LINES));
                acc <= 9'((acc_n >= 10'(LINES)) ? acc_n - 10'(LINES) : acc_n);
            end else od <= od + 10'd1;
        end else cc <= cc + 5'd1;
    end
endmodule
