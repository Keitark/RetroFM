/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_vgm.h"
#include "retrofm_vgz.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TINY_VGM_SIZE 0x81U
#define VGZ_FIXTURE_CAPACITY 256U

#define GZIP_FLAG_HEADER_CRC 0x02U
#define GZIP_FLAG_EXTRA 0x04U
#define GZIP_FLAG_NAME 0x08U
#define GZIP_FLAG_COMMENT 0x10U

static int failures;

#define CHECK(condition) do {                                                   \
    if (!(condition)) {                                                        \
        fprintf(stderr, "%s:%d: CHECK failed: %s\n",                         \
                __FILE__, __LINE__, #condition);                               \
        ++failures;                                                            \
    }                                                                          \
} while (0)

static void put_le_u16(uint8_t *bytes, size_t offset, uint16_t value) {
    bytes[offset] = (uint8_t)value;
    bytes[offset + 1U] = (uint8_t)(value >> 8U);
}

static void put_le_u32(uint8_t *bytes, size_t offset, uint32_t value) {
    bytes[offset] = (uint8_t)value;
    bytes[offset + 1U] = (uint8_t)(value >> 8U);
    bytes[offset + 2U] = (uint8_t)(value >> 16U);
    bytes[offset + 3U] = (uint8_t)(value >> 24U);
}

static uint32_t fixture_crc32(const uint8_t *bytes, size_t length) {
    uint32_t crc = UINT32_MAX;
    size_t index;

    for (index = 0U; index < length; ++index) {
        unsigned bit;

        crc ^= bytes[index];
        for (bit = 0U; bit < 8U; ++bit) {
            if ((crc & 1U) != 0U) {
                crc = (crc >> 1U) ^ UINT32_C(0xEDB88320);
            } else {
                crc >>= 1U;
            }
        }
    }
    return ~crc;
}

static void make_tiny_vgm(uint8_t bytes[TINY_VGM_SIZE]) {
    memset(bytes, 0, TINY_VGM_SIZE);
    memcpy(bytes, "Vgm ", 4U);
    put_le_u32(bytes, 0x04U, TINY_VGM_SIZE - 4U);
    put_le_u32(bytes, 0x08U, UINT32_C(0x00000171));
    put_le_u32(bytes, 0x34U, 0x4CU);
    put_le_u32(bytes, 0x44U, UINT32_C(4000000));
    bytes[0x80U] = 0x66U;
}

static size_t make_stored_vgz(uint8_t gzip[VGZ_FIXTURE_CAPACITY],
                              uint8_t flags,
                              size_t *header_size) {
    static const uint8_t extra[] = { 'X', 'Y', 'Z' };
    static const char name[] = "tiny.vgm";
    static const char comment[] = "retrofm fixture";
    uint8_t vgm[TINY_VGM_SIZE];
    uint16_t header_crc;
    uint32_t data_crc;
    size_t position = 0U;

    make_tiny_vgm(vgm);
    gzip[position++] = 0x1FU;
    gzip[position++] = 0x8BU;
    gzip[position++] = 8U;
    gzip[position++] = flags;
    put_le_u32(gzip, position, 0U);
    position += 4U;
    gzip[position++] = 0U;
    gzip[position++] = 0xFFU;

    if ((flags & GZIP_FLAG_EXTRA) != 0U) {
        put_le_u16(gzip, position, (uint16_t)sizeof(extra));
        position += 2U;
        memcpy(gzip + position, extra, sizeof(extra));
        position += sizeof(extra);
    }
    if ((flags & GZIP_FLAG_NAME) != 0U) {
        memcpy(gzip + position, name, sizeof(name));
        position += sizeof(name);
    }
    if ((flags & GZIP_FLAG_COMMENT) != 0U) {
        memcpy(gzip + position, comment, sizeof(comment));
        position += sizeof(comment);
    }
    if ((flags & GZIP_FLAG_HEADER_CRC) != 0U) {
        header_crc = (uint16_t)fixture_crc32(gzip, position);
        put_le_u16(gzip, position, header_crc);
        position += 2U;
    }
    *header_size = position;

    /* One final RFC 1951 stored block containing the complete tiny VGM. */
    gzip[position++] = 0x01U;
    put_le_u16(gzip, position, TINY_VGM_SIZE);
    position += 2U;
    put_le_u16(gzip, position,
               (uint16_t)(UINT16_MAX - (uint16_t)TINY_VGM_SIZE));
    position += 2U;
    memcpy(gzip + position, vgm, sizeof(vgm));
    position += sizeof(vgm);

    data_crc = fixture_crc32(vgm, sizeof(vgm));
    put_le_u32(gzip, position, data_crc);
    position += 4U;
    put_le_u32(gzip, position, TINY_VGM_SIZE);
    position += 4U;
    return position;
}

