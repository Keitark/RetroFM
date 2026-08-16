/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_player.h"
#include "retrofm_playlist.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

#define CHECK(condition) do {                                                   \
    if (!(condition)) {                                                        \
        fprintf(stderr, "%s:%d: CHECK failed: %s\n",                        \
                __FILE__, __LINE__, #condition);                               \
        ++failures;                                                            \
    }                                                                          \
} while (0)

static void test_playlist(void) {
    retrofm_playlist playlist;
    const retrofm_playlist_entry *entry;
    char too_long[RETROFM_PLAYLIST_PATH_CAPACITY + 1U];

    retrofm_playlist_init(&playlist);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/Zeta.VGZ") ==
          RETROFM_PLAYLIST_OK);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/sub/demo.PDX") ==
          RETROFM_PLAYLIST_OK);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/sub/Demo.MdX") ==
          RETROFM_PLAYLIST_OK);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/alpha.vgm") ==
          RETROFM_PLAYLIST_OK);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/alpha.pcm") ==
          RETROFM_PLAYLIST_OK);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/readme.txt") ==
          RETROFM_PLAYLIST_IGNORED);
    CHECK(retrofm_playlist_add_path(&playlist, "/MUSIC/ALPHA.VGM") ==
          RETROFM_PLAYLIST_DUPLICATE);
    CHECK(retrofm_playlist_finalize(&playlist) == RETROFM_PLAYLIST_OK);
    CHECK(playlist.track_count == 3U);

    entry = retrofm_playlist_get(&playlist, 0U);
    CHECK(entry != NULL);
    CHECK(strcmp(entry->path, "/music/alpha.vgm") == 0);
    CHECK(entry->format == RETROFM_TRACK_VGM);
    CHECK(strcmp(entry->display_name, "alpha") == 0);
    CHECK(strcmp(entry->opna_pcm_path, "/music/alpha.pcm") == 0);

    entry = retrofm_playlist_get(&playlist, 1U);
    CHECK(entry != NULL);
    CHECK(entry->format == RETROFM_TRACK_MDX);
    CHECK(strcmp(entry->pdx_path, "/music/sub/demo.PDX") == 0);
    CHECK(strcmp(entry->display_name, "Demo") == 0);

    entry = retrofm_playlist_get(&playlist, 2U);
    CHECK(entry != NULL && entry->format == RETROFM_TRACK_VGZ);
    CHECK(retrofm_playlist_get(&playlist, 3U) == NULL);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/new.vgm") ==
          RETROFM_PLAYLIST_FINALIZED);

    memset(too_long, 'a', sizeof(too_long));
    too_long[sizeof(too_long) - 1U] = '\0';
    retrofm_playlist_init(&playlist);
    CHECK(retrofm_playlist_add_path(&playlist, too_long) ==
          RETROFM_PLAYLIST_PATH_TOO_LONG);
}

static void test_embedded_pdx_lookup(void) {
    static const uint8_t name_without_suffix[] = {'D', 'R', 'A', '0', '0'};
    static const uint8_t name_with_suffix[] = {
        'd', 'r', 'a', '0', '0', '.', 'p', 'D', 'x'
    };
    retrofm_playlist playlist;
    const char *path;

    retrofm_playlist_init(&playlist);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/game/DRA01.MDX") ==
          RETROFM_PLAYLIST_OK);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/game/DRA00.PDX") ==
          RETROFM_PLAYLIST_OK);
    CHECK(retrofm_playlist_add_path(&playlist, "/music/other/DRA00.PDX") ==
          RETROFM_PLAYLIST_OK);
    CHECK(retrofm_playlist_finalize(&playlist) == RETROFM_PLAYLIST_OK);
    path = retrofm_playlist_find_pdx(&playlist, "/music/game/DRA01.MDX",
                                     name_without_suffix,
                                     sizeof(name_without_suffix));
    CHECK(path != NULL && strcmp(path, "/music/game/DRA00.PDX") == 0);
    path = retrofm_playlist_find_pdx(&playlist, "/music/game/DRA01.MDX",
                                     name_with_suffix,
                                     sizeof(name_with_suffix));
    CHECK(path != NULL && strcmp(path, "/music/game/DRA00.PDX") == 0);
    CHECK(retrofm_playlist_find_pdx(&playlist, "/music/missing/track.MDX",
                                    name_without_suffix,
                                    sizeof(name_without_suffix)) == NULL);
}

