/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_mdx_sequence.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

/*
 * Sequencing semantics are ported from mdxtools mdx_driver.c and
 * fm_opm_driver.c at RETROFM_MDX_PINNED_COMMIT. This local port removes the
 * software YM2151 backend and applies the bounded fixes recorded in
 * MDX_PORT_NOTES.md. RetroFM modification notice: modified/adapted on
 * 2026-08-13.
 */

#define MDX_INITIAL_TEMPO 216U
#define MDX_CYCLES_PER_TIMER_UNIT UINT32_C(25600)

static const uint8_t pcm_volume_from_opm[43] = {
    0x0FU, 0x0FU, 0x0FU, 0x0EU, 0x0EU, 0x0EU, 0x0DU, 0x0DU,
    0x0DU, 0x0CU, 0x0CU, 0x0BU, 0x0BU, 0x0BU, 0x0AU, 0x0AU,
    0x0AU, 0x09U, 0x09U, 0x08U, 0x08U, 0x08U, 0x07U, 0x07U,
    0x07U, 0x06U, 0x06U, 0x05U, 0x05U, 0x05U, 0x04U, 0x04U,
    0x04U, 0x03U, 0x03U, 0x02U, 0x02U, 0x02U, 0x01U, 0x01U,
    0x01U, 0x00U, 0x00U
};

static int16_t signed_be16(const uint8_t *bytes) {
    uint16_t value = (uint16_t)(((uint16_t)bytes[0] << 8U) | bytes[1]);
    return (int16_t)value;
}

static int32_t clamp_i64(int64_t value) {
    if (value > INT32_MAX) {
        return INT32_MAX;
    }
    if (value < INT32_MIN) {
        return INT32_MIN;
    }
    return (int32_t)value;
}

static uint8_t clamp_attenuation(int32_t value) {
    if (value < 0) {
        return 0U;
    }
    if (value > 127) {
        return 127U;
    }
    return (uint8_t)value;
}

static uint8_t mdx_volume_to_opm(int32_t volume) {
    static const uint8_t volume_table[16] = {
        0x2AU, 0x28U, 0x25U, 0x22U,
        0x20U, 0x1DU, 0x1AU, 0x18U,
        0x15U, 0x12U, 0x10U, 0x0DU,
        0x0AU, 0x08U, 0x05U, 0x02U
    };

    if (volume >= 0 && volume <= 15) {
        return volume_table[volume];
    }
    if (volume >= 128 && volume <= 255) {
        return (uint8_t)(volume - 128);
    }
    return 0U;
}

static uint8_t mdx_opm_to_pcm_volume(int32_t attenuation) {
    if (attenuation < 0) {
        return pcm_volume_from_opm[0];
    }
    if ((size_t)attenuation >= sizeof(pcm_volume_from_opm) /
                                      sizeof(pcm_volume_from_opm[0])) {
        return 0U;
    }
    return pcm_volume_from_opm[attenuation];
}

static retrofm_mdx_result fail_sequence(retrofm_mdx_sequencer *sequencer,
                                        retrofm_mdx_result result) {
    sequencer->failure = result;
    return result;
}

static retrofm_mdx_result emit_event(retrofm_mdx_sequencer *sequencer,
                                     uint8_t opcode,
                                     uint8_t reg,
                                     uint8_t data) {
    uint64_t delta;
    retrofm_event event;

    if (sequencer->event_callback == NULL ||
        sequencer->last_event_cycles > sequencer->current_cycles) {
        return fail_sequence(sequencer, RETROFM_MDX_BAD_STATE);
    }

    delta = sequencer->current_cycles - sequencer->last_event_cycles;
    while (delta > UINT32_MAX) {
        event.delta_cycles = UINT32_MAX;
        event.opcode = RETROFM_OP_DELAY;
        event.reg = 0U;
        event.data = 0U;
        event.flags = 0U;
        if (!sequencer->event_callback(sequencer->callback_user, &event)) {
            return fail_sequence(sequencer, RETROFM_MDX_CALLBACK_REJECTED);
        }
        sequencer->last_event_cycles += UINT32_MAX;
        delta -= UINT32_MAX;
    }

    event.delta_cycles = (uint32_t)delta;
    event.opcode = opcode;
    event.reg = reg;
    event.data = data;
    event.flags = 0U;
    if (!sequencer->event_callback(sequencer->callback_user, &event)) {
        return fail_sequence(sequencer, RETROFM_MDX_CALLBACK_REJECTED);
    }
    sequencer->last_event_cycles = sequencer->current_cycles;
    return RETROFM_MDX_OK;
}

static retrofm_mdx_result write_opm(retrofm_mdx_sequencer *sequencer,
                                    uint8_t reg,
                                    uint8_t data) {
    fm_driver_write_opm_reg(&sequencer->opm_driver.fm_driver, reg, data);
    return sequencer->failure;
}

