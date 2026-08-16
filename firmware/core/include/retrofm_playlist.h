/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_PLAYLIST_H
#define RETROFM_PLAYLIST_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RETROFM_PLAYLIST_MAX_TRACKS 128U
#define RETROFM_PLAYLIST_MAX_PDX_FILES 128U
#define RETROFM_PLAYLIST_MAX_OPNA_PCM_FILES 128U
#define RETROFM_PLAYLIST_PATH_CAPACITY 320U
#define RETROFM_PLAYLIST_NAME_CAPACITY 96U

typedef enum retrofm_track_format {
    RETROFM_TRACK_MDX = 0,
    RETROFM_TRACK_VGM,
    RETROFM_TRACK_VGZ
} retrofm_track_format;

typedef enum retrofm_playlist_result {
    RETROFM_PLAYLIST_OK = 0,
    RETROFM_PLAYLIST_IGNORED,
    RETROFM_PLAYLIST_BAD_ARGUMENT,
    RETROFM_PLAYLIST_PATH_TOO_LONG,
    RETROFM_PLAYLIST_FULL,
    RETROFM_PLAYLIST_DUPLICATE,
    RETROFM_PLAYLIST_FINALIZED
} retrofm_playlist_result;

typedef struct retrofm_playlist_entry {
    char path[RETROFM_PLAYLIST_PATH_CAPACITY];
    char pdx_path[RETROFM_PLAYLIST_PATH_CAPACITY];
    /* An OPNA input may carry a same-stem .pcm Delta-T image. It is never a
     * playable entry by itself. */
    char opna_pcm_path[RETROFM_PLAYLIST_PATH_CAPACITY];
    char display_name[RETROFM_PLAYLIST_NAME_CAPACITY];
    retrofm_track_format format;
} retrofm_playlist_entry;

typedef struct retrofm_playlist_pdx {
    char path[RETROFM_PLAYLIST_PATH_CAPACITY];
} retrofm_playlist_pdx;

typedef struct retrofm_playlist_opna_pcm {
    char path[RETROFM_PLAYLIST_PATH_CAPACITY];
} retrofm_playlist_opna_pcm;

typedef struct retrofm_playlist {
    retrofm_playlist_entry tracks[RETROFM_PLAYLIST_MAX_TRACKS];
    retrofm_playlist_pdx pdx_files[RETROFM_PLAYLIST_MAX_PDX_FILES];
    retrofm_playlist_opna_pcm
        opna_pcm_files[RETROFM_PLAYLIST_MAX_OPNA_PCM_FILES];
    size_t track_count;
    size_t pdx_count;
    size_t opna_pcm_count;
    bool finalized;
} retrofm_playlist;

void retrofm_playlist_init(retrofm_playlist *playlist);

/* Adds one regular file discovered below /music. Unsupported extensions are
 * deliberately reported as IGNORED. PDX files are retained only for later
 * same-directory, same-basename association with an MDX entry. */
retrofm_playlist_result retrofm_playlist_add_path(
    retrofm_playlist *playlist,
    const char *path);

/* Sorts playable entries case-insensitively and associates optional PDX files.
 * No additions are accepted after finalization. */
retrofm_playlist_result retrofm_playlist_finalize(
    retrofm_playlist *playlist);

const retrofm_playlist_entry *retrofm_playlist_get(
    const retrofm_playlist *playlist,
    size_t index);

/* Resolve the PDX name stored inside an MDX header.  The embedded name may
 * include or omit the .PDX suffix.  A file beside the MDX is preferred; an
 * unambiguous match elsewhere below /music is accepted as a fallback. */
const char *retrofm_playlist_find_pdx(
    const retrofm_playlist *playlist,
    const char *mdx_path,
    const uint8_t *embedded_name,
    size_t embedded_name_size);

const char *retrofm_track_format_string(retrofm_track_format format);
const char *retrofm_playlist_result_string(retrofm_playlist_result result);

#ifdef __cplusplus
}
#endif

#endif
