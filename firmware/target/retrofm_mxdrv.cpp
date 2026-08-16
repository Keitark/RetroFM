/* SPDX-License-Identifier: GPL-3.0-or-later */

/*
 * Thin adapter around portable_mdx commit
 * 2429db394a2e1a1dad91b173f1affee5d8797aca.
 *
 * MXDRV remains the authoritative MDX sequencer.  The two interposed
 * functions below preserve the original IOCS/X68Sound implementation while
 * exposing every ordered OPM write. X68Sound's OPM timer/command engine must
 * remain enabled because it is MXDRV's sequencer clock; its generated FM
 * samples are discarded. PCM8 and ADPCM use X68Sound's native 62.5 kHz
 * engine and its original 48 kHz FIR output path.  That path also retains
 * X68Sound's deliberate OPM/ADPCM balance coefficient; only the software FM
 * contribution itself is removed.
 */

#include "retrofm_mxdrv.h"

#include <mdx_util.h>
#include <mxdrv.h>
#include <mxdrv_context.h>
#include <x68sound.h>
#include <x68sound_context.h>

#include <cstdlib>
#include <cstring>
#include <limits>

static retrofm_mxdrv *active_driver;

/* These are the original dependency functions, renamed only at compile time
 * so the pinned checkout remains clean. */
void retrofm_portable_iocs_opmset_internal(MxdrvContext *context,
                                            int address,
                                            int data);
extern "C" int retrofm_portable_x68sound_start_pcm_internal(
    X68SoundContext *context, int sample_rate, int opm_flag,
    int adpcm_flag, int pcm_buffer);

void _iocs_opmset(MxdrvContext *context, int address, int data) {
    uint8_t actual = static_cast<uint8_t>(data);
    retrofm_portable_iocs_opmset_internal(context, address, data);
    (void)MxdrvContext_GetOpmReg(context, static_cast<uint8_t>(address),
                                 &actual, nullptr);
    if (active_driver != nullptr && active_driver->event_callback != nullptr) {
        const uint64_t absolute_cycles =
            (active_driver->source_samples * UINT64_C(100000000)) /
            RETROFM_MXDRV_SOURCE_HZ;
        retrofm_event event{};
        const uint64_t delta = absolute_cycles -
                               active_driver->last_event_cycles;
        if (delta > UINT32_MAX) {
            active_driver->callback_failed = true;
            return;
        }
        event.delta_cycles = static_cast<uint32_t>(delta);
        event.opcode = RETROFM_OP_YM2151;
        event.reg = static_cast<uint8_t>(address);
        event.data = actual;
        if (!active_driver->event_callback(active_driver->event_user, &event)) {
            active_driver->callback_failed = true;
        }
        active_driver->last_event_cycles = absolute_cycles;
    }
}

int X68Sound_StartPcm(X68SoundContext *context, int sample_rate,
                      int opm_flag, int adpcm_flag, int pcm_buffer) {
    (void)opm_flag;
    /* Keep the original OPM timer/command engine active. Its stereo FM samples
     * are discarded by the adapter; JT51 is the only audible FM source. */
    return retrofm_portable_x68sound_start_pcm_internal(
        context, sample_rate, 1, adpcm_flag, pcm_buffer);
}

static bool get_source_frame(retrofm_mxdrv *driver,
                             int16_t *left,
                             int16_t *right) {
    auto *context = static_cast<MxdrvContext *>(driver->driver_context);
    int16_t stereo[2]{};
    if (driver->terminated) {
        *left = 0;
        *right = 0;
        return true;
    }
    active_driver = driver;
    const int result = MXDRV_GetPCM(context, stereo, 1);
    active_driver = nullptr;
    if (result != 0 || driver->callback_failed) return false;
    *left = stereo[0];
    *right = stereo[1];
    ++driver->source_samples;
    driver->terminated = MXDRV_GetTerminated(context) != 0;
    return true;
}

