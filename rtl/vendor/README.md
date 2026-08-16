# Yamaha vendor-core integration boundary

This directory contains only glue around the audited upstream cores. It does
not contain the event scheduler, the 48 kHz resampler/mixer, AXI registers, or
firmware.

Pinned sources and license:

- JT51 `985a573dcfc1ff135553a39f7eae21d18ba57cbe`, GPL-3.0-or-later source
  headers and GPLv3 repository license;
- JT12/JT03 `45f4854f9ab43368f5a514857299ab7dfae4e6ab`, GPL-3.0-or-later source
  headers and GPLv3 repository license;
- JT49 `7f6abfd08a2af9a92dbd5b32c71ea773248a77e2`, GPL-3.0-or-later;
- `jt12_dac2.v` from the same pinned JT12 revision.

The combined FPGA design must remain GPL-3.0-compatible. The exact compile
lists are in `../../vivado/vendor_sources.tcl`; no wildcard source discovery is
used.

## Clock and sample contracts

Both wrappers run in the exact 80 MHz Yamaha-core domain. Inputs named
`cmd_*` are synchronous to `clk_audio`. `retrofm_yamaha_command_bridge`
provides the required crossing from the 100 MHz scheduler domain: independent
eight-entry Gray-pointer asynchronous FIFOs feed the two wrapper handshakes.
The source must assert valid only for the addressed chip and retain valid plus
payload until that chip's `src_ready` is high. `src_accept` records the exact
accepted scheduler edge; `blocked_sticky` records an attempted transfer while
full. The independent queues preserve per-chip ordering, but not a global
ordering relationship between the two chips. A larger scheduler-level queue
already preserves deadlines; these FIFOs absorb only CDC and bus-service
latency.

Both FIFO resets must be asserted as a coordinated flush. Reset deassertion
must be synchronized separately to `clk_system` and `clk_audio`; neither side
may resume traffic while the other side still contains pre-reset pointers or
payload. The final reset controller, not this narrow wrapper, owns that policy.

The current `retrofm_event_scheduler.sv` emits unconditional one-cycle
`jt51_wr`/`jt03_wr` pulses and has no sink-ready inputs. Connecting those
pulses directly, or merely connecting them to these FIFOs, is not lossless if
a FIFO is full. Before system integration, the scheduler must retain a due
chip event until the matching `*_src_ready` handshake occurs and must not
accept/dispatch a replacement event in that cycle. A timing deadline remains
the requested dispatch time; queue/bus latency should be included in the late
event diagnostic policy.

`retrofm_jt51_wrapper` generates phase-aligned 4 MHz and 2 MHz enables with a
modulo-40 counter. The pinned JT51 currently performs synthesis work on
`cen_p1` (2 MHz); `cen` is still supplied at the documented 4 MHz interface
rate. The core consequently emits its native sample every 32 `cen_p1` pulses,
or 62.5 kHz. `audio_left/right` are JT51's full-resolution signed 16-bit
`xleft/xright`; `dac_left/right` retain the lower-resolution hardware-like
outputs for comparison.

`retrofm_jt03_wrapper` uses an integer-Hz fractional accumulator:

`accumulator += master_clock_hz; pulse and subtract 80,000,000 on carry`.

For `0 < master_clock_hz <= 80,000,000`, its mean enable rate is exact for an
integer-Hz request and individual pulses have at most one 12.5 ns fabric-cycle
of displacement. The expected VGM YM2203 clocks are well inside that range.
The selected clock must be valid before reset is asserted and remain stable
while a track is active. The accumulator intentionally continues generating
enables during reset so the core receives the six enabled reset cycles required
by `jt03.v`; the system reset controller must hold reset long enough at the
selected rate. JT03's native
FM sample period is 72 master-clock enables with its reset divide-by-six
setting. Because upstream `snd_sample` is a held phase level under sparse
enables, the wrapper emits a one-`clk_audio` rising-edge pulse instead.

JT03 exposes signed 16-bit FM, unsigned 10-bit PSG, and the upstream signed
16-bit combined result separately. The product mixer should use the separated
outputs so it can apply explicit centering, gain, and saturation.

## Register-write state machines

