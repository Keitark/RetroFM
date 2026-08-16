/* SPDX-License-Identifier: GPL-3.0-or-later */

/*
 * EBAZ4205 RetroFM standalone application.
 *
 * This is the only translation unit that includes Xilinx BSP or FatFs
 * headers. The portable parsers, sequencers, playlist, state machine, CP932
 * conversion and PCM mixer remain buildable on the host.
 */

#include "retrofm_build_config.h"

#include "retrofm_event.h"
#include "retrofm_hw.h"
#include "retrofm_mdx.h"
#include "retrofm_mxdrv.h"
#include "retrofm_player.h"
#include "retrofm_playlist.h"
#include "retrofm_sjis.h"
#include "retrofm_st7789.h"
#include "retrofm_ui.h"
#include "retrofm_vgm.h"
#include "retrofm_vgz.h"

#include "ff.h"
#include "sleep.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xspips.h"
#include "xstatus.h"
#include "xtime_l.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef RETROFM_HW_BASEADDR
#error RETROFM_HW_BASEADDR must come from the integrated XSA address map
#endif

#ifndef RETROFM_IRQ_ID
#error RETROFM_IRQ_ID must name the integrated RetroFM F2P interrupt
#endif

#ifndef RETROFM_SPI_DEVICE_ID
#define RETROFM_SPI_DEVICE_ID XPAR_XSPIPS_0_DEVICE_ID
#endif

#ifndef RETROFM_GIC_DEVICE_ID
#if defined(XPAR_SCUGIC_SINGLE_DEVICE_ID)
#define RETROFM_GIC_DEVICE_ID XPAR_SCUGIC_SINGLE_DEVICE_ID
#elif defined(XPAR_SCUGIC_0_DEVICE_ID)
#define RETROFM_GIC_DEVICE_ID XPAR_SCUGIC_0_DEVICE_ID
#else
#error No generated XScuGic device ID is available
#endif
#endif

#define RETROFM_FILE_CAPACITY (8U * 1024U * 1024U)
#define RETROFM_EVENT_QUEUE_CAPACITY 8192U
/* MXDRV advances FM commands and decoded PDX from the same 44.1 kHz tick.
 * Keep enough decoded PCM look-ahead to fill the PL event FIFO even for
 * register-sparse MDX passages; 131072 frames are about 2.73 seconds at
 * 48 kHz and consume 512 KiB of the 256 MiB DDR. */
#define RETROFM_MXDRV_PCM_CAPACITY 131072U
#define RETROFM_EVENT_WATERMARK 512U
#define RETROFM_EVENT_REFILL_LEVEL 1536U
#define RETROFM_EVENT_RUNTIME_BUDGET 64U
#define RETROFM_PCM_SERVICE_LEVEL 3072U
#define RETROFM_PCM_REFILL_LEVEL 4080U
#define RETROFM_SCAN_DEPTH 4U
#define RETROFM_UI_ROWS_PER_SERVICE 32U
#define RETROFM_UI_INTERVAL_MS 33U
#define RETROFM_UI_INTERVAL_PCM8_MS 50U
#define RETROFM_FM_TOGGLE_HOLD_MS 1000U

typedef enum source_kind {
    SOURCE_NONE = 0,
    SOURCE_MDX,
    SOURCE_VGM
} source_kind;

typedef enum file_read_result {
    FILE_READ_OK = 0,
    FILE_READ_IO_ERROR,
    FILE_READ_TOO_LARGE
} file_read_result;

typedef struct event_queue {
    retrofm_event events[RETROFM_EVENT_QUEUE_CAPACITY];
    size_t head;
    size_t tail;
    size_t count;
} event_queue;

typedef struct mxdrv_pcm_queue {
    uint32_t frames[RETROFM_MXDRV_PCM_CAPACITY];
    size_t head;
    size_t tail;
    size_t count;
} mxdrv_pcm_queue;

typedef struct lcd_transport {
    XSpiPs *spi;
    retrofm_hw *hw;
    uint32_t aux_shadow;
} lcd_transport;

typedef struct retrofm_application {
    FATFS filesystem;
    XSpiPs spi;
    XScuGic interrupt_controller;
    retrofm_hw hw;
    retrofm_playlist playlist;
    retrofm_player player;
    retrofm_ui ui;
    lcd_transport lcd;

    source_kind source;
    retrofm_mdx mdx;
    retrofm_mxdrv mxdrv;
    retrofm_vgm vgm;
    event_queue event_queue;
    mxdrv_pcm_queue mxdrv_pcm;

    char title[128];
    char artist[128];
    char detail[96];
    uint64_t scheduled_cycles;
    uint64_t pcm_frame_cycles;
    uint32_t pcm_frame_remainder;
    uint32_t opna_pcm_bytes;
    uint32_t control_shadow;
    uint32_t previous_buttons;
    uint32_t previous_hold_started_ms;
    uint16_t ui_next_row;
    uint16_t button_service_counter;
    uint32_t ui_last_prepare_ms;
    bool ui_flushing;
    bool ui_refresh_requested;
    bool pcm_required;
    bool pcm8_detected;
    bool previous_hold_active;
    bool previous_hold_consumed;
    bool fm_muted;
    bool source_finished;
    bool callback_failed;
    volatile bool irq_pending;
} retrofm_application;

static uint8_t primary_file[RETROFM_FILE_CAPACITY];
static uint8_t auxiliary_file[RETROFM_FILE_CAPACITY];
static retrofm_application application;

static uint32_t monotonic_milliseconds(void) {
    XTime ticks;
    uint64_t seconds;
    uint64_t remainder;
    XTime_GetTime(&ticks);
    seconds = (uint64_t)ticks / COUNTS_PER_SECOND;
    remainder = (uint64_t)ticks % COUNTS_PER_SECOND;
    return (uint32_t)(seconds * 1000U +
        (remainder * 1000U) / COUNTS_PER_SECOND);
}

static bool mxdrv_pcm_push(mxdrv_pcm_queue *queue,
                           int16_t left,
                           int16_t right) {
    if (queue == NULL || queue->count >= RETROFM_MXDRV_PCM_CAPACITY)
        return false;
    queue->frames[queue->tail] = (uint16_t)left |
        ((uint32_t)(uint16_t)right << 16U);
    queue->tail = (queue->tail + 1U) % RETROFM_MXDRV_PCM_CAPACITY;
    ++queue->count;
    return true;
}

