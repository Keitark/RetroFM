/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_mdx_sequence.h"
#include "retrofm_pcm.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition)                                                     \
    do {                                                                     \
        if (!(condition)) {                                                  \
            fprintf(stderr, "CHECK failed at %s:%d: %s\n",                 \
                    __FILE__, __LINE__, #condition);                         \
            return 1;                                                        \
        }                                                                    \
    } while (0)

enum {
    PREFIX_SIZE = 8,
    TABLE_SIZE = 20,
    VOICE_SIZE = 27,
    TRACK_COUNT = 9,
    MAX_FILE_SIZE = 768,
    MAX_TRACE_EVENTS = 1024,
    MAX_PCM_COMMANDS = 32
};

typedef struct trace_log {
    retrofm_event events[MAX_TRACE_EVENTS];
    size_t count;
    bool reject;
} trace_log;

typedef struct pcm_trace_log {
    retrofm_mdx_pcm_command commands[MAX_PCM_COMMANDS];
    retrofm_pcm_mixer mixer;
    size_t count;
    bool reject;
} pcm_trace_log;

static void put_be16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)(value >> 8U);
    bytes[1] = (uint8_t)value;
}

static void put_be32(uint8_t *bytes, uint32_t value) {
    bytes[0] = (uint8_t)(value >> 24U);
    bytes[1] = (uint8_t)(value >> 16U);
    bytes[2] = (uint8_t)(value >> 8U);
    bytes[3] = (uint8_t)value;
}

static void make_voice(uint8_t voice[VOICE_SIZE]) {
    size_t index;

    memset(voice, 0, VOICE_SIZE);
    voice[0] = 0U;
    voice[1] = 0x07U;
    voice[2] = 0x0FU;
    for (index = 0U; index < 4U; ++index) {
        voice[3U + index] = (uint8_t)(0x11U * (index + 1U));
        voice[7U + index] = (uint8_t)(0x10U + index * 0x08U);
        voice[11U + index] = (uint8_t)(0x1FU - index);
        voice[15U + index] = (uint8_t)(0x20U + index);
        voice[19U + index] = (uint8_t)(0x30U + index);
        voice[23U + index] = (uint8_t)(0x40U + index);
    }
}

static size_t make_mdx(uint8_t *output,
                       const uint8_t *track_zero,
                       size_t track_zero_size) {
    static const uint8_t prefix[PREFIX_SIZE] = {
        'T', 'r', 'a', 'c', 0x0DU, 0x0AU, 0x1AU, 0x00U
    };
    static const uint8_t end_track[] = { 0xF1U, 0x00U };
    uint8_t voice[VOICE_SIZE];
    size_t relative = TABLE_SIZE;
    size_t voice_relative;
    size_t absolute;
    size_t track_index;

    memset(output, 0, MAX_FILE_SIZE);
    memcpy(output, prefix, sizeof(prefix));
    make_voice(voice);

    put_be16(output + PREFIX_SIZE + 2U, (uint16_t)relative);
    relative += track_zero_size;
    for (track_index = 1U; track_index < TRACK_COUNT; ++track_index) {
        put_be16(output + PREFIX_SIZE + 2U * (track_index + 1U),
                 (uint16_t)relative);
        relative += sizeof(end_track);
    }
    voice_relative = relative;
    put_be16(output + PREFIX_SIZE, (uint16_t)voice_relative);

    absolute = PREFIX_SIZE + TABLE_SIZE;
    memcpy(output + absolute, track_zero, track_zero_size);
    absolute += track_zero_size;
    for (track_index = 1U; track_index < TRACK_COUNT; ++track_index) {
        memcpy(output + absolute, end_track, sizeof(end_track));
        absolute += sizeof(end_track);
    }
    memcpy(output + absolute, voice, sizeof(voice));
    absolute += sizeof(voice);
    return absolute;
}

