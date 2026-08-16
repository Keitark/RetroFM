#ifndef RETROFM_HW_H
#define RETROFM_HW_H

#include "retrofm_event.h"

#include <stdbool.h>
#include <stdint.h>

#if defined(_MSC_VER)
#include <intrin.h>
#endif

typedef struct retrofm_hw {
    uintptr_t base;
} retrofm_hw;

enum {
    RETROFM_CONTROL_RUN = 1U << 0,
    RETROFM_CONTROL_PCM_ENABLE = 1U << 1,
    /* FM-only pop-suppressed mute; PDX/PCM remains audible. */
    RETROFM_CONTROL_FM_MUTE = 1U << 2,
    RETROFM_CONTROL_CHIP_SHIFT = 4,
    RETROFM_CONTROL_CHIP_NONE = 0U << RETROFM_CONTROL_CHIP_SHIFT,
    RETROFM_CONTROL_CHIP_JT51 = 1U << RETROFM_CONTROL_CHIP_SHIFT,
    RETROFM_CONTROL_CHIP_JT03 = 2U << RETROFM_CONTROL_CHIP_SHIFT,
    RETROFM_CONTROL_CHIP_OPNA = 3U << RETROFM_CONTROL_CHIP_SHIFT,
    RETROFM_CONTROL_EVENT_IRQ_ENABLE = 1U << 8,
    RETROFM_CONTROL_FAULT_IRQ_ENABLE = 1U << 9
};

enum {
    RETROFM_EVENT_LEVEL_MASK = 0x1FFFU,
    RETROFM_EVENT_EMPTY = 1U << 16,
    RETROFM_EVENT_FULL = 1U << 17,
    RETROFM_EVENT_OVERFLOW = 1U << 18,
    RETROFM_EVENT_UNDERRUN = 1U << 19,
    RETROFM_EVENT_LATE = 1U << 20,
    RETROFM_EVENT_COMMAND_CDC_FAULT = 1U << 21,
    RETROFM_EVENT_HALTED = 1U << 22,
    RETROFM_EVENT_COMMAND_BACKPRESSURE_SEEN = 1U << 23,
    RETROFM_PCM_LEVEL_MASK = 0x1FFFU,
    RETROFM_PCM_EMPTY = 1U << 16,
    RETROFM_PCM_FULL = 1U << 17,
    RETROFM_PCM_OVERFLOW = 1U << 18,
    RETROFM_PCM_UNDERRUN = 1U << 19
};

enum {
    RETROFM_BUTTON_PREVIOUS_MASK = 1U << 0,
    RETROFM_BUTTON_PLAY_PAUSE_MASK = 1U << 1,
    RETROFM_BUTTON_NEXT_MASK = 1U << 2,
    RETROFM_BUTTON_VOLUME_DOWN_MASK = 1U << 3,
    RETROFM_BUTTON_VOLUME_UP_MASK = 1U << 4,
    RETROFM_BUTTON_MASK = 0x1FU,
    RETROFM_LCD_AUX_DC = 1U << 0,
    RETROFM_LCD_AUX_RESET = 1U << 1,
    RETROFM_LCD_AUX_CS_N = 1U << 2
};

enum {
    RETROFM_IRQ_EVENT_LOW_WATER = 1U << 0,
    RETROFM_IRQ_EVENT_OVERFLOW = 1U << 1,
    RETROFM_IRQ_EVENT_UNDERRUN = 1U << 2,
    RETROFM_IRQ_EVENT_LATE = 1U << 3,
    RETROFM_IRQ_PCM_OVERFLOW = 1U << 4,
    RETROFM_IRQ_PCM_UNDERRUN = 1U << 5,
    RETROFM_IRQ_COMMAND_CDC_FAULT = 1U << 6
};

