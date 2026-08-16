/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_ui.h"
#include "retrofm_japanese_font.h"

#include <stddef.h>
#include <string.h>

enum {
    COLOR_BG = 0x0022,
    COLOR_PANEL = 0x0843,
    COLOR_FRAME = 0x31AC,
    COLOR_GRID = 0x10A5,
    COLOR_GRID_BRIGHT = 0x18E8,
    COLOR_TEXT = 0xD69D,
    COLOR_TEXT_MUTED = 0x94B6,
    COLOR_PEAK = 0xD69E,
    COLOR_HOLD = 0xF7BF,
    COLOR_BAR_1 = 0x28ED,
    COLOR_BAR_2 = 0x4231,
    COLOR_BAR_3 = 0x6B76,
    COLOR_BAR_4 = 0x94BA,
    COLOR_SPEC_1 = 0x4292,
    COLOR_SPEC_2 = 0x6BD7,
    COLOR_SPEC_3 = 0x955C,
    COLOR_ERROR = 0xF22A
};

static const uint8_t *glyph(char value) {
    static const uint8_t blank[5] = {0, 0, 0, 0, 0};
    static const uint8_t unknown[5] = {0x02, 0x01, 0x59, 0x09, 0x06};
    static const uint8_t digits[10][5] = {
        {0x3E,0x51,0x49,0x45,0x3E}, {0x00,0x42,0x7F,0x40,0x00},
        {0x42,0x61,0x51,0x49,0x46}, {0x21,0x41,0x45,0x4B,0x31},
        {0x18,0x14,0x12,0x7F,0x10}, {0x27,0x45,0x45,0x45,0x39},
        {0x3C,0x4A,0x49,0x49,0x30}, {0x01,0x71,0x09,0x05,0x03},
        {0x36,0x49,0x49,0x49,0x36}, {0x06,0x49,0x49,0x29,0x1E}
    };
    static const uint8_t letters[26][5] = {
        {0x7E,0x11,0x11,0x11,0x7E}, {0x7F,0x49,0x49,0x49,0x36},
        {0x3E,0x41,0x41,0x41,0x22}, {0x7F,0x41,0x41,0x22,0x1C},
        {0x7F,0x49,0x49,0x49,0x41}, {0x7F,0x09,0x09,0x09,0x01},
        {0x3E,0x41,0x49,0x49,0x7A}, {0x7F,0x08,0x08,0x08,0x7F},
        {0x00,0x41,0x7F,0x41,0x00}, {0x20,0x40,0x41,0x3F,0x01},
        {0x7F,0x08,0x14,0x22,0x41}, {0x7F,0x40,0x40,0x40,0x40},
        {0x7F,0x02,0x0C,0x02,0x7F}, {0x7F,0x04,0x08,0x10,0x7F},
        {0x3E,0x41,0x41,0x41,0x3E}, {0x7F,0x09,0x09,0x09,0x06},
        {0x3E,0x41,0x51,0x21,0x5E}, {0x7F,0x09,0x19,0x29,0x46},
        {0x46,0x49,0x49,0x49,0x31}, {0x01,0x01,0x7F,0x01,0x01},
        {0x3F,0x40,0x40,0x40,0x3F}, {0x1F,0x20,0x40,0x20,0x1F},
        {0x3F,0x40,0x38,0x40,0x3F}, {0x63,0x14,0x08,0x14,0x63},
        {0x07,0x08,0x70,0x08,0x07}, {0x61,0x51,0x49,0x45,0x43}
    };
    static const uint8_t colon[5] = {0,0x36,0x36,0,0};
    static const uint8_t slash[5] = {0x20,0x10,0x08,0x04,0x02};
    static const uint8_t dash[5] = {0x08,0x08,0x08,0x08,0x08};
    static const uint8_t dot[5] = {0,0x60,0x60,0,0};
    static const uint8_t percent[5] = {0x23,0x13,0x08,0x64,0x62};

    if (value >= 'a' && value <= 'z') value = (char)(value - 'a' + 'A');
    if (value >= '0' && value <= '9') return digits[value - '0'];
    if (value >= 'A' && value <= 'Z') return letters[value - 'A'];
    if (value == ' ') return blank;
    if (value == ':') return colon;
    if (value == '/') return slash;
    if (value == '-') return dash;
    if (value == '.') return dot;
    if (value == '%') return percent;
    return unknown;
}

