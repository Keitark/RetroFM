/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_mdx_sequence.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    PROBE_FILE_LIMIT = 8U * 1024U * 1024U
};

#define PROBE_TICK_LIMIT UINT64_C(10000000)

typedef struct probe_counts {
    uint64_t events;
    uint64_t pcm_commands;
} probe_counts;

typedef struct probe_command_counts {
    uint64_t informal_fm;
    uint64_t pcm8_bank;
    uint64_t pcm8_enable;
} probe_command_counts;

static bool count_event(void *user, const retrofm_event *event) {
    probe_counts *counts = (probe_counts *)user;
    if (counts == NULL || event == NULL) return false;
    ++counts->events;
    return true;
}

static bool count_pcm(void *user,
                      const retrofm_mdx_pcm_command *command) {
    probe_counts *counts = (probe_counts *)user;
    if (counts == NULL || command == NULL) return false;
    ++counts->pcm_commands;
    return true;
}

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
    if (bytes == NULL) {
        fclose(file);
        return NULL;
    }
    if (fread(bytes, 1U, (size_t)measured, file) != (size_t)measured) {
        free(bytes);
        fclose(file);
        return NULL;
    }
    fclose(file);
    *size = (size_t)measured;
    return bytes;
}

static int probe_pdx_file(const char *path) {
    uint8_t *bytes;
    size_t size;
    size_t index;
    size_t populated = 0U;
    uint64_t encoded_bytes = 0U;
    uint64_t decoded_samples = 0U;
    retrofm_pdx pdx;
    retrofm_pdx_result result;

    bytes = read_file(path, &size);
    if (bytes == NULL) {
        printf("PDX_READ_ERROR\t%s\n", path);
        return 5;
    }
    result = retrofm_pdx_open(&pdx, bytes, size);
    if (result != RETROFM_PDX_OK) {
        printf("PDX_PARSE_ERROR\t%s\t%s\n",
               retrofm_pdx_result_string(result), path);
        free(bytes);
        return 6;
    }
    for (index = 0U; index < RETROFM_PDX_SAMPLE_COUNT; ++index) {
        if (pdx.entries[index].length != 0U) {
            const uint8_t *sample_bytes;
            size_t sample_size;
            retrofm_adpcm_decoder decoder;
            int16_t sample;
            ++populated;
            encoded_bytes += pdx.entries[index].length;
            result = retrofm_pdx_get_sample(&pdx, index,
                                            &sample_bytes, &sample_size);
            if (result != RETROFM_PDX_OK) {
                printf("PDX_SAMPLE_ERROR\t%u\t%s\t%s\n", (unsigned)index,
                       retrofm_pdx_result_string(result), path);
                free(bytes);
                return 7;
            }
            result = retrofm_adpcm_begin(&decoder, sample_bytes, sample_size);
            if (result != RETROFM_PDX_OK) {
                printf("PDX_DECODE_ERROR\t%u\t%s\t%s\n", (unsigned)index,
                       retrofm_pdx_result_string(result), path);
                free(bytes);
                return 8;
            }
            while ((result = retrofm_adpcm_next(&decoder, &sample)) ==
                   RETROFM_PDX_OK) {
                ++decoded_samples;
            }
            if (result != RETROFM_PDX_END ||
                retrofm_adpcm_samples_remaining(&decoder) != 0U) {
                printf("PDX_DECODE_ERROR\t%u\t%s\t%s\n", (unsigned)index,
                       retrofm_pdx_result_string(result), path);
                free(bytes);
                return 8;
            }
        }
    }
    printf("PDX_PASS\tsamples=%u\tpopulated=%u\tencoded_bytes=%llu"
           "\tdecoded_samples=%llu\t%s\n",
           (unsigned)RETROFM_PDX_SAMPLE_COUNT, (unsigned)populated,
           (unsigned long long)encoded_bytes,
           (unsigned long long)decoded_samples, path);
    free(bytes);
    return 0;
}

static bool first_pass_complete(const retrofm_mdx_sequencer *sequencer) {
    size_t index;
    if (sequencer == NULL || sequencer->mdx == NULL) return false;
    for (index = 0U; index < sequencer->mdx->track_count; ++index) {
        const retrofm_mdx_track_state *track = &sequencer->tracks[index];
        if (track->used && !track->ended && track->loop_count == 0U) {
            return false;
        }
    }
    return true;
}

static void count_static_commands(const retrofm_mdx *mdx,
                                  probe_command_counts *counts) {
    size_t track_index;
    if (mdx == NULL || counts == NULL) return;
    for (track_index = 0U; track_index < mdx->track_count; ++track_index) {
        const retrofm_mdx_span *track = &mdx->tracks[track_index];
        size_t position = 0U;
        while (position < track->size) {
            retrofm_mdx_result result;
            size_t length = retrofm_mdx_command_size(
                track->data + position, track->size - position, &result);
            uint8_t opcode;
            if (length == 0U || result != RETROFM_MDX_OK) return;
            opcode = track->data[position];
            if (opcode >= 0xE0U && opcode <= 0xE6U) {
                if (track_index < 8U) {
                    ++counts->informal_fm;
                } else {
                    ++counts->pcm8_bank;
                }
            } else if (opcode == 0xE8U) {
                ++counts->pcm8_enable;
            }
            position += length;
        }
    }
}

