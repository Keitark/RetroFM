// SPDX-License-Identifier: GPL-3.0-or-later
//
// OPNA integration assembled from the GPL-3.0-or-later JT12 building blocks
// pinned by RetroFM.  The FM instance is six-channel/stereo; the auxiliary
// instance provides the JT49 SSG and the JT10 ADPCM engines.  The latter uses
// an external sample-read interface in upstream JT12.  RetroFM connects that
// interface to its PS-loaded Delta-T/ADPCM-B RAM.  The optional fixed-rhythm
// ROM is deliberately not bundled: it requires a separately supplied asset.

`default_nettype none

module retrofm_jt2608_wrapper (
    input  wire                       clk_audio,
    input  wire                       rst,
    input  wire [31:0]                master_clock_hz,
    output wire                       master_clock_cen,
    output wire                       master_clock_invalid,

    // Delta-T/ADPCM-B sample memory.  The wrapper exposes the original
    // JT10 byte address; the product top connects a bounded 128 KiB RAM.
    output wire [23:0]                adpcmb_addr,
    output wire                       adpcmb_roe_n,
    input  wire [7:0]                 adpcmb_data,

    input  wire                       cmd_valid,
    output wire                       cmd_ready,
    input  wire                       cmd_port,
    input  wire [7:0]                 cmd_reg,
    input  wire [7:0]                 cmd_data,
    output reg                        cmd_done,

    output wire [7:0]                 status,
    output wire                       irq_n,
    output reg                        sample_pulse,
    output wire signed [15:0]         audio_left,
    output wire signed [15:0]         audio_right,
    output wire                       core_accept_pulse
);
    localparam [32:0] AUDIO_CLOCK_HZ = 33'd80000000;
    localparam [2:0] BUS_IDLE = 3'd0, BUS_ADDR = 3'd1,
                     BUS_DATA_PRIME = 3'd2, BUS_DATA_WAIT = 3'd3,
                     BUS_SETTLE = 3'd4;

    reg [31:0] rate_accumulator = 0;
    reg core_cen = 0;
    wire [32:0] rate_sum = {1'b0, rate_accumulator} + {1'b0, master_clock_hz};
    always @(posedge clk_audio) begin
        if (master_clock_hz >= AUDIO_CLOCK_HZ[31:0]) begin
            rate_accumulator <= 0;
            core_cen <= 1'b1;
        end else if (rate_sum >= AUDIO_CLOCK_HZ) begin
            rate_accumulator <= rate_sum - AUDIO_CLOCK_HZ;
            core_cen <= 1'b1;
        end else begin
            rate_accumulator <= rate_sum[31:0];
            core_cen <= 1'b0;
        end
    end
    assign master_clock_cen = core_cen;
    assign master_clock_invalid = master_clock_hz == 0 ||
                                  master_clock_hz > AUDIO_CLOCK_HZ[31:0];

    // This matches the JT12 divider phase used by retrofm_jt03_wrapper.  An
    // OPNA defaults to the /6 FM, /4 SSG divider setting after reset.
    reg mirror_cen_reg = 0;
    reg [3:0] mirror_opn_cnt = 0;
    reg [2:0] mirror_ssg_cnt = 0;
    reg [1:0] mirror_div2 = 0;
    reg mirror_cen_int = 0;
    reg mirror_accept = 0;
    reg [1:0] mirror_div_setting = 2'b10;
    reg [3:0] mirror_opn_pres;
    reg [2:0] mirror_ssg_pres;
    reg [2:0] bus_state;
    reg held_port;
    reg [7:0] held_reg;
    reg [7:0] held_data;
    reg [4:0] settle_accepts;
    always @(*) begin
        casez (mirror_div_setting)
            2'b0?: begin mirror_opn_pres = 4'd1; mirror_ssg_pres = 3'd0; end
            2'b10: begin mirror_opn_pres = 4'd5; mirror_ssg_pres = 3'd3; end
            default: begin mirror_opn_pres = 4'd2; mirror_ssg_pres = 3'd1; end
        endcase
    end
    always @(posedge clk_audio) begin
        mirror_cen_reg <= core_cen;
        if (rst) mirror_div_setting <= 2'b10;
        if (mirror_cen_reg) begin
            mirror_opn_cnt <= mirror_opn_cnt == mirror_opn_pres ? 0 : mirror_opn_cnt + 1'b1;
            mirror_ssg_cnt <= mirror_ssg_cnt == mirror_ssg_pres ? 0 : mirror_ssg_cnt + 1'b1;
            mirror_div2 <= mirror_div2 == 2 ? 0 : mirror_div2 + 1'b1;
        end
        if (!rst && bus_state == BUS_ADDR && !held_port) begin
            case (held_reg)
                8'h2d: mirror_div_setting[1] <= 1'b1;
                8'h2e: mirror_div_setting[0] <= 1'b1;
                8'h2f: mirror_div_setting <= 2'b00;
                default: ;
            endcase
        end
    end
    always @(negedge clk_audio) begin
        mirror_cen_int <= mirror_opn_cnt == 0;
        mirror_accept <= mirror_cen_reg && mirror_cen_int;
    end
    assign core_accept_pulse = mirror_accept;

    wire [1:0] core_addr = {held_port,
        (bus_state == BUS_DATA_PRIME) || (bus_state == BUS_DATA_WAIT)};
    wire core_wr_n = (bus_state == BUS_IDLE) ||
                     ((bus_state == BUS_DATA_WAIT) && mirror_accept);
    wire [7:0] core_din = core_addr[0] ? held_data : held_reg;
    always @(posedge clk_audio) begin
        if (rst) begin
            bus_state <= BUS_IDLE;
            held_port <= 0;
            held_reg <= 0;
            held_data <= 0;
            settle_accepts <= 0;
            cmd_done <= 0;
        end else begin
            cmd_done <= 0;
            case (bus_state)
                BUS_IDLE: if (cmd_valid) begin
                    held_port <= cmd_port;
                    held_reg <= cmd_reg;
                    held_data <= cmd_data;
                    bus_state <= BUS_ADDR;
                end
                BUS_ADDR: if (mirror_accept) bus_state <= BUS_DATA_PRIME;
                BUS_DATA_PRIME: bus_state <= BUS_DATA_WAIT;
                BUS_DATA_WAIT: if (mirror_accept) begin
                    bus_state <= BUS_SETTLE;
                    settle_accepts <= 0;
                end
                BUS_SETTLE: if (mirror_accept) begin
                    // Six OPN channels x four operator slots.
                    if (settle_accepts == 5'd23) begin
                        bus_state <= BUS_IDLE;
                        cmd_done <= 1'b1;
                    end else settle_accepts <= settle_accepts + 1'b1;
                end
                default: bus_state <= BUS_IDLE;
            endcase
        end
    end
    assign cmd_ready = !rst && bus_state == BUS_IDLE;

    wire [7:0] fm_dout, aux_dout;
    wire fm_irq_n, aux_irq_n;
    wire signed [15:0] fm_left, fm_right;
    wire signed [15:0] aux_adpcmb_l, aux_adpcmb_r;
    wire [9:0] aux_psg;
    wire aux_sample;
    wire [7:0] unused_psg_a, unused_psg_b, unused_psg_c;
    wire [19:0] unused_fm_adpcma_addr;
    wire [4:0] unused_fm_adpcma_bank;
    wire unused_fm_adpcma_roe_n, unused_fm_adpcmb_roe_n;
    wire [23:0] unused_fm_adpcmb_addr;
    wire [19:0] unused_aux_adpcma_addr;
    wire [4:0] unused_aux_adpcma_bank;
    wire unused_aux_adpcma_roe_n, unused_aux_adpcmb_roe_n;
    wire [23:0] aux_adpcmb_addr;

    // Full six-channel FM core, retaining OPNA port-1 channel registers.
    jt12_top #(.use_lfo(1), .use_ssg(0), .num_ch(6), .use_pcm(1),
               .use_adpcm(0), .mask_div(0)) u_fm (
        .rst(rst), .clk(clk_audio), .cen(core_cen), .din(core_din),
        .addr(core_addr), .cs_n(1'b0), .wr_n(core_wr_n), .dout(fm_dout),
        .irq_n(fm_irq_n), .en_hifi_pcm(1'b0),
        .adpcma_addr(unused_fm_adpcma_addr), .adpcma_bank(unused_fm_adpcma_bank),
        .adpcma_roe_n(unused_fm_adpcma_roe_n), .adpcma_data(8'd0),
        .adpcmb_addr(unused_fm_adpcmb_addr), .adpcmb_data(8'd0),
        .adpcmb_roe_n(unused_fm_adpcmb_roe_n), .IOA_in(8'd0), .IOB_in(8'd0),
        .IOA_out(), .IOB_out(), .IOA_oe(), .IOB_oe(),
        .psg_A(), .psg_B(), .psg_C(), .fm_snd_left(fm_left),
        .fm_snd_right(fm_right), .adpcmA_l(), .adpcmA_r(), .adpcmB_l(),
        .adpcmB_r(), .psg_snd(), .snd_right(), .snd_left(),
        .snd_sample(), .ch_enable(6'h3f), .debug_bus(8'd0), .debug_view()
    );

    // JT10 supplies JT49 and the upstream ADPCM engines.  Its own YM2610
    // FM mix is intentionally discarded; FM above remains all six OPNA lanes.
    jt12_top #(.use_lfo(1), .use_ssg(1), .num_ch(6), .use_pcm(0),
               .use_adpcm(1), .JT49_DIV(3), .mask_div(0)) u_aux (
        .rst(rst), .clk(clk_audio), .cen(core_cen), .din(core_din),
        .addr(core_addr), .cs_n(1'b0), .wr_n(core_wr_n), .dout(aux_dout),
        .irq_n(aux_irq_n), .en_hifi_pcm(1'b0),
        .adpcma_addr(unused_aux_adpcma_addr), .adpcma_bank(unused_aux_adpcma_bank),
        .adpcma_roe_n(unused_aux_adpcma_roe_n), .adpcma_data(8'd0),
        .adpcmb_addr(aux_adpcmb_addr), .adpcmb_data(adpcmb_data),
        .adpcmb_roe_n(unused_aux_adpcmb_roe_n), .IOA_in(8'd0), .IOB_in(8'd0),
        .IOA_out(), .IOB_out(), .IOA_oe(), .IOB_oe(),
        .psg_A(unused_psg_a), .psg_B(unused_psg_b), .psg_C(unused_psg_c),
        // YM2608 rhythm is ADPCM-A backed by the chip's fixed rhythm ROM.
        // RetroFM intentionally does not ship that asset, so discard this
        // core's ADPCM-A output rather than decoding its rhythm commands with
        // a constant-zero pseudo-ROM and leaking artefacts into the mix.
        .fm_snd_left(), .fm_snd_right(), .adpcmA_l(), .adpcmA_r(),
        .adpcmB_l(aux_adpcmb_l), .adpcmB_r(aux_adpcmb_r),
        .psg_snd(aux_psg), .snd_right(), .snd_left(), .snd_sample(aux_sample),
        .ch_enable(6'h3f), .debug_bus(8'd0), .debug_view()
    );

    // Keep the upstream JT10 ADPCM-B calibration.  Its accumulator feeds B
    // at half amplitude because the Delta-T output is 16 bits while the FM
    // operator path is 14 bits.  The old raw 1:1 sum clipped readily and,
    // together with the unbacked ADPCM-A rhythm engine, made OPNA selections
    // sound noisy.  The fixed rhythm ROM is intentionally unsupported, not
    // substituted with fabricated noise.
    wire signed [18:0] mix_left = {{3{fm_left[15]}}, fm_left} +
                                   $signed({3'b000, aux_psg, 5'b00000}) +
                                   ({{3{aux_adpcmb_l[15]}}, aux_adpcmb_l} >>> 1);
    wire signed [18:0] mix_right = {{3{fm_right[15]}}, fm_right} +
                                    $signed({3'b000, aux_psg, 5'b00000}) +
                                    ({{3{aux_adpcmb_r[15]}}, aux_adpcmb_r} >>> 1);
    assign audio_left = mix_left > 19'sd32767 ? 16'sh7fff :
                        mix_left < -19'sd32768 ? 16'sh8000 : mix_left[15:0];
    assign audio_right = mix_right > 19'sd32767 ? 16'sh7fff :
                         mix_right < -19'sd32768 ? 16'sh8000 : mix_right[15:0];
    reg aux_sample_d;
    always @(posedge clk_audio) begin
        if (rst) begin aux_sample_d <= 0; sample_pulse <= 0; end
        else begin
            aux_sample_d <= aux_sample;
            sample_pulse <= aux_sample && !aux_sample_d;
        end
    end
    assign status = aux_dout;
    assign irq_n = fm_irq_n & aux_irq_n;
    assign adpcmb_addr = aux_adpcmb_addr;
    assign adpcmb_roe_n = unused_aux_adpcmb_roe_n;
endmodule

`default_nettype wire
