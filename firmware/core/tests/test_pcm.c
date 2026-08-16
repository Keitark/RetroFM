/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_pcm.h"

#include <stdio.h>

#define CHECK(condition) do { if (!(condition)) {                            \
    fprintf(stderr, "CHECK failed %s:%d: %s\n", __FILE__, __LINE__,         \
            #condition); return 1; } } while (0)

static int test_duration_and_pan(void) {
    static const uint8_t adpcm[] = {0x77, 0x77, 0xFF, 0xFF};
    retrofm_pcm_mixer mixer;
    size_t frames = 0U;
    bool heard_left = false;
    int16_t left;
    int16_t right;

    retrofm_pcm_init(&mixer);
    CHECK(retrofm_pcm_play(&mixer, 0U, adpcm, sizeof(adpcm),
                           4U, 15U, 1U) == RETROFM_PCM_OK);
    while (retrofm_pcm_active(&mixer) && frames < 100U) {
        CHECK(retrofm_pcm_next_frame(&mixer, &left, &right) == RETROFM_PCM_OK);
        if (left != 0) heard_left = true;
        CHECK(right == 0);
        ++frames;
    }
    CHECK(!retrofm_pcm_active(&mixer));
    CHECK(heard_left);
    /* Eight decoded samples at 15.625 kHz occupy about 24.6 output frames;
     * linear interpolation holds the final endpoint for one interval. */
    CHECK(frames >= 24U && frames <= 29U);
    return 0;
}

static int test_controls_and_saturation(void) {
    static const uint8_t adpcm[] = {0x77, 0x77, 0x77, 0x77};
    retrofm_pcm_mixer mixer;
    int16_t left = 0;
    int16_t right = 0;
    size_t channel;
    size_t frame;

    retrofm_pcm_init(&mixer);
    for (channel = 0U; channel < RETROFM_PCM_CHANNELS; ++channel) {
        CHECK(retrofm_pcm_play(&mixer, channel, adpcm, sizeof(adpcm),
                               4U, 0xA0U, 3U) == RETROFM_PCM_OK);
    }
    for (frame = 0U; frame < 12U; ++frame) {
        CHECK(retrofm_pcm_next_frame(&mixer, &left, &right) == RETROFM_PCM_OK);
    }
    CHECK(left == 32767 && right == 32767);
    CHECK(retrofm_pcm_set_pan(&mixer, 0U, 2U) == RETROFM_PCM_OK);
    CHECK(retrofm_pcm_set_volume(&mixer, 0U, 0x40U) == RETROFM_PCM_OK);
    CHECK(retrofm_pcm_set_frequency(&mixer, 0U, 0U) == RETROFM_PCM_OK);
    CHECK(retrofm_pcm_stop(&mixer, 0U) == RETROFM_PCM_OK);
    CHECK(retrofm_pcm_set_frequency(&mixer, 0U, 5U) ==
          RETROFM_PCM_BAD_FREQUENCY);
    CHECK(retrofm_pcm_stop(&mixer, RETROFM_PCM_CHANNELS) ==
          RETROFM_PCM_BAD_CHANNEL);
    return 0;
}

int main(void) {
    CHECK(test_duration_and_pan() == 0);
    CHECK(test_controls_and_saturation() == 0);
    puts("retrofm 48 kHz PCM mixer tests passed");
    return 0;
}
