// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Complete RetroFM programmable-logic subsystem.  AXI/deadlines/mixing/DAC
// run from the 100 MHz PS FCLK0; Yamaha cores run from the exact 80 MHz Clocking
// Wizard output supplied by the block design.
module retrofm_pl_top (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 S_AXI_CLK CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_CLK, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 100000000" *)
    input  logic        s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 S_AXI_RST RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_RST, POLARITY ACTIVE_LOW" *)
    input  logic        s_axi_aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 AUDIO_CLK CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME AUDIO_CLK, ASSOCIATED_RESET rst_audio, FREQ_HZ 80000000" *)
    input  logic        clk_audio,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 AUDIO_RST RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME AUDIO_RST, POLARITY ACTIVE_HIGH" *)
    input  logic        rst_audio,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8, FREQ_HZ 100000000, HAS_BURST 0, HAS_LOCK 0, HAS_CACHE 0, HAS_REGION 0, HAS_QOS 0, HAS_PROT 1, SUPPORTS_NARROW_BURST 0, MAX_BURST_LENGTH 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  logic [7:0]  s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *) input logic [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input logic s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output logic s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input logic [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input logic [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input logic s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output logic s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output logic [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output logic s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input logic s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input logic [7:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *) input logic [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input logic s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output logic s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output logic [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output logic [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output logic s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input logic s_axi_rready,

    input  logic [4:0]  button_n,
    input  logic        lcd_sclk_from_ps,
    input  logic        lcd_mosi_from_ps,
    output logic        lcd_cs,
    output logic        lcd_dc,
    output logic        lcd_res,
    output logic        lcd_sclk,
    output logic        lcd_mosi,
    output logic        audio_sd_l,
    output logic        audio_sd_r,
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 IRQ INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME IRQ, SENSITIVITY LEVEL_HIGH" *)
    output logic        irq
);
    localparam logic [1:0] CHIP_JT51 = 2'd1;
    localparam logic [1:0] CHIP_JT03 = 2'd2;
    localparam logic [1:0] CHIP_OPNA = 2'd3;

    logic rst_system;
    assign rst_system = !s_axi_aresetn;

    logic [4:0] buttons;
    retrofm_buttons buttons_i (
        .clk(s_axi_aclk), .rst(rst_system),
        .button_n(button_n), .pressed(buttons)
    );

    logic jt51_scheduler_ready;
    logic jt03_scheduler_ready;
    logic jt51_wr;
    logic [7:0] jt51_reg;
    logic [7:0] jt51_data;
    logic jt03_wr;
    logic jt03_port;
    logic [7:0] jt03_reg;
    logic [7:0] jt03_data;
    logic mute_pulse;
    logic unmute_pulse;
    logic core_reset_pulse;
    logic event_flush_pulse;
    logic pcm_flush_pulse;
    logic clear_faults_pulse;
    logic command_cdc_fault_clear_pulse;
    logic [15:0] volume_q15;
    logic [31:0] ym2203_clock_hz;
    logic [1:0] active_chip;
    logic pcm_enable;
    logic fm_mute_enable;
    logic [31:0] lcd_aux;
    logic pcm_pop;
    logic pcm_valid;
    logic [31:0] pcm_frame;
    logic [13:0] key_masks;
    logic [7:0] jt51_key_mask;
    logic [5:0] jt03_activity;
    logic [47:0] jt03_meter_volume;
    logic [5:0] jt03_meter_trigger;
    logic jt03_meter_trigger_clear;
    logic [10:0] opna_activity;
    logic [87:0] opna_meter_volume;
    logic [10:0] opna_meter_trigger;
    logic opna_meter_trigger_clear;
    logic [15:0] peak_left;
    logic [15:0] peak_right;
    logic [255:0] spectrum_bins;
    logic command_cdc_fault;
    logic scheduler_underrun_active;

    function automatic logic [31:0] sanitize_ym2203_clock(
        input logic [31:0] requested_clock
    );
        begin
            if ((requested_clock != 0) &&
                (requested_clock <= 32'd80000000))
                sanitize_ym2203_clock = requested_clock;
            else
                sanitize_ym2203_clock = 32'd4000000;
        end
    endfunction

    // Reset request/acknowledge keeps both sides of each asynchronous command
    // FIFO in reset together.  The source side is released only after the
    // audio side has completed and acknowledged reset deassertion.
    logic reset_request_system;
    logic reset_ack_seen_system;
    logic bridge_reset_system;
    logic [31:0] ym2203_clock_hold_system;
    logic audio_reset_ack;
    (* ASYNC_REG = "TRUE" *) logic audio_reset_ack_meta;
    (* ASYNC_REG = "TRUE" *) logic audio_reset_ack_sync;

    always_ff @(posedge s_axi_aclk) begin
        if (rst_system) begin
            audio_reset_ack_meta <= 1'b0;
            audio_reset_ack_sync <= 1'b0;
            reset_request_system <= 1'b1;
            reset_ack_seen_system <= 1'b0;
            bridge_reset_system <= 1'b1;
            ym2203_clock_hold_system <= 32'd4000000;
        end else begin
            audio_reset_ack_meta <= audio_reset_ack;
            audio_reset_ack_sync <= audio_reset_ack_meta;

            if (core_reset_pulse || event_flush_pulse) begin
                // The bundled configuration remains fixed throughout the
                // request/ack reset handshake.  The audio side samples it
                // only after the synchronized request has been stable for
                // several 80 MHz clocks.
                ym2203_clock_hold_system <=
                    sanitize_ym2203_clock(ym2203_clock_hz);
                reset_request_system <= 1'b1;
                reset_ack_seen_system <= 1'b0;
                bridge_reset_system <= 1'b1;
            end else if (bridge_reset_system) begin
                if (!reset_ack_seen_system && audio_reset_ack_sync) begin
                    reset_request_system <= 1'b0;
                    reset_ack_seen_system <= 1'b1;
                end else if (reset_ack_seen_system &&
                             !audio_reset_ack_sync) begin
                    bridge_reset_system <= 1'b0;
                    reset_ack_seen_system <= 1'b0;
                end
            end
        end
    end

    (* ASYNC_REG = "TRUE" *) logic reset_request_audio_meta;
    (* ASYNC_REG = "TRUE" *) logic reset_request_audio_sync;
    logic core_reset_audio;
    logic [8:0] reset_audio_cycles;
    logic [2:0] reset_master_enables;
    logic [31:0] ym2203_clock_audio;
    logic ym2203_master_cen;
    // CONTROL is written in the 100 MHz AXI domain.  A track is stopped
    // while its chip selection changes and command traffic is held behind the
    // bridge reset, but the audio-domain command sinks must never consume the
    // raw asynchronous bits.  This two-stage capture is therefore safe for
    // the stable selection and prevents a transient write going to both OPN
    // implementations.
    (* ASYNC_REG = "TRUE" *) logic [1:0] active_chip_audio_meta;
    (* ASYNC_REG = "TRUE" *) logic [1:0] active_chip_audio;

    always_ff @(posedge clk_audio) begin
        if (rst_audio) begin
            reset_request_audio_meta <= 1'b1;
            reset_request_audio_sync <= 1'b1;
            core_reset_audio <= 1'b1;
            audio_reset_ack <= 1'b0;
            reset_audio_cycles <= '0;
            reset_master_enables <= '0;
            ym2203_clock_audio <= 32'd4000000;
            active_chip_audio_meta <= CHIP_JT03;
            active_chip_audio <= CHIP_JT03;
        end else begin
            reset_request_audio_meta <= reset_request_system;
            reset_request_audio_sync <= reset_request_audio_meta;
            active_chip_audio_meta <= active_chip;
            active_chip_audio <= active_chip_audio_meta;
            if (reset_request_audio_sync) begin
                core_reset_audio <= 1'b1;
                if (reset_audio_cycles == 9'd3)
                    ym2203_clock_audio <= ym2203_clock_hold_system;
                if (reset_audio_cycles != 9'd319)
                    reset_audio_cycles <= reset_audio_cycles + 1'b1;
                if (ym2203_master_cen && reset_master_enables != 3'd7)
                    reset_master_enables <= reset_master_enables + 1'b1;
                if ((reset_audio_cycles == 9'd319) &&
                    (reset_master_enables >= 3'd6))
                    audio_reset_ack <= 1'b1;
            end else begin
                core_reset_audio <= 1'b0;
                audio_reset_ack <= 1'b0;
                reset_audio_cycles <= '0;
                reset_master_enables <= '0;
            end
        end
    end

    logic jt51_queue_ready;
    logic jt03_queue_ready;
    logic jt51_queue_valid;
    logic jt03_queue_valid;
    logic [7:0] jt51_queue_reg;
    logic [7:0] jt51_queue_data;
    logic [7:0] jt03_queue_reg;
    logic [7:0] jt03_queue_data;
    logic jt03_queue_port;
    logic jt51_queue_overflow;
    logic jt03_queue_overflow;
    logic [4:0] jt51_queue_level;
    logic [4:0] jt03_queue_level;
    logic jt51_bridge_ready;
    logic jt03_bridge_ready;

    retrofm_command_queue #(.DEPTH(16)) jt51_command_queue_i (
        .clk(s_axi_aclk), .rst(rst_system), .flush(bridge_reset_system),
        .command_pulse(jt51_wr), .command_port(1'b0), .command_reg(jt51_reg),
        .command_data(jt51_data), .scheduler_ready(jt51_queue_ready),
        .stream_valid(jt51_queue_valid), .stream_ready(jt51_bridge_ready), .stream_port(),
        .stream_reg(jt51_queue_reg), .stream_data(jt51_queue_data),
        .overflow_pulse(jt51_queue_overflow), .level(jt51_queue_level)
    );

    retrofm_command_queue #(.DEPTH(16)) jt03_command_queue_i (
        .clk(s_axi_aclk), .rst(rst_system), .flush(bridge_reset_system),
        .command_pulse(jt03_wr), .command_port(jt03_port), .command_reg(jt03_reg),
        .command_data(jt03_data), .scheduler_ready(jt03_queue_ready),
        .stream_valid(jt03_queue_valid), .stream_ready(jt03_bridge_ready),
        .stream_port(jt03_queue_port),
        .stream_reg(jt03_queue_reg), .stream_data(jt03_queue_data),
        .overflow_pulse(jt03_queue_overflow), .level(jt03_queue_level)
    );

    assign jt51_scheduler_ready = jt51_queue_ready && !bridge_reset_system;
    assign jt03_scheduler_ready = jt03_queue_ready && !bridge_reset_system;

    logic jt51_audio_valid;
    logic jt03_audio_valid;
    logic jt51_audio_ready;
    logic jt03_audio_ready;
    logic jt03_core_ready;
    logic opna_core_ready;
    logic [7:0] jt51_audio_reg;
    logic [7:0] jt51_audio_data;
    logic [7:0] jt03_audio_reg;
    logic [7:0] jt03_audio_data;
    logic jt03_audio_port;
    logic jt51_bridge_accept;
    logic jt03_bridge_accept;
    logic jt51_bridge_blocked;
    logic jt03_bridge_blocked;
    logic command_backpressure_seen;
    logic clear_bridge_faults;

    assign clear_bridge_faults = clear_faults_pulse ||
                                 command_cdc_fault_clear_pulse;
    assign command_backpressure_seen = jt51_bridge_blocked ||
                                       jt03_bridge_blocked;

    retrofm_yamaha_command_bridge #(.FIFO_ADDR_WIDTH(3)) command_bridge_i (
        .clk_system(s_axi_aclk), .rst_system(bridge_reset_system),
        .clear_blocked(clear_bridge_faults),
        .jt51_src_valid(jt51_queue_valid),
        .jt51_src_ready(jt51_bridge_ready),
        .jt51_src_reg(jt51_queue_reg), .jt51_src_data(jt51_queue_data),
        .jt51_src_accept(jt51_bridge_accept),
        .jt51_blocked_sticky(jt51_bridge_blocked),
        .jt03_src_valid(jt03_queue_valid),
        .jt03_src_ready(jt03_bridge_ready),
        .jt03_src_port(jt03_queue_port),
        .jt03_src_reg(jt03_queue_reg), .jt03_src_data(jt03_queue_data),
        .jt03_src_accept(jt03_bridge_accept),
        .jt03_blocked_sticky(jt03_bridge_blocked),
        .clk_audio(clk_audio), .rst_audio(core_reset_audio || rst_audio),
        .jt51_dst_valid(jt51_audio_valid),
        .jt51_dst_ready(jt51_audio_ready),
        .jt51_dst_reg(jt51_audio_reg), .jt51_dst_data(jt51_audio_data),
        .jt03_dst_valid(jt03_audio_valid),
        .jt03_dst_ready(jt03_audio_ready),
        .jt03_dst_port(jt03_audio_port),
        .jt03_dst_reg(jt03_audio_reg), .jt03_dst_data(jt03_audio_data)
    );

    always_ff @(posedge s_axi_aclk) begin
        if (rst_system) begin
            command_cdc_fault <= 1'b0;
        end else if (clear_bridge_faults) begin
            command_cdc_fault <= 1'b0;
        end else if (jt51_queue_overflow || jt03_queue_overflow) begin
            command_cdc_fault <= 1'b1;
        end
    end

    logic signed [15:0] jt51_audio_left;
    logic signed [15:0] jt51_audio_right;
    logic signed [15:0] jt51_full_left;
    logic signed [15:0] jt51_full_right;
    logic jt51_sample_pulse;
    logic [7:0] jt51_status;
    logic jt51_irq_n;

    retrofm_jt51_wrapper jt51_i (
        .clk_audio(clk_audio), .rst(core_reset_audio || rst_audio),
        .cmd_valid(jt51_audio_valid), .cmd_ready(jt51_audio_ready),
        .cmd_reg(jt51_audio_reg), .cmd_data(jt51_audio_data), .cmd_done(),
        .status(jt51_status), .irq_n(jt51_irq_n),
        .sample_pulse(jt51_sample_pulse),
        .audio_left(jt51_full_left), .audio_right(jt51_full_right),
        // Preserve the reconstructed YM3012-compatible left/right path for
        // normal playback.  The full-resolution outputs above are retained
        // only as diagnostics and must not bypass that quantization stage.
        .dac_left(jt51_audio_left), .dac_right(jt51_audio_right),
        .cen_4mhz(), .cen_2mhz()
    );

    logic signed [15:0] jt03_audio_fm;
    logic [9:0] jt03_audio_psg;
    logic signed [15:0] jt03_audio_combined;
    logic jt03_sample_pulse;
    logic [7:0] jt03_status;
    logic jt03_irq_n;
    logic ym2203_clock_invalid;

    retrofm_jt03_wrapper jt03_i (
        .clk_audio(clk_audio), .rst(core_reset_audio || rst_audio),
        .master_clock_hz(ym2203_clock_audio),
        .master_clock_cen(ym2203_master_cen),
        .master_clock_invalid(ym2203_clock_invalid),
        .cmd_valid(jt03_audio_valid && active_chip_audio == CHIP_JT03),
        .cmd_ready(jt03_core_ready),
        .cmd_reg(jt03_audio_reg), .cmd_data(jt03_audio_data), .cmd_done(),
        .status(jt03_status), .irq_n(jt03_irq_n),
        .sample_pulse(jt03_sample_pulse), .fm_audio(jt03_audio_fm),
        .psg_audio(jt03_audio_psg), .combined_audio(jt03_audio_combined),
        .core_accept_pulse()
    );

    logic signed [15:0] opna_audio_left;
    logic signed [15:0] opna_audio_right;
    logic opna_sample_pulse;
    logic [7:0] opna_status;
    logic opna_irq_n;
    logic opna_clock_invalid;
    logic opna_sample_write;
    logic [16:0] opna_sample_write_addr;
    logic [31:0] opna_sample_write_data;
    logic [3:0] opna_sample_write_strb;
    logic [23:0] opna_adpcmb_addr;
    logic opna_adpcmb_roe_n;
    logic [7:0] opna_adpcmb_data;

    retrofm_jt2608_wrapper opna_i (
        .clk_audio(clk_audio), .rst(core_reset_audio || rst_audio),
        .master_clock_hz(ym2203_clock_audio), .master_clock_cen(),
        .master_clock_invalid(opna_clock_invalid),
        .adpcmb_addr(opna_adpcmb_addr), .adpcmb_roe_n(opna_adpcmb_roe_n),
        .adpcmb_data(opna_adpcmb_data),
        .cmd_valid(jt03_audio_valid && active_chip_audio == CHIP_OPNA),
        .cmd_ready(opna_core_ready), .cmd_port(jt03_audio_port),
        .cmd_reg(jt03_audio_reg), .cmd_data(jt03_audio_data), .cmd_done(),
        .status(opna_status), .irq_n(opna_irq_n),
        .sample_pulse(opna_sample_pulse), .audio_left(opna_audio_left),
        .audio_right(opna_audio_right), .core_accept_pulse()
    );

    // 128 KiB covers every PCM asset in the supplied sample archive
    // (largest: 120,136 bytes).  Addresses above this range return a mirror;
    // firmware validates imported asset sizes before upload.
    retrofm_opna_adpcmb_ram #(.ADDR_WIDTH(17)) opna_adpcmb_ram_i (
        .sys_clk(s_axi_aclk), .sys_wr(opna_sample_write),
        .sys_addr(opna_sample_write_addr), .sys_data(opna_sample_write_data),
        .sys_wstrb(opna_sample_write_strb), .audio_clk(clk_audio),
        .audio_addr(opna_adpcmb_addr[16:0]), .audio_data(opna_adpcmb_data)
    );

    // JT03 and OPNA share the same serialized OPN command transport because
    // CONTROL selects exactly one active OPN-family core for a track.
    always_comb begin
        case (active_chip_audio)
            CHIP_JT03: jt03_audio_ready = jt03_core_ready;
            CHIP_OPNA: jt03_audio_ready = opna_core_ready;
            default:   jt03_audio_ready = 1'b0;
        endcase
    end

    logic [31:0] jt51_sample_system;
    logic [15:0] jt03_sample_system;
    logic [31:0] opna_sample_system;
    logic jt51_sample_update;
    logic jt03_sample_update;
    logic opna_sample_update;

    retrofm_sample_cdc #(.DATA_WIDTH(32)) jt51_sample_cdc_i (
        .src_clk(clk_audio), .src_rst(core_reset_audio || rst_audio),
        .src_pulse(jt51_sample_pulse),
        // Use JT51's hardware-faithful YM3012-compatible representation.
        // The full-resolution outputs remain available above for diagnostics.
        .src_data({jt51_audio_right, jt51_audio_left}),
        .dst_clk(s_axi_aclk), .dst_rst(rst_system || bridge_reset_system),
        .dst_data(jt51_sample_system), .dst_update(jt51_sample_update)
    );

    retrofm_sample_cdc #(.DATA_WIDTH(16)) jt03_sample_cdc_i (
        .src_clk(clk_audio), .src_rst(core_reset_audio || rst_audio),
        .src_pulse(jt03_sample_pulse),
        // Upstream JT03's signed combined output applies its audited FM/SSG
        // scale.  The mixer duplicates this mono sample into L and R.
        .src_data(jt03_audio_combined),
        .dst_clk(s_axi_aclk), .dst_rst(rst_system || bridge_reset_system),
        .dst_data(jt03_sample_system), .dst_update(jt03_sample_update)
    );

    retrofm_sample_cdc #(.DATA_WIDTH(32)) opna_sample_cdc_i (
        .src_clk(clk_audio), .src_rst(core_reset_audio || rst_audio),
        .src_pulse(opna_sample_pulse), .src_data({opna_audio_right, opna_audio_left}),
        .dst_clk(s_axi_aclk), .dst_rst(rst_system || bridge_reset_system),
        .dst_data(opna_sample_system), .dst_update(opna_sample_update)
    );

    logic sample_48k_ce;
    logic [31:0] sample_48k_phase;
    logic mixer_ce;
    logic mixer_gain_ce;
    logic pcm_mix_event;
    logic jt51_mix_event;
    logic jt03_mix_event;
    logic opna_mix_event;
    logic mixer_out_valid;
    logic pcm_mix_valid;
    logic [31:0] pcm_mix_frame;

    retrofm_fractional_ce #(.BASE_HZ(100000000), .ACC_WIDTH(32)) ce_48k_i (
        .clk(s_axi_aclk), .rst(rst_system), .enable(1'b1),
        .rate_hz(32'd48000), .ce(sample_48k_ce), .phase(sample_48k_phase)
    );

    assign pcm_pop = sample_48k_ce;

    // `pcm_valid` is a one-system-clock FIFO-read strobe.  A native-rate
    // JT51 mixer event can arrive at any later system clock, so retain each
    // accepted PCM frame instead of feeding that transient pulse directly
    // into the mixer.  A new frame bypasses the hold at its 48 kHz capture.
    retrofm_pcm_sample_hold pcm_sample_hold_i (
        .clk(s_axi_aclk), .rst(rst_system), .flush(pcm_flush_pulse),
        .source_enable(pcm_enable), .frame_tick(pcm_mix_event),
        .frame_valid(pcm_valid),
        .frame(pcm_frame), .sample_valid(pcm_mix_valid),
        .sample_frame(pcm_mix_frame)
    );

    always_ff @(posedge s_axi_aclk) begin
        if (rst_system) begin
            pcm_mix_event <= 1'b0;
            jt51_mix_event <= 1'b0;
            jt03_mix_event <= 1'b0;
            opna_mix_event <= 1'b0;
        end else begin
            // The FIFO and the CDC register their outputs on their source
            // edge.  Delay each event one 100 MHz cycle so the mixer captures
            // the coherent newly registered value, never the old one.
            pcm_mix_event <= sample_48k_ce;
            jt51_mix_event <= jt51_sample_update;
            jt03_mix_event <= jt03_sample_update;
            opna_mix_event <= opna_sample_update;
        end
    end

    // JT51 is now a direct zero-order-held 62.5 kHz source.  No resampler is
    // instantiated in this audio path.  The PCM event also advances the gain
    // ramps at their established 48 kHz cadence; re-capturing an unchanged
    // held JT51 value during that event does not interpolate it.
    always_comb begin
        mixer_ce = pcm_mix_event || jt51_mix_event || jt03_mix_event ||
                   opna_mix_event;
        mixer_gain_ce = pcm_mix_event;
    end

    logic mute_request;
    logic pending_unmute;
    retrofm_mute_controller mute_controller_i (
        .clk(s_axi_aclk), .rst(rst_system),
        .mute_pulse(mute_pulse), .unmute_pulse(unmute_pulse),
        .core_reset_pulse(core_reset_pulse),
        .bridge_reset(bridge_reset_system),
        .mute_request(mute_request), .pending_unmute(pending_unmute)
    );

    // The DAC receives signed Q16.4.  A conventional signed-16 source sample
    // N is represented as N*16, retaining four fractional gain/mix bits until
    // the 100 MHz second-order sigma-delta modulators.
    logic signed [19:0] mixed_left;
    logic signed [19:0] mixed_right;
    logic signed [19:0] mixed_dac_left_next;
    logic signed [19:0] mixed_dac_right_next;
    logic signed [19:0] mixed_dac_left;
    logic signed [19:0] mixed_dac_right;
    logic signed [15:0] mixed_monitor_left_next;
    logic signed [15:0] mixed_monitor_right_next;
    logic signed [15:0] mixed_monitor_left;
    logic signed [15:0] mixed_monitor_right;
    logic [15:0] mute_gain_q15;
    logic [15:0] fm_mute_gain_q15;

    retrofm_stereo_mixer mixer_i (
        .clk(s_axi_aclk), .rst(rst_system), .sample_ce(mixer_ce),
        .gain_ce(mixer_gain_ce),
        .jt51_enable(active_chip == CHIP_JT51),
        .jt51_left($signed(jt51_sample_system[15:0])),
        .jt51_right($signed(jt51_sample_system[31:16])),
        .jt03_enable(active_chip == CHIP_JT03),
        .jt03_mono($signed(jt03_sample_system)),
        .opna_enable(active_chip == CHIP_OPNA),
        .opna_left($signed(opna_sample_system[15:0])),
        .opna_right($signed(opna_sample_system[31:16])),
        .pcm_enable(pcm_mix_valid),
        .pcm_left($signed(pcm_mix_frame[15:0])),
        .pcm_right($signed(pcm_mix_frame[31:16])),
        .volume_q15(volume_q15), .mute_request(mute_request),
        // A temporarily empty register-event FIFO must not silence an FM
        // chip: between writes the Yamaha core is expected to keep sounding
        // its current envelopes and phases.  Late/overflow diagnostics remain
        // visible to firmware, while global mute still handles stop/pause.
        // CONTROL[2] independently ramps FM down/up, retaining PDX/PCM so
        // MDX PCM balance can be auditioned without stopping sequencing.
        .fm_mute_request(fm_mute_enable),
        .mute_gain_q15(mute_gain_q15),
        .fm_mute_gain_q15(fm_mute_gain_q15),
        .out_valid(mixer_out_valid),
        .out_left(mixed_left), .out_right(mixed_right)
    );

    // Keep the same seven-eighths full-scale margin required by the proven
    // second-order loop, but make it an explicit Q16.4 limiter.  Both the DAC
    // and monitor path below therefore observe the same post-limiter signal.
    function automatic logic signed [19:0] clamp_sdm_q4(
        input logic signed [19:0] sample_q4
    );
        begin
            if (sample_q4 > 20'sh70000)
                clamp_sdm_q4 = 20'sh70000;
            else if (sample_q4 < -20'sh70000)
                clamp_sdm_q4 = -20'sh70000;
            else
                clamp_sdm_q4 = sample_q4;
        end
    endfunction

    always_comb begin
        mixed_dac_left_next = clamp_sdm_q4(mixed_left);
        mixed_dac_right_next = clamp_sdm_q4(mixed_right);
    end

    // Keep the Q16.4 clamp directly in front of the DAC, but register it
    // once before the high-rate loop.  This does not change a held source
    // value or its numeric representation; it only isolates the mixer's
    // final arithmetic from the 100 MHz sigma-delta feedback timing cone.
    always_ff @(posedge s_axi_aclk) begin
        if (rst_system) begin
            mixed_dac_left <= '0;
            mixed_dac_right <= '0;
        end else begin
            mixed_dac_left <= mixed_dac_left_next;
            mixed_dac_right <= mixed_dac_right_next;
        end
    end

    retrofm_sigma_delta #(.WIDTH(20)) dac_left_i (
        .clk(s_axi_aclk), .rst(rst_system),
        .sample(mixed_dac_left), .bit_out(audio_sd_l)
    );
    retrofm_sigma_delta #(.WIDTH(20)) dac_right_i (
        .clk(s_axi_aclk), .rst(rst_system),
        .sample(mixed_dac_right), .bit_out(audio_sd_r)
    );

    // Peak meters and the Goertzel display intentionally use signed-16
    // samples.  This rounded/saturated conversion is monitor-only: the audio
    // path above remains Q16.4 all the way into the sigma-delta loop.
    function automatic logic signed [15:0] q4_to_monitor_s16(
        input logic signed [19:0] sample_q4
    );
        logic [20:0] magnitude;
        logic [20:0] rounded_magnitude;
        begin
            if (sample_q4 < 0) begin
                magnitude = $unsigned(-$signed({sample_q4[19], sample_q4}));
                rounded_magnitude = (magnitude + 21'd8) >> 4;
                if (rounded_magnitude >= 21'd32768)
                    q4_to_monitor_s16 = -16'sd32768;
                else
                    q4_to_monitor_s16 = -$signed({1'b0,
                                                    rounded_magnitude[15:0]});
            end else begin
                magnitude = {1'b0, sample_q4};
                rounded_magnitude = (magnitude + 21'd8) >> 4;
                if (rounded_magnitude > 21'd32767)
                    q4_to_monitor_s16 = 16'sh7fff;
                else
                    q4_to_monitor_s16 = $signed({1'b0,
                                                   rounded_magnitude[15:0]});
            end
        end
    endfunction

    always_comb begin
        mixed_monitor_left_next = q4_to_monitor_s16(mixed_dac_left);
        mixed_monitor_right_next = q4_to_monitor_s16(mixed_dac_right);
    end

    // The monitor is intentionally one more 100 MHz cycle behind the DAC.
    // This isolates display-only rounding from peak/Goertzel arithmetic;
    // neither the Q16.4 DAC stream nor its limiting behavior is affected.
    always_ff @(posedge s_axi_aclk) begin
        if (rst_system) begin
            mixed_monitor_left <= '0;
            mixed_monitor_right <= '0;
        end else begin
            mixed_monitor_left <= mixed_monitor_left_next;
            mixed_monitor_right <= mixed_monitor_right_next;
        end
    end

    function automatic logic [15:0] absolute_sample(
        input logic signed [15:0] sample
    );
        begin
            if (sample == 16'sh8000)
                absolute_sample = 16'h8000;
            else if (sample[15])
                absolute_sample = $unsigned(-sample);
            else
                absolute_sample = $unsigned(sample);
        end
    endfunction

    logic [15:0] absolute_left;
    logic [15:0] absolute_right;
    always_comb begin
        absolute_left = absolute_sample(mixed_monitor_left);
        absolute_right = absolute_sample(mixed_monitor_right);
    end

    always_ff @(posedge s_axi_aclk) begin
        if (rst_system || clear_faults_pulse) begin
            peak_left <= '0;
            peak_right <= '0;
        // Peak decay remains calibrated in 48 kHz sample units.  The mixer
        // itself can also update on a native 62.5 kHz JT51 sample, but that
        // must not make the displayed meter decay faster during MDX playback.
        end else if (sample_48k_ce) begin
            if (absolute_left >= peak_left)
                peak_left <= absolute_left;
            else if (peak_left > 16'd64)
                peak_left <= peak_left - 16'd64;
            else
                peak_left <= '0;
            if (absolute_right >= peak_right)
                peak_right <= absolute_right;
            else if (peak_right > 16'd64)
                peak_right <= peak_right - 16'd64;
            else
                peak_right <= '0;
        end
    end

    always_ff @(posedge s_axi_aclk) begin
        if (rst_system || core_reset_pulse || event_flush_pulse) begin
            jt51_key_mask <= '0;
        end else begin
            if (jt51_wr && (jt51_reg == 8'h08)) begin
                if (|jt51_data[6:3])
                    jt51_key_mask[jt51_data[2:0]] <= 1'b1;
                else
                    jt51_key_mask[jt51_data[2:0]] <= 1'b0;
            end
        end
    end

    retrofm_jt03_activity jt03_activity_i (
        .clk(s_axi_aclk), .rst(rst_system),
        .clear(core_reset_pulse || event_flush_pulse),
        .trigger_clear(jt03_meter_trigger_clear),
        .write_pulse(jt03_wr), .reg_address(jt03_reg),
        .write_data(jt03_data), .activity(jt03_activity),
        .meter_volume(jt03_meter_volume),
        .meter_trigger(jt03_meter_trigger)
    );

    retrofm_opna_activity opna_activity_i (
        .clk(s_axi_aclk), .rst(rst_system),
        .clear(core_reset_pulse || event_flush_pulse),
        .trigger_clear(opna_meter_trigger_clear),
        .write_pulse(jt03_wr && active_chip == CHIP_OPNA),
        .write_port1(jt03_port), .reg_address(jt03_reg),
        .write_data(jt03_data), .activity(opna_activity),
        .meter_volume(opna_meter_volume),
        .meter_trigger(opna_meter_trigger)
    );

    assign key_masks = {jt03_activity, jt51_key_mask};

    logic spectrum_block_pulse;
    logic spectrum_busy;
    logic spectrum_overrun;
    retrofm_spectrum spectrum_i (
        .clk(s_axi_aclk), .rst(rst_system),
        // The Goertzel coefficients are calibrated for exactly 48 kHz.  Read
        // the latest held mixer output on that cadence; native JT51 updates
        // remain unresampled in the audio path above.
        .clear_overrun(clear_bridge_faults), .sample_ce(sample_48k_ce),
        .sample_left(mixed_monitor_left),
        .sample_right(mixed_monitor_right),
        .levels(spectrum_bins), .block_pulse(spectrum_block_pulse),
        .busy(spectrum_busy), .overrun_sticky(spectrum_overrun)
    );

    retrofm_pl_frontend frontend_i (
        .s_axi_aclk(s_axi_aclk), .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready), .key_masks(key_masks),
        .jt03_meter_volume(jt03_meter_volume),
        .jt03_meter_trigger(jt03_meter_trigger),
        .jt03_meter_trigger_clear(jt03_meter_trigger_clear),
        .opna_meter_volume(opna_meter_volume),
        .opna_meter_trigger(opna_meter_trigger),
        .opna_meter_trigger_clear(opna_meter_trigger_clear),
        .peak_left(peak_left), .peak_right(peak_right), .buttons(buttons),
        .command_cdc_fault(command_cdc_fault),
        .command_backpressure_seen(command_backpressure_seen),
        .spectrum_bins(spectrum_bins),
        .jt51_ready(jt51_scheduler_ready),
        .jt03_ready(jt03_scheduler_ready),
        .pcm_pop(pcm_pop), .pcm_valid(pcm_valid), .pcm_frame(pcm_frame),
        .jt51_wr(jt51_wr), .jt51_reg(jt51_reg), .jt51_data(jt51_data),
        .jt03_wr(jt03_wr), .jt03_port(jt03_port),
        .jt03_reg(jt03_reg), .jt03_data(jt03_data),
        .end_pulse(), .diagnostic_pulse(), .mute_pulse(mute_pulse),
        .unmute_pulse(unmute_pulse), .core_reset_pulse(core_reset_pulse),
        .event_flush_pulse(event_flush_pulse),
        .pcm_flush_pulse(pcm_flush_pulse),
        .clear_faults_pulse(clear_faults_pulse),
        .command_cdc_fault_clear_pulse(command_cdc_fault_clear_pulse),
        .volume_q15(volume_q15), .ym2203_clock_hz(ym2203_clock_hz),
        .opna_sample_write(opna_sample_write),
        .opna_sample_write_addr(opna_sample_write_addr),
        .opna_sample_write_data(opna_sample_write_data),
        .opna_sample_write_strb(opna_sample_write_strb),
        .active_chip(active_chip), .pcm_enable(pcm_enable),
        .fm_mute_enable(fm_mute_enable),
        .lcd_aux(lcd_aux), .irq(irq), .event_level(), .pcm_level(),
        .event_prefetch_valid(), .scheduler_pending(),
        .scheduler_halted(),
        .scheduler_underrun_active(scheduler_underrun_active),
        .late_count(), .underrun_count(),
        .playback_cycles()
    );

    // Locked LCD_AUX contract: bit 0 D/C, bit 1 active-high RESET_N, bit 2
    // active-low CS_N level (1 deselected, 0 selected).
    assign lcd_dc = lcd_aux[0];
    assign lcd_res = lcd_aux[1];
    assign lcd_cs = lcd_aux[2];
    assign lcd_sclk = lcd_sclk_from_ps;
    assign lcd_mosi = lcd_mosi_from_ps;

    logic unused_status;
    always_comb unused_status = ^{pcm_enable, pcm_flush_pulse,
        jt51_queue_level, jt03_queue_level, jt51_bridge_accept,
        jt03_bridge_accept, jt51_sample_update, jt03_sample_update,
        jt51_status, jt03_status, jt51_irq_n, jt03_irq_n,
        jt51_full_left, jt51_full_right, jt03_audio_fm, jt03_audio_psg,
        opna_status, opna_irq_n, opna_clock_invalid, opna_sample_update,
        opna_adpcmb_roe_n,
        ym2203_clock_invalid, sample_48k_phase, mute_gain_q15,
        fm_mute_gain_q15, pending_unmute,
        spectrum_block_pulse, spectrum_busy, spectrum_overrun};
endmodule
