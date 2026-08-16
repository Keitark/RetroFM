// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Generates an average rate_hz clock-enable from clk without creating a new
// clock domain.  For example BASE_HZ=100_000_000 and rate_hz=4_000_000 emits
// exactly four enables per one hundred input clocks.
module retrofm_fractional_ce #(
    parameter integer BASE_HZ   = 100_000_000,
    parameter integer ACC_WIDTH = 32
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 enable,
    input  logic [ACC_WIDTH-1:0] rate_hz,
    output logic                 ce,
    output logic [ACC_WIDTH-1:0] phase
);
    localparam logic [ACC_WIDTH:0] BASE_VALUE = BASE_HZ;
    logic [ACC_WIDTH:0] phase_sum;

    always_comb begin
        phase_sum = {1'b0, phase} + {1'b0, rate_hz};
    end

    always_ff @(posedge clk) begin
        if (rst || !enable) begin
            phase <= '0;
            ce    <= 1'b0;
        end else if (rate_hz == '0) begin
            phase <= '0;
            ce    <= 1'b0;
        end else if ({1'b0, rate_hz} >= BASE_VALUE) begin
            // Clamp invalid/over-range requests to one enable per clock.
            phase <= '0;
            ce    <= 1'b1;
        end else if (phase_sum >= BASE_VALUE) begin
            phase <= phase_sum - BASE_VALUE;
            ce    <= 1'b1;
        end else begin
            phase <= phase_sum[ACC_WIDTH-1:0];
            ce    <= 1'b0;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (BASE_HZ < 1)
            $fatal(1, "retrofm_fractional_ce BASE_HZ must be positive");
    end
`endif
endmodule
