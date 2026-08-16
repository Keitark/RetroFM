/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RETROFM_NULL_MUTEX_H
#define RETROFM_NULL_MUTEX_H

#include <new>

/* The Zynq target runs MXDRV synchronously from one bare-metal foreground
 * context.  Vitis' freestanding libstdc++ does not provide std::mutex, and no
 * concurrent caller exists, so the dependency's two serialization locks are
 * intentionally no-ops on this target only. */
class retrofm_null_mutex {
public:
    void lock() {}
    void unlock() {}
};

#endif
