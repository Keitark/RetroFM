# RetroFM physical bench record

This is an operator-completed acceptance sheet. Leave a result open until an
actual measurement or listening test has been performed on the named board.
Simulation and a successful bitstream build do not fill this sheet.

## Board identification

- EBAZ4205 serial/marking:
- expansion-board revision:
- bitstream/application build ID:
- test date and operator:
- oscilloscope/probe:
- line-input device and measured/rated impedance:

## Power-off H4 checks

| Check | Measured result | Pass/fail |
| --- | --- | --- |
| H4-4 continuity to P18 | | OPEN |
| H4-6 continuity to M19 | | OPEN |
| H4-2 continuity to ground | | OPEN |
| H4-4 resistance to 3.3 V / 5 V | | OPEN |
| H4-6 resistance to 3.3 V / 5 V | | OPEN |

## Powered audio checks

| Check | Left | Right | Pass/fail |
| --- | ---: | ---: | --- |
| unconfigured/idle pin voltage | | | OPEN |
| sigma-delta minimum/maximum at FPGA pin | | | OPEN |
| filter-side DC before 10 uF capacitor | | | OPEN |
| settled DC after 10 uF capacitor, limit 50 mV | | | OPEN |
| measured -3 dB corner, nominal 7.23 kHz | | | OPEN |
| opposite-channel leakage during solo tone | | | OPEN |

- Scope capture paths:
- Electrolytic polarity as fitted:
- Overshoot/undershoot observation:

## Functional acceptance

| Test | Evidence/notes | Pass/fail |
| --- | --- | --- |
| fixed YM2151 tone on both outputs | | OPEN |
| audible YM2151 left/right pan separation | | OPEN |
| rights-cleared FM-only MDX | | OPEN |
| rights-cleared MDX+PDX | | OPEN |
| rights-cleared YM2203 VGM | | OPEN |
| rights-cleared YM2203 VGZ | | OPEN |
| previous / play-pause / next / volume buttons | | OPEN |
| display title, state, activity, errors | | OPEN |
| natural end auto-advances | | OPEN |
| looped track repeats until navigation | | OPEN |
| 30-minute late/event/PCM underrun counters remain zero | | OPEN |
| FAT32 cold boot from SD with `BOOT.BIN` | | OPEN |

Overall physical acceptance: **OPEN**