static bool mxdrv_pcm_pop(mxdrv_pcm_queue *queue,
                          int16_t *left,
                          int16_t *right) {
    uint32_t frame;
    if (queue == NULL || left == NULL || right == NULL || queue->count == 0U)
        return false;
    frame = queue->frames[queue->head];
    queue->head = (queue->head + 1U) % RETROFM_MXDRV_PCM_CAPACITY;
    --queue->count;
    *left = (int16_t)(uint16_t)frame;
    *right = (int16_t)(uint16_t)(frame >> 16U);
    return true;
}

static bool event_queue_push(event_queue *queue, const retrofm_event *event) {
    if (queue == NULL || event == NULL ||
        queue->count >= RETROFM_EVENT_QUEUE_CAPACITY) return false;
    queue->events[queue->tail] = *event;
    queue->tail = (queue->tail + 1U) % RETROFM_EVENT_QUEUE_CAPACITY;
    ++queue->count;
    return true;
}

static const retrofm_event *event_queue_front(const event_queue *queue) {
    if (queue == NULL || queue->count == 0U) return NULL;
    return &queue->events[queue->head];
}

static void event_queue_pop(event_queue *queue) {
    if (queue == NULL || queue->count == 0U) return;
    queue->head = (queue->head + 1U) % RETROFM_EVENT_QUEUE_CAPACITY;
    --queue->count;
}

static bool sequencer_event(void *context, const retrofm_event *event) {
    retrofm_application *app = (retrofm_application *)context;
    if (!event_queue_push(&app->event_queue, event)) {
        app->callback_failed = true;
        return false;
    }
    app->scheduled_cycles += event->delta_cycles;
    return true;
}

static file_read_result read_file(const char *path, uint8_t *destination,
                                  size_t capacity, size_t *amount) {
    FIL file;
    FRESULT result;
    FSIZE_t file_size;
    size_t used = 0U;

    if (path == NULL || destination == NULL || amount == NULL) {
        return FILE_READ_IO_ERROR;
    }
    *amount = 0U;
    result = f_open(&file, path, FA_READ);
    if (result != FR_OK) return FILE_READ_IO_ERROR;
    file_size = f_size(&file);
    if (file_size > capacity) {
        (void)f_close(&file);
        return FILE_READ_TOO_LARGE;
    }
    while (used < (size_t)file_size) {
        UINT request = (UINT)((size_t)file_size - used);
        UINT received = 0U;
        if (request > 65536U) request = 65536U;
        result = f_read(&file, destination + used, request, &received);
        if (result != FR_OK || received != request) {
            (void)f_close(&file);
            return FILE_READ_IO_ERROR;
        }
        used += received;
    }
    result = f_close(&file);
    if (result != FR_OK) return FILE_READ_IO_ERROR;
    *amount = used;
    return FILE_READ_OK;
}

static bool join_path(char *destination, size_t capacity,
                      const char *directory, const char *name) {
    size_t directory_length = strlen(directory);
    size_t name_length = strlen(name);
    bool needs_slash = directory_length != 0U &&
                       directory[directory_length - 1U] != '/';
    size_t required = directory_length + (needs_slash ? 1U : 0U) +
                      name_length + 1U;
    if (required > capacity) return false;
    memcpy(destination, directory, directory_length);
    if (needs_slash) destination[directory_length++] = '/';
    memcpy(destination + directory_length, name, name_length + 1U);
    return true;
}

static bool scan_directory(retrofm_playlist *playlist,
                           const char *path,
                           unsigned depth) {
    DIR directory;
    FILINFO info;
    FRESULT result;

    if (depth > RETROFM_SCAN_DEPTH) {
        xil_printf("FatFs scan depth exceeded at %s\r\n", path);
        return false;
    }
    result = f_opendir(&directory, path);
    if (result != FR_OK) {
        xil_printf("FatFs opendir %s -> %d\r\n", path, (int)result);
        return false;
    }
    for (;;) {
        char child[RETROFM_PLAYLIST_PATH_CAPACITY];
        result = f_readdir(&directory, &info);
        if (result != FR_OK) {
            xil_printf("FatFs readdir %s -> %d\r\n", path, (int)result);
            (void)f_closedir(&directory);
            return false;
        }
        if (info.fname[0] == '\0') break;
        if (strcmp(info.fname, ".") == 0 || strcmp(info.fname, "..") == 0) {
            continue;
        }
        if (!join_path(child, sizeof(child), path, info.fname)) {
            xil_printf("FatFs path too long below %s\r\n", path);
            (void)f_closedir(&directory);
            return false;
        }
        if ((info.fattrib & AM_DIR) != 0U) {
            if (depth < RETROFM_SCAN_DEPTH &&
                !scan_directory(playlist, child, depth + 1U)) {
                (void)f_closedir(&directory);
                return false;
            }
        } else {
            retrofm_playlist_result added =
                retrofm_playlist_add_path(playlist, child);
            if (added != RETROFM_PLAYLIST_OK &&
                added != RETROFM_PLAYLIST_IGNORED &&
                added != RETROFM_PLAYLIST_DUPLICATE) {
                xil_printf("Playlist add %s -> %d\r\n", child, (int)added);
                (void)f_closedir(&directory);
                return false;
            }
        }
    }
    result = f_closedir(&directory);
    if (result != FR_OK) {
        xil_printf("FatFs closedir %s -> %d\r\n", path, (int)result);
        return false;
    }
    return true;
}

static void save_volume(const retrofm_player *player) {
    FIL file;
    UINT written = 0U;
    uint8_t byte;
    if (player == NULL) return;
    byte = player->volume_step;
    if (f_open(&file, "0:/retrofm-volume.cfg",
               FA_CREATE_ALWAYS | FA_WRITE) != FR_OK) return;
    (void)f_write(&file, &byte, 1U, &written);
    (void)f_sync(&file);
    (void)f_close(&file);
}

static void load_volume(retrofm_player *player) {
    FIL file;
    UINT received = 0U;
    uint8_t byte = RETROFM_PLAYER_DEFAULT_VOLUME;
    if (player == NULL ||
        f_open(&file, "0:/retrofm-volume.cfg", FA_READ) != FR_OK) return;
    if (f_read(&file, &byte, 1U, &received) == FR_OK && received == 1U &&
        byte <= RETROFM_PLAYER_VOLUME_STEPS) player->volume_step = byte;
    (void)f_close(&file);
}

