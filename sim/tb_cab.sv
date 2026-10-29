// The cabinet adapter's link into the Sprints' controls: pp_cab_io clocked at
// 96 MHz (as core_top does) against a model of the adapter's PIO program, and
// ss_cab_merge behind it.  The model follows docs/snac_link.md section 3: on
// LATCH rising it samples the switch lines, then presents the 40-bit frame MSB
// first and moves to the next bit after each CLK falls.  Checks: the frame is
// accepted, the pedal scales to the Sprints' and APB's codes, the switches map,
// and the wheel's quadrature counts as the 53xx does (ST2 falling, up with ST1
// low), at the three gains, in both directions, with a turn back.
`timescale 1ns/1ps
module tb_cab;
    logic clk = 0;
    always #5.208 clk = ~clk;                 // 96 MHz
    logic reset = 1, enable = 0;

    // ---- the adapter model
    logic [7:0] sw  = 8'hFF;                   // D: 0 ST1 1 ST2 2 SFT 3 COIN1 4 COIN2 5 START 6 SERVICE 7 TEST
    logic [7:0] pg  = 8'h00, pb = 8'h00;
    wire  latch, sclk;
    logic data = 1'b0;
    logic [39:0] fr;
    integer bitn;
    logic latch_q = 0, sclk_q = 0;
    always @(posedge clk) begin
        latch_q <= latch; sclk_q <= sclk;
    end
    // LATCH rising (as the PIO sees it): take the sample, present the first bit
    always @(posedge latch) begin
        fr = {sw, ~sw, pg, pb, pg ^ pb ^ 8'h5A};
        bitn = 39;
        data <= 1'b0;
    end
    always @(negedge latch) begin
        data <= fr[39]; bitn = 38;
    end
    // each CLK fall: the next bit
    always @(negedge sclk) if (!latch && bitn >= 0 && bitn < 39) begin data <= fr[bitn]; bitn = bitn - 1; end

    wire [7:0] lines, gas, ble;
    wire present, frame_ok, lane_b; wire [15:0] errs;
    pp_cab_io #(.HALF(16), .LATCH_W(96), .GAP(96)) io (
        .clk(clk), .reset(reset), .enable(enable), .latch(latch), .sclk(sclk),
        .sdata(data), .sdata_b(1'b1),
        .lines(lines), .gas(gas), .ble(ble), .present(present), .frame_ok(frame_ok),
        .lane_b(lane_b), .err_count(errs));

    logic [1:0] gain = 0; logic rev = 0;
    wire live = enable && present;
    wire [7:0] wheel, ped_s, ped_a; wire c1, c2, st, tst, hig;   // c2 is the action button now
    ss_cab_merge #(.WHEEL_Q8(256)) m (.clk(clk), .reset(reset), .live(live), .cab_lines(lines), .cab_gas(gas), .gain(gain), .rev(rev),
                    .wheel(wheel), .pedal_sprint(ped_s), .pedal_apb(ped_a),
                    .coin1(c1), .action(c2), .start(st), .test(tst), .hi_gear(hig));

    integer fails = 0;
    task check(input string what, input integer got, input integer exp);
        if (got !== exp) begin $display("FAIL %s: got %0d (0x%0h) expected %0d (0x%0h)", what, got, got, exp, exp); fails++; end
    endtask
    task settle; repeat (4000) @(posedge clk); endtask    // a few frames (one is ~15 us = 1440 clocks)

    // one whole quadrature cycle in the direction given, as vwheel.c makes it: the
    // counted edge is ST2 falling, with ST1 low (up) or high (down)
    task cycle(input bit up);
        // phases (ST2 ST1): rest 11, then up: 11 -> 10(ST1 low... ) see below
        if (up) begin
            sw[0] = 0; settle;  sw[1] = 0; settle;     // ST1 falls, then ST2 falls with ST1 low: +1
            sw[0] = 1; settle;  sw[1] = 1; settle;     // released back to rest
        end else begin
            sw[1] = 0; settle;                         // ST2 falls with ST1 high: -1
            sw[0] = 0; settle;  sw[1] = 1; settle;  sw[0] = 1; settle;
        end
    endtask

    initial begin
        repeat (20) @(posedge clk); reset = 0; enable = 1;
        settle; settle;
        check("present", present, 1);
        check("errors", errs, 0);
        check("idle lines", lines, 8'hFF);
        check("coin1 idle", c1, 0); check("start idle", st, 0); check("test idle", tst, 0);
        check("pedal released (Sprint)", ped_s, 8'hFF); check("pedal released (APB)", ped_a, 8'h3F);

        // pedal: released 0, floored 0x90 = 0x3f of travel, half 0x48 = 31 (31.5 floored)
        pg = 8'h90; settle; check("pedal floored (Sprint)", ped_s, 8'hC0); check("pedal floored (APB)", ped_a, 8'h00);
        pg = 8'h48; settle; check("pedal half (Sprint)", ped_s, 8'hFF - 31); check("pedal half (APB)", ped_a, 8'h3F - 31);
        pg = 8'hFF; settle; check("pedal past the end (Sprint)", ped_s, 8'hC0);
        pg = 8'h00; settle;

        // switches (0 = closed)
        sw[3] = 0; settle; check("coin1", c1, 1); sw[3] = 1;
        sw[4] = 0; settle; check("action (COIN2 line)", c2, 1); sw[4] = 1;
        sw[5] = 0; settle; check("start", st, 1); sw[5] = 1;
        sw[7] = 0; settle; check("test", tst, 1); sw[7] = 1;
        sw[6] = 0; settle; check("service is not self-test", tst, 0); sw[6] = 1;
        sw[2] = 0; settle; check("hi gear", hig, 1); sw[2] = 1;
        settle; check("all released", {c1, c2, st, tst, hig}, 0);

        // wheel, gain 0: +1 a cycle, both ways
        check("wheel at start", wheel, 0);
        repeat (5) cycle(1); check("5 up", wheel, 5);
        repeat (3) cycle(0); check("3 down", wheel, 2);
        repeat (4) cycle(0); check("wraps", wheel, 8'hFE);
        // gain 1: one count for two cycles, a turn back cancels the half
        gain = 1; settle;
        repeat (4) cycle(1); check("gain 1, 4 up (FE + 2 wraps to 00)", wheel, 8'h00);
        cycle(1); cycle(0); check("gain 1, a turn back cancels", wheel, 8'h00);
        // gain 2: two a cycle
        gain = 2; settle;
        repeat (3) cycle(1); check("gain 2, 3 up", wheel, 6);
        cycle(0); check("gain 2, 1 down", wheel, 4);

        // reversed: the same turn counts the other way
        gain = 0; rev = 1; settle;
        cycle(1); check("rev, 1 up counts down", wheel, 3);
        rev = 0; settle;

        // the cabinet unplugged: frames stop -> not live, idle outputs
        enable = 0; settle;
        check("not live, Sprint pedal idle", ped_s, 8'hFF);
        check("not live, no switches", {c1, c2, st, tst, hig}, 0);

        if (fails == 0) $display("tb_cab: PASS");
        else            $display("tb_cab: %0d FAIL", fails);
        $finish;
    end
    initial begin #200_000_000; $display("tb_cab: TIMEOUT"); $finish; end
endmodule
