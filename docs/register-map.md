# PS-to-PL register contract

Base address is assigned by Vivado and exported in `xparameters.h`; firmware
must use that generated value rather than hardcode the provisional
`0x43C00000` allocation. All registers are little-endian 32-bit words.

## Event format

```text
63            52 51  48 47      40 39      32 31                    0
+----------------+------+----------+----------+----------------------+
| flags/reserved |opcode|   data   | register | delta, 100 MHz cycles|
+----------------+------+----------+----------+----------------------+
```

Opcodes are `0` JT51/YM2151, `1` JT03/YM2203, `2` delay/no-op, `3` end of
track, `4` JT2608/YM2608, and `15` diagnostics. For opcode `4`, event flag
bit 0 selects the YM2608 port 1 write; all other flags/reserved bits must be
zero. For every other opcode flags/reserved must be zero. A producer writes
`EVENT_LO` (the delta) first and `EVENT_HI` second; the `EVENT_HI` write
atomically commits the complete entry.

## Registers

| Offset | Name | Access | Meaning |
| ---: | --- | --- | --- |
| 0x00 | ID | R | `0x52464D31` (`RFM1`) |
| 0x04 | VERSION | R | ABI major in 31:16, minor in 15:0; current `1.2` |
| 0x08 | CONTROL | R/W | run, IRQ enables, selected chip |
| 0x0C | COMMAND | W1P | mute, unmute, core reset, FIFO flush, clear faults |
| 0x10 | EVENT_LO | W | delta staging word |
| 0x14 | EVENT_HI | W | opcode/register/data/flags and atomic commit |
| 0x18 | EVENT_STATUS | R | level, empty/full, faults, scheduler halted |
| 0x1C | EVENT_WATERMARK | R/W | low-water threshold, default 512 |
| 0x20 | PCM_FRAME | W | left in 15:0, right in 31:16; commits one frame |
| 0x24 | PCM_STATUS | R | level, empty/full, overflow, underrun sticky |
| 0x28 | VOLUME | R/W | unsigned Q1.15 gain, `0x8000` is unity |
| 0x2C | YM2203_CLOCK | R/W | validated clock in Hz |
| 0x30 | KEY_MASKS | R | JT51 in 7:0, JT03 FM1-FM3 in 10:8, JT03 SSG1-SSG3 in 13:11 |
| 0x34 | PEAKS | R | absolute peak L in 15:0, R in 31:16 |
| 0x38 | LATE_COUNT | R | saturated late-event count |
| 0x3C | PLAY_CYCLES_LO | R | coherent playback-cycle snapshot low word |
| 0x40 | PLAY_CYCLES_HI | R | coherent playback-cycle snapshot high word |
| 0x44 | BUTTONS | R | debounced active-high levels for five buttons |
| 0x48 | LCD_AUX | R/W | D/C, reset, and chip-select output bits |
| 0x4C | IRQ_STATUS | R/W1C | low water and sticky-fault interrupt sources |
| 0x50–0x6C | SPECTRUM_0..7 | R | eight words containing 32 packed 8-bit visualizer bins |
| 0x70 | JT03_METER_LO | R | packed 8-bit captured volumes for FM1, FM2, FM3, and SSG1 |
| 0x74 | JT03_METER_HI | R/RC | SSG2/SSG3 volumes in 15:0 and sticky trigger bits FM1–SSG3 in 21:16; reading clears triggers |
| 0x78 | OPNA_SAMPLE_ADDR | R/W | byte address for the bounded YM2608 ADPCM-B sample store |
| 0x7C | OPNA_SAMPLE_DATA | W | packed sample bytes; each write advances the sample address by four bytes |
| 0x80 | OPNA_METER_0 | R | packed 8-bit activity levels for OPNA FM1–FM4 |
| 0x84 | OPNA_METER_1 | R | packed 8-bit activity levels for OPNA FM5, FM6, SSG1, SSG2 |
| 0x88 | OPNA_METER_2 | R | packed 8-bit activity levels for OPNA SSG3, rhythm, ADPCM-B |
| 0x8C | OPNA_METER_FLAGS | R/RC | sticky triggers for the eleven OPNA lanes; reading clears them |

JT03 meter volumes are generated from the timestamped writes dispatched to the
core, so they remain aligned with audible playback even when software and the
event FIFO are far ahead. FM key-on captures an operator-4 carrier total-level
estimate (operator 4 is a carrier in every YM2203 algorithm);
SSG amplitude, mixer-enable, and envelope-restart writes capture the SSG level.
The UI applies the same note-trigger, decay, and afterglow algorithm used by
the MXDRV MDX meters.

For an OPNA track, the UI reads the separate eleven-lane meter block in this
order: FM1–FM6, SSG1–SSG3, rhythm, ADPCM-B. The FM and SSG lanes are derived
from the same timestamped register writes that feed the core. Rhythm and
ADPCM-B activity are write-driven indicators; this release does not include a
fixed OPNA rhythm-ROM/ADPCM-A audio implementation.

The OPNA sample registers load an optional same-stem `.pcm` sidecar before
unmute. The sample store is bounded at 128 KiB and is intended for the
Delta-T/ADPCM-B path. It is not a fixed rhythm-ROM substitute, and a VGM data
block that the parser cannot prove safe is rejected rather than ignored.

