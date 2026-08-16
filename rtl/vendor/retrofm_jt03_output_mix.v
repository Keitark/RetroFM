// SPDX-License-Identifier: GPL-3.0-or-later
`default_nettype none

/* JT03 already accumulates its three FM channels into one signed 16-bit
 * stream, while JT49 has already combined its three SSG voices.  Therefore
 * dividing this pair by the four software-YMFM output slots is not equivalent:
 * it attenuates the complete hardware chip by 12 dB.  Preserve JT03's native
 * FM/SSG balance, but widen and saturate the addition instead of allowing the
 * upstream 16-bit combined output to wrap on loud passages. */
module retrofm_jt03_output_mix (
    input  wire signed [15:0] fm_audio,
    input  wire        [9:0]  psg_audio,
    output wire signed [15:0] mixed_audio
);
    wire signed [17:0] fm_wide = {{2{fm_audio[15]}}, fm_audio};
    wire signed [17:0] psg_wide = $signed({2'b00, psg_audio, 5'b00000});
    wire signed [17:0] sum_wide = fm_wide + psg_wide;
    assign mixed_audio = sum_wide > 18'sd32767 ? 16'sh7fff :
                         sum_wide < -18'sd32768 ? 16'sh8000 :
                         sum_wide[15:0];
endmodule

`default_nettype wire
