/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Keitark */

#ifndef RETROFM_SJIS_H
#define RETROFM_SJIS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum retrofm_sjis_result {
    RETROFM_SJIS_OK = 0,
    RETROFM_SJIS_REPLACED,
    RETROFM_SJIS_BAD_ARGUMENT,
    RETROFM_SJIS_OUTPUT_TOO_SMALL
} retrofm_sjis_result;

/* Allocation-free Windows-31J/CP932 conversion for MDX titles. Invalid or
 * incomplete byte sequences are replaced with '?' and return REPLACED. */
retrofm_sjis_result retrofm_sjis_to_utf8(const uint8_t *source,
                                         size_t source_size,
                                         char *destination,
                                         size_t destination_capacity,
                                         size_t *destination_size);

const char *retrofm_sjis_result_string(retrofm_sjis_result result);

#ifdef __cplusplus
}
#endif

#endif
