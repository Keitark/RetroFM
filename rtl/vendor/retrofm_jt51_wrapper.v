// SPDX-License-Identifier: GPL-3.0-or-later
//
// Narrow integration wrapper for JT51 commit
// 985a573dcfc1ff135553a39f7eae21d18ba57cbe.
// The wrapper is intentionally fixed to an 80 MHz fabric clock.

`default_nettype none

module retrofm_jt51_wrapper (
    input  wire                       clk_audio,
    input  wire                       rst,

    input  wire                       cmd_valid,
    output wire                       cmd_ready,
    input  wire [7:0]                 cmd_reg,
    input  wire [7:0]                 cmd_data,
    output reg                        cmd_done,

    output wire [7:0]                 status,
    output wire                       irq_n,
    output wire                       sample_pulse,
    output wire signed [15:0]         audio_left,
    output wire signed [15:0]         audio_right,
    output wire signed [15:0]         dac_left,
    output wire signed [15:0]         dac_right,

    output wire                       cen_4mhz,
    output wire                       cen_2mhz
);

    localparam [1:0] BUS_IDLE = 2'd0;
    localparam [1:0] BUS_ADDR = 2'd1;
    localparam [1:0] BUS_DATA = 2'd2;
    localparam [1:0] BUS_BUSY = 2'd3;

    reg [1:0] bus_state;
    reg [7:0] held_reg;
    reg [7:0] held_data;
    reg [5:0] ce_count;

    wire core_a0 = bus_state == BUS_DATA;
    wire core_wr_n = bus_state == BUS_IDLE;
    wire [7:0] core_din = core_a0 ? held_data : held_reg;

    // 80 MHz / 20 = 4 MHz and 80 MHz / 40 = 2 MHz.  cen_2mhz is
    // phase-aligned with every other cen_4mhz pulse as JT51 expects.
    assign cen_4mhz = (ce_count == 6'd0) || (ce_count == 6'd20);
    assign cen_2mhz = (ce_count == 6'd0);

    always @(posedge clk_audio) begin
        if (rst) begin
            ce_count <= 6'd0;
        end else if (ce_count == 6'd39) begin
            ce_count <= 6'd0;
        end else begin
            ce_count <= ce_count + 6'd1;
        end
    end

    // JT51 samples both address and data only on cen_p1.  Each phase is
    // therefore held until a real 2 MHz accepting edge has occurred.  A data
    // write also starts the core's 32-synthesis-clock busy interval.  Do not
    // accept another command until that interval has completed: operator
    // parameters are transported through a 32-slot CSR and a later write can
    // otherwise replace the pending value before it reaches its target slot.
    always @(posedge clk_audio) begin
        if (rst) begin
            bus_state <= BUS_IDLE;
            held_reg <= 8'd0;
            held_data <= 8'd0;
            cmd_done <= 1'b0;
        end else begin
            cmd_done <= 1'b0;
            case (bus_state)
                BUS_IDLE: begin
                    if (cmd_valid) begin
                        held_reg <= cmd_reg;
                        held_data <= cmd_data;
                        bus_state <= BUS_ADDR;
                    end
                end

                BUS_ADDR: begin
                    if (cen_2mhz)
                        bus_state <= BUS_DATA;
                end

                BUS_DATA: begin
                    if (cen_2mhz)
                        bus_state <= BUS_BUSY;
                end

                BUS_BUSY: begin
                    if (!status[7]) begin
                        bus_state <= BUS_IDLE;
                        cmd_done <= 1'b1;
                    end
                end

                default: bus_state <= BUS_IDLE;
            endcase
        end
    end

    assign cmd_ready = bus_state == BUS_IDLE;

    jt51 u_jt51 (
        .rst        (rst),
        .clk        (clk_audio),
        .cen        (cen_4mhz),
        .cen_p1     (cen_2mhz),
        .cs_n       (1'b0),
        .wr_n       (core_wr_n),
        .a0         (core_a0),
        .din        (core_din),
        .dout       (status),
        .ct1        (),
        .ct2        (),
        .irq_n      (irq_n),
        .sample     (sample_pulse),
        .left       (dac_left),
        .right      (dac_right),
        .xleft      (audio_left),
        .xright     (audio_right)
    );

endmodule

`default_nettype wire
