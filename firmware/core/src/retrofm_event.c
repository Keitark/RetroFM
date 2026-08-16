/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_event.h"

uint64_t retrofm_event_pack(const retrofm_event *event) {
    uint64_t low;

    if (event == NULL || event->opcode > 15U || event->flags > 0x0FFFU) {
        return UINT64_C(0);
    }

    low = (uint64_t)event->delta_cycles |
          ((uint64_t)event->reg << 32U) |
          ((uint64_t)event->data << 40U) |
          ((uint64_t)event->opcode << 48U) |
          ((uint64_t)event->flags << 52U);
    return low;
}

bool retrofm_event_unpack(uint64_t packed, retrofm_event *event) {
    if (event == NULL) {
        return false;
    }

    event->delta_cycles = (uint32_t)packed;
    event->reg = (uint8_t)((packed >> 32U) & 0xFFU);
    event->data = (uint8_t)((packed >> 40U) & 0xFFU);
    event->opcode = (uint8_t)((packed >> 48U) & 0x0FU);
    event->flags = (uint16_t)((packed >> 52U) & 0x0FFFU);
    return true;
}

void retrofm_timebase_reset(retrofm_timebase *timebase) {
    if (timebase != NULL) {
        timebase->remainder = 0U;
    }
}

uint64_t retrofm_vgm_samples_to_cycles(retrofm_timebase *timebase,
                                       uint32_t samples) {
    uint64_t numerator;

    if (timebase == NULL) {
        return UINT64_C(0);
    }

    numerator = (uint64_t)samples * RETROFM_PL_CLOCK_HZ +
                (uint64_t)timebase->remainder;
    timebase->remainder = (uint32_t)(numerator % RETROFM_VGM_TICK_HZ);
    return numerator / RETROFM_VGM_TICK_HZ;
}