static size_t make_pcm_mdx(uint8_t *output,
                           size_t track_count,
                           const uint8_t *track_eight,
                           size_t track_eight_size,
                           const uint8_t *track_nine,
                           size_t track_nine_size) {
    static const uint8_t prefix[] = {
        'P', 'C', 'M', 0x0DU, 0x0AU, 0x1AU,
        'T', 'R', 'A', 'C', 'E', '.', 'P', 'D', 'X', 0x00U
    };
    static const uint8_t end_track[] = { 0xF1U, 0x00U };
    uint8_t voice[VOICE_SIZE];
    const size_t table_size = 2U * (track_count + 1U);
    size_t relative = table_size;
    size_t absolute;
    size_t track_index;

    memset(output, 0, MAX_FILE_SIZE);
    memcpy(output, prefix, sizeof(prefix));
    make_voice(voice);

    for (track_index = 0U; track_index < track_count; ++track_index) {
        size_t track_size = sizeof(end_track);
        if (track_index == 8U) track_size = track_eight_size;
        if (track_index == 9U) track_size = track_nine_size;
        put_be16(output + sizeof(prefix) + 2U * (track_index + 1U),
                 (uint16_t)relative);
        relative += track_size;
    }
    put_be16(output + sizeof(prefix), (uint16_t)relative);

    absolute = sizeof(prefix) + table_size;
    for (track_index = 0U; track_index < track_count; ++track_index) {
        const uint8_t *track = end_track;
        size_t track_size = sizeof(end_track);
        if (track_index == 8U) {
            track = track_eight;
            track_size = track_eight_size;
        } else if (track_index == 9U) {
            track = track_nine;
            track_size = track_nine_size;
        }
        memcpy(output + absolute, track, track_size);
        absolute += track_size;
    }
    memcpy(output + absolute, voice, sizeof(voice));
    absolute += sizeof(voice);
    return absolute;
}

static size_t make_pdx(uint8_t *output) {
    static const uint8_t sample[] = { 0x10U, 0x32U, 0x54U, 0x76U };

    memset(output, 0, RETROFM_PDX_TABLE_BYTES + sizeof(sample));
    put_be32(output, RETROFM_PDX_TABLE_BYTES);
    put_be32(output + 4U, (uint32_t)sizeof(sample));
    memcpy(output + RETROFM_PDX_TABLE_BYTES, sample, sizeof(sample));
    return RETROFM_PDX_TABLE_BYTES + sizeof(sample);
}

static bool collect_event(void *user, const retrofm_event *event) {
    trace_log *trace = (trace_log *)user;

    if (trace->reject || trace->count >= MAX_TRACE_EVENTS) {
        return false;
    }
    trace->events[trace->count++] = *event;
    return true;
}

static bool collect_pcm(void *user,
                        const retrofm_mdx_pcm_command *command) {
    pcm_trace_log *trace = (pcm_trace_log *)user;
    retrofm_pcm_result result;

    if (trace->reject || trace->count >= MAX_PCM_COMMANDS) {
        return false;
    }
    trace->commands[trace->count++] = *command;
    switch ((retrofm_mdx_pcm_opcode)command->opcode) {
        case RETROFM_MDX_PCM_PLAY:
            result = retrofm_pcm_play(&trace->mixer,
                                      command->channel,
                                      command->sample_data,
                                      command->sample_size,
                                      command->frequency,
                                      command->volume,
                                      command->pan);
            break;
        case RETROFM_MDX_PCM_STOP:
            result = retrofm_pcm_stop(&trace->mixer, command->channel);
            break;
        case RETROFM_MDX_PCM_SET_FREQUENCY:
            result = retrofm_pcm_set_frequency(&trace->mixer,
                                               command->channel,
                                               command->frequency);
            break;
        case RETROFM_MDX_PCM_SET_VOLUME:
            result = retrofm_pcm_set_volume(&trace->mixer,
                                            command->channel,
                                            command->volume);
            break;
        case RETROFM_MDX_PCM_SET_PAN:
            result = retrofm_pcm_set_pan(&trace->mixer,
                                         command->channel,
                                         command->pan);
            break;
        default:
            return false;
    }
    return result == RETROFM_PCM_OK;
}

static uint64_t trace_hash(const trace_log *trace) {
    uint64_t hash = UINT64_C(14695981039346656037);
    size_t event_index;

    for (event_index = 0U; event_index < trace->count; ++event_index) {
        uint64_t packed = retrofm_event_pack(&trace->events[event_index]);
        unsigned byte_index;

        for (byte_index = 0U; byte_index < 8U; ++byte_index) {
            hash ^= (packed >> (byte_index * 8U)) & UINT64_C(0xFF);
            hash *= UINT64_C(1099511628211);
        }
    }
    return hash;
}

static bool trace_contains(const trace_log *trace,
                           uint8_t reg,
                           uint8_t data) {
    size_t index;

    for (index = 0U; index < trace->count; ++index) {
        if (trace->events[index].opcode == RETROFM_OP_YM2151 &&
            trace->events[index].reg == reg &&
            trace->events[index].data == data) {
            return true;
        }
    }
    return false;
}

