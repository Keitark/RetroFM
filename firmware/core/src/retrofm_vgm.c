/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_vgm.h"

#include <limits.h>
#include <string.h>

#define VGM_MIN_VERSION UINT32_C(0x00000151)
#define YM2203_CLOCK_OFFSET 0x44U
#define YM2608_CLOCK_OFFSET 0x48U
#define VGM_MAX_YM2203_CLOCK UINT32_C(10000000)
#define VGM_MAX_YM2608_CLOCK UINT32_C(10000000)

static const size_t unsupported_clock_offsets[] = {
    0x0CU, 0x10U, 0x2CU, 0x30U, 0x38U, 0x40U,
    0x4CU, 0x50U, 0x54U, 0x58U, 0x5CU,
    0x60U, 0x64U, 0x68U, 0x6CU, 0x70U, 0x74U,
    0x80U, 0x84U, 0x88U, 0x8CU, 0x90U, 0x98U,
    0x9CU, 0xA0U, 0xA4U, 0xA8U, 0xACU, 0xB0U,
    0xB4U, 0xB8U, 0xC0U, 0xC4U, 0xC8U, 0xCCU,
    0xD0U, 0xD8U, 0xDCU, 0xE0U, 0xE4U
};

static bool has_bytes(size_t position, size_t amount, size_t size) {
    return position <= size && amount <= size - position;
}

static uint16_t read_u16(const uint8_t *bytes, size_t offset) {
    return (uint16_t)((uint16_t)bytes[offset] |
                      ((uint16_t)bytes[offset + 1U] << 8U));
}

static uint32_t read_u32(const uint8_t *bytes, size_t offset) {
    return (uint32_t)bytes[offset] |
           ((uint32_t)bytes[offset + 1U] << 8U) |
           ((uint32_t)bytes[offset + 2U] << 16U) |
           ((uint32_t)bytes[offset + 3U] << 24U);
}

static retrofm_result emit_pending(retrofm_vgm *vgm, retrofm_event *event) {
    uint64_t amount = vgm->pending_cycles;

    if (amount == 0U) {
        return RETROFM_BAD_ARGUMENT;
    }

    event->delta_cycles = amount > UINT32_MAX ? UINT32_MAX : (uint32_t)amount;
    event->opcode = RETROFM_OP_DELAY;
    event->reg = 0U;
    event->data = 0U;
    event->flags = 0U;
    vgm->pending_cycles -= event->delta_cycles;
    vgm->scan_budget = vgm->size + 1U;
    return RETROFM_OK;
}

static retrofm_result add_wait(retrofm_vgm *vgm, uint32_t samples) {
    uint64_t cycles = retrofm_vgm_samples_to_cycles(&vgm->timebase, samples);
    if (UINT64_MAX - vgm->pending_cycles < cycles) {
        return RETROFM_RANGE_ERROR;
    }
    vgm->pending_cycles += cycles;
    if (vgm->tracking_loop_progress && cycles != 0U) {
        vgm->loop_time_progress = true;
    }
    vgm->scan_budget = vgm->size + 1U;
    return RETROFM_OK;
}

