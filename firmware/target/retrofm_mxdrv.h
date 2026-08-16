/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RETROFM_MXDRV_H
#define RETROFM_MXDRV_H

#include "retrofm_event.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RETROFM_MXDRV_SOURCE_HZ 48000U
#define RETROFM_MXDRV_OUTPUT_HZ 48000U
/* X68Sound's 48 kHz path establishes the original FM/ADPCM coefficient.
 * With software FM removed, a modest +2.77 dB PCM trim restores the PDX
 * presence measured against JT51 without changing MDX register data. */
#define RETROFM_MXDRV_PCM_VOLUME 352

typedef bool (*retrofm_mxdrv_event_callback)(void *user,
                                             const retrofm_event *event);

typedef struct retrofm_mxdrv {
    void *driver_context;
    retrofm_mxdrv_event_callback event_callback;
    void *event_user;
    uint64_t source_samples;
    uint64_t last_event_cycles;
    bool callback_failed;
    bool initialized;
    bool terminated;
} retrofm_mxdrv;

bool retrofm_mxdrv_open(retrofm_mxdrv *driver,
                        const uint8_t *mdx_image,
                        size_t mdx_size,
                        const uint8_t *pdx_image,
                        size_t pdx_size,
                        retrofm_mxdrv_event_callback event_callback,
                        void *event_user);

bool retrofm_mxdrv_next_frame(retrofm_mxdrv *driver,
                              int16_t *left,
                              int16_t *right);

void retrofm_mxdrv_close(retrofm_mxdrv *driver);
bool retrofm_mxdrv_ended(const retrofm_mxdrv *driver);
bool retrofm_mxdrv_callback_failed(const retrofm_mxdrv *driver);
uint64_t retrofm_mxdrv_cycles(const retrofm_mxdrv *driver);
uint16_t retrofm_mxdrv_part_activity(const retrofm_mxdrv *driver,
                                     bool *pcm8_detected);
bool retrofm_mxdrv_part_meters(const retrofm_mxdrv *driver,
                               uint8_t volume[16],
                               uint16_t *current_mask,
                               uint16_t *trigger_mask,
                               bool *pcm8_detected);

#ifdef __cplusplus
}
#endif

#endif
