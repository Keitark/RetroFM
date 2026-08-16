/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_pcm.h"

#include <limits.h>
#include <string.h>

#define PHASE_ONE (UINT64_C(1) << 32U)

static const uint32_t rate_numerator[5] = {
    15625U, 15625U, 15625U, 31250U, 15625U
};
static const uint8_t rate_denominator[5] = {4U, 3U, 2U, 3U, 1U};

/* Exact Q11 volume curve from mdxtools 606e3a7's PCM mixer. */
static const uint8_t volume_alias[16] = {
    0x6B, 0x6F, 0x71, 0x74, 0x76, 0x79, 0x7B, 0x7D,
    0x80, 0x82, 0x84, 0x87, 0x8A, 0x8C, 0x8F, 0x91
};
static const uint16_t volume_curve[97] = {
    5, 6, 6, 7, 7, 8, 9, 10, 10, 11, 12, 14, 15, 16, 18, 20, 21,
    23, 25, 29, 31, 33, 37, 41, 46, 50, 54, 60, 66, 72, 80, 89,
    97, 107, 117, 130, 142, 156, 173, 189, 205, 226, 246, 267,
    308, 328, 369, 410, 431, 492, 533, 594, 656, 717, 799, 861,
    963, 1045, 1147, 1270, 1393, 1536, 1700, 1864, 2048, 2253,
    2479, 2724, 2991, 3298, 3625, 3994, 4383, 4834, 5325, 5837,
    6431, 7087, 7783, 8561, 9442, 10363, 11387, 12555, 13824,
    15217, 16733, 18371, 20255, 22221, 24454, 26932, 29696,
    32768, 36127, 39732, 43541
};

static bool valid_channel(size_t channel) {
    return channel < RETROFM_PCM_CHANNELS;
}

static uint16_t volume_to_gain(uint8_t volume) {
    uint8_t mapped = volume;
    if (volume <= 15U) mapped = volume_alias[volume];
    if (mapped < 0x40U || mapped > 0xA0U) return 0U;
    return volume_curve[mapped - 0x40U];
}

static uint64_t frequency_step(uint8_t frequency) {
    uint64_t denominator =
        (uint64_t)rate_denominator[frequency] * RETROFM_PCM_OUTPUT_HZ;
    return ((uint64_t)rate_numerator[frequency] << 32U) / denominator;
}

static int16_t saturate16(int64_t sample) {
    if (sample > INT16_MAX) return INT16_MAX;
    if (sample < INT16_MIN) return INT16_MIN;
    return (int16_t)sample;
}

static retrofm_pcm_result decode_next(retrofm_pcm_voice *voice,
                                      int16_t *sample) {
    retrofm_pdx_result result = retrofm_adpcm_next(&voice->decoder, sample);
    if (result == RETROFM_PDX_OK) return RETROFM_PCM_OK;
    if (result == RETROFM_PDX_END) return RETROFM_PCM_BAD_SAMPLE;
    return RETROFM_PCM_DECODE_ERROR;
}

void retrofm_pcm_init(retrofm_pcm_mixer *mixer) {
    if (mixer != NULL) memset(mixer, 0, sizeof(*mixer));
}

retrofm_pcm_result retrofm_pcm_play(retrofm_pcm_mixer *mixer,
                                    size_t channel,
                                    const uint8_t *adpcm,
                                    size_t adpcm_bytes,
                                    uint8_t frequency,
                                    uint8_t volume,
                                    uint8_t pan) {
    retrofm_pcm_voice *voice;
    retrofm_pdx_result decoder_result;

    if (mixer == NULL || adpcm == NULL || adpcm_bytes == 0U) {
        return RETROFM_PCM_BAD_ARGUMENT;
    }
    if (!valid_channel(channel)) return RETROFM_PCM_BAD_CHANNEL;
    if (frequency >= 5U) return RETROFM_PCM_BAD_FREQUENCY;
    voice = &mixer->voices[channel];
    memset(voice, 0, sizeof(*voice));
    decoder_result = retrofm_adpcm_begin(&voice->decoder, adpcm, adpcm_bytes);
    if (decoder_result != RETROFM_PDX_OK) return RETROFM_PCM_BAD_SAMPLE;
    voice->frequency = frequency;
    voice->step_q32 = frequency_step(frequency);
    voice->gain_q11 = volume_to_gain(volume);
    voice->pan = pan & 3U;
    voice->active = true;
    return RETROFM_PCM_OK;
}

