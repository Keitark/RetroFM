/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_EVENT_H
#define RETROFM_EVENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum retrofm_opcode {
    RETROFM_OP_YM2151 = 0,
    RETROFM_OP_YM2203 = 1,
    RETROFM_OP_DELAY = 2,
    RETROFM_OP_END = 3,
    /* YM2608/OPNA.  flags bit 0 selects the second register port. */
    RETROFM_OP_YM2608 = 4,
    RETROFM_OP_DIAGNOSTIC = 15
};

enum {
    RETROFM_EVENT_FLAG_OPNA_PORT1 = 1U << 0
};

typedef struct retrofm_event {
    uint32_t delta_cycles;
    uint8_t opcode;
    uint8_t reg;
    uint8_t data;
    uint16_t flags;
} retrofm_event;

typedef struct retrofm_timebase {
    uint32_t remainder;
} retrofm_timebase;

#define RETROFM_PL_CLOCK_HZ UINT32_C(100000000)
#define RETROFM_VGM_TICK_HZ UINT32_C(44100)

uint64_t retrofm_event_pack(const retrofm_event *event);
bool retrofm_event_unpack(uint64_t packed, retrofm_event *event);

void retrofm_timebase_reset(retrofm_timebase *timebase);
uint64_t retrofm_vgm_samples_to_cycles(retrofm_timebase *timebase,
                                       uint32_t samples);

#ifdef __cplusplus
}
#endif

#endif
