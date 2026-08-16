// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module tb_retrofm_mute_controller;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic mute_pulse = 1'b0;
    logic unmute_pulse = 1'b0;
    logic core_reset_pulse = 1'b0;
    logic bridge_reset = 1'b0;
    logic mute_request;
    logic pending_unmute;
    integer failures = 0;

    always #5 clk = ~clk;

    retrofm_mute_controller dut (.*);

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $error("FAIL: %s", message);
            failures++;
        end
    endtask

    task automatic pulse_unmute;
        unmute_pulse = 1'b1;
        @(posedge clk); #1;
        unmute_pulse = 1'b0;
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;
        check(mute_request && !pending_unmute,
              "reset leaves output muted with no pending unmute");

        bridge_reset = 1'b1;
        pulse_unmute();
        check(mute_request && pending_unmute,
              "unmute during bridge reset is retained while output stays muted");
        repeat (8) begin
            @(posedge clk); #1;
            check(mute_request && pending_unmute,
                  "extended bridge reset cannot lose pending unmute");
        end
        bridge_reset = 1'b0;
        @(posedge clk); #1;
        check(!mute_request && !pending_unmute,
              "pending unmute applies immediately after bridge reset releases");

        bridge_reset = 1'b1;
        pulse_unmute();
        mute_pulse = 1'b1;
        @(posedge clk); #1;
        mute_pulse = 1'b0;
        check(mute_request && !pending_unmute,
              "explicit mute cancels pending unmute");
        bridge_reset = 1'b0;
        repeat (2) @(posedge clk); #1;
        check(mute_request, "cancelled unmute does not leak after reset");

        unmute_pulse = 1'b1;
        core_reset_pulse = 1'b1;
        @(posedge clk); #1;
        unmute_pulse = 1'b0;
        core_reset_pulse = 1'b0;
        check(mute_request && !pending_unmute,
              "core reset has priority over simultaneous unmute");

        if (failures == 0)
            $display("PASS: RetroFM pending-unmute controller checks completed");
        else
            $fatal(1, "%0d pending-unmute checks failed", failures);
        $finish;
    end
endmodule
