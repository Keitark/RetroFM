// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Converts the registered-read interface of retrofm_sync_fifo into a stable
// ready/valid stream.  One prefetched word may be held while the downstream
// scheduler is waiting for a future deadline.
module retrofm_fifo_prefetch_bridge #(
    parameter integer DATA_WIDTH = 64
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  flush,

    input  logic                  fifo_empty,
    output logic                  fifo_rd_en,
    input  logic                  fifo_rd_valid,
    input  logic [DATA_WIDTH-1:0] fifo_rd_data,

    output logic                  stream_valid,
    output logic [DATA_WIDTH-1:0] stream_data,
    input  logic                  stream_ready,

    output logic                  occupied
);
    logic                  buffer_valid;
    logic [DATA_WIDTH-1:0] buffer_data;
    logic                  read_outstanding;
    logic                  consume;

    always_comb begin
        stream_valid = buffer_valid;
        stream_data  = buffer_data;
        consume      = buffer_valid && stream_ready;

        // A new read may be launched while the current buffer word is being
        // consumed.  read_outstanding prevents a second registered FIFO read
        // until the first result has arrived.
        fifo_rd_en = !read_outstanding && !fifo_empty &&
                     (!buffer_valid || consume);
        occupied = buffer_valid || read_outstanding;
    end

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            buffer_valid    <= 1'b0;
            buffer_data     <= '0;
            read_outstanding <= 1'b0;
        end else begin
            if (fifo_rd_en)
                read_outstanding <= 1'b1;

            if (consume)
                buffer_valid <= 1'b0;

            if (fifo_rd_valid) begin
                buffer_data      <= fifo_rd_data;
                buffer_valid     <= 1'b1;
                read_outstanding <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!rst && !flush && fifo_rd_valid && buffer_valid && !consume)
            $fatal(1, "prefetch bridge received data with no free skid slot");
    end
`endif
endmodule

