/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_diagnostic.h"

#include <stdio.h>

#define CHECK(condition) do { if (!(condition)) {                            \
    fprintf(stderr, "CHECK failed %s:%d: %s\n", __FILE__, __LINE__,         \
            #condition); return 1; } } while (0)

int main(void) {
    size_t count = retrofm_diagnostic_event_count();
    size_t index;
    uint64_t duration = 0U;
    unsigned left_pan = 0U;
    unsigned right_pan = 0U;
    unsigned key_on = 0U;
    unsigned key_off = 0U;
    retrofm_event event = {0};

    CHECK(count > 50U);
    for (index = 0U; index < count; ++index) {
        CHECK(retrofm_diagnostic_event(index, &event));
        CHECK(event.flags == 0U);
        duration += event.delta_cycles;
        if (event.opcode == RETROFM_OP_YM2151 && event.reg == 0x20U &&
            (event.data & 0xC0U) == 0x80U) ++left_pan;
        if (event.opcode == RETROFM_OP_YM2151 && event.reg == 0x21U &&
            (event.data & 0xC0U) == 0x40U) ++right_pan;
        if (event.opcode == RETROFM_OP_YM2151 && event.reg == 0x08U) {
            if ((event.data & 0x78U) != 0U) ++key_on;
            else ++key_off;
        }
    }
    CHECK(duration == UINT64_C(55000000));
    CHECK(left_pan == 1U && right_pan == 1U);
    CHECK(key_on == 2U && key_off == 2U);
    CHECK(event.opcode == RETROFM_OP_END);
    CHECK(!retrofm_diagnostic_event(count, &event));
    puts("RetroFM JT51 diagnostic-tone trace tests passed");
    return 0;
}