static void opm_event_callback(struct fm_opm_driver *driver,
                               uint8_t reg,
                               uint8_t data) {
    retrofm_mdx_sequencer *sequencer =
        (retrofm_mdx_sequencer *)((uint8_t *)driver -
            offsetof(retrofm_mdx_sequencer, opm_driver));

    if (sequencer->failure == RETROFM_MDX_OK) {
        (void)emit_event(sequencer, RETROFM_OP_YM2151, reg, data);
    }
}

static retrofm_mdx_result emit_pcm(retrofm_mdx_sequencer *sequencer,
                                   retrofm_mdx_pcm_opcode opcode,
                                   size_t track_index,
                                   uint8_t sample_index,
                                   const uint8_t *sample_data,
                                   size_t sample_size) {
    const retrofm_mdx_track_state *track;
    retrofm_mdx_pcm_command command;

    if (sequencer->pcm_callback == NULL || track_index < 8U ||
        track_index >= 16U) {
        return fail_sequence(sequencer, RETROFM_MDX_MISSING_PDX);
    }
    track = &sequencer->tracks[track_index];
    memset(&command, 0, sizeof(command));
    command.timestamp_cycles = sequencer->current_cycles;
    command.sample_data = sample_data;
    command.sample_size = sample_size;
    command.opcode = (uint8_t)opcode;
    command.channel = (uint8_t)(track_index - 8U);
    command.sample_index = sample_index;
    command.frequency = track->adpcm_frequency;
    command.volume = mdx_opm_to_pcm_volume(
        track->opm_volume + sequencer->fade_value);
    command.pan = track->pan;
    if (!sequencer->pcm_callback(sequencer->pcm_callback_user, &command)) {
        return fail_sequence(sequencer, RETROFM_MDX_PCM_CALLBACK_REJECTED);
    }
    return RETROFM_MDX_OK;
}

static retrofm_mdx_result set_pitch(retrofm_mdx_sequencer *sequencer,
                                    size_t channel,
                                    int32_t pitch) {
    int32_t bounded_pitch = pitch;

    if (bounded_pitch < 0) {
        bounded_pitch = 0;
    } else if (bounded_pitch >= 96 * 16384) {
        bounded_pitch = 96 * 16384 - 1;
    }
    fm_driver_set_pitch(&sequencer->opm_driver.fm_driver,
                        (int)channel,
                        bounded_pitch);
    return sequencer->failure;
}

static retrofm_mdx_result set_total_level(retrofm_mdx_sequencer *sequencer,
                                          size_t channel,
                                          int32_t attenuation,
                                          const uint8_t *voice) {
    uint8_t bounded_attenuation = clamp_attenuation(attenuation);

    fm_driver_set_tl(&sequencer->opm_driver.fm_driver,
                     (int)channel,
                     bounded_attenuation,
                     (uint8_t *)voice);
    return sequencer->failure;
}

static retrofm_mdx_result load_voice(retrofm_mdx_sequencer *sequencer,
                                     size_t channel,
                                     const uint8_t *voice,
                                     int32_t attenuation,
                                     uint8_t pan) {
    fm_driver_load_voice(&sequencer->opm_driver.fm_driver,
                         (int)channel,
                         (uint8_t *)voice,
                         0,
                         (int)clamp_attenuation(attenuation),
                         (int)pan);
    return sequencer->failure;
}

static retrofm_mdx_result load_hardware_lfo(retrofm_mdx_sequencer *sequencer,
                                            uint8_t waveform,
                                            uint8_t frequency,
                                            uint8_t pmd,
                                            uint8_t amd) {
    fm_driver_load_lfo(&sequencer->opm_driver.fm_driver,
                       0,
                       waveform,
                       frequency,
                       pmd,
                       amd);
    return sequencer->failure;
}

static void lfo_initialize(retrofm_mdx_lfo_state *lfo,
                           uint8_t waveform,
                           uint16_t period,
                           int16_t amplitude) {
    lfo->enabled = true;
    lfo->waveform = waveform;
    lfo->period = period;
    lfo->amplitude = amplitude;
}

static void lfo_start(retrofm_mdx_lfo_state *lfo) {
    lfo->phase = 0;
    lfo->pitch = 0;
    if (lfo->waveform == 0U || lfo->waveform == 2U) {
        lfo->phase = lfo->period / 2;
    }
    if (lfo->waveform == 2U) {
        lfo->pitch = clamp_i64((int64_t)lfo->amplitude * 2);
    }
}

