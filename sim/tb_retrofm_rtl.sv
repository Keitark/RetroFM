// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module tb_retrofm_rtl;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    integer failures = 0;
    integer test_stage = 0;

    initial begin
        #100000;
        $fatal(1, "RETROFM RTL SELF-TEST TIMEOUT at stage %0d", test_stage);
    end

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $error("CHECK FAILED: %s", message);
                failures = failures + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // FIFO
    // ------------------------------------------------------------------
    logic fifo_flush;
    logic fifo_wr_en;
    logic [7:0] fifo_wr_data;
    logic fifo_wr_accept;
    logic fifo_overflow;
    logic fifo_rd_en;
    logic [7:0] fifo_rd_data;
    logic fifo_rd_valid;
    logic fifo_underflow;
    logic fifo_full;
    logic fifo_empty;
    logic [2:0] fifo_count;

    retrofm_sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(5)
    ) fifo_dut (
        .clk(clk), .rst(rst), .flush(fifo_flush),
        .wr_en(fifo_wr_en), .wr_data(fifo_wr_data),
        .wr_accept(fifo_wr_accept), .overflow_pulse(fifo_overflow),
        .rd_en(fifo_rd_en), .rd_data(fifo_rd_data),
        .rd_valid(fifo_rd_valid), .underflow_pulse(fifo_underflow),
        .full(fifo_full), .empty(fifo_empty), .count(fifo_count)
    );

    task automatic fifo_write(input logic [7:0] value);
        begin
            @(negedge clk);
            fifo_wr_data = value;
            fifo_wr_en = 1'b1;
            @(posedge clk); #1;
            check(fifo_wr_accept, "FIFO write should be accepted");
            @(negedge clk);
            fifo_wr_en = 1'b0;
        end
    endtask

    task automatic fifo_read_check(input logic [7:0] expected);
        begin
            @(negedge clk);
            fifo_rd_en = 1'b1;
            @(posedge clk); #1;
            check(fifo_rd_valid, "FIFO read should be valid");
            check(fifo_rd_data == expected, "FIFO preserved ordering across wrap");
            @(negedge clk);
            fifo_rd_en = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // Fractional CE
    // ------------------------------------------------------------------
    logic frac_enable;
    logic [7:0] frac_rate;
    logic frac_ce;
    logic [7:0] frac_phase;
    integer frac_pulses;

    retrofm_fractional_ce #(
        .BASE_HZ(10),
        .ACC_WIDTH(8)
    ) frac_dut (
        .clk(clk), .rst(rst), .enable(frac_enable),
        .rate_hz(frac_rate), .ce(frac_ce), .phase(frac_phase)
    );

    // ------------------------------------------------------------------
    // Mixer
    // ------------------------------------------------------------------
    logic mix_sample_ce;
    logic mix_gain_ce;
    logic mix_jt51_enable;
    logic signed [15:0] mix_jt51_left;
    logic signed [15:0] mix_jt51_right;
    logic mix_jt03_enable;
    logic signed [15:0] mix_jt03_mono;
    logic mix_opna_enable;
    logic signed [15:0] mix_opna_left;
    logic signed [15:0] mix_opna_right;
    logic mix_pcm_enable;
    logic signed [15:0] mix_pcm_left;
    logic signed [15:0] mix_pcm_right;
    logic [15:0] mix_volume;
    logic mix_mute;
    logic mix_fm_mute;
    logic [15:0] mix_mute_gain;
    logic [15:0] mix_fm_mute_gain;
    logic mix_out_valid;
    logic signed [19:0] mix_out_left;
    logic signed [19:0] mix_out_right;

    retrofm_stereo_mixer #(
        .MUTE_STEP_Q15(16'h4000),
        .RESET_MUTED(1'b1),
        // Keep this general arithmetic/mute regression independent of the
        // MDX-specific JT51/PCM balance coefficients.  The focused PCM test
        // covers the production defaults and their Q16.4 result.
        .JT51_POST_GAIN_Q15(16'h8000),
        .PCM_BALANCE_GAIN_Q15(16'h8000)
    ) mixer_dut (
        .clk(clk), .rst(rst), .sample_ce(mix_sample_ce),
        .gain_ce(mix_gain_ce),
        .jt51_enable(mix_jt51_enable),
        .jt51_left(mix_jt51_left), .jt51_right(mix_jt51_right),
        .jt03_enable(mix_jt03_enable), .jt03_mono(mix_jt03_mono),
        .opna_enable(mix_opna_enable), .opna_left(mix_opna_left),
        .opna_right(mix_opna_right),
        .pcm_enable(mix_pcm_enable),
        .pcm_left(mix_pcm_left), .pcm_right(mix_pcm_right),
        .volume_q15(mix_volume), .mute_request(mix_mute),
        .fm_mute_request(mix_fm_mute),
        .mute_gain_q15(mix_mute_gain),
        .fm_mute_gain_q15(mix_fm_mute_gain),
        .out_valid(mix_out_valid),
        .out_left(mix_out_left), .out_right(mix_out_right)
    );

    task automatic mixer_tick;
        begin
            @(negedge clk);
            mix_sample_ce = 1'b1;
            mix_gain_ce = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            mix_sample_ce = 1'b0;
            mix_gain_ce = 1'b0;
            while (!mix_out_valid) begin
                @(posedge clk); #1;
            end
        end
    endtask

    // A native JT51 update is allowed to recapture the source values but
    // must not advance the 48 kHz mute/fade ramps.  The top-level drives this
    // path from jt51_sample_update after the coherent stereo mailbox capture.
    task automatic mixer_native_tick;
        begin
            @(negedge clk);
            mix_sample_ce = 1'b1;
            mix_gain_ce = 1'b0;
            @(posedge clk); #1;
            @(negedge clk);
            mix_sample_ce = 1'b0;
            while (!mix_out_valid) begin
                @(posedge clk); #1;
            end
        end
    endtask

    // Exercise the production mixer final Q60-to-Q16.4 rounding helper at
    // the exact half-LSB and signed-rail boundaries.  This locks the narrow
    // timing-oriented implementation to symmetric ties-away-from-zero
    // behavior rather than merely checking ordinary audio-sized values.
    task automatic check_mixer_round(
        input logic signed [86:0] raw_q60,
        input logic signed [19:0] expected_q4,
        input string message
    );
        logic signed [19:0] actual_q4;
        begin
            actual_q4 = mixer_dut.round_saturate_q4(raw_q60);
            check(actual_q4 === expected_q4, message);
        end
    endtask

    // ------------------------------------------------------------------
    // Sigma-delta
    // ------------------------------------------------------------------
    logic sdm_local_reset;
    logic signed [19:0] sdm_sample;
    logic sdm_bit;
    logic signed [15:0] sdm_reference_sample;
    logic sdm_reference_bit;
    integer sdm_ones;

    retrofm_sigma_delta #(.WIDTH(20)) sdm_dut (
        .clk(clk), .rst(rst || sdm_local_reset),
        .sample(sdm_sample), .bit_out(sdm_bit)
    );

    // A Q16.4 audio value {s16, 4'b0} must produce the exact same 1-bit
    // stream as the former WIDTH=16 modulator driven by s16.  This proves the
    // widened interface adds fractional precision rather than attenuating the
    // existing DAC amplitude or changing its second-order noise shaping.
    retrofm_sigma_delta #(.WIDTH(16)) sdm_reference_dut (
        .clk(clk), .rst(rst || sdm_local_reset),
        .sample(sdm_reference_sample), .bit_out(sdm_reference_bit)
    );

    task automatic measure_sdm_q4_equivalent(
        input logic signed [15:0] value,
        input integer clocks,
        output integer ones
    );
        integer i;
        begin
            @(negedge clk);
            sdm_local_reset = 1'b1;
            sdm_reference_sample = value;
            sdm_sample = {value, 4'b0000};
            @(posedge clk); #1;
            @(negedge clk);
            sdm_local_reset = 1'b0;
            // A second-order loop has a deterministic reset transient.  Let
            // both error delays settle before measuring steady-state density.
            repeat (256) @(posedge clk);
            ones = 0;
            for (i = 0; i < clocks; i = i + 1) begin
                @(posedge clk); #1;
                check(sdm_bit == sdm_reference_bit,
                      "Q16.4 sigma-delta bitstream matches WIDTH=16 reference");
                if (sdm_bit)
                    ones = ones + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Event scheduler
    // ------------------------------------------------------------------
    logic sched_clear;
    logic sched_clear_stats;
    logic sched_run;
    logic sched_valid;
    logic [63:0] sched_data;
    logic sched_ready;
    logic jt51_wr;
    logic [7:0] jt51_reg;
    logic [7:0] jt51_data;
    logic jt03_wr;
    logic jt03_port;
    logic [7:0] jt03_reg;
    logic [7:0] jt03_data;
    logic sched_end;
    logic sched_diag;
    logic sched_pending;
    logic sched_halted;
    logic sched_core_stalled;
    logic sched_jt51_ready;
    logic sched_underrun_active;
    logic sched_late_pulse;
    logic sched_underrun_pulse;
    logic [31:0] sched_late_count;
    logic [31:0] sched_underrun_count;
    logic [63:0] sched_playback_cycles;
    logic [63:0] sched_scheduled_cycles;

    integer jt51_writes;
    integer jt03_writes;
    integer jt51_time_0;
    integer jt51_time_1;
    integer jt03_time_0;

    retrofm_event_scheduler scheduler_dut (
        .clk(clk), .rst(rst), .clear(sched_clear),
        .clear_stats(sched_clear_stats), .run(sched_run),
        .event_valid(sched_valid), .event_data(sched_data),
        .event_ready(sched_ready),
        .source_has_event(sched_valid),
        .jt51_ready(sched_jt51_ready), .jt03_ready(1'b1),
        .jt51_wr(jt51_wr), .jt51_reg(jt51_reg), .jt51_data(jt51_data),
        .jt03_wr(jt03_wr), .jt03_port(jt03_port),
        .jt03_reg(jt03_reg), .jt03_data(jt03_data),
        .end_pulse(sched_end), .diagnostic_pulse(sched_diag),
        .pending(sched_pending), .halted(sched_halted),
        .core_stalled(sched_core_stalled),
        .playback_advancing(),
        .underrun_active(sched_underrun_active),
        .late_pulse(sched_late_pulse),
        .underrun_pulse(sched_underrun_pulse),
        .late_count(sched_late_count),
        .underrun_count(sched_underrun_count),
        .playback_cycles(sched_playback_cycles),
        .scheduled_cycles(sched_scheduled_cycles)
    );

    function automatic logic [63:0] pack_event(
        input logic [31:0] delta,
        input logic [3:0] opcode,
        input logic [7:0] reg_address,
        input logic [7:0] write_data
    );
        begin
            pack_event = 64'h0;
            pack_event[31:0]  = delta;
            pack_event[39:32] = reg_address;
            pack_event[47:40] = write_data;
            pack_event[51:48] = opcode;
        end
    endfunction

    task automatic send_event(input logic [63:0] value);
        begin
            @(negedge clk);
            sched_data  = value;
            sched_valid = 1'b1;
            while (!sched_ready)
                @(negedge clk);
            @(posedge clk); #1;
            @(negedge clk);
            sched_valid = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (jt51_wr) begin
            if (jt51_writes == 0)
                jt51_time_0 = sched_playback_cycles;
            else if (jt51_writes == 1)
                jt51_time_1 = sched_playback_cycles;
            jt51_writes = jt51_writes + 1;
        end
        if (jt03_wr) begin
            if (jt03_writes == 0)
                jt03_time_0 = sched_playback_cycles;
            jt03_writes = jt03_writes + 1;
        end
    end

    initial begin
        fifo_flush = 1'b0;
        fifo_wr_en = 1'b0;
        fifo_wr_data = '0;
        fifo_rd_en = 1'b0;
        frac_enable = 1'b0;
        frac_rate = '0;
        mix_sample_ce = 1'b0;
        mix_gain_ce = 1'b0;
        mix_jt51_enable = 1'b0;
        mix_jt51_left = '0;
        mix_jt51_right = '0;
        mix_jt03_enable = 1'b0;
        mix_jt03_mono = '0;
        mix_opna_enable = 1'b0;
        mix_opna_left = '0;
        mix_opna_right = '0;
        mix_pcm_enable = 1'b0;
        mix_pcm_left = '0;
        mix_pcm_right = '0;
        mix_volume = 16'h8000;
        mix_mute = 1'b1;
        mix_fm_mute = 1'b0;
        sdm_local_reset = 1'b0;
        sdm_sample = '0;
        sdm_reference_sample = '0;
        sched_clear = 1'b0;
        sched_clear_stats = 1'b0;
        sched_run = 1'b0;
        sched_valid = 1'b0;
        sched_data = '0;
        sched_jt51_ready = 1'b1;
        jt51_writes = 0;
        jt03_writes = 0;
        jt51_time_0 = 0;
        jt51_time_1 = 0;
        jt03_time_0 = 0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        test_stage = 1;
        // FIFO: fill a non-power-of-two depth, reject overflow, then prove
        // rejected full writes and pointer wrap preserve ordering.
        fifo_write(8'd1);
        fifo_write(8'd2);
        fifo_write(8'd3);
        fifo_write(8'd4);
        fifo_write(8'd5);
        check(fifo_full && fifo_count == 5, "FIFO reports full at DEPTH");

        @(negedge clk);
        fifo_wr_data = 8'd6;
        fifo_wr_en = 1'b1;
        @(posedge clk); #1;
        check(!fifo_wr_accept && fifo_overflow, "FIFO rejects write-only overflow");

        @(negedge clk);
        fifo_wr_data = 8'd99;
        fifo_wr_en = 1'b1;
        fifo_rd_en = 1'b1;
        @(posedge clk); #1;
        check(!fifo_wr_accept && fifo_overflow && fifo_rd_valid,
              "FIFO rejects a full write even when a read frees a slot");
        check(fifo_rd_data == 8'd1, "FIFO returns oldest entry while full");
        check(!fifo_full && fifo_count == 4,
              "FIFO read safely frees one full-buffer slot");
        @(negedge clk);
        fifo_wr_en = 1'b0;
        fifo_rd_en = 1'b0;

        fifo_write(8'd99);

        fifo_read_check(8'd2);
        fifo_read_check(8'd3);
        fifo_read_check(8'd4);
        fifo_read_check(8'd5);
        fifo_read_check(8'd99);
        check(fifo_empty && fifo_count == 0, "FIFO becomes empty after wrapped reads");

        @(negedge clk);
        fifo_rd_en = 1'b1;
        @(posedge clk); #1;
        check(!fifo_rd_valid && fifo_underflow, "FIFO reports empty read");
        @(negedge clk);
        fifo_rd_en = 1'b0;

        test_stage = 2;
        // Fractional enable: exact long-term pulse count and phase.
        frac_rate = 8'd4;
        frac_enable = 1'b1;
        frac_pulses = 0;
        repeat (100) begin
            @(posedge clk); #1;
            if (frac_ce)
                frac_pulses = frac_pulses + 1;
        end
        check(frac_pulses == 40, "fractional CE produces exact 4/10 average");
        check(frac_phase == 0, "fractional CE remainder returns to zero");
        @(negedge clk);
        frac_rate = 8'd10;
        frac_pulses = 0;
        repeat (10) begin
            @(posedge clk); #1;
            if (frac_ce)
                frac_pulses = frac_pulses + 1;
        end
        check(frac_pulses == 10, "fractional CE clamps BASE_HZ to every clock");
        frac_enable = 1'b0;

        test_stage = 3;
        // Mixer: two-step unmute, positive/negative saturation, volume, mute.
        mix_jt51_enable = 1'b1;
        mix_jt03_enable = 1'b1;
        mix_pcm_enable = 1'b1;
        mix_jt51_left = 16'sd20000;
        mix_jt51_right = -16'sd20000;
        mix_jt03_mono = 16'sd20000;
        mix_pcm_left = 16'sd20000;
        mix_pcm_right = -16'sd20000;
        mix_volume = 16'h8000;
        mix_mute = 1'b0;
        mix_fm_mute = 1'b0;
        mixer_tick();
        check(mix_mute_gain == 16'h4000, "mixer unmute ramp reaches half gain");
        check(mix_out_left == 20'sd480000, "mixer applies half mute gain");
        check(mix_out_right == -20'sd160000,
              "mixer preserves signed channel summation");
        mixer_tick();
        check(mix_mute_gain == 16'h8000, "mixer unmute ramp reaches unity");
        check(mix_out_left == 20'sh7ffff, "mixer saturates positive overflow");
        check(mix_out_right == -20'sd320000,
              "mixer keeps unsaturated negative value");

        // A JT51-native source event must update the held stereo value without
        // accidentally changing the gain at 62.5 kHz.  Keep that value held
        // for 1,600 system clocks (100 MHz / 62.5 kHz) until the next native
        // event, modelling the active top-level JT51 path.
        mix_jt03_enable = 1'b0;
        mix_pcm_enable = 1'b0;
        mix_jt51_left = 16'sd1000;
        mix_jt51_right = -16'sd2000;
        mixer_native_tick();
        check(mix_mute_gain == 16'h8000,
              "native JT51 event leaves 48 kHz mute gain unchanged");
        check(mix_out_left == 20'sd16000 && mix_out_right == -20'sd32000,
              "native JT51 event transfers an atomic stereo pair");
        repeat (1600) begin
            @(posedge clk); #1;
            check(!mix_out_valid,
                  "held native JT51 sample does not create interpolated updates");
            check(mix_out_left == 20'sd16000 && mix_out_right == -20'sd32000,
                  "native JT51 stereo sample remains held for 1600 system clocks");
        end
        mix_jt51_left = -16'sd3000;
        mix_jt51_right = 16'sd4000;
        mixer_native_tick();
        check(mix_out_left == -20'sd48000 && mix_out_right == 20'sd64000,
              "next native JT51 event replaces both held channels together");

        mix_jt03_enable = 1'b1;
        mix_pcm_enable = 1'b1;
        mix_jt51_left = 16'sd20000;
        mix_jt51_right = -16'sd20000;
        mix_pcm_left = 16'sd20000;
        mix_pcm_right = -16'sd20000;

        // Force all three right sources negative to exercise negative clipping.
        mix_jt03_mono = -16'sd20000;
        mixer_tick();
        check(mix_out_right == 20'sh80000, "mixer saturates negative overflow");
        mix_jt03_mono = 16'sd20000;
        mix_volume = 16'h4000;
        mixer_tick();
        check(mix_out_left == 20'sd480000, "mixer applies Q1.15 volume");
        mix_mute = 1'b1;
        mixer_tick();
        check(mix_mute_gain == 16'h4000 && mix_out_left == 20'sd240000,
              "mixer ramps down without a discontinuous mute");
        mixer_tick();
        check(mix_mute_gain == 16'h0000 && mix_out_left == 20'sd0,
              "mixer reaches digital silence");

        // Event starvation mutes only FM; decoded PCM must continue through
        // the same global volume path without an underrun dropout.
        mix_mute = 1'b0;
        mix_fm_mute = 1'b1;
        mix_jt51_left = 16'sd12000;
        mix_jt51_right = 16'sd12000;
        mix_jt03_enable = 1'b0;
        mix_pcm_left = 16'sd4000;
        mix_pcm_right = 16'sd4000;
        mix_volume = 16'h8000;
        mixer_tick();
        mixer_tick();
        check(mix_fm_mute_gain == 16'h0000,
              "event underrun ramp reaches FM silence");
        check(mix_out_left == 20'sd64000 && mix_out_right == 20'sd64000,
              "event underrun leaves PCM playback audible");
        mix_fm_mute = 1'b0;

        test_stage = 35;
        // Final-round unit boundaries.  Q60 bit 55 is one half Q16.4 LSB.
        check_mixer_round(87'sd0, 20'sd0, "rounder preserves zero");
        check_mixer_round((87'sd1 <<< 55) - 87'sd1, 20'sd0,
                          "positive below-half Q60 residue rounds down");
        check_mixer_round(87'sd1 <<< 55, 20'sd1,
                          "positive exact half Q60 residue rounds away");
        check_mixer_round((87'sd1 <<< 55) + 87'sd1, 20'sd1,
                          "positive above-half Q60 residue rounds up");
        check_mixer_round(-((87'sd1 <<< 55) - 87'sd1), 20'sd0,
                          "negative below-half Q60 residue rounds toward zero");
        check_mixer_round(-(87'sd1 <<< 55), -20'sd1,
                          "negative exact half Q60 residue rounds away");
        check_mixer_round(-((87'sd1 <<< 55) + 87'sd1), -20'sd1,
                          "negative above-half Q60 residue rounds away");
        check_mixer_round(87'sd524287 <<< 56, 20'sh7ffff,
                          "rounder preserves exact Q16.4 positive rail");
        check_mixer_round(-(87'sd524288 <<< 56), 20'sh80000,
                          "rounder preserves exact Q16.4 negative rail");
        check_mixer_round((87'sd524287 <<< 56) + (87'sd1 <<< 55),
                          20'sh7ffff,
                          "rounder saturates positive just-overflow tie");
        check_mixer_round(-((87'sd524288 <<< 56) + (87'sd1 <<< 55)),
                          20'sh80000,
                          "rounder saturates negative just-overflow tie");

        test_stage = 4;
        // Q16.4 sigma-delta density checks.  Each call also compares every
        // output bit with a WIDTH=16 reference driven by the same normalized
        // sample, proving the new width keeps the former analog level.
        measure_sdm_q4_equivalent(16'sd0, 256, sdm_ones);
        $display("SDM density zero: %0d/256", sdm_ones);
        check(sdm_ones == 128, "sigma-delta signed zero has 50 percent density");
        measure_sdm_q4_equivalent(16'sd8192, 256, sdm_ones);
        check(sdm_ones == 160, "sigma-delta preserves +8192 normalized density");
        measure_sdm_q4_equivalent(-16'sd8192, 256, sdm_ones);
        check(sdm_ones == 96, "sigma-delta preserves -8192 normalized density");
        measure_sdm_q4_equivalent(16'sh6000, 256, sdm_ones);
        check(sdm_ones == 224, "sigma-delta preserves +0x6000 normalized density");
        measure_sdm_q4_equivalent(-16'sh6000, 256, sdm_ones);
        check(sdm_ones == 32, "sigma-delta preserves -0x6000 normalized density");
        measure_sdm_q4_equivalent(16'sh7fff, 256, sdm_ones);
        $display("SDM density positive full scale: %0d/256", sdm_ones);
        check(sdm_ones == 240,
              "sigma-delta clamps positive full scale to stable loop headroom");
        measure_sdm_q4_equivalent(16'sh8000, 256, sdm_ones);
        $display("SDM density negative full scale: %0d/256", sdm_ones);
        check(sdm_ones == 16,
              "sigma-delta clamps negative full scale to stable loop headroom");

        test_stage = 50;
        // Scheduler: exact field decode, cumulative delta timing, and an
        // ordered zero-delta burst that must not be mistaken for starvation.
        @(negedge clk);
        sched_clear = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        sched_clear = 1'b0;
        sched_data = pack_event(32'd0, 4'h0, 8'h20, 8'h7f);
        sched_valid = 1'b1;
        sched_run = 1'b1;
        // Present the first event before the first running edge so delta zero
        // is relative to playback time zero rather than an artificial driver
        // gap in the testbench.
        @(posedge clk); #1;
        @(negedge clk);
        sched_valid = 1'b0;
        test_stage = 51;
        wait (jt51_writes == 1);
        test_stage = 52;
        check(jt51_reg == 8'h20 && jt51_data == 8'h7f,
              "scheduler decodes JT51 register/data bit positions");

        test_stage = 53;
        send_event(pack_event(32'd3, 4'h1, 8'h2a, 8'h55));
        check(sched_pending, "scheduler retains a future-deadline event");
        // Keep the next zero-delta event valid until the future JT03 event is
        // due.  The timestamp-zero startup barrier means it is not valid to
        // assume that three playback cycles elapsed before this handshake.
        send_event(pack_event(32'd0, 4'h0, 8'h08, 8'h78));
        test_stage = 54;
        wait (jt03_writes == 1);
        test_stage = 55;
        check(jt03_reg == 8'h2a && jt03_data == 8'h55,
              "scheduler decodes JT03 register/data bit positions");
        wait (jt51_writes == 2);
        test_stage = 56;
        check((jt03_time_0 - jt51_time_0) == 3,
              "scheduler honors a three-cycle cumulative deadline");
        check((jt51_time_1 - jt03_time_0) == 1,
              "scheduler emits a zero-delta burst at maximum one-write throughput");
        check(sched_late_count == 0,
              "resident zero-delta burst is ordered without a late fault");
        check(jt51_reg == 8'h08 && jt51_data == 8'h78,
              "scheduler preserves the queued event payload");

        test_stage = 57;
        // Let the source genuinely starve, then submit an event whose
        // cumulative deadline is in the past.  This is the late condition.
        repeat (4) @(posedge clk);
        check(sched_underrun_active,
              "scheduler enters starvation before late-event test");
        send_event(pack_event(32'd0, 4'hf, 8'h00, 8'h00));
        wait (sched_diag);
        check(sched_late_count == 1,
              "post-starvation past-deadline event increments late count");

        test_stage = 58;
        send_event(pack_event(32'd2, 4'h2, 8'haa, 8'hbb));
        wait (!sched_pending);
        test_stage = 59;
        send_event(pack_event(32'd0, 4'hf, 8'h00, 8'h00));
        wait (sched_diag);
        check(!jt51_wr && !jt03_wr, "delay/diagnostic opcodes do not write FM cores");
        test_stage = 60;
        send_event(pack_event(32'd0, 4'h3, 8'h00, 8'h00));
        wait (sched_end);
        check(sched_halted && !sched_ready, "end opcode halts without underrun churn");

        test_stage = 6;
        // Clear and verify an empty running stream increments underrun only
        // once per starvation episode.
        @(negedge clk);
        sched_run = 1'b0;
        sched_clear = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        sched_clear = 1'b0;
        sched_run = 1'b1;
        repeat (5) @(posedge clk);
        #1;
        check(sched_underrun_count == 1 && sched_underrun_active,
              "scheduler counts one underrun per continuous empty interval");
        send_event(pack_event(32'd0, 4'h3, 8'h00, 8'h00));
        wait (sched_end);
        check(sched_underrun_count == 1,
              "end event clears starvation without adding underruns");

        test_stage = 61;
        // X68000 timing model: timestamp-zero setup is a barrier, but once
        // the first future event establishes musical time, OPM busy waiting
        // must not stretch that timeline.  PCM can therefore remain locked
        // to wall-clock 48 kHz while the command queue catches up.
        @(negedge clk);
        sched_run = 1'b0;
        sched_clear = 1'b1;
        sched_jt51_ready = 1'b0;
        @(posedge clk); #1;
        @(negedge clk);
        sched_clear = 1'b0;
        sched_run = 1'b1;
        sched_data = pack_event(32'd0, 4'h0, 8'h20, 8'hc7);
        sched_valid = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        sched_valid = 1'b0;
        repeat (6) @(posedge clk);
        #1;
        check(sched_core_stalled,
              "timestamp-zero setup reports blocked JT51 service");
        check(sched_playback_cycles == 0,
              "timestamp-zero setup holds the playback epoch");

        @(negedge clk);
        sched_jt51_ready = 1'b1;
        wait (jt51_wr);
        send_event(pack_event(32'd3, 4'hf, 8'h00, 8'h00));
        wait (sched_diag);
        check(sched_playback_cycles == 3,
              "first future event releases startup at its exact deadline");

        test_stage = 62;
        @(negedge clk);
        sched_jt51_ready = 1'b0;
        send_event(pack_event(32'd0, 4'h0, 8'h08, 8'h78));
        check(sched_core_stalled,
              "runtime JT51 backpressure retains the due write");
        jt51_time_0 = sched_playback_cycles;
        repeat (6) @(posedge clk);
        #1;
        check((sched_playback_cycles - jt51_time_0) == 6,
              "runtime JT51 backpressure does not stretch musical time");
        @(negedge clk);
        sched_jt51_ready = 1'b1;
        wait (jt51_wr);
        check(jt51_reg == 8'h08 && jt51_data == 8'h78,
              "delayed runtime JT51 write remains ordered and intact");

        if (failures == 0) begin
            test_stage = 7;
            $display("RETROFM RTL SELF-TEST PASS");
            $finish;
        end else begin
            $fatal(1, "RETROFM RTL SELF-TEST FAILED: %0d checks", failures);
        end
    end
endmodule