JT51 gates its memory-mapped register block with `cen_p1`. Its wrapper accepts
one `{register,data}` request in `BUS_IDLE`, holds the address phase until a
real 2 MHz enable, then holds the data phase until the next 2 MHz enable.
`cmd_ready` is high only in `BUS_IDLE`; `cmd_done` pulses after data acceptance.

JT03 is subtler. `jt12_mmr` sees the external bus on every 80 MHz edge, but
operator/channel state consumes its pending flags only on private
`jt12_div.clk_en` edges. The upstream top does not expose that enable. The
wrapper therefore:

1. holds the address through one mirrored internal-accept interval;
2. asserts data for at least one 80 MHz edge to create the pending flag;
3. keeps data asserted while waiting; and
4. deasserts write on the accepting edge, when `jt12_reg` consumes the old flag
   and `jt12_mmr` clears it.

That last deassertion is intentional. Keeping write asserted on the accepting
edge leaves a fresh pending flag and replays one-shot operations such as key-on
at the following accepting edge.

## JT03 phase-mirror assumptions

The wrapper duplicates the small `cen_reg` plus FM-prescaler state from the
pinned `jt12_top.v` and `jt12_div.v`. This is necessary because there is no
public write-accept port. It is safe only under these audited assumptions:

- the JT12 and JT49 commits remain exactly pinned and `FASTDIV` is not defined;
- every YM2203 register write goes through this wrapper;
- the FPGA configuration initializes both upstream and mirror counters to zero;
- `clk_audio`, reset, and `master_clock_hz` reach the core and mirror together,
  and `master_clock_hz` is stable across reset and playback;
- selections of divider registers `2D`, `2E`, and `2F` are not made through a
  second bus path; and
- reset is held for at least six generated master-clock enables, as required by
  `jt03.v`. Like upstream, reset does not restart the divider's FPGA-init-only
  counters; the mirror intentionally follows that behavior.

A future upstream fork that exports `clk_en` should replace this mirror with
that explicit acceptance signal.

The pinned `jt12_top.v` also references `op_result_hd` in its optional ADPCM
generate branch before the later declaration. Vivado 2024.2 reports the early
reference as an implicit wire, then correctly elaborates the JT03
`use_adpcm=0` configuration with no black boxes. The dependency is deliberately
left byte-for-byte upstream. Do not enable Verilog's `default_nettype none`
directive around the vendor source set; the wrappers restore the default to
`wire` before it is read. A future source upgrade must re-audit this behavior.

## Compile check

With the dependencies already fetched, run:

```powershell
vivado.bat -mode batch `
  -source samples\retrofm_player\vivado\compile_vendor_ooc.tcl
```

The script verifies detached dependency revisions, reads only the audited
source lists, synthesizes, places, and routes `retrofm_vendor_compile_top` out
of context for `xc7z010clg400-1`, and writes reports plus checkpoints under
`build/vendor_ooc`. It returns a pass marker only if the routed 100/80 MHz
design has non-negative setup and hold slack and the selected `check_timing`
categories are zero. It is not proof of final board/system timing closure. The
OOC boundary uses explicit synchronous I/O budgets and estimated BUFG sources;
the final Clocking Wizard and top-level constraints supersede them.

Vivado 2024.2 `report_cdc` identifies the four Gray-pointer synchronizers as
the expected `CDC-3`/`CDC-6` structures and reports 32 `CDC-15` data paths from
the asynchronous FIFO memories to ready-gated destination captures. Those
data buses are intentional bundled-data paths: the synchronized Gray write
pointer cannot make `dst_valid` true until at least two destination clocks
after the write, and the selected memory word cannot be overwritten until the
synchronized read pointer returns to the source. They are not independent bit
synchronizers.

The audited routed OOC result from Vivado 2024.2 is recorded under
`build/vendor_ooc`: 2,642 LUTs (15.01%), 2,248 registers (6.39%), eight
RAMB18s/four BRAM tiles (6.67%), and zero DSPs. The 100/80 MHz timing summary
closed with setup WNS +0.363 ns and hold WHS +0.011 ns, with zero routing
errors and zero issues in the checked unconstrained-clock/I/O categories.
These margins are only for the OOC boundary and must not be quoted as final
system timing closure.