static size_t trace_count_register(const trace_log *trace,
                                   uint8_t reg,
                                   uint8_t data) {
    size_t count = 0U;
    size_t index;

    for (index = 0U; index < trace->count; ++index) {
        if (trace->events[index].opcode == RETROFM_OP_YM2151 &&
            trace->events[index].reg == reg &&
            trace->events[index].data == data) {
            ++count;
        }
    }
    return count;
}

static int run_to_end(retrofm_mdx_sequencer *sequencer, size_t maximum_ticks) {
    size_t tick;

    for (tick = 0U; tick < maximum_ticks; ++tick) {
        retrofm_mdx_result result = retrofm_mdx_sequencer_tick(sequencer);
        CHECK(result == RETROFM_MDX_OK);
        if (retrofm_mdx_sequencer_ended(sequencer)) {
            CHECK(retrofm_mdx_sequencer_tick(sequencer) == RETROFM_MDX_END);
            return 0;
        }
    }
    CHECK(false);
    return 1;
}

static int test_deterministic_trace(void) {
    static const uint8_t track_zero[] = {
        0xFFU, 0xC0U,             /* tempo: next tick is 1,638,400 cycles */
        0xFDU, 0x00U,             /* voice zero */
        0xFCU, 0x01U,             /* left pan */
        0xFEU, 0x12U, 0x34U,      /* direct OPM write */
        0x80U, 0x00U,             /* shortest note */
        0xF1U, 0x00U
    };
    uint8_t bytes[MAX_FILE_SIZE];
    retrofm_mdx mdx;
    retrofm_mdx_sequencer sequencer;
    trace_log trace;
    uint64_t hash;
    size_t file_size;
    size_t index;
    size_t second_tick_index = SIZE_MAX;

    memset(&trace, 0, sizeof(trace));
    file_size = make_mdx(bytes, track_zero, sizeof(track_zero));
    CHECK(retrofm_mdx_open(&mdx, bytes, file_size) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_init(&sequencer, &mdx,
                                     collect_event, &trace) == RETROFM_MDX_OK);
    CHECK(run_to_end(&sequencer, 4U) == 0);

    CHECK(trace.count == 322U);
    CHECK(trace.events[0].delta_cycles == 0U);
    CHECK(trace.events[0].opcode == RETROFM_OP_YM2151);
    CHECK(trace.events[0].reg == 0x00U && trace.events[0].data == 0U);
    CHECK(trace.events[95].reg == 0x5FU && trace.events[95].data == 0U);
    CHECK(trace.events[96].reg == 0x60U && trace.events[96].data == 0x7FU);
    CHECK(trace.events[127].reg == 0x7FU && trace.events[127].data == 0x7FU);
    CHECK(trace.events[128].reg == 0x80U && trace.events[128].data == 0U);
    CHECK(trace.events[223].reg == 0xDFU && trace.events[223].data == 0U);
    CHECK(trace.events[224].reg == 0xE0U && trace.events[224].data == 0x0FU);
    CHECK(trace.events[255].reg == 0xFFU && trace.events[255].data == 0x0FU);
    CHECK(trace.events[263].reg == 0x08U && trace.events[263].data == 0x07U);
    CHECK(trace.events[264].delta_cycles == UINT32_C(1024000));
    CHECK(trace.events[264].reg == 0x28U && trace.events[264].data == 0U);
    CHECK(trace_contains(&trace, 0x20U, 0x47U));
    CHECK(trace_contains(&trace, 0x12U, 0x34U));
    CHECK(trace_contains(&trace, 0x08U, 0x78U));

    for (index = 265U; index < trace.count; ++index) {
        if (trace.events[index].delta_cycles != 0U) {
            second_tick_index = index;
            break;
        }
    }
    CHECK(second_tick_index == 314U);
    CHECK(trace.events[second_tick_index].delta_cycles == UINT32_C(1638400));
    CHECK(trace.events[second_tick_index].reg == 0x08U);
    CHECK(trace.events[second_tick_index].data == 0x00U);
    CHECK(trace.events[trace.count - 1U].opcode == RETROFM_OP_END);
    CHECK(trace.events[trace.count - 1U].delta_cycles == 0U);

    hash = trace_hash(&trace);
    CHECK(hash == UINT64_C(0xF816D1900AE88CEA));
    return 0;
}

