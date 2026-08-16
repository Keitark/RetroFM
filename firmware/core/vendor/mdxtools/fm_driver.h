/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * From mdxtools commit 606e3a7009aa1a9dfa6bee8bc875dbd5483714e9.
 * RetroFM modification notice: modified/adapted on 2026-08-13.
 */
#ifndef RETROFM_VENDOR_FM_DRIVER_H
#define RETROFM_VENDOR_FM_DRIVER_H

#include <stdint.h>

struct fm_driver {
    void *data_ptr;
    void (*reset_key_sync)(struct fm_driver *, int);
    void (*set_pms_ams)(struct fm_driver *, int, uint8_t);
    void (*set_pitch)(struct fm_driver *, int, int);
    void (*set_tl)(struct fm_driver *, int, uint8_t, uint8_t *);
    void (*note_on)(struct fm_driver *, int, uint8_t, uint8_t *);
    void (*note_off)(struct fm_driver *, int);
    void (*write_opm_reg)(struct fm_driver *, uint8_t, uint8_t);
    void (*set_pan)(struct fm_driver *, int, uint8_t, uint8_t *);
    void (*set_noise_freq)(struct fm_driver *, int, int);
    void (*load_voice)(struct fm_driver *, int, uint8_t *, int, int, int);
    void (*load_lfo)(struct fm_driver *, int, uint8_t, uint8_t, uint8_t,
                     uint8_t);
};

void fm_driver_init(struct fm_driver *driver);
void fm_driver_reset_key_sync(struct fm_driver *driver, int channel);
void fm_driver_set_pms_ams(struct fm_driver *driver, int channel,
                           uint8_t pms_ams);
void fm_driver_set_pitch(struct fm_driver *driver, int channel, int pitch);
void fm_driver_set_tl(struct fm_driver *driver, int channel, uint8_t tl,
                      uint8_t *voice);
void fm_driver_note_on(struct fm_driver *driver, int channel, uint8_t op_mask,
                       uint8_t *voice);
void fm_driver_note_off(struct fm_driver *driver, int channel);
void fm_driver_write_opm_reg(struct fm_driver *driver, uint8_t reg,
                             uint8_t value);
void fm_driver_set_pan(struct fm_driver *driver, int channel, uint8_t pan,
                       uint8_t *voice);
void fm_driver_set_noise_freq(struct fm_driver *driver, int channel, int freq);
void fm_driver_load_voice(struct fm_driver *driver, int channel,
                          uint8_t *voice, int voice_num, int opm_volume,
                          int pan);
void fm_driver_load_lfo(struct fm_driver *driver, int channel, uint8_t wave,
                        uint8_t freq, uint8_t pmd, uint8_t amd);

#endif
