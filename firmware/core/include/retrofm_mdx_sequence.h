/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_MDX_SEQUENCE_H
#define RETROFM_MDX_SEQUENCE_H

#include "retrofm_event.h"
#include "retrofm_mdx.h"
#include "retrofm_pdx.h"
#include "fm_opm_driver.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RETROFM_MDX_REPEAT_DEPTH 16U
#define RETROFM_MDX_COMMANDS_PER_TICK 4096U
#define RETROFM_MDX_PINNED_COMMIT \
    "606e3a7009aa1a9dfa6bee8bc875dbd5483714e9"

typedef bool (*retrofm_mdx_event_callback)(void *user,
                                           const retrofm_event *event);

typedef enum retrofm_mdx_pcm_opcode {
    RETROFM_MDX_PCM_PLAY = 0,
    RETROFM_MDX_PCM_STOP,
    RETROFM_MDX_PCM_SET_FREQUENCY,
    RETROFM_MDX_PCM_SET_VOLUME,
    RETROFM_MDX_PCM_SET_PAN
} retrofm_mdx_pcm_opcode;

/*
 * PCM commands carry an absolute 100 MHz timestamp so the PS can apply them
 * to retrofm_pcm at the same timeline position as the FM event stream.
 * sample_data/sample_size are populated only for PLAY and remain owned by the
 * parsed PDX backing buffer.
 */
typedef struct retrofm_mdx_pcm_command {
    uint64_t timestamp_cycles;
    const uint8_t *sample_data;
    size_t sample_size;
    uint8_t opcode;
    uint8_t channel;
    uint8_t sample_index;
    uint8_t frequency;
    uint8_t volume;
    uint8_t pan;
} retrofm_mdx_pcm_command;

typedef bool (*retrofm_mdx_pcm_callback)(
    void *user,
    const retrofm_mdx_pcm_command *command);

typedef struct retrofm_mdx_lfo_state {
    int32_t period;
    int32_t amplitude;
    int32_t phase;
    int32_t pitch;
    uint8_t waveform;
    bool enabled;
} retrofm_mdx_lfo_state;

typedef struct retrofm_mdx_repeat_state {
    size_t body_position;
    uint16_t remaining;
} retrofm_mdx_repeat_state;

typedef struct retrofm_mdx_track_state {
    const uint8_t *data;
    size_t size;
    size_t position;
    int32_t ticks_remaining;
    int32_t volume;
    int32_t opm_volume;
    int32_t staccato;
    int32_t staccato_counter;
    int32_t voice_number;
    int32_t note;
    int32_t pitch;
    int32_t portamento;
    int32_t lfo_delay;
    int32_t lfo_delay_counter;
    retrofm_mdx_lfo_state pitch_lfo;
    retrofm_mdx_lfo_state amplitude_lfo;
    retrofm_mdx_repeat_state repeats[RETROFM_MDX_REPEAT_DEPTH];
    size_t repeat_depth;
    uint32_t loop_count;
    uint8_t key_on_delay;
    uint8_t key_on_delay_counter;
    uint8_t pan;
    uint8_t pms_ams;
    uint8_t adpcm_frequency;
    int16_t detune;
    bool used;
    bool ended;
    bool waiting;
    bool skip_note_off;
    bool skip_note_on;
    bool hardware_lfo_enabled;
    bool hardware_lfo_key_sync;
} retrofm_mdx_track_state;

typedef struct retrofm_mdx_sequencer {
    const retrofm_mdx *mdx;
    const retrofm_pdx *pdx;
    retrofm_mdx_track_state tracks[RETROFM_MDX_MAX_TRACKS];
    retrofm_mdx_event_callback event_callback;
    retrofm_mdx_pcm_callback pcm_callback;
    void *callback_user;
    void *pcm_callback_user;
    uint64_t current_cycles;
    uint64_t last_event_cycles;
    uint64_t tick_count;
    uint32_t cycles_per_tick;
    int32_t fade_rate;
    int32_t fade_counter;
    int32_t fade_value;
    retrofm_mdx_result failure;
    struct fm_opm_driver opm_driver;
    bool ended;
    bool end_event_emitted;
    bool pcm8_enabled;
} retrofm_mdx_sequencer;

/* mdx and its backing file bytes must remain alive until sequencing ends. */
retrofm_mdx_result retrofm_mdx_sequencer_init(
    retrofm_mdx_sequencer *sequencer,
    const retrofm_mdx *mdx,
    retrofm_mdx_event_callback event_callback,
    void *callback_user);

/* Required instead of the FM-only initializer when mdx->uses_pdx is true. */
retrofm_mdx_result retrofm_mdx_sequencer_init_with_pdx(
    retrofm_mdx_sequencer *sequencer,
    const retrofm_mdx *mdx,
    const retrofm_pdx *pdx,
    retrofm_mdx_event_callback event_callback,
    void *callback_user,
    retrofm_mdx_pcm_callback pcm_callback,
    void *pcm_callback_user);

/* Advances one MDX timer tick. The first tick occurs after the initial period. */
retrofm_mdx_result retrofm_mdx_sequencer_tick(
    retrofm_mdx_sequencer *sequencer);

retrofm_mdx_result retrofm_mdx_sequencer_start_fade(
    retrofm_mdx_sequencer *sequencer,
    uint8_t rate);

bool retrofm_mdx_sequencer_ended(const retrofm_mdx_sequencer *sequencer);
uint64_t retrofm_mdx_sequencer_cycles(const retrofm_mdx_sequencer *sequencer);

#ifdef __cplusplus
}
#endif

#endif
