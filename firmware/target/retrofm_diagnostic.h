/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_DIAGNOSTIC_H
#define RETROFM_DIAGNOSTIC_H

#include "retrofm_event.h"

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Fixed, conservative JT51 bring-up tone. Channel 0 is left, channel 1 is
 * right, both use algorithm 7 with high TL attenuation. The sequence keys off
 * after 500 ms, leaves 50 ms for release, then emits END. */
size_t retrofm_diagnostic_event_count(void);
bool retrofm_diagnostic_event(size_t index, retrofm_event *event);

#ifdef __cplusplus
}
#endif

#endif
