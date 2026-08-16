/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_japanese_font.h"

#include <stdbool.h>

/* Extracted verbatim from M5GFX 0.2.18. See vendor/ for its IPA license. */
extern const uint8_t lgfx_font_japan_gothic_12[108977];

enum { FONT_SIZE = 108977 };

typedef struct bit_reader {
    const uint8_t *pointer;
    const uint8_t *end;
    uint8_t bit_position;
    bool valid;
} bit_reader;

static uint16_t read_be16(const uint8_t *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8U) | bytes[1]);
}

static uint8_t unsigned_bits(bit_reader *reader, uint8_t count) {
    uint16_t value;
    uint8_t next_position;
    if (reader == NULL || !reader->valid || count == 0U || count > 8U ||
        reader->pointer >= reader->end) {
        if (reader != NULL) reader->valid = false;
        return 0U;
    }
    value = (uint16_t)(*reader->pointer >> reader->bit_position);
    next_position = (uint8_t)(reader->bit_position + count);
    if (next_position >= 8U) {
        next_position = (uint8_t)(next_position - 8U);
        ++reader->pointer;
        if (reader->pointer >= reader->end) {
            reader->valid = false;
            return 0U;
        }
        value |= (uint16_t)(*reader->pointer <<
                            (8U - reader->bit_position));
    }
    reader->bit_position = next_position;
    return (uint8_t)(value & ((UINT16_C(1) << count) - 1U));
}

static int8_t signed_bits(bit_reader *reader, uint8_t count) {
    return (int8_t)((int16_t)unsigned_bits(reader, count) -
                    (INT16_C(1) << (count - 1U)));
}

static const uint8_t *find_glyph(uint16_t encoding) {
    const uint8_t *const base = lgfx_font_japan_gothic_12;
    const uint8_t *const end = base + FONT_SIZE;
    const uint8_t *font = base + 23U;

    if (encoding <= 255U) {
        if (encoding >= (uint16_t)'a') {
            font += read_be16(base + 19U);
        } else if (encoding >= (uint16_t)'A') {
            font += read_be16(base + 17U);
        }
        while (font + 2U < end && font[1] != 0U) {
            if (font[0] == (uint8_t)encoding) return font + 2U;
            if (font[1] < 2U || font + font[1] >= end) break;
            font += font[1];
        }
    } else {
        const uint8_t *lookup;
        uint16_t candidate = 0U;
        font += read_be16(base + 21U);
        lookup = font;
        while (lookup + 4U <= end) {
            uint16_t displacement = read_be16(lookup);
            candidate = read_be16(lookup + 2U);
            if (displacement == 0U || font + displacement >= end) return NULL;
            font += displacement;
            lookup += 4U;
            if (candidate >= encoding) break;
        }
        if (candidate < encoding) return NULL;
        while (font + 3U < end) {
            candidate = read_be16(font);
            if (candidate == 0U) break;
            if (candidate == encoding) return font + 3U;
            if (font[2] < 3U || font + font[2] >= end) break;
            font += font[2];
        }
    }
    return NULL;
}

static uint32_t next_utf8(const char **text) {
    const uint8_t *bytes = (const uint8_t *)*text;
    uint32_t code;
    if (bytes[0] < 0x80U) {
        ++*text;
        return bytes[0];
    }
    if ((bytes[0] & 0xE0U) == 0xC0U &&
        (bytes[1] & 0xC0U) == 0x80U) {
        code = ((uint32_t)(bytes[0] & 0x1FU) << 6U) |
               (bytes[1] & 0x3FU);
        *text += 2;
        return code >= 0x80U ? code : (uint32_t)'?';
    }
    if ((bytes[0] & 0xF0U) == 0xE0U &&
        (bytes[1] & 0xC0U) == 0x80U &&
        (bytes[2] & 0xC0U) == 0x80U) {
        code = ((uint32_t)(bytes[0] & 0x0FU) << 12U) |
               ((uint32_t)(bytes[1] & 0x3FU) << 6U) |
               (bytes[2] & 0x3FU);
        *text += 3;
        if (code >= 0x800U && (code < 0xD800U || code > 0xDFFFU)) {
            return code;
        }
        return (uint32_t)'?';
    }
    ++*text;
    return (uint32_t)'?';
}

