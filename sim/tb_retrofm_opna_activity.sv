// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module tb_retrofm_opna_activity;
    logic clk = 1'b0, rst = 1'b1, clear = 1'b0, trigger_clear = 1'b0;
    logic write_pulse = 1'b0, write_port1 = 1'b0;
    logic [7:0] reg_address = 8'd0, write_data = 8'd0;
    logic [10:0] activity, meter_trigger;
    logic [87:0] meter_volume;
    integer failures = 0;

    always #5 clk = ~clk;

    retrofm_opna_activity dut (
        .clk(clk), .rst(rst), .clear(clear), .trigger_clear(trigger_clear),
        .write_pulse(write_pulse), .write_port1(write_port1),
        .reg_address(reg_address), .write_data(write_data),
        .activity(activity), .meter_volume(meter_volume),
        .meter_trigger(meter_trigger)
    );

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $error("CHECK FAILED: %s", message);
                failures = failures + 1;
            end
        end
    endtask

    task automatic write_register(input logic port1, input logic [7:0] address,
                                  input logic [7:0] value);
        begin
            @(negedge clk);
            write_port1 = port1; reg_address = address; write_data = value;
            write_pulse = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            write_pulse = 1'b0;
        end
    endtask

    task automatic clear_triggers;
        begin
            @(negedge clk); trigger_clear = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); trigger_clear = 1'b0;
        end
    endtask

    initial begin
        #10000;
        $fatal(1, "RETROFM OPNA ACTIVITY SELF-TEST TIMEOUT");
    end

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        check(activity == 11'd0 && meter_volume == 88'd0,
              "reset clears all OPNA parts");

        write_register(1'b0, 8'h4c, 8'h10);
        write_register(1'b0, 8'h28, 8'hf0);
        check(activity[0] && meter_trigger[0] && meter_volume[7:0] == 8'd222,
              "FM1 carrier level and key-on are captured");
        write_register(1'b1, 8'h4c, 8'h20);
        write_register(1'b0, 8'h28, 8'hf4);
        check(activity[3] && meter_trigger[3] &&
              meter_volume[31:24] == 8'd190,
              "FM4 uses port-1 carrier level and port-0 key code");

        clear_triggers();
        write_register(1'b0, 8'h08, 8'h0f);
        write_register(1'b0, 8'h07, 8'h3e);
        check(activity[6] && meter_trigger[6] &&
              meter_volume[55:48] == 8'hff,
              "SSG1 is ordered after all six FM channels");

        write_register(1'b0, 8'h10, 8'h01);
        check(activity[9] && meter_trigger[9] &&
              meter_volume[79:72] == 8'hff,
              "rhythm key mask triggers rhythm lane");
        write_register(1'b1, 8'h1b, 8'h70);
        write_register(1'b1, 8'h10, 8'h80);
        check(activity[10] && meter_trigger[10] &&
              meter_volume[87:80] == 8'h70,
              "ADPCM-B level and start are visible in lane eleven");

        clear_triggers();
        check(meter_trigger == 11'd0, "AXI-equivalent flags read clears triggers");
        if (failures == 0) begin
            $display("RETROFM OPNA ACTIVITY SELF-TEST PASS");
            $finish;
        end
        $fatal(1, "RETROFM OPNA ACTIVITY SELF-TEST FAILED: %0d", failures);
    end
endmodule
