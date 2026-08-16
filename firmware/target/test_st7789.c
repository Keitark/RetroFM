/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_st7789.h"
#include "retrofm_ui.h"

#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) {                            \
    fprintf(stderr, "CHECK failed %s:%d: %s\n", __FILE__, __LINE__,         \
            #condition); return 1; } } while (0)

typedef struct mock_lcd {
    uint8_t bytes[256];
    uint8_t dc[256];
    size_t used;
    uint32_t delays[8];
    size_t delay_count;
    bool selected;
    bool reset;
    bool data_mode;
} mock_lcd;

static bool select_lcd(void *context, bool selected) {
    ((mock_lcd *)context)->selected = selected;
    return true;
}

static bool set_dc(void *context, bool data_mode) {
    ((mock_lcd *)context)->data_mode = data_mode;
    return true;
}

static bool set_reset(void *context, bool high) {
    ((mock_lcd *)context)->reset = high;
    return true;
}

static bool write_lcd(void *context, const uint8_t *bytes, size_t amount) {
    mock_lcd *mock = (mock_lcd *)context;
    size_t index;
    if (amount > sizeof(mock->bytes) - mock->used) return false;
    for (index = 0U; index < amount; ++index) {
        mock->bytes[mock->used] = bytes[index];
        mock->dc[mock->used] = mock->data_mode ? 1U : 0U;
        ++mock->used;
    }
    return true;
}

static void delay_ms(void *context, uint32_t amount) {
    mock_lcd *mock = (mock_lcd *)context;
    if (mock->delay_count < sizeof(mock->delays) / sizeof(mock->delays[0])) {
        mock->delays[mock->delay_count++] = amount;
    }
}

int main(void) {
    mock_lcd mock;
    retrofm_lcd_io io;
    const uint8_t commands[] = {
        0x36, 0x3A, 0xB2, 0xB7, 0xBB, 0xC0, 0xC2, 0xC3,
        0xC4, 0xC6, 0xD0, 0xE0, 0xE1, 0x21, 0x11, 0x29,
        0x2A, 0x2B, 0x2C
    };
    size_t command_index = 0U;
    size_t index;
    static retrofm_ui ui;
    static uint16_t ascii_title[RETROFM_LCD_WIDTH * 18U];
    static uint16_t japanese_title[RETROFM_LCD_WIDTH * 18U];
    retrofm_ui_model model;

    memset(&mock, 0, sizeof(mock));
    io.context = &mock;
    io.select = select_lcd;
    io.set_dc = set_dc;
    io.set_reset = set_reset;
    io.write = write_lcd;
    io.delay_ms = delay_ms;

    CHECK(retrofm_st7789_init(&io));
    CHECK(mock.selected);
    CHECK(mock.reset);
    CHECK(mock.delay_count == 5U);
    CHECK(mock.delays[0] == 1U && mock.delays[1] == 1U);
    CHECK(mock.delays[2] == 120U && mock.delays[3] == 120U);
    CHECK(mock.delays[4] == 20U);
    for (index = 0U; index < mock.used; ++index) {
        if (mock.dc[index] == 0U) {
            CHECK(command_index < sizeof(commands));
            CHECK(mock.bytes[index] == commands[command_index]);
            ++command_index;
        }
    }
    CHECK(command_index == sizeof(commands));
    CHECK(!retrofm_st7789_set_window(&io, 239U, 239U, 2U, 1U));
    memset(&model, 0, sizeof(model));
    model.title = "TEST";
    model.artist = "RETROFM PROJECT";
    model.format = "MDX / YM2151";
    model.state = "PLAYING";
    model.part_count = 8U;
    model.part_activity = 1U;
    model.spectrum[0] = 255U;
    model.spectrum[1] = 64U;
    model.animation_ms = 1000U;
    CHECK(retrofm_ui_prepare(&ui, &model));
    /* Fixed-point equivalents of the original M5StickS3 visualizer:
     * spectrum 0.70 attack, peak 0.60 attack, part 0.75 attack from a
     * 0.65 + 0.20 key-on kick, and 120 ms peak holds. */
    CHECK(ui.spectrum_value[0] == 178U);
    /* sqrt(64 * 255) = 127: the display-only gamma curve makes normal
     * musical levels use the formerly empty upper spectrum area. */
    CHECK(ui.spectrum_value[1] == 89U);
    CHECK(ui.spectrum_peak[0] == 107U);
    CHECK(ui.spectrum_hold[0] == 107U);
    CHECK(ui.spectrum_hold_until_ms[0] == 1120U);
    CHECK(ui.part_level[0] == 163U);
    CHECK(ui.part_peak[0] == 90U);
    CHECK(ui.part_hold[0] == 90U);
    CHECK(ui.part_kick_until_ms[0] == 1080U);
    CHECK(ui.part_hold_until_ms[0] == 1120U);
    model.part_meter_valid = true;
    model.part_trigger = 1U;
    model.part_current = 1U;
    model.part_volume[0] = 255U;
    model.animation_ms = 2000U;
    CHECK(retrofm_ui_prepare(&ui, &model));
    CHECK(ui.part_level[0] == 255U);
    CHECK(ui.part_peak[0] == 255U);
    model.part_trigger = 0U;
    model.part_current = 0U;
    model.animation_ms = 2030U;
    CHECK(retrofm_ui_prepare(&ui, &model));
    /* MXDRV example ratios normalized to the elapsed 30 ms. */
    CHECK(ui.part_level[0] == 231U);
    CHECK(ui.part_peak[0] == 249U);
    memcpy(ascii_title,
           &ui.pixels[30U * RETROFM_LCD_WIDTH],
           sizeof(ascii_title));
    CHECK(ui.pixels[175U * RETROFM_LCD_WIDTH + 10U] !=
          ui.pixels[175U * RETROFM_LCD_WIDTH + 38U]);
    /* UTF-8 for three Japanese Katakana glyphs. */
    model.title = "\xE3\x83\x86\xE3\x82\xB9\xE3\x83\x88";
    CHECK(retrofm_ui_prepare(&ui, &model));
    CHECK(memcmp(ascii_title,
                 &ui.pixels[30U * RETROFM_LCD_WIDTH],
                 sizeof(ascii_title)) != 0);
    memcpy(japanese_title,
           &ui.pixels[30U * RETROFM_LCD_WIDTH],
           sizeof(japanese_title));
    model.title = "???";
    CHECK(retrofm_ui_prepare(&ui, &model));
    CHECK(memcmp(japanese_title,
                 &ui.pixels[30U * RETROFM_LCD_WIDTH],
                 sizeof(japanese_title)) != 0);
    puts("ST7789 command-table test passed");
    return 0;
}
