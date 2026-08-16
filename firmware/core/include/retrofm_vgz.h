/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_VGZ_H
#define RETROFM_VGZ_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef RETROFM_HAS_VGZ
#define RETROFM_HAS_VGZ 0
#endif

typedef enum retrofm_vgz_result {
    RETROFM_VGZ_OK = 0,
    RETROFM_VGZ_UNAVAILABLE,
    RETROFM_VGZ_BAD_ARGUMENT,
    RETROFM_VGZ_TRUNCATED,
    RETROFM_VGZ_BAD_MAGIC,
    RETROFM_VGZ_UNSUPPORTED_METHOD,
    RETROFM_VGZ_RESERVED_FLAGS,
    RETROFM_VGZ_BAD_HEADER_CRC,
    RETROFM_VGZ_LIMIT_EXCEEDED,
    RETROFM_VGZ_OUTPUT_TOO_SMALL,
    RETROFM_VGZ_DEFLATE_ERROR,
    RETROFM_VGZ_TRAILING_DATA,
    RETROFM_VGZ_BAD_CRC32,
    RETROFM_VGZ_BAD_ISIZE
} retrofm_vgz_result;

/*
 * Decompresses exactly one gzip member into caller-owned storage.
 *
 * The output is valid only when RETROFM_VGZ_OK is returned. output_size is
 * reset to zero on entry and remains zero on error. max_decompressed_size is
 * an independent policy cap and is enforced even when the gzip ISIZE lies.
 */
retrofm_vgz_result retrofm_vgz_decompress(const uint8_t *source,
                                          size_t source_size,
                                          uint8_t *output,
                                          size_t output_capacity,
                                          size_t max_decompressed_size,
                                          size_t *output_size);

const char *retrofm_vgz_result_string(retrofm_vgz_result result);

#ifdef __cplusplus
}
#endif

#endif
