/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "retrofm_mxdrv.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#define CHECK(condition) do { if (!(condition)) { \
    std::fprintf(stderr, "CHECK failed at %s:%d: %s\n", \
                 __FILE__, __LINE__, #condition); return 1; } } while (0)

struct trace_state {
    uint64_t writes;
    uint64_t hash = UINT64_C(14695981039346656037);
    uint64_t cycles;
    uint64_t key_on_writes;
    uint8_t key_on_channels;
    uint8_t pan_channels;
    uint64_t service_ready_cycles;
    uint64_t maximum_service_lag_cycles;
    uint64_t left_pan_writes;
    uint64_t right_pan_writes;
    uint64_t stereo_pan_writes;
    uint8_t pan_transitions[32]{};
    uint8_t pan_transition_count;
    uint8_t last_channel_zero_pan;
};

static bool trace_event(void *user, const retrofm_event *event) {
    auto *trace = static_cast<trace_state *>(user);
    const uint8_t bytes[6] = {
        static_cast<uint8_t>(event->delta_cycles),
        static_cast<uint8_t>(event->delta_cycles >> 8U),
        static_cast<uint8_t>(event->delta_cycles >> 16U),
        static_cast<uint8_t>(event->delta_cycles >> 24U),
        event->reg, event->data
    };
    for (uint8_t value : bytes) {
        trace->hash ^= value;
        trace->hash *= UINT64_C(1099511628211);
    }
    trace->cycles += event->delta_cycles;
    /* The current JT51 bridge accepts one complete address/data transaction
     * every 34 2 MHz enables.  Model that serialized service here so real
     * MDX files expose sustained register backlog instead of merely proving
     * that the callback emitted all writes. */
    constexpr uint64_t jt51_service_cycles = UINT64_C(1700);
    const uint64_t service_start = trace->service_ready_cycles > trace->cycles ?
        trace->service_ready_cycles : trace->cycles;
    const uint64_t service_lag = service_start - trace->cycles;
    if (service_lag > trace->maximum_service_lag_cycles)
        trace->maximum_service_lag_cycles = service_lag;
    trace->service_ready_cycles = service_start + jt51_service_cycles;
    if (event->reg == 0x08U && (event->data & 0x78U) != 0U) {
        ++trace->key_on_writes;
        trace->key_on_channels |=
            static_cast<uint8_t>(1U << (event->data & 0x07U));
    }
    if (event->reg >= 0x20U && event->reg <= 0x27U &&
        (event->data & 0xC0U) != 0U) {
        trace->pan_channels |=
            static_cast<uint8_t>(1U << (event->reg & 0x07U));
    }
    if (event->reg == 0x20U && (event->data & 0xC0U) != 0U) {
        const uint8_t pan = static_cast<uint8_t>(event->data & 0xC0U);
        if (pan == 0x40U) ++trace->left_pan_writes;
        if (pan == 0x80U) ++trace->right_pan_writes;
        if (pan == 0xC0U) ++trace->stereo_pan_writes;
        if (pan != trace->last_channel_zero_pan) {
            if (trace->pan_transition_count <
                sizeof(trace->pan_transitions)) {
                trace->pan_transitions[trace->pan_transition_count++] = pan;
            }
            trace->last_channel_zero_pan = pan;
        }
    }
    ++trace->writes;
    return event->opcode == RETROFM_OP_YM2151;
}

static bool read_file(const char *path, std::vector<uint8_t> *bytes) {
    std::FILE *file = std::fopen(path, "rb");
    long length;
    if (file == nullptr || std::fseek(file, 0, SEEK_END) != 0 ||
        (length = std::ftell(file)) <= 0 ||
        std::fseek(file, 0, SEEK_SET) != 0) return false;
    bytes->resize(static_cast<size_t>(length));
    const bool okay = std::fread(bytes->data(), 1, bytes->size(), file) ==
                      bytes->size();
    std::fclose(file);
    return okay;
}

static bool contains_pan_sequence(const trace_state& trace,
                                  uint8_t first, uint8_t second,
                                  uint8_t third) {
    for (uint8_t i = 0U; i + 2U < trace.pan_transition_count; ++i) {
        if (trace.pan_transitions[i] == first &&
            trace.pan_transitions[i + 1U] == second &&
            trace.pan_transitions[i + 2U] == third) return true;
    }
    return false;
}

