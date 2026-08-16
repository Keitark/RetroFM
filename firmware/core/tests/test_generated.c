// SPDX-License-Identifier: GPL-3.0-or-later

#include "retrofm_mdx.h"
#include "retrofm_pdx.h"
#include "retrofm_vgm.h"
#include "retrofm_vgz.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef RETROFM_TESTDATA_DIR
#error RETROFM_TESTDATA_DIR must name the generated testdata directory
#endif

#define CHECK(condition)                                                     \
    do {                                                                     \
        if (!(condition)) {                                                  \
            fprintf(stderr, "CHECK failed at %s:%d: %s\n",                 \
                    __FILE__, __LINE__, #condition);                         \
            return 1;                                                        \
        }                                                                    \
    } while (0)

typedef struct file_buffer {
    unsigned char *data;
    size_t size;
} file_buffer;

static int load_file(const char *name, file_buffer *buffer) {
    char path[1024];
    FILE *file;
    long length;
    int written = snprintf(path, sizeof(path), "%s/%s",
                           RETROFM_TESTDATA_DIR, name);
    if (written < 0 || (size_t)written >= sizeof(path)) return 0;
    file = fopen(path, "rb");
    if (file == NULL) return 0;
    if (fseek(file, 0L, SEEK_END) != 0) {
        fclose(file);
        return 0;
    }
    length = ftell(file);
    if (length < 0 || fseek(file, 0L, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
    buffer->data = (unsigned char *)malloc((size_t)length);
    buffer->size = (size_t)length;
    if (buffer->data == NULL ||
        fread(buffer->data, 1U, buffer->size, file) != buffer->size) {
        free(buffer->data);
        buffer->data = NULL;
        buffer->size = 0U;
        fclose(file);
        return 0;
    }
    fclose(file);
    return 1;
}

static void release_file(file_buffer *buffer) {
    free(buffer->data);
    buffer->data = NULL;
    buffer->size = 0U;
}

static int test_vgm_and_vgz(void) {
    file_buffer vgm_file = {0};
    file_buffer vgz_file = {0};
    unsigned char inflated[2048];
    size_t inflated_size = 0U;
    retrofm_vgm vgm;
    retrofm_event event;
    char title[80];
    size_t writes = 0U;
    size_t timed_writes = 0U;
    retrofm_result result;

    CHECK(load_file("retrofm_ym2203_demo.vgm", &vgm_file));
    CHECK(retrofm_vgm_open(&vgm, vgm_file.data, vgm_file.size, false) ==
          RETROFM_OK);
    CHECK(vgm.ym2203_clock_hz == 4000000U);
    CHECK(retrofm_vgm_title(&vgm, title, sizeof(title)) == RETROFM_OK);
    CHECK(strcmp(title, "RetroFM YM2203 FM + SSG Demo") == 0);
    CHECK(retrofm_vgm_artist(&vgm, title, sizeof(title)) == RETROFM_OK);
    CHECK(strcmp(title, "RetroFM project") == 0);
    do {
        result = retrofm_vgm_next(&vgm, &event);
        if (result == RETROFM_OK) {
            if (event.opcode == RETROFM_OP_YM2203) {
                ++writes;
                if (event.delta_cycles != 0U) ++timed_writes;
            }
        }
    } while (result == RETROFM_OK);
    CHECK(result == RETROFM_END);
    CHECK(writes >= 40U);
    /* Three subsequent notes and the final key-off each carry the preceding
     * quarter-note wait; the first note begins at delta zero. */
    CHECK(timed_writes == 4U);

#if RETROFM_HAS_VGZ
    CHECK(load_file("retrofm_ym2203_demo.vgz", &vgz_file));
    CHECK(retrofm_vgz_decompress(vgz_file.data, vgz_file.size,
                                  inflated, sizeof(inflated),
                                  sizeof(inflated), &inflated_size) ==
          RETROFM_VGZ_OK);
    CHECK(inflated_size == vgm_file.size);
    CHECK(memcmp(inflated, vgm_file.data, inflated_size) == 0);
    release_file(&vgz_file);
#endif
    release_file(&vgm_file);
    return 0;
}

static int test_mdx_and_pdx(void) {
    file_buffer fm_file = {0};
    file_buffer lr_file = {0};
    file_buffer pcm_mdx_file = {0};
    file_buffer pdx_file = {0};
    retrofm_mdx mdx;
    retrofm_pdx pdx;
    retrofm_adpcm_decoder decoder;
    const uint8_t *sample_bytes;
    size_t sample_length;
    size_t decoded = 0U;
    int16_t sample;
    retrofm_pdx_result result;

    CHECK(load_file("retrofm_ym2151_demo.mdx", &fm_file));
    CHECK(retrofm_mdx_open(&mdx, fm_file.data, fm_file.size) ==
          RETROFM_MDX_OK);
    CHECK(!mdx.uses_pdx);
    CHECK(mdx.pdx_name.size == 0U);
    release_file(&fm_file);

    CHECK(load_file("retrofm_ym2151_lr_test.mdx", &lr_file));
    CHECK(retrofm_mdx_open(&mdx, lr_file.data, lr_file.size) ==
          RETROFM_MDX_OK);
    CHECK(!mdx.uses_pdx);
    CHECK(mdx.pdx_name.size == 0U);
    release_file(&lr_file);

    CHECK(load_file("retrofm_ym2151_pdx_demo.mdx", &pcm_mdx_file));
    CHECK(retrofm_mdx_open(&mdx, pcm_mdx_file.data, pcm_mdx_file.size) ==
          RETROFM_MDX_OK);
    CHECK(mdx.uses_pdx);
    CHECK(mdx.pdx_name.size == strlen("RETROFM_YM2151_PDX_DEMO.PDX"));

    CHECK(load_file("retrofm_ym2151_pdx_demo.pdx", &pdx_file));
    CHECK(retrofm_pdx_open(&pdx, pdx_file.data, pdx_file.size) ==
          RETROFM_PDX_OK);
    CHECK(retrofm_pdx_get_sample(&pdx, 0U, &sample_bytes, &sample_length) ==
          RETROFM_PDX_OK);
    CHECK(sample_length == 256U);
    CHECK(retrofm_adpcm_begin(&decoder, sample_bytes, sample_length) ==
          RETROFM_PDX_OK);
    do {
        result = retrofm_adpcm_next(&decoder, &sample);
        if (result == RETROFM_PDX_OK) ++decoded;
    } while (result == RETROFM_PDX_OK);
    CHECK(result == RETROFM_PDX_END);
    CHECK(decoded == 512U);

    release_file(&pdx_file);
    release_file(&pcm_mdx_file);
    return 0;
}

int main(void) {
    CHECK(test_vgm_and_vgz() == 0);
    CHECK(test_mdx_and_pdx() == 0);
    puts("generated RetroFM smoke files validated");
    return 0;
}
