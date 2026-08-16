/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_MDX_H
#define RETROFM_MDX_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RETROFM_MDX_MAX_TRACKS 16U
#define RETROFM_MDX_VOICE_SIZE 27U

typedef enum retrofm_mdx_result {
    RETROFM_MDX_OK = 0,
    RETROFM_MDX_BAD_ARGUMENT,
    RETROFM_MDX_TRUNCATED,
    RETROFM_MDX_BAD_TITLE,
    RETROFM_MDX_BAD_PDX_NAME,
    RETROFM_MDX_LZX_UNSUPPORTED,
    RETROFM_MDX_BAD_TRACK_COUNT,
    RETROFM_MDX_BAD_OFFSET,
    RETROFM_MDX_OVERLAP,
    RETROFM_MDX_BAD_VOICE_DATA,
    RETROFM_MDX_DUPLICATE_VOICE,
    RETROFM_MDX_TRUNCATED_COMMAND,
    RETROFM_MDX_UNSUPPORTED_COMMAND,
    RETROFM_MDX_BAD_COMMAND_ARGUMENT,
    RETROFM_MDX_BAD_REPEAT,
    RETROFM_MDX_BAD_LOOP,
    RETROFM_MDX_MISSING_VOICE,
    RETROFM_MDX_END,
    RETROFM_MDX_BAD_STATE,
    RETROFM_MDX_CALLBACK_REJECTED,
    RETROFM_MDX_ZERO_TIME_LOOP,
    RETROFM_MDX_TIME_OVERFLOW,
    RETROFM_MDX_MISSING_PDX,
    RETROFM_MDX_PDX_SAMPLE_ERROR,
    RETROFM_MDX_PCM_CALLBACK_REJECTED,
    RETROFM_MDX_PCM8_NOT_ENABLED,
    RETROFM_MDX_PCM8_BANK_UNSUPPORTED
} retrofm_mdx_result;

typedef struct retrofm_mdx_span {
    const uint8_t *data;
    size_t size;
} retrofm_mdx_span;

typedef struct retrofm_mdx {
    retrofm_mdx_span whole_file;
    retrofm_mdx_span title;
    retrofm_mdx_span pdx_name;
    retrofm_mdx_span voice_data;
    retrofm_mdx_span tracks[RETROFM_MDX_MAX_TRACKS];
    const uint8_t *voices[256];
    size_t data_start;
    uint8_t track_count;
    uint16_t voice_count;
    bool uses_pdx;
} retrofm_mdx;

retrofm_mdx_result retrofm_mdx_open(retrofm_mdx *mdx,
                                    const uint8_t *bytes,
                                    size_t size);

size_t retrofm_mdx_command_size(const uint8_t *track,
                                size_t remaining,
                                retrofm_mdx_result *result);

const char *retrofm_mdx_result_string(retrofm_mdx_result result);

#ifdef __cplusplus
}
#endif

#endif
