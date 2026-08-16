`timescale 1ns/1ps
module tb_retrofm_jt03_output_mix;
    logic signed [15:0] fm;
    logic [9:0] psg;
    wire signed [15:0] mixed;

    retrofm_jt03_output_mix dut(
        .fm_audio(fm), .psg_audio(psg), .mixed_audio(mixed));

    initial begin
        fm = 16'sd12000; psg = 10'd0; #1;
        if (mixed !== 16'sd12000) $fatal(1, "FM level is incorrect");
        fm = 16'sd0; psg = 10'd400; #1;
        if (mixed !== 16'sd12800) $fatal(1, "SSG level is incorrect");
        fm = 16'sd32767; psg = 10'd1023; #1;
        if (mixed !== 16'sd32767) $fatal(1, "positive saturation is incorrect");
        fm = -16'sd32768; psg = 10'd0; #1;
        if (mixed !== -16'sd32768) $fatal(1, "negative limit is incorrect");
        fm = -16'sd20000; psg = 10'd1000; #1;
        if (mixed !== 16'sd12000) $fatal(1, "wide mixed sum is incorrect");
        fm = -16'sd20001; psg = 10'd0; #1;
        if (mixed !== -16'sd20001) $fatal(1, "negative FM level is incorrect");
        $display("RETROFM JT03 OUTPUT MIX SELF-TEST PASS");
        $finish;
    end
endmodule
