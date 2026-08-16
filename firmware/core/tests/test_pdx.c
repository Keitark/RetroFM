/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_pdx.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define PDX_VECTOR_SIZE 800U
#define PDX_PAYLOAD_SIZE 32U

static int failures;

#define CHECK(condition) do {                                                   \
    if (!(condition)) {                                                        \
        fprintf(stderr, "%s:%d: CHECK failed: %s\n",                         \
                __FILE__, __LINE__, #condition);                               \
        ++failures;                                                            \
    }                                                                          \
} while (0)

static void put_be_u32(uint8_t *bytes, size_t offset, uint32_t value) {
    bytes[offset] = (uint8_t)(value >> 24U);
    bytes[offset + 1U] = (uint8_t)(value >> 16U);
    bytes[offset + 2U] = (uint8_t)(value >> 8U);
    bytes[offset + 3U] = (uint8_t)value;
}

static void make_pdx_vector(uint8_t bytes[PDX_VECTOR_SIZE]) {
    size_t index;

    memset(bytes, 0, PDX_VECTOR_SIZE);
    put_be_u32(bytes, 0U, RETROFM_PDX_TABLE_BYTES);
    put_be_u32(bytes, 4U, PDX_PAYLOAD_SIZE);
    for (index = 0U; index < PDX_PAYLOAD_SIZE; ++index) {
        bytes[RETROFM_PDX_TABLE_BYTES + index] = (uint8_t)(index & 0x0FU);
    }
}

static uint32_t rotate_right(uint32_t value, unsigned amount) {
    return (value >> amount) | (value << (32U - amount));
}