extern "C" bool retrofm_mxdrv_open(
    retrofm_mxdrv *driver, const uint8_t *mdx_image, size_t mdx_size,
    const uint8_t *pdx_image, size_t pdx_size,
    retrofm_mxdrv_event_callback event_callback, void *event_user) {
    uint32_t required_mdx = 0;
    uint32_t required_pdx = 0;
    uint8_t *mdx_buffer = nullptr;
    uint8_t *pdx_buffer = nullptr;
    MxdrvContext *context = nullptr;
    uint64_t pool_size;

    if (driver == nullptr || mdx_image == nullptr || mdx_size == 0U ||
        mdx_size > UINT32_MAX || pdx_size > UINT32_MAX ||
        (pdx_size != 0U && pdx_image == nullptr) ||
        event_callback == nullptr) return false;
    std::memset(driver, 0, sizeof(*driver));
    if (!MdxGetRequiredBufferSize(mdx_image, static_cast<uint32_t>(mdx_size),
                                  static_cast<uint32_t>(pdx_size),
                                  &required_mdx, &required_pdx)) return false;
    mdx_buffer = static_cast<uint8_t *>(std::malloc(required_mdx));
    if (required_pdx != 0U)
        pdx_buffer = static_cast<uint8_t *>(std::malloc(required_pdx));
    if (mdx_buffer == nullptr || (required_pdx != 0U && pdx_buffer == nullptr))
        goto fail;
    if (!MdxUtilCreateMdxPdxBuffer(
            mdx_image, static_cast<uint32_t>(mdx_size),
            pdx_image, static_cast<uint32_t>(pdx_size),
            mdx_buffer, required_mdx, pdx_buffer, required_pdx)) goto fail;

    context = static_cast<MxdrvContext *>(std::calloc(1, sizeof(*context)));
    if (context == nullptr) goto fail;
    pool_size = (static_cast<uint64_t>(required_mdx) + required_pdx) * 2U +
                512U * 1024U;
    if (pool_size < 2U * 1024U * 1024U) pool_size = 2U * 1024U * 1024U;
    if (pool_size > static_cast<uint64_t>(std::numeric_limits<int>::max()) ||
        !MxdrvContext_Initialize(context, static_cast<int>(pool_size))) goto fail;
    if (MXDRV_Start(context, RETROFM_MXDRV_SOURCE_HZ, 0, 0, 0,
                    static_cast<int>(required_mdx),
                    static_cast<int>(required_pdx), 0) != 0) {
        MxdrvContext_Terminate(context);
        goto fail;
    }
    MXDRV_PCM8Enable(context, 1);
    /* Both X68Sound render paths are build-locally stripped of only their
     * operator/output block. Timer, command, envelope, ADPCM, and PCM8 logic
     * remain authoritative, so unity here controls the sampled-audio path
     * without putting software FM into the PL FIFO. */
    MXDRV_TotalVolume(context, RETROFM_MXDRV_PCM_VOLUME);
    if (MXDRV_SetData2(context, mdx_buffer, required_mdx,
                       pdx_buffer, required_pdx) != 0) {
        MXDRV_End(context);
        MxdrvContext_Terminate(context);
        goto fail;
    }
    std::free(mdx_buffer);
    std::free(pdx_buffer);
    driver->driver_context = context;
    driver->event_callback = event_callback;
    driver->event_user = event_user;
    driver->initialized = true;
    active_driver = driver;
    MXDRV_Play2(context);
    active_driver = nullptr;
    if (driver->callback_failed) {
        retrofm_mxdrv_close(driver);
        return false;
    }
    return true;

fail:
    std::free(mdx_buffer);
    std::free(pdx_buffer);
    std::free(context);
    return false;
}

extern "C" bool retrofm_mxdrv_next_frame(retrofm_mxdrv *driver,
                                           int16_t *left,
                                           int16_t *right) {
    if (driver == nullptr || left == nullptr || right == nullptr ||
        !driver->initialized) return false;
    return get_source_frame(driver, left, right);
}

extern "C" void retrofm_mxdrv_close(retrofm_mxdrv *driver) {
    if (driver == nullptr) return;
    if (driver->initialized && driver->driver_context != nullptr) {
        auto *context = static_cast<MxdrvContext *>(driver->driver_context);
        MXDRV_Stop(context);
        MXDRV_End(context);
        MxdrvContext_Terminate(context);
        std::free(context);
    }
    if (active_driver == driver) active_driver = nullptr;
    std::memset(driver, 0, sizeof(*driver));
}

extern "C" bool retrofm_mxdrv_ended(const retrofm_mxdrv *driver) {
    return driver != nullptr && driver->terminated;
}

extern "C" bool retrofm_mxdrv_callback_failed(
    const retrofm_mxdrv *driver) {
    return driver == nullptr || driver->callback_failed;
}

