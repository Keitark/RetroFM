// SPDX-License-Identifier: GPL-3.0-or-later
//
// Narrow integration wrapper for JT03 in JT12 commit
// 45f4854f9ab43368f5a514857299ab7dfae4e6ab and JT49 commit
// 7f6abfd08a2af9a92dbd5b32c71ea773248a77e2.

`default_nettype none

module retrofm_jt03_wrapper (
    input  wire                       clk_audio,
    input  wire                       rst,

    // Requested YM2203 master clock in whole hertz.  Values from 1 through
    // 80 MHz are representable; normal VGM values are far below that limit.
    input  wire [31:0]                master_clock_hz,
    output wire                       master_clock_cen,
    output wire                       master_clock_invalid,

    input  wire                       cmd_valid,
    output wire                       cmd_ready,
    input  wire [7:0]                 cmd_reg,
    input  wire [7:0]                 cmd_data,
    output reg                        cmd_done,

    output wire [7:0]                 status,
    output wire                       irq_n,
    output reg                        sample_pulse,
    output wire signed [15:0]         fm_audio,
    output wire [9:0]                 psg_audio,
    output wire signed [15:0]         combined_audio,
    output wire                       core_accept_pulse
);

    localparam [32:0] AUDIO_CLOCK_HZ = 33'd80000000;

    localparam [2:0] BUS_IDLE       = 3'd0;
    localparam [2:0] BUS_ADDR       = 3'd1;
    localparam [2:0] BUS_DATA_PRIME = 3'd2;
    localparam [2:0] BUS_DATA_WAIT  = 3'd3;
    localparam [2:0] BUS_SETTLE     = 3'd4;

    reg [2:0] bus_state;
    reg [7:0] held_reg;
    reg [7:0] held_data;
    reg [3:0] settle_accepts;

    // Keep this generator running during rst: jt03.v requires reset to span
    // at least six clk-and-cen cycles.  FPGA-init values also make the NCO
    // phase deterministic at configuration.
    reg [31:0] rate_accumulator = 32'd0;
    reg core_cen = 1'b0;
    reg core_reset_local = 1'b1;
    wire [32:0] rate_sum = {1'b0, rate_accumulator} +
                            {1'b0, master_clock_hz};

    // Bresenham/fractional accumulator.  The long-term enable frequency is
    // exactly master_clock_hz for an integer-Hz setting, with at most one
    // 80 MHz period of instantaneous timing displacement.
    // JT03's public top does not expose jt12_div.clk_en.  The following
    // state is an exact phase mirror of the pinned jt12_top/jt12_div pair:
    // jt12_top first registers cen, jt12_div advances opn_cnt on the
    // positive edge, then forms clk_en on the negative edge.  The counters
    // intentionally are not reset, matching the upstream FPGA-init model.
    reg       mirror_cen_reg = 1'b0;
    reg [3:0] mirror_opn_cnt = 4'd0;
    reg [2:0] mirror_ssg_cnt = 3'd0;
    reg [1:0] mirror_div2 = 2'd0;
    reg       mirror_cen_int = 1'b0;
    reg       mirror_accept = 1'b0;
    reg [1:0] mirror_div_setting;
    reg [3:0] mirror_opn_pres;
    reg [2:0] mirror_ssg_pres;
    wire divider_phase_zero = (mirror_opn_cnt == 4'd0) &&
                              (mirror_ssg_cnt == 3'd0) &&
                              (mirror_div2 == 2'd0);
    wire release_reset_phase = core_reset_local && !rst &&
                               !core_cen && !mirror_cen_reg &&
                               divider_phase_zero;

    always @(posedge clk_audio) begin
        if (release_reset_phase) begin
            // Restart the fractional master-clock phase together with the
            // upstream dividers. This makes every track start reproducible.
            rate_accumulator <= 32'd0;
            core_cen <= 1'b0;
        end else if (master_clock_hz >= AUDIO_CLOCK_HZ[31:0]) begin
            rate_accumulator <= 32'd0;
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
    assign master_clock_invalid = (master_clock_hz == 32'd0) ||
                                  (master_clock_hz > AUDIO_CLOCK_HZ[31:0]);

    always @(*) begin
        casez (mirror_div_setting)
            2'b0?: begin
                mirror_opn_pres = 4'd1; // divide by 2
                mirror_ssg_pres = 3'd0; // divide by 1
            end
            2'b10: begin
                mirror_opn_pres = 4'd5; // divide by 6
                mirror_ssg_pres = 3'd3; // divide by 4
            end
            2'b11: begin
                mirror_opn_pres = 4'd2; // divide by 3
                mirror_ssg_pres = 3'd1; // divide by 2
            end
            default: begin
                mirror_opn_pres = 4'd5;
                mirror_ssg_pres = 3'd3;
            end
        endcase
    end

    always @(posedge clk_audio) begin
        mirror_cen_reg <= core_cen;

        if (mirror_cen_reg) begin
            if (mirror_opn_cnt == mirror_opn_pres)
                mirror_opn_cnt <= 4'd0;
            else
                mirror_opn_cnt <= mirror_opn_cnt + 4'd1;

            if (mirror_ssg_cnt == mirror_ssg_pres)
                mirror_ssg_cnt <= 3'd0;
            else
                mirror_ssg_cnt <= mirror_ssg_cnt + 3'd1;

            if (mirror_div2 == 2'd2)
                mirror_div2 <= 2'd0;
            else
                mirror_div2 <= mirror_div2 + 2'd1;
        end
    end

    // Upstream JT12 intentionally does not reset its prescaler counters.
    // Keep reset asserted locally after the system request falls until the
    // mirrored FM, SSG, and /2 counters are all at their common zero phase
    // and no delayed master enable remains in flight.
    always @(posedge clk_audio) begin
        if (rst)
            core_reset_local <= 1'b1;
        else if (release_reset_phase)
            core_reset_local <= 1'b0;
    end

    always @(negedge clk_audio) begin
        mirror_cen_int <= mirror_opn_cnt == 4'd0;
        mirror_accept <= mirror_cen_reg && mirror_cen_int;
    end

    // Selecting 2D/2E/2F changes the upstream divider before a data phase.
    // Mirror those address-side effects exactly; all register writes must go
    // through this wrapper for the phase mirror to remain authoritative.
    always @(posedge clk_audio) begin
        if (core_reset_local) begin
            mirror_div_setting <= 2'b10;
        end else if (bus_state == BUS_ADDR) begin
            case (held_reg)
                8'h2d: mirror_div_setting[1] <= 1'b1;
                8'h2e: mirror_div_setting[0] <= 1'b1;
                8'h2f: mirror_div_setting <= 2'b00;
                default: ;
            endcase
        end
    end

    assign core_accept_pulse = mirror_accept;

    wire core_addr = (bus_state == BUS_DATA_PRIME) ||
                     (bus_state == BUS_DATA_WAIT);
    wire data_accepting_now = (bus_state == BUS_DATA_WAIT) && mirror_accept;
    wire core_wr_n = (bus_state == BUS_IDLE) || data_accepting_now;
    wire [7:0] core_din = core_addr ? held_data : held_reg;

    // Address is held through an internal acceptance interval.  JT12's MMR
    // itself is ungated, so data is first asserted to set its pending flags,
    // then deasserted on an accepting edge.  On that same edge jt12_reg sees
    // the old pending flag once while jt12_mmr clears it.  Holding write low
    // on the accepting edge would replay key-on and other one-shot writes at
    // the following accepting edge.
    always @(posedge clk_audio) begin
        if (core_reset_local) begin
            bus_state <= BUS_IDLE;
            held_reg <= 8'd0;
            held_data <= 8'd0;
            settle_accepts <= 4'd0;
            cmd_done <= 1'b0;
        end else begin
            cmd_done <= 1'b0;
            case (bus_state)
                BUS_IDLE: begin
                    if (cmd_valid) begin
                        held_reg <= cmd_reg;
                        held_data <= cmd_data;
                        bus_state <= BUS_ADDR;
                    end
                end

                BUS_ADDR: begin
                    if (mirror_accept)
                        bus_state <= BUS_DATA_PRIME;
                end

                BUS_DATA_PRIME: begin
                    bus_state <= BUS_DATA_WAIT;
                end

                BUS_DATA_WAIT: begin
                    if (mirror_accept) begin
                        // JT03 stores operator parameters in a 12-slot
                        // circular register.  The MMR update selector and
                        // data remain pending only until the next port write.
                        // Do not accept that next write until every slot has
                        // had an internal synthesizer enable, otherwise an
                        // adjacent VGM write can replace a parameter before
                        // its intended operator sees it.
                        bus_state <= BUS_SETTLE;
                        settle_accepts <= 4'd0;
                    end
                end

                BUS_SETTLE: begin
                    if (mirror_accept) begin
                        if (settle_accepts == 4'd11) begin
                            bus_state <= BUS_IDLE;
                            cmd_done <= 1'b1;
                        end else begin
                            settle_accepts <= settle_accepts + 1'b1;
                        end
                    end
                end

                default: bus_state <= BUS_IDLE;
            endcase
        end
    end

    assign cmd_ready = !core_reset_local && (bus_state == BUS_IDLE);

    wire core_snd_sample;
    reg core_snd_sample_d;
    wire [7:0] ioa_out_unused;
    wire [7:0] iob_out_unused;
    wire ioa_oe_unused;
    wire iob_oe_unused;
    wire [7:0] psg_a_unused;
    wire [7:0] psg_b_unused;
    wire [7:0] psg_c_unused;
    wire [7:0] debug_unused;
    wire signed [15:0] core_combined_unused;

    // snd_sample is a level derived from an internally clock-enabled phase
    // bit.  Convert its rising transition into one clk_audio-wide pulse.
    always @(posedge clk_audio) begin
        if (core_reset_local) begin
            core_snd_sample_d <= 1'b0;
            sample_pulse <= 1'b0;
        end else begin
            sample_pulse <= core_snd_sample && !core_snd_sample_d;
            core_snd_sample_d <= core_snd_sample;
        end
    end

    jt03 #(.YM2203_LUMPED(0)) u_jt03 (
        .rst            (core_reset_local),
        .clk            (clk_audio),
        .cen            (core_cen),
        .din            (core_din),
        .addr           (core_addr),
        .cs_n           (1'b0),
        .wr_n           (core_wr_n),
        .dout           (status),
        .irq_n          (irq_n),
        .IOA_in         (8'd0),
        .IOB_in         (8'd0),
        .IOA_out        (ioa_out_unused),
        .IOB_out        (iob_out_unused),
        .IOA_oe         (ioa_oe_unused),
        .IOB_oe         (iob_oe_unused),
        .psg_A          (psg_a_unused),
        .psg_B          (psg_b_unused),
        .psg_C          (psg_c_unused),
        .fm_snd         (fm_audio),
        .psg_snd        (psg_audio),
        .snd            (core_combined_unused),
        .snd_sample     (core_snd_sample),
        .debug_view     (debug_unused)
    );

    retrofm_jt03_output_mix output_mix_i (
        .fm_audio(fm_audio),
        .psg_audio(psg_audio),
        .mixed_audio(combined_audio)
    );

endmodule

`default_nettype wire
