/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_PCM_H
#define RETROFM_PCM_H

#include "retrofm_pdx.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RETROFM_PCM_CHANNELS 8U
#define RETROFM_PCM_OUTPUT_HZ 48000U

typedef enum retrofm_pcm_result {
    RETROFM_PCM_OK = 0,
    RETROFM_PCM_BAD_ARGUMENT,
    RETROFM_PCM_BAD_CHANNEL,
    RETROFM_PCM_BAD_FREQUENCY,
    RETROFM_PCM_BAD_SAMPLE,
    RETROFM_PCM_DECODE_ERROR
} retrofm_pcm_result;

typedef struct retrofm_pcm_voice {
    retrofm_adpcm_decoder decoder;
    uint64_t phase_q32;
    uint64_t step_q32;
    int16_t previous;
    int16_t next;
    uint16_t gain_q11;
    uint8_t frequency;
    uint8_t pan;
    bool primed;
    bool final_sample;
    bool active;
} retrofm_pcm_voice;

typedef struct retrofm_pcm_mixer {
    retrofm_pcm_voice voices[RETROFM_PCM_CHANNELS];
} retrofm_pcm_mixer;

void retrofm_pcm_init(retrofm_pcm_mixer *mixer);

retrofm_pcm_result retrofm_pcm_play(retrofm_pcm_mixer *mixer,
                                    size_t channel,
                                    const uint8_t *adpcm,
                                    size_t adpcm_bytes,
                                    uint8_t frequency,
                                    uint8_t volume,
                                    uint8_t pan);

retrofm_pcm_result retrofm_pcm_stop(retrofm_pcm_mixer *mixer, size_t channel);
retrofm_pcm_result retrofm_pcm_set_frequency(retrofm_pcm_mixer *mixer,
                                             size_t channel,
                                             uint8_t frequency);
retrofm_pcm_result retrofm_pcm_set_volume(retrofm_pcm_mixer *mixer,
                                          size_t channel,
                                          uint8_t volume);
retrofm_pcm_result retrofm_pcm_set_pan(retrofm_pcm_mixer *mixer,
                                       size_t channel,
                                       uint8_t pan);

/* Produces one signed 48 kHz stereo frame. Pan bit 0 enables left and bit 1
 * enables right, matching the MDX output-phase convention used by mdxtools. */
retrofm_pcm_result retrofm_pcm_next_frame(retrofm_pcm_mixer *mixer,
                                          int16_t *left,
                                          int16_t *right);

bool retrofm_pcm_active(const retrofm_pcm_mixer *mixer);

#ifdef __cplusplus
}
#endif

#endif
