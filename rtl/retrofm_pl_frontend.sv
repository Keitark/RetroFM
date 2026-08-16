// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// RetroFM PS-to-PL register/FIFO front end.  s_axi_aclk is the 100 MHz player
// timebase; this module creates no derived clock domains.
module retrofm_pl_frontend #(
    parameter integer AXI_ADDR_WIDTH   = 8,
    parameter integer EVENT_FIFO_DEPTH = 2048,
    parameter integer PCM_FIFO_DEPTH   = 4096
) (
    input  logic                      s_axi_aclk,
    input  logic                      s_axi_aresetn,

    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [2:0]                s_axi_awprot,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    input  logic [31:0]               s_axi_wdata,
    input  logic [3:0]                s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [2:0]                s_axi_arprot,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    output logic [31:0]               s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    input  logic [13:0]               key_masks,
    input  logic [47:0]               jt03_meter_volume,
    input  logic [5:0]                jt03_meter_trigger,
    input  logic [87:0]               opna_meter_volume,
    input  logic [10:0]               opna_meter_trigger,
    input  logic [15:0]               peak_left,
    input  logic [15:0]               peak_right,
    input  logic [4:0]                buttons,
    input  logic                      command_cdc_fault,
    input  logic                      command_backpressure_seen,
    input  logic [255:0]              spectrum_bins,

    input  logic                      jt51_ready,
    input  logic                      jt03_ready,

    input  logic                      pcm_pop,
    output logic                      pcm_valid,
    output logic [31:0]               pcm_frame,

    output logic                      jt51_wr,
    output logic [7:0]                jt51_reg,
    output logic [7:0]                jt51_data,
    output logic                      jt03_wr,
    output logic                      jt03_port,
    output logic [7:0]                jt03_reg,
    output logic [7:0]                jt03_data,
    output logic                      end_pulse,
    output logic                      diagnostic_pulse,

    output logic                      mute_pulse,
    output logic                      unmute_pulse,
    output logic                      core_reset_pulse,
    output logic                      event_flush_pulse,
    output logic                      pcm_flush_pulse,
    output logic                      clear_faults_pulse,
    output logic                      command_cdc_fault_clear_pulse,
    output logic                      jt03_meter_trigger_clear,
    output logic                      opna_meter_trigger_clear,

    output logic [15:0]               volume_q15,
    output logic [31:0]               ym2203_clock_hz,
    output logic                      opna_sample_write,
    output logic [16:0]               opna_sample_write_addr,
    output logic [31:0]               opna_sample_write_data,
    output logic [3:0]                opna_sample_write_strb,
    output logic [1:0]                active_chip,
    output logic                      pcm_enable,
    output logic                      fm_mute_enable,
    output logic [31:0]               lcd_aux,
    output logic                      irq,

    output logic [12:0]               event_level,
    output logic [12:0]               pcm_level,
    output logic                      event_prefetch_valid,
    output logic                      scheduler_pending,
    output logic                      scheduler_halted,
    output logic                      scheduler_underrun_active,
    output logic [31:0]               late_count,
    output logic [31:0]               underrun_count,
    output logic [63:0]               playback_cycles
);
    localparam logic [7:0] REG_ID              = 8'h00;
    localparam logic [7:0] REG_VERSION         = 8'h04;
    localparam logic [7:0] REG_CONTROL         = 8'h08;
    localparam logic [7:0] REG_COMMAND         = 8'h0c;
    localparam logic [7:0] REG_EVENT_LO        = 8'h10;
    localparam logic [7:0] REG_EVENT_HI        = 8'h14;
    localparam logic [7:0] REG_EVENT_STATUS    = 8'h18;
    localparam logic [7:0] REG_EVENT_WATERMARK = 8'h1c;
    localparam logic [7:0] REG_PCM_FRAME       = 8'h20;
    localparam logic [7:0] REG_PCM_STATUS      = 8'h24;
    localparam logic [7:0] REG_VOLUME          = 8'h28;
    localparam logic [7:0] REG_YM2203_CLOCK    = 8'h2c;
    localparam logic [7:0] REG_KEY_MASKS       = 8'h30;
    localparam logic [7:0] REG_PEAKS           = 8'h34;
    localparam logic [7:0] REG_LATE_COUNT      = 8'h38;
    localparam logic [7:0] REG_PLAY_CYCLES_LO  = 8'h3c;
    localparam logic [7:0] REG_PLAY_CYCLES_HI  = 8'h40;
    localparam logic [7:0] REG_BUTTONS         = 8'h44;
    localparam logic [7:0] REG_LCD_AUX         = 8'h48;
    localparam logic [7:0] REG_IRQ_STATUS      = 8'h4c;
    localparam logic [7:0] REG_SPECTRUM_0      = 8'h50;
    localparam logic [7:0] REG_SPECTRUM_1      = 8'h54;
    localparam logic [7:0] REG_SPECTRUM_2      = 8'h58;
    localparam logic [7:0] REG_SPECTRUM_3      = 8'h5c;
    localparam logic [7:0] REG_SPECTRUM_4      = 8'h60;
    localparam logic [7:0] REG_SPECTRUM_5      = 8'h64;
    localparam logic [7:0] REG_SPECTRUM_6      = 8'h68;
    localparam logic [7:0] REG_SPECTRUM_7      = 8'h6c;
    localparam logic [7:0] REG_JT03_METER_LO   = 8'h70;
    localparam logic [7:0] REG_JT03_METER_HI   = 8'h74;
    localparam logic [7:0] REG_OPNA_SAMPLE_ADDR = 8'h78;
    localparam logic [7:0] REG_OPNA_SAMPLE_DATA = 8'h7c;
    localparam logic [7:0] REG_OPNA_METER_0     = 8'h80;
    localparam logic [7:0] REG_OPNA_METER_1     = 8'h84;
    localparam logic [7:0] REG_OPNA_METER_2     = 8'h88;
    localparam logic [7:0] REG_OPNA_METER_FLAGS = 8'h8c;

    localparam integer EVENT_COUNT_WIDTH =
        (EVENT_FIFO_DEPTH <= 1) ? 1 : $clog2(EVENT_FIFO_DEPTH + 1);
    localparam integer PCM_COUNT_WIDTH =
        (PCM_FIFO_DEPTH <= 1) ? 1 : $clog2(PCM_FIFO_DEPTH + 1);

    logic rst;
    assign rst = !s_axi_aresetn;

    function automatic logic [31:0] merge_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strobes
    );
        integer byte_index;
        begin
            merge_wstrb = old_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                if (strobes[byte_index])
                    merge_wstrb[byte_index*8 +: 8] =
                        new_value[byte_index*8 +: 8];
        end
    endfunction

    function automatic logic [31:0] strobe_masked(
        input logic [31:0] value,
        input logic [3:0]  strobes
    );
        integer byte_index;
        begin
            strobe_masked = 32'h00000000;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                if (strobes[byte_index])
                    strobe_masked[byte_index*8 +: 8] =
                        value[byte_index*8 +: 8];
        end
    endfunction

    function automatic logic write_address_valid(input logic [7:0] address);
        begin
            case (address)
                REG_CONTROL,
                REG_COMMAND,
                REG_EVENT_LO,
                REG_EVENT_HI,
                REG_EVENT_WATERMARK,
                REG_PCM_FRAME,
                REG_VOLUME,
                REG_YM2203_CLOCK,
                REG_OPNA_SAMPLE_ADDR,
                REG_OPNA_SAMPLE_DATA,
                REG_LCD_AUX,
                REG_IRQ_STATUS: write_address_valid = 1'b1;
                default: write_address_valid = 1'b0;
            endcase
        end
    endfunction

    logic [AXI_ADDR_WIDTH-1:0] aw_hold_addr;
    logic                      aw_hold_valid;
    logic [31:0]               w_hold_data;
    logic [3:0]                w_hold_strb;
    logic                      w_hold_valid;

    logic [31:0] control_reg;
    logic [31:0] event_lo_staging;
    logic [31:0] event_hi_staging;
    logic [31:0] event_watermark;
    logic [31:0] pcm_frame_staging;
    logic [31:0] volume_reg;
    logic [31:0] ym2203_clock_reg;
    logic [16:0] opna_sample_addr_reg;
    logic [31:0] opna_sample_addr_merged;
    logic [31:0] lcd_aux_reg;

    logic event_overflow_sticky;
    logic event_underrun_sticky;
    logic late_sticky;
    logic pcm_overflow_sticky;
    logic pcm_underrun_sticky;

    logic [63:0] playback_snapshot;
    logic [63:0] playback_time_offset;

    logic event_fifo_wr_en;
    logic [63:0] event_fifo_wr_data;
    logic event_fifo_wr_accept;
    logic event_fifo_overflow;
    logic event_fifo_rd_en;
    logic [63:0] event_fifo_rd_data;
    logic event_fifo_rd_valid;
    logic event_fifo_underflow;
    logic event_fifo_full_raw;
    logic event_fifo_empty_raw;
    logic [EVENT_COUNT_WIDTH-1:0] event_fifo_count;

    logic pcm_fifo_wr_en;
    logic [31:0] pcm_fifo_wr_data;
    logic pcm_fifo_wr_accept;
    logic pcm_fifo_overflow;
    logic pcm_fifo_underflow;
    logic pcm_fifo_full;
    logic pcm_fifo_empty;
    logic [PCM_COUNT_WIDTH-1:0] pcm_fifo_count;

    logic bridge_stream_valid;
    logic [63:0] bridge_stream_data;
    logic bridge_stream_ready;
    logic bridge_occupied;

    logic scheduler_core_stalled;
    logic scheduler_playback_advancing;
    logic scheduler_late_pulse;
    logic scheduler_underrun_pulse;
    logic [63:0] scheduler_playback_cycles;
    logic [63:0] scheduler_scheduled_cycles;

    logic [31:0] event_level_word;
    logic [31:0] pcm_level_word;
    logic event_empty_logical;
    logic event_full_logical;
    logic event_low_water;
    logic [31:0] event_status_word;
    logic [31:0] pcm_status_word;
    logic [31:0] irq_status_word;
    logic [31:0] read_data_mux;
    logic read_address_valid;
    logic [31:0] command_word;

    assign volume_q15       = volume_reg[15:0];
    assign ym2203_clock_hz  = ym2203_clock_reg;
    always_comb opna_sample_addr_merged = merge_wstrb(
        {15'd0, opna_sample_addr_reg}, w_hold_data, w_hold_strb);
    assign active_chip      = control_reg[5:4];
    // Explicit CONTROL allocation not present in the original register-map
    // draft: bit 1 enables the 48 kHz PCM consumer and PCM underrun tracking.
    // CONTROL[0] remains event-scheduler run.
    assign pcm_enable       = control_reg[1];
    assign fm_mute_enable   = control_reg[2];
    assign lcd_aux          = lcd_aux_reg;
    assign playback_cycles  = scheduler_playback_cycles - playback_time_offset;
    assign event_prefetch_valid = bridge_stream_valid;

    always_comb begin
        event_level_word = 32'h00000000;
        event_level_word[EVENT_COUNT_WIDTH-1:0] = event_fifo_count;
        if (bridge_occupied)
            event_level_word = event_level_word + 1'b1;

        pcm_level_word = 32'h00000000;
        pcm_level_word[PCM_COUNT_WIDTH-1:0] = pcm_fifo_count;

        event_level = event_level_word[12:0];
        pcm_level   = pcm_level_word[12:0];
        event_empty_logical = (event_level_word == 0);
        event_full_logical  = (event_level_word >= EVENT_FIFO_DEPTH);
        event_low_water = (event_level_word <= event_watermark);

        // STATUS and IRQ bit assignments are provisional because the current
        // register-map document names the fields but does not assign bits.
        event_status_word = 32'h00000000;
        event_status_word[12:0] = event_level_word[12:0];
        event_status_word[16] = event_empty_logical;
        event_status_word[17] = event_full_logical;
        event_status_word[18] = event_overflow_sticky;
        event_status_word[19] = event_underrun_sticky;
        event_status_word[20] = late_sticky;
        event_status_word[21] = command_cdc_fault;
        event_status_word[22] = scheduler_halted;
        // A full CDC bridge can legally backpressure ready/valid without
        // losing a command.  Keep that history visible, but never include it
        // in the fatal fault IRQ represented by bit 21 / IRQ_STATUS[6].
        event_status_word[23] = command_backpressure_seen;

        pcm_status_word = 32'h00000000;
        pcm_status_word[12:0] = pcm_level_word[12:0];
        pcm_status_word[16] = pcm_fifo_empty;
        pcm_status_word[17] = pcm_fifo_full;
        pcm_status_word[18] = pcm_overflow_sticky;
        pcm_status_word[19] = pcm_underrun_sticky;

        irq_status_word = 32'h00000000;
        irq_status_word[0] = event_low_water;
        irq_status_word[1] = event_overflow_sticky;
        irq_status_word[2] = event_underrun_sticky;
        irq_status_word[3] = late_sticky;
        irq_status_word[4] = pcm_overflow_sticky;
        irq_status_word[5] = pcm_underrun_sticky;
        irq_status_word[6] = command_cdc_fault;

        irq = (control_reg[8] && event_low_water) ||
              (control_reg[9] && (|irq_status_word[6:1]));

        read_address_valid = 1'b1;
        case (s_axi_araddr[7:0])
            REG_ID:              read_data_mux = 32'h52464d31;
            REG_VERSION:         read_data_mux = 32'h00010002;
            REG_CONTROL:         read_data_mux = control_reg;
            REG_COMMAND,
            REG_EVENT_LO,
            REG_EVENT_HI,
            REG_PCM_FRAME: begin
                read_data_mux = 32'h00000000;
                read_address_valid = 1'b0;
            end
            REG_EVENT_STATUS:    read_data_mux = event_status_word;
            REG_EVENT_WATERMARK: read_data_mux = event_watermark;
            REG_PCM_STATUS:      read_data_mux = pcm_status_word;
            REG_VOLUME:          read_data_mux = volume_reg;
            REG_YM2203_CLOCK:    read_data_mux = ym2203_clock_reg;
            REG_OPNA_SAMPLE_ADDR: read_data_mux = {15'd0, opna_sample_addr_reg};
            REG_KEY_MASKS:       read_data_mux = {18'h00000, key_masks};
            REG_PEAKS:           read_data_mux = {peak_right, peak_left};
            REG_LATE_COUNT:      read_data_mux = late_count;
            REG_PLAY_CYCLES_LO:  read_data_mux = playback_cycles[31:0];
            REG_PLAY_CYCLES_HI:  read_data_mux = playback_snapshot[63:32];
            REG_BUTTONS:         read_data_mux = {27'h0000000, buttons};
            REG_LCD_AUX:         read_data_mux = lcd_aux_reg;
            REG_IRQ_STATUS:      read_data_mux = irq_status_word;
            REG_SPECTRUM_0:      read_data_mux = spectrum_bins[31:0];
            REG_SPECTRUM_1:      read_data_mux = spectrum_bins[63:32];
            REG_SPECTRUM_2:      read_data_mux = spectrum_bins[95:64];
            REG_SPECTRUM_3:      read_data_mux = spectrum_bins[127:96];
            REG_SPECTRUM_4:      read_data_mux = spectrum_bins[159:128];
            REG_SPECTRUM_5:      read_data_mux = spectrum_bins[191:160];
            REG_SPECTRUM_6:      read_data_mux = spectrum_bins[223:192];
            REG_SPECTRUM_7:      read_data_mux = spectrum_bins[255:224];
            REG_JT03_METER_LO:   read_data_mux = jt03_meter_volume[31:0];
            REG_JT03_METER_HI:   read_data_mux = {
                                      10'h000, jt03_meter_trigger,
                                      jt03_meter_volume[47:32]};
            REG_OPNA_METER_0:    read_data_mux = opna_meter_volume[31:0];
            REG_OPNA_METER_1:    read_data_mux = opna_meter_volume[63:32];
            REG_OPNA_METER_2:    read_data_mux = {8'h00, opna_meter_volume[87:64]};
            REG_OPNA_METER_FLAGS: read_data_mux = {21'h000000,
                                                    opna_meter_trigger};
            default: begin
                read_data_mux = 32'h00000000;
                read_address_valid = 1'b0;
            end
        endcase

        command_word = strobe_masked(w_hold_data, w_hold_strb);
    end

    assign s_axi_awready = !aw_hold_valid && !s_axi_bvalid;
    assign s_axi_wready  = !w_hold_valid && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    retrofm_sync_fifo #(
        .DATA_WIDTH(64),
        .DEPTH(EVENT_FIFO_DEPTH)
    ) event_fifo (
        .clk(s_axi_aclk), .rst(rst), .flush(event_flush_pulse),
        .wr_en(event_fifo_wr_en), .wr_data(event_fifo_wr_data),
        .wr_accept(event_fifo_wr_accept),
        .overflow_pulse(event_fifo_overflow),
        .rd_en(event_fifo_rd_en), .rd_data(event_fifo_rd_data),
        .rd_valid(event_fifo_rd_valid),
        .underflow_pulse(event_fifo_underflow),
        .full(event_fifo_full_raw), .empty(event_fifo_empty_raw),
        .count(event_fifo_count)
    );

    retrofm_fifo_prefetch_bridge #(.DATA_WIDTH(64)) event_bridge (
        .clk(s_axi_aclk), .rst(rst), .flush(event_flush_pulse),
        .fifo_empty(event_fifo_empty_raw), .fifo_rd_en(event_fifo_rd_en),
        .fifo_rd_valid(event_fifo_rd_valid), .fifo_rd_data(event_fifo_rd_data),
        .stream_valid(bridge_stream_valid), .stream_data(bridge_stream_data),
        .stream_ready(bridge_stream_ready), .occupied(bridge_occupied)
    );

    retrofm_event_scheduler scheduler (
        .clk(s_axi_aclk), .rst(rst), .clear(event_flush_pulse),
        .clear_stats(clear_faults_pulse), .run(control_reg[0]),
        .event_valid(bridge_stream_valid), .event_data(bridge_stream_data),
        .event_ready(bridge_stream_ready),
        .source_has_event(!event_empty_logical),
        .jt51_ready(jt51_ready), .jt03_ready(jt03_ready),
        .jt51_wr(jt51_wr), .jt51_reg(jt51_reg), .jt51_data(jt51_data),
        .jt03_wr(jt03_wr), .jt03_port(jt03_port),
        .jt03_reg(jt03_reg), .jt03_data(jt03_data),
        .end_pulse(end_pulse), .diagnostic_pulse(diagnostic_pulse),
        .pending(scheduler_pending), .halted(scheduler_halted),
        .core_stalled(scheduler_core_stalled),
        .playback_advancing(scheduler_playback_advancing),
        .underrun_active(scheduler_underrun_active),
        .late_pulse(scheduler_late_pulse),
        .underrun_pulse(scheduler_underrun_pulse),
        .late_count(late_count), .underrun_count(underrun_count),
        .playback_cycles(scheduler_playback_cycles),
        .scheduled_cycles(scheduler_scheduled_cycles)
    );

    retrofm_sync_fifo #(
        .DATA_WIDTH(32),
        .DEPTH(PCM_FIFO_DEPTH)
    ) pcm_fifo (
        .clk(s_axi_aclk), .rst(rst), .flush(pcm_flush_pulse),
        .wr_en(pcm_fifo_wr_en), .wr_data(pcm_fifo_wr_data),
        .wr_accept(pcm_fifo_wr_accept),
        .overflow_pulse(pcm_fifo_overflow),
        .rd_en(pcm_pop && pcm_enable),
        .rd_data(pcm_frame), .rd_valid(pcm_valid),
        .underflow_pulse(pcm_fifo_underflow),
        .full(pcm_fifo_full), .empty(pcm_fifo_empty),
        .count(pcm_fifo_count)
    );

    always_ff @(posedge s_axi_aclk) begin
        if (rst) begin
            aw_hold_addr          <= '0;
            aw_hold_valid         <= 1'b0;
            w_hold_data           <= '0;
            w_hold_strb           <= '0;
            w_hold_valid          <= 1'b0;
            s_axi_bresp           <= 2'b00;
            s_axi_bvalid          <= 1'b0;
            s_axi_rdata           <= '0;
            s_axi_rresp           <= 2'b00;
            s_axi_rvalid          <= 1'b0;

            control_reg           <= 32'h00000000;
            event_lo_staging      <= 32'h00000000;
            event_hi_staging      <= 32'h00000000;
            event_watermark       <= 32'd512;
            pcm_frame_staging     <= 32'h00000000;
            volume_reg            <= 32'h00008000;
            // A valid idle clock lets the JT03 reset controller complete
            // before the first VGM header supplies its track-specific clock.
            ym2203_clock_reg       <= 32'd4000000;
            opna_sample_addr_reg    <= '0;
            opna_sample_write       <= 1'b0;
            opna_sample_write_addr  <= '0;
            opna_sample_write_data  <= '0;
            opna_sample_write_strb  <= '0;
            // LCD_AUX[2:0] = {CS_N, RESET_N, D/C}.  Deselect the panel and
            // release reset until firmware starts the validated init flow.
            lcd_aux_reg           <= 32'h00000006;
            playback_snapshot     <= 64'h0000000000000000;
            playback_time_offset  <= 64'h0000000000000000;

            event_overflow_sticky <= 1'b0;
            event_underrun_sticky <= 1'b0;
            late_sticky           <= 1'b0;
            pcm_overflow_sticky   <= 1'b0;
            pcm_underrun_sticky   <= 1'b0;

            event_fifo_wr_en      <= 1'b0;
            event_fifo_wr_data    <= '0;
            pcm_fifo_wr_en        <= 1'b0;
            pcm_fifo_wr_data      <= '0;
            mute_pulse            <= 1'b0;
            unmute_pulse          <= 1'b0;
            core_reset_pulse      <= 1'b0;
            event_flush_pulse     <= 1'b0;
            pcm_flush_pulse       <= 1'b0;
            clear_faults_pulse    <= 1'b0;
            command_cdc_fault_clear_pulse <= 1'b0;
            jt03_meter_trigger_clear <= 1'b0;
            opna_meter_trigger_clear <= 1'b0;
            opna_sample_write <= 1'b0;
        end else begin
            event_fifo_wr_en   <= 1'b0;
            pcm_fifo_wr_en     <= 1'b0;
            mute_pulse         <= 1'b0;
            unmute_pulse       <= 1'b0;
            core_reset_pulse   <= 1'b0;
            event_flush_pulse  <= 1'b0;
            pcm_flush_pulse    <= 1'b0;
            clear_faults_pulse <= 1'b0;
            command_cdc_fault_clear_pulse <= 1'b0;
            jt03_meter_trigger_clear <= 1'b0;
            opna_meter_trigger_clear <= 1'b0;
            opna_sample_write <= 1'b0;

            if (s_axi_awready && s_axi_awvalid) begin
                aw_hold_addr  <= s_axi_awaddr;
                aw_hold_valid <= 1'b1;
            end
            if (s_axi_wready && s_axi_wvalid) begin
                w_hold_data  <= s_axi_wdata;
                w_hold_strb  <= s_axi_wstrb;
                w_hold_valid <= 1'b1;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (!s_axi_bvalid && aw_hold_valid && w_hold_valid) begin
                aw_hold_valid <= 1'b0;
                w_hold_valid  <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= write_address_valid(aw_hold_addr[7:0]) ?
                                 2'b00 : 2'b10;

                case (aw_hold_addr[7:0])
                    REG_CONTROL:
                        control_reg <= merge_wstrb(control_reg,
                                                   w_hold_data,
                                                   w_hold_strb);
                    REG_COMMAND: begin
                        mute_pulse         <= command_word[0];
                        unmute_pulse       <= command_word[1];
                        core_reset_pulse   <= command_word[2];
                        event_flush_pulse  <= command_word[3];
                        pcm_flush_pulse    <= command_word[4];
                        clear_faults_pulse <= command_word[5];
                        if (command_word[5]) begin
                            event_overflow_sticky <= 1'b0;
                            event_underrun_sticky <= 1'b0;
                            late_sticky           <= 1'b0;
                            pcm_overflow_sticky   <= 1'b0;
                            pcm_underrun_sticky   <= 1'b0;
                        end
                    end
                    REG_EVENT_LO:
                        event_lo_staging <= merge_wstrb(event_lo_staging,
                                                       w_hold_data,
                                                       w_hold_strb);
                    REG_EVENT_HI: begin
                        if (|w_hold_strb) begin
                            event_hi_staging <= merge_wstrb(event_hi_staging,
                                                           w_hold_data,
                                                           w_hold_strb);
                            if (!event_full_logical) begin
                                event_fifo_wr_data <= {
                                    merge_wstrb(event_hi_staging,
                                                w_hold_data,
                                                w_hold_strb),
                                    event_lo_staging};
                                event_fifo_wr_en <= 1'b1;
                            end else begin
                                event_overflow_sticky <= 1'b1;
                            end
                        end
                    end
                    REG_EVENT_WATERMARK:
                        event_watermark <= merge_wstrb(event_watermark,
                                                      w_hold_data,
                                                      w_hold_strb);
                    REG_PCM_FRAME: begin
                        if (|w_hold_strb) begin
                            pcm_frame_staging <= merge_wstrb(pcm_frame_staging,
                                                            w_hold_data,
                                                            w_hold_strb);
                            pcm_fifo_wr_data <= merge_wstrb(pcm_frame_staging,
                                                           w_hold_data,
                                                           w_hold_strb);
                            pcm_fifo_wr_en <= 1'b1;
                        end
                    end
                    REG_VOLUME:
                        volume_reg <= merge_wstrb(volume_reg,
                                                  w_hold_data,
                                                  w_hold_strb);
                    REG_YM2203_CLOCK:
                        ym2203_clock_reg <= merge_wstrb(ym2203_clock_reg,
                                                       w_hold_data,
                                                       w_hold_strb);
                    REG_OPNA_SAMPLE_ADDR:
                        opna_sample_addr_reg <= opna_sample_addr_merged[16:0];
                    REG_OPNA_SAMPLE_DATA: begin
                        opna_sample_write <= |w_hold_strb;
                        opna_sample_write_addr <= opna_sample_addr_reg;
                        opna_sample_write_data <= w_hold_data;
                        opna_sample_write_strb <= w_hold_strb;
                        opna_sample_addr_reg <= opna_sample_addr_reg + 17'd4;
                    end
                    REG_LCD_AUX:
                        lcd_aux_reg <= merge_wstrb(lcd_aux_reg,
                                                   w_hold_data,
                                                   w_hold_strb);
                    REG_IRQ_STATUS: begin
                        if (command_word[1]) event_overflow_sticky <= 1'b0;
                        if (command_word[2]) event_underrun_sticky <= 1'b0;
                        if (command_word[3]) late_sticky <= 1'b0;
                        if (command_word[4]) pcm_overflow_sticky <= 1'b0;
                        if (command_word[5]) pcm_underrun_sticky <= 1'b0;
                        command_cdc_fault_clear_pulse <= command_word[6];
                    end
                    default: begin
                        // Invalid/read-only writes return SLVERR above.
                    end
                endcase
            end

            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
            if (s_axi_arready && s_axi_arvalid) begin
                s_axi_rdata  <= read_data_mux;
                s_axi_rresp  <= read_address_valid ? 2'b00 : 2'b10;
                s_axi_rvalid <= 1'b1;
                if (s_axi_araddr[7:0] == REG_PLAY_CYCLES_LO)
                    playback_snapshot <= playback_cycles;
                if (s_axi_araddr[7:0] == REG_JT03_METER_HI)
                    jt03_meter_trigger_clear <= 1'b1;
                if (s_axi_araddr[7:0] == REG_OPNA_METER_FLAGS)
                    opna_meter_trigger_clear <= 1'b1;
            end

            if (event_fifo_overflow)
                event_overflow_sticky <= 1'b1;
            if (scheduler_underrun_pulse)
                event_underrun_sticky <= 1'b1;
            if (scheduler_late_pulse)
                late_sticky <= 1'b1;
            if (pcm_fifo_overflow)
                pcm_overflow_sticky <= 1'b1;
            if (pcm_fifo_underflow)
                pcm_underrun_sticky <= 1'b1;
            if (clear_faults_pulse)
                playback_time_offset <= scheduler_playback_cycles +
                    (scheduler_playback_advancing ? 64'd1 : 64'd0);
            // Scheduler clear and the software-visible playback epoch must
            // take effect together after an event-FIFO flush.
            if (event_flush_pulse)
                playback_time_offset <= 64'h0000000000000000;
        end
    end

    // Protection properties are intentionally consumed but unused.
    logic unused_prot;
    always_comb unused_prot = ^{s_axi_awprot, s_axi_arprot,
                                event_fifo_wr_accept,
                                pcm_fifo_wr_accept,
                                event_fifo_underflow,
                                event_fifo_full_raw,
                                scheduler_core_stalled,
                                scheduler_scheduled_cycles};

`ifndef SYNTHESIS
    initial begin
        if (AXI_ADDR_WIDTH < 8)
            $fatal(1, "retrofm_pl_frontend AXI_ADDR_WIDTH must be at least 8");
        if (EVENT_FIFO_DEPTH > 8191 || PCM_FIFO_DEPTH > 8191)
            $fatal(1, "status level fields support at most 8191 entries");
    end
`endif
endmodule