static retrofm_result validate_clocks(const uint8_t *bytes,
                                      size_t header_size,
                                      uint32_t *ym2203_clock_hz,
                                      uint32_t *ym2608_clock_hz,
                                      bool *is_ym2608) {
    size_t i;
    uint32_t ym2203_raw;
    uint32_t ym2608_raw;

    if (!has_bytes(YM2203_CLOCK_OFFSET, 4U, header_size)) {
        return RETROFM_BAD_HEADER;
    }

    ym2203_raw = read_u32(bytes, YM2203_CLOCK_OFFSET);
    ym2608_raw = has_bytes(YM2608_CLOCK_OFFSET, 4U, header_size) ?
        read_u32(bytes, YM2608_CLOCK_OFFSET) : 0U;
    if ((ym2203_raw & UINT32_C(0x40000000)) != 0U ||
        (ym2608_raw & UINT32_C(0x40000000)) != 0U) {
        return RETROFM_MULTI_CHIP;
    }
    if ((ym2203_raw & UINT32_C(0x80000000)) != 0U ||
        (ym2608_raw & UINT32_C(0x80000000)) != 0U) {
        return RETROFM_BAD_CLOCK;
    }
    ym2203_raw &= UINT32_C(0x3FFFFFFF);
    ym2608_raw &= UINT32_C(0x3FFFFFFF);
    if ((ym2203_raw == 0U && ym2608_raw == 0U) ||
        (ym2203_raw != 0U && ym2608_raw != 0U)) {
        return ym2203_raw != 0U ? RETROFM_MULTI_CHIP :
                                  RETROFM_UNSUPPORTED_CHIP;
    }
    if (ym2203_raw != 0U && ym2203_raw > VGM_MAX_YM2203_CLOCK) {
        return RETROFM_BAD_CLOCK;
    }
    if (ym2608_raw != 0U && ym2608_raw > VGM_MAX_YM2608_CLOCK) {
        return RETROFM_BAD_CLOCK;
    }
    *ym2203_clock_hz = ym2203_raw;
    *ym2608_clock_hz = ym2608_raw;
    *is_ym2608 = ym2608_raw != 0U;

    for (i = 0U; i < sizeof(unsupported_clock_offsets) /
                            sizeof(unsupported_clock_offsets[0]); ++i) {
        size_t offset = unsupported_clock_offsets[i];
        if (has_bytes(offset, 4U, header_size) &&
            (read_u32(bytes, offset) & UINT32_C(0x3FFFFFFF)) != 0U) {
            return RETROFM_UNSUPPORTED_CHIP;
        }
    }
    return RETROFM_OK;
}

static retrofm_result validate_extra_header(const uint8_t *bytes,
                                            size_t data_start) {
    uint32_t relative;
    uint32_t header_size;
    size_t extra_position;
    size_t extra_end;

    if (!has_bytes(0xBCU, 4U, data_start)) return RETROFM_OK;
    relative = read_u32(bytes, 0xBCU);
    if (relative == 0U) return RETROFM_OK;
    if ((uint64_t)relative + 0xBCU > SIZE_MAX) return RETROFM_BAD_HEADER;
    extra_position = 0xBCU + (size_t)relative;
    if (!has_bytes(extra_position, 4U, data_start)) {
        return RETROFM_BAD_HEADER;
    }
    header_size = read_u32(bytes, extra_position);
    if (header_size < 4U || header_size > 12U ||
        !has_bytes(extra_position, (size_t)header_size, data_start)) {
        return RETROFM_BAD_HEADER;
    }
    extra_end = extra_position + (size_t)header_size;

    if (header_size >= 8U) {
        size_t field = extra_position + 4U;
        uint32_t clock_relative = read_u32(bytes, field);
        if (clock_relative != 0U) {
            size_t list_position;
            uint8_t count;
            if ((uint64_t)field + clock_relative > SIZE_MAX) {
                return RETROFM_BAD_HEADER;
            }
            list_position = field + (size_t)clock_relative;
            if (list_position < extra_end ||
                !has_bytes(list_position, 1U, data_start)) {
                return RETROFM_BAD_HEADER;
            }
            count = bytes[list_position];
            if (!has_bytes(list_position + 1U, (size_t)count * 5U,
                           data_start)) {
                return RETROFM_BAD_HEADER;
            }
            if (count != 0U) return RETROFM_MULTI_CHIP;
        }
    }

    if (header_size >= 12U) {
        size_t field = extra_position + 8U;
        uint32_t volume_relative = read_u32(bytes, field);
        if (volume_relative != 0U) {
            size_t list_position;
            uint8_t count;
            if ((uint64_t)field + volume_relative > SIZE_MAX) {
                return RETROFM_BAD_HEADER;
            }
            list_position = field + (size_t)volume_relative;
            if (list_position < extra_end ||
                !has_bytes(list_position, 1U, data_start)) {
                return RETROFM_BAD_HEADER;
            }
            count = bytes[list_position];
            if (!has_bytes(list_position + 1U, (size_t)count * 4U,
                           data_start)) {
                return RETROFM_BAD_HEADER;
            }
            /* Chip-volume entries alter renderer balance only.  They do not
             * add a sound chip, so version 1 accepts a well-formed list while
             * retaining JT03's hardware-faithful built-in FM/SSG balance. */
        }
    }
    return RETROFM_OK;
}

