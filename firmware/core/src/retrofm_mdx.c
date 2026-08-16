// SPDX-License-Identifier: GPL-3.0-or-later
// Bounds-safe MDX front end for mdxtools 606e3a7009aa1a9dfa6bee8bc875dbd5483714e9.

#include "retrofm_mdx.h"

#include <string.h>

typedef struct retrofm_mdx_chunk {
    size_t start;
    size_t end;
} retrofm_mdx_chunk;

static uint16_t be16(const uint8_t *data) {
    return (uint16_t)(((uint16_t)data[0] << 8U) | data[1]);
}

static int16_t signed_be16(const uint8_t *data) {
    return (int16_t)be16(data);
}

static bool range_ok(size_t offset, size_t amount, size_t total) {
    return offset <= total && amount <= total - offset;
}

size_t retrofm_mdx_command_size(const uint8_t *track,
                                size_t remaining,
                                retrofm_mdx_result *result) {
    uint8_t command;
    size_t size;

    if (result != NULL) *result = RETROFM_MDX_OK;
    if (track == NULL || remaining == 0U) {
        if (result != NULL) *result = RETROFM_MDX_TRUNCATED_COMMAND;
        return 0U;
    }

    command = track[0];
    if (command <= 0x7FU) {
        size = 1U;
    } else if (command <= 0xDFU) {
        size = 2U;
    } else if (command == 0xEAU || command == 0xEBU || command == 0xECU) {
        if (remaining < 2U) {
            if (result != NULL) *result = RETROFM_MDX_TRUNCATED_COMMAND;
            return 0U;
        }
        size = (track[1] == 0x80U || track[1] == 0x81U) ? 2U : 6U;
    } else {
        switch (command) {
            case 0xFEU: case 0xF6U: case 0xF5U: case 0xF4U:
            case 0xF3U: case 0xF2U: case 0xE7U:
                size = 3U;
                break;
            case 0xFFU: case 0xFDU: case 0xFCU: case 0xFBU:
            case 0xF8U: case 0xF0U: case 0xEFU: case 0xEDU: case 0xE9U:
                size = 2U;
                break;
            case 0xFAU: case 0xF9U: case 0xF7U: case 0xEEU: case 0xE8U:
                size = 1U;
                break;
            case 0xF1U:
                if (remaining < 2U) {
                    if (result != NULL) *result = RETROFM_MDX_TRUNCATED_COMMAND;
                    return 0U;
                }
                size = track[1] == 0U ? 2U : 3U;
                break;
            default:
                /* mdxtools treats the reserved/informal E0-E6 opcodes as
                 * one-byte commands and reports them through its unknown
                 * command callback. Preserve that safe framing here. */
                if (command >= 0xE0U && command <= 0xE6U) {
                    size = 1U;
                    break;
                }
                if (result != NULL) *result = RETROFM_MDX_UNSUPPORTED_COMMAND;
                return 0U;
        }
    }

    if (size > remaining) {
        if (result != NULL) *result = RETROFM_MDX_TRUNCATED_COMMAND;
        return 0U;
    }
    return size;
}

static bool is_command_boundary(const retrofm_mdx_span *track, size_t target) {
    size_t position = 0U;
    if (target >= track->size) return false;

    while (position < track->size) {
        retrofm_mdx_result result;
        size_t length;
        if (position == target) return true;
        length = retrofm_mdx_command_size(track->data + position,
                                          track->size - position, &result);
        if (length == 0U) return false;
        position += length;
    }
    return false;
}

