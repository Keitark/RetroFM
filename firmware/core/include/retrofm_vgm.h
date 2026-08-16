/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_VGM_H
#define RETROFM_VGM_H

#include "retrofm_event.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum retrofm_result {
    RETROFM_OK = 0,
    RETROFM_END,
    RETROFM_BAD_ARGUMENT,
    RETROFM_TRUNCATED,
    RETROFM_BAD_MAGIC,
    RETROFM_BAD_VERSION,
    RETROFM_BAD_HEADER,
    RETROFM_UNSUPPORTED_CHIP,
    RETROFM_MULTI_CHIP,
    RETROFM_BAD_CLOCK,
    RETROFM_UNSUPPORTED_COMMAND,
    RETROFM_BAD_LOOP,
    RETROFM_RANGE_ERROR
} retrofm_result;

typedef struct retrofm_vgm {
    const uint8_t *bytes;
    size_t size;
    size_t position;
    size_t data_start;
    size_t loop_position;
    uint32_t version;
    uint32_t ym2203_clock_hz;
    uint32_t ym2608_clock_hz;
    bool is_ym2608;
    uint32_t loop_count;
    uint64_t pending_cycles;
    size_t scan_budget;
    retrofm_timebase timebase;
    bool loop_enabled;
    bool has_loop;
    bool loop_target_seen;
    bool tracking_loop_progress;
    bool loop_time_progress;
    bool end_after_delay;
    bool loop_after_delay;
    bool ended;
} retrofm_vgm;

retrofm_result retrofm_vgm_open(retrofm_vgm *vgm,
                                const uint8_t *bytes,
                                size_t size,
                                bool loop_enabled);

retrofm_result retrofm_vgm_next(retrofm_vgm *vgm, retrofm_event *event);

retrofm_result retrofm_vgm_title(const retrofm_vgm *vgm,
                                 char *utf8,
                                 size_t capacity);

retrofm_result retrofm_vgm_artist(const retrofm_vgm *vgm,
                                  char *utf8,
                                  size_t capacity);

const char *retrofm_result_string(retrofm_result result);

#ifdef __cplusplus
}
#endif

#endif
