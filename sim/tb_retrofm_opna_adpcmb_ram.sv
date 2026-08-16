`timescale 1ns/1ps

module tb_retrofm_opna_adpcmb_ram;
    logic sys_clk = 0;
    logic audio_clk = 0;
    logic sys_wr = 0;
    logic [3:0] sys_addr = 0;
    logic [31:0] sys_data = 0;
    logic [3:0] sys_wstrb = 0;
    logic [3:0] audio_addr = 0;
    logic [7:0] audio_data;

    always #5 sys_clk = ~sys_clk;
    always #6.25 audio_clk = ~audio_clk;

    retrofm_opna_adpcmb_ram #(.ADDR_WIDTH(4)) dut (
        .sys_clk, .sys_wr, .sys_addr, .sys_data, .sys_wstrb,
        .audio_clk, .audio_addr, .audio_data
    );

    task automatic write_word(
        input logic [3:0] address,
        input logic [31:0] data,
        input logic [3:0] strobes
    );
        begin
            @(negedge sys_clk);
            sys_addr = address;
            sys_data = data;
            sys_wstrb = strobes;
            sys_wr = 1'b1;
            @(negedge sys_clk);
            sys_wr = 1'b0;
            sys_wstrb = '0;
        end
    endtask

    task automatic expect_byte(input logic [3:0] address,
                               input logic [7:0] expected);
        begin
            @(negedge audio_clk);
            audio_addr = address;
            // One synchronous RAM read plus the registered byte lane.
            repeat (2) @(posedge audio_clk);
            #1;
            if (audio_data !== expected)
                $fatal(1, "byte %h: got %h expected %h", address,
                       audio_data, expected);
        end
    endtask

    initial begin
        write_word(4'h0, 32'h44332211, 4'b1111);
        write_word(4'h4, 32'h88776655, 4'b1111);
        // Partial write must retain untouched bytes.
        write_word(4'h0, 32'h00AA00CC, 4'b0101);

        expect_byte(4'h0, 8'hCC);
        expect_byte(4'h1, 8'h22);
        expect_byte(4'h2, 8'hAA);
        expect_byte(4'h3, 8'h44);
        expect_byte(4'h4, 8'h55);
        expect_byte(4'h5, 8'h66);
        expect_byte(4'h6, 8'h77);
        expect_byte(4'h7, 8'h88);
        $display("RETROFM OPNA ADPCM-B RAM SELF-TEST PASS");
        $finish;
    end
endmodule
