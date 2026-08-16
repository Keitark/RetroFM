#include "retrofm_event.h"
#include "retrofm_vgm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

static int failures;

#define CHECK(condition) do {                                                   \
    if (!(condition)) {                                                        \
        fprintf(stderr, "%s:%d: CHECK failed: %s\n",                         \
                __FILE__, __LINE__, #condition);                               \
        ++failures;                                                            \
    }                                                                          \
} while (0)

static void put_u32(unsigned char *bytes, size_t offset, unsigned value) {
    bytes[offset] = (unsigned char)value;
    bytes[offset + 1U] = (unsigned char)(value >> 8U);
    bytes[offset + 2U] = (unsigned char)(value >> 16U);
    bytes[offset + 3U] = (unsigned char)(value >> 24U);
}

static void make_header(unsigned char *bytes, size_t size) {
    memset(bytes, 0, size);
    memcpy(bytes, "Vgm ", 4U);
    put_u32(bytes, 0x04U, (unsigned)(size - 4U));
    put_u32(bytes, 0x08U, 0x00000171U);
    put_u32(bytes, 0x34U, 0x4CU); /* data begins at 0x80 */
    put_u32(bytes, 0x44U, 4000000U);
}

static void make_ym2608_header(unsigned char *bytes, size_t size) {
    make_header(bytes, size);
    put_u32(bytes, 0x44U, 0U);
    put_u32(bytes, 0x48U, 7987200U);
}

static void test_event_pack(void) {
    retrofm_event source = { 123456U, RETROFM_OP_YM2151, 0x28U, 0x7FU, 5U };
    retrofm_event decoded;
    uint64_t packed = retrofm_event_pack(&source);

    CHECK(packed == UINT64_C(0x00507F280001E240));
    CHECK(retrofm_event_unpack(packed, &decoded));
    CHECK(source.delta_cycles == decoded.delta_cycles);
    CHECK(source.opcode == decoded.opcode);
    CHECK(source.reg == decoded.reg);
    CHECK(source.data == decoded.data);
    CHECK(source.flags == decoded.flags);
}

static void test_timebase_no_drift(void) {
    retrofm_timebase timebase;
    uint64_t cycles = 0U;
    unsigned i;

    retrofm_timebase_reset(&timebase);
    for (i = 0U; i < 44100U; ++i) {
        cycles += retrofm_vgm_samples_to_cycles(&timebase, 1U);
    }
    CHECK(cycles == RETROFM_PL_CLOCK_HZ);
    CHECK(timebase.remainder == 0U);
}

static void test_all_wait_forms(void) {
    unsigned char file[0xA0U];
    const unsigned char commands[] = {
        0x61U, 0x34U, 0x12U, 0x62U, 0x63U, 0x70U, 0x7FU,
        0x55U, 0x22U, 0x33U, 0x66U
    };
    const unsigned samples = 0x1234U + 735U + 882U + 1U + 16U;
    retrofm_vgm vgm;
    retrofm_event event;
    retrofm_timebase reference;
    uint64_t expected;

    make_header(file, sizeof(file));
    memcpy(file + 0x80U, commands, sizeof(commands));
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(vgm.ym2203_clock_hz == 4000000U);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    retrofm_timebase_reset(&reference);
    expected = retrofm_vgm_samples_to_cycles(&reference, samples);
    CHECK(event.delta_cycles == expected);
    CHECK(event.opcode == RETROFM_OP_YM2203);
    CHECK(event.reg == 0x22U && event.data == 0x33U);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_END);
}

static void test_data_block_and_trailing_wait(void) {
    unsigned char file[0xA0U];
    const unsigned char commands[] = {
        0x67U, 0x66U, 0x00U, 0x03U, 0x00U, 0x00U, 0x00U,
        0xAAU, 0xBBU, 0xCCU,
        0x55U, 0x07U, 0x38U,
        0x70U, 0x66U
    };
    retrofm_vgm vgm;
    retrofm_event event;

    make_header(file, sizeof(file));
    memcpy(file + 0x80U, commands, sizeof(commands));
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    CHECK(event.opcode == RETROFM_OP_YM2203 && event.reg == 7U);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    CHECK(event.opcode == RETROFM_OP_DELAY);
    CHECK(event.delta_cycles == 2267U);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_END);
}

