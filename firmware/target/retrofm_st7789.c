/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_st7789.h"

typedef struct lcd_init_step {
    uint8_t command;
    uint8_t length;
    uint8_t data[14];
    uint16_t delay_ms;
} lcd_init_step;

/*
 * ST7789 initialization values follow the verified EBAZ4205 adapter source in
 * tomorrow56/EBAZ4205_tutorial, commit
 * ad2f97c881b06ae54d132e37675aac8543c28917. That source is MIT-licensed,
 * Copyright (c) 2025 tomorrow56 A.K.A. ThousanDIY; see THIRD_PARTY_NOTICES.md.
 * The values are expressed here as command records for the RetroFM transport.
 */
static const lcd_init_step init_steps[] = {
    {0x36, 1, {0x00}, 0},
    {0x3A, 1, {0x55}, 0},
    {0xB2, 5, {0x0C, 0x0C, 0x00, 0x33, 0x33}, 0},
    {0xB7, 1, {0x35}, 0},
    {0xBB, 1, {0x19}, 0},
    {0xC0, 1, {0x2C}, 0},
    {0xC2, 2, {0x01, 0xFF}, 0},
    {0xC3, 1, {0x12}, 0},
    {0xC4, 1, {0x20}, 0},
    {0xC6, 1, {0x0F}, 0},
    {0xD0, 2, {0xA4, 0xA1}, 0},
    {0xE0, 14, {0xD0, 0x04, 0x0D, 0x11, 0x13, 0x2B, 0x3F,
                0x54, 0x4C, 0x18, 0x0D, 0x0B, 0x1F, 0x23}, 0},
    {0xE1, 14, {0xD0, 0x04, 0x0C, 0x11, 0x13, 0x2C, 0x3F,
                0x44, 0x51, 0x2F, 0x1F, 0x1F, 0x20, 0x23}, 0},
    {0x21, 0, {0}, 0},
    {0x11, 0, {0}, 120},
    {0x29, 0, {0}, 20},
};

static bool io_valid(const retrofm_lcd_io *io) {
    return io != NULL && io->select != NULL && io->set_dc != NULL &&
           io->set_reset != NULL && io->write != NULL && io->delay_ms != NULL;
}

static bool send(const retrofm_lcd_io *io,
                 bool data_mode,
                 const uint8_t *bytes,
                 size_t amount) {
    return io->set_dc(io->context, data_mode) &&
           (amount == 0U || io->write(io->context, bytes, amount));
}

static bool command(const retrofm_lcd_io *io,
                    uint8_t value,
                    const uint8_t *data,
                    size_t amount) {
    return send(io, false, &value, 1U) &&
           (amount == 0U || send(io, true, data, amount));
}

bool retrofm_st7789_init(const retrofm_lcd_io *io) {
    size_t index;

    if (!io_valid(io)) return false;
    if (!io->select(io->context, false) ||
        !io->set_reset(io->context, true)) return false;
    io->delay_ms(io->context, 1U);
    if (!io->set_reset(io->context, false)) return false;
    io->delay_ms(io->context, 1U);
    if (!io->set_reset(io->context, true)) return false;
    io->delay_ms(io->context, 120U);
    if (!io->select(io->context, true)) return false;

    for (index = 0U; index < sizeof(init_steps) / sizeof(init_steps[0]);
         ++index) {
        const lcd_init_step *step = &init_steps[index];
        if (!command(io, step->command, step->data, step->length)) {
            (void)io->select(io->context, false);
            return false;
        }
        if (step->delay_ms != 0U) {
            io->delay_ms(io->context, step->delay_ms);
        }
    }
    return retrofm_st7789_set_window(io, 0U, 0U,
                                      RETROFM_LCD_WIDTH,
                                      RETROFM_LCD_HEIGHT);
}

bool retrofm_st7789_set_window(const retrofm_lcd_io *io,
                               uint16_t x,
                               uint16_t y,
                               uint16_t width,
                               uint16_t height) {
    uint32_t x_end;
    uint32_t y_end;
    uint8_t range[4];

    if (!io_valid(io) || width == 0U || height == 0U) return false;
    x_end = (uint32_t)x + width - 1U;
    y_end = (uint32_t)y + height - 1U;
    if (x_end >= RETROFM_LCD_WIDTH || y_end >= RETROFM_LCD_HEIGHT) {
        return false;
    }
    range[0] = (uint8_t)(x >> 8U);
    range[1] = (uint8_t)x;
    range[2] = (uint8_t)(x_end >> 8U);
    range[3] = (uint8_t)x_end;
    if (!command(io, 0x2AU, range, sizeof(range))) return false;
    range[0] = (uint8_t)(y >> 8U);
    range[1] = (uint8_t)y;
    range[2] = (uint8_t)(y_end >> 8U);
    range[3] = (uint8_t)y_end;
    return command(io, 0x2BU, range, sizeof(range)) &&
           command(io, 0x2CU, NULL, 0U);
}

bool retrofm_st7789_write_pixels(const retrofm_lcd_io *io,
                                 const uint16_t *rgb565,
                                 size_t pixel_count) {
    uint8_t buffer[128];
    size_t position = 0U;

    if (!io_valid(io) || (pixel_count != 0U && rgb565 == NULL)) return false;
    if (!io->set_dc(io->context, true)) return false;
    while (position < pixel_count) {
        size_t count = pixel_count - position;
        size_t index;
        if (count > sizeof(buffer) / 2U) count = sizeof(buffer) / 2U;
        for (index = 0U; index < count; ++index) {
            uint16_t pixel = rgb565[position + index];
            buffer[index * 2U] = (uint8_t)(pixel >> 8U);
            buffer[index * 2U + 1U] = (uint8_t)pixel;
        }
        if (!io->write(io->context, buffer, count * 2U)) return false;
        position += count;
    }
    return true;
}

bool retrofm_st7789_fill(const retrofm_lcd_io *io, uint16_t rgb565) {
    uint16_t line[RETROFM_LCD_WIDTH];
    size_t index;

    if (!retrofm_st7789_set_window(io, 0U, 0U,
                                    RETROFM_LCD_WIDTH,
                                    RETROFM_LCD_HEIGHT)) return false;
    for (index = 0U; index < RETROFM_LCD_WIDTH; ++index) line[index] = rgb565;
    for (index = 0U; index < RETROFM_LCD_HEIGHT; ++index) {
        if (!retrofm_st7789_write_pixels(io, line, RETROFM_LCD_WIDTH)) {
            return false;
        }
    }
    return true;
}
