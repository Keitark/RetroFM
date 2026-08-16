// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Lossless adapter from the scheduler's registered one-cycle command pulses
// to a held ready/valid stream.  One physical FIFO slot is deliberately
// reserved: scheduler_ready is removed one cycle before the FIFO can become
// full, covering the command pulse already registered in the scheduler.
module retrofm_command_queue #(
    parameter integer DEPTH = 16
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,

    input  logic        command_pulse,
    input  logic        command_port,
    input  logic [7:0]  command_reg,
    input  logic [7:0]  command_data,
    output logic        scheduler_ready,

    output logic        stream_valid,
    input  logic        stream_ready,
    output logic        stream_port,
    output logic [7:0]  stream_reg,
    output logic [7:0]  stream_data,

    output logic        overflow_pulse,
    output logic [$clog2(DEPTH+1)-1:0] level
);
    localparam integer COUNT_WIDTH = $clog2(DEPTH + 1);

    logic fifo_wr_accept;
    logic fifo_rd_en;
    logic [16:0] fifo_rd_data;
    logic fifo_rd_valid;
    logic fifo_underflow;
    logic fifo_full;
    logic fifo_empty;
    logic [COUNT_WIDTH-1:0] fifo_count;
    logic bridge_occupied;
    logic [16:0] stream_word;
    logic [COUNT_WIDTH:0] logical_level;

    always_comb begin
        logical_level = {1'b0, fifo_count} + bridge_occupied;
        level = logical_level[COUNT_WIDTH-1:0];
        // DEPTH-1 is the maximum advertised occupancy; the final physical
        // slot absorbs the scheduler output registered on this clock.
        scheduler_ready = !rst && !flush &&
                          (logical_level < (DEPTH - 1));
        {stream_port, stream_reg, stream_data} = stream_word;
    end

    retrofm_sync_fifo #(
        .DATA_WIDTH(17),
        .DEPTH(DEPTH)
    ) command_fifo (
        .clk(clk), .rst(rst), .flush(flush),
        .wr_en(command_pulse),
        .wr_data({command_port, command_reg, command_data}),
        .wr_accept(fifo_wr_accept),
        .overflow_pulse(overflow_pulse),
        .rd_en(fifo_rd_en), .rd_data(fifo_rd_data),
        .rd_valid(fifo_rd_valid), .underflow_pulse(fifo_underflow),
        .full(fifo_full), .empty(fifo_empty), .count(fifo_count)
    );

    retrofm_fifo_prefetch_bridge #(.DATA_WIDTH(17)) command_prefetch (
        .clk(clk), .rst(rst), .flush(flush),
        .fifo_empty(fifo_empty), .fifo_rd_en(fifo_rd_en),
        .fifo_rd_valid(fifo_rd_valid), .fifo_rd_data(fifo_rd_data),
        .stream_valid(stream_valid), .stream_data(stream_word),
        .stream_ready(stream_ready), .occupied(bridge_occupied)
    );

    logic unused_status;
    always_comb unused_status = ^{fifo_wr_accept, fifo_underflow, fifo_full};

`ifndef SYNTHESIS
    initial begin
        if (DEPTH < 3)
            $fatal(1, "retrofm_command_queue DEPTH must be at least three");
    end
`endif
endmodule
