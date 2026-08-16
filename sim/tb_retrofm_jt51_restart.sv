`timescale 1ns/1ps

module tb_retrofm_jt51_restart;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cmd_valid = 1'b0;
    logic [7:0] cmd_reg = '0;
    logic [7:0] cmd_data = '0;
    wire cmd_ready;
    wire sample_pulse;
    wire signed [15:0] audio_left;
    wire signed [15:0] audio_right;
    wire signed [15:0] dac_left;
    wire signed [15:0] dac_right;
    integer signed first_left [0:127];
    integer signed first_right [0:127];
    integer signed first_audio_left [0:127];
    integer signed first_audio_right [0:127];
    integer index;
    integer peak_dac;
    integer peak_audio;
    integer magnitude;

    always #6.25 clk = ~clk;

    retrofm_jt51_wrapper dut (
        .clk_audio(clk), .rst(rst),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_reg(cmd_reg), .cmd_data(cmd_data), .cmd_done(),
        .status(), .irq_n(), .sample_pulse(sample_pulse),
        .audio_left(audio_left), .audio_right(audio_right),
        .dac_left(dac_left), .dac_right(dac_right),
        .cen_4mhz(), .cen_2mhz()
    );

    task automatic reset_core;
        begin
            rst <= 1'b1;
            repeat (160) @(posedge clk);
            rst <= 1'b0;
            wait (cmd_ready);
            @(posedge clk);
        end
    endtask

    task automatic write_reg(input logic [7:0] reg_number,
                             input logic [7:0] value);
        integer accepting_edges;
        begin
            wait (cmd_ready);
            @(posedge clk);
            cmd_reg <= reg_number;
            cmd_data <= value;
            cmd_valid <= 1'b1;
            @(posedge clk);
            cmd_valid <= 1'b0;
            wait (!cmd_ready);
            accepting_edges = 0;
            while (!cmd_ready) begin
                @(posedge clk);
                if (dut.cen_2mhz)
                    accepting_edges = accepting_edges + 1;
            end
            // Address, data, then the complete 32-clock JT51 busy/CSR path.
            if (accepting_edges < 34)
                $fatal(1, "JT51 command released before busy/CSR settled: %0d edges",
                       accepting_edges);
        end
    endtask

    task automatic program_tone;
        integer slot;
        logic [7:0] offset;
        begin
            write_reg(8'h08, 8'h00); // channel 0 key off
            write_reg(8'h20, 8'hc7); // stereo, algorithm 7
            write_reg(8'h28, 8'h3c); // key code
            write_reg(8'h30, 8'h00); // key fraction
            write_reg(8'h38, 8'h00); // PMS/AMS off
            for (slot = 0; slot < 4; slot = slot + 1) begin
                offset = slot * 8;
                write_reg(8'h40 + offset, 8'h01 + slot[7:0]);
                write_reg(8'h60 + offset, slot * 8);
                write_reg(8'h80 + offset, 8'h1f);
                write_reg(8'ha0 + offset, 8'h00);
                write_reg(8'hc0 + offset, 8'h00);
                write_reg(8'he0 + offset, 8'h0f);
            end
            write_reg(8'h08, 8'h78); // all four operators on, channel 0
        end
    endtask

    initial begin
        reset_core();
        program_tone();
        repeat (96) @(posedge sample_pulse);
        peak_dac = 0;
        peak_audio = 0;
        for (index = 0; index < 128; index = index + 1) begin
            @(posedge sample_pulse);
            first_left[index] = $signed(dac_left);
            first_right[index] = $signed(dac_right);
            first_audio_left[index] = $signed(audio_left);
            first_audio_right[index] = $signed(audio_right);
            magnitude = $signed(dac_left) < 0 ?
                -$signed(dac_left) : $signed(dac_left);
            if (magnitude > peak_dac) peak_dac = magnitude;
            magnitude = $signed(audio_left) < 0 ?
                -$signed(audio_left) : $signed(audio_left);
            if (magnitude > peak_audio) peak_audio = magnitude;
        end
        if (peak_dac == 0 || peak_audio == 0)
            $fatal(1, "JT51 output path remained silent");

        // Leave a different operator and phase state, then model a track
        // switch.  Core reset plus the same ordered write stream must produce
        // the exact same patch and samples.
        write_reg(8'h60, 8'h7f);
        write_reg(8'h48, 8'h0f);
        repeat (37) @(posedge sample_pulse);
        repeat (13) @(posedge clk);
        reset_core();
        program_tone();
        repeat (96) @(posedge sample_pulse);
        for (index = 0; index < 128; index = index + 1) begin
            @(posedge sample_pulse);
            if ($signed(dac_left) !== first_left[index] ||
                $signed(dac_right) !== first_right[index] ||
                $signed(audio_left) !== first_audio_left[index] ||
                $signed(audio_right) !== first_audio_right[index])
                $fatal(1, "JT51 restart differs at sample %0d", index);
        end
        $display("JT51 output peaks hardware=%0d full=%0d",
                 peak_dac, peak_audio);
        $display("RETROFM JT51 RESTART SELF-TEST PASS");
        $finish;
    end

    initial begin
        #30000000;
        $fatal(1, "JT51 restart self-test timeout");
    end
endmodule