static void lfo_tick(retrofm_mdx_lfo_state *lfo) {
    bool phase_reset = false;

    if (!lfo->enabled || lfo->period <= 0) {
        return;
    }
    ++lfo->phase;
    if (lfo->phase >= lfo->period) {
        phase_reset = true;
        lfo->phase = 0;
    }

    if (lfo->waveform == 0U) {
        if (phase_reset) {
            lfo->pitch = clamp_i64(-((int64_t)lfo->amplitude *
                                      lfo->period / 2));
        } else {
            lfo->pitch = clamp_i64((int64_t)lfo->pitch + lfo->amplitude);
        }
    } else if (lfo->waveform == 1U) {
        lfo->pitch = lfo->amplitude;
        if (phase_reset) {
            lfo->amplitude = clamp_i64(-(int64_t)lfo->amplitude);
        }
    } else if (lfo->waveform == 2U) {
        if (phase_reset) {
            lfo->amplitude = clamp_i64(-(int64_t)lfo->amplitude);
        }
        lfo->pitch = clamp_i64((int64_t)lfo->pitch + lfo->amplitude);
    }
}

static void refresh_ended(retrofm_mdx_sequencer *sequencer) {
    size_t index;

    sequencer->ended = true;
    for (index = 0U; index < sequencer->mdx->track_count; ++index) {
        if (sequencer->tracks[index].used && !sequencer->tracks[index].ended) {
            sequencer->ended = false;
            break;
        }
    }
}

static retrofm_mdx_result note_off(retrofm_mdx_sequencer *sequencer,
                                   size_t track_index) {
    retrofm_mdx_track_state *track = &sequencer->tracks[track_index];

    if (track->note < 0) {
        return RETROFM_MDX_OK;
    }
    if (track_index < 8U) {
        if (track->skip_note_off) {
            track->skip_note_on = true;
            track->skip_note_off = false;
        } else {
            retrofm_mdx_result result;
            fm_driver_note_off(&sequencer->opm_driver.fm_driver,
                               (int)track_index);
            result = sequencer->failure;
            if (result != RETROFM_MDX_OK) {
                return result;
            }
        }
    } else {
        retrofm_mdx_result result = emit_pcm(sequencer,
                                             RETROFM_MDX_PCM_STOP,
                                             track_index,
                                             UINT8_MAX,
                                             NULL,
                                             0U);
        if (result != RETROFM_MDX_OK) {
            return result;
        }
    }
    track->note = -1;
    return RETROFM_MDX_OK;
}

static retrofm_mdx_result note_on(retrofm_mdx_sequencer *sequencer,
                                  size_t track_index) {
    retrofm_mdx_track_state *track = &sequencer->tracks[track_index];
    const uint8_t *voice;
    retrofm_mdx_result result;

    if (track_index >= 8U) {
        const uint8_t *sample_data = NULL;
        size_t sample_size = 0U;
        retrofm_pdx_result pdx_result;

        if (track_index > 8U && !sequencer->pcm8_enabled) {
            return fail_sequence(sequencer, RETROFM_MDX_PCM8_NOT_ENABLED);
        }
        if (sequencer->pdx == NULL || sequencer->pcm_callback == NULL) {
            return fail_sequence(sequencer, RETROFM_MDX_MISSING_PDX);
        }
        if (track->note < 0 || track->note >= (int32_t)RETROFM_PDX_SAMPLE_COUNT) {
            return fail_sequence(sequencer, RETROFM_MDX_PDX_SAMPLE_ERROR);
        }
        pdx_result = retrofm_pdx_get_sample(sequencer->pdx,
                                            (size_t)track->note,
                                            &sample_data,
                                            &sample_size);
        if (pdx_result == RETROFM_PDX_EMPTY_SAMPLE) {
            return RETROFM_MDX_OK;
        }
        if (pdx_result != RETROFM_PDX_OK) {
            return fail_sequence(sequencer, RETROFM_MDX_PDX_SAMPLE_ERROR);
        }
        return emit_pcm(sequencer,
                        RETROFM_MDX_PCM_PLAY,
                        track_index,
                        (uint8_t)track->note,
                        sample_data,
                        sample_size);
    }
    if (track->voice_number < 0) {
        return RETROFM_MDX_OK;
    }
    voice = sequencer->mdx->voices[(uint8_t)track->voice_number];
    if (voice == NULL) {
        return fail_sequence(sequencer, RETROFM_MDX_MISSING_VOICE);
    }

    result = set_pitch(sequencer, track_index, track->pitch);
    if (result != RETROFM_MDX_OK) return result;
    result = set_total_level(sequencer,
                             track_index,
                             track->opm_volume + sequencer->fade_value,
                             voice);
    if (result != RETROFM_MDX_OK) return result;

    if (track->skip_note_on) {
        track->skip_note_on = false;
        return RETROFM_MDX_OK;
    }
    if (track->hardware_lfo_enabled) {
        fm_driver_set_pms_ams(&sequencer->opm_driver.fm_driver,
                              (int)track_index,
                              track->pms_ams);
        result = sequencer->failure;
        if (result != RETROFM_MDX_OK) return result;
        if (track->hardware_lfo_key_sync) {
            fm_driver_reset_key_sync(&sequencer->opm_driver.fm_driver,
                                     (int)track_index);
            result = sequencer->failure;
            if (result != RETROFM_MDX_OK) return result;
        }
    }

    if (track->pitch_lfo.enabled || track->amplitude_lfo.enabled) {
        if (track->lfo_delay > 0) {
            track->lfo_delay_counter = track->lfo_delay;
        } else {
            if (track->pitch_lfo.enabled) lfo_start(&track->pitch_lfo);
            if (track->amplitude_lfo.enabled) lfo_start(&track->amplitude_lfo);
        }
    }

    fm_driver_note_on(&sequencer->opm_driver.fm_driver,
                      (int)track_index,
                      (uint8_t)(voice[2] & 0x0FU),
                      (uint8_t *)voice);
    return sequencer->failure;
}

