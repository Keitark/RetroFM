// SPDX-License-Identifier: GPL-3.0-or-later
// Small Gray-pointer asynchronous FIFO for Yamaha register commands.

`default_nettype none

module retrofm_async_command_fifo #(
    parameter integer DATA_WIDTH = 16,
    parameter integer ADDR_WIDTH = 3
) (
    input  wire                       src_clk,
    input  wire                       src_rst,
    input  wire                       src_clear_blocked,
    input  wire                       src_valid,
    output wire                       src_ready,
    input  wire [DATA_WIDTH-1:0]      src_data,
    output wire                       src_accept,
    output reg                        src_blocked_sticky,

    input  wire                       dst_clk,
    input  wire                       dst_rst,
    output wire                       dst_valid,
    input  wire                       dst_ready,
    output wire [DATA_WIDTH-1:0]      dst_data
);

    localparam integer PTR_WIDTH = ADDR_WIDTH + 1;
    localparam integer DEPTH = 1 << ADDR_WIDTH;

    (* ram_style = "distributed" *)
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    reg [PTR_WIDTH-1:0] write_binary;
    reg [PTR_WIDTH-1:0] write_gray;
    reg                 write_full;
    reg [PTR_WIDTH-1:0] read_binary;
    reg [PTR_WIDTH-1:0] read_gray;
    reg                 read_empty;

    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] read_gray_src_meta;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] read_gray_src_sync;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] write_gray_dst_meta;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] write_gray_dst_sync;

    wire write_take = src_valid && src_ready;
    wire read_take = dst_valid && dst_ready;
    wire [PTR_WIDTH-1:0] write_binary_next =
        write_binary + {{(PTR_WIDTH-1){1'b0}}, write_take};
    wire [PTR_WIDTH-1:0] read_binary_next =
        read_binary + {{(PTR_WIDTH-1){1'b0}}, read_take};
    wire [PTR_WIDTH-1:0] write_gray_next =
        (write_binary_next >> 1) ^ write_binary_next;
    wire [PTR_WIDTH-1:0] read_gray_next =
        (read_binary_next >> 1) ^ read_binary_next;

    // Invert the two high Gray bits for the standard power-of-two full test.
    wire [PTR_WIDTH-1:0] read_gray_full_compare =
        {~read_gray_src_sync[PTR_WIDTH-1:PTR_WIDTH-2],
          read_gray_src_sync[PTR_WIDTH-3:0]};
    wire write_full_next = write_gray_next == read_gray_full_compare;
    wire read_empty_next = read_gray_next == write_gray_dst_sync;

    assign src_ready = !write_full;
    assign src_accept = write_take;
    assign dst_valid = !read_empty;

    // The synchronized write pointer reaches the read domain at least two
    // dst clocks after memory changes, so this show-ahead LUTRAM word is
    // stable before dst_valid asserts and until an accepted pop.
    assign dst_data = memory[read_binary[ADDR_WIDTH-1:0]];

    always @(posedge src_clk) begin
        if (src_rst) begin
            read_gray_src_meta <= {PTR_WIDTH{1'b0}};
            read_gray_src_sync <= {PTR_WIDTH{1'b0}};
        end else begin
            read_gray_src_meta <= read_gray;
            read_gray_src_sync <= read_gray_src_meta;
        end
    end

    always @(posedge dst_clk) begin
        if (dst_rst) begin
            write_gray_dst_meta <= {PTR_WIDTH{1'b0}};
            write_gray_dst_sync <= {PTR_WIDTH{1'b0}};
        end else begin
            write_gray_dst_meta <= write_gray;
            write_gray_dst_sync <= write_gray_dst_meta;
        end
    end

    always @(posedge src_clk) begin
        if (src_rst) begin
            write_binary <= {PTR_WIDTH{1'b0}};
            write_gray <= {PTR_WIDTH{1'b0}};
            write_full <= 1'b0;
            src_blocked_sticky <= 1'b0;
        end else begin
            if (write_take)
                memory[write_binary[ADDR_WIDTH-1:0]] <= src_data;
            write_binary <= write_binary_next;
            write_gray <= write_gray_next;
            write_full <= write_full_next;

            if (src_clear_blocked)
                src_blocked_sticky <= 1'b0;
            else if (src_valid && !src_ready)
                src_blocked_sticky <= 1'b1;
        end
    end

    always @(posedge dst_clk) begin
        if (dst_rst) begin
            read_binary <= {PTR_WIDTH{1'b0}};
            read_gray <= {PTR_WIDTH{1'b0}};
            read_empty <= 1'b1;
        end else begin
            read_binary <= read_binary_next;
            read_gray <= read_gray_next;
            read_empty <= read_empty_next;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_WIDTH < 2)
            $fatal(1, "retrofm_async_command_fifo ADDR_WIDTH must be >= 2");
    end
`endif

endmodule

`default_nettype wire
