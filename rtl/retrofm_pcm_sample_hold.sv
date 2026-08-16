// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// PCM FIFO reads are valid for one system clock only.  The audio mixer can
// also be requested by an asynchronous-rate Yamaha source, so retain each
// accepted PCM frame until the next 48 kHz PCM service tick.  A newly valid
// frame bypasses the register at that tick; later native-source captures use
// the held copy.  An empty service tick clears the held sample so a PCM FIFO
// underrun becomes silence rather than repeating stale audio indefinitely.
module retrofm_pcm_sample_hold (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,
    input  logic        source_enable,
    input  logic        frame_tick,
    input  logic        frame_valid,
    input  logic [31:0] frame,
    output logic        sample_valid,
    output logic [31:0] sample_frame
);
    logic        held_valid;
    logic [31:0] held_frame;

    always_ff @(posedge clk) begin
        if (rst || flush || !source_enable) begin
            held_valid <= 1'b0;
            held_frame <= '0;
        end else if (frame_tick) begin
            held_valid <= frame_valid;
            held_frame <= frame_valid ? frame : '0;
        end
    end

    always_comb begin
        // On the service edge, choose the new FIFO result explicitly.  This
        // prevents the mixer from seeing the prior held sample on an empty
        // tick before the sequential clear above takes effect.
        if (frame_tick) begin
            sample_valid = source_enable && frame_valid;
            sample_frame = frame_valid ? frame : '0;
        end else begin
            sample_valid = source_enable && held_valid;
            sample_frame = held_frame;
        end
    end
endmodule
