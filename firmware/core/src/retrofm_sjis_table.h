/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Keitark */

#ifndef RETROFM_SJIS_TABLE_H
#define RETROFM_SJIS_TABLE_H

#include <stddef.h>
#include <stdint.h>

typedef struct retrofm_sjis_map {
    uint16_t sjis;
    uint16_t unicode;
} retrofm_sjis_map;

extern const retrofm_sjis_map retrofm_sjis_table[];
extern const size_t retrofm_sjis_table_size;

#endif
