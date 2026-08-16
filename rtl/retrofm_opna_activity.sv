// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Playback-synchronous YM2608 part meter.  The lanes follow the documented
// OPNA channel order: FM1..FM6, SSG1..SSG3, rhythm, ADPCM-B.  These are register
// activity meters, not an audio-domain level detector: their job is to give
// the UI reliable note starts and a useful carrier/level proxy without
// crossing the six-channel synthesizer's internal state into AXI.
module retrofm_opna_activity (
    input  logic        clk,
    input  logic        rst,
    input  logic        clear,
    input  logic        trigger_clear,
    input  logic        write_pulse,
    input  logic        write_port1,
    input  logic [7:0]  reg_address,
    input  logic [7:0]  write_data,
    output logic [10:0] activity,
    output logic [87:0] meter_volume,
    output logic [10:0] meter_trigger
);
    logic [5:0] fm_activity;
    logic [7:0] fm_carrier [0:5];
    logic [7:0] fm_meter [0:5];
    logic [7:0] ssg_mixer;
    logic [4:0] ssg_amplitude [0:2];
    logic [7:0] ssg_meter [0:2];
    logic [7:0] rhythm_meter;
    logic [7:0] adpcm_meter;
    integer index;
    integer channel;

    function automatic logic [7:0] ssg_meter_level(
        input logic [4:0] amplitude
    );
        begin
            ssg_meter_level = amplitude[4] ? 8'hff :
                              (amplitude[3:0] * 8'd17);
        end
    endfunction

    function automatic logic ssg_enabled(
        input logic [7:0] mixer,
        input integer selected_channel
    );
        begin
            ssg_enabled = !mixer[selected_channel] ||
                          !mixer[selected_channel + 3];
        end
    endfunction

    function automatic integer fm_key_channel(input logic [2:0] code);
        begin
            case (code)
                3'd0: fm_key_channel = 0;
                3'd1: fm_key_channel = 1;
                3'd2: fm_key_channel = 2;
                3'd4: fm_key_channel = 3;
                3'd5: fm_key_channel = 4;
                3'd6: fm_key_channel = 5;
                default: fm_key_channel = -1;
            endcase
        end
    endfunction

    always_comb begin
        activity = {((ssg_amplitude[2] != 0) && ssg_enabled(ssg_mixer, 2)),
                    ((ssg_amplitude[1] != 0) && ssg_enabled(ssg_mixer, 1)),
                    ((ssg_amplitude[0] != 0) && ssg_enabled(ssg_mixer, 0)),
                    fm_activity};
        activity[9] = rhythm_meter != 0;
        activity[10] = adpcm_meter != 0;
        meter_volume = {adpcm_meter, rhythm_meter,
                        ssg_meter[2], ssg_meter[1], ssg_meter[0],
                        fm_meter[5], fm_meter[4], fm_meter[3],
                        fm_meter[2], fm_meter[1], fm_meter[0]};
    end

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            fm_activity <= 6'd0;
            ssg_mixer <= 8'h3f;
            meter_trigger <= 11'd0;
            rhythm_meter <= 8'd0;
            adpcm_meter <= 8'd0;
            for (index = 0; index < 6; index = index + 1) begin
                fm_carrier[index] <= 8'd0;
                fm_meter[index] <= 8'd0;
            end
            for (index = 0; index < 3; index = index + 1) begin
                ssg_amplitude[index] <= 5'd0;
                ssg_meter[index] <= 8'd0;
            end
        end else begin
            if (trigger_clear) meter_trigger <= 11'd0;
            if (write_pulse) begin
                // YM2608 key-on is always in port 0.  Codes 4,5,6 select
                // the second FM bank; codes 3 and 7 are invalid/reserved.
                if (!write_port1 && reg_address == 8'h28) begin
                    channel = fm_key_channel(write_data[2:0]);
                    if (channel >= 0) begin
                        fm_activity[channel] <= |write_data[7:4];
                        if (|write_data[7:4]) begin
                            fm_meter[channel] <= fm_carrier[channel];
                            meter_trigger[channel] <= 1'b1;
                        end
                    end
                end
                // Operator-4 total level is a carrier in every OPN 4-op
                // algorithm.  Port 1 contains FM4..FM6.
                if ((reg_address & 8'hfc) == 8'h4c &&
                    reg_address[1:0] < 2'd3) begin
                    channel = write_port1 ? (reg_address[1:0] + 3) :
                                            reg_address[1:0];
                    fm_carrier[channel] <=
                        {1'b0, (7'h7f - write_data[6:0])} << 1;
                end

                if (!write_port1) begin
                    case (reg_address)
                        8'h07: begin
                            for (index = 0; index < 3; index = index + 1) begin
                                if ((ssg_amplitude[index] != 0) &&
                                    !ssg_enabled(ssg_mixer, index) &&
                                    ssg_enabled(write_data, index)) begin
                                    meter_trigger[index + 6] <= 1'b1;
                                    ssg_meter[index] <=
                                        ssg_meter_level(ssg_amplitude[index]);
                                end
                            end
                            ssg_mixer <= write_data;
                        end
                        8'h08, 8'h09, 8'h0a: begin
                            index = reg_address - 8'h08;
                            ssg_amplitude[index] <= write_data[4:0];
                            ssg_meter[index] <= ssg_meter_level(write_data[4:0]);
                            if (write_data[4:0] != 0 &&
                                ssg_enabled(ssg_mixer, index))
                                meter_trigger[index + 6] <= 1'b1;
                        end
                        8'h0d: begin
                            for (index = 0; index < 3; index = index + 1) begin
                                if (ssg_amplitude[index][4] &&
                                    ssg_enabled(ssg_mixer, index)) begin
                                    ssg_meter[index] <= 8'hff;
                                    meter_trigger[index + 6] <= 1'b1;
                                end
                            end
                        end
                        // OPNA rhythm key-on/off.  A nonzero key mask starts
                        // one or more fixed-rhythm voices, so show a full kick
                        // until the UI's normal decay takes over.
                        8'h10: if (|write_data[5:0]) begin
                            rhythm_meter <= 8'hff;
                            meter_trigger[9] <= 1'b1;
                        end
                        default: begin end
                    endcase
                end else begin
                    // ADPCM-B start (bit 7) and its total-level register.
                    // A sidecar is loaded before unmute, so this follows the
                    // real Delta-T start command rather than parser progress.
                    if (reg_address == 8'h10 && write_data[7]) begin
                        if (adpcm_meter == 0) adpcm_meter <= 8'hc0;
                        meter_trigger[10] <= 1'b1;
                    end
                    if (reg_address == 8'h1b)
                        adpcm_meter <= write_data;
                end
            end
        end
    end
endmodule
