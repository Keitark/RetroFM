/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_JAPANESE_FONT_H
#define RETROFM_JAPANESE_FONT_H

#include <stddef.h>
#include <stdint.h>

/*
 * Draw UTF-8 text with the same IPA Gothic 12 U8g2 font selected by the
 * original M5StickS3 player. Returns the number of decoded code points.
 */
size_t retrofm_japanese_draw_utf8(uint16_t *pixels,
                                  uint16_t surface_width,
                                  uint16_t surface_height,
                                  uint16_t x,
                                  uint16_t y,
                                  const char *text,
                                  size_t maximum_codepoints,
                                  uint16_t color);

int retrofm_japanese_measure_utf8(const char *text,
                                  size_t maximum_codepoints);

size_t retrofm_japanese_draw_utf8_clipped(uint16_t *pixels,
                                          uint16_t surface_width,
                                          uint16_t surface_height,
                                          int x,
                                          int y,
                                          int clip_left,
                                          int clip_right,
                                          const char *text,
                                          size_t maximum_codepoints,
                                          uint16_t color);

#endif