enum {
    RETROFM_REG_ID = 0x00,
    RETROFM_REG_VERSION = 0x04,
    RETROFM_REG_CONTROL = 0x08,
    RETROFM_REG_COMMAND = 0x0C,
    RETROFM_REG_EVENT_LO = 0x10,
    RETROFM_REG_EVENT_HI = 0x14,
    RETROFM_REG_EVENT_STATUS = 0x18,
    RETROFM_REG_EVENT_WATERMARK = 0x1C,
    RETROFM_REG_PCM_FRAME = 0x20,
    RETROFM_REG_PCM_STATUS = 0x24,
    RETROFM_REG_VOLUME = 0x28,
    RETROFM_REG_YM2203_CLOCK = 0x2C,
    RETROFM_REG_KEY_MASKS = 0x30,
    RETROFM_REG_PEAKS = 0x34,
    RETROFM_REG_LATE_COUNT = 0x38,
    RETROFM_REG_PLAY_CYCLES_LO = 0x3C,
    RETROFM_REG_PLAY_CYCLES_HI = 0x40,
    RETROFM_REG_BUTTONS = 0x44,
    RETROFM_REG_LCD_AUX = 0x48,
    RETROFM_REG_IRQ_STATUS = 0x4C,
    RETROFM_REG_SPECTRUM_0 = 0x50,
    RETROFM_REG_SPECTRUM_1 = 0x54,
    RETROFM_REG_SPECTRUM_2 = 0x58,
    RETROFM_REG_SPECTRUM_3 = 0x5C,
    RETROFM_REG_SPECTRUM_4 = 0x60,
    RETROFM_REG_SPECTRUM_5 = 0x64,
    RETROFM_REG_SPECTRUM_6 = 0x68,
    RETROFM_REG_SPECTRUM_7 = 0x6C,
    RETROFM_REG_JT03_METER_LO = 0x70,
    RETROFM_REG_JT03_METER_HI = 0x74,
    RETROFM_REG_OPNA_SAMPLE_ADDR = 0x78,
    RETROFM_REG_OPNA_SAMPLE_DATA = 0x7C,
    RETROFM_REG_OPNA_METER_0 = 0x80,
    RETROFM_REG_OPNA_METER_1 = 0x84,
    RETROFM_REG_OPNA_METER_2 = 0x88,
    RETROFM_REG_OPNA_METER_FLAGS = 0x8C
};

enum {
    RETROFM_COMMAND_MUTE = 1U << 0,
    RETROFM_COMMAND_UNMUTE = 1U << 1,
    RETROFM_COMMAND_CORE_RESET = 1U << 2,
    RETROFM_COMMAND_EVENT_FLUSH = 1U << 3,
    RETROFM_COMMAND_PCM_FLUSH = 1U << 4,
    RETROFM_COMMAND_CLEAR_FAULTS = 1U << 5
};

static inline uint32_t retrofm_hw_read(const retrofm_hw *hw, uint32_t offset) {
    return *(volatile const uint32_t *)(hw->base + offset);
}

static inline void retrofm_hw_write(const retrofm_hw *hw,
                                    uint32_t offset,
                                    uint32_t value) {
    *(volatile uint32_t *)(hw->base + offset) = value;
}

/* The event low word is staging state and the high-word write is the atomic
 * commit. A real ARM data-memory barrier is required between them: volatile
 * alone constrains the compiler, not the Cortex-A9/AXI transaction order. */
static inline void retrofm_hw_io_barrier(void) {
#if defined(__arm__) || defined(__aarch64__)
    __asm__ volatile("dmb sy" ::: "memory");
#elif defined(_MSC_VER)
    _ReadWriteBarrier();
#elif defined(__GNUC__) || defined(__clang__)
    __asm__ volatile("" ::: "memory");
#else
#error Provide a compiler/MMIO write barrier for this target
#endif
}

static inline void retrofm_hw_io_sync(void) {
#if defined(__arm__) || defined(__aarch64__)
    __asm__ volatile("dsb sy" ::: "memory");
#elif defined(_MSC_VER)
    _ReadWriteBarrier();
#elif defined(__GNUC__) || defined(__clang__)
    __asm__ volatile("" ::: "memory");
#else
#error Provide a compiler/MMIO completion barrier for this target
#endif
}

