// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// One-sample-delayed linear rate converter for JT51's exact 62.5 kHz output.
// The source mailbox is observed in the 100 MHz system domain.  A phase
// accumulator measures the 1,600 system clocks between source samples and
// reconstructs the requested 48 kHz point between the previous/current pair.
// This avoids the non-uniform sample dropping of a latest-value/ZOH crossing.
module retrofm_jt51_resampler #(
    parameter integer INPUT_PERIOD_CYCLES = 1600
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     src_update,
    input  logic signed [15:0]       src_left,
    input  logic signed [15:0]       src_right,
    input  logic                     dst_ce,
    output logic signed [15:0]       dst_left,
    output logic signed [15:0]       dst_right
);
    localparam integer PHASE_BASE = 32768 / INPUT_PERIOD_CYCLES;
    localparam integer PHASE_REMAINDER = 32768 % INPUT_PERIOD_CYCLES;
    localparam integer REM_WIDTH = $clog2(INPUT_PERIOD_CYCLES + 1);

    logic signed [15:0] previous_left;
    logic signed [15:0] previous_right;
    logic signed [15:0] current_left;
    logic signed [15:0] current_right;
    logic [15:0] phase_q15;
    logic [REM_WIDTH-1:0] phase_remainder;
    logic have_first;
    logic have_pair;

    logic [REM_WIDTH:0] remainder_sum;
    logic [16:0] phase_increment;
    logic [16:0] phase_sum;
    logic signed [16:0] difference_left;
    logic signed [16:0] difference_right;
    logic signed [16:0] phase_signed;
    logic signed [33:0] product_left;
    logic signed [33:0] product_right;
    logic signed [17:0] interpolated_left;
    logic signed [17:0] interpolated_right;

    always_comb begin
        remainder_sum = phase_remainder + PHASE_REMAINDER;
        phase_increment = PHASE_BASE;
        if (remainder_sum >= INPUT_PERIOD_CYCLES) begin
            remainder_sum = remainder_sum - INPUT_PERIOD_CYCLES;
            phase_increment = PHASE_BASE + 1;
        end
        phase_sum = {1'b0, phase_q15} + phase_increment;

        difference_left = $signed({current_left[15], current_left}) -
                          $signed({previous_left[15], previous_left});
        difference_right = $signed({current_right[15], current_right}) -
                           $signed({previous_right[15], previous_right});
        phase_signed = $signed({1'b0, phase_q15});
        product_left = difference_left * phase_signed;
        product_right = difference_right * phase_signed;
        interpolated_left =
            $signed({{2{previous_left[15]}}, previous_left}) +
            (product_left >>> 15);
        interpolated_right =
            $signed({{2{previous_right[15]}}, previous_right}) +
            (product_right >>> 15);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            previous_left <= '0;
            previous_right <= '0;
            current_left <= '0;
            current_right <= '0;
            phase_q15 <= '0;
            phase_remainder <= '0;
            have_first <= 1'b0;
            have_pair <= 1'b0;
            dst_left <= '0;
            dst_right <= '0;
        end else begin
            if (src_update) begin
                previous_left <= current_left;
                previous_right <= current_right;
                current_left <= src_left;
                current_right <= src_right;
                phase_q15 <= 16'd0;
                phase_remainder <= '0;
                have_pair <= have_first;
                have_first <= 1'b1;
            end else if (phase_q15 < 16'h8000) begin
                if (phase_sum >= 17'h08000) begin
                    phase_q15 <= 16'h8000;
                    phase_remainder <= '0;
                end else begin
                    phase_q15 <= phase_sum[15:0];
                    phase_remainder <= remainder_sum[REM_WIDTH-1:0];
                end
            end

            if (dst_ce) begin
                if (have_pair) begin
                    dst_left <= interpolated_left[15:0];
                    dst_right <= interpolated_right[15:0];
                end else if (have_first) begin
                    dst_left <= current_left;
                    dst_right <= current_right;
                end else begin
                    dst_left <= '0;
                    dst_right <= '0;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (INPUT_PERIOD_CYCLES < 2 || INPUT_PERIOD_CYCLES > 32768)
            $fatal(1, "retrofm_jt51_resampler invalid input period");
    end
`endif
endmodule