static int test_modulation_noise_and_key_delay(void) {
    static const uint8_t track_zero[] = {
        0xFDU, 0x00U,
        0xF3U, 0x00U, 0x04U,                    /* detune */
        0xF2U, 0x01U, 0x00U,                    /* portamento */
        0xEAU, 0x40U, 0x20U, 0x81U, 0x05U, 0x12U,
        0xECU, 0x02U, 0x00U, 0x04U, 0x00U, 0x01U,
        0xEBU, 0x01U, 0x00U, 0x04U, 0x00U, 0x01U,
        0xE9U, 0x01U,
        0xEDU, 0x9FU,                            /* noise enable + freq 31 */
        0xF0U, 0x01U,                            /* one-tick key-on delay */
        0x80U, 0x02U,
        0xEDU, 0x00U,                            /* noise disable */
        0xF1U, 0x00U
    };
    uint8_t bytes[MAX_FILE_SIZE];
    retrofm_mdx mdx;
    retrofm_mdx_sequencer sequencer;
    trace_log trace;
    size_t file_size;

    memset(&trace, 0, sizeof(trace));
    file_size = make_mdx(bytes, track_zero, sizeof(track_zero));
    CHECK(retrofm_mdx_open(&mdx, bytes, file_size) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_init(&sequencer, &mdx,
                                     collect_event, &trace) == RETROFM_MDX_OK);
    CHECK(run_to_end(&sequencer, 8U) == 0);

    CHECK(trace_contains(&trace, 0x0FU, 0x9FU));
    CHECK(trace_contains(&trace, 0x0FU, 0x00U));
    CHECK(trace_contains(&trace, 0x1BU, 0x00U));
    CHECK(trace_contains(&trace, 0x18U, 0x20U));
    CHECK(trace_contains(&trace, 0x19U, 0x81U));
    CHECK(trace_contains(&trace, 0x19U, 0x05U));
    CHECK(trace_contains(&trace, 0x38U, 0x12U));
    CHECK(trace_contains(&trace, 0x01U, 0x02U));
    CHECK(trace_contains(&trace, 0x01U, 0x00U));
    CHECK(trace_count_register(&trace, 0x08U, 0x78U) == 1U);
    CHECK(trace_contains(&trace, 0x30U, 0x24U));
    CHECK(trace_contains(&trace, 0x30U, 0x28U));
    return 0;
}

static int test_loop_and_zero_time_guard(void) {
    static const uint8_t looped[] = {
        0xFDU, 0x00U,
        0x80U, 0x00U,
        0xF1U, 0xFFU, 0xFBU       /* after + (-5) = note */
    };
    static const uint8_t zero_time_loop[] = {
        0xF1U, 0xFFU, 0xFDU       /* after + (-3) = command itself */
    };
    uint8_t bytes[MAX_FILE_SIZE];
    retrofm_mdx mdx;
    retrofm_mdx_sequencer sequencer;
    trace_log trace;
    size_t file_size;
    retrofm_mdx_result open_result;

    memset(&trace, 0, sizeof(trace));
    file_size = make_mdx(bytes, looped, sizeof(looped));
    CHECK(retrofm_mdx_open(&mdx, bytes, file_size) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_init(&sequencer, &mdx,
                                     collect_event, &trace) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_tick(&sequencer) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_tick(&sequencer) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_tick(&sequencer) == RETROFM_MDX_OK);
    CHECK(!retrofm_mdx_sequencer_ended(&sequencer));
    CHECK(trace_count_register(&trace, 0x08U, 0x78U) == 3U);

    memset(&trace, 0, sizeof(trace));
    file_size = make_mdx(bytes, zero_time_loop, sizeof(zero_time_loop));
    /* The hardened front end rejects a self-loop before the sequencer can
     * execute it. This is the preferred zero-progress-loop behavior. */
    open_result = retrofm_mdx_open(&mdx, bytes, file_size);
    if (open_result != RETROFM_MDX_BAD_LOOP) {
        fprintf(stderr, "zero-time loop open result: %s (%d)\n",
                retrofm_mdx_result_string(open_result), (int)open_result);
    }
    CHECK(open_result == RETROFM_MDX_BAD_LOOP);
    return 0;
}

