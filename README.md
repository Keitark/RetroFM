# RetroFM for EBAZ4205

[![GPLv3 source](https://img.shields.io/badge/source-GPLv3-blue)](LICENSE)
[![EBAZ4205 / Zynq--7000](https://img.shields.io/badge/target-EBAZ4205%20%2F%20Zynq--7000-4c9a2e)](docs/hardware.md)
[![OPM hardware](https://img.shields.io/badge/OPM-YM2151%20%2F%20JT51-6f42c1)](docs/architecture.md)
[![OPN hardware](https://img.shields.io/badge/OPN-YM2203%20%2F%20JT03-6f42c1)](docs/architecture.md)
[![OPNA experimental](https://img.shields.io/badge/OPNA-YM2608%20experimental-d98b2b)](docs/register-map.md)
[![Board prototype](https://img.shields.io/badge/board-prototype%20%7C%20bench%20pending-bb3333)](STATUS.md)

English | [日本語](README.ja.md)

RetroFM is a source-first FM player for the EBAZ4205 Zynq-7000 board. The ARM
processing system handles storage, file parsing, sequencing, metadata, and the
ST7789 display. The FPGA fabric schedules timestamped Yamaha register writes,
mixes hardware FM and PCM, and produces stereo 1-bit delta-sigma audio.

> Current status: the candidate source, host tests, RTL/build checks, and a
> packaged candidate have evidence in the workspace. Physical board playback,
> audio wiring, cold SD boot, and long-run acceptance are still open.

This public snapshot is source-only. It does not ship a bitstream, BOOT.BIN,
ELF, local build products, or private music. The small files under
testdata/generated are rights-cleared deterministic test fixtures, not a music
release.

## What is implemented

- MDX playback with optional same-basename PDX PCM.
- VGM and VGZ playback for the OPN/YM2203 path.
- An experimental, deliberately narrow OPNA/YM2608 VGM path.
- FAT32 /music scanning, SD boot packaging, metadata, volume persistence,
  auto-advance, looping, error screens, and an ST7789 UI.
- Five active-low PL buttons and stereo 1-bit delta-sigma outputs on H4.
- Host-testable parsers and player state separated from synthesizable RTL and
  the Xilinx standalone target.

## Architecture

~~~mermaid
flowchart LR
    SD["FAT32 /music"] --> PS["ARM PS<br/>FatFs, parsers, sequencers, UI"]
    PS -->|"timestamped OPM/OPN/OPNA writes"| FIFO["AXI event FIFO<br/>100 MHz deadlines"]
    PS -->|"PDX / PCM frames"| PFIFO["PCM FIFO<br/>48 kHz"]
    FIFO --> CORES["JT51 YM2151<br/>JT03 YM2203<br/>JT2608 OPNA"]
    CORES --> MIX["FPGA mixer<br/>volume + mute ramp"]
    PFIFO --> MIX
    MIX --> SDM["Stereo 1-bit delta-sigma<br/>100 MHz PL plane"]
    SDM --> H4["H4-4/P18 left<br/>H4-6/M19 right"]
~~~

The event scheduler, mixer, AXI front end, and delta-sigma modulators run from
the 100 MHz PS FCLK. The JT51 path uses the exact 4 MHz YM2151 enable in the
audited 80 MHz Yamaha-core domain. PCM is mixed at 48 kHz using the latest
native core sample; this is a zero-order/latest-sample conversion rather than
a band-limited resampler. See [architecture.md](docs/architecture.md).

## Supported inputs and hardware cores

| Input | Hardware path | Scope and current status |
| --- | --- | --- |
| .mdx with optional .pdx | MXDRV/portable_mdx sequencing → timestamped writes → JT51 YM2151-compatible FPGA core; PDX remains the sampled PCM path | Implemented in the candidate source; board acceptance pending |
| One-chip .vgm / .vgz declaring YM2203 | ARM VGM iterator → JT03-compatible core from JT12/JT49 | Implemented; unsupported chips, clocks, and commands fail closed; board acceptance pending |
| One-chip .vgm / .vgz declaring YM2608 | Direct YM2608 port-0/port-1 writes → JT2608 wrapper; optional same-stem .pcm sidecar is uploaded before playback | Experimental candidate path; six FM lanes, SSG, and ADPCM-B sidecar are present; fixed rhythm-ROM/ADPCM-A audio is not implemented |

The OPNA path is intentionally narrow. It accepts timestamped direct-register
writes and supported waits/end markers, uses a bounded 128 KiB sidecar store,
and rejects unsupported or ambiguous streams rather than silently dropping
commands. Do not infer support for arbitrary VGM commands, multi-chip files,
the YM2608 fixed rhythm ROM, or ADPCM-A audio.

PMD/FMP, S98, multi-chip VGM, unsupported clock fields, unsupported commands,
and malformed files are outside this source snapshot's playback scope.

## Build and verify

Run these commands from the RetroFM directory:

~~~powershell
.\test.ps1
.\verify.ps1
.\verify.ps1 -RouteVendor
.\verify.ps1 -ImplementFullDesign
~~~

test.ps1 configures and runs the host core tests and the public target-support
tests. The MXDRV comparison test is added only when the separately fetched
prototype dependency is present. verify.ps1 adds the Xilinx RTL suites;
RouteVendor adds the slower vendor-core gate and ImplementFullDesign runs the
complete PS/PL build.

The public verification path fetches only dependencies whose source terms are
cleared for this repository:

~~~powershell
.\fetch_dependencies.ps1
.\test.ps1
.\build.ps1
~~~

The design targets xc7z010clg400-1, uses a 100 MHz PS FCLK, and does not use
the adapter's standalone N18 clock. Vivado/Vitis, XSCT, and Bootgen 2024.2 are
external AMD/Xilinx tools and are not redistributed here.

The current MDX target requires the optional portable_mdx/MXDRV/X68Sound
prototype dependency. To create standalone firmware and a ready-to-copy SD
directory for private evaluation, explicitly acknowledge that boundary:

~~~powershell
.\fetch_dependencies.ps1 -IncludePrototypeMdx
.\build.ps1
.\packaging\build_firmware.ps1 -IncludePrototypeMdx
~~~

The final command generates `build/vitis/sd/BOOT.BIN` plus the SD directory.
That binary is private and non-redistributable until the portable_mdx terms are
resolved. Build output and proprietary Xilinx tools are intentionally not
committed to this public snapshot.

## SD card workflow

1. Use an 8 GB or 16 GB microSDHC card for first bring-up; ordinary Class 4 or
   Class 10 media is sufficient.
2. Create one MBR primary partition and format it FAT32. A 32 KiB allocation
   unit is a safe choice. Do not use exFAT or secondary/recovery partitions.
3. Copy the contents of build/vitis/sd to the card root. Keep BOOT.BIN at the
   root and put playable files under /music.
4. Keep optional PDX files beside their MDX files. OPNA sidecars use the same
   basename with the .pcm extension and are not standalone tracks.
5. Set MIO5 to the verified SD-boot level before a power cycle. MIO4 is not a
   player button and should not be held during reset.

The player recursively scans /music to four directory levels. See
[hardware.md](docs/hardware.md) and [packaging/README.md](packaging/README.md).

## Hardware and filter warning

| Function | EBAZ4205 / adapter connection |
| --- | --- |
| Audio left | FPGA P18 → H4 pin 4 |
| Audio right | FPGA M19 → H4 pin 6 |
| Audio ground | H4 pin 2 |
| LCD | CS T20, D/C R18, reset N17, SCLK R19, MOSI P20 |
| Buttons | T19 previous, P19 play/pause, U20 next, U19 volume down, V20 volume up |

The intended first-build filter is one network per channel:

~~~text
FPGA output -- 220 ohm --+-- 10 uF series capacitor -- line input
                          |
                        100 nF
                          |
                         GND
~~~

The nominal corner is 7.23 kHz. Connect the filtered output only to an active
speaker or a line input rated at least 10 kohm; this is not a headphone or
passive-speaker driver. Power off before fitting the filter, verify H4
continuity, and confirm the selected contacts are not tied to 3.3 V or 5 V.
After settling, measure less than 50 mV DC after the 10 uF capacitor. Use a
high-impedance oscilloscope for overshoot and channel-isolation checks.

The ST7789 route constraints cover FPGA package routes only. Panel setup/hold,
cable delay, ringing, voltage margin, and the audio connector still require
bench measurements. Keep the [bench record](docs/bench-record.md) open until
those measurements and listening tests exist.

## Evidence and known limitations

The candidate evidence ledger is in [STATUS.md](STATUS.md). The current audit
record reports 9/9 host CTest tests and 3/3 public target-support CTest tests,
candidate RTL/build checks, and a routed/package candidate. Those results do
not imply a board boot or audible output.

Known limitations:

- Physical H4 continuity, filtered audio, display, buttons, FAT32 cold boot,
  and 30-minute playback are not accepted yet.
- Standalone local ngspice evidence is unavailable; analog bench checks remain
  open.
- The OPNA path has no fixed rhythm-ROM/ADPCM-A audio and remains experimental.
- MDX PCM8 bank-select commands E0–E6, unknown commands, LZX-wrapped input, and
  zero-time/pathological loops are rejected explicitly.
- The public snapshot contains no prebuilt binary or music release.

## Media slots

The source snapshot has no reviewed media assets. Add artifacts only after the
corresponding evidence is recorded:

- ST7789 UI photograph.
- EBAZ4205 plus H4 adapter photograph.
- High-impedance scope capture of filtered left/right output.
- FAT32 card layout photograph.
- Architecture rendering based on the diagram above.

## Acknowledgements and licensing

The combined RetroFM source is GPL-3.0-only; see [LICENSE](LICENSE), [COPYING](COPYING), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Dependency revisions and
their terms are pinned in [third_party.lock.json](third_party.lock.json).

The board integration follows the EBAZ4205 tutorial and adapter work by
[tomorrow56 / ThousanDIY](https://qiita.com/tomorrow56/items/7a6340c04b87f584288a).
The PS preset and adapter materials are used under the upstream MIT notice.

The FPGA cores acknowledge Jose Tejada and contributors through
[JT51](https://github.com/jotego/jt51), [JT12](https://github.com/jotego/jt12),
and [JT49](https://github.com/jotego/jt49). MDX sequencing retains the
hardened [mdxtools](https://github.com/vampirefrog/mdxtools) adaptation.
The target's MXDRV path uses pinned
[portable_mdx](https://github.com/yosshin4004/portable_mdx) sources and the
original MXDRVg/MXDRV.X/X68Sound authors' work: the timer, command, register,
PCM, and ADPCM paths remain, while software OPM output is compiled out and
ordered writes are sent to JT51. The portable_mdx lock entry records unresolved
prototype-distribution terms; do not treat them as cleared by this README.

Other retained notices cover [miniz](https://github.com/richgel999/miniz),
[M5Stack M5GFX](https://github.com/m5stack/M5GFX), and the IPA font license.
Read the shipped notices before redistributing a build or any test asset.
