// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

module tb_retrofm_jt51_resampler;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic src_update = 1'b0;
    logic signed [15:0] src_left = '0;
    logic signed [15:0] src_right = '0;
    logic dst_ce = 1'b0;
    logic signed [15:0] dst_left;
    logic signed [15:0] dst_right;

    always #5 clk = ~clk;

    retrofm_jt51_resampler #(.INPUT_PERIOD_CYCLES(10)) dut (.*);

    task automatic source_sample(input integer left, input integer right);
        begin
            @(negedge clk);
            src_left = left;
            src_right = right;
            src_update = 1'b1;
            @(posedge clk);
            @(negedge clk);
            src_update = 1'b0;
        end
    endtask

    task automatic output_check(input integer left, input integer right,
                                input string label_text);
        begin
            $display("%s state pair=%0d phase=%0d prev=%0d/%0d current=%0d/%0d",
                     label_text, dut.have_pair, dut.phase_q15,
                     $signed(dut.previous_left), $signed(dut.previous_right),
                     $signed(dut.current_left), $signed(dut.current_right));
            @(negedge clk);
            dst_ce = 1'b1;
            @(posedge clk);
            #1;
            dst_ce = 1'b0;
            if ($signed(dst_left) !== left || $signed(dst_right) !== right)
                $fatal(1, "%s expected %0d/%0d got %0d/%0d", label_text,
                       left, right, $signed(dst_left), $signed(dst_right));
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;
        source_sample(0, 0);
        repeat (10) @(posedge clk);
        source_sample(10000, -10000);

        repeat (5) @(posedge clk);
        output_check(5000, -5000, "half interpolation");
        repeat (5) @(posedge clk);
        output_check(10000, -10000, "completed interpolation");

        source_sample(-10000, 10000);
        repeat (5) @(posedge clk);
        output_check(0, 0, "bipolar midpoint");
        repeat (5) @(posedge clk);
        output_check(-10000, 10000, "bipolar endpoint");

        $display("RETROFM JT51 RESAMPLER SELF-TEST PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "JT51 resampler self-test timeout");
    end
endmodule
