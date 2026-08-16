// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Source-event mixer in the 100 MHz system domain. Yamaha and PCM sources are
// held between their native update events. The arithmetic remains wide until
// the final signed Q16.4 output, so gain products are rounded only once before
// entering the 100 MHz delta-sigma modulator.
//
// The JT51/PDX balance is expressed as the algebraically equivalent pair:
//
//   JT51_POST_GAIN * (FM + PCM_BALANCE * PCM)
//
// Defaults are based on the measured DETA01M MXDRV/RetroFM RMS comparison.
// JT03 and OPNA bypass these MDX-specific coefficients.
module retrofm_stereo_mixer #(
    parameter logic [15:0] MUTE_STEP_Q15       = 16'd256,
    parameter logic        RESET_MUTED         = 1'b1,
    parameter logic [15:0] JT51_POST_GAIN_Q15  = 16'd21605,
    parameter logic [15:0] PCM_BALANCE_GAIN_Q15 = 16'd49700
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     sample_ce,
    input  logic                     gain_ce,

    input  logic                     jt51_enable,
    input  logic signed [15:0]       jt51_left,
    input  logic signed [15:0]       jt51_right,
    input  logic                     jt03_enable,
    input  logic signed [15:0]       jt03_mono,
    input  logic                     opna_enable,
    input  logic signed [15:0]       opna_left,
    input  logic signed [15:0]       opna_right,
    input  logic                     pcm_enable,
    input  logic signed [15:0]       pcm_left,
    input  logic signed [15:0]       pcm_right,

    input  logic [15:0]              volume_q15,
    input  logic                     mute_request,
    input  logic                     fm_mute_request,
    output logic [15:0]              mute_gain_q15,
    output logic [15:0]              fm_mute_gain_q15,
    output logic                     out_valid,
    // Q16.4: the four low bits retain fractional gain/mix precision. A
    // signed-16 unity sample N is represented as N*16 at this interface.
    output logic signed [19:0]       out_left,
    output logic signed [19:0]       out_right
);
    localparam logic [15:0] UNITY_Q15 = 16'h8000;

    logic signed [17:0] fm_sum_left_next;
    logic signed [17:0] fm_sum_right_next;
    logic        [15:0] mute_gain_next;
    logic        [15:0] mute_gain_for_capture;
    logic        [16:0] mute_gain_sum;
    logic        [15:0] fm_mute_gain_next;
    logic        [15:0] fm_mute_gain_for_capture;
    logic        [16:0] fm_mute_gain_sum;

    logic                    capture_valid;
    logic signed [17:0]      fm_sum_left_stage;
    logic signed [17:0]      fm_sum_right_stage;
    logic signed [17:0]      pcm_left_capture_stage;
    logic signed [17:0]      pcm_right_capture_stage;
    logic signed [16:0]      fm_gain_capture_stage;
    logic signed [16:0]      pcm_gain_capture_stage;
    logic signed [16:0]      balance_gain_capture_stage;
    logic signed [16:0]      volume_gain_capture_stage;
    logic signed [16:0]      mute_gain_capture_stage;

    // Both source products are Q15 and remain full precision through the add.
    logic                    source_product_valid;
    logic signed [34:0]      fm_product_left_stage;
    logic signed [34:0]      fm_product_right_stage;
    logic signed [34:0]      pcm_product_left_stage;
    logic signed [34:0]      pcm_product_right_stage;
    logic signed [16:0]      balance_gain_product_stage;
    logic signed [16:0]      volume_gain_product_stage;
    logic signed [16:0]      mute_gain_product_stage;

    logic                    sum_valid;
    logic signed [35:0]      sum_left_stage;
    logic signed [35:0]      sum_right_stage;
    logic signed [16:0]      balance_gain_sum_stage;
    logic signed [16:0]      volume_gain_sum_stage;
    logic signed [16:0]      mute_gain_sum_stage;

    logic                    balance_valid;
    logic signed [52:0]      balance_product_left_stage;
    logic signed [52:0]      balance_product_right_stage;
    logic signed [16:0]      volume_gain_balance_stage;
    logic signed [16:0]      mute_gain_balance_stage;

    logic                    volume_valid;
    logic signed [69:0]      volume_product_left_stage;
    logic signed [69:0]      volume_product_right_stage;
    logic signed [16:0]      mute_gain_volume_stage;

    logic                    mute_valid;
    logic signed [86:0]      mute_product_left_stage;
    logic signed [86:0]      mute_product_right_stage;

    // Symmetric round-to-nearest followed by signed-20 saturation.  The
    // product is Q60 and only bit 55 can affect Q16.4 rounding.  Do not form
    // `abs(value) + 2**55` across all 87 bits here: that creates a long carry
    // chain after the final DSP stage.  Instead, inspect the integer and
    // rounding bits directly.  The negative branch derives round-to-nearest
    // away from zero from the two's-complement fractional residue.
    //
    // Keeping four fractional bits here prevents gain quantization from being
    // thrown away before the delta-sigma loop.
    function automatic logic signed [19:0] round_saturate_q4(
        input logic signed [86:0] value
    );
        logic [19:0] positive_rounded;
        logic signed [20:0] negative_floor;
        logic signed [20:0] negative_rounded;
        begin
            if (!value[86]) begin
                // Positive: integer bits [74:56] plus the half-LSB bit.  A
                // bit above 74, or a carry out of this 20-bit add, exceeds
                // the signed Q16.4 positive rail.
                positive_rounded = {1'b0, value[74:56]} + value[55];
                if (|value[86:75] || positive_rounded[19])
                    round_saturate_q4 = 20'sh7ffff;
                else
                    round_saturate_q4 = {1'b0, positive_rounded[18:0]};
            end else begin
                // Arithmetic division floors negative values.  For a
                // negative residue r, the Q60 low word is U-r; add one to
                // that floor only when 0 < r < U/2 (low word > U/2).
                // Values beyond this 21-bit window are unconditionally
                // below the signed Q16.4 negative rail.
                negative_floor = $signed(value[76:56]);
                if (value[55:0] > 56'h80000000000000)
                    negative_rounded = negative_floor + 21'sd1;
                else
                    negative_rounded = negative_floor;

                if (!(&value[86:76]) ||
                    (negative_rounded < -21'sd524288))
                    round_saturate_q4 = 20'sh80000;
                else
                    round_saturate_q4 = negative_rounded[19:0];
            end
        end
    endfunction

    always_comb begin
        fm_mute_gain_sum = {1'b0, fm_mute_gain_q15} +
                           {1'b0, MUTE_STEP_Q15};
        fm_mute_gain_next = fm_mute_gain_q15;
        if (fm_mute_request) begin
            if (fm_mute_gain_q15 > MUTE_STEP_Q15)
                fm_mute_gain_next = fm_mute_gain_q15 - MUTE_STEP_Q15;
            else
                fm_mute_gain_next = 16'h0000;
        end else begin
            if (fm_mute_gain_sum >= {1'b0, UNITY_Q15})
                fm_mute_gain_next = UNITY_Q15;
            else
                fm_mute_gain_next = fm_mute_gain_sum[15:0];
        end
        fm_mute_gain_for_capture = gain_ce ? fm_mute_gain_next :
                                             fm_mute_gain_q15;

        fm_sum_left_next  = 18'sd0;
        fm_sum_right_next = 18'sd0;
        if (jt51_enable) begin
            fm_sum_left_next  = fm_sum_left_next +
                                {{2{jt51_left[15]}}, jt51_left};
            fm_sum_right_next = fm_sum_right_next +
                                {{2{jt51_right[15]}}, jt51_right};
        end
        if (jt03_enable) begin
            fm_sum_left_next  = fm_sum_left_next +
                                {{2{jt03_mono[15]}}, jt03_mono};
            fm_sum_right_next = fm_sum_right_next +
                                {{2{jt03_mono[15]}}, jt03_mono};
        end
        if (opna_enable) begin
            fm_sum_left_next  = fm_sum_left_next +
                                {{2{opna_left[15]}}, opna_left};
            fm_sum_right_next = fm_sum_right_next +
                                {{2{opna_right[15]}}, opna_right};
        end

        mute_gain_sum = {1'b0, mute_gain_q15} + {1'b0, MUTE_STEP_Q15};
        mute_gain_next = mute_gain_q15;
        if (mute_request) begin
            if (mute_gain_q15 > MUTE_STEP_Q15)
                mute_gain_next = mute_gain_q15 - MUTE_STEP_Q15;
            else
                mute_gain_next = 16'h0000;
        end else begin
            if (mute_gain_sum >= {1'b0, UNITY_Q15})
                mute_gain_next = UNITY_Q15;
            else
                mute_gain_next = mute_gain_sum[15:0];
        end
        mute_gain_for_capture = gain_ce ? mute_gain_next : mute_gain_q15;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mute_gain_q15 <= RESET_MUTED ? 16'h0000 : UNITY_Q15;
            fm_mute_gain_q15 <= UNITY_Q15;
            capture_valid <= 1'b0;
            source_product_valid <= 1'b0;
            sum_valid <= 1'b0;
            balance_valid <= 1'b0;
            volume_valid <= 1'b0;
            mute_valid <= 1'b0;
            out_valid <= 1'b0;
            fm_sum_left_stage <= '0;
            fm_sum_right_stage <= '0;
            pcm_left_capture_stage <= '0;
            pcm_right_capture_stage <= '0;
            fm_gain_capture_stage <= '0;
            pcm_gain_capture_stage <= '0;
            balance_gain_capture_stage <= '0;
            volume_gain_capture_stage <= '0;
            mute_gain_capture_stage <= '0;
            fm_product_left_stage <= '0;
            fm_product_right_stage <= '0;
            pcm_product_left_stage <= '0;
            pcm_product_right_stage <= '0;
            balance_gain_product_stage <= '0;
            volume_gain_product_stage <= '0;
            mute_gain_product_stage <= '0;
            sum_left_stage <= '0;
            sum_right_stage <= '0;
            balance_gain_sum_stage <= '0;
            volume_gain_sum_stage <= '0;
            mute_gain_sum_stage <= '0;
            balance_product_left_stage <= '0;
            balance_product_right_stage <= '0;
            volume_gain_balance_stage <= '0;
            mute_gain_balance_stage <= '0;
            volume_product_left_stage <= '0;
            volume_product_right_stage <= '0;
            mute_gain_volume_stage <= '0;
            mute_product_left_stage <= '0;
            mute_product_right_stage <= '0;
            out_left <= '0;
            out_right <= '0;
        end else begin
            capture_valid <= sample_ce;
            source_product_valid <= capture_valid;
            sum_valid <= source_product_valid;
            balance_valid <= sum_valid;
            volume_valid <= balance_valid;
            mute_valid <= volume_valid;
            out_valid <= mute_valid;

            if (gain_ce) begin
                mute_gain_q15 <= mute_gain_next;
                fm_mute_gain_q15 <= fm_mute_gain_next;
            end

            if (sample_ce) begin
                fm_sum_left_stage <= fm_sum_left_next;
                fm_sum_right_stage <= fm_sum_right_next;
                pcm_left_capture_stage <= pcm_enable ?
                    {{2{pcm_left[15]}}, pcm_left} : 18'sd0;
                pcm_right_capture_stage <= pcm_enable ?
                    {{2{pcm_right[15]}}, pcm_right} : 18'sd0;
                fm_gain_capture_stage <=
                    $signed({1'b0, fm_mute_gain_for_capture});
                pcm_gain_capture_stage <= $signed({1'b0,
                    jt51_enable ? PCM_BALANCE_GAIN_Q15 : UNITY_Q15});
                balance_gain_capture_stage <= $signed({1'b0,
                    jt51_enable ? JT51_POST_GAIN_Q15 : UNITY_Q15});
                volume_gain_capture_stage <= $signed({1'b0, volume_q15});
                mute_gain_capture_stage <=
                    $signed({1'b0, mute_gain_for_capture});
            end

            if (capture_valid) begin
                fm_product_left_stage <=
                    fm_sum_left_stage * fm_gain_capture_stage;
                fm_product_right_stage <=
                    fm_sum_right_stage * fm_gain_capture_stage;
                pcm_product_left_stage <=
                    pcm_left_capture_stage * pcm_gain_capture_stage;
                pcm_product_right_stage <=
                    pcm_right_capture_stage * pcm_gain_capture_stage;
                balance_gain_product_stage <= balance_gain_capture_stage;
                volume_gain_product_stage <= volume_gain_capture_stage;
                mute_gain_product_stage <= mute_gain_capture_stage;
            end

            if (source_product_valid) begin
                sum_left_stage <=
                    {{1{fm_product_left_stage[34]}}, fm_product_left_stage} +
                    {{1{pcm_product_left_stage[34]}}, pcm_product_left_stage};
                sum_right_stage <=
                    {{1{fm_product_right_stage[34]}}, fm_product_right_stage} +
                    {{1{pcm_product_right_stage[34]}}, pcm_product_right_stage};
                balance_gain_sum_stage <= balance_gain_product_stage;
                volume_gain_sum_stage <= volume_gain_product_stage;
                mute_gain_sum_stage <= mute_gain_product_stage;
            end

            if (sum_valid) begin
                balance_product_left_stage <=
                    sum_left_stage * balance_gain_sum_stage;
                balance_product_right_stage <=
                    sum_right_stage * balance_gain_sum_stage;
                volume_gain_balance_stage <= volume_gain_sum_stage;
                mute_gain_balance_stage <= mute_gain_sum_stage;
            end

            if (balance_valid) begin
                volume_product_left_stage <=
                    balance_product_left_stage * volume_gain_balance_stage;
                volume_product_right_stage <=
                    balance_product_right_stage * volume_gain_balance_stage;
                mute_gain_volume_stage <= mute_gain_balance_stage;
            end

            if (volume_valid) begin
                mute_product_left_stage <=
                    volume_product_left_stage * mute_gain_volume_stage;
                mute_product_right_stage <=
                    volume_product_right_stage * mute_gain_volume_stage;
            end

            if (mute_valid) begin
                out_left <= round_saturate_q4(mute_product_left_stage);
                out_right <= round_saturate_q4(mute_product_right_stage);
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (MUTE_STEP_Q15 == 16'h0000)
            $fatal(1, "retrofm_stereo_mixer MUTE_STEP_Q15 must be nonzero");
        if (JT51_POST_GAIN_Q15 == 16'h0000 ||
            PCM_BALANCE_GAIN_Q15 < UNITY_Q15)
            $fatal(1, "retrofm_stereo_mixer invalid balance coefficients");
    end
`endif
endmodule