static retrofm_mdx_result validate_track(retrofm_mdx *mdx, size_t track_index) {
    const retrofm_mdx_span *track = &mdx->tracks[track_index];
    size_t position = 0U;
    size_t repeat_stack[16];
    size_t repeat_depth = 0U;
    bool ended = false;

    while (position < track->size) {
        const uint8_t *command = track->data + position;
        retrofm_mdx_result result;
        size_t length = retrofm_mdx_command_size(command,
                                                  track->size - position,
                                                  &result);
        size_t after;
        if (length == 0U) return result;
        after = position + length;

        if (command[0] >= 0x80U && command[0] <= 0xDFU && track_index >= 8U) {
            mdx->uses_pdx = true;
        }

        switch (command[0]) {
            case 0xFDU:
                if (track_index < 8U && mdx->voices[command[1]] == NULL) {
                    return RETROFM_MDX_MISSING_VOICE;
                }
                break;
            case 0xFCU:
                if (command[1] > 3U) return RETROFM_MDX_BAD_COMMAND_ARGUMENT;
                break;
            case 0xEFU:
                if (command[1] >= mdx->track_count) {
                    return RETROFM_MDX_BAD_COMMAND_ARGUMENT;
                }
                break;
            case 0xEDU:
                if (track_index >= 8U && command[1] > 4U) {
                    return RETROFM_MDX_BAD_COMMAND_ARGUMENT;
                }
                break;
            case 0xEBU:
            case 0xECU:
                if (length == 6U && command[1] > 2U) {
                    return RETROFM_MDX_BAD_COMMAND_ARGUMENT;
                }
                break;
            case 0xE7U:
                if (command[1] != 1U) return RETROFM_MDX_BAD_COMMAND_ARGUMENT;
                break;
            case 0xF6U:
                if (repeat_depth >= sizeof(repeat_stack) / sizeof(repeat_stack[0]) ||
                    command[1] == 0U) {
                    return RETROFM_MDX_BAD_REPEAT;
                }
                repeat_stack[repeat_depth++] = position;
                break;
            case 0xF5U: {
                int16_t relative = signed_be16(command + 1U);
                int64_t target = (int64_t)after + relative;
                if (repeat_depth == 0U || target < 0 ||
                    (uint64_t)target >= track->size ||
                    !is_command_boundary(track, (size_t)target) ||
                    (size_t)target != repeat_stack[repeat_depth - 1U] + 3U ||
                    target - 1 != (int64_t)repeat_stack[repeat_depth - 1U] + 2) {
                    return RETROFM_MDX_BAD_REPEAT;
                }
                --repeat_depth;
                break;
            }
            case 0xF4U: {
                int16_t relative = signed_be16(command + 1U);
                int64_t operand = (int64_t)after + relative;
                int16_t start_relative;
                int64_t counter;
                if (repeat_depth == 0U || operand < 1 ||
                    !range_ok((size_t)operand, 2U, track->size) ||
                    track->data[(size_t)operand - 1U] != 0xF5U) {
                    return RETROFM_MDX_BAD_REPEAT;
                }
                start_relative = signed_be16(track->data + (size_t)operand);
                counter = operand + start_relative + 1;
                if (counter < 0 || (uint64_t)counter >= track->size ||
                    (size_t)counter != repeat_stack[repeat_depth - 1U] + 2U) {
                    return RETROFM_MDX_BAD_REPEAT;
                }
                break;
            }
            case 0xF1U:
                if (command[1] == 0U) {
                    if (repeat_depth != 0U) return RETROFM_MDX_BAD_REPEAT;
                    ended = true;
                } else {
                    int16_t relative = signed_be16(command + 1U);
                    int64_t target = (int64_t)after + relative;
                    if (target < 0 || (uint64_t)target >= track->size ||
                        (size_t)target >= position ||
                        !is_command_boundary(track, (size_t)target)) {
                        return RETROFM_MDX_BAD_LOOP;
                    }
                    if (repeat_depth != 0U) return RETROFM_MDX_BAD_REPEAT;
                    /* A loop command is a terminal control-flow instruction:
                     * bytes after it are unreachable except zero padding. */
                    ended = true;
                }
                break;
            default:
                break;
        }

        position = after;
        if (ended) {
            while (position < track->size && track->data[position] == 0U) {
                ++position;
            }
            if (position != track->size) {
                return RETROFM_MDX_BAD_COMMAND_ARGUMENT;
            }
            break;
        }
    }

    return ended ? RETROFM_MDX_OK : RETROFM_MDX_TRUNCATED_COMMAND;
}