static void fill_rect(retrofm_ui *ui, uint16_t x, uint16_t y,
                      uint16_t width, uint16_t height, uint16_t color) {
    uint16_t row;
    uint16_t column;
    if ((uint32_t)x + width > RETROFM_LCD_WIDTH ||
        (uint32_t)y + height > RETROFM_LCD_HEIGHT) return;
    for (row = 0U; row < height; ++row) {
        for (column = 0U; column < width; ++column) {
            ui->pixels[(size_t)(y + row) * RETROFM_LCD_WIDTH + x + column] =
                color;
        }
    }
}

static void draw_character(retrofm_ui *ui, uint16_t x, uint16_t y,
                           char value, uint16_t color, uint8_t scale) {
    const uint8_t *columns = glyph(value);
    uint8_t column;
    uint8_t row;
    for (column = 0U; column < 5U; ++column) {
        for (row = 0U; row < 7U; ++row) {
            if ((columns[column] & (uint8_t)(1U << row)) != 0U) {
                fill_rect(ui,
                          (uint16_t)(x + column * scale),
                          (uint16_t)(y + row * scale),
                          scale, scale, color);
            }
        }
    }
}

static void draw_text(retrofm_ui *ui, uint16_t x, uint16_t y,
                      const char *text, size_t maximum,
                      uint16_t color, uint8_t scale) {
    size_t used = 0U;
    uint16_t cursor = x;
    while (text != NULL && *text != '\0' && used < maximum) {
        unsigned char byte = (unsigned char)*text++;
        char shown;
        if (byte < 0x80U) {
            shown = (char)byte;
        } else {
            while (((unsigned char)*text & 0xC0U) == 0x80U) ++text;
            shown = '?';
        }
        if ((uint32_t)cursor + 5U * scale >= RETROFM_LCD_WIDTH) break;
        draw_character(ui, cursor, y, shown, color, scale);
        cursor = (uint16_t)(cursor + 6U * scale);
        ++used;
    }
}

static void draw_number(retrofm_ui *ui, uint16_t x, uint16_t y,
                        uint32_t value, uint8_t digits, uint16_t color) {
    uint32_t divisor = 1U;
    uint8_t index;
    for (index = 1U; index < digits; ++index) divisor *= 10U;
    for (index = 0U; index < digits; ++index) {
        draw_character(ui, (uint16_t)(x + index * 6U), y,
                       (char)('0' + (value / divisor) % 10U), color, 1U);
        divisor /= 10U;
    }
}

static uint32_t text_signature(const char *text) {
    uint32_t value = UINT32_C(2166136261);
    if (text == NULL) return 0U;
    while (*text != '\0') {
        value ^= (uint8_t)*text++;
        value *= UINT32_C(16777619);
    }
    return value;
}

static void draw_marquee(retrofm_ui *ui,
                          const char *text,
                          int y,
                          int left,
                          int right,
                          uint32_t now_ms,
                          uint32_t *signature,
                          uint32_t *start_ms,
                          uint16_t color) {
    uint32_t current_signature = text_signature(text);
    int text_width;
    int area_width = right - left;
    int draw_x = left;
    if (text == NULL || *text == '\0' || area_width <= 0) return;
    if (*signature != current_signature) {
        *signature = current_signature;
        *start_ms = now_ms;
    }
    text_width = retrofm_japanese_measure_utf8(text, 96U);
    if (text_width > area_width) {
        const uint32_t wait_ms = 1000U;
        const uint32_t pixels_per_second = 30U;
        const int gap = 24;
        uint32_t scroll_ms =
            (uint32_t)(((uint64_t)(text_width + gap) * 1000U) /
                       pixels_per_second);
        uint32_t cycle_ms = wait_ms + scroll_ms + wait_ms;
        uint32_t elapsed = now_ms - *start_ms;
        uint32_t phase = cycle_ms != 0U ? elapsed % cycle_ms : 0U;
        if (phase >= wait_ms && phase < wait_ms + scroll_ms) {
            uint32_t scroll_phase = phase - wait_ms;
            draw_x -= (int)((scroll_phase * pixels_per_second) / 1000U);
        }
        (void)retrofm_japanese_draw_utf8_clipped(
            ui->pixels, RETROFM_LCD_WIDTH, RETROFM_LCD_HEIGHT,
            draw_x, y, left, right, text, 96U, color);
        (void)retrofm_japanese_draw_utf8_clipped(
            ui->pixels, RETROFM_LCD_WIDTH, RETROFM_LCD_HEIGHT,
            draw_x + text_width + gap, y, left, right, text, 96U, color);
    } else {
        (void)retrofm_japanese_draw_utf8_clipped(
            ui->pixels, RETROFM_LCD_WIDTH, RETROFM_LCD_HEIGHT,
            draw_x, y, left, right, text, 96U, color);
    }
}