retrofm_result retrofm_vgm_open(retrofm_vgm *vgm,
                                const uint8_t *bytes,
                                size_t size,
                                bool loop_enabled) {
    uint32_t relative;
    uint32_t eof_relative;
    size_t logical_size;
    size_t data_start;
    size_t clock_header_size;
    retrofm_result result;

    if (vgm == NULL || bytes == NULL) {
        return RETROFM_BAD_ARGUMENT;
    }
    memset(vgm, 0, sizeof(*vgm));

    if (size < 0x48U) {
        return RETROFM_TRUNCATED;
    }
    if (memcmp(bytes, "Vgm ", 4U) != 0) {
        return RETROFM_BAD_MAGIC;
    }

    vgm->version = read_u32(bytes, 0x08U);
    if (vgm->version < VGM_MIN_VERSION) {
        return RETROFM_BAD_VERSION;
    }

    eof_relative = read_u32(bytes, 0x04U);
    logical_size = size;
    if (eof_relative != 0U) {
        uint64_t declared = (uint64_t)eof_relative + 4U;
        if (declared > size || declared < 0x40U) {
            return RETROFM_BAD_HEADER;
        }
        logical_size = (size_t)declared;
    }

    relative = read_u32(bytes, 0x34U);
    data_start = relative == 0U ? 0x40U : (size_t)relative + 0x34U;
    if (data_start < 0x40U || data_start >= logical_size) {
        return RETROFM_BAD_HEADER;
    }

    clock_header_size = data_start;
    result = validate_extra_header(bytes, data_start);
    if (result != RETROFM_OK) return result;
    if (has_bytes(0xBCU, 4U, data_start) &&
        read_u32(bytes, 0xBCU) != 0U) {
        clock_header_size = 0xBCU + (size_t)read_u32(bytes, 0xBCU);
    }

    result = validate_clocks(bytes, clock_header_size,
                             &vgm->ym2203_clock_hz,
                             &vgm->ym2608_clock_hz,
                             &vgm->is_ym2608);
    if (result != RETROFM_OK) {
        return result;
    }

    relative = read_u32(bytes, 0x1CU);
    if (relative != 0U) {
        uint64_t loop_position = (uint64_t)relative + 0x1CU;
        if (loop_position < data_start || loop_position >= logical_size) {
            return RETROFM_BAD_LOOP;
        }
        if (!has_bytes(0x20U, 4U, data_start) ||
            read_u32(bytes, 0x20U) == 0U) {
            return RETROFM_BAD_LOOP;
        }
        vgm->has_loop = true;
        vgm->loop_position = (size_t)loop_position;
    }

    vgm->bytes = bytes;
    vgm->size = logical_size;
    vgm->data_start = data_start;
    vgm->position = data_start;
    vgm->scan_budget = logical_size + 1U;
    vgm->loop_enabled = loop_enabled;
    retrofm_timebase_reset(&vgm->timebase);
    return RETROFM_OK;
}