retrofm_mdx_result retrofm_mdx_open(retrofm_mdx *mdx,
                                    const uint8_t *bytes,
                                    size_t size) {
    size_t title_end = SIZE_MAX;
    size_t position = 0U;
    size_t table_bytes;
    size_t i;
    size_t j;
    uint16_t offsets[RETROFM_MDX_MAX_TRACKS + 1U];
    retrofm_mdx_chunk chunks[RETROFM_MDX_MAX_TRACKS + 1U];

    if (mdx == NULL || bytes == NULL) return RETROFM_MDX_BAD_ARGUMENT;
    memset(mdx, 0, sizeof(*mdx));
    if (size < 8U) return RETROFM_MDX_TRUNCATED;

    for (i = 2U; i < size; ++i) {
        if (bytes[i - 2U] == 0x0DU && bytes[i - 1U] == 0x0AU &&
            bytes[i] == 0x1AU) {
            title_end = i - 2U;
            position = i + 1U;
            break;
        }
    }
    if (title_end == SIZE_MAX) return RETROFM_MDX_BAD_TITLE;
    mdx->title.data = bytes;
    mdx->title.size = title_end;

    for (i = position; i < size && bytes[i] != 0U; ++i) {
    }
    if (i == size) return RETROFM_MDX_BAD_PDX_NAME;
    mdx->pdx_name.data = bytes + position;
    mdx->pdx_name.size = i - position;
    mdx->data_start = i + 1U;

    if (!range_ok(mdx->data_start, 7U, size)) return RETROFM_MDX_TRUNCATED;
    if (bytes[mdx->data_start + 4U] == 'L' &&
        bytes[mdx->data_start + 5U] == 'Z' &&
        bytes[mdx->data_start + 6U] == 'X') {
        return RETROFM_MDX_LZX_UNSUPPORTED;
    }

    /* The first offset names the voice-data chunk.  The second offset names
     * track A, which starts immediately after the complete offset table and
     * therefore encodes whether this is a 9- or 16-track MDX.  Real files may
     * place the voice chunk after the tracks, so offsets[0] cannot be used to
     * infer the track count. */
    offsets[1] = be16(bytes + mdx->data_start + 2U);
    if (offsets[1] < 4U || (offsets[1] & 1U) != 0U) {
        return RETROFM_MDX_BAD_TRACK_COUNT;
    }
    mdx->track_count = (uint8_t)(offsets[1] / 2U - 1U);
    if (mdx->track_count != 9U && mdx->track_count != 16U) {
        return RETROFM_MDX_BAD_TRACK_COUNT;
    }
    table_bytes = 2U * ((size_t)mdx->track_count + 1U);
    if (offsets[1] != table_bytes ||
        !range_ok(mdx->data_start, table_bytes, size)) {
        return RETROFM_MDX_BAD_OFFSET;
    }

    for (i = 0U; i <= mdx->track_count; ++i) {
        size_t absolute;
        offsets[i] = be16(bytes + mdx->data_start + i * 2U);
        absolute = mdx->data_start + offsets[i];
        if (offsets[i] < table_bytes || absolute >= size) {
            return RETROFM_MDX_BAD_OFFSET;
        }
        chunks[i].start = absolute;
        chunks[i].end = size;
        for (j = 0U; j < i; ++j) {
            if (offsets[i] == offsets[j]) return RETROFM_MDX_OVERLAP;
        }
    }

    for (i = 0U; i <= mdx->track_count; ++i) {
        for (j = 0U; j <= mdx->track_count; ++j) {
            if (chunks[j].start > chunks[i].start &&
                chunks[j].start < chunks[i].end) {
                chunks[i].end = chunks[j].start;
            }
        }
        if (chunks[i].end <= chunks[i].start) return RETROFM_MDX_OVERLAP;
    }

    mdx->voice_data.data = bytes + chunks[0].start;
    mdx->voice_data.size = chunks[0].end - chunks[0].start;
    if (mdx->voice_data.size == 0U ||
        mdx->voice_data.size % RETROFM_MDX_VOICE_SIZE != 0U ||
        mdx->voice_data.size / RETROFM_MDX_VOICE_SIZE > 256U) {
        return RETROFM_MDX_BAD_VOICE_DATA;
    }
    mdx->voice_count =
        (uint16_t)(mdx->voice_data.size / RETROFM_MDX_VOICE_SIZE);
    for (i = 0U; i < mdx->voice_count; ++i) {
        const uint8_t *voice = mdx->voice_data.data +
                               i * RETROFM_MDX_VOICE_SIZE;
        if (mdx->voices[voice[0]] != NULL) {
            return RETROFM_MDX_DUPLICATE_VOICE;
        }
        mdx->voices[voice[0]] = voice;
    }

    for (i = 0U; i < mdx->track_count; ++i) {
        retrofm_mdx_result result;
        mdx->tracks[i].data = bytes + chunks[i + 1U].start;
        mdx->tracks[i].size = chunks[i + 1U].end - chunks[i + 1U].start;
        result = validate_track(mdx, i);
        if (result != RETROFM_MDX_OK) return result;
    }

    mdx->whole_file.data = bytes;
    mdx->whole_file.size = size;
    return RETROFM_MDX_OK;
}