static uint8_t approach_level(uint8_t previous, uint8_t target,
                              unsigned rise_q8, unsigned fall_q8) {
    unsigned amount;
    if (target == previous) return previous;
    if (target > previous) {
        unsigned difference = (unsigned)target - previous;
        amount = (difference * rise_q8 + 128U) >> 8U;
        if (amount == 0U) amount = 1U;
        if (amount > difference) amount = difference;
        return (uint8_t)(previous + amount);
    }
    {
        unsigned difference = (unsigned)previous - target;
        amount = (difference * fall_q8 + 128U) >> 8U;
        if (amount == 0U) amount = 1U;
        if (amount > difference) amount = difference;
        return (uint8_t)(previous - amount);
    }
}

static bool time_before(uint32_t now_ms, uint32_t deadline_ms) {
    return (int32_t)(deadline_ms - now_ms) > 0;
}

static uint8_t decay_90_percent(uint8_t value) {
    return (uint8_t)(((unsigned)value * 230U + 128U) >> 8U);
}

static uint8_t decay_ratio(uint8_t value, unsigned numerator,
                           unsigned denominator, unsigned steps) {
    while (steps-- != 0U && value != 0U) {
        value = (uint8_t)(((unsigned)value * numerator) / denominator);
    }
    return value;
}

/* The PL already supplies a logarithmic Goertzel magnitude.  A direct linear
 * mapping of that 0..255 code into sixteen display cells leaves ordinary FM
 * material concentrated in the bottom few cells.  Apply a display-only
 * square-root gamma curve: it preserves zero and full scale while expanding
 * useful mid-level motion.  This is deliberately not an audio gain change. */
static uint8_t spectrum_display_level(uint8_t logarithmic_magnitude) {
    uint32_t radicand = (uint32_t)logarithmic_magnitude * UINT32_C(255);
    uint16_t low = 0U;
    uint16_t high = UINT8_MAX;
    while (low < high) {
        uint16_t middle = (uint16_t)((low + high + 1U) >> 1U);
        if ((uint32_t)middle * middle <= radicand) {
            low = middle;
        } else {
            high = (uint16_t)(middle - 1U);
        }
    }
    return (uint8_t)low;
}

static uint16_t spectrum_color(unsigned segment) {
    if (segment < 6U) return COLOR_SPEC_1;
    if (segment < 11U) return COLOR_SPEC_2;
    return COLOR_SPEC_3;
}

static uint16_t part_color(unsigned segment) {
    if (segment < 2U) return COLOR_BAR_1;
    if (segment < 5U) return COLOR_BAR_2;
    if (segment < 7U) return COLOR_BAR_3;
    return COLOR_BAR_4;
}

