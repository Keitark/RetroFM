/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_hw.h"

#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) {                            \
    fprintf(stderr, "CHECK failed %s:%d: %s\n", __FILE__, __LINE__,         \
            #condition); return 1; } } while (0)

int main(void) {
    uint32_t registers[36];
    retrofm_hw hw;
    retrofm_event event;

    memset(registers, 0, sizeof(registers));
    hw.base = (uintptr_t)registers;
    event.delta_cycles = UINT32_C(0x12345678);
    event.opcode = RETROFM_OP_YM2203;
    event.reg = 0x28U;
    event.data = 0xF0U;
    event.flags = 0U;

    CHECK(retrofm_hw_event_push(&hw, &event));
    CHECK(registers[RETROFM_REG_EVENT_LO / 4U] == UINT32_C(0x12345678));
    CHECK(registers[RETROFM_REG_EVENT_HI / 4U] == UINT32_C(0x0001F028));
    registers[RETROFM_REG_EVENT_STATUS / 4U] = RETROFM_EVENT_FULL | 2048U;
    CHECK(!retrofm_hw_event_push(&hw, &event));
    CHECK(retrofm_hw_event_level(&hw) == 2048U);
    CHECK(!retrofm_hw_event_push(&hw, NULL));
    registers[RETROFM_REG_EVENT_STATUS / 4U] = 0U;
    event.flags = 1U;
    CHECK(!retrofm_hw_event_push(&hw, &event));
    event.flags = 0U;
    event.opcode = RETROFM_OP_YM2608;
    event.flags = RETROFM_EVENT_FLAG_OPNA_PORT1;
    CHECK(retrofm_hw_event_push(&hw, &event));
    CHECK(registers[RETROFM_REG_EVENT_HI / 4U] == UINT32_C(0x0014F028));
    event.flags = 2U;
    CHECK(!retrofm_hw_event_push(&hw, &event));
    event.flags = 0U;
    event.opcode = 7U;
    CHECK(!retrofm_hw_event_push(&hw, &event));

    registers[RETROFM_REG_PCM_STATUS / 4U] = 12U;
    CHECK(retrofm_hw_pcm_push(&hw, (int16_t)-2, (int16_t)3));
    CHECK(registers[RETROFM_REG_PCM_FRAME / 4U] == UINT32_C(0x0003FFFE));
    CHECK(retrofm_hw_pcm_level(&hw) == 12U);
    registers[RETROFM_REG_PCM_STATUS / 4U] = RETROFM_PCM_FULL;
    CHECK(!retrofm_hw_pcm_push(&hw, 0, 0));

    CHECK(retrofm_hw_latch_ym2203_clock(&hw, UINT32_C(4000000)));
    CHECK(registers[RETROFM_REG_YM2203_CLOCK / 4U] == UINT32_C(4000000));
    CHECK(registers[RETROFM_REG_COMMAND / 4U] == RETROFM_COMMAND_CORE_RESET);
    CHECK(!retrofm_hw_latch_ym2203_clock(&hw, 0U));
    CHECK(!retrofm_hw_latch_ym2203_clock(&hw, UINT32_C(10000001)));

    {
        const uint8_t sample_data[] = {0x11U, 0x22U, 0x33U, 0x44U, 0x55U};
        CHECK(retrofm_hw_opna_sample_upload(&hw, sample_data,
                                            (uint32_t)sizeof(sample_data)));
        CHECK(registers[RETROFM_REG_OPNA_SAMPLE_ADDR / 4U] == 0U);
        CHECK(registers[RETROFM_REG_OPNA_SAMPLE_DATA / 4U] == UINT32_C(0x00000055));
        CHECK(!retrofm_hw_opna_sample_upload(&hw, NULL, 1U));
        CHECK(!retrofm_hw_opna_sample_upload(&hw, sample_data, UINT32_C(131073)));
    }

    registers[RETROFM_REG_PLAY_CYCLES_LO / 4U] = UINT32_C(0x89ABCDEF);
    registers[RETROFM_REG_PLAY_CYCLES_HI / 4U] = UINT32_C(0x01234567);
    CHECK(retrofm_hw_playback_cycles(&hw) == UINT64_C(0x0123456789ABCDEF));
    registers[RETROFM_REG_EVENT_STATUS / 4U] =
        RETROFM_EVENT_COMMAND_CDC_FAULT | RETROFM_EVENT_HALTED |
        RETROFM_EVENT_COMMAND_BACKPRESSURE_SEEN;
    CHECK((retrofm_hw_read(&hw, RETROFM_REG_EVENT_STATUS) &
           RETROFM_EVENT_COMMAND_CDC_FAULT) != 0U);
    CHECK((retrofm_hw_read(&hw, RETROFM_REG_EVENT_STATUS) &
           RETROFM_EVENT_HALTED) != 0U);
    CHECK((retrofm_hw_read(&hw, RETROFM_REG_EVENT_STATUS) &
           RETROFM_EVENT_COMMAND_BACKPRESSURE_SEEN) != 0U);
    {
        uint8_t bins[32] = {0};
        uint8_t expected[32];
        unsigned word;
        for (word = 0U; word < 32U; ++word) expected[word] = (uint8_t)word;
        for (word = 0U; word < 8U; ++word) {
            registers[(RETROFM_REG_SPECTRUM_0 / 4U) + word] =
                UINT32_C(0x03020100) + word * UINT32_C(0x04040404);
        }
        retrofm_hw_spectrum(&hw, bins);
        CHECK(memcmp(bins, expected, sizeof(bins)) == 0);
    }
    {
        uint8_t volume[6] = {0};
        uint16_t trigger;
        registers[RETROFM_REG_JT03_METER_LO / 4U] = UINT32_C(0x44332211);
        registers[RETROFM_REG_JT03_METER_HI / 4U] = UINT32_C(0x002D6655);
        trigger = retrofm_hw_jt03_meters(&hw, volume);
        CHECK(volume[0] == 0x11U && volume[1] == 0x22U &&
              volume[2] == 0x33U && volume[3] == 0x44U &&
              volume[4] == 0x55U && volume[5] == 0x66U);
        CHECK(trigger == 0x2DU);
    }
    {
        uint8_t volume[11] = {0};
        uint16_t trigger;
        registers[RETROFM_REG_OPNA_METER_0 / 4U] = UINT32_C(0x44332211);
        registers[RETROFM_REG_OPNA_METER_1 / 4U] = UINT32_C(0x88776655);
        registers[RETROFM_REG_OPNA_METER_2 / 4U] = UINT32_C(0x00BBAA99);
        registers[RETROFM_REG_OPNA_METER_FLAGS / 4U] = UINT32_C(0x00000555);
        trigger = retrofm_hw_opna_meters(&hw, volume);
        CHECK(volume[0] == 0x11U && volume[1] == 0x22U &&
              volume[2] == 0x33U && volume[3] == 0x44U &&
              volume[4] == 0x55U && volume[5] == 0x66U &&
              volume[6] == 0x77U && volume[7] == 0x88U &&
              volume[8] == 0x99U && volume[9] == 0xAAU &&
              volume[10] == 0xBBU);
        CHECK(trigger == 0x555U);
    }
    puts("RetroFM MMIO contract tests passed");
    return 0;
}