static retrofm_player_error classify_vgm_error(retrofm_result result) {
    if (result == RETROFM_UNSUPPORTED_CHIP || result == RETROFM_MULTI_CHIP ||
        result == RETROFM_UNSUPPORTED_COMMAND ||
        result == RETROFM_BAD_VERSION || result == RETROFM_BAD_CLOCK) {
        return RETROFM_PLAYER_ERROR_UNSUPPORTED;
    }
    return RETROFM_PLAYER_ERROR_MALFORMED;
}

static retrofm_player_error validate_vgm_bytes(const uint8_t *bytes,
                                               size_t size,
                                               uint32_t *clock_hz,
                                               bool *has_loop,
                                               bool *is_ym2608) {
    retrofm_vgm validator;
    retrofm_event event;
    retrofm_result result = retrofm_vgm_open(&validator, bytes, size, false);
    if (result != RETROFM_OK) return classify_vgm_error(result);
    *clock_hz = validator.is_ym2608 ? validator.ym2608_clock_hz :
                                     validator.ym2203_clock_hz;
    *has_loop = validator.has_loop;
    *is_ym2608 = validator.is_ym2608;
    do {
        result = retrofm_vgm_next(&validator, &event);
    } while (result == RETROFM_OK);
    return result == RETROFM_END ?
        RETROFM_PLAYER_ERROR_NONE : classify_vgm_error(result);
}

static void reset_runtime(retrofm_application *app) {
    retrofm_mxdrv_close(&app->mxdrv);
    memset(&app->mdx, 0, sizeof(app->mdx));
    memset(&app->mxdrv, 0, sizeof(app->mxdrv));
    memset(&app->vgm, 0, sizeof(app->vgm));
    memset(&app->event_queue, 0, sizeof(app->event_queue));
    memset(&app->mxdrv_pcm, 0, sizeof(app->mxdrv_pcm));
    app->source = SOURCE_NONE;
    app->title[0] = '\0';
    app->artist[0] = '\0';
    app->detail[0] = '\0';
    app->scheduled_cycles = 0U;
    app->pcm_frame_cycles = 0U;
    app->pcm_frame_remainder = 0U;
    app->opna_pcm_bytes = 0U;
    app->pcm_required = false;
    app->pcm8_detected = false;
    app->source_finished = false;
    app->callback_failed = false;
}

static retrofm_player_error open_mdx(retrofm_application *app,
                                     const retrofm_playlist_entry *entry,
                                     size_t mdx_size) {
    size_t title_size = 0U;
    retrofm_mdx_result result = retrofm_mdx_open(&app->mdx,
                                                  primary_file,
                                                  mdx_size);
    if (result != RETROFM_MDX_OK) {
        (void)snprintf(app->detail, sizeof(app->detail), "%s",
                       retrofm_mdx_result_string(result));
        return RETROFM_PLAYER_ERROR_MALFORMED;
    }
    if (retrofm_sjis_to_utf8(app->mdx.title.data, app->mdx.title.size,
                             app->title, sizeof(app->title), &title_size) ==
        RETROFM_SJIS_BAD_ARGUMENT) {
        app->title[0] = '\0';
    }
    if (app->title[0] == '\0') {
        (void)snprintf(app->title, sizeof(app->title), "%s",
                       entry->display_name);
    }

    if (app->mdx.uses_pdx) {
        const char *pdx_path = retrofm_playlist_find_pdx(
            &app->playlist, entry->path, app->mdx.pdx_name.data,
            app->mdx.pdx_name.size);
        size_t pdx_size;
        if (pdx_path == NULL) {
            return RETROFM_PLAYER_ERROR_MISSING_PDX;
        }
        file_read_result read_result =
            read_file(pdx_path, auxiliary_file,
                      sizeof(auxiliary_file), &pdx_size);
        if (read_result != FILE_READ_OK) {
            return read_result == FILE_READ_TOO_LARGE ?
                RETROFM_PLAYER_ERROR_FILE_TOO_LARGE :
                RETROFM_PLAYER_ERROR_STORAGE;
        }
        if (!retrofm_mxdrv_open(&app->mxdrv, primary_file, mdx_size,
                                auxiliary_file, pdx_size,
                                sequencer_event, app)) {
            return RETROFM_PLAYER_ERROR_MALFORMED;
        }
    } else {
        if (!retrofm_mxdrv_open(&app->mxdrv, primary_file, mdx_size,
                                NULL, 0U, sequencer_event, app)) {
            return RETROFM_PLAYER_ERROR_MALFORMED;
        }
    }
    app->pcm_required = true;
    app->source = SOURCE_MDX;
    (void)snprintf(app->artist, sizeof(app->artist), "MXDRV / JT51");
    (void)snprintf(app->detail, sizeof(app->detail), "MDX / MXDRV / JT51");
    return RETROFM_PLAYER_ERROR_NONE;
}

static retrofm_player_error open_vgm(retrofm_application *app,
                                     const retrofm_playlist_entry *entry,
                                     const uint8_t *bytes,
                                     size_t size,
                                     const uint8_t *opna_pcm,
                                     size_t opna_pcm_size) {
    uint32_t clock_hz = 0U;
    bool has_loop = false;
    bool is_ym2608 = false;
    retrofm_player_error error =
        validate_vgm_bytes(bytes, size, &clock_hz, &has_loop, &is_ym2608);
    retrofm_result result;
    if (error != RETROFM_PLAYER_ERROR_NONE) return error;
    result = retrofm_vgm_open(&app->vgm, bytes, size, true);
    if (result != RETROFM_OK) return classify_vgm_error(result);
    if (app->vgm.is_ym2608 && opna_pcm_size != 0U) {
        if (opna_pcm_size > UINT32_C(131072) ||
            !retrofm_hw_opna_sample_upload(&app->hw, opna_pcm,
                                            (uint32_t)opna_pcm_size)) {
            return RETROFM_PLAYER_ERROR_FILE_TOO_LARGE;
        }
        app->opna_pcm_bytes = (uint32_t)opna_pcm_size;
    }
    result = retrofm_vgm_title(&app->vgm, app->title, sizeof(app->title));
    if (result != RETROFM_OK || app->title[0] == '\0') {
        (void)snprintf(app->title, sizeof(app->title), "%s",
                       entry->display_name);
    }
    result = retrofm_vgm_artist(&app->vgm, app->artist,
                                sizeof(app->artist));
    if (result != RETROFM_OK || app->artist[0] == '\0') {
        (void)snprintf(app->artist, sizeof(app->artist), "VGM / %s",
                       app->vgm.is_ym2608 ? "OPNA" : "JT03");
    }
    app->source = SOURCE_VGM;
    (void)snprintf(app->detail, sizeof(app->detail),
                   "%s / %s %lu HZ%s%s",
                   entry->format == RETROFM_TRACK_VGZ ? "VGZ" : "VGM",
                   is_ym2608 ? "YM2608" : "YM2203",
                   (unsigned long)clock_hz,
                   has_loop ? " LOOP" : "",
                   app->opna_pcm_bytes != 0U ? " PCM" : "");
    return RETROFM_PLAYER_ERROR_NONE;
}

static retrofm_player_error read_opna_pcm_sidecar(
    const retrofm_playlist_entry *entry, uint8_t *destination,
    size_t capacity, size_t *amount) {
    file_read_result read_result;
    if (entry == NULL || destination == NULL || amount == NULL) {
        return RETROFM_PLAYER_ERROR_STORAGE;
    }
    *amount = 0U;
    if (entry->opna_pcm_path[0] == '\0') return RETROFM_PLAYER_ERROR_NONE;
    read_result = read_file(entry->opna_pcm_path, destination, capacity,
                            amount);
    if (read_result == FILE_READ_TOO_LARGE || *amount > UINT32_C(131072)) {
        return RETROFM_PLAYER_ERROR_FILE_TOO_LARGE;
    }
    return read_result == FILE_READ_OK ? RETROFM_PLAYER_ERROR_NONE :
                                         RETROFM_PLAYER_ERROR_STORAGE;
}

static retrofm_player_error open_selected(retrofm_application *app) {
    const retrofm_playlist_entry *entry =
        retrofm_playlist_get(&app->playlist, app->player.selected);
    size_t size;
    file_read_result read_result;
    if (entry == NULL) return RETROFM_PLAYER_ERROR_STORAGE;
    reset_runtime(app);
    read_result = read_file(entry->path, primary_file,
                            sizeof(primary_file), &size);
    if (read_result != FILE_READ_OK) {
        return read_result == FILE_READ_TOO_LARGE ?
            RETROFM_PLAYER_ERROR_FILE_TOO_LARGE :
            RETROFM_PLAYER_ERROR_STORAGE;
    }
    if (entry->format == RETROFM_TRACK_MDX) {
        return open_mdx(app, entry, size);
    }
    if (entry->format == RETROFM_TRACK_VGM) {
        size_t pcm_size = 0U;
        retrofm_player_error error = read_opna_pcm_sidecar(
            entry, auxiliary_file, sizeof(auxiliary_file), &pcm_size);
        if (error != RETROFM_PLAYER_ERROR_NONE) return error;
        return open_vgm(app, entry, primary_file, size, auxiliary_file,
                        pcm_size);
    }
#if RETROFM_HAS_VGZ
    {
        size_t decompressed_size = 0U;
        retrofm_vgz_result result = retrofm_vgz_decompress(
            primary_file, size, auxiliary_file, sizeof(auxiliary_file),
            sizeof(auxiliary_file), &decompressed_size);
        if (result != RETROFM_VGZ_OK) {
            (void)snprintf(app->detail, sizeof(app->detail), "%s",
                           retrofm_vgz_result_string(result));
            return result == RETROFM_VGZ_LIMIT_EXCEEDED ||
                   result == RETROFM_VGZ_OUTPUT_TOO_SMALL ?
                RETROFM_PLAYER_ERROR_FILE_TOO_LARGE :
                RETROFM_PLAYER_ERROR_MALFORMED;
        }
        size_t pcm_size = 0U;
        retrofm_player_error error = read_opna_pcm_sidecar(
            entry, primary_file, sizeof(primary_file), &pcm_size);
        if (error != RETROFM_PLAYER_ERROR_NONE) return error;
        return open_vgm(app, entry, auxiliary_file, decompressed_size,
                        primary_file, pcm_size);
    }
#else
    return RETROFM_PLAYER_ERROR_UNSUPPORTED;
#endif
}

static bool produce_mdx_frame(retrofm_application *app) {
    int16_t left;
    int16_t right;
    if (app == NULL || app->source != SOURCE_MDX || app->source_finished ||
        app->mxdrv_pcm.count >= RETROFM_MXDRV_PCM_CAPACITY) return false;
    if (!retrofm_mxdrv_next_frame(&app->mxdrv, &left, &right) ||
        !mxdrv_pcm_push(&app->mxdrv_pcm, left, right)) return false;
    if (retrofm_mxdrv_ended(&app->mxdrv)) {
        retrofm_event event;
        uint64_t end_cycles = retrofm_mxdrv_cycles(&app->mxdrv);
        uint64_t delta = end_cycles - app->scheduled_cycles;
        if (delta > UINT32_MAX) return false;
        memset(&event, 0, sizeof(event));
        event.delta_cycles = (uint32_t)delta;
        event.opcode = RETROFM_OP_END;
        if (!sequencer_event(app, &event)) return false;
        app->source_finished = true;
    }
    return !app->callback_failed;
}

static bool produce_source(retrofm_application *app, size_t desired_events) {
    size_t iterations = 0U;
    while (app->event_queue.count < desired_events &&
           !app->source_finished && iterations++ < 4096U) {
        if (app->source == SOURCE_VGM) {
            retrofm_event event;
            retrofm_result result = retrofm_vgm_next(&app->vgm, &event);
            if (result == RETROFM_OK) {
                if (!sequencer_event(app, &event)) return false;
            } else if (result == RETROFM_END) {
                memset(&event, 0, sizeof(event));
                event.opcode = RETROFM_OP_END;
                if (!sequencer_event(app, &event)) return false;
                app->source_finished = true;
            } else {
                (void)snprintf(app->detail, sizeof(app->detail), "%s",
                               retrofm_result_string(result));
                return false;
            }
        } else if (app->source == SOURCE_MDX) {
            if (app->mxdrv_pcm.count >= RETROFM_MXDRV_PCM_CAPACITY) break;
            if (!produce_mdx_frame(app)) return false;
        } else {
            return false;
        }
        if (app->callback_failed) return false;
    }
    return true;
}

static bool service_event_fifo(retrofm_application *app, uint32_t target,
                               uint32_t write_budget) {
    uint32_t level = retrofm_hw_event_level(&app->hw);
    uint32_t written = 0U;
    while (level < target && written < write_budget) {
        const retrofm_event *event;
        if (app->event_queue.count == 0U && !app->source_finished &&
            !produce_source(app, RETROFM_EVENT_RUNTIME_BUDGET)) return false;
        event = event_queue_front(&app->event_queue);
        if (event == NULL) break;
        if (!retrofm_hw_event_push(&app->hw, event)) break;
        event_queue_pop(&app->event_queue);
        ++level;
        ++written;
    }
    /* An empty register FIFO is not an audio underrun: a Yamaha FM core must
     * continue sounding its current state between writes.  Clear the
     * producer-starvation history once look-ahead has recovered; genuinely
     * late events remain independently fatal through RETROFM_EVENT_LATE. */
    if (level != 0U) {
        retrofm_hw_write(&app->hw, RETROFM_REG_IRQ_STATUS,
                         RETROFM_IRQ_EVENT_UNDERRUN);
    }
    return level != 0U || app->source_finished || app->source == SOURCE_MDX;
}

static void advance_pcm_clock(retrofm_application *app) {
    uint64_t numerator = (uint64_t)app->pcm_frame_remainder +
                         RETROFM_PL_CLOCK_HZ;
    app->pcm_frame_cycles += numerator / RETROFM_MXDRV_OUTPUT_HZ;
    app->pcm_frame_remainder =
        (uint32_t)(numerator % RETROFM_MXDRV_OUTPUT_HZ);
}

static bool service_pcm_fifo(retrofm_application *app, uint32_t target) {
    uint32_t level;
    if (!app->pcm_required) return true;
    level = retrofm_hw_pcm_level(&app->hw);
    while (level < target) {
        int16_t left;
        int16_t right;
        if (app->source == SOURCE_MDX) {
            while (app->mxdrv_pcm.count == 0U && !app->source_finished) {
                if (!produce_mdx_frame(app)) return false;
            }
            if (!mxdrv_pcm_pop(&app->mxdrv_pcm, &left, &right)) {
                left = 0;
                right = 0;
            }
            if (!retrofm_hw_pcm_push(&app->hw, left, right)) break;
            advance_pcm_clock(app);
            ++level;
            continue;
        }
        return false;
    }
    if (level != 0U) {
        retrofm_hw_write(&app->hw, RETROFM_REG_IRQ_STATUS,
                         RETROFM_IRQ_PCM_UNDERRUN);
    }
    return level != 0U;
}

static void stop_hardware(retrofm_application *app) {
    retrofm_hw_write(&app->hw, RETROFM_REG_COMMAND, RETROFM_COMMAND_MUTE);
    usleep(5000U);
    app->control_shadow = 0U;
    retrofm_hw_write(&app->hw, RETROFM_REG_CONTROL, 0U);
    retrofm_hw_write(&app->hw, RETROFM_REG_COMMAND,
                     RETROFM_COMMAND_CORE_RESET |
                     RETROFM_COMMAND_EVENT_FLUSH |
                     RETROFM_COMMAND_PCM_FLUSH |
                     RETROFM_COMMAND_CLEAR_FAULTS);
    retrofm_hw_write(&app->hw, RETROFM_REG_IRQ_STATUS,
                     RETROFM_IRQ_COMMAND_CDC_FAULT);
    retrofm_hw_io_sync();
    usleep(1000U);
}

static retrofm_player_error start_selected(retrofm_application *app) {
    retrofm_player_error error;
    stop_hardware(app);
    error = open_selected(app);
    if (error != RETROFM_PLAYER_ERROR_NONE) return error;
    if (app->source == SOURCE_VGM) {
        uint32_t ym_clock_hz = app->vgm.is_ym2608 ?
            app->vgm.ym2608_clock_hz : app->vgm.ym2203_clock_hz;
        if (!retrofm_hw_latch_ym2203_clock(&app->hw, ym_clock_hz)) {
            return RETROFM_PLAYER_ERROR_HARDWARE;
        }
        /* The integrated reset sequencer stretches/synchronizes the pulse;
         * this bounded guard interval completes before FIFO prefill. */
        usleep(1000U);
    }
    (void)retrofm_player_loaded(&app->player,
        app->source == SOURCE_VGM && app->vgm.has_loop);
    retrofm_hw_write(&app->hw, RETROFM_REG_EVENT_WATERMARK,
                     RETROFM_EVENT_WATERMARK);
    retrofm_hw_write(&app->hw, RETROFM_REG_VOLUME,
                     retrofm_player_volume_q15(&app->player));
    if (!service_event_fifo(app, RETROFM_EVENT_REFILL_LEVEL, UINT32_MAX)) {
        return RETROFM_PLAYER_ERROR_EVENT_FIFO;
    }
    if (!service_pcm_fifo(app, RETROFM_PCM_REFILL_LEVEL)) {
        return RETROFM_PLAYER_ERROR_PCM_FIFO;
    }
    app->control_shadow = RETROFM_CONTROL_EVENT_IRQ_ENABLE |
                          RETROFM_CONTROL_FAULT_IRQ_ENABLE |
        (app->source == SOURCE_MDX ? RETROFM_CONTROL_CHIP_JT51 :
         app->vgm.is_ym2608 ? RETROFM_CONTROL_CHIP_OPNA :
                               RETROFM_CONTROL_CHIP_JT03);
    if (app->fm_muted) app->control_shadow |= RETROFM_CONTROL_FM_MUTE;
    retrofm_hw_write(&app->hw, RETROFM_REG_CONTROL, app->control_shadow);
    retrofm_hw_io_sync();
    app->control_shadow |= RETROFM_CONTROL_RUN;
    if (app->pcm_required) app->control_shadow |= RETROFM_CONTROL_PCM_ENABLE;
    retrofm_hw_write(&app->hw, RETROFM_REG_CONTROL, app->control_shadow);
    retrofm_hw_io_sync();
    retrofm_hw_write(&app->hw, RETROFM_REG_COMMAND,
                     RETROFM_COMMAND_UNMUTE);
    (void)retrofm_player_prefilled(&app->player);
    return RETROFM_PLAYER_ERROR_NONE;
}

static void fail_player(retrofm_application *app,
                        retrofm_player_error error) {
    stop_hardware(app);
    (void)retrofm_player_fail(&app->player, error);
    app->ui_refresh_requested = true;
}

static void handle_action(retrofm_application *app,
                          retrofm_player_action action) {
    if (action == RETROFM_PLAYER_ACTION_LOAD_SELECTED) {
        retrofm_player_error error = start_selected(app);
        if (error != RETROFM_PLAYER_ERROR_NONE) fail_player(app, error);
    } else if (action == RETROFM_PLAYER_ACTION_PAUSE) {
        retrofm_hw_write(&app->hw, RETROFM_REG_COMMAND,
                         RETROFM_COMMAND_MUTE);
        usleep(5000U);
        app->control_shadow &= ~(RETROFM_CONTROL_RUN |
                                 RETROFM_CONTROL_PCM_ENABLE);
        retrofm_hw_write(&app->hw, RETROFM_REG_CONTROL, app->control_shadow);
    } else if (action == RETROFM_PLAYER_ACTION_RESUME) {
        app->control_shadow |= RETROFM_CONTROL_RUN;
        if (app->pcm_required) {
            app->control_shadow |= RETROFM_CONTROL_PCM_ENABLE;
        }
        retrofm_hw_write(&app->hw, RETROFM_REG_CONTROL, app->control_shadow);
        retrofm_hw_io_sync();
        retrofm_hw_write(&app->hw, RETROFM_REG_COMMAND,
                         RETROFM_COMMAND_UNMUTE);
    } else if (action == RETROFM_PLAYER_ACTION_SET_VOLUME) {
        retrofm_hw_write(&app->hw, RETROFM_REG_VOLUME,
                         retrofm_player_volume_q15(&app->player));
        save_volume(&app->player);
    } else if (action == RETROFM_PLAYER_ACTION_STOP) {
        stop_hardware(app);
    }
}

static bool lcd_select(void *context, bool selected) {
    lcd_transport *transport = (lcd_transport *)context;
    if (selected) transport->aux_shadow &= ~RETROFM_LCD_AUX_CS_N;
    else transport->aux_shadow |= RETROFM_LCD_AUX_CS_N;
    retrofm_hw_write(transport->hw, RETROFM_REG_LCD_AUX,
                     transport->aux_shadow);
    return true;
}

static bool lcd_set_dc(void *context, bool data_mode) {
    lcd_transport *transport = (lcd_transport *)context;
    if (data_mode) transport->aux_shadow |= RETROFM_LCD_AUX_DC;
    else transport->aux_shadow &= ~RETROFM_LCD_AUX_DC;
    retrofm_hw_write(transport->hw, RETROFM_REG_LCD_AUX,
                     transport->aux_shadow);
    return true;
}

static bool lcd_set_reset(void *context, bool high) {
    lcd_transport *transport = (lcd_transport *)context;
    if (high) transport->aux_shadow |= RETROFM_LCD_AUX_RESET;
    else transport->aux_shadow &= ~RETROFM_LCD_AUX_RESET;
    retrofm_hw_write(transport->hw, RETROFM_REG_LCD_AUX,
                     transport->aux_shadow);
    return true;
}

static bool lcd_write(void *context, const uint8_t *bytes, size_t amount) {
    lcd_transport *transport = (lcd_transport *)context;
    uint8_t receive[128];
    if (bytes == NULL || amount > sizeof(receive)) return false;
    return XSpiPs_PolledTransfer(transport->spi, (uint8_t *)bytes,
                                 receive, (uint32_t)amount) == XST_SUCCESS;
}

static void lcd_delay(void *context, uint32_t milliseconds) {
    (void)context;
    usleep(milliseconds * 1000U);
}

static bool initialize_spi_and_lcd(retrofm_application *app) {
    XSpiPs_Config *config = XSpiPs_LookupConfig(RETROFM_SPI_DEVICE_ID);
    retrofm_lcd_io io;
    if (config == NULL ||
        XSpiPs_CfgInitialize(&app->spi, config, config->BaseAddress) !=
            XST_SUCCESS) return false;
    if (XSpiPs_SetOptions(&app->spi,
            XSPIPS_MASTER_OPTION | XSPIPS_FORCE_SSELECT_OPTION |
            XSPIPS_CLK_ACTIVE_LOW_OPTION | XSPIPS_CLK_PHASE_1_OPTION) !=
        XST_SUCCESS) return false;
    if (XSpiPs_SetClkPrescaler(&app->spi, XSPIPS_CLK_PRESCALE_8) !=
            XST_SUCCESS ||
        XSpiPs_SetSlaveSelect(&app->spi, 0U) != XST_SUCCESS) return false;

    app->lcd.spi = &app->spi;
    app->lcd.hw = &app->hw;
    app->lcd.aux_shadow = RETROFM_LCD_AUX_RESET | RETROFM_LCD_AUX_CS_N;
    retrofm_hw_write(&app->hw, RETROFM_REG_LCD_AUX,
                     app->lcd.aux_shadow);
    io.context = &app->lcd;
    io.select = lcd_select;
    io.set_dc = lcd_set_dc;
    io.set_reset = lcd_set_reset;
    io.write = lcd_write;
    io.delay_ms = lcd_delay;
    return retrofm_ui_init(&app->ui, &io);
}

static void retrofm_interrupt(void *context) {
    retrofm_application *app = (retrofm_application *)context;
    app->irq_pending = true;
    XScuGic_Disable(&app->interrupt_controller, RETROFM_IRQ_ID);
}

static bool initialize_interrupt(retrofm_application *app) {
    XScuGic_Config *config = XScuGic_LookupConfig(RETROFM_GIC_DEVICE_ID);
    if (config == NULL ||
        XScuGic_CfgInitialize(&app->interrupt_controller, config,
                              config->CpuBaseAddress) != XST_SUCCESS ||
        XScuGic_Connect(&app->interrupt_controller, RETROFM_IRQ_ID,
                        retrofm_interrupt, app) != XST_SUCCESS) return false;
    XScuGic_SetPriorityTriggerType(&app->interrupt_controller,
                                   RETROFM_IRQ_ID, 0xA0U, 0x01U);
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
        (Xil_ExceptionHandler)XScuGic_InterruptHandler,
        &app->interrupt_controller);
    XScuGic_Enable(&app->interrupt_controller, RETROFM_IRQ_ID);
    Xil_ExceptionEnable();
    return true;
}