static void increment_volume(retrofm_mdx_track_state *track) {
    if (track->volume < 15) {
        ++track->volume;
    } else if (track->volume > 128) {
        --track->volume;
    }
}

static void decrement_volume(retrofm_mdx_track_state *track) {
    if (track->volume > 0 && track->volume < 16) {
        --track->volume;
    } else if (track->volume >= 128 && track->volume < 255) {
        ++track->volume;
    }
}

static retrofm_mdx_result apply_volume(retrofm_mdx_sequencer *sequencer,
                                       size_t track_index) {
    retrofm_mdx_track_state *track = &sequencer->tracks[track_index];

    track->opm_volume = mdx_volume_to_opm(track->volume);
    if (track_index < 8U && track->voice_number >= 0) {
        const uint8_t *voice =
            sequencer->mdx->voices[(uint8_t)track->voice_number];
        if (voice == NULL) {
            return fail_sequence(sequencer, RETROFM_MDX_MISSING_VOICE);
        }
        return set_total_level(sequencer,
                               track_index,
                               track->opm_volume,
                               voice);
    } else if (track_index >= 8U) {
        return emit_pcm(sequencer,
                        RETROFM_MDX_PCM_SET_VOLUME,
                        track_index,
                        UINT8_MAX,
                        NULL,
                        0U);
    }
    return RETROFM_MDX_OK;
}