static inline bool retrofm_hw_event_push(const retrofm_hw *hw,
                                         const retrofm_event *event) {
    uint64_t packed;
    uint32_t status = retrofm_hw_read(hw, RETROFM_REG_EVENT_STATUS);
    if (event == NULL ||
        (event->opcode != RETROFM_OP_YM2151 &&
         event->opcode != RETROFM_OP_YM2203 &&
         event->opcode != RETROFM_OP_YM2608 &&
         event->opcode != RETROFM_OP_DELAY &&
         event->opcode != RETROFM_OP_END &&
         event->opcode != RETROFM_OP_DIAGNOSTIC) ||
        (event->opcode != RETROFM_OP_YM2608 && event->flags != 0U) ||
        (event->opcode == RETROFM_OP_YM2608 &&
         (event->flags & ~RETROFM_EVENT_FLAG_OPNA_PORT1) != 0U) ||
        (status & RETROFM_EVENT_FULL) != 0U) {
        return false;
    }
    packed = retrofm_event_pack(event);
    retrofm_hw_write(hw, RETROFM_REG_EVENT_LO, (uint32_t)packed);
    retrofm_hw_io_barrier();
    retrofm_hw_write(hw, RETROFM_REG_EVENT_HI, (uint32_t)(packed >> 32U));
    retrofm_hw_io_barrier();
    return true;
}

static inline bool retrofm_hw_pcm_push(const retrofm_hw *hw,
                                       int16_t left,
                                       int16_t right) {
    uint32_t status = retrofm_hw_read(hw, RETROFM_REG_PCM_STATUS);
    if ((status & RETROFM_PCM_FULL) != 0U) {
        return false;
    }
    retrofm_hw_write(hw, RETROFM_REG_PCM_FRAME,
                     (uint16_t)left | ((uint32_t)(uint16_t)right << 16U));
    return true;
}

static inline uint32_t retrofm_hw_event_level(const retrofm_hw *hw) {
    return retrofm_hw_read(hw, RETROFM_REG_EVENT_STATUS) &
           RETROFM_EVENT_LEVEL_MASK;
}

static inline uint32_t retrofm_hw_pcm_level(const retrofm_hw *hw) {
    return retrofm_hw_read(hw, RETROFM_REG_PCM_STATUS) &
           RETROFM_PCM_LEVEL_MASK;
}

/* The audio-domain clock value is captured by the reset sequencer. Keep the
 * player muted/stopped, write the validated clock first, then request reset. */
static inline bool retrofm_hw_latch_ym2203_clock(const retrofm_hw *hw,
                                                uint32_t clock_hz) {
    if (hw == NULL || clock_hz == 0U || clock_hz > UINT32_C(10000000)) {
        return false;
    }
    retrofm_hw_write(hw, RETROFM_REG_YM2203_CLOCK, clock_hz);
    retrofm_hw_io_barrier();
    retrofm_hw_write(hw, RETROFM_REG_COMMAND, RETROFM_COMMAND_CORE_RESET);
    retrofm_hw_io_sync();
    return true;
}

/* Load a declared YM2608 Delta-T sample image before playback.  The PL
 * auto-increments the address by four after each DATA write; incomplete final
 * words are zero-padded.  The initial release uses a bounded 128 KiB store. */
static inline bool retrofm_hw_opna_sample_upload(const retrofm_hw *hw,
                                                 const uint8_t *bytes,
                                                 uint32_t size) {
    uint32_t offset;
    if (hw == NULL || size > UINT32_C(131072) || (size != 0U && bytes == NULL)) {
        return false;
    }
    retrofm_hw_write(hw, RETROFM_REG_OPNA_SAMPLE_ADDR, 0U);
    for (offset = 0U; offset < size; offset += 4U) {
        uint32_t word = bytes[offset];
        if (offset + 1U < size) word |= (uint32_t)bytes[offset + 1U] << 8U;
        if (offset + 2U < size) word |= (uint32_t)bytes[offset + 2U] << 16U;
        if (offset + 3U < size) word |= (uint32_t)bytes[offset + 3U] << 24U;
        retrofm_hw_write(hw, RETROFM_REG_OPNA_SAMPLE_DATA, word);
    }
    retrofm_hw_io_sync();
    return true;
}