static void service_buttons(retrofm_application *app) {
    uint32_t buttons = retrofm_hw_read(&app->hw, RETROFM_REG_BUTTONS) &
                       RETROFM_BUTTON_MASK;
    uint32_t pressed = buttons & ~app->previous_buttons;
    bool previous_down =
        (buttons & RETROFM_BUTTON_PREVIOUS_MASK) != 0U;
    uint32_t now_ms = monotonic_milliseconds();
    app->previous_buttons = buttons;
    if (previous_down) {
        if (!app->previous_hold_active) {
            app->previous_hold_active = true;
            app->previous_hold_consumed = false;
            app->previous_hold_started_ms = now_ms;
        } else if (!app->previous_hold_consumed &&
                   now_ms - app->previous_hold_started_ms >=
                       RETROFM_FM_TOGGLE_HOLD_MS) {
            app->fm_muted = !app->fm_muted;
            if (app->fm_muted)
                app->control_shadow |= RETROFM_CONTROL_FM_MUTE;
            else
                app->control_shadow &= ~RETROFM_CONTROL_FM_MUTE;
            retrofm_hw_write(&app->hw, RETROFM_REG_CONTROL,
                             app->control_shadow);
            app->ui_refresh_requested = true;
            xil_printf("FM-only mute %s\r\n",
                       app->fm_muted ? "enabled" : "disabled");
            app->previous_hold_consumed = true;
        }
    } else if (app->previous_hold_active) {
        if (!app->previous_hold_consumed) {
            handle_action(app, retrofm_player_press(
                &app->player, RETROFM_BUTTON_PREVIOUS));
        }
        app->previous_hold_active = false;
    }
    if ((pressed & RETROFM_BUTTON_PLAY_PAUSE_MASK) != 0U) {
        handle_action(app, retrofm_player_press(&app->player,
                                                RETROFM_BUTTON_PLAY_PAUSE));
    } else if ((pressed & RETROFM_BUTTON_NEXT_MASK) != 0U) {
        handle_action(app, retrofm_player_press(&app->player,
                                                RETROFM_BUTTON_NEXT));
    }
    if ((pressed & RETROFM_BUTTON_VOLUME_DOWN_MASK) != 0U) {
        handle_action(app, retrofm_player_press(&app->player,
                                                RETROFM_BUTTON_VOLUME_DOWN));
    }
    if ((pressed & RETROFM_BUTTON_VOLUME_UP_MASK) != 0U) {
        handle_action(app, retrofm_player_press(&app->player,
                                                RETROFM_BUTTON_VOLUME_UP));
    }
}

static bool check_faults(retrofm_application *app) {
    uint32_t event_status = retrofm_hw_read(&app->hw,
                                            RETROFM_REG_EVENT_STATUS);
    uint32_t pcm_status = retrofm_hw_read(&app->hw,
                                          RETROFM_REG_PCM_STATUS);
    if ((event_status & (RETROFM_EVENT_OVERFLOW |
                         RETROFM_EVENT_LATE |
                         RETROFM_EVENT_COMMAND_CDC_FAULT)) != 0U) {
        fail_player(app, RETROFM_PLAYER_ERROR_EVENT_FIFO);
        return false;
    }
    if (app->pcm_required &&
        (pcm_status & RETROFM_PCM_OVERFLOW) != 0U) {
        fail_player(app, RETROFM_PLAYER_ERROR_PCM_FIFO);
        return false;
    }
    return true;
}

static void prepare_ui(retrofm_application *app, uint32_t now_ms) {
    retrofm_ui_model model;
    uint32_t peaks = retrofm_hw_read(&app->hw, RETROFM_REG_PEAKS);
    uint16_t hardware_keys = (uint16_t)retrofm_hw_read(
        &app->hw, RETROFM_REG_KEY_MASKS);
    memset(&model, 0, sizeof(model));
    model.title = app->title[0] != '\0' ? app->title : "RETROFM";
    model.artist = app->artist[0] != '\0' ? app->artist : app->detail;
    model.format = app->detail;
    model.state = retrofm_player_state_string(app->player.state);
    model.error = app->player.error != RETROFM_PLAYER_ERROR_NONE ?
        retrofm_player_error_string(app->player.error) : NULL;
    model.elapsed_seconds =
        (uint32_t)(retrofm_hw_playback_cycles(&app->hw) /
                   RETROFM_PL_CLOCK_HZ);
    model.event_level = (uint16_t)retrofm_hw_event_level(&app->hw);
    model.pcm_level = (uint16_t)retrofm_hw_pcm_level(&app->hw);
    model.peak_left = (uint16_t)peaks;
    model.peak_right = (uint16_t)(peaks >> 16U);
    if (app->source == SOURCE_MDX) {
        bool pcm_active = false;
        model.part_meter_valid = retrofm_mxdrv_part_meters(
            &app->mxdrv, model.part_volume, &model.part_current,
            &model.part_trigger, &pcm_active);
        model.part_activity = model.part_current | model.part_trigger;
        if (pcm_active) app->pcm8_detected = true;
        model.part_count = app->pcm8_detected ? 16U : 8U;
    } else if (app->source == SOURCE_VGM) {
        model.part_meter_valid = true;
        if (app->vgm.is_ym2608) {
            model.part_current = 0U;
            model.part_trigger = retrofm_hw_opna_meters(
                &app->hw, model.part_volume);
            model.part_count = 11U;
        } else {
            model.part_current = (uint16_t)((hardware_keys >> 8U) & 0x3fU);
            model.part_trigger = retrofm_hw_jt03_meters(
                &app->hw, model.part_volume);
            model.part_count = 6U;
        }
        model.part_activity = model.part_current | model.part_trigger;
    } else {
        model.part_activity = hardware_keys;
        model.part_count = 8U;
    }
    retrofm_hw_spectrum(&app->hw, model.spectrum);
    model.volume_step = app->player.volume_step;
    model.animation_ms = now_ms;
    if (!retrofm_ui_prepare(&app->ui, &model)) {
        fail_player(app, RETROFM_PLAYER_ERROR_DISPLAY);
        return;
    }
    app->ui_last_prepare_ms = now_ms;
    app->ui_refresh_requested = false;
    app->ui_next_row = 0U;
    app->ui_flushing = true;
}