static void test_basic_vgz(void) {
    uint8_t gzip[VGZ_FIXTURE_CAPACITY];
    uint8_t expected[TINY_VGM_SIZE];
    uint8_t output[TINY_VGM_SIZE];
    size_t header_size;
    size_t gzip_size;
    size_t output_size = 0U;
    retrofm_vgm vgm;
    retrofm_event event;

    make_tiny_vgm(expected);
    CHECK(fixture_crc32(expected, sizeof(expected)) == UINT32_C(0x2DD51FAB));
    gzip_size = make_stored_vgz(gzip, 0U, &header_size);
    CHECK(header_size == 10U);
    CHECK(gzip_size == 152U);
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_OK);
    CHECK(output_size == sizeof(expected));
    CHECK(memcmp(output, expected, sizeof(expected)) == 0);
    CHECK(retrofm_vgm_open(&vgm, output, output_size, false) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_END);
}

static void test_optional_headers(void) {
    const uint8_t all_optional = GZIP_FLAG_EXTRA | GZIP_FLAG_NAME |
                                 GZIP_FLAG_COMMENT | GZIP_FLAG_HEADER_CRC;
    uint8_t gzip[VGZ_FIXTURE_CAPACITY];
    uint8_t output[TINY_VGM_SIZE];
    size_t header_size;
    size_t gzip_size;
    size_t output_size;

    gzip_size = make_stored_vgz(gzip, all_optional, &header_size);
    CHECK(header_size == 42U);
    CHECK(gzip_size == 184U);
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_OK);
    CHECK(output_size == TINY_VGM_SIZE);

    gzip[header_size - 1U] ^= 0x01U;
    output_size = 123U;
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_BAD_HEADER_CRC);
    CHECK(output_size == 0U);
}

static void test_trailer_validation(void) {
    uint8_t gzip[VGZ_FIXTURE_CAPACITY];
    uint8_t output[TINY_VGM_SIZE];
    size_t header_size;
    size_t gzip_size;
    size_t output_size;

    gzip_size = make_stored_vgz(gzip, 0U, &header_size);
    gzip[gzip_size - 8U] ^= 0x01U;
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_BAD_CRC32);

    gzip_size = make_stored_vgz(gzip, 0U, &header_size);
    gzip[gzip_size - 4U] ^= 0x01U;
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_BAD_ISIZE);
}

static void test_header_rejections(void) {
    uint8_t gzip[VGZ_FIXTURE_CAPACITY];
    uint8_t output[TINY_VGM_SIZE];
    size_t header_size;
    size_t gzip_size;
    size_t output_size;

    gzip_size = make_stored_vgz(gzip, 0U, &header_size);
    gzip[3] |= 0x20U;
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_RESERVED_FLAGS);

    gzip_size = make_stored_vgz(gzip, 0U, &header_size);
    CHECK(retrofm_vgz_decompress(gzip, 17U,
                                 output, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_TRUNCATED);

    gzip_size = make_stored_vgz(gzip, 0U, &header_size);
    gzip[3] = GZIP_FLAG_EXTRA;
    put_le_u16(gzip, 10U, UINT16_MAX);
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_TRUNCATED);
}

static void test_output_limits(void) {
    uint8_t gzip[VGZ_FIXTURE_CAPACITY];
    uint8_t output[TINY_VGM_SIZE];
    size_t header_size;
    size_t gzip_size;
    size_t output_size = 123U;

    gzip_size = make_stored_vgz(gzip, 0U, &header_size);
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), TINY_VGM_SIZE - 1U,
                                 &output_size) == RETROFM_VGZ_LIMIT_EXCEEDED);
    CHECK(output_size == 0U);

    /* A false small ISIZE must not bypass the runtime output cap. */
    put_le_u32(gzip, gzip_size - 4U, 64U);
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), 64U,
                                 &output_size) == RETROFM_VGZ_LIMIT_EXCEEDED);
    CHECK(output_size == 0U);

    gzip_size = make_stored_vgz(gzip, 0U, &header_size);
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, TINY_VGM_SIZE - 1U, TINY_VGM_SIZE,
                                 &output_size) == RETROFM_VGZ_OUTPUT_TOO_SMALL);
    CHECK(output_size == 0U);
}

static void test_bad_arguments(void) {
    uint8_t gzip[VGZ_FIXTURE_CAPACITY];
    uint8_t output[TINY_VGM_SIZE];
    size_t header_size;
    size_t gzip_size;
    size_t output_size;

    gzip_size = make_stored_vgz(gzip, 0U, &header_size);
    CHECK(retrofm_vgz_decompress(NULL, gzip_size,
                                 output, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_BAD_ARGUMENT);
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 NULL, sizeof(output), sizeof(output),
                                 &output_size) == RETROFM_VGZ_BAD_ARGUMENT);
    CHECK(retrofm_vgz_decompress(gzip, gzip_size,
                                 output, sizeof(output), sizeof(output),
                                 NULL) == RETROFM_VGZ_BAD_ARGUMENT);
}

int main(void) {
    test_basic_vgz();
    test_optional_headers();
    test_trailer_validation();
    test_header_rejections();
    test_output_limits();
    test_bad_arguments();

    if (failures != 0) {
        fprintf(stderr, "%d VGZ test(s) failed\n", failures);
        return EXIT_FAILURE;
    }
    puts("retrofm VGZ tests passed");
    return EXIT_SUCCESS;
}