static inline void retrofm_hw_spectrum(const retrofm_hw *hw,
                                       uint8_t bins[32]) {
    unsigned word_index;
    if (hw == NULL || bins == NULL) return;
    for (word_index = 0U; word_index < 8U; ++word_index) {
        uint32_t packed = retrofm_hw_read(
            hw, RETROFM_REG_SPECTRUM_0 + word_index * 4U);
        unsigned byte_index;
        for (byte_index = 0U; byte_index < 4U; ++byte_index) {
            bins[word_index * 4U + byte_index] =
                (uint8_t)(packed >> (byte_index * 8U));
        }
    }
}

/* Read the six playback-synchronous YM2203 meter captures.  Reading the high
 * word acknowledges the sticky note-trigger flags in hardware.  Channels are
 * ordered FM1, FM2, FM3, SSG1, SSG2, SSG3. */
static inline uint16_t retrofm_hw_jt03_meters(const retrofm_hw *hw,
                                              uint8_t volume[6]) {
    uint32_t low;
    uint32_t high;
    unsigned channel;
    if (hw == NULL || volume == NULL) return 0U;
    low = retrofm_hw_read(hw, RETROFM_REG_JT03_METER_LO);
    high = retrofm_hw_read(hw, RETROFM_REG_JT03_METER_HI);
    for (channel = 0U; channel < 4U; ++channel)
        volume[channel] = (uint8_t)(low >> (channel * 8U));
    volume[4] = (uint8_t)high;
    volume[5] = (uint8_t)(high >> 8U);
    return (uint16_t)((high >> 16U) & 0x3fU);
}

/* Read the eleven playback-synchronous YM2608 meters in channel order:
 * FM1..FM6, SSG1..SSG3, rhythm, ADPCM-B.  Reading FLAGS acknowledges note
 * starts, exactly as the six-part JT03 meter does. */
static inline uint16_t retrofm_hw_opna_meters(const retrofm_hw *hw,
                                              uint8_t volume[11]) {
    uint32_t first;
    uint32_t second;
    uint32_t third;
    uint32_t flags;
    unsigned channel;
    if (hw == NULL || volume == NULL) return 0U;
    first = retrofm_hw_read(hw, RETROFM_REG_OPNA_METER_0);
    second = retrofm_hw_read(hw, RETROFM_REG_OPNA_METER_1);
    third = retrofm_hw_read(hw, RETROFM_REG_OPNA_METER_2);
    flags = retrofm_hw_read(hw, RETROFM_REG_OPNA_METER_FLAGS);
    for (channel = 0U; channel < 4U; ++channel)
        volume[channel] = (uint8_t)(first >> (channel * 8U));
    for (channel = 0U; channel < 4U; ++channel)
        volume[channel + 4U] = (uint8_t)(second >> (channel * 8U));
    volume[8] = (uint8_t)third;
    volume[9] = (uint8_t)(third >> 8U);
    volume[10] = (uint8_t)(third >> 16U);
    return (uint16_t)(flags & UINT16_C(0x07ff));
}

/* Reading the low word asks the PL front end to snapshot the corresponding
 * high word. The AXI read completes before this function returns. */
static inline uint64_t retrofm_hw_playback_cycles(const retrofm_hw *hw) {
    uint32_t low = retrofm_hw_read(hw, RETROFM_REG_PLAY_CYCLES_LO);
    retrofm_hw_io_barrier();
    return (uint64_t)low |
           ((uint64_t)retrofm_hw_read(hw, RETROFM_REG_PLAY_CYCLES_HI) << 32U);
}

#endif
