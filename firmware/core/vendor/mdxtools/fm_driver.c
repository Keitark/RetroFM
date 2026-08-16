/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * From mdxtools commit 606e3a7009aa1a9dfa6bee8bc875dbd5483714e9.
 * RetroFM modification notice: modified/adapted on 2026-08-13.
 */
#include "fm_driver.h"

void fm_driver_init(struct fm_driver *driver) {
    driver->data_ptr = 0;
    driver->reset_key_sync = 0;
    driver->set_pms_ams = 0;
    driver->set_pitch = 0;
    driver->set_tl = 0;
    driver->note_on = 0;
    driver->note_off = 0;
    driver->write_opm_reg = 0;
    driver->set_pan = 0;
    driver->set_noise_freq = 0;
    driver->load_voice = 0;
    driver->load_lfo = 0;
}

void fm_driver_reset_key_sync(struct fm_driver *d, int c) {
    if (d->reset_key_sync) d->reset_key_sync(d, c);
}
void fm_driver_set_pms_ams(struct fm_driver *d, int c, uint8_t value) {
    if (d->set_pms_ams) d->set_pms_ams(d, c, value);
}
void fm_driver_set_pitch(struct fm_driver *d, int c, int pitch) {
    if (d->set_pitch) d->set_pitch(d, c, pitch);
}
void fm_driver_set_tl(struct fm_driver *d, int c, uint8_t tl, uint8_t *v) {
    if (d->set_tl) d->set_tl(d, c, tl, v);
}
void fm_driver_note_on(struct fm_driver *d, int c, uint8_t mask, uint8_t *v) {
    if (d->note_on) d->note_on(d, c, mask, v);
}
void fm_driver_note_off(struct fm_driver *d, int c) {
    if (d->note_off) d->note_off(d, c);
}
void fm_driver_write_opm_reg(struct fm_driver *d, uint8_t r, uint8_t value) {
    if (d->write_opm_reg) d->write_opm_reg(d, r, value);
}
void fm_driver_set_pan(struct fm_driver *d, int c, uint8_t pan, uint8_t *v) {
    if (d->set_pan) d->set_pan(d, c, pan, v);
}
void fm_driver_set_noise_freq(struct fm_driver *d, int c, int freq) {
    if (d->set_noise_freq) d->set_noise_freq(d, c, freq);
}
void fm_driver_load_voice(struct fm_driver *d, int c, uint8_t *v,
                          int voice_num, int volume, int pan) {
    if (d->load_voice) d->load_voice(d, c, v, voice_num, volume, pan);
}
void fm_driver_load_lfo(struct fm_driver *d, int c, uint8_t wave,
                        uint8_t freq, uint8_t pmd, uint8_t amd) {
    if (d->load_lfo) d->load_lfo(d, c, wave, freq, pmd, amd);
}