retrofm_result retrofm_vgm_next(retrofm_vgm *vgm, retrofm_event *event) {
    if (vgm == NULL || event == NULL || vgm->bytes == NULL) {
        return RETROFM_BAD_ARGUMENT;
    }

    if (vgm->pending_cycles > UINT32_MAX) {
        return emit_pending(vgm, event);
    }

    if (vgm->loop_after_delay && vgm->pending_cycles == 0U) {
        vgm->loop_after_delay = false;
        vgm->position = vgm->loop_position;
        ++vgm->loop_count;
    }
    if (vgm->end_after_delay && vgm->pending_cycles == 0U) {
        vgm->end_after_delay = false;
        vgm->ended = true;
    }
    if (vgm->ended) {
        return RETROFM_END;
    }

    for (;;) {
        uint8_t command;
        retrofm_result result;

        /* A VGM loop offset must identify a command boundary, and the loop
         * body must advance musical time.  The header's loop-sample count is
         * metadata and cannot be trusted to prove either property. */
        if (vgm->has_loop && vgm->position == vgm->loop_position) {
            vgm->loop_target_seen = true;
            vgm->tracking_loop_progress = true;
            vgm->loop_time_progress = false;
        }

        if (vgm->scan_budget == 0U) {
            return RETROFM_BAD_LOOP;
        }
        --vgm->scan_budget;

        if (!has_bytes(vgm->position, 1U, vgm->size)) {
            return RETROFM_TRUNCATED;
        }
        command = vgm->bytes[vgm->position++];

        if (command == 0x55U || command == 0x56U || command == 0x57U) {
            if (!has_bytes(vgm->position, 2U, vgm->size)) {
                return RETROFM_TRUNCATED;
            }
            if ((command == 0x55U && vgm->is_ym2608) ||
                (command != 0x55U && !vgm->is_ym2608)) {
                return RETROFM_UNSUPPORTED_COMMAND;
            }
            event->delta_cycles = (uint32_t)vgm->pending_cycles;
            event->opcode = vgm->is_ym2608 ? RETROFM_OP_YM2608 :
                                              RETROFM_OP_YM2203;
            event->reg = vgm->bytes[vgm->position];
            event->data = vgm->bytes[vgm->position + 1U];
            event->flags = command == 0x57U ? RETROFM_EVENT_FLAG_OPNA_PORT1 :
                                               0U;
            vgm->position += 2U;
            vgm->pending_cycles = 0U;
            vgm->scan_budget = vgm->size + 1U;
            return RETROFM_OK;
        }

        if (command == 0x61U) {
            uint16_t samples;
            if (!has_bytes(vgm->position, 2U, vgm->size)) {
                return RETROFM_TRUNCATED;
            }
            samples = read_u16(vgm->bytes, vgm->position);
            vgm->position += 2U;
            result = add_wait(vgm, samples);
        } else if (command == 0x62U) {
            result = add_wait(vgm, 735U);
        } else if (command == 0x63U) {
            result = add_wait(vgm, 882U);
        } else if (command >= 0x70U && command <= 0x7FU) {
            result = add_wait(vgm, (uint32_t)(command & 0x0FU) + 1U);
        } else if (command == 0x67U) {
            uint32_t block_size;
            if (!has_bytes(vgm->position, 6U, vgm->size) ||
                vgm->bytes[vgm->position] != 0x66U) {
                return RETROFM_TRUNCATED;
            }
            /* 0x81 is the YM2608 Delta-T ROM block.  This release does not
             * have the OPNA sample-memory loader yet, so accepting it would
             * make valid files lose their ADPCM-B voice without warning. */
            if (vgm->is_ym2608 && vgm->bytes[vgm->position + 1U] == 0x81U) {
                return RETROFM_UNSUPPORTED_COMMAND;
            }
            block_size = read_u32(vgm->bytes, vgm->position + 2U) &
                         UINT32_C(0x7FFFFFFF);
            vgm->position += 6U;
            if (!has_bytes(vgm->position, block_size, vgm->size)) {
                return RETROFM_TRUNCATED;
            }
            vgm->position += block_size;
            result = RETROFM_OK;
        } else if (command == 0x66U) {
            if (vgm->has_loop &&
                (!vgm->loop_target_seen || !vgm->loop_time_progress)) {
                return RETROFM_BAD_LOOP;
            }
            if (vgm->loop_enabled && vgm->has_loop) {
                if (vgm->pending_cycles != 0U) {
                    vgm->loop_after_delay = true;
                    return emit_pending(vgm, event);
                }
                vgm->position = vgm->loop_position;
                ++vgm->loop_count;
                result = RETROFM_OK;
            } else {
                if (vgm->pending_cycles != 0U) {
                    vgm->end_after_delay = true;
                    return emit_pending(vgm, event);
                }
                vgm->ended = true;
                return RETROFM_END;
            }
        } else {
            return RETROFM_UNSUPPORTED_COMMAND;
        }

        if (result != RETROFM_OK) {
            return result;
        }
        if (vgm->pending_cycles > UINT32_MAX) {
            return emit_pending(vgm, event);
        }
    }
}

static size_t append_utf8(char *destination, size_t capacity, size_t used,
                          uint16_t codepoint) {
    if (codepoint < 0x80U) {
        if (used + 1U < capacity) destination[used] = (char)codepoint;
        return used + 1U;
    }
    if (codepoint < 0x800U) {
        if (used + 2U < capacity) {
            destination[used] = (char)(0xC0U | (codepoint >> 6U));
            destination[used + 1U] = (char)(0x80U | (codepoint & 0x3FU));
        }
        return used + 2U;
    }
    if (used + 3U < capacity) {
        destination[used] = (char)(0xE0U | (codepoint >> 12U));
        destination[used + 1U] = (char)(0x80U | ((codepoint >> 6U) & 0x3FU));
        destination[used + 2U] = (char)(0x80U | (codepoint & 0x3FU));
    }
    return used + 3U;
}

