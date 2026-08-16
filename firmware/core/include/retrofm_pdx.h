/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_PDX_H
#define RETROFM_PDX_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RETROFM_PDX_SAMPLE_COUNT 96U
#define RETROFM_PDX_TABLE_BYTES (RETROFM_PDX_SAMPLE_COUNT * 8U)

typedef enum retrofm_pdx_result {
    RETROFM_PDX_OK = 0,
    RETROFM_PDX_END,
    RETROFM_PDX_BAD_ARGUMENT,
    RETROFM_PDX_TRUNCATED,
    RETROFM_PDX_INVALID_RANGE,
    RETROFM_PDX_INDEX_OUT_OF_RANGE,
    RETROFM_PDX_EMPTY_SAMPLE,
    RETROFM_PDX_BAD_STATE
} retrofm_pdx_result;

typedef struct retrofm_pdx_entry {
    uint32_t offset;
    uint32_t length;
} retrofm_pdx_entry;

typedef struct retrofm_pdx {
    /* The caller owns this storage and must keep it alive while pdx is used. */
    const uint8_t *bytes;
    size_t size;
    retrofm_pdx_entry entries[RETROFM_PDX_SAMPLE_COUNT];
} retrofm_pdx;

/*
 * The decoder emits the signed 12-bit values produced by the MSM6258/OKI
 * algorithm. The mixer may scale these to its signed 16-bit sample domain.
 */
typedef struct retrofm_adpcm_decoder {
    const uint8_t *bytes;
    size_t length;
    size_t byte_position;
    int16_t signal;
    uint8_t step_index;
    bool high_nibble_next;
} retrofm_adpcm_decoder;

retrofm_pdx_result retrofm_pdx_open(retrofm_pdx *pdx,
                                    const uint8_t *bytes,
                                    size_t size);

retrofm_pdx_result retrofm_pdx_get_sample(const retrofm_pdx *pdx,
                                          size_t sample_index,
                                          const uint8_t **bytes,
                                          size_t *length);

retrofm_pdx_result retrofm_adpcm_begin(retrofm_adpcm_decoder *decoder,
                                       const uint8_t *bytes,
                                       size_t length);

retrofm_pdx_result retrofm_adpcm_next(retrofm_adpcm_decoder *decoder,
                                      int16_t *sample);

size_t retrofm_adpcm_samples_remaining(const retrofm_adpcm_decoder *decoder);

const char *retrofm_pdx_result_string(retrofm_pdx_result result);

#ifdef __cplusplus
}
#endif

#endif
