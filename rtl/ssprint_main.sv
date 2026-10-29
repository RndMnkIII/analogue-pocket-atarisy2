//------------------------------------------------------------------------------
// Atari System 2 main board, T11 side (docs/hardware.md sections 2-4): the
// CPU, the slapstic, work RAM, the fixed program ROM (block RAM), the banked
// program ROM (SDRAM through the memory request interface), the bank select
// and interrupt latches, the watchdog, the ADC0809 and the input port, and
// the ports to the video RAMs and the sound board.
//
// Bus timing: block RAM and I/O answer one clock after the request, the
// video RAMs three (their port A is registered twice), SDRAM when it acks.
//------------------------------------------------------------------------------
`default_nettype none

module ssprint_main
    import ssprint_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    input  logic        cen_10m,

    // fixed program ROM load (32 KB, 8000-ffff)
    input  logic        rom_we,
    input  logic  [7:0] cfg_slapstic,       // the image header's slapstic type (105..110)
    input  logic [14:0] rom_waddr,
    input  logic  [7:0] rom_wdata,

    // banked program ROM in SDRAM (memory request interface, read only)
    output logic [24:1] brom_addr,
    output logic        brom_req,
    input  logic [15:0] brom_rdata,
    input  logic        brom_ack,

    // video RAM port (ssprint_video)
    output logic [11:0] vr_addr,
    output logic        vr_we,
    output logic  [1:0] vr_be,
    output logic [15:0] vr_wdata,
    output logic        vr_sel_pal, vr_sel_alpha, vr_sel_mob, vr_sel_pft, vr_sel_pfb,
    input  logic [15:0] vr_rdata,
    output logic        xscroll_we, yscroll_we,
    output logic [15:0] scroll_wdata,
    input  logic        irq_32v, irq_vbl,      // pulses from the video timing

    // sound board
    output logic        snd_cmd_wr,
    output logic  [7:0] snd_cmd,
    output logic        snd_cpu_reset,         // level: 6502 held in reset
    output logic        snd_reset_pulse,       // any write to 15a0
    input  logic        snd_cmd_full,
    input  logic        snd_cmd_rd,            // pulse: the 6502 read the command
    input  logic        snd_resp_full,
    input  logic        snd_resp_wr,           // pulse: the 6502 wrote a response
    input  logic  [7:0] snd_resp,
    output logic        snd_resp_rd,           // pulse: the T11 read it

    // inputs (active high)
    input  logic  [2:0] start,                 // players 1, 2, 3
    input  logic        btn2, btn3,     // APB's buttons (IN0 bits 1 and 3)
    input  logic        service,               // self-test switch on
    input  logic  [7:0] pedal0, pedal1, pedal2,// ADC channels 0-2 (0xff = released)

    output logic        wdog_expired,          // pulse: the watchdog timed out

    // debug
    output logic [15:0] dbg_pc,
    output logic        dbg_done,
    output logic  [1:0] dbg_slap_bank,
    output logic  [3:0] dbg_cp
);
    // ------------------------------------------------------------------------
    // CPU
    // ------------------------------------------------------------------------
    logic [15:0] bus_addr, bus_wdata;
    logic [15:0] bus_rdata_r;                   // the data the sequencer latches (everything but RAM and ROM)
    logic [15:0] ram_q, rom_q;                  // the RAM's and the ROM's own synchronous read ports
    logic        rd_ram, rd_rom;                // which of the three the last access read
    wire  [15:0] bus_rdata /* verilator public_flat_rd */ = rd_ram ? ram_q : rd_rom ? rom_q : bus_rdata_r;
    logic        bus_rd, bus_wr, bus_ack, bus_fetch;
    logic  [1:0] bus_be;
    logic  [3:0] cp /* verilator public_flat_rd */;
    logic  [7:0] dbg_psw;
    logic        dbg_wait;

    t11 cpu (
        .clk(clk), .reset(reset), .cen(cen_10m),
        .bus_addr(bus_addr), .bus_rd(bus_rd), .bus_wr(bus_wr), .bus_be(bus_be), .bus_wdata(bus_wdata),
        .bus_rdata(bus_rdata), .bus_ack(bus_ack), .bus_fetch(bus_fetch),
        .cp(cp),
        .dbg_pc(dbg_pc), .dbg_done(dbg_done), .dbg_psw(dbg_psw), .dbg_wait(dbg_wait)
    );
    assign dbg_cp = cp;
    wire unused_ok = &{1'b0, bus_fetch, dbg_psw, dbg_wait};

    // ------------------------------------------------------------------------
    // slapstic: every bus cycle
    // ------------------------------------------------------------------------
    wire req = bus_rd | bus_wr;
    logic req_d;
    always_ff @(posedge clk) req_d <= req & ~bus_ack;
    wire  bus_strobe = req && !req_d && !bus_ack;
    logic [1:0] slap_bank;
    slapstic slap (.clk(clk), .reset(reset), .chip(cfg_slapstic), .strobe(bus_strobe), .addr(bus_addr), .bank(slap_bank), .init_en(1'b0), .init_bank(2'd0));
    assign dbg_slap_bank = slap_bank;

    // ------------------------------------------------------------------------
    // decode
    // ------------------------------------------------------------------------
    wire [15:0] a = bus_addr;
    wire sel_ram  = (a[15:12] == 4'h0);
    wire sel_pal  = (a[15:10] == 6'b000100);                        // 1000-13ff
    wire sel_io   = (a[15:10] == 6'b000101) || (a[15:11] == 5'b00011); // 1400-1fff
    wire sel_vram = (a[15:13] == 3'b001);                           // 2000-3fff
    wire sel_bnk  = (a[15:14] == 2'b01);                            // 4000-7fff
    wire sel_rom  = a[15];
    wire sel_alpha = sel_vram && slap_bank == 2'd0 && a[12:11] != 2'b11;
    wire sel_mob   = sel_vram && slap_bank == 2'd0 && a[12:11] == 2'b11;
    wire sel_pft   = sel_vram && slap_bank == 2'd2;
    wire sel_pfb   = sel_vram && slap_bank == 2'd3;
    wire sel_video = sel_pal || sel_alpha || sel_mob || sel_pft || sel_pfb;
    // I/O sub-decode (a[10:7] for the 1400-17ff block, a[10] for 1800/1c00)
    wire io_adc    = sel_io && a[11:7] == 5'b01000;                 // 1400-147f: ADC read / bank select write
    wire io_adcs   = sel_io && a[11:7] == 5'b01001;                 // 1480-14ff: ADC start
    wire io_ack0   = sel_io && a[11:5] == 7'b0101100;               // 1580-159f
    wire io_sres   = sel_io && a[11:5] == 7'b0101101;               // 15a0-15bf
    wire io_ack2   = sel_io && a[11:5] == 7'b0101110;               // 15c0-15df
    wire io_ack3   = sel_io && a[11:5] == 7'b0101111;               // 15e0-15ff
    wire io_ien    = sel_io && a[11:7] == 5'b01100;                 // 1600-167f
    wire io_scmd   = sel_io && a[11:7] == 5'b01101;                 // 1680-16ff
    wire io_xs     = sel_io && a[11:7] == 5'b01110;                 // 1700-177f
    wire io_ys     = sel_io && a[11:7] == 5'b01111;                 // 1780-17ff
    wire io_in0    = sel_io && a[11:10] == 2'b10;                   // 1800-1bff
    wire io_sresp  = sel_io && a[11:10] == 2'b11;                   // 1c00-1fff

    // ------------------------------------------------------------------------
    // memories
    // ------------------------------------------------------------------------
    (* ramstyle = "no_rw_check" *) logic [1:0][7:0] ram [0:2047] /* verilator public_flat_rw */;
    (* ramstyle = "no_rw_check" *) logic [1:0][7:0] rom [0:16383] /* verilator public_flat_rw */;
    always_ff @(posedge clk) begin
        if (rom_we) rom[rom_waddr[14:1]][rom_waddr[0]] <= rom_wdata;
    end
    // bank select: b = ((data >> 10) & 0x3f) ^ 3; bank = {b5, b4, b1, b0, b3, b2}
    logic [5:0] bank1, bank2;
    wire  [5:0] bsel = bus_wdata[15:10] ^ 6'b000011;
    wire  [5:0] bnum = {bsel[5], bsel[4], bsel[1], bsel[0], bsel[3], bsel[2]};

    // ------------------------------------------------------------------------
    // interrupts (hardware.md section 3)
    // ------------------------------------------------------------------------
    logic [3:0] irq_en;
    logic       video_int, scan_int, p2portwr, p2portrd;
    assign cp = {video_int, scan_int, p2portwr, p2portrd};

    // ------------------------------------------------------------------------
    // ADC0809: channel latched on the start write, result 66 ADC clocks later
    // (625 kHz = cen_10m / 16)
    // ------------------------------------------------------------------------
    logic [2:0]  adc_chan /* verilator public_flat_rd */;
    logic [7:0]  adc_sar  /* verilator public_flat_rd */;
    logic [10:0] adc_cnt  /* verilator public_flat_rd */;   // conversion countdown in cen_10m ticks (66 x 16 = 1056)
    // bench probes: the T11's ADC strobe and data read cycles
    wire dbg_adc_st /* verilator public_flat_rd */ = bus_strobe && bus_wr && io_adcs && bus_be[0];
    wire dbg_adc_rd /* verilator public_flat_rd */ = bus_strobe && !bus_wr && io_adc;
    wire dbg_io_rd  /* verilator public_flat_rd */ = bus_strobe && !bus_wr && sel_io;   // any T11 read of the I/O page (the bench logs address and data)
    wire [15:0] dbg_io_a /* verilator public_flat_rd */ = a;
    wire  [7:0]  adc_in = (adc_chan == 3'd0) ? pedal0 : (adc_chan == 3'd1) ? pedal1 : (adc_chan == 3'd2) ? pedal2 : 8'hff;

    // ------------------------------------------------------------------------
    // watchdog: 2^20 cen_10m ticks (105 ms) without a kick
    // ------------------------------------------------------------------------
    logic [20:0] wdog;

    // ------------------------------------------------------------------------
    // bus sequencer
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] { B_IDLE, B_V1, B_V2, B_SD, B_DONE } bst_t;
    bst_t bst;
    wire in_idle = (bst == B_IDLE) && req;

    // The RAM and the ROM each have a plain synchronous port, written or read at the first clock of a
    // one-clock access and nothing else (Quartus 25.1 does not infer them as block RAM when the read sits
    // inside the bus sequencer's priority chain). bus_rdata picks the port with rd_ram / rd_rom.
    wire one_clk = in_idle && !sel_bnk && !sel_video;
    always_ff @(posedge clk) begin
        if (one_clk && sel_ram && bus_wr && !reset) begin
            if (bus_be[0]) ram[a[11:1]][0] <= bus_wdata[7:0];
            if (bus_be[1]) ram[a[11:1]][1] <= bus_wdata[15:8];
        end
    end
    always_ff @(posedge clk) begin
        if (one_clk) begin
            ram_q <= ram[a[11:1]];
            rom_q <= rom[a[14:1]];
        end
    end
    // video port: selects while the access is in progress; write only on its first clock
    assign vr_addr  = sel_pal ? {4'd0, a[8:1]} : a[12:1];
    assign vr_be    = bus_be;
    assign vr_wdata = bus_wdata;
    assign vr_we    = in_idle && bus_wr;
    assign vr_sel_pal = sel_pal && req; assign vr_sel_alpha = sel_alpha && req; assign vr_sel_mob = sel_mob && req;
    assign vr_sel_pft = sel_pft && req; assign vr_sel_pfb = sel_pfb && req;
    logic [15:0] xs_reg, ys_reg;                // the scroll registers, byte-merged (COMBINE_DATA)
    logic        xs_sel;
    assign scroll_wdata = xs_sel ? xs_reg : ys_reg;
    assign snd_cmd  = bus_wdata[7:0];
    assign brom_addr = SD_MAIN_BANK + {5'd0, (a[13] ? bank2 : bank1), a[12:1]};
    // IN0: service (1 = off), start 1/2 (active low), P1TALK, P2TALK, start 3 (active low)
    // IN0 (MAME atarisy2 "IN0"): bit 15 self-test, 7/6/3 = start 1/2/3 on the
    // Sprints; APB reads its two buttons on bits 1 and 3 (paperboy's base map
    // has buttons on 7 and 6, which the core does not fit)
    wire [15:0] in0 = {~service, 7'b1111111, ~start[0], ~start[1], snd_cmd_full, snd_resp_full, ~(start[2] | btn3), 1'b1, ~btn2, 1'b1};

    always_ff @(posedge clk) begin
        bus_ack <= 1'b0; xscroll_we <= 1'b0; yscroll_we <= 1'b0; snd_cmd_wr <= 1'b0; snd_reset_pulse <= 1'b0; snd_resp_rd <= 1'b0;
        xs_sel <= io_xs;
        wdog_expired <= 1'b0;
        if (reset) begin
            bst <= B_IDLE; brom_req <= 1'b0; bank1 <= 6'd0; bank2 <= 6'd0; irq_en <= 4'd0;
            video_int <= 1'b0; scan_int <= 1'b0; p2portwr <= 1'b0; p2portrd <= 1'b0;
            snd_cpu_reset <= 1'b1;                       // machine_reset: sound_reset_w(1)
            adc_chan <= '0; adc_sar <= 8'hff; adc_cnt <= '0; wdog <= '0; bus_rdata_r <= '0; rd_ram <= 1'b0; rd_rom <= 1'b0; xs_reg <= '0; ys_reg <= '0; xs_sel <= 1'b0;
        end else begin
            // interrupt sources (level flip-flops clocked by their events)
            if (irq_vbl)     video_int <= irq_en[3];
            if (irq_32v)     scan_int  <= irq_en[2];
            if (snd_resp_wr) p2portwr  <= irq_en[1];
            if (snd_cmd_rd)  p2portrd  <= irq_en[0];
            // ADC conversion
            if (adc_cnt != 11'd0) begin
                if (cen_10m) begin
                    adc_cnt <= adc_cnt - 11'd1;
                    // MAME's ADC0808: the SAR takes the input one ADC clock (16 T11
                    // clocks) after the start and again at the end of the 64-clock
                    // conversion, so a read during the conversion already sees the
                    // new channel's sample -- APB reads its pedal that early
                    if (adc_cnt == 11'd1040 || adc_cnt == 11'd1) adc_sar <= adc_in;
                end
            end
            // watchdog
            if (cen_10m) begin
                if (wdog[20]) begin wdog <= '0; wdog_expired <= 1'b1; end
                else wdog <= wdog + 21'd1;
            end

            case (bst)
                B_IDLE: if (req) begin
                    if (sel_bnk) begin
                        brom_req <= 1'b1; bst <= B_SD;
                    end else if (sel_video) begin
                        bst <= B_V1;
                    end else begin
                        // one-clock devices: answer now
                        bus_ack <= 1'b1; bst <= B_DONE;
                        bus_rdata_r <= 16'hffff;
                        rd_ram <= sel_ram; rd_rom <= sel_rom;     // the RAM and the ROM: ram_q / rom_q (see above)
                        if (io_adc)    bus_rdata_r <= {8'hff, adc_sar};
                        if (io_in0)    bus_rdata_r <= in0;
                        if (io_sresp)  begin bus_rdata_r <= {8'hff, snd_resp}; if (bus_rd) begin p2portwr <= 1'b0; snd_resp_rd <= 1'b1; end end
                        if (bus_wr) begin
                            // the 8-bit registers sit on the even byte (MAME maps them
                            // as byte handlers at the even address): a write to the odd
                            // byte alone -- MOVB to 1681 follows every sound command --
                            // must not reach them
                            if (io_adc) begin if (a[1]) bank2 <= bnum; else bank1 <= bnum; end
                            if (io_adcs && bus_be[0]) begin adc_chan <= a[3:1]; adc_cnt <= 11'd1056; end
                            if (io_ack0 && bus_be[0]) p2portrd <= 1'b0;
                            if (io_sres && bus_be[0]) begin snd_cpu_reset <= bus_wdata[0]; snd_reset_pulse <= 1'b1; end
                            if (io_ack2 && bus_be[0]) scan_int <= 1'b0;
                            if (io_ack3 && bus_be[0]) video_int <= 1'b0;
                            if (io_ien && bus_be[0])  irq_en <= bus_wdata[3:0];
                            if (io_scmd && bus_be[0]) snd_cmd_wr <= 1'b1;
                            if (io_xs) begin
                                if (bus_be[0]) xs_reg[7:0]  <= bus_wdata[7:0];
                                if (bus_be[1]) xs_reg[15:8] <= bus_wdata[15:8];
                                xscroll_we <= 1'b1;
                            end
                            if (io_ys) begin
                                if (bus_be[0]) ys_reg[7:0]  <= bus_wdata[7:0];
                                if (bus_be[1]) ys_reg[15:8] <= bus_wdata[15:8];
                                yscroll_we <= 1'b1;
                            end
                            if (io_in0 && bus_be[0]) wdog <= '0;
                        end
                    end
                end
                B_V1: bst <= B_V2;
                B_V2: begin bus_rdata_r <= vr_rdata; rd_ram <= 1'b0; rd_rom <= 1'b0; bus_ack <= 1'b1; bst <= B_DONE; end
                B_SD: if (brom_ack) begin bus_rdata_r <= brom_rdata; rd_ram <= 1'b0; rd_rom <= 1'b0; brom_req <= 1'b0; bus_ack <= 1'b1; bst <= B_DONE; end
                B_DONE: bst <= B_IDLE;
                default: bst <= B_IDLE;
            endcase
        end
    end
    wire unused_ram = &{1'b0, a[0]};
endmodule

`default_nettype wire
