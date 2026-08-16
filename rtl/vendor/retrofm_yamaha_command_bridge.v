// SPDX-License-Identifier: GPL-3.0-or-later
// Independent lossless command queues from the 100 MHz scheduler domain to
// the 80 MHz Yamaha-core domain.

`default_nettype none

module retrofm_yamaha_command_bridge #(
    parameter integer FIFO_ADDR_WIDTH = 3
) (
    input  wire                       clk_system,
    input  wire                       rst_system,
    input  wire                       clear_blocked,

    input  wire                       jt51_src_valid,
    output wire                       jt51_src_ready,
    input  wire [7:0]                 jt51_src_reg,
    input  wire [7:0]                 jt51_src_data,
    output wire                       jt51_src_accept,
    output wire                       jt51_blocked_sticky,

    input  wire                       jt03_src_valid,
    output wire                       jt03_src_ready,
    input  wire                       jt03_src_port,
    input  wire [7:0]                 jt03_src_reg,
    input  wire [7:0]                 jt03_src_data,
    output wire                       jt03_src_accept,
    output wire                       jt03_blocked_sticky,

    input  wire                       clk_audio,
    input  wire                       rst_audio,

    output wire                       jt51_dst_valid,
    input  wire                       jt51_dst_ready,
    output wire [7:0]                 jt51_dst_reg,
    output wire [7:0]                 jt51_dst_data,

    output wire                       jt03_dst_valid,
    input  wire                       jt03_dst_ready,
    output wire                       jt03_dst_port,
    output wire [7:0]                 jt03_dst_reg,
    output wire [7:0]                 jt03_dst_data
);

    wire [15:0] jt51_dst_command;
    wire [16:0] jt03_dst_command;

    retrofm_async_command_fifo #(
        .DATA_WIDTH(16),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_jt51_fifo (
        .src_clk           (clk_system),
        .src_rst           (rst_system),
        .src_clear_blocked (clear_blocked),
        .src_valid         (jt51_src_valid),
        .src_ready         (jt51_src_ready),
        .src_data          ({jt51_src_reg, jt51_src_data}),
        .src_accept        (jt51_src_accept),
        .src_blocked_sticky(jt51_blocked_sticky),
        .dst_clk           (clk_audio),
        .dst_rst           (rst_audio),
        .dst_valid         (jt51_dst_valid),
        .dst_ready         (jt51_dst_ready),
        .dst_data          (jt51_dst_command)
    );

    retrofm_async_command_fifo #(
        .DATA_WIDTH(17),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_jt03_fifo (
        .src_clk           (clk_system),
        .src_rst           (rst_system),
        .src_clear_blocked (clear_blocked),
        .src_valid         (jt03_src_valid),
        .src_ready         (jt03_src_ready),
        .src_data          ({jt03_src_port, jt03_src_reg, jt03_src_data}),
        .src_accept        (jt03_src_accept),
        .src_blocked_sticky(jt03_blocked_sticky),
        .dst_clk           (clk_audio),
        .dst_rst           (rst_audio),
        .dst_valid         (jt03_dst_valid),
        .dst_ready         (jt03_dst_ready),
        .dst_data          (jt03_dst_command)
    );

    assign {jt51_dst_reg, jt51_dst_data} = jt51_dst_command;
    assign {jt03_dst_port, jt03_dst_reg, jt03_dst_data} = jt03_dst_command;

endmodule

`default_nettype wire
