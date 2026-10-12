// The 25 -> 15 kHz converter on its own (target/pocket/ana_15k.sv), fed the
// core's raster (640 x 416 dots, a dot every sixth 96 MHz clock, 512 x 384
// visible) with a colour every dot and line can be told apart by, and read
// at its outputs as the Analogizer takes them.  It checks, frame after frame:
//
//   picture  every output line j shows pair j's 512 dots in order: each
//            exactly (a + b) >> 1 per channel of source lines 2j and 2j+1,
//            kept to its top 6 bits (Blend), or exactly line 2j's top 6
//            bits (Sharp); 192 such lines a frame
//   lines    every hsync period is 6097 or 6098 clocks -- never anything
//            else, frame boundary included -- with exactly 26 of the long
//            ones a frame; hsync 45 dots (450 clocks)
//   frame    vsync rises exactly once a frame, on output line 219 every
//            time, and its period is the source frame's, 1,597,440 clocks;
//            after the first, every frame restart falls on the natural end
//            of line 261 (nothing dropped, repeated or torn)
//   ring     every dot the output reads is the pair it should show: never
//            one the source has not written yet (overtaken), never one the
//            next pair in its slot has already replaced (overflowed); and
//            the least time from a dot's write to its read, and from its
//            read to its slot's next write -- the margins DELAY sits between
//
// sim/run_ana15k.sh builds and runs it, and runs it again at a DELAY too
// early and one too late, which must fail.
`timescale 1ps/1ps
`default_nettype none

