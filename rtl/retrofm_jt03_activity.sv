// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Derive six YM2203 part meters at the point where timestamped writes reach
// JT03.  This keeps the display aligned with audible playback rather than the
// firmware parser, which normally runs hundreds of events ahead.
//
// FM has an explicit key-on command.  Its meter captures an approximate
// channel loudness from operator 4 total level; operator 4 is a carrier in
// every four-operator Yamaha algorithm.  SSG has no
// key-on command, so nonzero amplitude/envelope writes and mixer enable edges
// act as note triggers.  Trigger bits remain sticky until the AXI meter read.
module retrofm_jt03_activity (
    input  logic        clk,
    input  logic        rst,
    input  logic        clear,
    input  logic        trigger_clear,
    input  logic        write_pulse,
    input  logic [7:0]  reg_address,
    input  logic [7:0]  write_data,
    output logic [5:0]  activity,
    output logic [47:0] meter_volume,
    output logic [5:0]  meter_trigger
);
    logic [2:0] fm_activity;
    logic [7:0] fm_op4_level [0:2];
    logic [7:0] fm_meter [0:2];

    logic [7:0] ssg_mixer;
    logic [4:0] ssg_amplitude [0:2];
    logic [7:0] ssg_meter [0:2];
    logic [2:0] ssg_activity;

    integer comb_channel;
    integer seq_channel;
    function automatic logic [7:0] ssg_meter_level(
        input logic [4:0] amplitude
    );
        begin
            // Bit 4 selects the envelope generator.  Without exposing the
            // internal envelope phase, show its trigger at full scale.
            ssg_meter_level = amplitude[4] ? 8'hff :
                              (amplitude[3:0] * 8'd17);
        end
    endfunction

    function automatic logic ssg_source_enabled(
        input logic [7:0] mixer,
        input integer selected_channel
    );
        begin
            ssg_source_enabled = !mixer[selected_channel] ||
                                 !mixer[selected_channel + 3];
        end
    endfunction

    always_comb begin
        for (comb_channel = 0; comb_channel < 3;
             comb_channel = comb_channel + 1) begin
            ssg_activity[comb_channel] =
                (ssg_amplitude[comb_channel] != 5'd0) &&
                ssg_source_enabled(ssg_mixer, comb_channel);
        end
        activity = {ssg_activity, fm_activity};
        meter_volume = {ssg_meter[2], ssg_meter[1], ssg_meter[0],
                        fm_meter[2], fm_meter[1], fm_meter[0]};
    end

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            fm_activity <= 3'b000;
            ssg_mixer <= 8'h3f;
            meter_trigger <= 6'b000000;
            for (seq_channel = 0; seq_channel < 3;
                 seq_channel = seq_channel + 1) begin
                fm_op4_level[seq_channel] <= 8'd0;
                fm_meter[seq_channel] <= 8'd0;
                ssg_amplitude[seq_channel] <= 5'd0;
                ssg_meter[seq_channel] <= 8'd0;
            end
        end else begin
            if (trigger_clear) meter_trigger <= 6'b000000;

            if (write_pulse) begin
                if ((reg_address == 8'h28) &&
                    (write_data[1:0] < 2'd3)) begin
                    fm_activity[write_data[1:0]] <= |write_data[7:4];
                    if (|write_data[7:4]) begin
                        fm_meter[write_data[1:0]] <=
                            fm_op4_level[write_data[1:0]];
                        meter_trigger[write_data[1:0]] <= 1'b1;
                    end
                end

                // 0x4c-0x4e are operator 4 TL for FM1-FM3.  Precompute the
                // visual level on that register write so key-on only copies a
                // registered byte and never places a long carrier-selection
                // cone on the 100 MHz event-dispatch path.
                if (((reg_address & 8'hfc) == 8'h4c) &&
                    (reg_address[1:0] < 2'd3))
                    fm_op4_level[reg_address[1:0]] <=
                        {1'b0, (7'h7f - write_data[6:0])} << 1;

                case (reg_address)
                    8'h07: begin
                        for (seq_channel = 0; seq_channel < 3;
                             seq_channel = seq_channel + 1) begin
                            if ((ssg_amplitude[seq_channel] != 5'd0) &&
                                !ssg_source_enabled(ssg_mixer, seq_channel) &&
                                ssg_source_enabled(write_data, seq_channel)) begin
                                meter_trigger[seq_channel + 3] <= 1'b1;
                                ssg_meter[seq_channel] <= ssg_meter_level(
                                    ssg_amplitude[seq_channel]);
                            end
                        end
                        ssg_mixer <= write_data;
                    end
                    8'h08: begin
                        ssg_amplitude[0] <= write_data[4:0];
                        ssg_meter[0] <= ssg_meter_level(write_data[4:0]);
                        if ((write_data[4:0] != 5'd0) &&
                            ssg_source_enabled(ssg_mixer, 0))
                            meter_trigger[3] <= 1'b1;
                    end
                    8'h09: begin
                        ssg_amplitude[1] <= write_data[4:0];
                        ssg_meter[1] <= ssg_meter_level(write_data[4:0]);
                        if ((write_data[4:0] != 5'd0) &&
                            ssg_source_enabled(ssg_mixer, 1))
                            meter_trigger[4] <= 1'b1;
                    end
                    8'h0a: begin
                        ssg_amplitude[2] <= write_data[4:0];
                        ssg_meter[2] <= ssg_meter_level(write_data[4:0]);
                        if ((write_data[4:0] != 5'd0) &&
                            ssg_source_enabled(ssg_mixer, 2))
                            meter_trigger[5] <= 1'b1;
                    end
                    8'h0d: begin
                        // An envelope-shape write restarts the envelope and is
                        // the SSG equivalent of a fresh note trigger.
                        for (seq_channel = 0; seq_channel < 3;
                             seq_channel = seq_channel + 1) begin
                            if (ssg_amplitude[seq_channel][4] &&
                                ssg_source_enabled(ssg_mixer, seq_channel)) begin
                                meter_trigger[seq_channel + 3] <= 1'b1;
                                ssg_meter[seq_channel] <= 8'hff;
                            end
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule
