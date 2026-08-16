/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_playlist.h"

#include <stdint.h>
#include <string.h>

typedef enum path_kind {
    PATH_KIND_OTHER = 0,
    PATH_KIND_MDX,
    PATH_KIND_VGM,
    PATH_KIND_VGZ,
    PATH_KIND_PDX,
    PATH_KIND_OPNA_PCM
} path_kind;

static unsigned char ascii_lower(unsigned char value) {
    if (value >= (unsigned char)'A' && value <= (unsigned char)'Z') {
        return (unsigned char)(value + ((unsigned char)'a' -
                                       (unsigned char)'A'));
    }
    return value;
}

static int ascii_case_compare(const char *left, const char *right) {
    size_t position = 0U;
    for (;;) {
        unsigned char a = ascii_lower((unsigned char)left[position]);
        unsigned char b = ascii_lower((unsigned char)right[position]);
        if (a != b) return a < b ? -1 : 1;
        if (a == 0U) return 0;
        ++position;
    }
}

static size_t bounded_length(const char *text, size_t capacity) {
    size_t length = 0U;
    if (text == NULL) return SIZE_MAX;
    while (length < capacity && text[length] != '\0') ++length;
    return length;
}

static const char *extension(const char *path) {
    const char *last_dot = NULL;
    const char *cursor = path;
    while (*cursor != '\0') {
        if (*cursor == '/' || *cursor == '\\') {
            last_dot = NULL;
        } else if (*cursor == '.') {
            last_dot = cursor;
        }
        ++cursor;
    }
    return last_dot;
}

static bool extension_is(const char *value, const char *expected) {
    return value != NULL && ascii_case_compare(value, expected) == 0;
}

static path_kind classify_path(const char *path) {
    const char *suffix = extension(path);
    if (extension_is(suffix, ".mdx")) return PATH_KIND_MDX;
    if (extension_is(suffix, ".vgm")) return PATH_KIND_VGM;
    if (extension_is(suffix, ".vgz")) return PATH_KIND_VGZ;
    if (extension_is(suffix, ".pdx")) return PATH_KIND_PDX;
    if (extension_is(suffix, ".pcm")) return PATH_KIND_OPNA_PCM;
    return PATH_KIND_OTHER;
}

static void make_display_name(char *destination, const char *path) {
    const char *name = path;
    const char *cursor = path;
    const char *suffix = extension(path);
    size_t amount;

    while (*cursor != '\0') {
        if (*cursor == '/' || *cursor == '\\') name = cursor + 1;
        ++cursor;
    }
    amount = suffix != NULL && suffix >= name ?
        (size_t)(suffix - name) : strlen(name);
    if (amount >= RETROFM_PLAYLIST_NAME_CAPACITY) {
        amount = RETROFM_PLAYLIST_NAME_CAPACITY - 1U;
    }
    if (amount != 0U) memcpy(destination, name, amount);
    destination[amount] = '\0';
}

static bool same_stem(const char *left, const char *right) {
    const char *left_extension = extension(left);
    const char *right_extension = extension(right);
    size_t left_length;
    size_t right_length;
    size_t index;

    if (left_extension == NULL || right_extension == NULL) return false;
    left_length = (size_t)(left_extension - left);
    right_length = (size_t)(right_extension - right);
    if (left_length != right_length) return false;
    for (index = 0U; index < left_length; ++index) {
        if (ascii_lower((unsigned char)left[index]) !=
            ascii_lower((unsigned char)right[index])) return false;
    }
    return true;
}

static const char *base_name(const char *path) {
    const char *name = path;
    const char *cursor = path;
    while (*cursor != '\0') {
        if (*cursor == '/' || *cursor == '\\') name = cursor + 1;
        ++cursor;
    }
    return name;
}

static size_t directory_length(const char *path) {
    const char *name = base_name(path);
    return (size_t)(name - path);
}

static bool same_directory(const char *left, const char *right) {
    size_t left_length = directory_length(left);
    size_t right_length = directory_length(right);
    size_t index;
    if (left_length != right_length) return false;
    for (index = 0U; index < left_length; ++index) {
        if (ascii_lower((unsigned char)left[index]) !=
            ascii_lower((unsigned char)right[index])) return false;
    }
    return true;
}

static bool embedded_pdx_matches(const char *path,
                                 const uint8_t *embedded_name,
                                 size_t embedded_name_size) {
    const char *name = base_name(path);
    const char *suffix = extension(path);
    size_t stem_size;
    size_t requested_size = embedded_name_size;
    size_t index;

    if (!extension_is(suffix, ".pdx") || suffix < name) return false;
    stem_size = (size_t)(suffix - name);
    if (requested_size >= 4U &&
        embedded_name[requested_size - 4U] == (uint8_t)'.' &&
        ascii_lower(embedded_name[requested_size - 3U]) ==
            (unsigned char)'p' &&
        ascii_lower(embedded_name[requested_size - 2U]) ==
            (unsigned char)'d' &&
        ascii_lower(embedded_name[requested_size - 1U]) ==
            (unsigned char)'x') {
        requested_size -= 4U;
    }
    if (requested_size == 0U || requested_size != stem_size) return false;
    for (index = 0U; index < requested_size; ++index) {
        if (ascii_lower(embedded_name[index]) !=
            ascii_lower((unsigned char)name[index])) return false;
    }
    return true;
}

void retrofm_playlist_init(retrofm_playlist *playlist) {
    if (playlist != NULL) memset(playlist, 0, sizeof(*playlist));
}

retrofm_playlist_result retrofm_playlist_add_path(
    retrofm_playlist *playlist,
    const char *path) {
    size_t path_length;
    size_t index;
    path_kind kind;

    if (playlist == NULL || path == NULL || path[0] == '\0') {
        return RETROFM_PLAYLIST_BAD_ARGUMENT;
    }
    if (playlist->finalized) return RETROFM_PLAYLIST_FINALIZED;
    path_length = bounded_length(path, RETROFM_PLAYLIST_PATH_CAPACITY);
    if (path_length == SIZE_MAX ||
        path_length >= RETROFM_PLAYLIST_PATH_CAPACITY) {
        return RETROFM_PLAYLIST_PATH_TOO_LONG;
    }
    kind = classify_path(path);
    if (kind == PATH_KIND_OTHER) return RETROFM_PLAYLIST_IGNORED;

    if (kind == PATH_KIND_PDX) {
        for (index = 0U; index < playlist->pdx_count; ++index) {
            if (ascii_case_compare(playlist->pdx_files[index].path, path) == 0) {
                return RETROFM_PLAYLIST_DUPLICATE;
            }
        }
        if (playlist->pdx_count >= RETROFM_PLAYLIST_MAX_PDX_FILES) {
            return RETROFM_PLAYLIST_FULL;
        }
        memcpy(playlist->pdx_files[playlist->pdx_count].path,
               path, path_length + 1U);
        ++playlist->pdx_count;
        return RETROFM_PLAYLIST_OK;
    }

    if (kind == PATH_KIND_OPNA_PCM) {
        for (index = 0U; index < playlist->opna_pcm_count; ++index) {
            if (ascii_case_compare(playlist->opna_pcm_files[index].path,
                                   path) == 0) {
                return RETROFM_PLAYLIST_DUPLICATE;
            }
        }
        if (playlist->opna_pcm_count >= RETROFM_PLAYLIST_MAX_OPNA_PCM_FILES) {
            return RETROFM_PLAYLIST_FULL;
        }
        memcpy(playlist->opna_pcm_files[playlist->opna_pcm_count].path,
               path, path_length + 1U);
        ++playlist->opna_pcm_count;
        return RETROFM_PLAYLIST_OK;
    }

    for (index = 0U; index < playlist->track_count; ++index) {
        if (ascii_case_compare(playlist->tracks[index].path, path) == 0) {
            return RETROFM_PLAYLIST_DUPLICATE;
        }
    }
    if (playlist->track_count >= RETROFM_PLAYLIST_MAX_TRACKS) {
        return RETROFM_PLAYLIST_FULL;
    }
    {
        retrofm_playlist_entry *entry = &playlist->tracks[playlist->track_count];
        memset(entry, 0, sizeof(*entry));
        memcpy(entry->path, path, path_length + 1U);
        make_display_name(entry->display_name, path);
        if (kind == PATH_KIND_MDX) entry->format = RETROFM_TRACK_MDX;
        else if (kind == PATH_KIND_VGM) entry->format = RETROFM_TRACK_VGM;
        else entry->format = RETROFM_TRACK_VGZ;
    }
    ++playlist->track_count;
    return RETROFM_PLAYLIST_OK;
}

retrofm_playlist_result retrofm_playlist_finalize(
    retrofm_playlist *playlist) {
    size_t index;

    if (playlist == NULL) return RETROFM_PLAYLIST_BAD_ARGUMENT;
    if (playlist->finalized) return RETROFM_PLAYLIST_FINALIZED;

    for (index = 1U; index < playlist->track_count; ++index) {
        retrofm_playlist_entry entry = playlist->tracks[index];
        size_t position = index;
        while (position > 0U &&
               ascii_case_compare(entry.path,
                                  playlist->tracks[position - 1U].path) < 0) {
            playlist->tracks[position] = playlist->tracks[position - 1U];
            --position;
        }
        playlist->tracks[position] = entry;
    }

    for (index = 0U; index < playlist->track_count; ++index) {
        retrofm_playlist_entry *entry = &playlist->tracks[index];
        size_t pdx_index;
        if (entry->format == RETROFM_TRACK_MDX) {
            for (pdx_index = 0U; pdx_index < playlist->pdx_count;
                 ++pdx_index) {
                if (same_stem(entry->path,
                              playlist->pdx_files[pdx_index].path)) {
                    size_t length = strlen(playlist->pdx_files[pdx_index].path);
                    memcpy(entry->pdx_path,
                           playlist->pdx_files[pdx_index].path,
                           length + 1U);
                    break;
                }
            }
        }
        if (entry->format == RETROFM_TRACK_VGM ||
            entry->format == RETROFM_TRACK_VGZ) {
            size_t pcm_index;
            for (pcm_index = 0U; pcm_index < playlist->opna_pcm_count;
                 ++pcm_index) {
                const char *candidate =
                    playlist->opna_pcm_files[pcm_index].path;
                if (same_stem(entry->path, candidate) &&
                    same_directory(entry->path, candidate)) {
                    size_t length = strlen(candidate);
                    memcpy(entry->opna_pcm_path, candidate, length + 1U);
                    break;
                }
            }
        }
    }
    playlist->finalized = true;
    return RETROFM_PLAYLIST_OK;
}

const retrofm_playlist_entry *retrofm_playlist_get(
    const retrofm_playlist *playlist,
    size_t index) {
    if (playlist == NULL || !playlist->finalized ||
        index >= playlist->track_count) return NULL;
    return &playlist->tracks[index];
}

const char *retrofm_playlist_find_pdx(
    const retrofm_playlist *playlist,
    const char *mdx_path,
    const uint8_t *embedded_name,
    size_t embedded_name_size) {
    const char *fallback = NULL;
    size_t index;

    if (playlist == NULL || !playlist->finalized || mdx_path == NULL ||
        embedded_name == NULL || embedded_name_size == 0U) return NULL;
    for (index = 0U; index < playlist->pdx_count; ++index) {
        const char *candidate = playlist->pdx_files[index].path;
        if (!embedded_pdx_matches(candidate, embedded_name,
                                  embedded_name_size)) continue;
        if (same_directory(mdx_path, candidate)) return candidate;
        if (fallback != NULL) return NULL;
        fallback = candidate;
    }
    return fallback;
}

const char *retrofm_track_format_string(retrofm_track_format format) {
    switch (format) {
        case RETROFM_TRACK_MDX: return "MDX / YM2151";
        case RETROFM_TRACK_VGM: return "VGM / YM2203";
        case RETROFM_TRACK_VGZ: return "VGZ / YM2203";
        default: return "unknown";
    }
}

const char *retrofm_playlist_result_string(retrofm_playlist_result result) {
    switch (result) {
        case RETROFM_PLAYLIST_OK: return "ok";
        case RETROFM_PLAYLIST_IGNORED: return "unsupported file ignored";
        case RETROFM_PLAYLIST_BAD_ARGUMENT: return "bad argument";
        case RETROFM_PLAYLIST_PATH_TOO_LONG: return "path too long";
        case RETROFM_PLAYLIST_FULL: return "playlist full";
        case RETROFM_PLAYLIST_DUPLICATE: return "duplicate path";
        case RETROFM_PLAYLIST_FINALIZED: return "playlist already finalized";
        default: return "unknown error";
    }
}
