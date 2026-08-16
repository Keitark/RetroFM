// SPDX-License-Identifier: GPL-3.0-or-later
// OOC-only top that keeps both Yamaha cores and the selected DAC in one cone.

`default_nettype none

module retrofm_vendor_compile_top (
    input  wire                       clk_system,
    input  wire                       rst_system,
    input  wire                       clk_audio,
    input  wire                       rst_audio,
    input  wire                       clear_blocked,
    input  wire [31:0]                ym2203_clock_hz,
    input  wire signed [15:0]         dac_test_sample,
    input  wire                       jt51_cmd_valid,
    input  wire [7:0]                 jt51_cmd_reg,
    input  wire [7:0]                 jt51_cmd_data,
    input  wire                       jt03_cmd_valid,
    input  wire [7:0]                 jt03_cmd_reg,
    input  wire [7:0]                 jt03_cmd_data,
    output wire                       jt51_cmd_ready,
    output wire                       jt03_cmd_ready,
    output wire                       jt51_cmd_accept,
    output wire                       jt03_cmd_accept,
    output wire                       jt51_blocked_sticky,
    output wire                       jt03_blocked_sticky,
    output wire                       jt51_cmd_done,
    output wire                       jt03_cmd_done,
    output wire signed [15:0]         jt51_left,
    output wire signed [15:0]         jt51_right,
    output wire signed [15:0]         jt03_fm,
    output wire [9:0]                 jt03_psg,
    output wire signed [15:0]         jt03_combined,
    output wire [7:0]                 jt51_status,
    output wire [7:0]                 jt03_status,
    output wire                       jt51_irq_n,
    output wire                       jt03_irq_n,
    output wire                       jt51_sample,
    output wire                       jt03_sample,
    output wire                       pwm_left,
    output wire                       pwm_right
);

    wire jt51_audio_valid;
    wire jt51_audio_ready;
    wire [7:0] jt51_audio_reg;
    wire [7:0] jt51_audio_data;
    wire jt03_audio_valid;
    wire jt03_audio_ready;
    wire jt03_audio_port;
    wire [7:0] jt03_audio_reg;
    wire [7:0] jt03_audio_data;

    retrofm_yamaha_command_bridge #(.FIFO_ADDR_WIDTH(3)) u_command_bridge (
        .clk_system         (clk_system),
        .rst_system         (rst_system),
        .clear_blocked      (clear_blocked),
        .jt51_src_valid     (jt51_cmd_valid),
        .jt51_src_ready     (jt51_cmd_ready),
        .jt51_src_reg       (jt51_cmd_reg),
        .jt51_src_data      (jt51_cmd_data),
        .jt51_src_accept    (jt51_cmd_accept),
        .jt51_blocked_sticky(jt51_blocked_sticky),
        .jt03_src_valid     (jt03_cmd_valid),
        .jt03_src_ready     (jt03_cmd_ready),
        .jt03_src_port      (1'b0),
        .jt03_src_reg       (jt03_cmd_reg),
        .jt03_src_data      (jt03_cmd_data),
        .jt03_src_accept    (jt03_cmd_accept),
        .jt03_blocked_sticky(jt03_blocked_sticky),
        .clk_audio          (clk_audio),
        .rst_audio          (rst_audio),
        .jt51_dst_valid     (jt51_audio_valid),
        .jt51_dst_ready     (jt51_audio_ready),
        .jt51_dst_reg       (jt51_audio_reg),
        .jt51_dst_data      (jt51_audio_data),
        .jt03_dst_valid     (jt03_audio_valid),
        .jt03_dst_ready     (jt03_audio_ready),
        .jt03_dst_port      (jt03_audio_port),
        .jt03_dst_reg       (jt03_audio_reg),
        .jt03_dst_data      (jt03_audio_data)
    );

    wire signed [15:0] jt51_dac_left;
    wire signed [15:0] jt51_dac_right;
    wire jt51_cen_4m;
    wire jt51_cen_2m;

    retrofm_jt51_wrapper u_jt51_wrapper (
        .clk_audio   (clk_audio),
        .rst         (rst_audio),
        .cmd_valid   (jt51_audio_valid),
        .cmd_ready   (jt51_audio_ready),
        .cmd_reg     (jt51_audio_reg),
        .cmd_data    (jt51_audio_data),
        .cmd_done    (jt51_cmd_done),
        .status      (jt51_status),
        .irq_n       (jt51_irq_n),
        .sample_pulse(jt51_sample),
        .audio_left  (jt51_left),
        .audio_right (jt51_right),
        .dac_left    (jt51_dac_left),
        .dac_right   (jt51_dac_right),
        .cen_4mhz    (jt51_cen_4m),
        .cen_2mhz    (jt51_cen_2m)
    );

    wire jt03_clock_cen;
    wire jt03_clock_invalid;
    wire jt03_accept;
    wire signed [15:0] jt03_combined_core;

    retrofm_jt03_wrapper u_jt03_wrapper (
        .clk_audio           (clk_audio),
        .rst                 (rst_audio),
        .master_clock_hz     (ym2203_clock_hz),
        .master_clock_cen    (jt03_clock_cen),
        .master_clock_invalid(jt03_clock_invalid),
        .cmd_valid           (jt03_audio_valid),
        .cmd_ready           (jt03_audio_ready),
        .cmd_reg             (jt03_audio_reg),
        .cmd_data            (jt03_audio_data),
        .cmd_done            (jt03_cmd_done),
        .status              (jt03_status),
        .irq_n               (jt03_irq_n),
        .sample_pulse        (jt03_sample),
        .fm_audio            (jt03_fm),
        .psg_audio           (jt03_psg),
        .combined_audio      (jt03_combined_core),
        .core_accept_pulse   (jt03_accept)
    );

    wire unused_jt03_port = jt03_audio_port;

    // Keep the independently visible OPNA wrapper in the OOC build.  The
    // production top supplies the port bit from VGM flags; this OOC target
    // drives port 0 and folds both OPNA audio lanes into an existing observed
    // output so the core is retained without inventing unconstrained I/O.
    wire opna_clock_cen;
    wire opna_clock_invalid;
    wire opna_cmd_done;
    wire [7:0] opna_status;
    wire opna_irq_n;
    wire opna_sample;
    wire opna_accept;
    wire signed [15:0] opna_left;
    wire signed [15:0] opna_right;
    wire [23:0] opna_adpcmb_addr;
    wire opna_adpcmb_roe_n;
    retrofm_jt2608_wrapper u_opna_wrapper (
        .clk_audio           (clk_audio),
        .rst                 (rst_audio),
        .master_clock_hz     (ym2203_clock_hz),
        .master_clock_cen    (opna_clock_cen),
        .master_clock_invalid(opna_clock_invalid),
        .adpcmb_addr         (opna_adpcmb_addr),
        .adpcmb_roe_n        (opna_adpcmb_roe_n),
        .adpcmb_data         (8'd0),
        .cmd_valid           (jt03_audio_valid),
        .cmd_ready           (),
        .cmd_port            (1'b0),
        .cmd_reg             (jt03_audio_reg),
        .cmd_data            (jt03_audio_data),
        .cmd_done            (opna_cmd_done),
        .status              (opna_status),
        .irq_n               (opna_irq_n),
        .sample_pulse        (opna_sample),
        .audio_left          (opna_left),
        .audio_right         (opna_right),
        .core_accept_pulse   (opna_accept)
    );
    assign jt03_combined = jt03_combined_core ^ opna_left ^ opna_right;

    // The product top feeds its post-mix samples to these DACs at 100 MHz.
    // This OOC top uses an independent system-domain sample so it verifies the
    // selected primitive without introducing a fake audio-to-system CDC path.
    jt12_dac2 #(.width(16)) u_dac_left (
        .clk  (clk_system),
        .rst  (rst_system),
        .din  (dac_test_sample),
        .dout (pwm_left)
    );

    jt12_dac2 #(.width(16)) u_dac_right (
        .clk  (clk_system),
        .rst  (rst_system),
        .din  (dac_test_sample),
        .dout (pwm_right)
    );

endmodule

`default_nettype wire
