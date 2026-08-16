// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module tb_retrofm_jt03_activity;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic clear = 1'b0;
    logic trigger_clear = 1'b0;
    logic write_pulse = 1'b0;
    logic [7:0] reg_address = 8'd0;
    logic [7:0] write_data = 8'd0;
    logic [5:0] activity;
    logic [47:0] meter_volume;
    logic [5:0] meter_trigger;
    integer failures = 0;

    always #5 clk = ~clk;

    retrofm_jt03_activity dut (
        .clk(clk), .rst(rst), .clear(clear),
        .trigger_clear(trigger_clear),
        .write_pulse(write_pulse), .reg_address(reg_address),
        .write_data(write_data), .activity(activity),
        .meter_volume(meter_volume), .meter_trigger(meter_trigger)
    );

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $error("CHECK FAILED: %s", message);
                failures = failures + 1;
            end
        end
    endtask

    task automatic clear_triggers;
        begin
            @(negedge clk);
            trigger_clear = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            trigger_clear = 1'b0;
        end
    endtask

    task automatic write_register(input logic [7:0] address,
                                  input logic [7:0] value);
        begin
            @(negedge clk);
            reg_address = address;
            write_data = value;
            write_pulse = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            write_pulse = 1'b0;
        end
    endtask

    initial begin
        #10000;
        $fatal(1, "RETROFM JT03 ACTIVITY SELF-TEST TIMEOUT");
    end

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;
        check(activity == 6'b000000, "reset leaves all parts inactive");
        check(meter_volume == 48'd0 && meter_trigger == 6'd0,
              "reset clears meter values and triggers");

        // Operator 4 is a carrier in every algorithm.  TL 16 therefore
        // captures (127 - 16) * 2 = 222 without an algorithm-dependent path.
        write_register(8'h4c, 8'h10);
        write_register(8'h28, 8'hf0);
        check(activity[0], "FM1 key-on is visible");
        check(meter_trigger[0] && meter_volume[7:0] == 8'd222,
              "FM1 key-on captures carrier-derived volume");
        clear_triggers();
        check(meter_trigger == 6'd0, "AXI-equivalent read clears triggers");
        write_register(8'h28, 8'h01);
        check(!activity[1], "FM2 zero-operator command remains off");
        write_register(8'h28, 8'hf2);
        check(activity[2], "FM3 key-on is visible");
        write_register(8'h28, 8'h00);
        check(!activity[0] && activity[2], "FM1 key-off is isolated");

        // Mixer reset value disables both tone and noise. Volume alone must
        // therefore not claim audible SSG activity.
        write_register(8'h08, 8'h0f);
        check(!activity[3], "SSG1 volume alone stays inactive while muted");
        check(!meter_trigger[3], "muted SSG volume write is not a note");
        write_register(8'h07, 8'h3e);
        check(activity[3], "SSG1 tone enable exposes fixed-volume activity");
        check(meter_trigger[3] && meter_volume[31:24] == 8'hff,
              "SSG1 enable captures its fixed amplitude");
        clear_triggers();
        write_register(8'h08, 8'h07);
        check(meter_trigger[3] && meter_volume[31:24] == 8'd119,
              "active SSG amplitude write retriggers at scaled volume");
        write_register(8'h08, 8'h00);
        check(!activity[3], "SSG1 zero volume clears activity");

        write_register(8'h09, 8'h10);
        write_register(8'h07, 8'h2f);
        check(activity[4], "SSG2 noise plus envelope mode is active");
        check(meter_trigger[4] && meter_volume[39:32] == 8'hff,
              "SSG envelope mode captures full-scale trigger");
        clear_triggers();
        write_register(8'h0d, 8'h09);
        check(meter_trigger[4], "envelope-shape restart retriggers SSG2");
        write_register(8'h07, 8'h3f);
        check(!activity[4], "disabling both SSG2 sources clears activity");

        write_register(8'h0a, 8'h07);
        write_register(8'h07, 8'h1f);
        check(activity[5], "SSG3 noise activity is visible");

        @(negedge clk);
        clear = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        clear = 1'b0;
        check(activity == 6'b000000, "player flush clears FM and SSG state");
        check(meter_volume == 48'd0 && meter_trigger == 6'd0,
              "player flush clears meter state");

        if (failures == 0) begin
            $display("RETROFM JT03 ACTIVITY SELF-TEST PASS");
            $finish;
        end
        $fatal(1, "RETROFM JT03 ACTIVITY SELF-TEST FAILED: %0d checks",
               failures);
    end
endmodule
