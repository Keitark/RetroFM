// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Regression test for the native-rate JT51 mixer conversion.  The PCM FIFO
// read-valid signal is one system-clock wide, so the sample hold must retain
// its frame through later native JT51 events but clear it on an empty 48 kHz
// PCM service tick.
module tb_pcm_balance_investigation;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic sample_ce;
    logic gain_ce;
    logic jt51_enable;
    logic signed [15:0] jt51_left;
    logic signed [15:0] jt51_right;
    logic pcm_frame_tick;
    logic pcm_frame_valid;
    logic [31:0] pcm_frame;
    logic pcm_mix_valid;
    logic [31:0] pcm_mix_frame;
    logic out_valid;
    logic signed [19:0] out_left;
    logic signed [19:0] out_right;
    integer failures = 0;

    retrofm_pcm_sample_hold pcm_hold_dut (
        .clk(clk), .rst(rst), .flush(1'b0), .source_enable(1'b1),
        .frame_tick(pcm_frame_tick), .frame_valid(pcm_frame_valid),
        .frame(pcm_frame),
        .sample_valid(pcm_mix_valid), .sample_frame(pcm_mix_frame)
    );

    retrofm_stereo_mixer #(
        .MUTE_STEP_Q15(16'd256), .RESET_MUTED(1'b0)
    ) dut (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .gain_ce(gain_ce),
        .jt51_enable(jt51_enable),
        .jt51_left(jt51_left), .jt51_right(jt51_right),
        .jt03_enable(1'b0), .jt03_mono(16'sd0),
        .opna_enable(1'b0), .opna_left(16'sd0), .opna_right(16'sd0),
        .pcm_enable(pcm_mix_valid),
        .pcm_left($signed(pcm_mix_frame[15:0])),
        .pcm_right($signed(pcm_mix_frame[31:16])),
        .volume_q15(16'h8000), .mute_request(1'b0),
        .fm_mute_request(1'b0), .mute_gain_q15(), .fm_mute_gain_q15(),
        .out_valid(out_valid), .out_left(out_left), .out_right(out_right)
    );

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $error("CHECK FAILED: %s", message);
                failures = failures + 1;
            end
        end
    endtask

    task automatic source_event(input logic is_pcm_service,
                                input logic pcm_strobe,
                                input integer expected_left,
                                input string name);
        begin
            @(negedge clk);
            pcm_frame_tick = is_pcm_service;
            pcm_frame_valid = pcm_strobe;
            sample_ce = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            sample_ce = 1'b0;
            pcm_frame_tick = 1'b0;
            pcm_frame_valid = 1'b0;
            while (!out_valid) begin
                @(posedge clk); #1;
            end
            $display("%s: out_left=%0d out_right=%0d", name,
                     $signed(out_left), $signed(out_right));
            check($signed(out_left) == expected_left, name);
        end
    endtask

    initial begin
        sample_ce = 1'b0;
        gain_ce = 1'b0;
        jt51_enable = 1'b1;
        jt51_left = 16'sd12000;
        jt51_right = 16'sd12000;
        pcm_frame_tick = 1'b0;
        pcm_frame_valid = 1'b0;
        pcm_frame = {16'sd4000, 16'sd4000};

        repeat (4) @(posedge clk);
        rst = 1'b0;

        // Q16.4 expected values use the default measured balance coefficients:
        // 0.6593 * (FM + 1.5167 * PCM).  PCM remains effectively unity after
        // the paired coefficients; FM is reduced to match MXDRV's ratio.
        source_event(1'b0, 1'b0, 126592, "FM only");
        source_event(1'b1, 1'b1, 190593, "FM plus current PCM frame");
        jt51_enable = 1'b0;
        source_event(1'b1, 1'b1, 64000, "PCM only");

        // In actual MDX/JT51 mode the paired coefficients are both active.
        // With a zero FM sample, PCM4000 becomes Q16.4 64002: the two static
        // coefficients are deliberately near reciprocal, not bit-identical.
        jt51_enable = 1'b1;
        jt51_left = 16'sd0;
        jt51_right = 16'sd0;
        source_event(1'b1, 1'b1, 64002, "JT51-mode PCM only");

        // Restore FM.  A normal 48 kHz PCM FIFO read is followed by a native
        // JT51 62.5 kHz mixer event after the one-cycle FIFO strobe is low.
        // The held PCM contribution must remain present on that event.
        jt51_left = 16'sd12000;
        jt51_right = 16'sd12000;
        source_event(1'b1, 1'b1, 190593, "PCM read event");
        source_event(1'b0, 1'b0, 190593, "following native JT51 event");

        // A PCM FIFO underrun must not replay the previous held sample.  The
        // empty 48 kHz service tick removes PCM, then the next native JT51
        // update stays FM-only.
        source_event(1'b1, 1'b0, 126592, "empty PCM service clears hold");
        source_event(1'b0, 1'b0, 126592, "native event remains PCM-silent");

        if (failures == 0) begin
            $display("PCM BALANCE INVESTIGATION PASS");
            $finish;
        end
        $fatal(1, "PCM BALANCE INVESTIGATION FAILED: %0d", failures);
    end

    initial begin
        #100000;
        $fatal(1, "PCM balance investigation timeout");
    end
endmodule