static int test_repeat_runtime(void) {
    static const uint8_t repeated[] = {
        0xFDU, 0x00U,
        0xF6U, 0x02U, 0x00U,
        0x80U, 0x00U,
        0xF5U, 0xFFU, 0xFBU,       /* after + (-5) = repeated note */
        0xF1U, 0x00U
    };
    uint8_t bytes[MAX_FILE_SIZE];
    retrofm_mdx mdx;
    retrofm_mdx_sequencer sequencer;
    trace_log trace;
    size_t file_size;

    memset(&trace, 0, sizeof(trace));
    file_size = make_mdx(bytes, repeated, sizeof(repeated));
    CHECK(retrofm_mdx_open(&mdx, bytes, file_size) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_init(&sequencer, &mdx,
                                     collect_event, &trace) == RETROFM_MDX_OK);
    CHECK(run_to_end(&sequencer, 5U) == 0);
    CHECK(trace_count_register(&trace, 0x08U, 0x78U) == 2U);
    return 0;
}

static int test_callback_rejection(void) {
    static const uint8_t end_track[] = { 0xF1U, 0x00U };
    uint8_t bytes[MAX_FILE_SIZE];
    retrofm_mdx mdx;
    retrofm_mdx_sequencer sequencer;
    trace_log trace;
    size_t file_size;

    memset(&trace, 0, sizeof(trace));
    trace.reject = true;
    file_size = make_mdx(bytes, end_track, sizeof(end_track));
    CHECK(retrofm_mdx_open(&mdx, bytes, file_size) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_init(&sequencer, &mdx,
                                     collect_event, &trace) ==
          RETROFM_MDX_CALLBACK_REJECTED);
    CHECK(retrofm_mdx_sequencer_tick(&sequencer) ==
          RETROFM_MDX_CALLBACK_REJECTED);
    return 0;
}

static int test_pdx_pcm_trace(void) {
    static const uint8_t pcm_track[] = {
        0xE8U,                         /* PCM8 enable */
        0xFCU, 0x01U,                  /* left */
        0xEDU, 0x03U,                  /* 10416.67 Hz selector */
        0xFBU, 0x0FU,                  /* maximum MDX volume */
        0x80U, 0x01U,                  /* PDX sample zero, two ticks */
        0xF1U, 0x00U
    };
    uint8_t mdx_bytes[MAX_FILE_SIZE];
    uint8_t pdx_bytes[RETROFM_PDX_TABLE_BYTES + 4U];
    retrofm_mdx mdx;
    retrofm_pdx pdx;
    retrofm_mdx_sequencer sequencer;
    trace_log fm_trace;
    pcm_trace_log pcm_trace;
    size_t mdx_size;
    size_t pdx_size;
    int16_t left;
    int16_t right;

    memset(&fm_trace, 0, sizeof(fm_trace));
    memset(&pcm_trace, 0, sizeof(pcm_trace));
    retrofm_pcm_init(&pcm_trace.mixer);
    mdx_size = make_pcm_mdx(mdx_bytes, 9U,
                            pcm_track, sizeof(pcm_track), NULL, 0U);
    pdx_size = make_pdx(pdx_bytes);
    CHECK(retrofm_mdx_open(&mdx, mdx_bytes, mdx_size) == RETROFM_MDX_OK);
    CHECK(mdx.uses_pdx);
    CHECK(retrofm_pdx_open(&pdx, pdx_bytes, pdx_size) == RETROFM_PDX_OK);
    CHECK(retrofm_mdx_sequencer_init(&sequencer, &mdx,
                                     collect_event, &fm_trace) ==
          RETROFM_MDX_MISSING_PDX);
    CHECK(retrofm_mdx_sequencer_init_with_pdx(
              &sequencer, &mdx, &pdx,
              collect_event, &fm_trace, collect_pcm, &pcm_trace) ==
          RETROFM_MDX_OK);

    CHECK(retrofm_mdx_sequencer_tick(&sequencer) == RETROFM_MDX_OK);
    CHECK(pcm_trace.count == 4U);
    CHECK(pcm_trace.commands[0].opcode == RETROFM_MDX_PCM_SET_PAN);
    CHECK(pcm_trace.commands[0].channel == 0U);
    CHECK(pcm_trace.commands[0].pan == 1U);
    CHECK(pcm_trace.commands[0].timestamp_cycles == UINT64_C(1024000));
    CHECK(pcm_trace.commands[1].opcode == RETROFM_MDX_PCM_SET_FREQUENCY);
    CHECK(pcm_trace.commands[1].frequency == 3U);
    CHECK(pcm_trace.commands[2].opcode == RETROFM_MDX_PCM_SET_VOLUME);
    CHECK(pcm_trace.commands[2].volume == 0x0FU);
    CHECK(pcm_trace.commands[3].opcode == RETROFM_MDX_PCM_PLAY);
    CHECK(pcm_trace.commands[3].sample_index == 0U);
    CHECK(pcm_trace.commands[3].sample_data ==
          pdx_bytes + RETROFM_PDX_TABLE_BYTES);
    CHECK(pcm_trace.commands[3].sample_size == 4U);
    CHECK(pcm_trace.commands[3].frequency == 3U);
    CHECK(pcm_trace.commands[3].volume == 0x0FU);
    CHECK(pcm_trace.commands[3].pan == 1U);
    CHECK(retrofm_pcm_active(&pcm_trace.mixer));
    CHECK(retrofm_pcm_next_frame(&pcm_trace.mixer, &left, &right) ==
          RETROFM_PCM_OK);
    CHECK(left != 0);
    CHECK(right == 0);

    CHECK(retrofm_mdx_sequencer_tick(&sequencer) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_tick(&sequencer) == RETROFM_MDX_OK);
    CHECK(pcm_trace.count == 5U);
    CHECK(pcm_trace.commands[4].opcode == RETROFM_MDX_PCM_STOP);
    CHECK(pcm_trace.commands[4].channel == 0U);
    CHECK(pcm_trace.commands[4].timestamp_cycles == UINT64_C(3072000));
    CHECK(!retrofm_pcm_active(&pcm_trace.mixer));
    return 0;
}