extern "C" uint64_t retrofm_mxdrv_cycles(const retrofm_mxdrv *driver) {
    if (driver == nullptr) return 0U;
    return (driver->source_samples * UINT64_C(100000000)) /
           RETROFM_MXDRV_SOURCE_HZ;
}

extern "C" uint16_t retrofm_mxdrv_part_activity(
    const retrofm_mxdrv *driver, bool *pcm8_detected) {
    uint16_t activity = 0U;
    bool saw_pcm = false;
    if (pcm8_detected != nullptr) *pcm8_detected = false;
    if (driver == nullptr || !driver->initialized ||
        driver->driver_context == nullptr) return 0U;
    auto *context = static_cast<MxdrvContext *>(driver->driver_context);
    for (uint8_t channel = 0U; channel < 8U; ++channel) {
        bool current = false;
        bool logical = false;
        if (MxdrvContext_GetFmKeyOn(context, channel, &current, &logical) &&
            (current || logical)) {
            activity |= static_cast<uint16_t>(UINT16_C(1) << channel);
        }
        logical = false;
        if (MxdrvContext_GetPcmKeyOn(context, channel, &logical) && logical) {
            activity |= static_cast<uint16_t>(UINT16_C(1) << (channel + 8U));
            saw_pcm = true;
        }
    }
    if (pcm8_detected != nullptr) *pcm8_detected = saw_pcm;
    return activity;
}

static uint8_t mxdrv_meter_volume(uint8_t value) {
    if ((value & 0x80U) != 0U) {
        return static_cast<uint8_t>((0x7fU - (value & 0x7fU)) * 2U);
    }
    return static_cast<uint8_t>((value & 0x0fU) * 0x11U);
}

extern "C" bool retrofm_mxdrv_part_meters(
    const retrofm_mxdrv *driver, uint8_t volume[16],
    uint16_t *current_mask, uint16_t *trigger_mask,
    bool *pcm8_detected) {
    uint16_t current = 0U;
    uint16_t triggered = 0U;
    bool saw_pcm = false;
    if (volume == nullptr || current_mask == nullptr ||
        trigger_mask == nullptr) return false;
    std::memset(volume, 0, 16U);
    *current_mask = 0U;
    *trigger_mask = 0U;
    if (pcm8_detected != nullptr) *pcm8_detected = false;
    if (driver == nullptr || !driver->initialized ||
        driver->driver_context == nullptr) return false;

    auto *context = static_cast<MxdrvContext *>(driver->driver_context);
    const volatile auto *fm_channels = static_cast<volatile MXWORK_CH *>(
        MXDRV_GetWork(context, MXDRV_WORK_FM));
    const volatile auto *pcm_channels = static_cast<volatile MXWORK_CH *>(
        MXDRV_GetWork(context, MXDRV_WORK_PCM));
    if (fm_channels == nullptr || pcm_channels == nullptr) return false;

    for (uint8_t channel = 0U; channel < 8U; ++channel) {
        bool key_on = false;
        bool logical_key_on = false;
        volume[channel] = mxdrv_meter_volume(fm_channels[channel].S0022);
        if (!MxdrvContext_GetFmKeyOn(context, channel, &key_on,
                                     &logical_key_on)) return false;
        if (key_on) current |= static_cast<uint16_t>(UINT16_C(1) << channel);
        if (logical_key_on)
            triggered |= static_cast<uint16_t>(UINT16_C(1) << channel);
    }

    for (uint8_t channel = 0U; channel < 8U; ++channel) {
        const volatile MXWORK_CH *work = channel == 0U ? &fm_channels[8] :
                                                        &pcm_channels[channel - 1U];
        bool logical_key_on = false;
        const uint16_t mask = static_cast<uint16_t>(
            UINT16_C(1) << (channel + 8U));
        volume[channel + 8U] = mxdrv_meter_volume(work->S0022);
        if ((work->S0016 & (1U << 3U)) != 0U) current |= mask;
        if (!MxdrvContext_GetPcmKeyOn(context, channel, &logical_key_on))
            return false;
        if (logical_key_on) {
            triggered |= mask;
            saw_pcm = true;
        }
    }
    *current_mask = current;
    *trigger_mask = triggered;
    if (pcm8_detected != nullptr) *pcm8_detected = saw_pcm;
    return true;
}

