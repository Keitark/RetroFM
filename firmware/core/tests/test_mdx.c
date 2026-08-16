// SPDX-License-Identifier: GPL-3.0-or-later

#include "retrofm_mdx.h"

#include <stdio.h>
#include <string.h>

#define CHECK(condition)                                                     \
    do {                                                                     \
        if (!(condition)) {                                                  \
            fprintf(stderr, "CHECK failed at %s:%d: %s\n",                 \
                    __FILE__, __LINE__, #condition);                         \
            return 1;                                                        \
        }                                                                    \
    } while (0)

enum {
    PREFIX_SIZE = 8,
    TABLE_SIZE = 20,
    VOICE_SIZE = 27,
    TRACK_COUNT = 9,
    MAX_FILE_SIZE = 160
};

static void put_be16(uint8_t *data, uint16_t value) {
    data[0] = (uint8_t)(value >> 8U);
    data[1] = (uint8_t)value;
}

static size_t make_mdx(uint8_t *out,
                       const uint8_t *track0,
                       size_t track0_size,
                       const uint8_t *track8,
                       size_t track8_size) {
    static const uint8_t prefix[PREFIX_SIZE] = {
        'T', 'e', 's', 't', 0x0D, 0x0A, 0x1A, 0x00
    };
    static const uint8_t end_track[2] = {0xF1, 0x00};
    size_t offset = TABLE_SIZE;
    size_t voice_offset;
    size_t i;

    memset(out, 0, MAX_FILE_SIZE);
    memcpy(out, prefix, sizeof(prefix));

    put_be16(out + PREFIX_SIZE + 2U, (uint16_t)offset);
    offset += track0_size;

    for (i = 1U; i < TRACK_COUNT; ++i) {
        put_be16(out + PREFIX_SIZE + 2U * (i + 1U), (uint16_t)offset);
        offset += (i == 8U) ? track8_size : sizeof(end_track);
    }
    voice_offset = offset;
    put_be16(out + PREFIX_SIZE, (uint16_t)voice_offset);

    /* One voice, number zero. The remaining bytes form a quiet but
     * structurally valid 27-byte OPM voice record. */
    memcpy(out + PREFIX_SIZE + TABLE_SIZE, track0, track0_size);
    offset = PREFIX_SIZE + TABLE_SIZE + track0_size;
    for (i = 1U; i < TRACK_COUNT; ++i) {
        const uint8_t *source = (i == 8U) ? track8 : end_track;
        size_t amount = (i == 8U) ? track8_size : sizeof(end_track);
        memcpy(out + offset, source, amount);
        offset += amount;
    }
    out[PREFIX_SIZE + voice_offset] = 0U;
    offset += VOICE_SIZE;
    return offset;
}

static int test_valid_file(void) {
    static const uint8_t track0[] = {
        0xFD, 0x00,       /* voice 0 */
        0xFC, 0x03,       /* stereo */
        0xFB, 0x0F,       /* volume */
        0x80, 0x00,       /* shortest note */
        0x00,             /* shortest rest */
        0xF1, 0x00        /* end */
    };
    static const uint8_t track8[] = {0xF1, 0x00};
    uint8_t bytes[MAX_FILE_SIZE];
    retrofm_mdx mdx;
    size_t size = make_mdx(bytes, track0, sizeof(track0),
                           track8, sizeof(track8));

    CHECK(retrofm_mdx_open(&mdx, bytes, size) == RETROFM_MDX_OK);
    CHECK(mdx.track_count == TRACK_COUNT);
    CHECK(mdx.voice_count == 1U);
    CHECK(mdx.voices[0] == bytes + size - VOICE_SIZE);
    CHECK(mdx.title.size == 4U);
    CHECK(memcmp(mdx.title.data, "Test", 4U) == 0);
    CHECK(mdx.pdx_name.size == 0U);
    CHECK(mdx.tracks[0].size == sizeof(track0));
    CHECK(!mdx.uses_pdx);
    return 0;
}

static int test_pdx_detection(void) {
    static const uint8_t track0[] = {0xF1, 0x00};
    static const uint8_t track8[] = {0x80, 0x00, 0xF1, 0x00};
    uint8_t bytes[MAX_FILE_SIZE];
    retrofm_mdx mdx;
    size_t size = make_mdx(bytes, track0, sizeof(track0),
                           track8, sizeof(track8));

    CHECK(retrofm_mdx_open(&mdx, bytes, size) == RETROFM_MDX_OK);
    CHECK(mdx.uses_pdx);
    return 0;
}

static int test_repeat_and_loop(void) {
    static const uint8_t repeated[] = {
        0xF6, 0x02, 0x00, /* repeat twice; byte 2 is runtime counter */
        0x00,
        0xF5, 0xFF, 0xFC, /* after + (-4) = first command in body */
        0xF1, 0x00
    };
    static const uint8_t looped[] = {
        0x00,
        0xF1, 0xFF, 0xFC  /* after + (-4) = track start */
    };
    static const uint8_t bad_repeat[] = {
        0xF6, 0x02, 0x00, 0x00, 0xF5, 0xFF, 0xFB, 0xF1, 0x00
    };
    static const uint8_t end_track[] = {0xF1, 0x00};
    uint8_t bytes[MAX_FILE_SIZE];
    retrofm_mdx mdx;
    size_t size;

    size = make_mdx(bytes, repeated, sizeof(repeated),
                    end_track, sizeof(end_track));
    CHECK(retrofm_mdx_open(&mdx, bytes, size) == RETROFM_MDX_OK);

    size = make_mdx(bytes, looped, sizeof(looped),
                    end_track, sizeof(end_track));
    CHECK(retrofm_mdx_open(&mdx, bytes, size) == RETROFM_MDX_OK);

    size = make_mdx(bytes, bad_repeat, sizeof(bad_repeat),
                    end_track, sizeof(end_track));
    CHECK(retrofm_mdx_open(&mdx, bytes, size) == RETROFM_MDX_BAD_REPEAT);
    return 0;
}

static int test_bad_inputs(void) {
    static const uint8_t valid_track[] = {0xFD, 0x00, 0xF1, 0x00};
    static const uint8_t missing_voice[] = {0xFD, 0x01, 0xF1, 0x00};
    static const uint8_t truncated_write[] = {0xFE, 0x12};
    static const uint8_t end_track[] = {0xF1, 0x00};
    uint8_t bytes[MAX_FILE_SIZE];
    retrofm_mdx mdx;
    size_t size;

    CHECK(retrofm_mdx_open(NULL, bytes, sizeof(bytes)) ==
          RETROFM_MDX_BAD_ARGUMENT);
    CHECK(retrofm_mdx_open(&mdx, NULL, sizeof(bytes)) ==
          RETROFM_MDX_BAD_ARGUMENT);
    CHECK(retrofm_mdx_open(&mdx, bytes, 7U) == RETROFM_MDX_TRUNCATED);

    memset(bytes, 0x55, sizeof(bytes));
    CHECK(retrofm_mdx_open(&mdx, bytes, sizeof(bytes)) ==
          RETROFM_MDX_BAD_TITLE);

    size = make_mdx(bytes, missing_voice, sizeof(missing_voice),
                    end_track, sizeof(end_track));
    CHECK(retrofm_mdx_open(&mdx, bytes, size) ==
          RETROFM_MDX_MISSING_VOICE);

    size = make_mdx(bytes, truncated_write, sizeof(truncated_write),
                    end_track, sizeof(end_track));
    CHECK(retrofm_mdx_open(&mdx, bytes, size) ==
          RETROFM_MDX_TRUNCATED_COMMAND);

    size = make_mdx(bytes, valid_track, sizeof(valid_track),
                    end_track, sizeof(end_track));
    /* Duplicate track offsets are rejected instead of aliasing chunks. */
    memcpy(bytes + PREFIX_SIZE + 4U, bytes + PREFIX_SIZE + 2U, 2U);
    CHECK(retrofm_mdx_open(&mdx, bytes, size) == RETROFM_MDX_OVERLAP);

    size = make_mdx(bytes, valid_track, sizeof(valid_track),
                    end_track, sizeof(end_track));
    bytes[PREFIX_SIZE + 4U] = 'L';
    bytes[PREFIX_SIZE + 5U] = 'Z';
    bytes[PREFIX_SIZE + 6U] = 'X';
    CHECK(retrofm_mdx_open(&mdx, bytes, size) ==
          RETROFM_MDX_LZX_UNSUPPORTED);
    return 0;
}

static int test_command_framing(void) {
    static const uint8_t end_command[] = {0xF1, 0x00};
    static const uint8_t lfo_short[] = {0xEA, 0x80};
    static const uint8_t lfo_long[] = {0xEA, 0x00, 1, 2, 3, 4};
    static const uint8_t informal[] = {0xE6};
    retrofm_mdx_result result = RETROFM_MDX_OK;

    CHECK(retrofm_mdx_command_size(end_command, sizeof(end_command),
                                    &result) == 2U);
    CHECK(result == RETROFM_MDX_OK);
    CHECK(retrofm_mdx_command_size(lfo_short, sizeof(lfo_short),
                                    &result) == 2U);
    CHECK(retrofm_mdx_command_size(lfo_long, sizeof(lfo_long),
                                    &result) == 6U);
    CHECK(retrofm_mdx_command_size(informal, sizeof(informal),
                                    &result) == 1U);
    CHECK(retrofm_mdx_command_size(lfo_long, 5U, &result) == 0U);
    CHECK(result == RETROFM_MDX_TRUNCATED_COMMAND);
    return 0;
}

int main(void) {
    CHECK(test_valid_file() == 0);
    CHECK(test_pdx_detection() == 0);
    CHECK(test_repeat_and_loop() == 0);
    CHECK(test_bad_inputs() == 0);
    CHECK(test_command_framing() == 0);
    puts("retrofm MDX parser tests passed");
    return 0;
}
