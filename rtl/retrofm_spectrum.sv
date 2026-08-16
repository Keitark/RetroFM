// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Low-rate 32-bin spectrum estimator for the display.  One signed multiply
// operation is time-multiplexed across all Goertzel recurrences between
// 48 kHz samples (the 32x18 operation maps to two DSP48E1s on 7-series).
// The 256-sample bins cover the musically useful 187.5 Hz through 10.5 kHz
// range. Proper Goertzel power removes the strong low-frequency bias of the
// tempting abs(z1)+abs(z2) shortcut. A compact log2 approximation maps roughly
// -60..0 dB to 0..255 without using the Cortex-A9.
module retrofm_spectrum (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     clear_overrun,
    input  logic                     sample_ce,
    input  logic signed [15:0]       sample_left,
    input  logic signed [15:0]       sample_right,
    output logic [255:0]             levels,
    output logic                     block_pulse,
    output logic                     busy,
    output logic                     overrun_sticky
);
    localparam integer BIN_COUNT = 32;
    localparam integer STATE_WIDTH = 32;
    localparam integer COEFF_WIDTH = 18;
    localparam integer COEFF_FRAC = 16;

    // The recurrence is reset after every 256 samples.  With |input| <= 32768,
    // the largest finite-window L1 bound (bin 0), including one LSB of product
    // truncation error per recurrence, is below 221 million.  Signed 32-bit
    // state therefore has more than three bits of worst-case headroom.

    logic signed [STATE_WIDTH-1:0] state_z1 [0:BIN_COUNT-1];
    logic signed [STATE_WIDTH-1:0] state_z2 [0:BIN_COUNT-1];
    logic signed [16:0] sample_latched;
    logic [4:0] bin_index;
    logic [7:0] sample_index;
    logic [3:0] pipeline_phase;

    logic signed [16:0] mono_sum;
    logic signed [COEFF_WIDTH-1:0] coefficient;
    logic signed [COEFF_WIDTH-1:0] coefficient_reg;
    logic signed [STATE_WIDTH+COEFF_WIDTH-1:0] product_reg;
    logic signed [STATE_WIDTH-1:0] scaled_product_reg;
    logic signed [STATE_WIDTH-1:0] state_z1_work;
    logic signed [STATE_WIDTH-1:0] state_z2_work;
    logic signed [STATE_WIDTH-1:0] next_state_reg;
    logic signed [STATE_WIDTH-1:0] extended_sample;
    logic signed [STATE_WIDTH-1:0] next_state_calculated;
    logic signed [63:0] power_product_reg;
    logic signed [63:0] square_next_reg;
    logic signed [63:0] square_previous_reg;
    logic signed [64:0] power_calculated;
    logic [64:0] power_reg;
    logic [7:0] logarithmic_code_reg;
    logic [7:0] display_level;
    logic [7:0] display_level_reg;

    integer reset_index;

    function automatic logic signed [COEFF_WIDTH-1:0] bin_coefficient(
        input logic [4:0] index
    );
        begin
            // round(2*cos(2*pi*k/256) * 2^16), with k selected for useful
            // visual coverage across the useful MDX/OPM band.
            case (index)
                5'd0:  bin_coefficient = 18'sd131033;  // k=1
                5'd1:  bin_coefficient = 18'sd130914;  // k=2
                5'd2:  bin_coefficient = 18'sd130717;  // k=3
                5'd3:  bin_coefficient = 18'sd130441;  // k=4
                5'd4:  bin_coefficient = 18'sd130086;  // k=5
                5'd5:  bin_coefficient = 18'sd129653;  // k=6
                5'd6:  bin_coefficient = 18'sd129142;  // k=7
                5'd7:  bin_coefficient = 18'sd128553;  // k=8
                5'd8:  bin_coefficient = 18'sd127887;  // k=9
                5'd9:  bin_coefficient = 18'sd127144;  // k=10
                5'd10: bin_coefficient = 18'sd125428;  // k=12
                5'd11: bin_coefficient = 18'sd123410;  // k=14
                5'd12: bin_coefficient = 18'sd121095;  // k=16
                5'd13: bin_coefficient = 18'sd118488;  // k=18
                5'd14: bin_coefficient = 18'sd115595;  // k=20
                5'd15: bin_coefficient = 18'sd112424;  // k=22
                5'd16: bin_coefficient = 18'sd108982;  // k=24
                5'd17: bin_coefficient = 18'sd105278;  // k=26
                5'd18: bin_coefficient = 18'sd101320;  // k=28
                5'd19: bin_coefficient = 18'sd97118;   // k=30
                5'd20: bin_coefficient = 18'sd92682;   // k=32
                5'd21: bin_coefficient = 18'sd88023;   // k=34
                5'd22: bin_coefficient = 18'sd83151;   // k=36
                5'd23: bin_coefficient = 18'sd78079;   // k=38
                5'd24: bin_coefficient = 18'sd72820;   // k=40
                5'd25: bin_coefficient = 18'sd67384;   // k=42
                5'd26: bin_coefficient = 18'sd61787;   // k=44
                5'd27: bin_coefficient = 18'sd56041;   // k=46
                5'd28: bin_coefficient = 18'sd50159;   // k=48
                5'd29: bin_coefficient = 18'sd44157;   // k=50
                5'd30: bin_coefficient = 18'sd34959;   // k=53
                default: bin_coefficient = 18'sd25571; // k=56
            endcase
        end
    endfunction

    function automatic logic [7:0] logarithmic_power_code(
        input logic [64:0] value
    );
        integer scan;
        integer msb;
        logic [2:0] fraction;
        begin
            msb = 0;
            for (scan = 0; scan <= 64; scan = scan + 1)
                if (value[scan]) msb = scan;
            // log2(sqrt(power)) in Q4 is log2(power) in Q3. Power
            // exponents 26..46 therefore map to magnitude code 0..160.
            if (value == '0 || msb < 26) begin
                logarithmic_power_code = 8'd0;
            end else if (msb >= 46) begin
                logarithmic_power_code = 8'd160;
            end else begin
                case (msb)
                    26: fraction = value[25:23];
                    27: fraction = value[26:24];
                    28: fraction = value[27:25];
                    29: fraction = value[28:26];
                    30: fraction = value[29:27];
                    31: fraction = value[30:28];
                    32: fraction = value[31:29];
                    33: fraction = value[32:30];
                    34: fraction = value[33:31];
                    35: fraction = value[34:32];
                    36: fraction = value[35:33];
                    37: fraction = value[36:34];
                    38: fraction = value[37:35];
                    39: fraction = value[38:36];
                    40: fraction = value[39:37];
                    41: fraction = value[40:38];
                    42: fraction = value[41:39];
                    43: fraction = value[42:40];
                    44: fraction = value[43:41];
                    default: fraction = value[44:42];
                endcase
                logarithmic_power_code = ((msb - 26) << 3) + fraction;
            end
        end
    endfunction

    function automatic logic [7:0] scale_logarithmic_code(
        input logic [7:0] code
    );
        logic [8:0] mapped;
        begin
            if (code >= 8'd160) begin
                scale_logarithmic_code = 8'hff;
            end else begin
                // 255/160 = 1 + 1/2 + 1/16 + 1/32 exactly.
                mapped = {1'b0, code} + (code >> 1) +
                         (code >> 4) + (code >> 5);
                scale_logarithmic_code = mapped[7:0];
            end
        end
    endfunction

    always_comb begin
        mono_sum = $signed({sample_left[15], sample_left}) +
                   $signed({sample_right[15], sample_right});
        coefficient = bin_coefficient(bin_index);
        extended_sample = {{(STATE_WIDTH-17){sample_latched[16]}},
                           sample_latched};
        next_state_calculated = extended_sample + scaled_product_reg -
                                state_z2_work;
        power_calculated =
            $signed({square_next_reg[63], square_next_reg}) +
            $signed({square_previous_reg[63], square_previous_reg}) -
            $signed({power_product_reg[63], power_product_reg});
        display_level = scale_logarithmic_code(logarithmic_code_reg);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            levels           <= 256'h0;
            block_pulse      <= 1'b0;
            busy             <= 1'b0;
            overrun_sticky   <= 1'b0;
            sample_latched   <= 17'sd0;
            bin_index        <= 5'd0;
            sample_index     <= 8'd0;
            pipeline_phase   <= 4'd0;
            product_reg      <= '0;
            coefficient_reg  <= '0;
            scaled_product_reg <= '0;
            state_z1_work    <= '0;
            state_z2_work    <= '0;
            next_state_reg   <= '0;
            power_product_reg <= '0;
            square_next_reg <= '0;
            square_previous_reg <= '0;
            power_reg <= '0;
            logarithmic_code_reg <= '0;
            display_level_reg <= '0;
            for (reset_index = 0; reset_index < BIN_COUNT;
                 reset_index = reset_index + 1) begin
                state_z1[reset_index] <= '0;
                state_z2[reset_index] <= '0;
            end
        end else begin
            block_pulse <= 1'b0;
            if (clear_overrun)
                overrun_sticky <= 1'b0;
            if (sample_ce && busy)
                overrun_sticky <= 1'b1;

            if (!busy) begin
                if (sample_ce) begin
                    sample_latched <= mono_sum >>> 1;
                    bin_index <= 5'd0;
                    pipeline_phase <= 4'd0;
                    busy <= 1'b1;
                end
            end else begin
                case (pipeline_phase)
                    4'd0: begin
                        // Register coefficient and state separately so the
                        // 32-way coefficient mux never feeds the DSP in the
                        // same 100 MHz cycle.
                        coefficient_reg <= coefficient;
                        state_z1_work <= state_z1[bin_index];
                        state_z2_work <= state_z2[bin_index];
                        pipeline_phase <= 4'd1;
                    end
                    4'd1: begin
                        product_reg <= state_z1_work * coefficient_reg;
                        pipeline_phase <= 4'd2;
                    end
                    4'd2: begin
                        scaled_product_reg <= product_reg >>> COEFF_FRAC;
                        pipeline_phase <= 4'd3;
                    end
                    4'd3: begin
                        next_state_reg <= next_state_calculated;
                        pipeline_phase <= 4'd4;
                    end
                    4'd4: begin
                        if (sample_index != 8'hff) begin
                            state_z2[bin_index] <= state_z1_work;
                            state_z1[bin_index] <= next_state_reg;
                            pipeline_phase <= 4'd0;
                            if (bin_index == 5'd31) begin
                                busy <= 1'b0;
                                sample_index <= sample_index + 1'b1;
                            end else begin
                                bin_index <= bin_index + 1'b1;
                            end
                        end else begin
                            // At the final sample, compute true Goertzel
                            // power: z1^2 + z2^2 - coefficient*z1*z2.
                            // Here next_state_reg is the final z1 and
                            // state_z1_work is the final z2.
                            product_reg <= next_state_reg * coefficient_reg;
                            pipeline_phase <= 4'd5;
                        end
                    end
                    4'd5: begin
                        scaled_product_reg <= product_reg >>> COEFF_FRAC;
                        pipeline_phase <= 4'd6;
                    end
                    4'd6: begin
                        power_product_reg <= next_state_reg * next_state_reg;
                        pipeline_phase <= 4'd7;
                    end
                    4'd7: begin
                        square_next_reg <= power_product_reg;
                        power_product_reg <= state_z1_work * state_z1_work;
                        pipeline_phase <= 4'd8;
                    end
                    4'd8: begin
                        square_previous_reg <= power_product_reg;
                        power_product_reg <= scaled_product_reg *
                                             state_z1_work;
                        pipeline_phase <= 4'd9;
                    end
                    4'd9: begin
                        power_reg <= power_calculated[64] ? 65'd0 :
                                     $unsigned(power_calculated);
                        pipeline_phase <= 4'd10;
                    end
                    4'd10: begin
                        logarithmic_code_reg <=
                            logarithmic_power_code(power_reg);
                        pipeline_phase <= 4'd11;
                    end
                    4'd11: begin
                        display_level_reg <= display_level;
                        pipeline_phase <= 4'd12;
                    end
                    default: begin
                        // Each display block is an independent DFT window;
                        // carrying resonator state across the boundary would
                        // smear tracks and eventually overflow the recurrence.
                        state_z2[bin_index] <= '0;
                        state_z1[bin_index] <= '0;
                        levels[bin_index*8 +: 8] <= display_level_reg;
                        pipeline_phase <= 4'd0;
                        if (bin_index == 5'd31) begin
                            busy <= 1'b0;
                            sample_index <= 8'd0;
                            block_pulse <= 1'b1;
                        end else begin
                            bin_index <= bin_index + 1'b1;
                        end
                    end
                endcase
            end
        end
    end
endmodule