static retrofm_mdx_result advance_track(retrofm_mdx_sequencer *sequencer,
                                        size_t track_index) {
    retrofm_mdx_track_state *track = &sequencer->tracks[track_index];
    const uint8_t *command;
    uint8_t opcode;
    size_t length;
    retrofm_mdx_result framing_result;
    retrofm_mdx_result result;

    if (track->position >= track->size) {
        return fail_sequence(sequencer, RETROFM_MDX_TRUNCATED_COMMAND);
    }
    command = track->data + track->position;
    length = retrofm_mdx_command_size(command,
                                      track->size - track->position,
                                      &framing_result);
    if (length == 0U) {
        return fail_sequence(sequencer, framing_result);
    }
    opcode = command[0];

    result = note_off(sequencer, track_index);
    if (result != RETROFM_MDX_OK) {
        return result;
    }

    if (opcode <= 0x7FU) {
        track->note = -1;
        track->ticks_remaining = (int32_t)opcode + 1;
        track->position += 1U;
        return RETROFM_MDX_OK;
    }
    if (opcode <= 0xDFU) {
        int64_t pitch_base;

        track->ticks_remaining = (int32_t)command[1] + 1;
        track->key_on_delay_counter = 0U;
        track->position += 2U;
        track->note = opcode & 0x7FU;
        pitch_base = (int64_t)5 + ((int64_t)track->note << 6U) + track->detune;
        track->pitch = clamp_i64(pitch_base * 256);

        if (track->staccato <= 8) {
            track->staccato_counter =
                track->staccato * track->ticks_remaining / 8;
        } else {
            track->staccato_counter =
                track->ticks_remaining - (256 - track->staccato);
            if (track->staccato_counter < 0) {
                track->staccato_counter = 0;
            }
        }

        if (track->key_on_delay != 0U) {
            track->key_on_delay_counter = track->key_on_delay;
            return RETROFM_MDX_OK;
        }
        return note_on(sequencer, track_index);
    }

    switch (opcode) {
        case 0xFFU:
            sequencer->cycles_per_tick =
                ((uint32_t)256U - command[1]) * MDX_CYCLES_PER_TIMER_UNIT;
            track->position += 2U;
            break;

        case 0xFEU:
            result = write_opm(sequencer, command[1], command[2]);
            if (result != RETROFM_MDX_OK) return result;
            track->position += 3U;
            break;

        case 0xFDU:
            if (track_index < 8U) {
                const uint8_t *voice = sequencer->mdx->voices[command[1]];
                if (voice == NULL) {
                    return fail_sequence(sequencer, RETROFM_MDX_MISSING_VOICE);
                }
                track->voice_number = command[1];
                result = load_voice(sequencer,
                                    track_index,
                                    voice,
                                    track->opm_volume,
                                    track->pan);
                if (result != RETROFM_MDX_OK) return result;
            }
            track->position += 2U;
            break;

        case 0xFCU:
            track->pan = command[1];
            if (track_index < 8U && track->voice_number >= 0) {
                const uint8_t *voice =
                    sequencer->mdx->voices[(uint8_t)track->voice_number];
                fm_driver_set_pan(&sequencer->opm_driver.fm_driver,
                                  (int)track_index,
                                  track->pan,
                                  (uint8_t *)voice);
                result = sequencer->failure;
                if (result != RETROFM_MDX_OK) return result;
            } else if (track_index >= 8U) {
                result = emit_pcm(sequencer,
                                  RETROFM_MDX_PCM_SET_PAN,
                                  track_index,
                                  UINT8_MAX,
                                  NULL,
                                  0U);
                if (result != RETROFM_MDX_OK) return result;
            }
            track->position += 2U;
            break;

        case 0xFBU:
            track->volume = command[1];
            result = apply_volume(sequencer, track_index);
            if (result != RETROFM_MDX_OK) return result;
            track->position += 2U;
            break;

        case 0xFAU:
            decrement_volume(track);
            result = apply_volume(sequencer, track_index);
            if (result != RETROFM_MDX_OK) return result;
            track->position += 1U;
            break;

        case 0xF9U:
            increment_volume(track);
            result = apply_volume(sequencer, track_index);
            if (result != RETROFM_MDX_OK) return result;
            track->position += 1U;
            break;

        case 0xF8U:
            track->staccato = command[1];
            track->position += 2U;
            break;

        case 0xF7U:
            if (track_index < 8U) {
                track->skip_note_off = true;
            }
            track->position += 1U;
            break;

        case 0xF6U:
            if (track->repeat_depth >= RETROFM_MDX_REPEAT_DEPTH ||
                command[1] == 0U) {
                return fail_sequence(sequencer, RETROFM_MDX_BAD_REPEAT);
            }
            track->repeats[track->repeat_depth].body_position =
                track->position + 3U;
            track->repeats[track->repeat_depth].remaining = command[1];
            ++track->repeat_depth;
            track->position += 3U;
            break;

        case 0xF5U: {
            retrofm_mdx_repeat_state *repeat;
            int16_t relative;
            int64_t target;

            if (track->repeat_depth == 0U) {
                return fail_sequence(sequencer, RETROFM_MDX_BAD_REPEAT);
            }
            repeat = &track->repeats[track->repeat_depth - 1U];
            relative = signed_be16(command + 1U);
            target = (int64_t)track->position + 3 + relative;
            if (target < 0 || (uint64_t)target >= track->size ||
                (size_t)target != repeat->body_position) {
                return fail_sequence(sequencer, RETROFM_MDX_BAD_REPEAT);
            }
            if (repeat->remaining > 1U) {
                --repeat->remaining;
                track->position = (size_t)target;
            } else {
                --track->repeat_depth;
                track->position += 3U;
            }
            break;
        }

        case 0xF4U: {
            retrofm_mdx_repeat_state *repeat;
            int16_t relative;
            int64_t operand;

            if (track->repeat_depth == 0U) {
                return fail_sequence(sequencer, RETROFM_MDX_BAD_REPEAT);
            }
            repeat = &track->repeats[track->repeat_depth - 1U];
            relative = signed_be16(command + 1U);
            operand = (int64_t)track->position + 3 + relative;
            if (operand < 0 || (uint64_t)operand + 2U > track->size ||
                operand == 0 || track->data[(size_t)operand - 1U] != 0xF5U) {
                return fail_sequence(sequencer, RETROFM_MDX_BAD_REPEAT);
            }
            if (repeat->remaining <= 1U) {
                track->position = (size_t)operand + 2U;
                --track->repeat_depth;
            } else {
                track->position += 3U;
            }
            break;
        }

        case 0xF3U:
            if (track_index < 8U) track->detune = signed_be16(command + 1U);
            track->position += 3U;
            break;

        case 0xF2U:
            if (track_index < 8U) track->portamento = signed_be16(command + 1U);
            track->position += 3U;
            break;

        case 0xF1U:
            if (command[1] == 0U) {
                track->ended = true;
                track->position += 2U;
                refresh_ended(sequencer);
            } else {
                int16_t relative = signed_be16(command + 1U);
                int64_t target = (int64_t)track->position + 3 + relative;
                if (target < 0 || (uint64_t)target >= track->size ||
                    (size_t)target >= track->position) {
                    return fail_sequence(sequencer, RETROFM_MDX_BAD_LOOP);
                }
                ++track->loop_count;
                track->position = (size_t)target;
            }
            break;

        case 0xF0U:
            track->key_on_delay = command[1];
            track->position += 2U;
            break;

        case 0xEFU:
            if (command[1] >= sequencer->mdx->track_count) {
                return fail_sequence(sequencer,
                                     RETROFM_MDX_BAD_COMMAND_ARGUMENT);
            }
            sequencer->tracks[command[1]].waiting = false;
            track->position += 2U;
            break;

        case 0xEEU:
            track->waiting = true;
            track->position += 1U;
            break;

        case 0xEDU:
            if (track_index < 8U) {
                result = write_opm(sequencer,
                                    0x0FU,
                                    (uint8_t)(command[1] & 0x9FU));
                if (result != RETROFM_MDX_OK) return result;
            } else {
                track->adpcm_frequency = command[1];
                result = emit_pcm(sequencer,
                                  RETROFM_MDX_PCM_SET_FREQUENCY,
                                  track_index,
                                  UINT8_MAX,
                                  NULL,
                                  0U);
                if (result != RETROFM_MDX_OK) return result;
            }
            track->position += 2U;
            break;

        case 0xECU:
        case 0xEBU: {
            retrofm_mdx_lfo_state *lfo = opcode == 0xECU ?
                &track->pitch_lfo : &track->amplitude_lfo;
            if (command[1] == 0x80U) {
                lfo->enabled = false;
                track->position += 2U;
            } else if (command[1] == 0x81U) {
                lfo->enabled = true;
                track->position += 2U;
            } else {
                lfo_initialize(lfo,
                               command[1],
                               (uint16_t)(((uint16_t)command[2] << 8U) |
                                          command[3]),
                               signed_be16(command + 4U));
                track->position += 6U;
            }
            break;
        }

        case 0xEAU:
            if (command[1] == 0x80U) {
                track->hardware_lfo_enabled = false;
                track->position += 2U;
            } else if (command[1] == 0x81U) {
                track->hardware_lfo_enabled = true;
                track->position += 2U;
            } else {
                track->hardware_lfo_key_sync =
                    (command[1] & 0x40U) != 0U;
                track->pms_ams = command[5];
                track->hardware_lfo_enabled = true;
                if (track_index < 8U) {
                    result = load_hardware_lfo(sequencer,
                                               command[1], command[2],
                                               command[3], command[4]);
                    if (result != RETROFM_MDX_OK) return result;
                }
                track->position += 6U;
            }
            break;

        case 0xE9U:
            track->lfo_delay = command[1];
            track->position += 2U;
            break;

        case 0xE7U:
            result = retrofm_mdx_sequencer_start_fade(sequencer, command[2]);
            if (result != RETROFM_MDX_OK) return result;
            track->position += 3U;
            break;

        case 0xE8U:
            sequencer->pcm8_enabled = true;
            track->position += length;
            break;

        case 0xE6U:
        case 0xE5U:
        case 0xE4U:
        case 0xE3U:
        case 0xE2U:
        case 0xE1U:
        case 0xE0U:
            if (track_index >= 8U) {
                return fail_sequence(sequencer,
                                     RETROFM_MDX_PCM8_BANK_UNSUPPORTED);
            }
            track->position += length;
            break;

        default:
            return fail_sequence(sequencer, RETROFM_MDX_UNSUPPORTED_COMMAND);
    }
    return RETROFM_MDX_OK;
}

