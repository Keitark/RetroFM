// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module tb_retrofm_spectrum;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic clear_overrun = 1'b0;
    logic sample_ce = 1'b0;
    logic signed [15:0] sample_left = 16'sd0;
    logic signed [15:0] sample_right = 16'sd0;
    logic [255:0] levels;
    logic block_pulse;
    logic busy;
    logic overrun_sticky;
    integer failures = 0;
    integer index;
    integer tone_index;
    integer sample_value;
    real angle;
    logic [255:0] expected_levels;
    logic signed [63:0] reference_z1 [0:31];
    logic signed [63:0] reference_z2 [0:31];
    logic signed [63:0] reference_product;
    logic signed [63:0] reference_scaled;
    logic signed [63:0] reference_next;
    logic signed [63:0] reference_scaled_final;
    logic signed [63:0] reference_power;
    logic [63:0] reference_peak;
    integer reference_bin;
    integer reference_sample_index;
    integer target_level;
    integer minimum_target_level;
    integer maximum_target_level;

    always #5 clk = ~clk;

    retrofm_spectrum dut (
        .clk(clk), .rst(rst), .clear_overrun(clear_overrun),
        .sample_ce(sample_ce), .sample_left(sample_left),
        .sample_right(sample_right), .levels(levels),
        .block_pulse(block_pulse), .busy(busy),
        .overrun_sticky(overrun_sticky)
    );

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $error("CHECK FAILED: %s", message);
                failures = failures + 1;
            end
        end
    endtask

    task automatic push_sample(input logic signed [15:0] value);
        begin
            wait (!busy);
            @(negedge clk);
            sample_left = value;
            sample_right = value;
            sample_ce = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            sample_ce = 1'b0;
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    function automatic logic signed [63:0] reference_coefficient(
        input integer bin
    );
        begin
            case (bin)
                0: reference_coefficient = 64'sd131033;
                1: reference_coefficient = 64'sd130914;
                2: reference_coefficient = 64'sd130717;
                3: reference_coefficient = 64'sd130441;
                4: reference_coefficient = 64'sd130086;
                5: reference_coefficient = 64'sd129653;
                6: reference_coefficient = 64'sd129142;
                7: reference_coefficient = 64'sd128553;
                8: reference_coefficient = 64'sd127887;
                9: reference_coefficient = 64'sd127144;
                10: reference_coefficient = 64'sd125428;
                11: reference_coefficient = 64'sd123410;
                12: reference_coefficient = 64'sd121095;
                13: reference_coefficient = 64'sd118488;
                14: reference_coefficient = 64'sd115595;
                15: reference_coefficient = 64'sd112424;
                16: reference_coefficient = 64'sd108982;
                17: reference_coefficient = 64'sd105278;
                18: reference_coefficient = 64'sd101320;
                19: reference_coefficient = 64'sd97118;
                20: reference_coefficient = 64'sd92682;
                21: reference_coefficient = 64'sd88023;
                22: reference_coefficient = 64'sd83151;
                23: reference_coefficient = 64'sd78079;
                24: reference_coefficient = 64'sd72820;
                25: reference_coefficient = 64'sd67384;
                26: reference_coefficient = 64'sd61787;
                27: reference_coefficient = 64'sd56041;
                28: reference_coefficient = 64'sd50159;
                29: reference_coefficient = 64'sd44157;
                30: reference_coefficient = 64'sd34959;
                default: reference_coefficient = 64'sd25571;
            endcase
        end
    endfunction

    function automatic integer bin_harmonic(input integer bin);
        begin
            case (bin)
                0: bin_harmonic = 1;
                1: bin_harmonic = 2;
                2: bin_harmonic = 3;
                3: bin_harmonic = 4;
                4: bin_harmonic = 5;
                5: bin_harmonic = 6;
                6: bin_harmonic = 7;
                7: bin_harmonic = 8;
                8: bin_harmonic = 9;
                9: bin_harmonic = 10;
                10: bin_harmonic = 12;
                11: bin_harmonic = 14;
                12: bin_harmonic = 16;
                13: bin_harmonic = 18;
                14: bin_harmonic = 20;
                15: bin_harmonic = 22;
                16: bin_harmonic = 24;
                17: bin_harmonic = 26;
                18: bin_harmonic = 28;
                19: bin_harmonic = 30;
                20: bin_harmonic = 32;
                21: bin_harmonic = 34;
                22: bin_harmonic = 36;
                23: bin_harmonic = 38;
                24: bin_harmonic = 40;
                25: bin_harmonic = 42;
                26: bin_harmonic = 44;
                27: bin_harmonic = 46;
                28: bin_harmonic = 48;
                29: bin_harmonic = 50;
                30: bin_harmonic = 53;
                default: bin_harmonic = 56;
            endcase
        end
    endfunction

    function automatic [7:0] reference_log_power(input logic [63:0] value);
        integer scan;
        integer msb;
        integer magnitude_q4;
        integer mapped;
        integer fraction;
        begin
            msb = 0;
            for (scan = 0; scan < 64; scan = scan + 1)
                if (value[scan]) msb = scan;
            if (value == 0 || msb < 26) begin
                reference_log_power = 8'd0;
            end else if (msb >= 46) begin
                reference_log_power = 8'hff;
            end else begin
                fraction = (value >> (msb - 3)) & 7;
                magnitude_q4 = (msb - 26) * 8 + fraction;
                mapped = magnitude_q4 + (magnitude_q4 >> 1) +
                         (magnitude_q4 >> 4) + (magnitude_q4 >> 5);
                reference_log_power = mapped[7:0];
            end
        end
    endfunction

    function automatic logic [63:0] reference_absolute(
        input logic signed [63:0] value
    );
        begin
            reference_absolute = value[63] ? $unsigned(-value) :
                                             $unsigned(value);
        end
    endfunction

    task automatic reset_reference;
        begin
            expected_levels = 256'd0;
            reference_peak = 64'd0;
            reference_sample_index = 0;
            for (reference_bin = 0; reference_bin < 32;
                 reference_bin = reference_bin + 1) begin
                reference_z1[reference_bin] = 64'sd0;
                reference_z2[reference_bin] = 64'sd0;
            end
        end
    endtask

    // Independent, wide fixed-point model.  It deliberately does not truncate
    // recurrence state to 32 bits, so a DUT state overflow also becomes an
    // output mismatch rather than being reproduced by the testbench.
    task automatic reference_push_sample(input integer value);
        begin
            for (reference_bin = 0; reference_bin < 32;
                 reference_bin = reference_bin + 1) begin
                reference_product = reference_z1[reference_bin] *
                                    reference_coefficient(reference_bin);
                reference_scaled = reference_product >>> 16;
                reference_next = value + reference_scaled -
                                 reference_z2[reference_bin];
                if (reference_absolute(reference_next) > reference_peak)
                    reference_peak = reference_absolute(reference_next);

                if (reference_sample_index == 255) begin
                    reference_scaled_final =
                        (reference_next *
                         reference_coefficient(reference_bin)) >>> 16;
                    reference_power = reference_next * reference_next +
                        reference_z1[reference_bin] *
                        reference_z1[reference_bin] -
                        reference_scaled_final *
                        reference_z1[reference_bin];
                    expected_levels[reference_bin*8 +: 8] =
                        reference_power > 0 ?
                        reference_log_power(reference_power) : 8'd0;
                    reference_z1[reference_bin] = 64'sd0;
                    reference_z2[reference_bin] = 64'sd0;
                end else begin
                    reference_z2[reference_bin] = reference_z1[reference_bin];
                    reference_z1[reference_bin] = reference_next;
                end
            end

            if (reference_sample_index == 255)
                reference_sample_index = 0;
            else
                reference_sample_index = reference_sample_index + 1;
        end
    endtask

    initial begin
        #30000000;
        $fatal(1, "RETROFM SPECTRUM SELF-TEST TIMEOUT");
    end

    initial begin
        reset_dut();

        // Silence must produce an all-zero completed block.
        for (index = 0; index < 256; index = index + 1)
            push_sample(16'sd0);
        wait (block_pulse);
        check(levels == 256'h0, "silence produces zero spectrum bins");

        // Every bin-centered tone must match an independent, wide fixed-point
        // model.  This checks coefficient selection, product scaling, pipeline
        // association, true Goertzel power, saturation, and block boundaries.
        minimum_target_level = 255;
        maximum_target_level = 0;
        for (tone_index = 0; tone_index < 32;
             tone_index = tone_index + 1) begin
            reset_dut();
            reset_reference();
            for (index = 0; index < 256; index = index + 1) begin
                angle = 2.0 * 3.14159265358979323846 *
                        bin_harmonic(tone_index) * index / 256.0;
                sample_value = $rtoi(12000.0 * $sin(angle));
                reference_push_sample(sample_value);
                push_sample(sample_value);
            end
            wait (block_pulse); #1;
            $display("SPECTRUM TONE BIN %0d DUT=%h REF=%h PEAK=%0d",
                     tone_index, levels, expected_levels, reference_peak);
            check(levels === expected_levels,
                  $sformatf("bin %0d tone matches fixed-point reference",
                            tone_index));
            check(reference_peak < 64'd2147483648,
                  $sformatf("bin %0d tone stays within signed 32-bit state",
                            tone_index));
            target_level = levels[tone_index*8 +: 8];
            if (target_level < minimum_target_level)
                minimum_target_level = target_level;
            if (target_level > maximum_target_level)
                maximum_target_level = target_level;

            if (tone_index == 12) begin
                check(levels[12*8 +: 8] > 8'd180,
                      "3000 Hz target bin has useful level");
                check(levels[12*8 +: 8] > levels[11*8 +: 8] + 8'd20 &&
                      levels[12*8 +: 8] > levels[13*8 +: 8] + 8'd20,
                      "3000 Hz target bin dominates adjacent bins");

                // The next window must not retain resonator energy.
                for (index = 0; index < 256; index = index + 1) begin
                    reference_push_sample(0);
                    push_sample(16'sd0);
                end
                wait (block_pulse); #1;
                check(levels === expected_levels && levels == 256'h0,
                      "completed spectrum window clears Goertzel state");
            end
        end
        check(minimum_target_level >= 180,
              "equal-amplitude tones retain useful display height");
        check(maximum_target_level - minimum_target_level <= 1,
              "equal-amplitude tones are frequency-neutral across all bins");

        // A full-scale alternating block adds a non-sinusoidal overflow and
        // exact-arithmetic stress case.
        reset_dut();
        reset_reference();
        for (index = 0; index < 256; index = index + 1) begin
            sample_value = index[0] ? 32767 : -32768;
            reference_push_sample(sample_value);
            push_sample(sample_value);
        end
        wait (block_pulse); #1;
        check(levels === expected_levels,
              "full-scale alternating block matches fixed-point reference");
        check(reference_peak < 64'd2147483648,
              "full-scale alternating block stays within signed 32-bit state");

        // A second sample while the 32-bin update is active is diagnosed.
        reset_dut();
        @(negedge clk);
        sample_ce = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        sample_ce = 1'b0;
        @(posedge clk); #1;
        @(negedge clk);
        sample_ce = 1'b1;
        @(posedge clk); #1;
        check(overrun_sticky, "busy sample collision is sticky");
        @(negedge clk);
        sample_ce = 1'b0;
        clear_overrun = 1'b1;
        @(posedge clk); #1;
        check(!overrun_sticky, "overrun sticky can be cleared");

        if (failures == 0) begin
            $display("RETROFM SPECTRUM SELF-TEST PASS");
            $finish;
        end
        $fatal(1, "RETROFM SPECTRUM SELF-TEST FAILED: %0d checks", failures);
    end
endmodule
