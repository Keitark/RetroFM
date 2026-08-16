/* SPDX-License-Identifier: GPL-3.0-or-later */

#ifndef RETROFM_PLAYER_H
#define RETROFM_PLAYER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RETROFM_PLAYER_VOLUME_STEPS 16U
#define RETROFM_PLAYER_DEFAULT_VOLUME 12U

typedef enum retrofm_player_state {
    RETROFM_PLAYER_EMPTY = 0,
    RETROFM_PLAYER_STOPPED,
    RETROFM_PLAYER_LOADING,
    RETROFM_PLAYER_PREFILLING,
    RETROFM_PLAYER_PLAYING,
    RETROFM_PLAYER_PAUSED,
    RETROFM_PLAYER_ERROR
} retrofm_player_state;

typedef enum retrofm_player_button {
    RETROFM_BUTTON_PREVIOUS = 0,
    RETROFM_BUTTON_PLAY_PAUSE,
    RETROFM_BUTTON_NEXT,
    RETROFM_BUTTON_VOLUME_DOWN,
    RETROFM_BUTTON_VOLUME_UP
} retrofm_player_button;

typedef enum retrofm_player_action {
    RETROFM_PLAYER_ACTION_NONE = 0,
    RETROFM_PLAYER_ACTION_LOAD_SELECTED,
    RETROFM_PLAYER_ACTION_START,
    RETROFM_PLAYER_ACTION_PAUSE,
    RETROFM_PLAYER_ACTION_RESUME,
    RETROFM_PLAYER_ACTION_SET_VOLUME,
    RETROFM_PLAYER_ACTION_STOP
} retrofm_player_action;

typedef enum retrofm_player_error {
    RETROFM_PLAYER_ERROR_NONE = 0,
    RETROFM_PLAYER_ERROR_STORAGE,
    RETROFM_PLAYER_ERROR_FILE_TOO_LARGE,
    RETROFM_PLAYER_ERROR_MISSING_PDX,
    RETROFM_PLAYER_ERROR_UNSUPPORTED,
    RETROFM_PLAYER_ERROR_MALFORMED,
    RETROFM_PLAYER_ERROR_EVENT_FIFO,
    RETROFM_PLAYER_ERROR_PCM_FIFO,
    RETROFM_PLAYER_ERROR_HARDWARE,
    RETROFM_PLAYER_ERROR_DISPLAY
} retrofm_player_error;

typedef struct retrofm_player {
    size_t track_count;
    size_t selected;
    retrofm_player_state state;
    retrofm_player_error error;
    uint8_t volume_step;
    bool looping;
} retrofm_player;

void retrofm_player_init(retrofm_player *player, size_t track_count);
retrofm_player_action retrofm_player_begin(retrofm_player *player);
retrofm_player_action retrofm_player_loaded(retrofm_player *player,
                                            bool looping);
retrofm_player_action retrofm_player_prefilled(retrofm_player *player);
retrofm_player_action retrofm_player_press(retrofm_player *player,
                                           retrofm_player_button button);
retrofm_player_action retrofm_player_natural_end(retrofm_player *player);
retrofm_player_action retrofm_player_fail(retrofm_player *player,
                                          retrofm_player_error error);
uint16_t retrofm_player_volume_q15(const retrofm_player *player);
const char *retrofm_player_state_string(retrofm_player_state state);
const char *retrofm_player_error_string(retrofm_player_error error);

#ifdef __cplusplus
}
#endif

#endif
