`timescale 1ns/1ps

module tb_retrofm_jt03_restart;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cmd_valid = 1'b0;
    logic [7:0] cmd_reg = '0;
    logic [7:0] cmd_data = '0;
    wire cmd_ready;
    wire sample_pulse;
    wire signed [15:0] combined_audio;
    integer signed first_run [0:127];
    integer index;

    always #6.25 clk = ~clk;

    retrofm_jt03_wrapper dut (
        .clk_audio(clk), .rst(rst),
        .master_clock_hz(32'd4000000),
        .master_clock_cen(), .master_clock_invalid(),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_reg(cmd_reg), .cmd_data(cmd_data), .cmd_done(),
        .status(), .irq_n(), .sample_pulse(sample_pulse),
        .fm_audio(), .psg_audio(), .combined_audio(combined_audio),
        .core_accept_pulse()
    );

    task automatic reset_core;
        begin
            rst <= 1'b1;
            repeat (400) @(posedge clk);
            rst <= 1'b0;
            wait (cmd_ready);
            @(posedge clk);
            if (dut.mirror_opn_cnt !== 0 || dut.mirror_ssg_cnt !== 0 ||
                dut.mirror_div2 !== 0 || dut.rate_accumulator !== 0)
                $fatal(1, "JT03 reset did not release at canonical phase");
        end
    endtask

    task automatic write_reg(input logic [7:0] reg_number,
                             input logic [7:0] value);
        integer accept_count;
        begin
            wait (cmd_ready);
            @(posedge clk);
            cmd_reg <= reg_number;
            cmd_data <= value;
            cmd_valid <= 1'b1;
            @(posedge clk);
            cmd_valid <= 1'b0;
            wait (!cmd_ready);
            accept_count = 0;
            while (!cmd_ready) begin
                @(posedge clk);
                if (dut.mirror_accept)
                    accept_count = accept_count + 1;
            end
            if (accept_count < 14)
                $fatal(1, "JT03 command released before CSR settled: %0d accepts",
                       accept_count);
        end
    endtask

    task automatic program_psg;
        begin
            write_reg(8'h00, 8'h04);
            write_reg(8'h01, 8'h00);
            write_reg(8'h07, 8'h3e);
            write_reg(8'h08, 8'h0f);
        end
    endtask

    // A compact three-channel FM setup using all four operator slots.  The
    // 2D address also exercises the prescaler-select path used by 02Main.vgz.
    // Consecutive operator writes are intentional: a wrapper that accepts the
    // next command before JT03's 12-slot CSR has consumed the previous update
    // produces predecessor/phase-dependent patches here.
    task automatic program_fm;
        integer channel;
        integer slot;
        logic [7:0] offset;
        begin
            write_reg(8'h2d, 8'h00);
            for (channel = 0; channel < 3; channel = channel + 1) begin
                write_reg(8'h28, channel[7:0]);
                write_reg(8'hb0 + channel[7:0], 8'h07);
                for (slot = 0; slot < 4; slot = slot + 1) begin
                    offset = (slot * 4) + channel;
                    write_reg(8'h30 + offset, 8'h01 + slot[7:0]);
                    write_reg(8'h40 + offset, 8'h08 + (slot * 3));
                    write_reg(8'h50 + offset, 8'h1f);
                    write_reg(8'h60 + offset, 8'h08 + slot[7:0]);
                    write_reg(8'h70 + offset, 8'h03 + slot[7:0]);
                    write_reg(8'h80 + offset, 8'h18 + slot[7:0]);
                    write_reg(8'h90 + offset, 8'h00);
                end
                write_reg(8'ha4 + channel[7:0], 8'h22 + channel[7:0]);
                write_reg(8'ha0 + channel[7:0], 8'h40 + (channel * 8));
                write_reg(8'h28, 8'hf0 | channel[7:0]);
            end
        end
    endtask

    initial begin
        reset_core();
        $display("first reset released at %0t", $time);
        program_fm();
        program_psg();
        $display("first FM/PSG programmed at %0t", $time);
        repeat (64) @(posedge sample_pulse);
        for (index = 0; index < 128; index = index + 1) begin
            @(posedge sample_pulse);
            first_run[index] = $signed(combined_audio);
        end
        $display("first samples captured at %0t", $time);

        // Change both FM and PSG state and stop at a deliberately unrelated
        // phase before switching to the same target program again.
        write_reg(8'h40, 8'h7f);
        write_reg(8'h44, 8'h00);
        write_reg(8'h07, 8'h00);
        repeat (37) @(posedge sample_pulse);
        repeat (17) @(posedge clk);
        reset_core();
        $display("second reset released at %0t", $time);
        program_fm();
        program_psg();
        $display("second FM/PSG programmed at %0t", $time);
        repeat (64) @(posedge sample_pulse);
        for (index = 0; index < 128; index = index + 1) begin
            @(posedge sample_pulse);
            if ($signed(combined_audio) !== first_run[index])
                $fatal(1, "JT03 restart differs at sample %0d", index);
        end
        $display("RETROFM JT03 RESTART SELF-TEST PASS");
        $finish;
    end

    initial begin
        #20000000;
        $display("timeout state rst=%b local=%b ready=%b cen=%b cen_reg=%b opn=%0d ssg=%0d div2=%0d acc=%0d bus=%0d sample=%b",
                 rst, dut.core_reset_local, cmd_ready, dut.core_cen,
                 dut.mirror_cen_reg, dut.mirror_opn_cnt,
                 dut.mirror_ssg_cnt, dut.mirror_div2,
                 dut.rate_accumulator, dut.bus_state, sample_pulse);
        $fatal(1, "JT03 restart self-test timeout");
    end
endmodule
