/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_vgz.h"

#include <stdbool.h>
#include <stdint.h>

#if RETROFM_HAS_VGZ
#include "miniz_tinfl.h"
#endif

#define GZIP_FIXED_HEADER_SIZE 10U
#define GZIP_TRAILER_SIZE 8U
#define GZIP_MINIMUM_SIZE (GZIP_FIXED_HEADER_SIZE + GZIP_TRAILER_SIZE)

#define GZIP_FLAG_HEADER_CRC 0x02U
#define GZIP_FLAG_EXTRA 0x04U
#define GZIP_FLAG_NAME 0x08U
#define GZIP_FLAG_COMMENT 0x10U
#define GZIP_RESERVED_FLAGS 0xE0U

#if RETROFM_HAS_VGZ
static bool has_bytes(size_t position, size_t amount, size_t limit) {
    return position <= limit && amount <= limit - position;
}

static uint16_t read_le_u16(const uint8_t *bytes) {
    return (uint16_t)((uint16_t)bytes[0] |
                      ((uint16_t)bytes[1] << 8U));
}

static uint32_t read_le_u32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] |
           ((uint32_t)bytes[1] << 8U) |
           ((uint32_t)bytes[2] << 16U) |
           ((uint32_t)bytes[3] << 24U);
}

static uint32_t gzip_crc32(const uint8_t *bytes, size_t length) {
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

static retrofm_vgz_result skip_zero_terminated(const uint8_t *source,
                                                size_t trailer_position,
                                                size_t *position) {
    while (*position < trailer_position && source[*position] != 0U) {
        ++*position;
    }
    if (*position >= trailer_position) {
        return RETROFM_VGZ_TRUNCATED;
    }
    ++*position;
    return RETROFM_VGZ_OK;
}
#endif

retrofm_vgz_result retrofm_vgz_decompress(const uint8_t *source,
                                          size_t source_size,
                                          uint8_t *output,
                                          size_t output_capacity,
                                          size_t max_decompressed_size,
                                          size_t *output_size) {
    if (output_size == NULL) {
        return RETROFM_VGZ_BAD_ARGUMENT;
    }
    *output_size = 0U;
    if (source == NULL || output == NULL) {
        return RETROFM_VGZ_BAD_ARGUMENT;
    }

#if !RETROFM_HAS_VGZ
    (void)source_size;
    (void)output_capacity;
    (void)max_decompressed_size;
    return RETROFM_VGZ_UNAVAILABLE;
#else
    {
        size_t position;
        size_t trailer_position;
        size_t compressed_size;
        size_t input_size;
        size_t output_limit;
        size_t produced;
        uint8_t flags;
        uint32_t expected_crc32;
        uint32_t expected_size;
        tinfl_decompressor decompressor;
        tinfl_status status;

        if (source_size < GZIP_MINIMUM_SIZE) {
            return RETROFM_VGZ_TRUNCATED;
        }
        if (source[0] != 0x1FU || source[1] != 0x8BU) {
            return RETROFM_VGZ_BAD_MAGIC;
        }
        if (source[2] != 8U) {
            return RETROFM_VGZ_UNSUPPORTED_METHOD;
        }

        flags = source[3];
        if ((flags & GZIP_RESERVED_FLAGS) != 0U) {
            return RETROFM_VGZ_RESERVED_FLAGS;
        }

        trailer_position = source_size - GZIP_TRAILER_SIZE;
        position = GZIP_FIXED_HEADER_SIZE;

        if ((flags & GZIP_FLAG_EXTRA) != 0U) {
            uint16_t extra_length;

            if (!has_bytes(position, 2U, trailer_position)) {
                return RETROFM_VGZ_TRUNCATED;
            }
            extra_length = read_le_u16(source + position);
            position += 2U;
            if (!has_bytes(position, extra_length, trailer_position)) {
                return RETROFM_VGZ_TRUNCATED;
            }
            position += extra_length;
        }
        if ((flags & GZIP_FLAG_NAME) != 0U) {
            retrofm_vgz_result result =
                skip_zero_terminated(source, trailer_position, &position);
            if (result != RETROFM_VGZ_OK) {
                return result;
            }
        }
        if ((flags & GZIP_FLAG_COMMENT) != 0U) {
            retrofm_vgz_result result =
                skip_zero_terminated(source, trailer_position, &position);
            if (result != RETROFM_VGZ_OK) {
                return result;
            }
        }
        if ((flags & GZIP_FLAG_HEADER_CRC) != 0U) {
            uint16_t expected_header_crc;
            uint16_t actual_header_crc;

            if (!has_bytes(position, 2U, trailer_position)) {
                return RETROFM_VGZ_TRUNCATED;
            }
            expected_header_crc = read_le_u16(source + position);
            actual_header_crc = (uint16_t)gzip_crc32(source, position);
            if (expected_header_crc != actual_header_crc) {
                return RETROFM_VGZ_BAD_HEADER_CRC;
            }
            position += 2U;
        }

        compressed_size = trailer_position - position;
        expected_crc32 = read_le_u32(source + trailer_position);
        expected_size = read_le_u32(source + trailer_position + 4U);

        if ((uint64_t)expected_size > (uint64_t)max_decompressed_size) {
            return RETROFM_VGZ_LIMIT_EXCEEDED;
        }
        if ((uint64_t)expected_size > (uint64_t)output_capacity) {
            return RETROFM_VGZ_OUTPUT_TOO_SMALL;
        }

        output_limit = output_capacity;
        if (output_limit > max_decompressed_size) {
            output_limit = max_decompressed_size;
        }
        input_size = compressed_size;
        produced = output_limit;
        tinfl_init(&decompressor);
        status = tinfl_decompress(&decompressor,
                                  source + position,
                                  &input_size,
                                  output,
                                  output,
                                  &produced,
                                  TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);

        if (status == TINFL_STATUS_HAS_MORE_OUTPUT) {
            return output_limit == max_decompressed_size ?
                   RETROFM_VGZ_LIMIT_EXCEEDED :
                   RETROFM_VGZ_OUTPUT_TOO_SMALL;
        }
        if (status == TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS ||
            status == TINFL_STATUS_NEEDS_MORE_INPUT) {
            return RETROFM_VGZ_TRUNCATED;
        }
        if (status != TINFL_STATUS_DONE) {
            return RETROFM_VGZ_DEFLATE_ERROR;
        }
        if (input_size != compressed_size) {
            return RETROFM_VGZ_TRAILING_DATA;
        }
        if ((uint64_t)produced != (uint64_t)expected_size) {
            return RETROFM_VGZ_BAD_ISIZE;
        }
        if (gzip_crc32(output, produced) != expected_crc32) {
            return RETROFM_VGZ_BAD_CRC32;
        }

        *output_size = produced;
        return RETROFM_VGZ_OK;
    }
#endif
}

const char *retrofm_vgz_result_string(retrofm_vgz_result result) {
    switch (result) {
        case RETROFM_VGZ_OK: return "ok";
        case RETROFM_VGZ_UNAVAILABLE: return "VGZ support unavailable";
        case RETROFM_VGZ_BAD_ARGUMENT: return "bad argument";
        case RETROFM_VGZ_TRUNCATED: return "truncated gzip stream";
        case RETROFM_VGZ_BAD_MAGIC: return "bad gzip magic";
        case RETROFM_VGZ_UNSUPPORTED_METHOD: return "unsupported gzip method";
        case RETROFM_VGZ_RESERVED_FLAGS: return "reserved gzip flags set";
        case RETROFM_VGZ_BAD_HEADER_CRC: return "gzip header CRC mismatch";
        case RETROFM_VGZ_LIMIT_EXCEEDED: return "decompressed-size limit exceeded";
        case RETROFM_VGZ_OUTPUT_TOO_SMALL: return "output buffer too small";
        case RETROFM_VGZ_DEFLATE_ERROR: return "invalid DEFLATE stream";
        case RETROFM_VGZ_TRAILING_DATA: return "trailing gzip member data";
        case RETROFM_VGZ_BAD_CRC32: return "gzip data CRC mismatch";
        case RETROFM_VGZ_BAD_ISIZE: return "gzip uncompressed size mismatch";
        default: return "unknown VGZ error";
    }
}