static void test_ym2608_ports(void) {
    unsigned char file[0xA0U];
    const unsigned char commands[] = {
        0x56U, 0x28U, 0xF0U, 0x70U,
        0x57U, 0xA4U, 0x22U, 0x66U
    };
    retrofm_vgm vgm;
    retrofm_event event;

    make_ym2608_header(file, sizeof(file));
    memcpy(file + 0x80U, commands, sizeof(commands));
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(vgm.is_ym2608);
    CHECK(vgm.ym2203_clock_hz == 0U);
    CHECK(vgm.ym2608_clock_hz == 7987200U);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    CHECK(event.opcode == RETROFM_OP_YM2608);
    CHECK(event.flags == 0U);
    CHECK(event.reg == 0x28U && event.data == 0xF0U);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    CHECK(event.opcode == RETROFM_OP_YM2608);
    CHECK(event.flags == RETROFM_EVENT_FLAG_OPNA_PORT1);
    CHECK(event.reg == 0xA4U && event.data == 0x22U);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_END);

    make_ym2608_header(file, sizeof(file));
    file[0x80U] = 0x55U;
    file[0x81U] = 0x28U;
    file[0x82U] = 0x00U;
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_UNSUPPORTED_COMMAND);

    make_ym2608_header(file, sizeof(file));
    file[0x80U] = 0x67U;
    file[0x81U] = 0x66U;
    file[0x82U] = 0x81U; /* YM2608 Delta-T sample-ROM block. */
    put_u32(file, 0x83U, 0U);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_UNSUPPORTED_COMMAND);
}

static void test_loop(void) {
    unsigned char file[0x90U];
    const unsigned char commands[] = {
        0x55U, 0x28U, 0xF0U, 0x70U, 0x66U
    };
    retrofm_vgm vgm;
    retrofm_event event;

    make_header(file, sizeof(file));
    memcpy(file + 0x80U, commands, sizeof(commands));
    put_u32(file, 0x1CU, 0x80U - 0x1CU);
    put_u32(file, 0x20U, 1U);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), true) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    CHECK(event.reg == 0x28U && event.delta_cycles == 0U);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    CHECK(event.opcode == RETROFM_OP_DELAY);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    CHECK(event.reg == 0x28U && vgm.loop_count == 1U);
}

static void test_zero_time_and_non_boundary_loops(void) {
    unsigned char file[0x90U];
    const unsigned char zero_time_commands[] = {
        0x55U, 0x28U, 0xF0U, 0x66U
    };
    const unsigned char timed_commands[] = {
        0x55U, 0x28U, 0xF0U, 0x70U, 0x66U
    };
    retrofm_vgm vgm;
    retrofm_event event;

    make_header(file, sizeof(file));
    memcpy(file + 0x80U, zero_time_commands, sizeof(zero_time_commands));
    put_u32(file, 0x1CU, 0x80U - 0x1CU);
    /* Deliberately lie in the header: the command stream has no wait. */
    put_u32(file, 0x20U, 1234U);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), true) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_BAD_LOOP);

    make_header(file, sizeof(file));
    memcpy(file + 0x80U, timed_commands, sizeof(timed_commands));
    /* Point into the YM2203 command operands rather than at a command. */
    put_u32(file, 0x1CU, 0x81U - 0x1CU);
    put_u32(file, 0x20U, 1U);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_BAD_LOOP);
}

