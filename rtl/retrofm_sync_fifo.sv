// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Single-clock FIFO with an explicit accepted-read/accepted-write contract.
// DEPTH need not be a power of two.  Read data is registered on an accepted
// read, which permits block-RAM inference in the eventual board integration.
module retrofm_sync_fifo #(
    parameter integer DATA_WIDTH  = 64,
    parameter integer DEPTH       = 2048,
    parameter integer ADDR_WIDTH  = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter integer COUNT_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   flush,

    input  logic                   wr_en,
    input  logic [DATA_WIDTH-1:0]  wr_data,
    output logic                   wr_accept,
    output logic                   overflow_pulse,

    input  logic                   rd_en,
    output logic [DATA_WIDTH-1:0]  rd_data,
    output logic                   rd_valid,
    output logic                   underflow_pulse,

    output logic                   full,
    output logic                   empty,
    output logic [COUNT_WIDTH-1:0] count
);
    localparam logic [ADDR_WIDTH-1:0] LAST_ADDR = DEPTH - 1;
    localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = DEPTH;

    logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] write_pointer;
    logic [ADDR_WIDTH-1:0] read_pointer;
    logic                  do_read;
    logic                  do_write;

    always_comb begin
        empty = (count == '0);
        full  = (count == DEPTH_COUNT);

        do_read = rd_en && !empty;
        // A commit presented while full is rejected even if a read occurs on
        // the same edge.  Besides matching the documented FIFO contract, this
        // avoids device-dependent dual-port block-RAM read/write collision
        // behavior when the full FIFO's pointers address the same word.
        do_write = wr_en && !full;
    end

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            write_pointer   <= '0;
            read_pointer    <= '0;
            count           <= '0;
            rd_data         <= '0;
            wr_accept       <= 1'b0;
            rd_valid        <= 1'b0;
            overflow_pulse  <= 1'b0;
            underflow_pulse <= 1'b0;
        end else begin
            wr_accept       <= do_write;
            rd_valid        <= do_read;
            overflow_pulse  <= wr_en && !do_write;
            underflow_pulse <= rd_en && !do_read;

            if (do_write) begin
                memory[write_pointer] <= wr_data;
                if (write_pointer == LAST_ADDR)
                    write_pointer <= '0;
                else
                    write_pointer <= write_pointer + 1'b1;
            end

            if (do_read) begin
                rd_data <= memory[read_pointer];
                if (read_pointer == LAST_ADDR)
                    read_pointer <= '0;
                else
                    read_pointer <= read_pointer + 1'b1;
            end

            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (DEPTH < 1)
            $fatal(1, "retrofm_sync_fifo DEPTH must be at least one");
        if (DATA_WIDTH < 1)
            $fatal(1, "retrofm_sync_fifo DATA_WIDTH must be at least one");
    end
`endif
endmodule
