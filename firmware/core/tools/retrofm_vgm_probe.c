/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_vgm.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

enum { PROBE_FILE_LIMIT = 8U * 1024U * 1024U };

static uint8_t *read_file(const char *path, size_t *size) {
    FILE *file;
    long measured;
    uint8_t *bytes;
    if (path == NULL || size == NULL) return NULL;
    *size = 0U;
    file = fopen(path, "rb");
    if (file == NULL) return NULL;
    if (fseek(file, 0L, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    measured = ftell(file);
    if (measured <= 0L || (uint64_t)measured > PROBE_FILE_LIMIT ||
        fseek(file, 0L, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    bytes = (uint8_t *)malloc((size_t)measured);
    if (bytes == NULL ||
        fread(bytes, 1U, (size_t)measured, file) != (size_t)measured) {
        free(bytes);
        fclose(file);
        return NULL;
    }
    fclose(file);
    *size = (size_t)measured;
    return bytes;
}

int main(int argc, char **argv) {
    uint8_t *bytes;
    size_t size;
    retrofm_vgm vgm;
    retrofm_event event;
    retrofm_result result;
    uint64_t events = 0U;
    uint64_t cycles = 0U;
    char title[256];
    char artist[256];
    if (argc != 2) {
        fprintf(stderr, "usage: retrofm_vgm_probe file.vgm\n");
        return 64;
    }
    bytes = read_file(argv[1], &size);
    if (bytes == NULL) {
        fprintf(stderr, "READ_ERROR\t%s\n", argv[1]);
        return 2;
    }
    result = retrofm_vgm_open(&vgm, bytes, size, false);
    if (result != RETROFM_OK) {
        printf("PARSE_ERROR\t%s\t%s\n", retrofm_result_string(result),
               argv[1]);
        free(bytes);
        return 3;
    }
    title[0] = '\0';
    artist[0] = '\0';
    (void)retrofm_vgm_title(&vgm, title, sizeof(title));
    (void)retrofm_vgm_artist(&vgm, artist, sizeof(artist));
    while ((result = retrofm_vgm_next(&vgm, &event)) == RETROFM_OK) {
        ++events;
        cycles += event.delta_cycles;
    }
    if (result != RETROFM_END) {
        printf("STREAM_ERROR\t%s\t%s\n", retrofm_result_string(result),
               argv[1]);
        free(bytes);
        return 4;
    }
    printf("VGM_PASS\tchip=%s\tclock=%u\tevents=%llu\tcycles=%llu\ttitle=%s"
           "\tartist=%s\t%s\n",
           vgm.is_ym2608 ? "YM2608" : "YM2203",
           (unsigned)(vgm.is_ym2608 ? vgm.ym2608_clock_hz :
                                      vgm.ym2203_clock_hz),
           (unsigned long long)events,
           (unsigned long long)cycles,
           title, artist, argv[1]);
    free(bytes);
    return 0;
}
