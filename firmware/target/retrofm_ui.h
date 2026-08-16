/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_UI_H
#define RETROFM_UI_H

#include "retrofm_st7789.h"

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct retrofm_ui_model {
    const char *title;
    const char *artist;
    const char *format;
    const char *state;
    const char *error;
    uint32_t elapsed_seconds;
    uint16_t event_level;
    uint16_t pcm_level;
    uint16_t peak_left;
    uint16_t peak_right;
    uint16_t part_activity;
    uint16_t part_current;
    uint16_t part_trigger;
    uint8_t part_volume[16];
    uint8_t part_count;
    bool part_meter_valid;
    uint8_t spectrum[32];
    uint8_t volume_step;
    bool fm_muted;
    uint32_t animation_ms;
} retrofm_ui_model;

typedef struct retrofm_ui {
    retrofm_lcd_io io;
    uint16_t pixels[RETROFM_LCD_WIDTH * RETROFM_LCD_HEIGHT];
    uint8_t spectrum_value[32];
    uint8_t spectrum_peak[32];
    uint8_t spectrum_hold[32];
    uint32_t spectrum_hold_until_ms[32];
    uint8_t part_level[16];
    uint8_t part_peak[16];
    uint8_t part_hold[16];
    uint16_t previous_part_activity;
    uint32_t part_last_update_ms;
    uint32_t part_kick_until_ms[16];
    uint32_t part_hold_until_ms[16];
    uint32_t title_signature;
    uint32_t artist_signature;
    uint32_t title_start_ms;
    uint32_t artist_start_ms;
} retrofm_ui;

bool retrofm_ui_init(retrofm_ui *ui, const retrofm_lcd_io *io);
bool retrofm_ui_prepare(retrofm_ui *ui, const retrofm_ui_model *model);
bool retrofm_ui_flush_rows(retrofm_ui *ui,
                           uint16_t first_row,
                           uint16_t row_count);
bool retrofm_ui_render(retrofm_ui *ui, const retrofm_ui_model *model);

#ifdef __cplusplus
}
#endif

#endif