static void update_visual_levels(retrofm_ui *ui,
                                 const retrofm_ui_model *model) {
    unsigned index;
    for (index = 0U; index < 32U; ++index) {
        uint8_t value = approach_level(ui->spectrum_value[index],
                                       spectrum_display_level(
                                           model->spectrum[index]),
                                       179U, 64U);
        ui->spectrum_value[index] = value;
        ui->spectrum_peak[index] = approach_level(
            ui->spectrum_peak[index], value, 154U, 64U);
        if (ui->spectrum_peak[index] >= ui->spectrum_hold[index]) {
            ui->spectrum_hold[index] = ui->spectrum_peak[index];
            ui->spectrum_hold_until_ms[index] = model->animation_ms + 120U;
        } else if (!time_before(model->animation_ms,
                                ui->spectrum_hold_until_ms[index])) {
            ui->spectrum_hold[index] = decay_90_percent(
                ui->spectrum_hold[index]);
        }
    }
    if (model->part_meter_valid) {
        uint32_t elapsed = ui->part_last_update_ms == 0U ? 0U :
                           model->animation_ms - ui->part_last_update_ms;
        unsigned decay_steps = (unsigned)((elapsed + 5U) / 10U);
        if (decay_steps > 100U) decay_steps = 100U;
        for (index = 0U; index < 16U; ++index) {
            uint16_t mask = (uint16_t)(1U << index);
            if ((model->part_trigger & mask) != 0U) {
                /* MXDRV's own example meter: a note-on captures the channel
                 * volume into both the bright bar and its dim afterglow. */
                ui->part_level[index] = model->part_volume[index];
                ui->part_peak[index] = model->part_volume[index];
            } else {
                ui->part_level[index] = decay_ratio(
                    ui->part_level[index], 31U, 32U, decay_steps);
                if ((model->part_current & mask) == 0U) {
                    ui->part_peak[index] = decay_ratio(
                        ui->part_peak[index], 127U, 128U, decay_steps);
                }
            }
            ui->part_hold[index] = 0U;
        }
        ui->part_last_update_ms = model->animation_ms;
        ui->previous_part_activity = model->part_current;
        return;
    }

    for (index = 0U; index < 16U; ++index) {
        uint16_t mask = (uint16_t)(1U << index);
        bool active = (model->part_activity & mask) != 0U;
        bool was_active = (ui->previous_part_activity & mask) != 0U;
        uint8_t target = active ? 166U : 0U;
        if (active && !was_active) {
            uint32_t kick_ms = model->part_count == 6U && index >= 3U ?
                               60U : 80U;
            ui->part_kick_until_ms[index] = model->animation_ms + kick_ms;
        }
        if (active && time_before(model->animation_ms,
                                  ui->part_kick_until_ms[index])) {
            unsigned kick = model->part_count == 6U && index >= 3U ?
                            38U : 51U;
            target = (uint8_t)(target + kick);
        }
        ui->part_level[index] = approach_level(
            ui->part_level[index], target, 192U, 64U);
        ui->part_peak[index] = approach_level(
            ui->part_peak[index], ui->part_level[index], 141U, 51U);
        if (ui->part_peak[index] >= ui->part_hold[index]) {
            ui->part_hold[index] = ui->part_peak[index];
            ui->part_hold_until_ms[index] = model->animation_ms + 120U;
        } else if (!time_before(model->animation_ms,
                                ui->part_hold_until_ms[index])) {
            ui->part_hold[index] = decay_90_percent(
                ui->part_hold[index]);
        }
    }
    ui->previous_part_activity = model->part_activity;
}

static void draw_spectrum(retrofm_ui *ui) {
    unsigned column;
    fill_rect(ui, 4U, 58U, 232U, 94U, COLOR_PANEL);
    for (column = 0U; column <= 32U; column += 4U) {
        uint16_t x = (uint16_t)(6U + column * 7U);
        if (x < 235U) fill_rect(ui, x, 59U, 1U, 92U, COLOR_GRID);
    }
    for (column = 0U; column < 32U; ++column) {
        uint16_t x = (uint16_t)(7U + column * 7U);
        unsigned segment;
        unsigned filled = ((unsigned)ui->spectrum_value[column] * 16U +
                           254U) / 255U;
        unsigned peak = ((unsigned)ui->spectrum_peak[column] * 16U) / 255U;
        unsigned hold = ((unsigned)ui->spectrum_hold[column] * 16U) / 255U;
        for (segment = 0U; segment < 16U; ++segment) {
            uint16_t y = (uint16_t)(145U - segment * 5U);
            if (segment < filled) {
                fill_rect(ui, x, y, 5U, 4U, spectrum_color(segment));
            }
        }
        if (peak != 0U) {
            uint16_t y = (uint16_t)(150U - peak * 5U);
            fill_rect(ui, x, y, 5U, 1U, COLOR_PEAK);
        }
        if (hold != 0U) {
            uint16_t y = (uint16_t)(150U - hold * 5U);
            fill_rect(ui, x, y, 5U, 1U, COLOR_HOLD);
        }
    }
}