static int test_pcm8_gate_and_bank_rejection(void) {
    static const uint8_t track_eight_without_enable[] = {
        0x00U, 0xF1U, 0x00U
    };
    static const uint8_t track_nine[] = {
        0x80U, 0x00U, 0xF1U, 0x00U
    };
    static const uint8_t unsupported_bank[] = {
        0xE0U, 0xF1U, 0x00U
    };
    uint8_t mdx_bytes[MAX_FILE_SIZE];
    uint8_t pdx_bytes[RETROFM_PDX_TABLE_BYTES + 4U];
    retrofm_mdx mdx;
    retrofm_pdx pdx;
    retrofm_mdx_sequencer sequencer;
    trace_log fm_trace;
    pcm_trace_log pcm_trace;
    size_t mdx_size;
    size_t pdx_size = make_pdx(pdx_bytes);

    CHECK(retrofm_pdx_open(&pdx, pdx_bytes, pdx_size) == RETROFM_PDX_OK);
    memset(&fm_trace, 0, sizeof(fm_trace));
    memset(&pcm_trace, 0, sizeof(pcm_trace));
    retrofm_pcm_init(&pcm_trace.mixer);

    mdx_size = make_pcm_mdx(mdx_bytes, 16U,
                            track_eight_without_enable,
                            sizeof(track_eight_without_enable),
                            track_nine, sizeof(track_nine));
    CHECK(retrofm_mdx_open(&mdx, mdx_bytes, mdx_size) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_init_with_pdx(
              &sequencer, &mdx, &pdx,
              collect_event, &fm_trace, collect_pcm, &pcm_trace) ==
          RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_tick(&sequencer) ==
          RETROFM_MDX_PCM8_NOT_ENABLED);

    memset(&fm_trace, 0, sizeof(fm_trace));
    memset(&pcm_trace, 0, sizeof(pcm_trace));
    mdx_size = make_pcm_mdx(mdx_bytes, 9U,
                            unsupported_bank, sizeof(unsupported_bank),
                            NULL, 0U);
    CHECK(retrofm_mdx_open(&mdx, mdx_bytes, mdx_size) == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_init_with_pdx(
              &sequencer, &mdx, &pdx,
              collect_event, &fm_trace, collect_pcm, &pcm_trace) ==
          RETROFM_MDX_OK);
    CHECK(retrofm_mdx_sequencer_tick(&sequencer) ==
          RETROFM_MDX_PCM8_BANK_UNSUPPORTED);
    return 0;
}

int main(void) {
    CHECK(test_deterministic_trace() == 0);
    CHECK(test_modulation_noise_and_key_delay() == 0);
    CHECK(test_loop_and_zero_time_guard() == 0);
    CHECK(test_repeat_runtime() == 0);
    CHECK(test_callback_rejection() == 0);
    CHECK(test_pdx_pcm_trace() == 0);
    CHECK(test_pcm8_gate_and_bank_rejection() == 0);
    puts("retrofm MDX sequencing trace tests passed");
    return 0;
}
