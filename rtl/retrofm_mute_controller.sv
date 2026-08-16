// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Lossless mute/unmute command arbitration around an extended core-reset
// handshake. An UNMUTE command received while bridge_reset is asserted is
// remembered and applied on the first cycle after reset completes.
module retrofm_mute_controller (
    input  logic clk,
    input  logic rst,
    input  logic mute_pulse,
    input  logic unmute_pulse,
    input  logic core_reset_pulse,
    input  logic bridge_reset,
    output logic mute_request,
    output logic pending_unmute
);
    always_ff @(posedge clk) begin
        if (rst) begin
            mute_request  <= 1'b1;
            pending_unmute <= 1'b0;
        end else if (mute_pulse || core_reset_pulse) begin
            // Explicit mute/reset always cancels an older unmute request.
            mute_request  <= 1'b1;
            pending_unmute <= 1'b0;
        end else if (bridge_reset) begin
            mute_request <= 1'b1;
            if (unmute_pulse)
                pending_unmute <= 1'b1;
        end else if (unmute_pulse || pending_unmute) begin
            mute_request  <= 1'b0;
            pending_unmute <= 1'b0;
        end
    end
endmodule