int main(int argc, char **argv) {
    std::vector<uint8_t> mdx;
    std::vector<uint8_t> external_pdx;
    trace_state first{};
    trace_state second{};
    retrofm_mxdrv driver{};
    int16_t left;
    int16_t right;
    bool fm_only_pcm_nonzero = false;
    const char *path = argc >= 2 ? argv[1] :
        RETROFM_TESTDATA_DIR "/retrofm_ym2151_demo.mdx";
    const unsigned frame_limit = argc >= 2 ? 48000U * 180U : 48000U;
    CHECK(read_file(path, &mdx));
    if (argc >= 3) CHECK(read_file(argv[2], &external_pdx));
    CHECK(retrofm_mxdrv_open(&driver, mdx.data(), mdx.size(),
                             external_pdx.empty() ? nullptr :
                                 external_pdx.data(),
                             external_pdx.size(),
                             trace_event, &first));
    uint64_t pcm_square_sum = 0U;
    uint64_t pcm_frames = 0U;
    uint64_t pcm_clipped_samples = 0U;
    uint32_t pcm_peak = 0U;
    for (unsigned i = 0; i < frame_limit && !retrofm_mxdrv_ended(&driver); ++i) {
        CHECK(retrofm_mxdrv_next_frame(&driver, &left, &right));
        fm_only_pcm_nonzero = fm_only_pcm_nonzero || left != 0 || right != 0;
        if (argc >= 3) {
            const int32_t left_wide = left;
            const int32_t right_wide = right;
            const uint32_t left_abs = left_wide < 0 ?
                static_cast<uint32_t>(-left_wide) :
                static_cast<uint32_t>(left_wide);
            const uint32_t right_abs = right_wide < 0 ?
                static_cast<uint32_t>(-right_wide) :
                static_cast<uint32_t>(right_wide);
            if (left_abs > pcm_peak) pcm_peak = left_abs;
            if (right_abs > pcm_peak) pcm_peak = right_abs;
            if (left == 32767 || left == -32767 || left == -32768)
                ++pcm_clipped_samples;
            if (right == 32767 || right == -32767 || right == -32768)
                ++pcm_clipped_samples;
            pcm_square_sum += static_cast<uint64_t>(left_wide * left_wide) +
                              static_cast<uint64_t>(right_wide * right_wide);
            ++pcm_frames;
        }
    }
    CHECK(!retrofm_mxdrv_callback_failed(&driver));
    CHECK(first.writes != 0U);
    CHECK(first.key_on_writes != 0U);
    CHECK(first.key_on_channels != 0U);
    CHECK(first.pan_channels != 0U);
    if (argc < 3) CHECK(!fm_only_pcm_nonzero);
    retrofm_mxdrv_close(&driver);

    if (argc >= 2) {
        std::fprintf(stderr,
                     "mxdrv real trace writes=%llu hash=%016llX cycles=%llu "
                     "keyons=%llu channels=%02X pan=%02X "
                     "pcm_frames=%llu peak=%u mean_square=%llu clipped=%llu "
                     "max_jt51_lag_us=%llu\n",
                     static_cast<unsigned long long>(first.writes),
                     static_cast<unsigned long long>(first.hash),
                     static_cast<unsigned long long>(first.cycles),
                     static_cast<unsigned long long>(first.key_on_writes),
                     first.key_on_channels, first.pan_channels,
                     static_cast<unsigned long long>(pcm_frames), pcm_peak,
                     static_cast<unsigned long long>(
                         pcm_frames == 0U ? 0U :
                         pcm_square_sum / (pcm_frames * 2U)),
                     static_cast<unsigned long long>(pcm_clipped_samples),
                     static_cast<unsigned long long>(
                         first.maximum_service_lag_cycles / 100U));
        retrofm_mxdrv_close(&driver);
        return 0;
    }
    CHECK(retrofm_mxdrv_open(&driver, mdx.data(), mdx.size(), nullptr, 0,
                             trace_event, &second));
    for (unsigned i = 0; i < frame_limit && !retrofm_mxdrv_ended(&driver); ++i)
        CHECK(retrofm_mxdrv_next_frame(&driver, &left, &right));
    std::fprintf(stderr,
                 "mxdrv traces first=%llu/%016llX/%llu second=%llu/%016llX/%llu\n",
                 static_cast<unsigned long long>(first.writes),
                 static_cast<unsigned long long>(first.hash),
                 static_cast<unsigned long long>(first.cycles),
                 static_cast<unsigned long long>(second.writes),
                 static_cast<unsigned long long>(second.hash),
                 static_cast<unsigned long long>(second.cycles));
    CHECK(first.writes == second.writes);
    CHECK(first.hash == second.hash);
    CHECK(first.cycles == second.cycles);
    retrofm_mxdrv_close(&driver);

    std::vector<uint8_t> pdx_mdx;
    std::vector<uint8_t> pdx;
    trace_state pdx_trace{};
    bool pdx_pcm_nonzero = false;
    bool pcm8_meter_seen = false;
    bool pcm_meter_volume_seen = false;
    CHECK(read_file(RETROFM_TESTDATA_DIR "/retrofm_ym2151_pdx_demo.mdx",
                    &pdx_mdx));
    CHECK(read_file(RETROFM_TESTDATA_DIR "/retrofm_ym2151_pdx_demo.pdx",
                    &pdx));
    CHECK(retrofm_mxdrv_open(&driver, pdx_mdx.data(), pdx_mdx.size(),
                             pdx.data(), pdx.size(), trace_event, &pdx_trace));
    for (unsigned i = 0; i < 48000U && !retrofm_mxdrv_ended(&driver); ++i) {
        bool pcm8_active = false;
        uint8_t meter_volume[16]{};
        uint16_t current_mask = 0U;
        uint16_t trigger_mask = 0U;
        CHECK(retrofm_mxdrv_next_frame(&driver, &left, &right));
        pdx_pcm_nonzero = pdx_pcm_nonzero || left != 0 || right != 0;
        CHECK(retrofm_mxdrv_part_meters(&driver, meter_volume,
                                        &current_mask, &trigger_mask,
                                        &pcm8_active));
        pcm8_meter_seen = pcm8_meter_seen ||
            (pcm8_active && (trigger_mask & UINT16_C(0xff00)) != 0U);
        for (unsigned part = 8U; part < 16U; ++part) {
            if ((trigger_mask & (UINT16_C(1) << part)) != 0U &&
                meter_volume[part] != 0U) pcm_meter_volume_seen = true;
        }
    }
    CHECK(!retrofm_mxdrv_callback_failed(&driver));
    CHECK(pdx_trace.writes != 0U);
    CHECK(pdx_pcm_nonzero);
    CHECK(pcm8_meter_seen);
    CHECK(pcm_meter_volume_seen);
    retrofm_mxdrv_close(&driver);

    std::vector<uint8_t> lr_mdx;
    trace_state lr_trace{};
    bool lr_pcm_nonzero = false;
    CHECK(read_file(RETROFM_TESTDATA_DIR "/retrofm_ym2151_lr_test.mdx",
                    &lr_mdx));
    CHECK(retrofm_mxdrv_open(&driver, lr_mdx.data(), lr_mdx.size(),
                             nullptr, 0, trace_event, &lr_trace));
    for (unsigned i = 0; i < 48000U * 12U; ++i) {
        CHECK(retrofm_mxdrv_next_frame(&driver, &left, &right));
        lr_pcm_nonzero = lr_pcm_nonzero || left != 0 || right != 0;
    }
    CHECK(!retrofm_mxdrv_callback_failed(&driver));
    CHECK(!lr_pcm_nonzero);
    CHECK(lr_trace.left_pan_writes != 0U);
    CHECK(lr_trace.right_pan_writes != 0U);
    CHECK(lr_trace.stereo_pan_writes != 0U);
    CHECK(contains_pan_sequence(lr_trace, 0x40U, 0x80U, 0xC0U));
    retrofm_mxdrv_close(&driver);
    std::puts("RetroFM MXDRV adapter tests passed");
    return 0;
}