static void sha256_transform(uint32_t state[8], const uint8_t block[64]) {
    static const uint32_t constants[64] = {
        UINT32_C(0x428A2F98), UINT32_C(0x71374491), UINT32_C(0xB5C0FBCF), UINT32_C(0xE9B5DBA5),
        UINT32_C(0x3956C25B), UINT32_C(0x59F111F1), UINT32_C(0x923F82A4), UINT32_C(0xAB1C5ED5),
        UINT32_C(0xD807AA98), UINT32_C(0x12835B01), UINT32_C(0x243185BE), UINT32_C(0x550C7DC3),
        UINT32_C(0x72BE5D74), UINT32_C(0x80DEB1FE), UINT32_C(0x9BDC06A7), UINT32_C(0xC19BF174),
        UINT32_C(0xE49B69C1), UINT32_C(0xEFBE4786), UINT32_C(0x0FC19DC6), UINT32_C(0x240CA1CC),
        UINT32_C(0x2DE92C6F), UINT32_C(0x4A7484AA), UINT32_C(0x5CB0A9DC), UINT32_C(0x76F988DA),
        UINT32_C(0x983E5152), UINT32_C(0xA831C66D), UINT32_C(0xB00327C8), UINT32_C(0xBF597FC7),
        UINT32_C(0xC6E00BF3), UINT32_C(0xD5A79147), UINT32_C(0x06CA6351), UINT32_C(0x14292967),
        UINT32_C(0x27B70A85), UINT32_C(0x2E1B2138), UINT32_C(0x4D2C6DFC), UINT32_C(0x53380D13),
        UINT32_C(0x650A7354), UINT32_C(0x766A0ABB), UINT32_C(0x81C2C92E), UINT32_C(0x92722C85),
        UINT32_C(0xA2BFE8A1), UINT32_C(0xA81A664B), UINT32_C(0xC24B8B70), UINT32_C(0xC76C51A3),
        UINT32_C(0xD192E819), UINT32_C(0xD6990624), UINT32_C(0xF40E3585), UINT32_C(0x106AA070),
        UINT32_C(0x19A4C116), UINT32_C(0x1E376C08), UINT32_C(0x2748774C), UINT32_C(0x34B0BCB5),
        UINT32_C(0x391C0CB3), UINT32_C(0x4ED8AA4A), UINT32_C(0x5B9CCA4F), UINT32_C(0x682E6FF3),
        UINT32_C(0x748F82EE), UINT32_C(0x78A5636F), UINT32_C(0x84C87814), UINT32_C(0x8CC70208),
        UINT32_C(0x90BEFFFA), UINT32_C(0xA4506CEB), UINT32_C(0xBEF9A3F7), UINT32_C(0xC67178F2)
    };
    uint32_t words[64];
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t d;
    uint32_t e;
    uint32_t f;
    uint32_t g;
    uint32_t h;
    size_t index;

    for (index = 0U; index < 16U; ++index) {
        const size_t offset = index * 4U;
        words[index] = ((uint32_t)block[offset] << 24U) |
                       ((uint32_t)block[offset + 1U] << 16U) |
                       ((uint32_t)block[offset + 2U] << 8U) |
                       (uint32_t)block[offset + 3U];
    }
    for (index = 16U; index < ARRAY_SIZE(words); ++index) {
        const uint32_t x = words[index - 15U];
        const uint32_t y = words[index - 2U];
        const uint32_t sigma0 = rotate_right(x, 7U) ^
                                rotate_right(x, 18U) ^ (x >> 3U);
        const uint32_t sigma1 = rotate_right(y, 17U) ^
                                rotate_right(y, 19U) ^ (y >> 10U);
        words[index] = words[index - 16U] + sigma0 +
                       words[index - 7U] + sigma1;
    }

    a = state[0];
    b = state[1];
    c = state[2];
    d = state[3];
    e = state[4];
    f = state[5];
    g = state[6];
    h = state[7];
    for (index = 0U; index < ARRAY_SIZE(words); ++index) {
        const uint32_t sum1 = rotate_right(e, 6U) ^
                              rotate_right(e, 11U) ^ rotate_right(e, 25U);
        const uint32_t choose = (e & f) ^ ((~e) & g);
        const uint32_t temp1 = h + sum1 + choose + constants[index] + words[index];
        const uint32_t sum0 = rotate_right(a, 2U) ^
                              rotate_right(a, 13U) ^ rotate_right(a, 22U);
        const uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
        const uint32_t temp2 = sum0 + majority;

        h = g;
        g = f;
        f = e;
        e = d + temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 + temp2;
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
}

static void sha256(const uint8_t *bytes, size_t length, uint8_t digest[32]) {
    uint32_t state[8] = {
        UINT32_C(0x6A09E667), UINT32_C(0xBB67AE85),
        UINT32_C(0x3C6EF372), UINT32_C(0xA54FF53A),
        UINT32_C(0x510E527F), UINT32_C(0x9B05688C),
        UINT32_C(0x1F83D9AB), UINT32_C(0x5BE0CD19)
    };
    uint8_t tail[128];
    const uint64_t bit_length = (uint64_t)length * UINT64_C(8);
    size_t remaining = length;
    size_t tail_size;
    size_t index;

    while (remaining >= 64U) {
        sha256_transform(state, bytes);
        bytes += 64U;
        remaining -= 64U;
    }

    memset(tail, 0, sizeof(tail));
    memcpy(tail, bytes, remaining);
    tail[remaining] = 0x80U;
    tail_size = remaining < 56U ? 64U : 128U;
    for (index = 0U; index < 8U; ++index) {
        tail[tail_size - 1U - index] =
            (uint8_t)(bit_length >> (unsigned)(index * 8U));
    }
    sha256_transform(state, tail);
    if (tail_size == 128U) {
        sha256_transform(state, tail + 64U);
    }

    for (index = 0U; index < ARRAY_SIZE(state); ++index) {
        digest[index * 4U] = (uint8_t)(state[index] >> 24U);
        digest[index * 4U + 1U] = (uint8_t)(state[index] >> 16U);
        digest[index * 4U + 2U] = (uint8_t)(state[index] >> 8U);
        digest[index * 4U + 3U] = (uint8_t)state[index];
    }
}

static void digest_to_hex(const uint8_t digest[32], char hex[65]) {
    static const char digits[] = "0123456789ABCDEF";
    size_t index;

    for (index = 0U; index < 32U; ++index) {
        hex[index * 2U] = digits[digest[index] >> 4U];
        hex[index * 2U + 1U] = digits[digest[index] & 0x0FU];
    }
    hex[64] = '\0';
}

static void test_generated_vector(void) {
    static const char expected_sha256[] =
        "1E81974D5F2F2EF5D529DBDB8FC08CC5495FA3019AC05A8204C1FC8493236798";
    static const int16_t expected_samples[] = {
        2, 4, 10, 12, 22, 24, 38, 40,
        58, 60, 83, 86, 122, 127, 195, 205
    };
    uint8_t vector[PDX_VECTOR_SIZE];
    uint8_t digest[32];
    char digest_hex[65];
    retrofm_pdx pdx;
    const uint8_t *sample_bytes = NULL;
    size_t sample_length = 0U;
    retrofm_adpcm_decoder decoder;
    retrofm_pdx_result result;
    int16_t sample = 0;
    size_t decoded_count;
    size_t index;

    make_pdx_vector(vector);
    sha256(vector, sizeof(vector), digest);
    digest_to_hex(digest, digest_hex);
    CHECK(strcmp(digest_hex, expected_sha256) == 0);

    CHECK(retrofm_pdx_open(&pdx, vector, sizeof(vector)) == RETROFM_PDX_OK);
    CHECK(pdx.entries[0].offset == RETROFM_PDX_TABLE_BYTES);
    CHECK(pdx.entries[0].length == PDX_PAYLOAD_SIZE);
    CHECK(retrofm_pdx_get_sample(&pdx, 0U, &sample_bytes, &sample_length) ==
          RETROFM_PDX_OK);
    CHECK(sample_bytes == vector + RETROFM_PDX_TABLE_BYTES);
    CHECK(sample_length == PDX_PAYLOAD_SIZE);
    CHECK(retrofm_adpcm_begin(&decoder, sample_bytes, sample_length) ==
          RETROFM_PDX_OK);
    CHECK(retrofm_adpcm_samples_remaining(&decoder) == 64U);

    for (index = 0U; index < ARRAY_SIZE(expected_samples); ++index) {
        CHECK(retrofm_adpcm_next(&decoder, &sample) == RETROFM_PDX_OK);
        CHECK(sample == expected_samples[index]);
    }
    CHECK(retrofm_adpcm_samples_remaining(&decoder) == 48U);

    decoded_count = ARRAY_SIZE(expected_samples);
    while ((result = retrofm_adpcm_next(&decoder, &sample)) == RETROFM_PDX_OK) {
        ++decoded_count;
    }
    CHECK(result == RETROFM_PDX_END);
    CHECK(decoded_count == 64U);
    CHECK(retrofm_adpcm_samples_remaining(&decoder) == 0U);
    CHECK(retrofm_adpcm_next(&decoder, &sample) == RETROFM_PDX_END);

    sample_bytes = vector;
    sample_length = 1U;
    CHECK(retrofm_pdx_get_sample(&pdx, 1U, &sample_bytes, &sample_length) ==
          RETROFM_PDX_EMPTY_SAMPLE);
    CHECK(sample_bytes == NULL);
    CHECK(sample_length == 0U);
}

static void test_low_nibble_first(void) {
    const uint8_t encoded[] = { 0x10U };
    retrofm_adpcm_decoder decoder;
    int16_t sample;

    CHECK(retrofm_adpcm_begin(&decoder, encoded, sizeof(encoded)) ==
          RETROFM_PDX_OK);
    CHECK(retrofm_adpcm_next(&decoder, &sample) == RETROFM_PDX_OK);
    CHECK(sample == 2);
    CHECK(retrofm_adpcm_samples_remaining(&decoder) == 1U);
    CHECK(retrofm_adpcm_next(&decoder, &sample) == RETROFM_PDX_OK);
    CHECK(sample == 8);
    CHECK(retrofm_adpcm_next(&decoder, &sample) == RETROFM_PDX_END);
}

static void test_parser_errors(void) {
    uint8_t vector[PDX_VECTOR_SIZE];
    retrofm_pdx pdx;
    const uint8_t *sample_bytes;
    size_t sample_length;

    make_pdx_vector(vector);
    CHECK(retrofm_pdx_open(NULL, vector, sizeof(vector)) ==
          RETROFM_PDX_BAD_ARGUMENT);
    CHECK(retrofm_pdx_open(&pdx, NULL, sizeof(vector)) ==
          RETROFM_PDX_BAD_ARGUMENT);
    CHECK(retrofm_pdx_open(&pdx, vector, RETROFM_PDX_TABLE_BYTES - 1U) ==
          RETROFM_PDX_TRUNCATED);

    make_pdx_vector(vector);
    put_be_u32(vector, 8U, PDX_VECTOR_SIZE - 1U);
    put_be_u32(vector, 12U, 2U);
    CHECK(retrofm_pdx_open(&pdx, vector, sizeof(vector)) ==
          RETROFM_PDX_INVALID_RANGE);

    make_pdx_vector(vector);
    put_be_u32(vector, 8U, UINT32_C(0xFFFFFFF0));
    put_be_u32(vector, 12U, UINT32_C(0x40));
    CHECK(retrofm_pdx_open(&pdx, vector, sizeof(vector)) ==
          RETROFM_PDX_INVALID_RANGE);

    make_pdx_vector(vector);
    put_be_u32(vector, 8U, RETROFM_PDX_TABLE_BYTES - 1U);
    put_be_u32(vector, 12U, 1U);
    CHECK(retrofm_pdx_open(&pdx, vector, sizeof(vector)) ==
          RETROFM_PDX_INVALID_RANGE);

    make_pdx_vector(vector);
    CHECK(retrofm_pdx_open(&pdx, vector, sizeof(vector)) == RETROFM_PDX_OK);
    CHECK(retrofm_pdx_get_sample(&pdx, RETROFM_PDX_SAMPLE_COUNT,
                                 &sample_bytes, &sample_length) ==
          RETROFM_PDX_INDEX_OUT_OF_RANGE);
    CHECK(retrofm_pdx_get_sample(&pdx, 0U, NULL, &sample_length) ==
          RETROFM_PDX_BAD_ARGUMENT);
    CHECK(retrofm_pdx_get_sample(&pdx, 0U, &sample_bytes, NULL) ==
          RETROFM_PDX_BAD_ARGUMENT);
}

static void test_decoder_errors(void) {
    const uint8_t encoded[] = { 0x00U };
    retrofm_adpcm_decoder decoder;
    int16_t sample;

    CHECK(retrofm_adpcm_begin(NULL, encoded, sizeof(encoded)) ==
          RETROFM_PDX_BAD_ARGUMENT);
    CHECK(retrofm_adpcm_begin(&decoder, NULL, sizeof(encoded)) ==
          RETROFM_PDX_BAD_ARGUMENT);
    CHECK(retrofm_adpcm_begin(&decoder, NULL, 0U) ==
          RETROFM_PDX_EMPTY_SAMPLE);
    CHECK(retrofm_adpcm_next(NULL, &sample) == RETROFM_PDX_BAD_ARGUMENT);
    CHECK(retrofm_adpcm_next(&decoder, NULL) == RETROFM_PDX_BAD_ARGUMENT);

    CHECK(retrofm_adpcm_begin(&decoder, encoded, sizeof(encoded)) ==
          RETROFM_PDX_OK);
    decoder.step_index = 49U;
    CHECK(retrofm_adpcm_next(&decoder, &sample) == RETROFM_PDX_BAD_STATE);
}

int main(void) {
    test_generated_vector();
    test_low_nibble_first();
    test_parser_errors();
    test_decoder_errors();

    if (failures != 0) {
        fprintf(stderr, "%d PDX test(s) failed\n", failures);
        return EXIT_FAILURE;
    }
    puts("retrofm PDX tests passed");
    return EXIT_SUCCESS;
}
