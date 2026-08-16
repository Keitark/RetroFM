/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_ui.h"

#include <stdio.h>
#include <string.h>

static int write_ppm(const char *path, const retrofm_ui *ui) {
    FILE *file = fopen(path, "wb");
    size_t index;
    if (file == NULL) return 0;
    (void)fprintf(file, "P6\n%u %u\n255\n",
                  RETROFM_LCD_WIDTH, RETROFM_LCD_HEIGHT);
    for (index = 0U;
         index < (size_t)RETROFM_LCD_WIDTH * RETROFM_LCD_HEIGHT;
         ++index) {
        uint16_t pixel = ui->pixels[index];
        unsigned char rgb[3];
        rgb[0] = (unsigned char)(((pixel >> 11U) & 0x1FU) * 255U / 31U);
        rgb[1] = (unsigned char)(((pixel >> 5U) & 0x3FU) * 255U / 63U);
        rgb[2] = (unsigned char)((pixel & 0x1FU) * 255U / 31U);
        if (fwrite(rgb, 1U, sizeof(rgb), file) != sizeof(rgb)) {
            (void)fclose(file);
            return 0;
        }
    }
    return fclose(file) == 0;
}

int main(int argc, char **argv) {
    static retrofm_ui ui;
    retrofm_ui_model model;
    unsigned index;
    const char *path = argc > 1 ? argv[1] : "retrofm-ui-preview.ppm";
    memset(&ui, 0, sizeof(ui));
    memset(&model, 0, sizeof(model));
    model.title = "RETROFM HARDWARE FM PLAYER";
    model.artist = "OPM + OPN + PCM / FPGA SYNTHESIS";
    model.format = "MDX / MXDRV / JT51";
    model.state = "PLAYING";
    model.elapsed_seconds = 154U;
    model.volume_step = 13U;
    model.part_count = 16U;
    model.part_activity = UINT16_C(0xA5D3);
    model.animation_ms = 2500U;
    for (index = 0U; index < 32U; ++index) {
        unsigned triangle = index < 16U ? index : 31U - index;
        model.spectrum[index] = (uint8_t)(35U + triangle * 13U);
    }
    if (!retrofm_ui_prepare(&ui, &model) || !write_ppm(path, &ui)) {
        return 1;
    }
    return 0;
}
