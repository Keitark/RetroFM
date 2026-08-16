// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Low-rate sample mailbox.  The source holds the data before toggling; the
// destination waits an additional clock after synchronizing that toggle before
// capturing the bundled data.  The supported Yamaha configurations keep the
// source sample cadence far below the 100 MHz destination service rate (and
// below one source toggle per four destination clocks), so acknowledgements
// are not required.
module retrofm_sample_cdc #(
    parameter integer DATA_WIDTH = 32
) (
    input  logic                  src_clk,
    input  logic                  src_rst,
    input  logic                  src_pulse,
    input  logic [DATA_WIDTH-1:0] src_data,

    input  logic                  dst_clk,
    input  logic                  dst_rst,
    output logic [DATA_WIDTH-1:0] dst_data,
    output logic                  dst_update
);
    logic [DATA_WIDTH-1:0] src_hold;
    logic                  src_toggle;
    (* ASYNC_REG = "TRUE" *) logic toggle_meta;
    (* ASYNC_REG = "TRUE" *) logic toggle_sync;
    logic toggle_seen;
    logic capture_pending;

    always_ff @(posedge src_clk) begin
        if (src_rst) begin
            src_hold   <= '0;
            src_toggle <= 1'b0;
        end else if (src_pulse) begin
            src_hold   <= src_data;
            src_toggle <= ~src_toggle;
        end
    end

    always_ff @(posedge dst_clk) begin
        if (dst_rst) begin
            toggle_meta    <= 1'b0;
            toggle_sync    <= 1'b0;
            toggle_seen    <= 1'b0;
            capture_pending <= 1'b0;
            dst_data       <= '0;
            dst_update     <= 1'b0;
        end else begin
            toggle_meta <= src_toggle;
            toggle_sync <= toggle_meta;
            dst_update  <= 1'b0;

            if (toggle_sync != toggle_seen) begin
                toggle_seen <= toggle_sync;
                capture_pending <= 1'b1;
            end else if (capture_pending) begin
                dst_data <= src_hold;
                dst_update <= 1'b1;
                capture_pending <= 1'b0;
            end
        end
    end
endmodule