static retrofm_mdx_result tick_track(retrofm_mdx_sequencer *sequencer,
                                     size_t track_index) {
    retrofm_mdx_track_state *track = &sequencer->tracks[track_index];
    size_t command_count = 0U;
    retrofm_mdx_result result;

    if (!track->used || track->ended || track->waiting) {
        return RETROFM_MDX_OK;
    }

    if (track->key_on_delay_counter > 0U) {
        --track->key_on_delay_counter;
        if (track->key_on_delay_counter == 0U &&
            track->staccato_counter > 0) {
            result = note_on(sequencer, track_index);
            if (result != RETROFM_MDX_OK) return result;
        }
    }

    --track->staccato_counter;
    if (track->staccato_counter <= 0 && track->key_on_delay_counter == 0U) {
        result = note_off(sequencer, track_index);
        if (result != RETROFM_MDX_OK) return result;
    }

    --track->ticks_remaining;
    if (track->ticks_remaining == 0) {
        track->portamento = 0;
    }

    if (track_index < 8U) {
        int32_t pitch = track->pitch;
        int32_t attenuation = track->opm_volume + sequencer->fade_value;

        if (track->portamento != 0) {
            track->pitch = clamp_i64((int64_t)track->pitch + track->portamento);
            pitch = track->pitch;
        }
        if (track->lfo_delay_counter > 0) {
            --track->lfo_delay_counter;
            if (track->lfo_delay_counter == 0) {
                if (track->pitch_lfo.enabled) lfo_start(&track->pitch_lfo);
                if (track->amplitude_lfo.enabled) lfo_start(&track->amplitude_lfo);
            }
        }
        if (track->pitch_lfo.enabled && track->lfo_delay_counter == 0) {
            pitch = clamp_i64((int64_t)pitch + track->pitch_lfo.pitch);
            lfo_tick(&track->pitch_lfo);
        }

        result = set_pitch(sequencer, track_index, pitch);
        if (result != RETROFM_MDX_OK) return result;

        if (track->amplitude_lfo.enabled && track->lfo_delay_counter == 0) {
            lfo_tick(&track->amplitude_lfo);
            attenuation = clamp_i64((int64_t)attenuation +
                                    track->amplitude_lfo.pitch);
        }
        if (track->voice_number >= 0) {
            const uint8_t *voice =
                sequencer->mdx->voices[(uint8_t)track->voice_number];
            if (voice == NULL) {
                return fail_sequence(sequencer, RETROFM_MDX_MISSING_VOICE);
            }
            result = set_total_level(sequencer,
                                     track_index,
                                     attenuation,
                                     voice);
            if (result != RETROFM_MDX_OK) return result;
        }
    } else if (sequencer->fade_value > 0) {
        result = emit_pcm(sequencer,
                          RETROFM_MDX_PCM_SET_VOLUME,
                          track_index,
                          UINT8_MAX,
                          NULL,
                          0U);
        if (result != RETROFM_MDX_OK) return result;
    }

    while (track->ticks_remaining <= 0 && !track->ended && !track->waiting) {
        if (command_count++ >= RETROFM_MDX_COMMANDS_PER_TICK) {
            return fail_sequence(sequencer, RETROFM_MDX_ZERO_TIME_LOOP);
        }
        result = advance_track(sequencer, track_index);
        if (result != RETROFM_MDX_OK) {
            return result;
        }
    }
    return RETROFM_MDX_OK;
}

