//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
// SPDX-FileType: SOURCE
// SPDX-FileCopyrightText: (c) 2023, OpenGateware authors and contributors
//------------------------------------------------------------------------------
//
// Copyright (c) 2023, Marcus Andrade <marcus@opengateware.org>
// Copyright (c) 2022, Analogue Enterprises Limited
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//------------------------------------------------------------------------------
// Platform Specific top-level -- Super Sprint (Atari Games, 1986)
// Instantiated by the real top-level: apf_top
//
// The machine (ssprint_core) is platform-agnostic; this file is the APF glue:
// bridge, data slots, the interact menu, controls, video and audio hand-off,
// and the SDRAM pins. The banked program ROM and the graphics ROMs live in
// SDRAM; everything else is block RAM.
//
// The screen is a 512x384 progressive raster at 60.1 Hz, not rotated.
//------------------------------------------------------------------------------

`default_nettype none

module core_top
    #(
         //! ------------------------------------------------------------------------
         //! System Configuration Parameters
         //! ------------------------------------------------------------------------
         // Memory
         parameter USE_SDRAM    = 1,       //! Enable SDRAM (banked program ROM, graphics)
         parameter USE_SRAM     = 0,       //! Enable SRAM
         parameter USE_CRAM0    = 0,       //! Enable Cellular RAM #1
         parameter USE_CRAM1    = 0,       //! Enable Cellular RAM #2
         // Cartridge port
         parameter USE_ANALOGIZER = 1,     //! Analogizer adapter (docs/analogizer.md)
         // Video
         parameter BPP_R        = 8,       //! Bits Per Pixel Red
         parameter BPP_G        = 8,       //! Bits Per Pixel Green
         parameter BPP_B        = 8,       //! Bits Per Pixel Blue
         // Audio
         parameter AUDIO_DW     = 16,      //! Audio Bits
         parameter AUDIO_S      = 1,       //! Signed Audio
         parameter STEREO       = 1,       //! Stereo Output
         parameter AUDIO_MIX    = 0,       //! [0] No Mix | [1] 25% | [2] 50% | [3] 100% (mono)
         // Gamepad/Joystick
         parameter JOY_PADS     = 2,       //! Gamepads through the framework mapper (players 1, 2); player 3 reads cont3 directly
         parameter JOY_ALT      = 0,       //! Players have their own controls
         // Data I/O - [MPU -> FPGA]
         parameter DIO_MASK     = 4'h0,    //! Upper 4 bits of address
         parameter DIO_AW       = 27,      //! Address Width
         parameter DIO_DW       = 8,       //! Data Width (8 or 16 bits)
         parameter DIO_DELAY    = 7,       //! Number of clock cycles to delay each write output
         parameter DIO_HOLD     = 4,       //! Number of clock cycles to hold the ioctl_wr signal high
         // HiScore I/O - [MPU <-> FPGA]
         parameter HS_AW        = 16,      //! Max size of game RAM address for highscores
         parameter HS_SW        = 8,       //! Max size of capture RAM For highscore data (default 8 = 256 bytes max)
         parameter HS_CFG_AW    = 2,       //! Max size of RAM address for highscore.dat entries (default 4 = 16 entries max)
         parameter HS_CFG_LW    = 2,       //! Max size of length for each highscore.dat entries (default 1 = 256 bytes max)
         parameter HS_CONFIG    = 2,       //! Dataslot index for config transfer
         parameter HS_DATA      = 3,       //! Dataslot index for save data transfer
         parameter HS_NVM_SZ    = 32'd93,  //! Number bytes required for Save
         parameter HS_MASK      = 4'h1,    //! Upper 4 bits of address
         parameter HS_WR_DELAY  = 4,       //! Number of clock cycles to delay each write output
         parameter HS_WR_HOLD   = 1,       //! Number of clock cycles to hold the nvram_wr signal high
         parameter HS_RD_DELAY  = 4,       //! Number of clock cycles it takes for a read to complete
         // Save I/O - [MPU <-> FPGA]
         parameter SIO_MASK     = 4'h1,    //! Upper 4 bits of address
         parameter SIO_AW       = 27,      //! Address Width
         parameter SIO_DW       = 8,       //! Data Width (8 or 16 bits)
         parameter SIO_WR_DELAY = 4,       //! Number of clock cycles to delay each write output
         parameter SIO_WR_HOLD  = 1,       //! Number of clock cycles to hold the nvram_wr signal high
         parameter SIO_RD_DELAY = 4,       //! Number of clock cycles it takes for a read to complete
         parameter SIO_SAVE_IDX = 2        //! Dataslot index for save data transfer
     ) (
         //! --------------------------------------------------------------------
         //! Clock Inputs 74.25mhz.
         //! Not Phase Aligned, Treat These Domains as Asynchronous
         //! --------------------------------------------------------------------
         input wire          clk_74a, // mainclk1
         input wire          clk_74b, // mainclk1

         //! --------------------------------------------------------------------
         //! Cartridge Interface
         //! --------------------------------------------------------------------
         // switches between 3.3v and 5v mechanically
         // output enable for multibit translators controlled by pic32
         // GBA AD[15:8]
         inout  wire   [7:0] cart_tran_bank2,
         output wire         cart_tran_bank2_dir,
         // GBA AD[7:0]
         inout  wire   [7:0] cart_tran_bank3,
         output wire         cart_tran_bank3_dir,
         // GBA A[23:16]
         inout  wire   [7:0] cart_tran_bank1,
         output wire         cart_tran_bank1_dir,
         // GBA [7] PHI#
         // GBA [6] WR#
         // GBA [5] RD#
         // GBA [4] CS1#/CS#
         //     [3:0] unwired
         inout  wire   [7:4] cart_tran_bank0,
         output wire         cart_tran_bank0_dir,
         // GBA CS2#/RES#
         inout  wire         cart_tran_pin30,
         output wire         cart_tran_pin30_dir,
         // when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
         // the goal is that when unconfigured, the FPGA weak pullups won't interfere.
         // thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
         // and general IO drive this pin.
         output wire         cart_pin30_pwroff_reset,
         // GBA IRQ/DRQ
         inout  wire         cart_tran_pin31,
         output wire         cart_tran_pin31_dir,

         //! --------------------------------------------------------------------
         //! Infrared
         //! --------------------------------------------------------------------
         input  wire         port_ir_rx,
         output wire         port_ir_tx,
         output wire         port_ir_rx_disable,

         //! --------------------------------------------------------------------
         //! GBA link port
         //! --------------------------------------------------------------------
         inout  wire         port_tran_si,
         output wire         port_tran_si_dir,
         inout  wire         port_tran_so,
         output wire         port_tran_so_dir,
         inout  wire         port_tran_sck,
         output wire         port_tran_sck_dir,
         inout  wire         port_tran_sd,
         output wire         port_tran_sd_dir,

         //! --------------------------------------------------------------------
         //! Cellular PSRAM 0 and 1, two chips (64mbit x2 dual die per chip)
         //! --------------------------------------------------------------------
         output wire [21:16] cram0_a,
         inout  wire  [15:0] cram0_dq,
         input  wire         cram0_wait,
         output wire         cram0_clk,
         output wire         cram0_adv_n,
         output wire         cram0_cre,
         output wire         cram0_ce0_n,
         output wire         cram0_ce1_n,
         output wire         cram0_oe_n,
         output wire         cram0_we_n,
         output wire         cram0_ub_n,
         output wire         cram0_lb_n,

         output wire [21:16] cram1_a,
         inout  wire  [15:0] cram1_dq,
         input  wire         cram1_wait,
         output wire         cram1_clk,
         output wire         cram1_adv_n,
         output wire         cram1_cre,
         output wire         cram1_ce0_n,
         output wire         cram1_ce1_n,
         output wire         cram1_oe_n,
         output wire         cram1_we_n,
         output wire         cram1_ub_n,
         output wire         cram1_lb_n,

         //! --------------------------------------------------------------------
         //! SDRAM, 512mbit 16bit
         //! --------------------------------------------------------------------
         output wire  [12:0] dram_a,        // Address bus
         output wire   [1:0] dram_ba,       // Bank select (single bits)
         inout  wire  [15:0] dram_dq,       // Bidirectional data bus
         output wire   [1:0] dram_dqm,      // High/low byte mask
         output wire         dram_clk,      // Chip clock
         output wire         dram_cke,      // Clock enable
         output wire         dram_ras_n,    // Select row address (active low)
         output wire         dram_cas_n,    // Select column address (active low)
         output wire         dram_we_n,     // Write enable (active low)

         //! --------------------------------------------------------------------
         //! SRAM, 1mbit 16bit
         //! --------------------------------------------------------------------
         output wire  [16:0] sram_a,        // Address bus
         inout  wire  [15:0] sram_dq,       // Bidirectional data bus
         output wire         sram_oe_n,     // Output enable
         output wire         sram_we_n,     // Write enable
         output wire         sram_ub_n,     // Upper Byte Mask
         output wire         sram_lb_n,     // Lower Byte Mask

         //! --------------------------------------------------------------------
         //! vblank driven by dock for sync in a certain mode
         //! --------------------------------------------------------------------
         input  wire         vblank,

         //! --------------------------------------------------------------------
         //! I/O to 6515D breakout USB UART
         //! --------------------------------------------------------------------
         output wire         dbg_tx,
         input  wire         dbg_rx,

         //! --------------------------------------------------------------------
         //! I/O pads near jtag connector user can solder to
         //! --------------------------------------------------------------------
         output wire         user1,
         input  wire         user2,

         //! --------------------------------------------------------------------
         //! RFU internal i2c bus
         //! --------------------------------------------------------------------
         inout  wire         aux_sda,
         output wire         aux_scl,

         //! --------------------------------------------------------------------
         //! RFU, do not use !!!
         //! --------------------------------------------------------------------
         output wire         vpll_feed,

         //! --------------------------------------------------------------------
         //! Logical Connections ////////////////////////////////////////////////
         //! --------------------------------------------------------------------

         //! --------------------------------------------------------------------
         //! Video Output to Scaler
         //! --------------------------------------------------------------------
         output wire  [23:0] video_rgb,
         output wire         video_rgb_clock,
         output wire         video_rgb_clock_90,
         output wire         video_hs,
         output wire         video_vs,
         output wire         video_de,
         output wire         video_skip,

         //! --------------------------------------------------------------------
         //! Audio
         //! --------------------------------------------------------------------
         output wire         audio_mclk,
         output wire         audio_lrck,
         output wire         audio_dac,
         input  wire         audio_adc,

         //! --------------------------------------------------------------------
         //! Bridge Bus Connection (synchronous to clk_74a)
         //! --------------------------------------------------------------------
         output wire         bridge_endian_little,
         input  wire  [31:0] bridge_addr,
         input  wire         bridge_rd,
         output reg   [31:0] bridge_rd_data,
         input  wire         bridge_wr,
         input  wire  [31:0] bridge_wr_data,

         //! --------------------------------------------------------------------
         //! Controller Data
         //! --------------------------------------------------------------------
         input  wire  [31:0] cont1_key,
         input  wire  [31:0] cont2_key,
         input  wire  [31:0] cont3_key,
         input  wire  [31:0] cont4_key,
         input  wire  [31:0] cont1_joy,
         input  wire  [31:0] cont2_joy,
         input  wire  [31:0] cont3_joy,
         input  wire  [31:0] cont4_joy,
         input  wire  [15:0] cont1_trig,
         input  wire  [15:0] cont2_trig,
         input  wire  [15:0] cont3_trig,
         input  wire  [15:0] cont4_trig
     );

    // not using the IR port, so turn off both the LED, and
    // disable the receive circuit to save power
    assign port_ir_tx         = 0;
    assign port_ir_rx_disable = 1;

    // bridge endianness
    assign bridge_endian_little = 0;

    // cart is unused unless the Analogizer has it (pocket_analogizer, below,
    // which holds these same levels until its menu entry enables it), so
    // set all level translators accordingly
    // directions are 0:IN, 1:OUT
    generate
        if(USE_ANALOGIZER == 0) begin
            assign cart_tran_bank3         = 8'hzz;
            assign cart_tran_bank3_dir     = 1'b0;
            assign cart_tran_bank2         = 8'hzz;
            assign cart_tran_bank2_dir     = 1'b0;
            assign cart_tran_bank1         = 8'hzz;
            assign cart_tran_bank1_dir     = 1'b0;
            assign cart_tran_bank0         = 4'hf;
            assign cart_tran_bank0_dir     = 1'b1;
            assign cart_tran_pin30         = 1'b0;  // reset or cs2, we let the hw control it by itself
            assign cart_tran_pin30_dir     = 1'bz;
            assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
            assign cart_tran_pin31         = 1'bz;  // input
            assign cart_tran_pin31_dir     = 1'b0;  // input
        end
    endgenerate

    // link port is input only
    assign port_tran_so      = 1'bz;
    assign port_tran_so_dir  = 1'b0; // SO is output only
    assign port_tran_si      = 1'bz;
    assign port_tran_si_dir  = 1'b0; // SI is input only
    assign port_tran_sck     = 1'bz;
    assign port_tran_sck_dir = 1'b0; // clock direction can change
    assign port_tran_sd      = 1'bz;
    assign port_tran_sd_dir  = 1'b0; // SD is input and not used

    assign dbg_tx    = 1'bZ;
    assign user1     = 1'bZ;
    assign aux_scl   = 1'bZ;
    assign vpll_feed = 1'bZ;

    // Tie off the memory the pins not being used
    generate
        if(USE_CRAM0 == 0) begin
            assign cram0_a     = 'h0;
            assign cram0_dq    = {16{1'bZ}};
            assign cram0_clk   = 0;
            assign cram0_adv_n = 1;
            assign cram0_cre   = 0;
            assign cram0_ce0_n = 1;
            assign cram0_ce1_n = 1;
            assign cram0_oe_n  = 1;
            assign cram0_we_n  = 1;
            assign cram0_ub_n  = 1;
            assign cram0_lb_n  = 1;
        end

        if(USE_CRAM1 == 0) begin
            assign cram1_a     = 'h0;
            assign cram1_dq    = {16{1'bZ}};
            assign cram1_clk   = 0;
            assign cram1_adv_n = 1;
            assign cram1_cre   = 0;
            assign cram1_ce0_n = 1;
            assign cram1_ce1_n = 1;
            assign cram1_oe_n  = 1;
            assign cram1_we_n  = 1;
            assign cram1_ub_n  = 1;
            assign cram1_lb_n  = 1;
        end

        if(USE_SDRAM == 0) begin
            assign dram_a     = 'h0;
            assign dram_ba    = 'h0;
            assign dram_dq    = {16{1'bZ}};
            assign dram_dqm   = 'h0;
            assign dram_clk   = 'h0;
            assign dram_cke   = 'h0;
            assign dram_ras_n = 'h1;
            assign dram_cas_n = 'h1;
            assign dram_we_n  = 'h1;
        end

        if(USE_SRAM == 0) begin
            assign sram_a    = 'h0;
            assign sram_dq   = {16{1'bZ}};
            assign sram_oe_n = 1;
            assign sram_we_n = 1;
            assign sram_ub_n = 1;
            assign sram_lb_n = 1;
        end
    endgenerate

    //! ------------------------------------------------------------------------
    //! Host/Target Command Handler
    //! ------------------------------------------------------------------------
    wire        reset_n;  // driven by host commands, can be used as core-wide reset
    wire [31:0] cmd_bridge_rd_data;

    // bridge host commands
    // synchronous to clk_74a
    wire        status_boot_done  = pll_core_locked_s;
    wire        status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire        status_running    = reset_n;           // we are running as soon as reset_n goes high

    wire        dataslot_requestread;
    wire [15:0] dataslot_requestread_id;
    wire        dataslot_requestread_ack = 1;
    wire        dataslot_requestread_ok  = 1;

    wire        dataslot_requestwrite;
    wire [15:0] dataslot_requestwrite_id;
    wire [31:0] dataslot_requestwrite_size;
    wire        dataslot_requestwrite_ack = 1;
    wire        dataslot_requestwrite_ok  = 1;

    wire        dataslot_update;
    wire [15:0] dataslot_update_id;
    wire [31:0] dataslot_update_size;

    wire        dataslot_allcomplete;

    wire [31:0] rtc_epoch_seconds;
    wire [31:0] rtc_date_bcd;
    wire [31:0] rtc_time_bcd;
    wire        rtc_valid;

    wire        savestate_supported;
    wire [31:0] savestate_addr;
    wire [31:0] savestate_size;
    wire [31:0] savestate_maxloadsize;

    wire        savestate_start;
    wire        savestate_start_ack;
    wire        savestate_start_busy;
    wire        savestate_start_ok;
    wire        savestate_start_err;

    wire        savestate_load;
    wire        savestate_load_ack;
    wire        savestate_load_busy;
    wire        savestate_load_ok;
    wire        savestate_load_err;

    wire        osnotify_inmenu;

    // bridge target commands
    // synchronous to clk_74a
    reg         target_dataslot_read;
    reg         target_dataslot_write;
    reg         target_dataslot_getfile;    // require additional param/resp structs to be mapped
    reg         target_dataslot_openfile;   // require additional param/resp structs to be mapped

    wire        target_dataslot_ack;
    wire        target_dataslot_done;
    wire  [2:0] target_dataslot_err;

    reg  [15:0] target_dataslot_id;
    reg  [31:0] target_dataslot_slotoffset;
    reg  [31:0] target_dataslot_bridgeaddr;
    reg  [31:0] target_dataslot_length;

    wire [31:0] target_buffer_param_struct; // to be mapped/implemented when using some Target commands
    wire [31:0] target_buffer_resp_struct;  // to be mapped/implemented when using some Target commands

    // bridge data slot access
    // synchronous to clk_74a
    logic  [9:0] datatable_addr;
    logic        datatable_wren;
    logic [31:0] datatable_data;
    wire  [31:0] datatable_q;
    // the save slot's size for the APF, written continuously as the NES core
    // does (slot index 1 -> size entry 1*2+1): the 512-byte EEPROM
    always_ff @(posedge clk_74a) begin
        datatable_wren <= 1'b1;
        datatable_addr <= 10'd3;
        datatable_data <= 32'h200;
    end

    core_bridge_cmd icb
    (
        .clk                        ( clk_74a                    ),
        .reset_n                    ( reset_n                    ),

        .bridge_endian_little       ( bridge_endian_little       ),
        .bridge_addr                ( bridge_addr                ),
        .bridge_rd                  ( bridge_rd                  ),
        .bridge_rd_data             ( cmd_bridge_rd_data         ),
        .bridge_wr                  ( bridge_wr                  ),
        .bridge_wr_data             ( bridge_wr_data             ),

        .status_boot_done           ( status_boot_done           ),
        .status_setup_done          ( status_setup_done          ),
        .status_running             ( status_running             ),

        .dataslot_requestread       ( dataslot_requestread       ),
        .dataslot_requestread_id    ( dataslot_requestread_id    ),
        .dataslot_requestread_ack   ( dataslot_requestread_ack   ),
        .dataslot_requestread_ok    ( dataslot_requestread_ok    ),

        .dataslot_requestwrite      ( dataslot_requestwrite      ),
        .dataslot_requestwrite_id   ( dataslot_requestwrite_id   ),
        .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
        .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack  ),
        .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok   ),

        .dataslot_update            ( dataslot_update            ),
        .dataslot_update_id         ( dataslot_update_id         ),
        .dataslot_update_size       ( dataslot_update_size       ),

        .dataslot_allcomplete       ( dataslot_allcomplete       ),

        .rtc_epoch_seconds          ( rtc_epoch_seconds          ),
        .rtc_date_bcd               ( rtc_date_bcd               ),
        .rtc_time_bcd               ( rtc_time_bcd               ),
        .rtc_valid                  ( rtc_valid                  ),

        .savestate_supported        ( savestate_supported        ),
        .savestate_addr             ( savestate_addr             ),
        .savestate_size             ( savestate_size             ),
        .savestate_maxloadsize      ( savestate_maxloadsize      ),

        .savestate_start            ( savestate_start            ),
        .savestate_start_ack        ( savestate_start_ack        ),
        .savestate_start_busy       ( savestate_start_busy       ),
        .savestate_start_ok         ( savestate_start_ok         ),
        .savestate_start_err        ( savestate_start_err        ),

        .savestate_load             ( savestate_load             ),
        .savestate_load_ack         ( savestate_load_ack         ),
        .savestate_load_busy        ( savestate_load_busy        ),
        .savestate_load_ok          ( savestate_load_ok          ),
        .savestate_load_err         ( savestate_load_err         ),

        .osnotify_inmenu            ( osnotify_inmenu            ),

        .target_dataslot_read       ( target_dataslot_read       ),
        .target_dataslot_write      ( target_dataslot_write      ),
        .target_dataslot_getfile    ( target_dataslot_getfile    ),
        .target_dataslot_openfile   ( target_dataslot_openfile   ),

        .target_dataslot_ack        ( target_dataslot_ack        ),
        .target_dataslot_done       ( target_dataslot_done       ),
        .target_dataslot_err        ( target_dataslot_err        ),

        .target_dataslot_id         ( target_dataslot_id         ),
        .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
        .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
        .target_dataslot_length     ( target_dataslot_length     ),

        .target_buffer_param_struct ( target_buffer_param_struct ),
        .target_buffer_resp_struct  ( target_buffer_resp_struct  ),

        .datatable_addr             ( datatable_addr             ),
        .datatable_wren             ( datatable_wren             ),
        .datatable_data             ( datatable_data             ),
        .datatable_q                ( datatable_q                )
    );

    //! END OF APF /////////////////////////////////////////////////////////////

    //! ////////////////////////////////////////////////////////////////////////
    //! @ System Modules
    //! ////////////////////////////////////////////////////////////////////////

    //! ------------------------------------------------------------------------
    //! APF Bridge Read Data
    //! ------------------------------------------------------------------------
    wire [31:0] int_bridge_rd_data;
    wire [31:0] ana_bridge_rd_data;
    wire [31:0] nvm_bridge_rd_data_s;

    // Not 0x10000000: a slot there hangs the Pocket at the end of loading as
    // soon as a file exists for it, with or without any hardware behind the
    // address (bisected on the panel, v0.1.1); 0x20000000, where the NES core
    // keeps its save, loads. And the APF takes the slot's size for the
    // write-back from the core's data-slot table, which the NES core writes
    // and this one did not: entry index*2+1 for slot index 1, 0x400 bytes.
    //
    // The save slot (data.json slot 1, 512 bytes at 0x20000000): its own loader,
    // since the platform's accepts only the ROM's address range, and the
    // unloader that answers the Pocket's read-back at shutdown. The unloader
    // delivers its word in the bridge clock domain already.
    // NV_SLOT: 0 = no save-slot hardware at all (a bisection build: the slot
    // written by the Pocket hung the load), 1 = loader only, 2 = loader and
    // unloader (the real thing)
    localparam NV_SLOT = 2;
    wire        nv_dl_download, nv_dl_wr;
    wire  [8:0] nv_dl_addr;
    wire  [7:0] nv_dl_data;
    wire [15:0] nv_dl_index;
    generate if (NV_SLOT >= 1) begin : g_nv_load
    data_io #(.MASK(4'h2), .AW(9), .DW(8), .DELAY(DIO_DELAY), .HOLD(DIO_HOLD)) pocket_nv_io
    (
        .clk_74a(clk_74a), .clk_memory(clk_sys),
        .dataslot_requestwrite(dataslot_requestwrite), .dataslot_requestwrite_id(dataslot_requestwrite_id),
        .dataslot_allcomplete(dataslot_allcomplete),
        .bridge_endian_little(bridge_endian_little), .bridge_addr(bridge_addr),
        .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
        .ioctl_download(nv_dl_download), .ioctl_index(nv_dl_index), .ioctl_wr(nv_dl_wr),
        .ioctl_addr(nv_dl_addr), .ioctl_data(nv_dl_data)
    );
    end else begin : g_nv_noload
        assign nv_dl_download = 1'b0; assign nv_dl_wr = 1'b0; assign nv_dl_addr = '0;
        assign nv_dl_data = '0; assign nv_dl_index = '0;
    end endgenerate
    wire        nv_rd_en;
    wire  [8:0] nv_rd_addr;
    wire  [7:0] nv_rd_data;
    generate if (NV_SLOT >= 2) begin : g_nv_unload
    data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2), .ADDRESS_SIZE(9), .READ_MEM_CLOCK_DELAY(4), .INPUT_WORD_SIZE(1)) pocket_nv_unload
    (
        .clk_74a(clk_74a), .clk_memory(clk_sys),
        .bridge_rd(bridge_rd), .bridge_endian_little(bridge_endian_little), .bridge_addr(bridge_addr),
        .bridge_rd_data(nvm_bridge_rd_data_s),
        .read_en(nv_rd_en), .read_addr(nv_rd_addr), .read_data(nv_rd_data)
    );
    end else begin : g_nv_nounload
        assign nvm_bridge_rd_data_s = 32'd0; assign nv_rd_en = 1'b0; assign nv_rd_addr = '0;
    end endgenerate
    // Saving is the core's doing, not the exit flush's: the Pocket only writes a
    // nonvolatile slot back onto a file it loaded, so a first save would never
    // be created (bisected on the panel, v0.1.1). Instead, whenever the game
    // has written its EEPROM, two seconds after the last write -- or at once
    // when the Pocket menu opens -- the core commands the APF to write slot 1
    // from bridge address 0x20000000, 512 bytes; the APF reads that range
    // through the unloader above and creates or updates ssprint.sav.
    wire        po_nv_dirty;                // toggles on every EEPROM write
    wire        nv_dirty_s;
    synch_3 sync_nvd(po_nv_dirty, nv_dirty_s, clk_74a);
    wire        inmenu_s;
    synch_3 sync_inmenu(osnotify_inmenu, inmenu_s, clk_74a);
    reg         nv_dirty_d = 1'b0, inmenu_d = 1'b0, allc_d = 1'b0;
    reg         nv_pending = 1'b0;          // written since the last save command
    reg  [27:0] nv_timer   = 28'd0;         // clk_74a cycles since the last write / save
    reg  [1:0]  nv_state   = 2'd0;          // 0 idle, 1 command raised, 2 waiting for done
    reg  [28:0] boot_timer = 29'd0;         // cycles since loading completed
    // dataslot_allcomplete cannot gate the saves: the bridge clears it when
    // the APF reads the slot to execute OUR write command, and raises it
    // again only on the host's own all-complete, after the initial load --
    // so gating on it allowed exactly one save per session (measured on the
    // panel). Latch its first rising edge instead.
    reg         nv_loaded  = 1'b0;
    localparam  NV_SETTLE  = 28'd148_500_000;   // 2 s at 74.25 MHz
    localparam  NV_BOOT    = 29'd371_250_000;   // 5 s: one save after loading regardless
    // status for the overlay: 0 a write was seen (sticky), 1 pending, 2 loaded
    // latch, 3 ack seen (sticky), 4 last error nonzero, 5-7 completed saves
    reg  [2:0]  nv_saves = 3'd0;
    reg  [7:0]  nv_stat = 8'd0;
    always_ff @(posedge clk_74a) begin
        nv_dirty_d <= nv_dirty_s; inmenu_d <= inmenu_s; allc_d <= dataslot_allcomplete;
        target_dataslot_read     <= 1'b0;
        target_dataslot_getfile  <= 1'b0;
        target_dataslot_openfile <= 1'b0;
        target_dataslot_id         <= 16'd2;   //! the save slot; slot 0 is the instance JSON, slot 1 the ROM
        target_dataslot_slotoffset <= 32'd0;
        target_dataslot_bridgeaddr <= 32'h2000_0000;
        target_dataslot_length     <= 32'h200;
        if (dataslot_allcomplete) nv_loaded <= 1'b1;
        if (nv_loaded && boot_timer != NV_BOOT) boot_timer <= boot_timer + 29'd1;
        if (nv_dirty_s != nv_dirty_d) begin nv_pending <= 1'b1; nv_timer <= 28'd0; nv_stat[0] <= 1'b1; end
        else if (nv_timer != NV_SETTLE) nv_timer <= nv_timer + 28'd1;
        nv_stat[1] <= nv_pending; nv_stat[2] <= nv_loaded; nv_stat[7:5] <= nv_saves;
        case (nv_state)
            2'd0: begin
                target_dataslot_write <= 1'b0;
                if ((nv_pending && nv_loaded && (nv_timer == NV_SETTLE || (inmenu_s && !inmenu_d)))
                    || (boot_timer == NV_BOOT - 29'd1)) begin
                    target_dataslot_write <= 1'b1;      // rising edge starts the command
                    nv_pending <= 1'b0;
                    nv_state   <= 2'd1;
                end
            end
            2'd1: if (target_dataslot_ack) begin target_dataslot_write <= 1'b0; nv_stat[3] <= 1'b1; nv_state <= 2'd2; end
            2'd2: if (target_dataslot_done) begin nv_stat[4] <= (target_dataslot_err != 3'd0); nv_saves <= nv_saves + 3'd1; nv_state <= 2'd0; end
            default: nv_state <= 2'd0;
        endcase
    end
    wire [7:0] nv_stat_s;
    synch_3 #(.WIDTH(8)) sync_nvstat(nv_stat, nv_stat_s, clk_sys);
    // the core's second NVRAM port: a load write wins, else the unloader's read
    wire       po_nv_we   = nv_dl_download && nv_dl_index == 16'h1 && nv_dl_wr;
    wire  [8:0] po_nv_addr = po_nv_we ? nv_dl_addr : nv_rd_addr;

    always_comb begin
        casex(bridge_addr)
            32'h2xxxxxxx: begin bridge_rd_data <= nvm_bridge_rd_data_s; end // the save slot, every word of it
            32'hF0000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Reset
            32'hF0000010: begin bridge_rd_data <= int_bridge_rd_data;   end // Service Mode Switch
            32'hF1000000: begin bridge_rd_data <= int_bridge_rd_data;   end // DIP Switches
            32'hF2000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Modifiers
            32'hF3000000: begin bridge_rd_data <= int_bridge_rd_data;   end // A/V Filters
            32'hF4000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Extra DIP Switches
            32'hF7xxxxxx: begin bridge_rd_data <= ana_bridge_rd_data;   end // Analogizer settings (menu)
            32'hF8xxxxxx: begin bridge_rd_data <= cmd_bridge_rd_data;   end // APF Bridge (Reserved)
            32'hFA000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Status Low  [31:0]
            32'hFB000000: begin bridge_rd_data <= int_bridge_rd_data;   end // Status High [63:32]
            default:      begin bridge_rd_data <= 0;                    end
        endcase
    end

    //! ------------------------------------------------------------------------
    //! Pause Core (Analogue OS Menu/Module Request)
    //! ------------------------------------------------------------------------
    wire pause_core, pause_req;

    pause_crtl core_pause
    (
        .clk_sys    ( clk_sys         ),
        .os_inmenu  ( osnotify_inmenu ),
        .pause_req  ( pause_req       ),
        .pause_core ( pause_core      )
    );

    //! ------------------------------------------------------------------------
    //! Interact: Dip Switches, Modifiers, Filters and Reset
    //! ------------------------------------------------------------------------
    wire  [7:0] dip_sw0, dip_sw1, dip_sw2, dip_sw3;
    wire  [7:0] ext_sw0, ext_sw1, ext_sw2, ext_sw3;
    wire  [7:0] mod_sw0, mod_sw1, mod_sw2, mod_sw3;
    wire  [3:0] scnl_sw, smask_sw, afilter_sw, vol_att;
    wire [63:0] status;
    wire        reset_sw, svc_sw, nvclear_sw;

    interact pocket_interact
    (
        // Clocks and Reset
        .clk_74a          ( clk_74a            ),
        .clk_sync         ( clk_sys            ),
        .reset_n          ( reset_n            ),
        // Pocket Bridge
        .bridge_addr      ( bridge_addr        ),
        .bridge_wr        ( bridge_wr          ),
        .bridge_wr_data   ( bridge_wr_data     ),
        .bridge_rd        ( bridge_rd          ),
        .bridge_rd_data   ( int_bridge_rd_data ),
        // Service Mode Switch
        .svc_sw           ( svc_sw             ),
        // DIP Switches
        .dip_sw0          ( dip_sw0            ),
        .dip_sw1          ( dip_sw1            ),
        .dip_sw2          ( dip_sw2            ),
        .dip_sw3          ( dip_sw3            ),
        // Extra DIP Switches
        .ext_sw0          ( ext_sw0            ),
        .ext_sw1          ( ext_sw1            ),
        .ext_sw2          ( ext_sw2            ),
        .ext_sw3          ( ext_sw3            ),
        // Modifiers
        .mod_sw0          ( mod_sw0            ),
        .mod_sw1          ( mod_sw1            ),
        .mod_sw2          ( mod_sw2            ),
        .mod_sw3          ( mod_sw3            ),
        // Status (Legacy Support)
        .status           ( status             ),
        // Filters Switches
        .scnl_sw          ( scnl_sw            ),
        .smask_sw         ( smask_sw           ),
        .afilter_sw       ( afilter_sw         ),
        .vol_att          ( vol_att            ),
        // Reset Switch
        .reset_sw         ( reset_sw           ),
        .nvclear_sw       ( nvclear_sw         )
    );

    //! ------------------------------------------------------------------------
    //! Audio
    //! ------------------------------------------------------------------------
    wire [AUDIO_DW-1:0] core_snd_l, core_snd_r; // Audio Mono/Left/Right

    audio_mixer #(.DW(AUDIO_DW),.STEREO(STEREO),.IIR(0)) pocket_audio_mixer   // IIR low-pass compiled out: 669 ALUTs, see docs/hardware.md 7b
    (
        // Clocks and Reset
        .clk_74b    ( clk_74b    ),
        .reset      ( reset_sw   ),
        // Controls
        .afilter_sw ( afilter_sw ),
        .vol_att    ( vol_att    ),
        .mix        ( AUDIO_MIX  ),
        .pause_core ( pause_core ),
        // Audio From Core
        .is_signed  ( AUDIO_S    ),
        .core_l     ( core_snd_l ),
        .core_r     ( core_snd_r ),
        // I2S
        .audio_mclk ( audio_mclk ),
        .audio_lrck ( audio_lrck ),
        .audio_dac  ( audio_dac  )
    );

    //! ------------------------------------------------------------------------
    //! Video
    //! ------------------------------------------------------------------------
    wire       [2:0] video_preset;     // Video Preset Configuration
    wire [BPP_R-1:0] core_r;           // Video Red
    wire [BPP_G-1:0] core_g;           // Video Green
    wire [BPP_B-1:0] core_b;           // Video Blue
    wire             core_hs, core_hb; // Horizontal Sync/Blank
    wire             core_vs, core_vb; // Vertical Sync/Blank
    wire             core_de;          // Display Enable

    assign core_hb = 1'b0;
    assign core_vb = 1'b0;

    video_mixer #(.RW(BPP_R),.GW(BPP_G),.BW(BPP_B)) pocket_video_mixer
    (
        // Clocks
        .clk_74a                  ( clk_74a                  ),
        .clk_sys                  ( clk_sys                  ),
        .clk_vid                  ( clk_vid                  ),
        .clk_vid_90deg            ( clk_vid_90deg            ),
        // Input Controls
        .video_preset             ( video_preset             ),
        .scnl_sw                  ( scnl_sw                  ),
        .smask_sw                 ( smask_sw                 ),
        // Input Video from Core
        .core_r                   ( core_r                   ),
        .core_g                   ( core_g                   ),
        .core_b                   ( core_b                   ),
        .core_vs                  ( core_vs                  ),
        .core_hs                  ( core_hs                  ),
        .core_de                  ( core_de                  ),
        // Output to Display
        .video_rgb                ( video_rgb                ),
        .video_vs                 ( video_vs                 ),
        .video_hs                 ( video_hs                 ),
        .video_de                 ( video_de                 ),
        .video_rgb_clock          ( video_rgb_clock          ),
        .video_rgb_clock_90       ( video_rgb_clock_90       ),
        // Pocket Bridge Slots
        .dataslot_requestwrite    ( dataslot_requestwrite    ), // [i]
        .dataslot_requestwrite_id ( dataslot_requestwrite_id ), // [i]
        .dataslot_allcomplete     ( dataslot_allcomplete     ), // [i]
        // MPU -> FPGA (MPU Write to FPGA)
        // Pocket Bridge
        .bridge_endian_little     ( bridge_endian_little     ), // [i]
        .bridge_addr              ( bridge_addr              ), // [i]
        .bridge_wr                ( bridge_wr                ), // [i]
        .bridge_wr_data           ( bridge_wr_data           )  // [i]
    );

    //! ------------------------------------------------------------------------
    //! Data I/O
    //! ------------------------------------------------------------------------
    wire              ioctl_download;
    wire       [15:0] ioctl_index;
    wire              ioctl_wr;
    wire [DIO_AW-1:0] ioctl_addr;
    wire [DIO_DW-1:0] ioctl_data;

    data_io #(.MASK(DIO_MASK),.AW(DIO_AW),.DW(DIO_DW),.DELAY(DIO_DELAY),.HOLD(DIO_HOLD)) pocket_data_io
    (
        // Clocks and Reset
        .clk_74a                  ( clk_74a                  ),
        .clk_memory               ( clk_sys                  ),
        // Pocket Bridge Slots
        .dataslot_requestwrite    ( dataslot_requestwrite    ), // [i]
        .dataslot_requestwrite_id ( dataslot_requestwrite_id ), // [i]
        .dataslot_allcomplete     ( dataslot_allcomplete     ), // [i]
        // MPU -> FPGA (MPU Write to FPGA)
        // Pocket Bridge
        .bridge_endian_little     ( bridge_endian_little     ), // [i]
        .bridge_addr              ( bridge_addr              ), // [i]
        .bridge_wr                ( bridge_wr                ), // [i]
        .bridge_wr_data           ( bridge_wr_data           ), // [i]
        // Controller Interface
        .ioctl_download           ( ioctl_download           ), // [o]
        .ioctl_index              ( ioctl_index              ), // [o]
        .ioctl_wr                 ( ioctl_wr                 ), // [o]
        .ioctl_addr               ( ioctl_addr               ), // [o]
        .ioctl_data               ( ioctl_data               )  // [o]
    );

    //! ------------------------------------------------------------------------
    //! Gamepad/Analog Stick
    //! ------------------------------------------------------------------------
    // Player 1
    // - DPAD
    wire       p1_up,     p1_down,   p1_left,   p1_right;
    wire       p1_btn_y,  p1_btn_x,  p1_btn_b,  p1_btn_a;
    wire       p1_btn_l1, p1_btn_l2, p1_btn_l3;
    wire       p1_btn_r1, p1_btn_r2, p1_btn_r3;
    wire       p1_select, p1_start;
    // - Analog
    wire       j1_up,     j1_down,   j1_left,   j1_right;
    wire [7:0] j1_lx,     j1_ly,     j1_rx,     j1_ry;

    // Player 2
    // - DPAD
    wire       p2_up,     p2_down,   p2_left,   p2_right;
    wire       p2_btn_y,  p2_btn_x,  p2_btn_b,  p2_btn_a;
    wire       p2_btn_l1, p2_btn_l2, p2_btn_l3;
    wire       p2_btn_r1, p2_btn_r2, p2_btn_r3;
    wire       p2_select, p2_start;
    // - Analog
    wire       j2_up,     j2_down,   j2_left,   j2_right;
    wire [7:0] j2_lx,     j2_ly,     j2_rx,     j2_ry;

    // Single Player or Alternate 2 Players for Arcade
    wire m_start1, m_start2;
    wire m_coin1,  m_coin2, m_coin;
    wire m_up,     m_down,  m_left, m_right;
    wire m_btn1,   m_btn2,  m_btn3, m_btn4;
    wire m_btn5,   m_btn6,  m_btn7, m_btn8;

    //! The controller words the game reads: the Pocket's, or with the
    //! Analogizer enabled, SNAC pads put in their place (pocket_analogizer.sv,
    //! below).  Use key1..key4 wherever a core would read cont1..4_key.  The
    //! analog sticks (cont*_joy) are the Pocket's either way.
    wire [31:0] key1, key2, key3, key4;

    gamepad #(.JOY_PADS(JOY_PADS),.JOY_ALT(JOY_ALT)) pocket_gamepad
    (
        .clk_sys   ( clk_sys   ),
        // Pocket PAD Interface
        .cont1_key ( key1      ), .cont1_joy ( cont1_joy ),
        .cont2_key ( key2      ), .cont2_joy ( cont2_joy ),
        .cont3_key ( key3      ), .cont3_joy ( cont3_joy ),
        .cont4_key ( key4      ), .cont4_joy ( cont4_joy ),
        // Player 1
        .p1_up     ( p1_up     ), .p1_down   ( p1_down   ),
        .p1_left   ( p1_left   ), .p1_right  ( p1_right  ),
        .p1_y      ( p1_btn_y  ), .p1_x      ( p1_btn_x  ),
        .p1_b      ( p1_btn_b  ), .p1_a      ( p1_btn_a  ),
        .p1_l1     ( p1_btn_l1 ), .p1_r1     ( p1_btn_r1 ),
        .p1_l2     ( p1_btn_l2 ), .p1_r2     ( p1_btn_r2 ),
        .p1_l3     ( p1_btn_l3 ), .p1_r3     ( p1_btn_r3 ),
        .p1_se     ( p1_select ), .p1_st     ( p1_start  ),
        .j1_up     ( j1_up     ), .j1_down   ( j1_down   ),
        .j1_left   ( j1_left   ), .j1_right  ( j1_right  ),
        .j1_lx     ( j1_lx     ), .j1_ly     ( j1_ly     ),
        .j1_rx     ( j1_rx     ), .j1_ry     ( j1_ry     ),
        // Player 2
        .p2_up     ( p2_up     ), .p2_down   ( p2_down   ),
        .p2_left   ( p2_left   ), .p2_right  ( p2_right  ),
        .p2_y      ( p2_btn_y  ), .p2_x      ( p2_btn_x  ),
        .p2_b      ( p2_btn_b  ), .p2_a      ( p2_btn_a  ),
        .p2_l1     ( p2_btn_l1 ), .p2_r1     ( p2_btn_r1 ),
        .p2_l2     ( p2_btn_l2 ), .p2_r2     ( p2_btn_r2 ),
        .p2_l3     ( p2_btn_l3 ), .p2_r3     ( p2_btn_r3 ),
        .p2_se     ( p2_select ), .p2_st     ( p2_start  ),
        .j2_up     ( j2_up     ), .j2_down   ( j2_down   ),
        .j2_left   ( j2_left   ), .j2_right  ( j2_right  ),
        .j2_lx     ( j2_lx     ), .j2_ly     ( j2_ly     ),
        .j2_rx     ( j2_rx     ), .j2_ry     ( j2_ry     ),
        // Single Player or Alternate 2 Players for Arcade
        .m_coin    ( m_coin    ),                           // Coinage P1 or P2
        .m_up      ( m_up      ), .m_down    ( m_down    ), // Up/Down
        .m_left    ( m_left    ), .m_right   ( m_right   ), // Left/Right
        .m_btn1    ( m_btn1    ), .m_btn4    ( m_btn4    ), // Y/X
        .m_btn2    ( m_btn2    ), .m_btn3    ( m_btn3    ), // B/A
        .m_btn5    ( m_btn5    ), .m_btn6    ( m_btn6    ), // L1/R1
        .m_btn7    ( m_btn7    ), .m_btn8    ( m_btn8    ), // L2/R2
        .m_coin1   ( m_coin1   ), .m_coin2   ( m_coin2   ), // P1/P2 Coin
        .m_start1  ( m_start1  ), .m_start2  ( m_start2  )  // P1/P2 Start
    );

    //! ------------------------------------------------------------------------
    //! Clocks
    //! ------------------------------------------------------------------------
    wire pll_core_locked, pll_core_locked_s;
    wire clk_sys;       // Machine, renderer and SDRAM: 96.0 MHz
    wire clk_vid;       // Video: 16.0 MHz dot clock, exactly clk_sys / 6
    wire clk_vid_90deg; // Video: 16.0 MHz @ 90deg (Pocket RGB clock pair)
    wire clk_sdram;     // SDRAM chip clock: 96.0 MHz, phase-shifted (see the SDC)
    wire clk_ana;       // Analogizer: 64.0 MHz, clk_sys * 2 / 3, four clocks a dot

    core_pll core_pll
    (
        .refclk   ( clk_74a ),
        .rst      ( 0       ),

        .outclk_0 ( clk_sys       ),
        .outclk_1 ( clk_vid       ),
        .outclk_2 ( clk_vid_90deg ),
        .outclk_3 ( clk_sdram     ),
        .outclk_4 ( clk_ana       ),

        .locked   ( pll_core_locked )
    );

    // Synchronize pll_core_locked into clk_74a domain before usage
    synch_3 sync_lck(pll_core_locked, pll_core_locked_s, clk_74a);

    //! ------------------------------------------------------------------------
    //! @ Super Sprint (Atari Games, 1986)
    //! ------------------------------------------------------------------------
    wire reset_sw_s;
    synch_3 sync_rst(reset_sw, reset_sw_s, clk_sys);

    //! The loader path must stay alive through the download (the host holds
    //! reset_n low for all of it); only the machine is reset by the menu.
    wire ss_reset    = reset_sw_s;
    wire ss_hw_reset = ~pll_core_locked_s;

    //! ROM: one slot with the 2,196,480-byte format 2 image from tools/mra_build.py (docs/hardware.md section 9).
    // Slot 1, not 0: slot 0 carries the instance JSON that names the game (the
    // Pocket consumes it, the core never sees it), the image arrives in slot 1
    // and the save lives in slot 2 (data.json).
    wire        ioctl_isROM = ioctl_download && ioctl_index == 16'h1;
    wire        dl_we       = ioctl_isROM && ioctl_wr;
    wire [24:0] dl_addr     = ioctl_addr[24:0];
    wire  [7:0] dl_data     = ioctl_data;

    //! Controls. Each player has a steering wheel (a quadrature counter the
    //! game reads as an 8-bit position), an accelerator pedal (an ADC channel:
    //! 0xff released, 0x3f floored) and a Start button; the cabinet has three
    //! coin slots. Player 1 is the Pocket's own controls (or dock pad 1),
    //! players 2 and 3 are dock pads 2 and 3.
    //!
    //! Steering: D-pad left/right turn the wheel at a rate set from the
    //! Interact menu (a held direction is a steady turn, as spinning the
    //! wheel is); a dock pad's left stick turns it proportionally. Pedal:
    //! A, B, X, Y or either trigger floors it.
    //! platform joypad numbering: Y/X = m_btn1/4, B/A = m_btn2/3, L1/R1 = m_btn5/6
    wire [1:0] steer_rate = mod_sw0[4:3];
    wire       steer_stick_rev = mod_sw0[0];        // menu: Analog Stick Steering = Reversed
    wire [1:0] steer_stick_sens = mod_sw1[3:2];     // menu: Analog Sensitivity (0 default, 1 less, 2 more); 0xF2000000 bits 11:10
    wire [7:0] wheel0, wheel1, wheel2;
    steer_wheel sw0 (.clk(clk_sys), .reset(ss_reset), .rate(steer_rate), .left(p1_left), .right(p1_right),
                     .stick_active(j1_left | j1_right), .stick_x(j1_lx), .stick_rev(steer_stick_rev), .stick_sens(steer_stick_sens), .pos(wheel0));
    steer_wheel sw1 (.clk(clk_sys), .reset(ss_reset), .rate(steer_rate), .left(p2_left), .right(p2_right),
                     .stick_active(j2_left | j2_right), .stick_x(j2_lx), .stick_rev(steer_stick_rev), .stick_sens(steer_stick_sens), .pos(wheel1));
    // player 3: dock pad 3, raw APF bits (0 up, 1 down, 2 left, 3 right, 4 A, 5 B, 6 X, 7 Y, 8 L1, 9 R1, 14 select, 15 start)
    wire [31:0] c3;
    synch_3 #(.WIDTH(32)) sync_c3(key3, c3, clk_sys);
    steer_wheel sw2 (.clk(clk_sys), .reset(ss_reset), .rate(steer_rate), .left(c3[2]), .right(c3[3]),
                     .stick_active(1'b0), .stick_x(8'h80), .stick_rev(1'b0), .stick_sens(2'd0), .pos(wheel2));
    // 720 Degrees: the rotating joystick on LETA 0 (centre) and LETA 1 (rotate)
    wire [7:0] rot720, ctr720;
    ctrl_720 c720 (.clk(clk_sys), .reset(ss_reset), .rate(steer_rate), .up(p1_up), .down(p1_down), .left(p1_left), .right(p1_right),
                   .spin_ccw(p1_btn_l1), .spin_cw(p1_btn_r1), .stick_active(j1_up | j1_down | j1_left | j1_right),
                   .stick_x(j1_lx), .stick_y(j1_ly), .rotate(rot720), .center(ctr720));
    //! The accelerator: the face buttons and R1 floor it, L1 is half throttle
    //! (the pedal reads 0x3f up, 0x00 floored, so half is 0x20; a full press
    //! wins over a half one)
    wire       gas1 = g_apb ? (p1_btn_b | p1_btn_x | p1_btn_r1)          // A and Y are APB's buttons
                             : (p1_btn_a | p1_btn_b | p1_btn_x | p1_btn_y | p1_btn_r1);
    wire       gas2 = p2_btn_a | p2_btn_b | p2_btn_x | p2_btn_y | p2_btn_r1;
    wire       gas3 = c3[4] | c3[5] | c3[6] | c3[7] | c3[9];
    wire       half1 = p1_btn_l1, half2 = p2_btn_l1, half3 = c3[8];
    wire [7:0] ped1 = gas1 ? 8'h00 : half1 ? 8'h20 : 8'h3f;
    wire [7:0] ped2 = gas2 ? 8'h00 : half2 ? 8'h20 : 8'h3f;
    wire [7:0] ped3 = gas3 ? 8'h00 : half3 ? 8'h20 : 8'h3f;
    //! Paperboy's handlebars: the stick's X/Y when it is off centre, else
    //! the D-pad as full deflection (MAME's AD_STICK: 0x10 .. 0x80 .. 0xf0)
    wire [7:0] hb_x = (j1_left | j1_right) ? j1_lx : p1_left ? 8'h10 : p1_right ? 8'hf0 : 8'h80;
    wire [7:0] hb_y = (j1_up | j1_down)    ? j1_ly : p1_up   ? 8'h10 : p1_down  ? 8'hf0 : 8'h80;
    //! Pedals: the ADC reads 0x3f with the pedal up and 0x00 floored, MAME's
    //! analog port (PORT_MINMAX 0x00-0x3f, inverted) as a player drives it.
    //! Not 0xff: that is only what an untouched port reads in a headless MAME,
    //! and APB's pedal calibration (docs/hardware.md 7.6) wraps on it and
    //! drives the car by itself until the pedal has moved once.
    reg  [7:0] pedal0 = 8'h3f, pedal1 = 8'h3f, pedal2 = 8'h3f;
    reg  [7:0] leta0_q = 8'hff, leta1_q = 8'hff, leta2_q = 8'hff;    // Paperboy has no LETA counters: its ports read 0xff
    always @(posedge clk_sys) begin
        pedal0 <= g_720 ? 8'hff : g_pb ? hb_x : ped1;    // 720's ADCs are unused (read 0xff)
        pedal1 <= g_720 ? 8'hff : g_pb ? hb_y : (g_apb ? ped1 : ped2);    // APB reads its pedal on ADC 1
        pedal2 <= ped3;
        leta0_q <= g_720 ? ctr720 : g_pb ? 8'hff : wheel0;    // 720: the joystick's centre and rotate discs
        leta1_q <= g_720 ? rot720 : g_pb ? 8'hff : wheel1;
        leta2_q <= (g_pb | g_720) ? 8'hff : wheel2;
    end
    //! Per-game wiring (cfg_game from the image header): Super Sprint's three
    //! players each have a wheel, pedal (ADC 0/1/2), start and coin slot;
    //! APB (game 2) has one wheel (LETA 0), its pedal on ADC 1, two buttons
    //! on IN0 -- button 3 is the SIREN, which also starts the game, so it is
    //! A; button 2 is Y -- and coins on IN1 bits 6/7.
    //! Championship Sprint (game 3) is Super Sprint with two players: its
    //! coins are on IN1 bits 6/7 like APB's, everything else Super Sprint's.
    //! (the game selects and the muxes they steer are registered: the
    //! header byte -> compare -> mux -> the 6502's input port read missed
    //! 96 MHz by 0.23 ns as one chain, and every input here is quasi-static)
    //! Paperboy (game 4): handlebars on ADC 0 (X) and ADC 1 (Y), its two
    //! buttons (throw) on IN0 bits 7/6 -- the bits the Sprints' start
    //! buttons use, so they arrive as starts[0]/[1] -- coins on IN1 bits
    //! 6/7, no start button (a button starts the game).
    reg        g_apb = 1'b0, g_cs = 1'b0, g_pb = 1'b0, g_720 = 1'b0;
    reg  [2:0] starts = 3'b000, coins = 3'b000;
    reg        btn2 = 1'b0, btn3 = 1'b0;
    always @(posedge clk_sys) begin
        g_apb  <= (cfg_game == 8'd2);
        g_cs   <= (cfg_game == 8'd3);
        g_pb   <= (cfg_game == 8'd4);
        g_720  <= (cfg_game == 8'd5);
        starts <= (g_pb | g_720) ? {1'b0, p1_btn_b, p1_btn_a} : {c3[15], p2_start, p1_start};
        coins  <= (g_apb | g_cs | g_pb | g_720) ? {p2_select, p1_select, 1'b0} : {c3[14], p2_select, p1_select};
        btn2   <= g_apb & p1_btn_y;
        btn3   <= g_apb & p1_btn_a;                         // siren / start
    end

    //! Diagnostics from the modifier word: bit 5 overlay, bit 6 SDRAM read
    //! capture alternate, bit 7 slow bursts.
    wire       ss_ovl        = mod_sw0[5];
    wire       ss_rd_late    = ~mod_sw0[6];
    wire       ss_burst_slow = mod_sw0[7];

    wire [7:0] ss_r, ss_g, ss_b;
    wire       ss_hs, ss_vs, ss_de, ss_hb, ss_vb, ss_ce_pix;
    wire signed [15:0] ss_audio_l, ss_audio_r;
    wire       ss_audio_valid;
    wire [15:0] dbg_t11_pc, dbg_6502_addr;
    wire  [7:0] dbg_flags, dbg_snd_cmd;
    wire        dbg_t11_done, dbg_snd_cmd_wr;
    wire  [7:0] nv_rd_data_core;

    wire [7:0] cfg_game, cfg_slapstic, cfg_flags, cfg_pf_bits, cfg_mo_bits;   // from the image header
    ssprint_core #(.DBG_OVERLAY(1)) ss (
        .cfg_game(cfg_game), .cfg_slapstic(cfg_slapstic), .cfg_flags(cfg_flags), .cfg_pf_bits(cfg_pf_bits), .cfg_mo_bits(cfg_mo_bits),
        .clk          ( clk_sys        ),
        .clk_sdram    ( clk_sdram      ),
        .hw_reset     ( ss_hw_reset    ),
        .reset        ( ss_reset       ),
        .rd_late      ( ss_rd_late     ),
        .burst_slow   ( ss_burst_slow  ),
        .overlay      ( ss_ovl         ),
        .dl_active    ( ioctl_download ),
        .dl_addr_in   ( dl_addr        ),
        .dl_data_in   ( dl_data        ),
        .dl_we_in     ( dl_we          ),
        .nv_addr      ( po_nv_addr     ),
        .nv_we        ( po_nv_we       ),
        .nv_wdata     ( nv_dl_data     ),
        .nv_rdata     ( nv_rd_data_core ),
        .nv_dirty     ( po_nv_dirty    ),
        .coin         ( coins          ),
        .start        ( starts         ),
        .btn2         ( btn2           ),
        .btn3         ( btn3           ),
        .service      ( svc_sw         ),
        .pedal0       ( pedal0         ),
        .pedal1       ( pedal1         ),
        .pedal2       ( pedal2         ),
        .wheel0       ( leta0_q        ),
        .wheel1       ( leta1_q        ),
        .wheel2       ( leta2_q        ),
        // DSW0 bits 4:0 (coinage, multiplier) are the same on every System 2
        // game and come from the menu's shared entries; bonus coins (7:5) and
        // DSW1 are per game. APB's live in the DIP register's bits 26:16
        // (interact.json; nothing above bit 30 -- the Pocket rejected option
        // values with bit 31 set): dip_sw2 = its DSW1 bits 7:1 (bit 0, the
        // attract lights, stays 0 = on), dip_sw3[2:0] = its DSW0 bits 7:5.
        //! One coin per play on every game: DSW0 bits 4:0 (coinage,
        //! multiplier) are held at 0 = 1 coin / 1 credit; APB's "coins
        //! required" (its DSW1 bits 7:6) at 01 = 1 to start, 1 to continue,
        //! its "max continues" (bits 2:1) at 11 = 199, its attract lights on.
        //! Only the difficulty switches (and the Sprints' obstacles and
        //! wrenches) are in the menu.
        //! Paperboy: DSW0 all factory (1 coin / 1 credit, no bonus coins),
        //! DSW1 difficulty (bits 1:0) from the menu's bits 15:14, the rest factory.
        .dsw0         ( g_apb ? {dip_sw3[2:0], 5'b00000} : (g_pb | g_720) ? 8'h00 : {dip_sw0[7:5], 5'b00000} ),
        .dsw1         ( g_apb ? {2'b01, dip_sw2[5:3], 2'b11, 1'b0} : g_pb ? {2'b11, 4'b0000, dip_sw1[7:6]} : g_720 ? {2'b01, 2'b01, dip_sw2[1:0], dip_sw2[7:6]} : dip_sw1 ),
        .cen_pix      ( ss_ce_pix      ),
        .r            ( ss_r           ),
        .g            ( ss_g           ),
        .b            ( ss_b           ),
        .hsync        ( ss_hs          ),
        .vsync        ( ss_vs          ),
        .hblank       ( ss_hb          ),
        .vblank       ( ss_vb          ),
        .de           ( ss_de          ),
        .audio_l      ( ss_audio_l     ),
        .audio_r      ( ss_audio_r     ),
        .audio_valid  ( ss_audio_valid ),
        .dram_dq      ( dram_dq        ),
        .dram_a       ( dram_a         ),
        .dram_ba      ( dram_ba        ),
        .dram_dqm_l   ( dram_dqm[0]    ),
        .dram_dqm_h   ( dram_dqm[1]    ),
        .dram_cs_n    (                ),
        .dram_ras_n   ( dram_ras_n     ),
        .dram_cas_n   ( dram_cas_n     ),
        .dram_we_n    ( dram_we_n      ),
        .dram_cke     ( dram_cke       ),
        .dram_clk     ( dram_clk       ),
        .dbg_t11_pc   ( dbg_t11_pc     ),
        .dbg_t11_done ( dbg_t11_done   ),
        .dbg_6502_addr( dbg_6502_addr  ),
        .dbg_flags    ( dbg_flags      ),
        .dbg_snd_cmd_wr( dbg_snd_cmd_wr ),
        .dbg_snd_cmd  ( dbg_snd_cmd    )
    );
    assign nv_rd_data = nv_rd_data_core;

    //! Screen shape from the Interact menu (video.json scaler modes):
    //! "Wide" is the cabinet's aspect, mode 0 (4:3) for a horizontal game
    //! and mode 2 (3:4, rotated 270 -- the scaler takes the aspect after
    //! rotation, as the Pocket showed) for a vertical one (header flag bit
    //! 1, APB); "Tall" is the Pocket's own 10:9, modes 1 and 3.
    wire [1:0] aspect_sel = mod_sw0[2:1];
    assign video_preset = cfg_flags[1] ? {1'b0, 2'd2 + aspect_sel} : ((aspect_sel == 2'd1) ? 3'd1 : 3'd0);

    //! ------------------------------------------------------------------
    //! Video: the core emits exactly one pixel per clk_vid (16 MHz = clk_sys/6),
    //! so this is a retiming register onto the video clock, not a rate change --
    //! the arrangement Punch-Out!!, Xenophobe, Time Pilot and S.T.U.N. Runner
    //! use; both clocks come from the one PLL so the SDC can prove it.
    //! ------------------------------------------------------------------
    reg [7:0] vr_q, vg_q, vb_q;
    reg       vhs_q, vvs_q, vde_q;
    always @(posedge clk_vid) begin
        vr_q  <= ss_r;  vg_q <= ss_g;  vb_q <= ss_b;
        vhs_q <= ss_hs; vvs_q <= ss_vs; vde_q <= ss_de;
    end
    //! "Analogizer: On, Pocket off" in the menu: the picture goes to the
    //! monitor only.  Syncs and DE keep running for the scaler.
    wire ana_pocket_off;
    reg  [1:0] poff_s = 2'b00;
    always @(posedge clk_vid) poff_s <= {poff_s[0], ana_pocket_off};
    assign core_r  = poff_s[1] ? 8'd0 : vr_q;
    assign core_g  = poff_s[1] ? 8'd0 : vg_q;
    assign core_b  = poff_s[1] ? 8'd0 : vb_q;
    assign core_hs = vhs_q;
    assign core_vs = vvs_q;
    assign core_de = vde_q;

    //! ------------------------------------------------------------------
    //! The Analogizer (target/pocket/pocket_analogizer.sv, docs/analogizer.md).
    //! It takes the same picture the Pocket gets, at the board's own raster:
    //! 640 x 416 dots of 16 MHz, 512 x 384 visible, 25.0 kHz lines and
    //! 60.1 Hz -- a medium-resolution monitor's, which no 15 kHz television
    //! syncs to.  Its clock is 64 MHz, the least that is four times the dot
    //! rate (the scandoubler halves the dot), from the PLL's spare output; it
    //! is held idle until the game is loaded.  Set from the core's menu
    //! (interact.json, 0xF7000000-0xF7000008).  With the menu's "Analogizer"
    //! off, the default, the cartridge port stays as an unused one and
    //! key1..key4 are cont1..cont4_key.
    //! ------------------------------------------------------------------
    generate
        if(USE_ANALOGIZER == 1) begin : analogizer
            pocket_analogizer #(.CLK_HZ(64_000_000), .LINE_LEN(640)) u_analogizer (
                .clk_74a(clk_74a), .clk(clk_ana), .rst(ss_reset),
                .clk_src(clk_sys), .src_pix_ce(ss_ce_pix),
                .src_rgb({ss_r, ss_g, ss_b}),
                .src_hs(ss_hs), .src_vs(ss_vs), .src_hb(ss_hb), .src_vb(ss_vb),
                .bridge_addr(bridge_addr),
                .bridge_rd(bridge_rd), .bridge_rd_data(ana_bridge_rd_data),
                .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
                .cont1_key(cont1_key), .cont2_key(cont2_key),
                .cont3_key(cont3_key), .cont4_key(cont4_key),
                .key1(key1), .key2(key2), .key3(key3), .key4(key4),
                .ena(), .pocket_off(ana_pocket_off),
                .ps2_code_new(), .ps2_code(),
                .cart_tran_bank2(cart_tran_bank2), .cart_tran_bank2_dir(cart_tran_bank2_dir),
                .cart_tran_bank3(cart_tran_bank3), .cart_tran_bank3_dir(cart_tran_bank3_dir),
                .cart_tran_bank1(cart_tran_bank1), .cart_tran_bank1_dir(cart_tran_bank1_dir),
                .cart_tran_bank0(cart_tran_bank0), .cart_tran_bank0_dir(cart_tran_bank0_dir),
                .cart_tran_pin30(cart_tran_pin30), .cart_tran_pin30_dir(cart_tran_pin30_dir),
                .cart_pin30_pwroff_reset(cart_pin30_pwroff_reset),
                .cart_tran_pin31(cart_tran_pin31), .cart_tran_pin31_dir(cart_tran_pin31_dir)
            );
        end else begin : no_analogizer
            assign key1 = cont1_key; assign key2 = cont2_key;
            assign key3 = cont3_key; assign key4 = cont4_key;
            assign ana_bridge_rd_data = 32'h0;
            assign ana_pocket_off = 1'b0;
        end
    endgenerate

    //! ------------------------------------------------------------------
    //! Audio clock domain crossing (METHODOLOGY section 5.4): the sound
    //! board's mix updates on the YM2151 clock; sample at 48 kHz on clk_sys,
    //! hold, and hand over to clk_74b with a toggle flag so the audio side
    //! never latches a torn sample.
    //! ------------------------------------------------------------------
    logic signed [15:0] snd_hold_l = 16'sd0, snd_hold_r = 16'sd0;
    logic               snd_tog  = 1'b0;
    logic       [10:0]  snd_div  = 11'd0;
    wire snd_tick = (snd_div == 11'd1999);      // 96 MHz / 2000 = 48 kHz
    always_ff @(posedge clk_sys) begin
        snd_div <= snd_div + 1'd1;
        if (snd_tick) begin
            snd_div    <= 11'd0;
            snd_hold_l <= ss_audio_l;
            snd_hold_r <= ss_audio_r;
            snd_tog    <= ~snd_tog;
        end
    end
    logic        [2:0]  snd_tog_s = 3'd0;
    logic signed [15:0] snd_xfer_l = 16'sd0, snd_xfer_r = 16'sd0;
    always_ff @(posedge clk_74b) begin
        snd_tog_s <= {snd_tog_s[1:0], snd_tog};
        if (snd_tog_s[2] != snd_tog_s[1]) begin snd_xfer_l <= snd_hold_l; snd_xfer_r <= snd_hold_r; end
    end
    assign core_snd_l = snd_xfer_l;
    assign core_snd_r = snd_xfer_r;

endmodule
