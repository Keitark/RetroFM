// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Second-order pulse-density modulator based on the GPL-3.0-or-later
// jt12_dac2 architecture by Jose Tejada.  The input must be held at the DAC
// clock rate.  Signed zero maps to a 50 percent bit density, producing
// mid-rail before the AC-coupling capacitor and zero volts DC after it settles.
module retrofm_sigma_delta #(
    parameter integer WIDTH = 16
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic signed [WIDTH-1:0] sample,
    output logic                    bit_out
);
    localparam integer INTERNAL_WIDTH = WIDTH + 5;
    // Constant full-scale inputs can overload this second-order loop.  Keep
    // one eighth of each rail as loop headroom (0x7000 for a 16-bit input).
    localparam logic signed [WIDTH-1:0] MAX_INPUT =
        (1 <<< (WIDTH - 1)) - (1 <<< (WIDTH - 4));
    localparam logic signed [WIDTH-1:0] MIN_INPUT = -MAX_INPUT;

    logic signed [WIDTH-1:0] limited_sample;
    logic [WIDTH-1:0]          offset_binary_sample;
    logic [INTERNAL_WIDTH-1:0] quantizer_input;
    logic [INTERNAL_WIDTH-1:0] quantizer_error;
    logic [INTERNAL_WIDTH-1:0] error_z1;
    logic [INTERNAL_WIDTH-1:0] error_z2;

    always_comb begin
        if (sample > MAX_INPUT)
            limited_sample = MAX_INPUT;
        else if (sample < MIN_INPUT)
            limited_sample = MIN_INPUT;
        else
            limited_sample = sample;
        offset_binary_sample = {~limited_sample[WIDTH-1],
                                limited_sample[WIDTH-2:0]};
        // Width truncation is intentional: the loop arithmetic is modulo
        // 2**INTERNAL_WIDTH, matching the proven JT12 implementation.
        quantizer_input = offset_binary_sample + {error_z1, 1'b0} - error_z2;
        bit_out = ~quantizer_input[INTERNAL_WIDTH-1];
        quantizer_error = quantizer_input - {bit_out, {WIDTH{1'b0}}};
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            error_z1 <= '0;
            error_z2 <= '0;
        end else begin
            error_z1 <= quantizer_error;
            error_z2 <= error_z1;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (WIDTH < 5)
            $fatal(1, "retrofm_sigma_delta WIDTH must be at least five");
    end
`endif
endmodule