`CONTROL[0]` enables deadline consumption. `CONTROL[1]` enables the 48 kHz
PCM FIFO consumer; leave it clear for FM-only tracks so an empty PCM queue
does not create an underrun. `CONTROL[2]` requests the mixer’s FM-only
pop-suppressed mute ramp; it leaves PDX/PCM audible. `CONTROL[5:4]` selects none, JT51, JT03, or OPNA for
the mixer. `CONTROL[8]` enables event-low-water IRQ and
`CONTROL[9]` enables fault IRQ.

The status words have fixed bit allocations:

| Register | Bits | Meaning |
| --- | --- | --- |
| EVENT_STATUS | 12:0 | logical event level, including the prefetch slot |
| EVENT_STATUS | 16 | empty |
| EVENT_STATUS | 17 | full |
| EVENT_STATUS | 18 | event overflow sticky |
| EVENT_STATUS | 19 | scheduler underrun sticky |
| EVENT_STATUS | 20 | late-event sticky |
| EVENT_STATUS | 21 | fatal command/CDC fault: an outer command queue overflowed and dropped a write |
| EVENT_STATUS | 22 | scheduler halted after consuming END |
| EVENT_STATUS | 23 | nonfatal command bridge backpressure seen; no command was dropped |
| PCM_STATUS | 12:0 | queued PCM frame level |
| PCM_STATUS | 16 | empty |
| PCM_STATUS | 17 | full |
| PCM_STATUS | 18 | PCM overflow sticky |
| PCM_STATUS | 19 | PCM underrun sticky |
| IRQ_STATUS | 0 | event low water; level-sensitive, not W1C |
| IRQ_STATUS | 1 | event overflow; W1C |
| IRQ_STATUS | 2 | event underrun; W1C |
| IRQ_STATUS | 3 | late event; W1C |
| IRQ_STATUS | 4 | PCM overflow; W1C |
| IRQ_STATUS | 5 | PCM underrun; W1C |
| IRQ_STATUS | 6 | fatal command/CDC fault; W1C |

The Yamaha CDC bridges use ready/valid backpressure. A full bridge can hold a
command temporarily without losing or reordering it; that condition sets only
`EVENT_STATUS[23]` and never asserts the fault IRQ. `EVENT_STATUS[21]` and
`IRQ_STATUS[6]` are reserved for an actual outer command-queue overflow/drop.
Writing one to `IRQ_STATUS[6]`, or issuing `COMMAND[5]`, clears both histories.

`LATE_COUNT` and the late sticky bit mean producer-starvation lateness: a due
event was unavailable because the source FIFO drained. Serialized zero-delta
writes that share a musical timestamp are not late while they remain resident
in the FIFO.

`LATE_COUNT` therefore measures producer/deadline starvation, not the Yamaha
bus transaction completion time. Hardware command serialization is bounded
and lossless: the outer queue has 16 physical entries (one is reserved for the
scheduler's registered strobe) and each CDC bridge has eight entries. At the
audited 80 MHz wrapper rates, one JT51 write can take up to about 1.0 us and one
JT03 write at a 4 MHz master clock can take up to about 3.0 us. Thus 16 already
queued simultaneous writes can require roughly 16 us or 48 us respectively;
the complete 24-entry outer-plus-CDC pipeline can approach 24 us or 72 us.
`EVENT_STATUS[23]` records CDC-bridge backpressure so software can diagnose
such bursts. Any actual outer-queue overflow/drop remains fatal via
`EVENT_STATUS[21]` and `IRQ_STATUS[6]`.

While a running event stream is empty, the scheduler exposes active underrun
to a dedicated FM-only pop-suppressed ramp. JT51/JT03 ramp down while decoded
PDX/PCM continues; accepting resident recovery events releases the FM ramp.

`BUTTONS[4:0]` are active-high debounced levels: previous, play/pause, next,
volume down, and volume up respectively. The firmware performs rising-edge
detection; the register is not a W1C event latch.

`LCD_AUX[0]` is D/C (`1` data), bit 1 is `RESET_N` (`1` run), and bit 2 is
`CS_N` (`1` deselected). Firmware keeps a shadow value and preserves all other
bits. These allocations and `EVENT_STATUS[22]` are required by the target
application and remain subject to the integrated top-level RTL test/XSA gate.

The saturated event-underrun counter is currently an internal/top-level
diagnostic, while its sticky state is software-readable. It has no ABI
register in version 1; software must not infer an undocumented offset.

`COMMAND` bits are immediate and self-clearing:

- bit 0: request pop-suppressed mute;
- bit 1: request unmute;
- bit 2: reset both FM cores after mute;
- bit 3: flush event FIFO;
- bit 4: flush PCM FIFO;
- bit 5: clear sticky faults, peaks, late count, and playback time.

Mute and core reset have priority over unmute. If bit 1 is written while the
cross-domain Yamaha reset handshake is still active, hardware retains the
request and unmutes on the first safe system-clock edge after reset completes.

## FIFO rules

The event FIFO contains 2048 entries and the PCM FIFO contains 4096 packed
stereo frames. A commit while full is rejected and sets the relevant overflow
flag. The low-water IRQ is level-sensitive while `event_level <= watermark`;
software should refill to at least 75 percent before returning from the refill
path.