static void test_player_state(void) {
    retrofm_player player;

    retrofm_player_init(&player, 3U);
    CHECK(player.state == RETROFM_PLAYER_STOPPED);
    CHECK(player.selected == 0U);
    CHECK(retrofm_player_volume_q15(&player) == 0x6000U);
    CHECK(retrofm_player_begin(&player) ==
          RETROFM_PLAYER_ACTION_LOAD_SELECTED);
    CHECK(player.state == RETROFM_PLAYER_LOADING);
    CHECK(retrofm_player_loaded(&player, false) ==
          RETROFM_PLAYER_ACTION_NONE);
    CHECK(player.state == RETROFM_PLAYER_PREFILLING);
    CHECK(retrofm_player_prefilled(&player) == RETROFM_PLAYER_ACTION_START);
    CHECK(player.state == RETROFM_PLAYER_PLAYING);

    CHECK(retrofm_player_press(&player, RETROFM_BUTTON_PLAY_PAUSE) ==
          RETROFM_PLAYER_ACTION_PAUSE);
    CHECK(player.state == RETROFM_PLAYER_PAUSED);
    CHECK(retrofm_player_press(&player, RETROFM_BUTTON_PLAY_PAUSE) ==
          RETROFM_PLAYER_ACTION_RESUME);
    CHECK(player.state == RETROFM_PLAYER_PLAYING);

    CHECK(retrofm_player_press(&player, RETROFM_BUTTON_PREVIOUS) ==
          RETROFM_PLAYER_ACTION_LOAD_SELECTED);
    CHECK(player.selected == 2U && player.state == RETROFM_PLAYER_LOADING);
    CHECK(retrofm_player_loaded(&player, true) == RETROFM_PLAYER_ACTION_NONE);
    CHECK(retrofm_player_prefilled(&player) == RETROFM_PLAYER_ACTION_START);
    CHECK(retrofm_player_natural_end(&player) ==
          RETROFM_PLAYER_ACTION_NONE);
    CHECK(player.selected == 2U);

    player.looping = false;
    CHECK(retrofm_player_natural_end(&player) ==
          RETROFM_PLAYER_ACTION_LOAD_SELECTED);
    CHECK(player.selected == 0U && player.state == RETROFM_PLAYER_LOADING);

    CHECK(retrofm_player_press(&player, RETROFM_BUTTON_VOLUME_UP) ==
          RETROFM_PLAYER_ACTION_SET_VOLUME);
    CHECK(retrofm_player_volume_q15(&player) == 0x6800U);
    CHECK(retrofm_player_fail(&player, RETROFM_PLAYER_ERROR_UNSUPPORTED) ==
          RETROFM_PLAYER_ACTION_STOP);
    CHECK(player.state == RETROFM_PLAYER_ERROR);
    CHECK(retrofm_player_press(&player, RETROFM_BUTTON_PLAY_PAUSE) ==
          RETROFM_PLAYER_ACTION_LOAD_SELECTED);
    CHECK(player.state == RETROFM_PLAYER_LOADING);
}

static void test_empty_player(void) {
    retrofm_player player;
    retrofm_player_init(&player, 0U);
    CHECK(player.state == RETROFM_PLAYER_EMPTY);
    CHECK(retrofm_player_begin(&player) == RETROFM_PLAYER_ACTION_NONE);
    CHECK(retrofm_player_press(&player, RETROFM_BUTTON_NEXT) ==
          RETROFM_PLAYER_ACTION_NONE);
}

int main(void) {
    test_playlist();
    test_embedded_pdx_lookup();
    test_player_state();
    test_empty_player();
    if (failures != 0) {
        fprintf(stderr, "%d test(s) failed\n", failures);
        return EXIT_FAILURE;
    }
    puts("retrofm playlist/player-state tests passed");
    return EXIT_SUCCESS;
}