retrofm_pcm_result retrofm_pcm_stop(retrofm_pcm_mixer *mixer, size_t channel) {
    if (mixer == NULL) return RETROFM_PCM_BAD_ARGUMENT;
    if (!valid_channel(channel)) return RETROFM_PCM_BAD_CHANNEL;
    memset(&mixer->voices[channel], 0, sizeof(mixer->voices[channel]));
    return RETROFM_PCM_OK;
}

retrofm_pcm_result retrofm_pcm_set_frequency(retrofm_pcm_mixer *mixer,
                                             size_t channel,
                                             uint8_t frequency) {
    if (mixer == NULL) return RETROFM_PCM_BAD_ARGUMENT;
    if (!valid_channel(channel)) return RETROFM_PCM_BAD_CHANNEL;
    if (frequency >= 5U) return RETROFM_PCM_BAD_FREQUENCY;
    mixer->voices[channel].frequency = frequency;
    mixer->voices[channel].step_q32 = frequency_step(frequency);
    return RETROFM_PCM_OK;
}

retrofm_pcm_result retrofm_pcm_set_volume(retrofm_pcm_mixer *mixer,
                                          size_t channel,
                                          uint8_t volume) {
    if (mixer == NULL) return RETROFM_PCM_BAD_ARGUMENT;
    if (!valid_channel(channel)) return RETROFM_PCM_BAD_CHANNEL;
    mixer->voices[channel].gain_q11 = volume_to_gain(volume);
    return RETROFM_PCM_OK;
}

retrofm_pcm_result retrofm_pcm_set_pan(retrofm_pcm_mixer *mixer,
                                       size_t channel,
                                       uint8_t pan) {
    if (mixer == NULL) return RETROFM_PCM_BAD_ARGUMENT;
    if (!valid_channel(channel)) return RETROFM_PCM_BAD_CHANNEL;
    mixer->voices[channel].pan = pan & 3U;
    return RETROFM_PCM_OK;
}

static retrofm_pcm_result voice_sample(retrofm_pcm_voice *voice,
                                       int32_t *sample) {
    if (!voice->active) {
        *sample = 0;
        return RETROFM_PCM_OK;
    }
    if (!voice->primed) {
        retrofm_pcm_result result = decode_next(voice, &voice->next);
        if (result != RETROFM_PCM_OK) {
            voice->active = false;
            *sample = 0;
            return result;
        }
        voice->previous = voice->next;
        voice->primed = true;
    }

    *sample = (int32_t)voice->previous +
        (int32_t)(((int64_t)(voice->next - voice->previous) *
                   (int64_t)voice->phase_q32) >> 32U);
    voice->phase_q32 += voice->step_q32;
    if (voice->phase_q32 >= PHASE_ONE) {
        retrofm_pcm_result result;
        voice->phase_q32 -= PHASE_ONE;
        voice->previous = voice->next;
        if (voice->final_sample) {
            voice->active = false;
        } else {
            result = decode_next(voice, &voice->next);
            if (result == RETROFM_PCM_BAD_SAMPLE) {
                voice->next = voice->previous;
                voice->final_sample = true;
            } else if (result != RETROFM_PCM_OK) {
                voice->active = false;
                return result;
            }
        }
    }
    return RETROFM_PCM_OK;
}

retrofm_pcm_result retrofm_pcm_next_frame(retrofm_pcm_mixer *mixer,
                                          int16_t *left,
                                          int16_t *right) {
    int64_t mix_left = 0;
    int64_t mix_right = 0;
    size_t channel;

    if (mixer == NULL || left == NULL || right == NULL) {
        return RETROFM_PCM_BAD_ARGUMENT;
    }
    for (channel = 0U; channel < RETROFM_PCM_CHANNELS; ++channel) {
        retrofm_pcm_voice *voice = &mixer->voices[channel];
        int32_t decoded;
        int64_t scaled;
        retrofm_pcm_result result = voice_sample(voice, &decoded);
        if (result == RETROFM_PCM_DECODE_ERROR) return result;
        scaled = ((int64_t)decoded * voice->gain_q11) >> 10U;
        if ((voice->pan & 1U) != 0U) mix_left += scaled;
        if ((voice->pan & 2U) != 0U) mix_right += scaled;
    }
    *left = saturate16(mix_left);
    *right = saturate16(mix_right);
    return RETROFM_PCM_OK;
}

bool retrofm_pcm_active(const retrofm_pcm_mixer *mixer) {
    size_t channel;
    if (mixer == NULL) return false;
    for (channel = 0U; channel < RETROFM_PCM_CHANNELS; ++channel) {
        if (mixer->voices[channel].active) return true;
    }
    return false;
}