static void draw_parts(retrofm_ui *ui, const retrofm_ui_model *model) {
    static const char *const fm_labels[8] = {
        "FM1", "FM2", "FM3", "FM4", "FM5", "FM6", "FM7", "FM8"
    };
    static const char *const opn_labels[6] = {
        "FM1", "FM2", "FM3", "S1", "S2", "S3"
    };
    static const char *const pcm_labels[8] = {
        "P08", "P09", "P10", "P11", "P12", "P13", "P14", "P15"
    };
    unsigned count = model->part_count;
    unsigned rows;
    unsigned per_row;
    unsigned row;
    if (count != 6U && count != 8U && count != 16U) count = 8U;
    rows = count > 8U ? 2U : 1U;
    per_row = count > 8U ? 8U : count;
    if (per_row == 0U) per_row = 1U;
    fill_rect(ui, 4U, 158U, 232U, 64U, COLOR_PANEL);
    for (row = 0U; row < rows; ++row) {
        unsigned item;
        uint16_t row_y = (uint16_t)(161U + row * 31U);
        uint16_t bar_height = rows == 2U ? 18U : 42U;
        uint16_t gap = rows == 2U ? 4U : 6U;
        uint16_t bar_width = (uint16_t)((224U - gap * (per_row - 1U)) /
                                        per_row);
        for (item = 0U; item < per_row; ++item) {
            unsigned index = row * 8U + item;
            uint16_t x = (uint16_t)(8U + item * (bar_width + gap));
            unsigned segment;
            unsigned filled = ((unsigned)ui->part_level[index] * 8U +
                               254U) / 255U;
            unsigned peak = ((unsigned)ui->part_peak[index] * 8U) / 255U;
            unsigned hold = ((unsigned)ui->part_hold[index] * 8U) / 255U;
            for (segment = 0U; segment < 8U; ++segment) {
                uint16_t segment_height = (uint16_t)(bar_height / 8U);
                uint16_t y = (uint16_t)(row_y + bar_height -
                                        (segment + 1U) * segment_height);
                fill_rect(ui, x, y, bar_width, 1U, COLOR_GRID);
                if (model->part_meter_valid && segment < peak &&
                    segment_height > 1U) {
                    fill_rect(ui, x, (uint16_t)(y + 1U), bar_width,
                              (uint16_t)(segment_height - 1U),
                              COLOR_GRID_BRIGHT);
                }
                if (segment < filled && segment_height > 1U) {
                    fill_rect(ui, x, (uint16_t)(y + 1U), bar_width,
                              (uint16_t)(segment_height - 1U),
                              part_color(segment));
                }
            }
            if (!model->part_meter_valid && peak != 0U) {
                uint16_t y = (uint16_t)(row_y + bar_height -
                                        peak * (bar_height / 8U));
                fill_rect(ui, x, y, bar_width, 1U, COLOR_PEAK);
            }
            if (hold != 0U) {
                uint16_t y = (uint16_t)(row_y + bar_height -
                                        hold * (bar_height / 8U));
                fill_rect(ui, x, y, bar_width, 1U, COLOR_HOLD);
            }
            if (rows == 2U) {
                const char *label = row == 0U ? fm_labels[item] :
                                               pcm_labels[item];
                draw_text(ui, x, (uint16_t)(row_y + bar_height + 1U),
                          label, 3U, COLOR_TEXT_MUTED, 1U);
            } else if (count == 6U) {
                draw_text(ui, x, 208U, opn_labels[item], 3U,
                          COLOR_TEXT_MUTED, 1U);
            } else {
                draw_text(ui, x, 208U, fm_labels[item], 3U,
                          COLOR_TEXT_MUTED, 1U);
            }
        }
    }
}

bool retrofm_ui_init(retrofm_ui *ui, const retrofm_lcd_io *io) {
    if (ui == NULL || io == NULL) return false;
    memset(ui, 0, sizeof(*ui));
    ui->io = *io;
    return retrofm_st7789_init(&ui->io) &&
           retrofm_st7789_fill(&ui->io, COLOR_BG);
}