static void service_ui(retrofm_application *app) {
    if (!app->ui_flushing) return;
    {
        uint16_t rows = RETROFM_LCD_HEIGHT - app->ui_next_row;
        if (rows > RETROFM_UI_ROWS_PER_SERVICE) {
            rows = RETROFM_UI_ROWS_PER_SERVICE;
        }
        if (!retrofm_ui_flush_rows(&app->ui, app->ui_next_row, rows)) {
            fail_player(app, RETROFM_PLAYER_ERROR_DISPLAY);
            return;
        }
        app->ui_next_row = (uint16_t)(app->ui_next_row + rows);
        if (app->ui_next_row == RETROFM_LCD_HEIGHT) {
            app->ui_flushing = false;
        }
    }
}

static bool hardware_probe(retrofm_application *app) {
    uint32_t version;
    if (retrofm_hw_read(&app->hw, RETROFM_REG_ID) != UINT32_C(0x52464D31)) {
        return false;
    }
    version = retrofm_hw_read(&app->hw, RETROFM_REG_VERSION);
    return (version >> 16U) == 1U;
}

int main(void) {
    retrofm_application *app = &application;
    FRESULT mount_result;

    memset(app, 0, sizeof(*app));
    app->hw.base = (uintptr_t)RETROFM_HW_BASEADDR;
    xil_printf("RetroFM standalone starting\r\n");
    if (!hardware_probe(app)) {
        xil_printf("RetroFM FPGA ABI probe failed\r\n");
        return 1;
    }
    stop_hardware(app);
    if (!initialize_spi_and_lcd(app)) {
        xil_printf("ST7789/SPI initialization failed\r\n");
        return 1;
    }
    mount_result = f_mount(&app->filesystem, "0:/", 1U);
    if (mount_result != FR_OK) {
        xil_printf("FatFs mount 0:/ -> %d\r\n", (int)mount_result);
        retrofm_player_init(&app->player, 0U);
        app->player.state = RETROFM_PLAYER_ERROR;
        app->player.error = RETROFM_PLAYER_ERROR_STORAGE;
        prepare_ui(app, monotonic_milliseconds());
        while (app->ui_flushing) service_ui(app);
        return 1;
    }
    retrofm_playlist_init(&app->playlist);
    if (!scan_directory(&app->playlist, "0:/music", 0U)) {
        xil_printf("FatFs playlist scan failed\r\n");
        retrofm_player_init(&app->player, 0U);
        app->player.state = RETROFM_PLAYER_ERROR;
        app->player.error = RETROFM_PLAYER_ERROR_STORAGE;
        prepare_ui(app, monotonic_milliseconds());
        while (app->ui_flushing) service_ui(app);
        return 1;
    }
    {
        retrofm_playlist_result playlist_result =
            retrofm_playlist_finalize(&app->playlist);
        if (playlist_result != RETROFM_PLAYLIST_OK) {
            xil_printf("Playlist finalize -> %d\r\n", (int)playlist_result);
        retrofm_player_init(&app->player, 0U);
        app->player.state = RETROFM_PLAYER_ERROR;
        app->player.error = RETROFM_PLAYER_ERROR_STORAGE;
        prepare_ui(app, monotonic_milliseconds());
        while (app->ui_flushing) service_ui(app);
        return 1;
        }
    }
    xil_printf("FatFs playlist ready: %u track(s)\r\n",
               (unsigned)app->playlist.track_count);
    retrofm_player_init(&app->player, app->playlist.track_count);
    load_volume(&app->player);
    retrofm_hw_write(&app->hw, RETROFM_REG_VOLUME,
                     retrofm_player_volume_q15(&app->player));
    if (!initialize_interrupt(app)) {
        app->player.state = RETROFM_PLAYER_ERROR;
        app->player.error = RETROFM_PLAYER_ERROR_HARDWARE;
        prepare_ui(app, monotonic_milliseconds());
        while (app->ui_flushing) service_ui(app);
        return 1;
    }
    prepare_ui(app, monotonic_milliseconds());
    if (app->playlist.track_count != 0U) {
        handle_action(app, retrofm_player_begin(&app->player));
    }

    for (;;) {
        uint32_t event_status;
        if (app->player.state == RETROFM_PLAYER_PLAYING) {
            event_status = retrofm_hw_read(&app->hw,
                                            RETROFM_REG_EVENT_STATUS);
            if (app->irq_pending ||
                (event_status & RETROFM_EVENT_LEVEL_MASK) <=
                    RETROFM_EVENT_WATERMARK) {
                app->irq_pending = false;
                if (!service_pcm_fifo(app, RETROFM_PCM_REFILL_LEVEL)) {
                    fail_player(app, RETROFM_PLAYER_ERROR_PCM_FIFO);
                } else if (!service_event_fifo(
                               app, RETROFM_EVENT_REFILL_LEVEL,
                               RETROFM_EVENT_RUNTIME_BUDGET)) {
                    fail_player(app, RETROFM_PLAYER_ERROR_EVENT_FIFO);
                } else if (!service_pcm_fifo(app,
                                             RETROFM_PCM_REFILL_LEVEL)) {
                    fail_player(app, RETROFM_PLAYER_ERROR_PCM_FIFO);
                }
                XScuGic_Enable(&app->interrupt_controller, RETROFM_IRQ_ID);
            } else if (app->pcm_required &&
                       retrofm_hw_pcm_level(&app->hw) <
                           RETROFM_PCM_SERVICE_LEVEL &&
                       !service_pcm_fifo(app, RETROFM_PCM_REFILL_LEVEL)) {
                fail_player(app, RETROFM_PLAYER_ERROR_PCM_FIFO);
            }
            if (app->player.state == RETROFM_PLAYER_PLAYING &&
                !check_faults(app)) continue;
            event_status = retrofm_hw_read(&app->hw,
                                            RETROFM_REG_EVENT_STATUS);
            if (app->source_finished && app->event_queue.count == 0U &&
                (event_status & RETROFM_EVENT_HALTED) != 0U) {
                handle_action(app, retrofm_player_natural_end(&app->player));
            }
        }

        if (++app->button_service_counter >= 10U) {
            app->button_service_counter = 0U;
            service_buttons(app);
        }
        if (!app->ui_flushing) {
            uint32_t now_ms = monotonic_milliseconds();
            uint32_t interval_ms = app->pcm8_detected ?
                RETROFM_UI_INTERVAL_PCM8_MS : RETROFM_UI_INTERVAL_MS;
            if (app->ui_refresh_requested ||
                now_ms - app->ui_last_prepare_ms >= interval_ms) {
                prepare_ui(app, now_ms);
            }
        }
        service_ui(app);
        usleep(1000U);
    }
}
