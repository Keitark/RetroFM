// SPDX-License-Identifier: GPL-3.0-or-later
//
// Byte-addressed dual-clock sample store for the YM2608 Delta-T/ADPCM-B path.
// The PS writes aligned 32-bit words while the audio core reads bytes.  The
// audio port has one clk_audio cycle of synchronous block-RAM latency, so the
// OPNA wrapper keeps its address stable while its upstream JT10 read-enable is
// asserted.  No clearing is performed: the PS must load every range selected
// by a song before unmuting it.

`timescale 1ns/1ps

module retrofm_opna_adpcmb_ram #(
    parameter int ADDR_WIDTH = 17
) (
    input  logic                  sys_clk,
    input  logic                  sys_wr,
    input  logic [ADDR_WIDTH-1:0] sys_addr,
    input  logic [31:0]           sys_data,
    input  logic [3:0]            sys_wstrb,

    input  logic                  audio_clk,
    input  logic [ADDR_WIDTH-1:0] audio_addr,
    output logic [7:0]            audio_data
);
    localparam int WORD_ADDR_WIDTH = ADDR_WIDTH - 2;
    localparam int WORD_COUNT = 1 << WORD_ADDR_WIDTH;

    (* ram_style = "block" *) logic [31:0] memory [0:WORD_COUNT-1];
    logic [31:0] audio_word;
    logic [1:0] audio_lane;
    integer lane;

    initial begin
        if (ADDR_WIDTH < 4) $fatal(1, "ADPCM-B RAM needs at least 16 bytes");
    end

    always_ff @(posedge sys_clk) begin
        if (sys_wr) begin
            for (lane = 0; lane < 4; lane = lane + 1)
                if (sys_wstrb[lane])
                    memory[sys_addr[ADDR_WIDTH-1:2]][lane*8 +: 8] <=
                        sys_data[lane*8 +: 8];
        end
    end

    always_ff @(posedge audio_clk) begin
        audio_word <= memory[audio_addr[ADDR_WIDTH-1:2]];
        audio_lane <= audio_addr[1:0];
    end

    always_comb begin
        case (audio_lane)
            2'd0: audio_data = audio_word[7:0];
            2'd1: audio_data = audio_word[15:8];
            2'd2: audio_data = audio_word[23:16];
            default: audio_data = audio_word[31:24];
        endcase
    end
endmodule
