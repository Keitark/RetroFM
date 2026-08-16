// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Five independent active-low button synchronizers/debouncers.  The output is
// an active-high pressed-state vector for the AXI BUTTONS register.
module retrofm_buttons #(
    parameter integer BUTTON_COUNT = 5,
    parameter integer DEBOUNCE_CYCLES = 500000
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic [BUTTON_COUNT-1:0] button_n,
    output logic [BUTTON_COUNT-1:0] pressed
);
    localparam integer COUNTER_WIDTH =
        (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);

    (* ASYNC_REG = "TRUE" *) logic [BUTTON_COUNT-1:0] sync_meta;
    (* ASYNC_REG = "TRUE" *) logic [BUTTON_COUNT-1:0] sync_pressed;
    logic [COUNTER_WIDTH-1:0] stable_count [0:BUTTON_COUNT-1];
    integer index;

    always_ff @(posedge clk) begin
        if (rst) begin
            sync_meta    <= '0;
            sync_pressed <= '0;
            pressed      <= '0;
            for (index = 0; index < BUTTON_COUNT; index = index + 1)
                stable_count[index] <= '0;
        end else begin
            sync_meta    <= ~button_n;
            sync_pressed <= sync_meta;
            for (index = 0; index < BUTTON_COUNT; index = index + 1) begin
                if (sync_pressed[index] == pressed[index]) begin
                    stable_count[index] <= '0;
                end else if (DEBOUNCE_CYCLES <= 1 ||
                             stable_count[index] == DEBOUNCE_CYCLES - 1) begin
                    pressed[index] <= sync_pressed[index];
                    stable_count[index] <= '0;
                end else begin
                    stable_count[index] <= stable_count[index] + 1'b1;
                end
            end
        end
    end
endmodule