const char *retrofm_mdx_result_string(retrofm_mdx_result result) {
    switch (result) {
        case RETROFM_MDX_OK: return "ok";
        case RETROFM_MDX_BAD_ARGUMENT: return "bad argument";
        case RETROFM_MDX_TRUNCATED: return "truncated file";
        case RETROFM_MDX_BAD_TITLE: return "bad title terminator";
        case RETROFM_MDX_BAD_PDX_NAME: return "bad PDX name";
        case RETROFM_MDX_LZX_UNSUPPORTED: return "LZX MDX unsupported";
        case RETROFM_MDX_BAD_TRACK_COUNT: return "MDX must contain 9 or 16 tracks";
        case RETROFM_MDX_BAD_OFFSET: return "bad chunk offset";
        case RETROFM_MDX_OVERLAP: return "overlapping MDX chunks";
        case RETROFM_MDX_BAD_VOICE_DATA: return "bad voice data";
        case RETROFM_MDX_DUPLICATE_VOICE: return "duplicate voice number";
        case RETROFM_MDX_TRUNCATED_COMMAND: return "truncated track command";
        case RETROFM_MDX_UNSUPPORTED_COMMAND: return "unsupported track command";
        case RETROFM_MDX_BAD_COMMAND_ARGUMENT: return "bad command argument";
        case RETROFM_MDX_BAD_REPEAT: return "bad repeat structure";
        case RETROFM_MDX_BAD_LOOP: return "bad track loop";
        case RETROFM_MDX_MISSING_VOICE: return "selected voice is absent";
        case RETROFM_MDX_END: return "end";
        case RETROFM_MDX_BAD_STATE: return "invalid sequencer state";
        case RETROFM_MDX_CALLBACK_REJECTED: return "event callback rejected trace";
        case RETROFM_MDX_ZERO_TIME_LOOP: return "zero-time command limit exceeded";
        case RETROFM_MDX_TIME_OVERFLOW: return "playback time overflow";
        case RETROFM_MDX_MISSING_PDX: return "MDX requires a parsed PDX file";
        case RETROFM_MDX_PDX_SAMPLE_ERROR: return "invalid PDX sample reference";
        case RETROFM_MDX_PCM_CALLBACK_REJECTED: return "PCM callback rejected command";
        case RETROFM_MDX_PCM8_NOT_ENABLED: return "PCM8 channel used before enable";
        case RETROFM_MDX_PCM8_BANK_UNSUPPORTED: return "unsupported PCM8 bank command";
        default: return "unknown MDX error";
    }
}