module tb_ana15k #(parameter int DELAY = 336_000);
    localparam int HTOTAL = 640, VTOTAL = 416, W = 512, H = 384;
    localparam int DIV = 6;
    localparam int SRC_FRAME = HTOTAL * VTOTAL * DIV;
    localparam int OLINES = 262, OVIS = 192, RING = 48;
    localparam int LSHORT = 6097, LLONG = 6098, NLONG = SRC_FRAME - OLINES * LSHORT;
    localparam int OHSW = 450, OVS0 = 219;

    logic clk = 1'b0;
    always #5208 clk = ~clk;                  // 96 MHz

    // ------------------------------------------------------- the source
    int         div = 0;
    logic       ce = 1'b0;
    logic [9:0] hpos = '0, vpos = '0;
    logic       hb = 1'b1, vb = 1'b1;
    logic [23:0] rgb = '0;
    function automatic [23:0] colour(input int x, input int y);
        logic [31:0] h;
        h = (x * 32'h9E3779B1) ^ (y * 32'h85EBCA77) ^ 32'h5bd1e995;
        h = h ^ (h >> 15);
        return h[23:0];
    endfunction
    always_ff @(posedge clk) begin
        div <= (div == DIV - 1) ? 0 : div + 1;
        ce  <= (div == DIV - 1);
        if (ce) begin
            if (hpos == 10'(HTOTAL - 1)) begin
                hpos <= '0;
                vpos <= (vpos == 10'(VTOTAL - 1)) ? '0 : vpos + 10'd1;
            end else hpos <= hpos + 10'd1;
            hb  <= !(hpos < 10'(W));
            vb  <= !(vpos < 10'(H));
            rgb <= (hpos < 10'(W) && vpos < 10'(H)) ? colour(hpos, vpos) : 24'h0;
        end
    end

    logic sharp = 1'b0;
    wire        o_ce, o_hs, o_vs, o_hb, o_vb;
    wire [23:0] o_rgb;
    ana_15k #(.DELAY(DELAY)) dut (
        .clk(clk), .sharp(sharp),
        .src_ce(ce), .src_rgb(rgb), .src_hb(hb), .src_vb(vb),
        .o_ce(o_ce), .o_rgb(o_rgb), .o_hs(o_hs), .o_vs(o_vs), .o_hb(o_hb), .o_vb(o_vb)
    );

    function automatic [7:0] six(input [7:0] v);     // what the converter keeps
        return {v[7:2], 2'b00};
    endfunction
    function automatic [7:0] avg(input [7:0] a, input [7:0] b);
        return six(8'((9'(a) + 9'(b)) >> 1));
    endfunction
    function automatic [23:0] want(input int x, input int j, input logic sh);
        logic [23:0] a, b;
        a = colour(x, 2 * j);
        b = colour(x, 2 * j + 1);
        if (sh) return {six(a[23:16]), six(a[15:8]), six(a[7:0])};
        return {avg(a[23:16], b[23:16]), avg(a[15:8], b[15:8]), avg(a[7:0], b[7:0])};
    endfunction

    int errors = 0;
    task automatic fail(input string what);
        if (errors < 20) $display("FAIL: %s", what);
        errors++;
    endtask

    // ------------------------------------------- the outputs, every clock
    longint cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // the picture, sampled the clock after its enable (outputs change at
    // the end of the enable's cycle)
    logic  take = 1'b0, phb = 1'b1, pvb = 1'b1;
    int    ox = 0, oj = -1, dots_bad = 0, lines_seen = 0, lines_short = 0;
    logic  mode_sh = 1'b0, checking = 1'b0;
    always @(posedge clk) begin
        take <= o_ce;
        if (take) begin
            if (pvb && !o_vb) oj = 0;
            else if (phb && !o_hb && !o_vb) oj = oj + 1;
            if (phb && !o_hb) ox = 0;
            if (!o_hb && !o_vb) begin
                if (checking && oj >= 0 && oj < OVIS && o_rgb !== want(ox, oj, mode_sh)) begin
                    if (dots_bad < 5)
                        $display("  line %0d dot %0d: got %06h want %06h (%s)", oj, ox, o_rgb,
                                 want(ox, oj, mode_sh), mode_sh ? "sharp" : "blend");
                    dots_bad++;
                end
                ox = ox + 1;
            end
            if (!phb && o_hb && !o_vb && checking) begin
                lines_seen++;
                if (ox != W) lines_short++;
            end
            phb = o_hb; pvb = o_vb;
        end
    end

    // timing: hsync and vsync periods, hsync width, the vsync's line
    logic   hs_p = 1'b0, vs_p = 1'b0;
    longint hs_t = -1, vs_t = -1, hs_rise_t = 0;
    int     per_bad = 0, long_n = 0, short_n = 0, width_bad = 0, hs_since_vb = 0;
    int     vs_line_bad = 0, vs_per_bad = 0, frames = 0;
    always @(posedge clk) begin
        hs_p <= o_hs; vs_p <= o_vs;
        if (o_hs && !hs_p) begin
            if (checking && hs_t >= 0) begin
                if (cyc - hs_t == LLONG) long_n++;
                else if (cyc - hs_t == LSHORT) short_n++;
                else begin
                    if (per_bad < 5) $display("  hsync period %0d clocks", cyc - hs_t);
                    per_bad++;
                end
            end
            hs_t = cyc; hs_rise_t = cyc;
            hs_since_vb++;
        end
        if (!o_hs && hs_p && checking && cyc - hs_rise_t != OHSW) width_bad++;
        if (o_vs && !vs_p) begin
            if (checking) begin
                frames++;
                if (vs_t >= 0 && cyc - vs_t != SRC_FRAME) begin
                    $display("  vsync period %0d clocks", cyc - vs_t);
                    vs_per_bad++;
                end
                if (hs_since_vb != OVS0) begin
                    $display("  vsync after %0d hsyncs from line 0", hs_since_vb);
                    vs_line_bad++;
                end
            end
            vs_t = cyc;
        end
    end
    // line 0 starts at o_vb's fall; count hsyncs from there
    logic vb_p2 = 1'b1;
    always @(posedge clk) begin
        vb_p2 <= o_vb;
        if (vb_p2 && !o_vb) hs_since_vb = 0;
    end

    // frame restarts that do not fall on the natural end of line 261
    int go_n = 0, go_off = 0;
    always @(posedge clk) if (dut.go) begin
        go_n++;
        if (go_n > 1 && !(dut.ol == 9'(OLINES - 1) && dut.od == 10'(dut.DOTS - 1) && dut.cc == dut.dot_last))
            go_off++;
    end

    // the ring: which pair (counted over the whole run) each slot address
    // holds and when it was written, which pair was last read from it and
    // when; every read must find the pair the output line shows, and every
    // write must find the pair it replaces already read
    int     sfr = 0, ofr = 0;                 // frames started, source and output
    always @(posedge clk) begin
        if (ce && dut.fstart) sfr <= sfr + 1;
        if (dut.go) ofr <= ofr + 1;
    end
    localparam int NA = RING * W;
    int     held [0:NA-1], rd_pair [0:NA-1];
    longint wr_t [0:NA-1], rd_t [0:NA-1];
    longint min_ahead = 1 << 40, min_behind = 1 << 40;
    int     overtaken = 0, overflowed = 0, reads = 0;
    logic   st_v_q = 1'b0;
    int     st_pair = 0;
    int     q, a, j;                       // (not declared with a value inside
                                           // the block: those would be static)
    always @(posedge clk) begin
        // the pair being written: the source frame and the line's pair
        if (dut.st_v) begin
            q = (sfr - 1) * (H / 2) + int'(dut.sy[8:1]);
            a = int'(dut.st_a);
            if (checking && held[a] >= 0 && held[a] == q - RING) begin
                if (rd_pair[a] < held[a]) begin              // never read
                    if (overflowed < 5)
                        $display("  pair %0d replaces pair %0d in slot %0d dot %0d before it was read",
                                 q, held[a], a / W, a % W);
                    overflowed++;
                end else if (cyc - rd_t[a] < min_behind) min_behind = cyc - rd_t[a];
            end
            held[a] = q; wr_t[a] = cyc;
        end
        // a read: the dot's address goes out on cc == 0 of a picture dot
        if (dut.cc == 5'd0 && dut.od < 10'(W) && dut.ol < 9'(OVIS) && ofr > 0) begin
            a = int'({dut.r_slot, dut.od[8:0]});
            j = (ofr - 1) * OVIS + int'(dut.ol);
            if (checking) begin
                reads++;
                if (held[a] != j) begin
                    if (held[a] < j) begin
                        if (overtaken < 5)
                            $display("  line %0d dot %0d read before its pair was written (slot holds pair %0d)",
                                     dut.ol, dut.od, held[a]);
                        overtaken++;
                    end else begin
                        if (overflowed < 5)
                            $display("  line %0d dot %0d: its slot already holds pair %0d", dut.ol, dut.od, held[a]);
                        overflowed++;
                    end
                end else if (cyc - wr_t[a] < min_ahead) min_ahead = cyc - wr_t[a];
            end
            rd_pair[a] = j; rd_t[a] = cyc;
        end
    end

    task automatic run_frames(input int n, input logic sh, input string name);
        lines_seen = 0; lines_short = 0; dots_bad = 0; per_bad = 0; long_n = 0; short_n = 0;
        width_bad = 0; vs_line_bad = 0; vs_per_bad = 0; frames = 0;
        // start checking at a vsync, so whole frames are counted
        @(posedge clk iff (o_vs && !vs_p));
        mode_sh = sh; checking = 1'b1;
        repeat (n) @(posedge clk iff (o_vs && !vs_p));
        checking = 1'b0;
        $display("%s: %0d frames, %0d lines of %0d dots, %0d short, %0d dots differ; hsync periods %0d x %0d + %0d x %0d, %0d other; %0d hsyncs not %0d clocks; vsync %0d off line %0d, %0d periods not %0d",
                 name, frames, lines_seen, W, lines_short, dots_bad, short_n, LSHORT, long_n, LLONG,
                 per_bad, width_bad, OHSW, vs_line_bad, OVS0, vs_per_bad, SRC_FRAME);
        if (lines_seen != n * OVIS) fail({name, ": not 192 visible lines a frame"});
        if (lines_short != 0) fail({name, ": a line without 512 dots"});
        if (dots_bad != 0) fail({name, ": dots differ from the pair"});
        if (per_bad != 0) fail({name, ": an hsync period other than 6097/6098"});
        if (long_n != n * NLONG) fail({name, ": not 26 long lines a frame"});
        if (width_bad != 0) fail({name, ": hsync not 45 dots"});
        if (vs_line_bad != 0) fail({name, ": vsync not on output line 219"});
        if (vs_per_bad != 0) fail({name, ": frame period is not the source's"});
    endtask

    initial begin
        for (int i = 0; i < NA; i++) begin held[i] = -1; rd_pair[i] = -1; wr_t[i] = 0; rd_t[i] = 0; end
        $display("DELAY %0d clocks, ring of %0d pairs", DELAY, RING);
        repeat (3 * SRC_FRAME) @(posedge clk);         // lock
        run_frames(3, 1'b0, "Blend");
        sharp = 1'b1;
        repeat (SRC_FRAME) @(posedge clk);
        run_frames(2, 1'b1, "Sharp");
        sharp = 1'b0;
        repeat (SRC_FRAME) @(posedge clk);
        run_frames(1, 1'b0, "Blend again");
        $display("frame restarts: %0d, %0d off the natural end of line 261 after the first",
                 go_n, go_off);
        if (go_off != 0) fail("a frame restart moved the output (a dropped or torn frame)");
        $display("ring: %0d reads checked; %0d overtaken, %0d overflowed; a dot is read at least %0d clocks after it is written and at least %0d before its slot is written again",
                 reads, overtaken, overflowed, min_ahead, min_behind);
        if (reads != 6 * OVIS * W) fail("ring: not every picture dot's read was checked");
        if (overtaken != 0) fail("ring: the output overtook the source");
        if (overflowed != 0) fail("ring: the source overwrote a pair before it was read");
        if (errors == 0) $display("PASS");
        else $display("FAILED: %0d", errors);
        $finish;
    end
endmodule