static retrofm_mdx_result initialize_sequencer(
    retrofm_mdx_sequencer *sequencer,
    const retrofm_mdx *mdx,
    retrofm_mdx_event_callback event_callback,
    void *callback_user) {
    size_t index;

    if (sequencer == NULL || mdx == NULL || event_callback == NULL ||
        mdx->whole_file.data == NULL ||
        (mdx->track_count != 9U && mdx->track_count != 16U)) {
        return RETROFM_MDX_BAD_ARGUMENT;
    }

    memset(sequencer, 0, sizeof(*sequencer));
    sequencer->mdx = mdx;
    sequencer->event_callback = event_callback;
    sequencer->callback_user = callback_user;
    sequencer->cycles_per_tick =
        ((uint32_t)256U - MDX_INITIAL_TEMPO) * MDX_CYCLES_PER_TIMER_UNIT;
    sequencer->failure = RETROFM_MDX_OK;

    for (index = 0U; index < mdx->track_count; ++index) {
        retrofm_mdx_track_state *track = &sequencer->tracks[index];
        if (mdx->tracks[index].data == NULL || mdx->tracks[index].size == 0U) {
            memset(sequencer, 0, sizeof(*sequencer));
            return RETROFM_MDX_BAD_ARGUMENT;
        }
        track->data = mdx->tracks[index].data;
        track->size = mdx->tracks[index].size;
        track->used = true;
        track->volume = 8;
        track->opm_volume = mdx_volume_to_opm(track->volume);
        track->staccato = 8;
        track->voice_number = -1;
        track->note = -1;
        track->pan = 3U;
        track->adpcm_frequency = 4U;
    }

    /*
     * A PL core reset is not a substitute for the register state expected by
     * MXDRV/mdxtools.  Install the timestamp adapter first, then execute the
     * pinned driver's complete 264-write OPM initialization sequence.
     */
    sequencer->opm_driver.write = opm_event_callback;
    fm_opm_driver_init(&sequencer->opm_driver);
    return sequencer->failure;
}