static void test_rejections(void) {
    unsigned char file[0x90U];
    retrofm_vgm vgm;
    retrofm_event event;

    make_header(file, sizeof(file));
    file[0x80U] = 0x66U;

    put_u32(file, 0x44U, 0x40400000U);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_MULTI_CHIP);

    make_header(file, sizeof(file));
    put_u32(file, 0x30U, 3579545U);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) ==
          RETROFM_UNSUPPORTED_CHIP);

    make_header(file, sizeof(file));
    file[0x80U] = 0x54U;
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_UNSUPPORTED_COMMAND);

    make_header(file, sizeof(file));
    file[0x80U] = 0x55U;
    file[0x81U] = 0x22U;
    put_u32(file, 0x04U, 0x7EU);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(retrofm_vgm_next(&vgm, &event) == RETROFM_TRUNCATED);

    make_header(file, sizeof(file));
    file[0x80U] = 0x66U;
    put_u32(file, 0x1CU, 0x80U - 0x1CU);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), true) ==
          RETROFM_BAD_LOOP);
}

static void test_late_header_and_extra_header(void) {
    unsigned char file[0x120U];
    retrofm_vgm vgm;

    make_header(file, sizeof(file));
    put_u32(file, 0x34U, 0x100U - 0x34U);
    file[0x100U] = 0x66U;
    put_u32(file, 0xC0U, 3072000U); /* WonderSwan */
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) ==
          RETROFM_UNSUPPORTED_CHIP);

    make_header(file, sizeof(file));
    put_u32(file, 0x34U, 0x100U - 0x34U);
    file[0x100U] = 0x66U;
    put_u32(file, 0xBCU, 4U);
    put_u32(file, 0xC0U, 12U);
    put_u32(file, 0xC8U, 4U);
    file[0xCCU] = 1U; /* one well-formed chip-volume entry */
    file[0xCDU] = 0x86U;
    file[0xCEU] = 0U;
    file[0xCFU] = 0U;
    file[0xD0U] = 0x82U;
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);

    put_u32(file, 0xC4U, 8U);
    file[0xCCU] = 1U; /* one second-chip clock entry */
    file[0xCDU] = 6U;
    put_u32(file, 0xCEU, 4000000U);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) ==
          RETROFM_MULTI_CHIP);

    put_u32(file, 0xC4U, 0U);
    put_u32(file, 0xC8U, 0x1000U);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) ==
          RETROFM_BAD_HEADER);
}

static void test_gd3_title(void) {
    unsigned char file[0xC0U];
    const unsigned char commands[] = { 0x66U };
    const unsigned char gd3[] = {
        'G','d','3',' ', 0x00,0x01,0x00,0x00, 0x0A,0x00,0x00,0x00,
        'T',0,'e',0,'s',0,'t',0,0,0
    };
    retrofm_vgm vgm;
    char title[16];

    make_header(file, sizeof(file));
    memcpy(file + 0x80U, commands, sizeof(commands));
    memcpy(file + 0xA0U, gd3, sizeof(gd3));
    put_u32(file, 0x14U, 0xA0U - 0x14U);
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(retrofm_vgm_title(&vgm, title, sizeof(title)) == RETROFM_OK);
    CHECK(strcmp(title, "Test") == 0);

    put_u32(file, 0xA8U, 9U); /* odd UTF-16 payload length */
    CHECK(retrofm_vgm_open(&vgm, file, sizeof(file), false) == RETROFM_OK);
    CHECK(retrofm_vgm_title(&vgm, title, sizeof(title)) ==
          RETROFM_BAD_HEADER);
}

int main(void) {
    test_event_pack();
    test_timebase_no_drift();
    test_all_wait_forms();
    test_data_block_and_trailing_wait();
    test_ym2608_ports();
    test_loop();
    test_zero_time_and_non_boundary_loops();
    test_rejections();
    test_late_header_and_extra_header();
    test_gd3_title();

    if (failures != 0) {
        fprintf(stderr, "%d test(s) failed\n", failures);
        return EXIT_FAILURE;
    }
    puts("retrofm core tests passed");
    return EXIT_SUCCESS;
}
