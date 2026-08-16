/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_ST7789_H
#define RETROFM_ST7789_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RETROFM_LCD_WIDTH 240U
#define RETROFM_LCD_HEIGHT 240U

typedef struct retrofm_lcd_io {
    void *context;
    bool (*select)(void *context, bool selected);
    bool (*set_dc)(void *context, bool data_mode);
    bool (*set_reset)(void *context, bool high);
    bool (*write)(void *context, const uint8_t *bytes, size_t amount);
    void (*delay_ms)(void *context, uint32_t milliseconds);
} retrofm_lcd_io;

/* Initializes the panel with the exact table used by the hardware-validated
 * EBAZ adapter test. The transport must already be configured for SPI mode 3,
 * MSB first. Chip select remains asserted on success. */
bool retrofm_st7789_init(const retrofm_lcd_io *io);

bool retrofm_st7789_set_window(const retrofm_lcd_io *io,
                               uint16_t x,
                               uint16_t y,
                               uint16_t width,
                               uint16_t height);

bool retrofm_st7789_write_pixels(const retrofm_lcd_io *io,
                                 const uint16_t *rgb565,
                                 size_t pixel_count);

bool retrofm_st7789_fill(const retrofm_lcd_io *io, uint16_t rgb565);

#ifdef __cplusplus
}
#endif

#endif