static retrofm_result gd3_field(const retrofm_vgm *vgm,
                                unsigned requested_field,
                                char *utf8,
                                size_t capacity) {
    uint32_t relative;
    uint32_t payload_size;
    size_t position;
    size_t payload_end;
    size_t used = 0U;
    unsigned field = 0U;
    bool last_was_terminator = false;

    if (vgm == NULL || vgm->bytes == NULL || utf8 == NULL || capacity == 0U) {
        return RETROFM_BAD_ARGUMENT;
    }
    utf8[0] = '\0';
    if (!has_bytes(0x14U, 4U, vgm->size)) {
        return RETROFM_TRUNCATED;
    }
    relative = read_u32(vgm->bytes, 0x14U);
    if (relative == 0U) {
        return RETROFM_END;
    }
    position = (size_t)relative + 0x14U;
    if (!has_bytes(position, 12U, vgm->size) ||
        memcmp(vgm->bytes + position, "Gd3 ", 4U) != 0) {
        return RETROFM_BAD_HEADER;
    }
    payload_size = read_u32(vgm->bytes, position + 8U);
    if ((payload_size & 1U) != 0U ||
        !has_bytes(position + 12U, payload_size, vgm->size)) {
        return RETROFM_BAD_HEADER;
    }
    position += 12U;
    payload_end = position + payload_size;
    while (position + 2U <= payload_end) {
        uint16_t codepoint = read_u16(vgm->bytes, position);
        position += 2U;
        if (codepoint == 0U) {
            last_was_terminator = true;
            if (field == requested_field) {
                utf8[used < capacity ? used : capacity - 1U] = '\0';
                return used == 0U ? RETROFM_END : RETROFM_OK;
            }
            ++field;
            used = 0U;
            continue;
        }
        last_was_terminator = false;
        if (codepoint >= 0xD800U && codepoint <= 0xDFFFU) {
            return RETROFM_BAD_HEADER;
        }
        if (field == requested_field) {
            used = append_utf8(utf8, capacity, used, codepoint);
        }
    }
    utf8[used < capacity ? used : capacity - 1U] = '\0';
    return last_was_terminator ? RETROFM_END : RETROFM_BAD_HEADER;
}

retrofm_result retrofm_vgm_title(const retrofm_vgm *vgm,
                                 char *utf8,
                                 size_t capacity) {
    retrofm_result result = gd3_field(vgm, 1U, utf8, capacity);
    if (result == RETROFM_OK) return result;
    if (result != RETROFM_END) return result;
    return gd3_field(vgm, 0U, utf8, capacity);
}

retrofm_result retrofm_vgm_artist(const retrofm_vgm *vgm,
                                  char *utf8,
                                  size_t capacity) {
    retrofm_result result = gd3_field(vgm, 7U, utf8, capacity);
    if (result == RETROFM_OK) return result;
    if (result != RETROFM_END) return result;
    return gd3_field(vgm, 6U, utf8, capacity);
}

const char *retrofm_result_string(retrofm_result result) {
    switch (result) {
        case RETROFM_OK: return "ok";
        case RETROFM_END: return "end";
        case RETROFM_BAD_ARGUMENT: return "bad argument";
        case RETROFM_TRUNCATED: return "truncated input";
        case RETROFM_BAD_MAGIC: return "bad VGM magic";
        case RETROFM_BAD_VERSION: return "unsupported VGM version";
        case RETROFM_BAD_HEADER: return "bad VGM header";
        case RETROFM_UNSUPPORTED_CHIP: return "unsupported chip";
        case RETROFM_MULTI_CHIP: return "multi-chip VGM";
        case RETROFM_BAD_CLOCK: return "invalid YM2203 clock";
        case RETROFM_UNSUPPORTED_COMMAND: return "unsupported VGM command";
        case RETROFM_BAD_LOOP: return "invalid or zero-progress loop";
        case RETROFM_RANGE_ERROR: return "numeric range error";
        default: return "unknown error";
    }
}
