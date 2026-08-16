/* SPDX-License-Identifier: GPL-3.0-or-later */
/*
 * From mdxtools commit 606e3a7009aa1a9dfa6bee8bc875dbd5483714e9.
 * RetroFM modification notice: modified/adapted on 2026-08-13.
 */
#ifndef RETROFM_VENDOR_FM_OPM_DRIVER_H
#define RETROFM_VENDOR_FM_OPM_DRIVER_H

#include "fm_driver.h"

struct fm_opm_driver {
    struct fm_driver fm_driver;
    uint8_t opm_cache[256];
    void (*write)(struct fm_opm_driver *driver, uint8_t reg, uint8_t value);
};

void fm_opm_driver_init(struct fm_opm_driver *driver);
void fm_opm_driver_write(struct fm_opm_driver *driver, uint8_t reg,
                         uint8_t value);

#endif
