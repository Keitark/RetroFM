/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * Pinned mdxtools fm_opm_driver.c, with only the unused software-VGM logger
 * removed. Register order and values are intentionally unchanged.
 * RetroFM modification notice: modified on 2026-08-13.
 */
#include "fm_opm_driver.h"

static int note_to_opm(int note) {
    static const uint8_t table[12] = {
        0x0, 0x1, 0x2, 0x4, 0x5, 0x6, 0x8, 0x9, 0xA, 0xC, 0xD, 0xE
    };
    return (note / 12) * 16 + table[note % 12];
}

void fm_opm_driver_write(struct fm_opm_driver *driver, uint8_t reg,
                         uint8_t value) {
    driver->opm_cache[reg] = value;
    if (driver->write) driver->write(driver, reg, value);
}

static void reset_key_sync(struct fm_driver *driver, int channel) {
    struct fm_opm_driver *opm = (struct fm_opm_driver *)driver;
    (void)channel;
    fm_opm_driver_write(opm, 0x01, 0x02);
    fm_opm_driver_write(opm, 0x01, 0x00);
}
static void set_pms_ams(struct fm_driver *driver, int channel,
                        uint8_t value) {
    fm_opm_driver_write((struct fm_opm_driver *)driver,
                        (uint8_t)(0x38 + channel), value);
}
static void set_pitch(struct fm_driver *driver, int channel, int pitch) {
    struct fm_opm_driver *opm = (struct fm_opm_driver *)driver;
    fm_opm_driver_write(opm, (uint8_t)(0x28 + channel),
                        (uint8_t)note_to_opm(pitch >> 14));
    fm_opm_driver_write(opm, (uint8_t)(0x30 + channel),
                        (uint8_t)((pitch >> 6) & 0xFC));
}
static void set_tl(struct fm_driver *driver, int channel, uint8_t tl,
                   uint8_t *voice) {
    static const uint8_t masks[8] = {
        0x08, 0x08, 0x08, 0x08, 0x0C, 0x0E, 0x0E, 0x0F
    };
    struct fm_opm_driver *opm = (struct fm_opm_driver *)driver;
    int mask = 1;
    int i;
    for (i = 0; i < 4; ++i, mask <<= 1) {
        int level = voice[7 + i];
        if ((masks[voice[1] & 7] & mask) != 0) {
            level += tl;
            if (level > 0x7F) level = 0x7F;
        }
        fm_opm_driver_write(opm, (uint8_t)(0x60 + i * 8 + channel),
                            (uint8_t)level);
    }
}
static void note_on(struct fm_driver *driver, int channel, uint8_t mask,
                    uint8_t *voice) {
    (void)voice;
    fm_opm_driver_write((struct fm_opm_driver *)driver, 0x08,
                        (uint8_t)(((mask & 0x0F) << 3) | (channel & 7)));
}
static void note_off(struct fm_driver *driver, int channel) {
    fm_opm_driver_write((struct fm_opm_driver *)driver, 0x08,
                        (uint8_t)(channel & 7));
}
static void write_reg(struct fm_driver *driver, uint8_t reg, uint8_t value) {
    fm_opm_driver_write((struct fm_opm_driver *)driver, reg, value);
}
static void set_pan(struct fm_driver *driver, int channel, uint8_t pan,
                    uint8_t *voice) {
    fm_opm_driver_write((struct fm_opm_driver *)driver,
                        (uint8_t)(0x20 + channel),
                        (uint8_t)((pan << 6) | voice[1]));
}
static void set_noise(struct fm_driver *driver, int channel, int freq) {
    (void)channel;
    fm_opm_driver_write((struct fm_opm_driver *)driver, 0x0F,
                        (uint8_t)(freq & 0x1F));
}
static void load_voice(struct fm_driver *driver, int channel, uint8_t *voice,
                       int voice_num, int volume, int pan) {
    struct fm_opm_driver *opm = (struct fm_opm_driver *)driver;
    int i;
    (void)voice_num;
    for (i = 0; i < 4; ++i)
        fm_opm_driver_write(opm, (uint8_t)(0x40 + i * 8 + channel),
                            voice[3 + i]);
    set_tl(driver, channel, (uint8_t)volume, voice);
    for (i = 0; i < 4; ++i)
        fm_opm_driver_write(opm, (uint8_t)(0x80 + i * 8 + channel),
                            voice[11 + i]);
    for (i = 0; i < 4; ++i)
        fm_opm_driver_write(opm, (uint8_t)(0xA0 + i * 8 + channel),
                            voice[15 + i]);
    for (i = 0; i < 4; ++i)
        fm_opm_driver_write(opm, (uint8_t)(0xC0 + i * 8 + channel),
                            voice[19 + i]);
    for (i = 0; i < 4; ++i)
        fm_opm_driver_write(opm, (uint8_t)(0xE0 + i * 8 + channel),
                            voice[23 + i]);
    set_pan(driver, channel, (uint8_t)pan, voice);
}
static void load_lfo(struct fm_driver *driver, int channel, uint8_t wave,
                     uint8_t freq, uint8_t pmd, uint8_t amd) {
    struct fm_opm_driver *opm = (struct fm_opm_driver *)driver;
    (void)channel;
    fm_opm_driver_write(opm, 0x19, 0x00);
    fm_opm_driver_write(opm, 0x1B, (uint8_t)(wave & 3));
    fm_opm_driver_write(opm, 0x18, freq);
    if ((pmd & 0x7F) != 0) fm_opm_driver_write(opm, 0x19, pmd);
    if (amd != 0) fm_opm_driver_write(opm, 0x19, amd);
}

void fm_opm_driver_init(struct fm_opm_driver *driver) {
    int i;
    void (*write_callback)(struct fm_opm_driver *, uint8_t, uint8_t) =
        driver->write;
    fm_driver_init(&driver->fm_driver);
    driver->write = write_callback;
    driver->fm_driver.reset_key_sync = reset_key_sync;
    driver->fm_driver.set_pms_ams = set_pms_ams;
    driver->fm_driver.set_pitch = set_pitch;
    driver->fm_driver.set_tl = set_tl;
    driver->fm_driver.note_on = note_on;
    driver->fm_driver.note_off = note_off;
    driver->fm_driver.write_opm_reg = write_reg;
    driver->fm_driver.set_pan = set_pan;
    driver->fm_driver.set_noise_freq = set_noise;
    driver->fm_driver.load_voice = load_voice;
    driver->fm_driver.load_lfo = load_lfo;
    for (i = 0; i < 0x60; ++i) fm_opm_driver_write(driver, (uint8_t)i, 0x00);
    for (i = 0x60; i < 0x80; ++i) fm_opm_driver_write(driver, (uint8_t)i, 0x7F);
    for (i = 0x80; i < 0xE0; ++i) fm_opm_driver_write(driver, (uint8_t)i, 0x00);
    for (i = 0xE0; i <= 0xFF; ++i) fm_opm_driver_write(driver, (uint8_t)i, 0x0F);
    for (i = 0; i < 8; ++i) fm_opm_driver_write(driver, 0x08, (uint8_t)i);
}
