/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Keitark */

#include "retrofm_sjis.h"

#include "retrofm_sjis_table.h"

#include <stdbool.h>

static uint16_t lookup(uint16_t sjis) {
    size_t low = 0U;
    size_t high = retrofm_sjis_table_size;
    while (low < high) {
        size_t middle = low + (high - low) / 2U;
        uint16_t key = retrofm_sjis_table[middle].sjis;
        if (key == sjis) return retrofm_sjis_table[middle].unicode;
        if (key < sjis) low = middle + 1U;
        else high = middle;
    }
    return 0U;
}

static size_t utf8_size(uint16_t codepoint) {
    if (codepoint < 0x80U) return 1U;
    if (codepoint < 0x800U) return 2U;
    return 3U;
}

static void append_utf8(char *destination, size_t *position,
                        uint16_t codepoint) {
    size_t output = *position;
    if (codepoint < 0x80U) {
        destination[output++] = (char)codepoint;
    } else if (codepoint < 0x800U) {
        destination[output++] = (char)(0xC0U | (codepoint >> 6U));
        destination[output++] = (char)(0x80U | (codepoint & 0x3FU));
    } else {
        destination[output++] = (char)(0xE0U | (codepoint >> 12U));
        destination[output++] =
            (char)(0x80U | ((codepoint >> 6U) & 0x3FU));
        destination[output++] = (char)(0x80U | (codepoint & 0x3FU));
    }
    *position = output;
}

retrofm_sjis_result retrofm_sjis_to_utf8(const uint8_t *source,
                                         size_t source_size,
                                         char *destination,
                                         size_t destination_capacity,
                                         size_t *destination_size) {
    size_t input = 0U;
    size_t output = 0U;
    bool replaced = false;

    if (destination_size != NULL) *destination_size = 0U;
    if ((source == NULL && source_size != 0U) || destination == NULL ||
        destination_capacity == 0U || destination_size == NULL) {
        return RETROFM_SJIS_BAD_ARGUMENT;
    }
    while (input < source_size && source[input] != 0U) {
        uint8_t first = source[input++];
        uint16_t codepoint;
        if (first <= 0x7FU) {
            codepoint = first;
        } else if (first >= 0xA1U && first <= 0xDFU) {
            codepoint = (uint16_t)(0xFF61U + (first - 0xA1U));
        } else if (input >= source_size || source[input] == 0U) {
            codepoint = (uint16_t)'?';
            replaced = true;
        } else {
            uint16_t sjis = (uint16_t)(((uint16_t)first << 8U) |
                                       source[input++]);
            codepoint = lookup(sjis);
            if (codepoint == 0U) {
                codepoint = (uint16_t)'?';
                replaced = true;
            }
        }
        if (utf8_size(codepoint) > destination_capacity - 1U - output) {
            destination[output] = '\0';
            *destination_size = output;
            return RETROFM_SJIS_OUTPUT_TOO_SMALL;
        }
        append_utf8(destination, &output, codepoint);
    }
    destination[output] = '\0';
    *destination_size = output;
    return replaced ? RETROFM_SJIS_REPLACED : RETROFM_SJIS_OK;
}

const char *retrofm_sjis_result_string(retrofm_sjis_result result) {
    switch (result) {
        case RETROFM_SJIS_OK: return "ok";
        case RETROFM_SJIS_REPLACED: return "invalid sequence replaced";
        case RETROFM_SJIS_BAD_ARGUMENT: return "bad argument";
        case RETROFM_SJIS_OUTPUT_TOO_SMALL: return "output too small";
        default: return "unknown error";
    }
}