int main(int argc, char **argv) {
    uint8_t *mdx_bytes;
    uint8_t *pdx_bytes = NULL;
    size_t mdx_size;
    size_t pdx_size = 0U;
    retrofm_mdx mdx;
    retrofm_pdx pdx;
    retrofm_mdx_sequencer sequencer;
    retrofm_mdx_result result;
    probe_counts counts = {0U, 0U};
    probe_command_counts command_counts = {0U, 0U, 0U};
    uint64_t ticks;
    const char *outcome = "LIMIT";

    if (argc == 3 && strcmp(argv[1], "--pdx") == 0) {
        return probe_pdx_file(argv[2]);
    }
    if (argc < 2 || argc > 3) {
        fprintf(stderr,
                "usage: retrofm_mdx_probe file.mdx [file.pdx]\n"
                "       retrofm_mdx_probe --pdx file.pdx\n");
        return 64;
    }
    mdx_bytes = read_file(argv[1], &mdx_size);
    if (mdx_bytes == NULL) {
        printf("READ_ERROR\t%s\n", argv[1]);
        return 2;
    }
    result = retrofm_mdx_open(&mdx, mdx_bytes, mdx_size);
    if (result != RETROFM_MDX_OK) {
        printf("PARSE_ERROR\t%s\t%s\n", retrofm_mdx_result_string(result),
               argv[1]);
        free(mdx_bytes);
        return 3;
    }
    count_static_commands(&mdx, &command_counts);
    if (mdx.uses_pdx) {
        retrofm_pdx_result pdx_result;
        if (argc != 3) {
            printf("NEEDS_PDX\t%.*s\t%s\n", (int)mdx.pdx_name.size,
                   (const char *)mdx.pdx_name.data, argv[1]);
            free(mdx_bytes);
            return 4;
        }
        pdx_bytes = read_file(argv[2], &pdx_size);
        if (pdx_bytes == NULL) {
            printf("PDX_READ_ERROR\t%s\t%s\n", argv[2], argv[1]);
            free(mdx_bytes);
            return 5;
        }
        pdx_result = retrofm_pdx_open(&pdx, pdx_bytes, pdx_size);
        if (pdx_result != RETROFM_PDX_OK) {
            printf("PDX_PARSE_ERROR\t%s\t%s\t%s\n",
                   retrofm_pdx_result_string(pdx_result), argv[2], argv[1]);
            free(pdx_bytes);
            free(mdx_bytes);
            return 6;
        }
        result = retrofm_mdx_sequencer_init_with_pdx(
            &sequencer, &mdx, &pdx, count_event, &counts,
            count_pcm, &counts);
    } else {
        result = retrofm_mdx_sequencer_init(&sequencer, &mdx,
                                             count_event, &counts);
    }
    if (result != RETROFM_MDX_OK) {
        printf("INIT_ERROR\t%s\t%s\n", retrofm_mdx_result_string(result),
               argv[1]);
        free(pdx_bytes);
        free(mdx_bytes);
        return 7;
    }

    for (ticks = 0U; ticks < PROBE_TICK_LIMIT; ++ticks) {
        result = retrofm_mdx_sequencer_tick(&sequencer);
        if (result == RETROFM_MDX_END ||
            retrofm_mdx_sequencer_ended(&sequencer)) {
            outcome = "PASS_END";
            break;
        }
        if (result != RETROFM_MDX_OK) {
            printf("SEQUENCE_ERROR\t%s\t%llu\t%s\n",
                   retrofm_mdx_result_string(result),
                   (unsigned long long)(ticks + 1U), argv[1]);
            free(pdx_bytes);
            free(mdx_bytes);
            return 8;
        }
        if (first_pass_complete(&sequencer)) {
            outcome = "PASS_LOOP";
            break;
        }
    }
    printf("%s\ttracks=%u\tpdx=%u\tticks=%llu\tevents=%llu\tpcm=%llu"
           "\tinformal_fm=%llu\tpcm8_bank=%llu\tpcm8_enable=%llu\t%s\n",
           outcome, (unsigned)mdx.track_count, mdx.uses_pdx ? 1U : 0U,
           (unsigned long long)(ticks + (ticks < PROBE_TICK_LIMIT ? 1U : 0U)),
           (unsigned long long)counts.events,
           (unsigned long long)counts.pcm_commands,
           (unsigned long long)command_counts.informal_fm,
           (unsigned long long)command_counts.pcm8_bank,
           (unsigned long long)command_counts.pcm8_enable, argv[1]);
    free(pdx_bytes);
    free(mdx_bytes);
    return outcome[0] == 'P' ? 0 : 9;
}