bool retrofm_ui_prepare(retrofm_ui *ui, const retrofm_ui_model *model) {
    if (ui == NULL || model == NULL) return false;
    update_visual_levels(ui, model);
    fill_rect(ui, 0U, 0U, RETROFM_LCD_WIDTH, RETROFM_LCD_HEIGHT, COLOR_BG);

    fill_rect(ui, 0U, 0U, RETROFM_LCD_WIDTH, 22U, COLOR_PANEL);
    fill_rect(ui, 0U, 21U, RETROFM_LCD_WIDTH, 1U, COLOR_FRAME);
    draw_text(ui, 4U, 5U, "RETROFM", 7U, COLOR_TEXT, 1U);
    draw_text(ui, 54U, 5U, model->state, 10U,
              model->error != NULL ? COLOR_ERROR : COLOR_TEXT_MUTED, 1U);
    if (model->fm_muted) {
        fill_rect(ui, 126U, 3U, 56U, 16U, COLOR_ERROR);
        draw_text(ui, 131U, 7U, "FM OFF", 6U, COLOR_BG, 1U);
    }
    fill_rect(ui, 188U, 3U, 48U, 16U, COLOR_GRID_BRIGHT);
    draw_text(ui, 192U, 7U, "VOL", 3U, COLOR_TEXT_MUTED, 1U);
    draw_number(ui, 214U, 7U,
                ((uint32_t)model->volume_step * 100U) / 16U,
                3U, COLOR_TEXT);

    draw_marquee(ui, model->title, 26, 4, 236, model->animation_ms,
                  &ui->title_signature, &ui->title_start_ms, COLOR_TEXT);
    draw_marquee(ui, model->artist, 41, 4, 236, model->animation_ms,
                  &ui->artist_signature, &ui->artist_start_ms,
                  COLOR_TEXT_MUTED);

    draw_spectrum(ui);
    fill_rect(ui, 0U, 154U, RETROFM_LCD_WIDTH, 2U, COLOR_GRID_BRIGHT);
    draw_parts(ui, model);

    fill_rect(ui, 0U, 225U, RETROFM_LCD_WIDTH, 15U, COLOR_PANEL);
    draw_number(ui, 4U, 229U, model->elapsed_seconds / 60U, 3U,
                COLOR_TEXT_MUTED);
    draw_character(ui, 22U, 229U, ':', COLOR_TEXT_MUTED, 1U);
    draw_number(ui, 28U, 229U, model->elapsed_seconds % 60U, 2U,
                COLOR_TEXT_MUTED);
    draw_text(ui, 52U, 229U, model->format, 28U, COLOR_TEXT_MUTED, 1U);

    if (model->error != NULL) {
        fill_rect(ui, 4U, 78U, 232U, 54U, COLOR_PANEL);
        fill_rect(ui, 4U, 78U, 232U, 1U, COLOR_ERROR);
        fill_rect(ui, 4U, 131U, 232U, 1U, COLOR_ERROR);
        draw_text(ui, 10U, 88U, "PLAYER ERROR", 12U, COLOR_ERROR, 2U);
        draw_text(ui, 10U, 113U, model->error, 35U, COLOR_TEXT, 1U);
    }

    return true;
}

bool retrofm_ui_flush_rows(retrofm_ui *ui,
                           uint16_t first_row,
                           uint16_t row_count) {
    if (ui == NULL || row_count == 0U ||
        (uint32_t)first_row + row_count > RETROFM_LCD_HEIGHT) return false;
    return retrofm_st7789_set_window(&ui->io, 0U, first_row,
                                      RETROFM_LCD_WIDTH, row_count) &&
           retrofm_st7789_write_pixels(
               &ui->io,
               ui->pixels + (size_t)first_row * RETROFM_LCD_WIDTH,
               (size_t)row_count * RETROFM_LCD_WIDTH);
}

bool retrofm_ui_render(retrofm_ui *ui, const retrofm_ui_model *model) {
    return retrofm_ui_prepare(ui, model) &&
           retrofm_ui_flush_rows(ui, 0U, RETROFM_LCD_HEIGHT);
}
