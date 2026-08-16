/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_player.h"

void retrofm_player_init(retrofm_player *player, size_t track_count) {
    if (player == NULL) return;
    player->track_count = track_count;
    player->selected = 0U;
    player->state = track_count == 0U ?
        RETROFM_PLAYER_EMPTY : RETROFM_PLAYER_STOPPED;
    player->error = RETROFM_PLAYER_ERROR_NONE;
    player->volume_step = RETROFM_PLAYER_DEFAULT_VOLUME;
    player->looping = false;
}

retrofm_player_action retrofm_player_begin(retrofm_player *player) {
    if (player == NULL || player->track_count == 0U) {
        return RETROFM_PLAYER_ACTION_NONE;
    }
    if (player->state != RETROFM_PLAYER_STOPPED &&
        player->state != RETROFM_PLAYER_ERROR) {
        return RETROFM_PLAYER_ACTION_NONE;
    }
    player->state = RETROFM_PLAYER_LOADING;
    player->error = RETROFM_PLAYER_ERROR_NONE;
    player->looping = false;
    return RETROFM_PLAYER_ACTION_LOAD_SELECTED;
}

retrofm_player_action retrofm_player_loaded(retrofm_player *player,
                                            bool looping) {
    if (player == NULL || player->state != RETROFM_PLAYER_LOADING) {
        return RETROFM_PLAYER_ACTION_NONE;
    }
    player->state = RETROFM_PLAYER_PREFILLING;
    player->looping = looping;
    return RETROFM_PLAYER_ACTION_NONE;
}

retrofm_player_action retrofm_player_prefilled(retrofm_player *player) {
    if (player == NULL || player->state != RETROFM_PLAYER_PREFILLING) {
        return RETROFM_PLAYER_ACTION_NONE;
    }
    player->state = RETROFM_PLAYER_PLAYING;
    return RETROFM_PLAYER_ACTION_START;
}

static retrofm_player_action select_relative(retrofm_player *player,
                                             bool next) {
    if (player->track_count == 0U) return RETROFM_PLAYER_ACTION_NONE;
    if (next) {
        player->selected = (player->selected + 1U) % player->track_count;
    } else if (player->selected == 0U) {
        player->selected = player->track_count - 1U;
    } else {
        --player->selected;
    }
    player->state = RETROFM_PLAYER_LOADING;
    player->error = RETROFM_PLAYER_ERROR_NONE;
    player->looping = false;
    return RETROFM_PLAYER_ACTION_LOAD_SELECTED;
}

retrofm_player_action retrofm_player_press(retrofm_player *player,
                                           retrofm_player_button button) {
    if (player == NULL) return RETROFM_PLAYER_ACTION_NONE;
    switch (button) {
        case RETROFM_BUTTON_PREVIOUS:
            return select_relative(player, false);
        case RETROFM_BUTTON_NEXT:
            return select_relative(player, true);
        case RETROFM_BUTTON_PLAY_PAUSE:
            if (player->state == RETROFM_PLAYER_PLAYING) {
                player->state = RETROFM_PLAYER_PAUSED;
                return RETROFM_PLAYER_ACTION_PAUSE;
            }
            if (player->state == RETROFM_PLAYER_PAUSED) {
                player->state = RETROFM_PLAYER_PLAYING;
                return RETROFM_PLAYER_ACTION_RESUME;
            }
            if (player->state == RETROFM_PLAYER_STOPPED ||
                player->state == RETROFM_PLAYER_ERROR) {
                return retrofm_player_begin(player);
            }
            return RETROFM_PLAYER_ACTION_NONE;
        case RETROFM_BUTTON_VOLUME_DOWN:
            if (player->volume_step == 0U) return RETROFM_PLAYER_ACTION_NONE;
            --player->volume_step;
            return RETROFM_PLAYER_ACTION_SET_VOLUME;
        case RETROFM_BUTTON_VOLUME_UP:
            if (player->volume_step >= RETROFM_PLAYER_VOLUME_STEPS) {
                return RETROFM_PLAYER_ACTION_NONE;
            }
            ++player->volume_step;
            return RETROFM_PLAYER_ACTION_SET_VOLUME;
        default:
            return RETROFM_PLAYER_ACTION_NONE;
    }
}

retrofm_player_action retrofm_player_natural_end(retrofm_player *player) {
    if (player == NULL || player->state != RETROFM_PLAYER_PLAYING ||
        player->looping || player->track_count == 0U) {
        return RETROFM_PLAYER_ACTION_NONE;
    }
    return select_relative(player, true);
}

retrofm_player_action retrofm_player_fail(retrofm_player *player,
                                          retrofm_player_error error) {
    if (player == NULL || error == RETROFM_PLAYER_ERROR_NONE) {
        return RETROFM_PLAYER_ACTION_NONE;
    }
    player->state = RETROFM_PLAYER_ERROR;
    player->error = error;
    player->looping = false;
    return RETROFM_PLAYER_ACTION_STOP;
}

uint16_t retrofm_player_volume_q15(const retrofm_player *player) {
    uint32_t step;
    if (player == NULL) return 0U;
    step = player->volume_step;
    if (step > RETROFM_PLAYER_VOLUME_STEPS) {
        step = RETROFM_PLAYER_VOLUME_STEPS;
    }
    return (uint16_t)((step * UINT32_C(0x8000)) /
                      RETROFM_PLAYER_VOLUME_STEPS);
}

const char *retrofm_player_state_string(retrofm_player_state state) {
    switch (state) {
        case RETROFM_PLAYER_EMPTY: return "NO MUSIC";
        case RETROFM_PLAYER_STOPPED: return "STOPPED";
        case RETROFM_PLAYER_LOADING: return "LOADING";
        case RETROFM_PLAYER_PREFILLING: return "BUFFERING";
        case RETROFM_PLAYER_PLAYING: return "PLAYING";
        case RETROFM_PLAYER_PAUSED: return "PAUSED";
        case RETROFM_PLAYER_ERROR: return "ERROR";
        default: return "UNKNOWN";
    }
}

const char *retrofm_player_error_string(retrofm_player_error error) {
    switch (error) {
        case RETROFM_PLAYER_ERROR_NONE: return "none";
        case RETROFM_PLAYER_ERROR_STORAGE: return "SD/FAT32 I/O error";
        case RETROFM_PLAYER_ERROR_FILE_TOO_LARGE: return "file exceeds buffer limit";
        case RETROFM_PLAYER_ERROR_MISSING_PDX: return "matching PDX is missing";
        case RETROFM_PLAYER_ERROR_UNSUPPORTED: return "unsupported format or chip";
        case RETROFM_PLAYER_ERROR_MALFORMED: return "malformed or truncated file";
        case RETROFM_PLAYER_ERROR_EVENT_FIFO: return "event FIFO service error";
        case RETROFM_PLAYER_ERROR_PCM_FIFO: return "PCM FIFO service error";
        case RETROFM_PLAYER_ERROR_HARDWARE: return "FPGA status fault";
        case RETROFM_PLAYER_ERROR_DISPLAY: return "LCD transport error";
        default: return "unknown error";
    }
}