static int draw_glyph(uint16_t *pixels,
                      uint16_t surface_width,
                      uint16_t surface_height,
                      int cursor_x,
                      int top_y,
                      int clip_left,
                      int clip_right,
                      uint16_t code,
                      uint16_t color) {
    const uint8_t *font = lgfx_font_japan_gothic_12;
    const uint8_t *glyph = find_glyph(code);
    bit_reader reader;
    uint16_t width;
    uint16_t height;
    int x_offset;
    int y_offset;
    int advance;
    uint16_t x = 0U;
    uint16_t y = 0U;

    if (glyph == NULL && code != (uint16_t)'?') glyph = find_glyph('?');
    if (glyph == NULL) return font[9];
    reader.pointer = glyph;
    reader.end = font + FONT_SIZE;
    reader.bit_position = 0U;
    reader.valid = true;
    width = unsigned_bits(&reader, font[4]);
    height = unsigned_bits(&reader, font[5]);
    x_offset = signed_bits(&reader, font[6]);
    y_offset = (int)(int8_t)font[10] + (int)(int8_t)font[12] -
               signed_bits(&reader, font[7]) - (int)height;
    advance = signed_bits(&reader, font[8]);

    while (reader.valid && y < height) {
        uint16_t runs[2];
        bool foreground = false;
        runs[0] = unsigned_bits(&reader, font[2]);
        runs[1] = unsigned_bits(&reader, font[3]);
        do {
            uint16_t remaining = runs[foreground ? 1U : 0U];
            while (reader.valid && remaining != 0U && y < height) {
                uint16_t amount = remaining;
                uint16_t room = (uint16_t)(width - x);
                uint16_t index;
                if (amount > room) amount = room;
                if (foreground) {
                    for (index = 0U; index < amount; ++index) {
                        int draw_x = cursor_x + x_offset + (int)x + index;
                        int draw_y = top_y + y_offset + (int)y;
                        if (draw_x >= clip_left && draw_x < clip_right &&
                            draw_x >= 0 && draw_y >= 0 &&
                            draw_x < surface_width && draw_y < surface_height) {
                            pixels[(size_t)draw_y * surface_width +
                                   (size_t)draw_x] = color;
                        }
                    }
                }
                x = (uint16_t)(x + amount);
                remaining = (uint16_t)(remaining - amount);
                if (x == width) {
                    x = 0U;
                    ++y;
                }
            }
            foreground = !foreground;
        } while (reader.valid &&
                 (foreground || unsigned_bits(&reader, 1U) != 0U));
    }
    return advance > 0 ? advance : (int)font[9];
}

static int glyph_advance(uint16_t code) {
    const uint8_t *font = lgfx_font_japan_gothic_12;
    const uint8_t *glyph = find_glyph(code);
    bit_reader reader;
    int advance;
    if (glyph == NULL && code != (uint16_t)'?') glyph = find_glyph('?');
    if (glyph == NULL) return font[9];
    reader.pointer = glyph;
    reader.end = font + FONT_SIZE;
    reader.bit_position = 0U;
    reader.valid = true;
    (void)unsigned_bits(&reader, font[4]);
    (void)unsigned_bits(&reader, font[5]);
    (void)signed_bits(&reader, font[6]);
    (void)signed_bits(&reader, font[7]);
    advance = signed_bits(&reader, font[8]);
    return advance > 0 ? advance : (int)font[9];
}

int retrofm_japanese_measure_utf8(const char *text,
                                  size_t maximum_codepoints) {
    size_t used = 0U;
    int width = 0;
    if (text == NULL) return 0;
    while (*text != '\0' && used < maximum_codepoints) {
        uint32_t code = next_utf8(&text);
        if (code > UINT16_MAX) code = (uint32_t)'?';
        width += glyph_advance((uint16_t)code);
        ++used;
    }
    return width;
}

size_t retrofm_japanese_draw_utf8_clipped(uint16_t *pixels,
                                          uint16_t surface_width,
                                          uint16_t surface_height,
                                          int x,
                                          int y,
                                          int clip_left,
                                          int clip_right,
                                          const char *text,
                                          size_t maximum_codepoints,
                                          uint16_t color) {
    size_t used = 0U;
    int cursor = x;
    if (pixels == NULL || text == NULL || surface_width == 0U ||
        surface_height == 0U || clip_left < 0 ||
        clip_right > surface_width || clip_left >= clip_right) return 0U;
    while (*text != '\0' && used < maximum_codepoints &&
           cursor < clip_right) {
        uint32_t code = next_utf8(&text);
        if (code > UINT16_MAX) code = (uint32_t)'?';
        cursor += draw_glyph(pixels, surface_width, surface_height,
                             cursor, y, clip_left, clip_right,
                             (uint16_t)code, color);
        ++used;
    }
    return used;
}

size_t retrofm_japanese_draw_utf8(uint16_t *pixels,
                                  uint16_t surface_width,
                                  uint16_t surface_height,
                                  uint16_t x,
                                  uint16_t y,
                                  const char *text,
                                  size_t maximum_codepoints,
                                  uint16_t color) {
    return retrofm_japanese_draw_utf8_clipped(
        pixels, surface_width, surface_height, x, y, 0, surface_width,
        text, maximum_codepoints, color);
}