retrofm_mdx_result retrofm_mdx_sequencer_init(
    retrofm_mdx_sequencer *sequencer,
    const retrofm_mdx *mdx,
    retrofm_mdx_event_callback event_callback,
    void *callback_user) {
    if (sequencer == NULL || mdx == NULL || event_callback == NULL) {
        return RETROFM_MDX_BAD_ARGUMENT;
    }
    if (mdx->uses_pdx) {
        return RETROFM_MDX_MISSING_PDX;
    }
    return initialize_sequencer(sequencer,
                                mdx,
                                event_callback,
                                callback_user);
}

retrofm_mdx_result retrofm_mdx_sequencer_init_with_pdx(
    retrofm_mdx_sequencer *sequencer,
    const retrofm_mdx *mdx,
    const retrofm_pdx *pdx,
    retrofm_mdx_event_callback event_callback,
    void *callback_user,
    retrofm_mdx_pcm_callback pcm_callback,
    void *pcm_callback_user) {
    retrofm_mdx_result result;

    if (pdx == NULL || pdx->bytes == NULL || pcm_callback == NULL) {
        return RETROFM_MDX_BAD_ARGUMENT;
    }
    result = initialize_sequencer(sequencer,
                                  mdx,
                                  event_callback,
                                  callback_user);
    if (result != RETROFM_MDX_OK) {
        return result;
    }
    sequencer->pdx = pdx;
    sequencer->pcm_callback = pcm_callback;
    sequencer->pcm_callback_user = pcm_callback_user;
    return RETROFM_MDX_OK;
}

retrofm_mdx_result retrofm_mdx_sequencer_start_fade(
    retrofm_mdx_sequencer *sequencer,
    uint8_t rate) {
    if (sequencer == NULL || sequencer->mdx == NULL) {
        return RETROFM_MDX_BAD_ARGUMENT;
    }
    if (sequencer->failure != RETROFM_MDX_OK || sequencer->ended ||
        sequencer->fade_rate != 0) {
        return RETROFM_MDX_BAD_STATE;
    }
    sequencer->fade_rate = (int32_t)rate / 2 + 1;
    sequencer->fade_counter = sequencer->fade_rate;
    sequencer->fade_value = 0;
    return RETROFM_MDX_OK;
}

retrofm_mdx_result retrofm_mdx_sequencer_tick(
    retrofm_mdx_sequencer *sequencer) {
    size_t track_index;
    retrofm_mdx_result result;

    if (sequencer == NULL || sequencer->mdx == NULL ||
        sequencer->event_callback == NULL) {
        return RETROFM_MDX_BAD_ARGUMENT;
    }
    if (sequencer->failure != RETROFM_MDX_OK) {
        return sequencer->failure;
    }
    if (sequencer->ended) {
        return RETROFM_MDX_END;
    }
    if (UINT64_MAX - sequencer->current_cycles < sequencer->cycles_per_tick) {
        return fail_sequence(sequencer, RETROFM_MDX_TIME_OVERFLOW);
    }
    sequencer->current_cycles += sequencer->cycles_per_tick;
    ++sequencer->tick_count;

    if (sequencer->fade_rate > 0) {
        --sequencer->fade_counter;
        if (sequencer->fade_counter == 0) {
            sequencer->fade_counter = sequencer->fade_rate;
            ++sequencer->fade_value;
            if (sequencer->fade_value > 72) {
                for (track_index = 0U; track_index < 8U; ++track_index) {
                    fm_driver_note_off(&sequencer->opm_driver.fm_driver,
                                       (int)track_index);
                    result = sequencer->failure;
                    if (result != RETROFM_MDX_OK) return result;
                }
                for (track_index = 8U;
                     track_index < sequencer->mdx->track_count;
                     ++track_index) {
                    if (sequencer->tracks[track_index].note >= 0) {
                        result = note_off(sequencer, track_index);
                        if (result != RETROFM_MDX_OK) return result;
                    }
                }
                sequencer->ended = true;
            }
        }
    }

    if (!sequencer->ended) {
        for (track_index = 0U;
             track_index < sequencer->mdx->track_count;
             ++track_index) {
            result = tick_track(sequencer, track_index);
            if (result != RETROFM_MDX_OK) {
                return result;
            }
        }
    }

    if (sequencer->ended && !sequencer->end_event_emitted) {
        result = emit_event(sequencer, RETROFM_OP_END, 0U, 0U);
        if (result != RETROFM_MDX_OK) {
            return result;
        }
        sequencer->end_event_emitted = true;
    }
    return RETROFM_MDX_OK;
}

bool retrofm_mdx_sequencer_ended(const retrofm_mdx_sequencer *sequencer) {
    return sequencer != NULL && sequencer->ended;
}

uint64_t retrofm_mdx_sequencer_cycles(const retrofm_mdx_sequencer *sequencer) {
    return sequencer == NULL ? UINT64_C(0) : sequencer->current_cycles;
}
