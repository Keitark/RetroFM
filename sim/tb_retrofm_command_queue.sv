// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module tb_retrofm_command_queue;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic flush = 1'b0;
    always #5 clk = ~clk;

    logic command_pulse;
    logic command_port;
    logic [7:0] command_reg;
    logic [7:0] command_data;
    logic scheduler_ready;
    logic stream_valid;
    logic stream_ready;
    logic stream_port;
    logic [7:0] stream_reg;
    logic [7:0] stream_data;
    logic overflow_pulse;
    logic [2:0] level;
    integer failures = 0;
    integer received = 0;

    retrofm_command_queue #(.DEPTH(4)) dut (
        .clk(clk), .rst(rst), .flush(flush),
        .command_pulse(command_pulse), .command_port(command_port), .command_reg(command_reg),
        .command_data(command_data), .scheduler_ready(scheduler_ready),
        .stream_valid(stream_valid), .stream_ready(stream_ready), .stream_port(stream_port),
        .stream_reg(stream_reg), .stream_data(stream_data),
        .overflow_pulse(overflow_pulse), .level(level)
    );

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $error("CHECK FAILED: %s", message);
            failures = failures + 1;
        end
    endtask

    task automatic pulse_command(input logic [7:0] index);
        begin
            @(negedge clk);
            check(scheduler_ready, "scheduler only issues while advertised ready");
            command_reg = index;
            command_data = ~index;
            command_pulse = 1'b1;
            @(posedge clk); #1;
            @(negedge clk);
            command_pulse = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (stream_valid && stream_ready) begin
            check(stream_reg == received[7:0],
                  "queue preserves command order through backpressure");
            check(stream_data == ~received[7:0],
                  "queue preserves command payload");
            received = received + 1;
        end
        #1;
        check(!overflow_pulse, "reserved physical slot prevents overflow");
    end

    initial begin
        command_pulse = 1'b0;
        command_port = 1'b0;
        command_reg = '0;
        command_data = '0;
        stream_ready = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Three scheduler pulses can be accepted into a four-word physical
        // queue while the sink is blocked.  Ready must then drop, leaving the
        // final slot reserved for a pulse registered on the preceding cycle.
        pulse_command(8'd0);
        pulse_command(8'd1);
        pulse_command(8'd2);
        repeat (4) @(posedge clk); #1;
        check(level == 3 && !scheduler_ready,
              "queue removes ready at DEPTH-1 logical occupancy");

        stream_ready = 1'b1;
        wait (scheduler_ready);
        pulse_command(8'd3);
        pulse_command(8'd4);
        wait (received == 5);
        repeat (3) @(posedge clk); #1;
        check(level == 0, "queue drains every accepted zero-delta command");

        if (failures == 0) begin
            $display("RETROFM COMMAND QUEUE SELF-TEST PASS");
            $finish;
        end
        $fatal(1, "RETROFM COMMAND QUEUE SELF-TEST FAILED: %0d", failures);
    end

    initial begin
        #100000;
        $fatal(1, "RETROFM COMMAND QUEUE SELF-TEST TIMEOUT");
    end
endmodule
