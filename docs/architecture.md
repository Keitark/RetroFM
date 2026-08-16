# RetroFM architecture

## Responsibility split

The ARM processing system owns FAT32, gzip decompression, MDX/VGM sequencing,
PDX ADPCM decoding, controls, metadata conversion, and the display. The FPGA
fabric owns the two FM cores, event deadlines, sample mixing, level metering,
mute ramping, and the stereo sigma-delta outputs.

```text
FAT32 /music
  |-- MDX -> mdxtools driver -> timestamped YM2151 writes --+
  |-- PDX -> PS ADPCM decoder -> 48 kHz stereo PCM --------+--> AXI4-Lite
  `-- VGM/VGZ -> VGM iterator -> timestamped YM2203 writes-+       |
                                                                  v
       +---------------- PL control/audio output @ 100 MHz -----------------+
       | 2048 x 64 event FIFO -> deadline scheduler -> JT51 + JT03           |
       | 4096 x 32 PCM FIFO ---------------------------> 48 kHz mixer         |
       | FM + SSG + PDX -> saturation -> volume -> mute ramp -> L/R SDM      |
       +--------------------------------------------------------------------+
                                                        |             |
                                               P18 / H4-4      M19 / H4-6
```

Both FM cores are instantiated in the bitstream. Only the selected core is
audible, but keeping both resident avoids a reconfiguration pause between
formats. AXI, the event timebase, mixer, and sigma-delta modulators use the
100 MHz PS FCLK0. A Clocking Wizard generates an 80 MHz Yamaha-core domain from
that same FCLK. This is required because the audited JT51 revision misses a
plain 100 MHz single-cycle constraint on XC7Z010; 80 MHz also makes the fixed
JT51 enables exact (4 MHz every 20 clocks and `cen_p1` 2 MHz every 40 clocks).
Command and sample crossings use explicit asynchronous handshakes/FIFOs. JT03
uses a fractional enable for the validated VGM clock.

The Yamaha sample mailboxes retain the latest native core sample and the mixer
samples that value at 48 kHz. This preserves pitch and register timing but is a
zero-order/latest-sample conversion rather than a band-limited resampler. The
7.23 kHz prototype filter suppresses much of the out-of-band energy; a later
interpolating sample-rate converter is a fidelity improvement, not a release
format requirement.

## Time representation

All event deltas are expressed in 100 MHz PL clock cycles. VGM waits use a
rational remainder accumulator rather than independently rounded conversions:

```text
numerator = wait_samples * 100000000 + remainder
delta     = numerator / 44100
remainder = numerator % 44100
```

This prevents long tracks from drifting because of repeated rounding. MDX
timer callbacks use the same absolute 100 MHz timebase before events enter the
FIFO.

## Playback invariants

- A file is validated before the output is unmuted.
- Unsupported clock fields or commands are fatal for that track; they are not
  silently skipped.
- FIFO overflow never overwrites an older event or PCM frame.
- Event underrun mutes only FM until the queue recovers. PCM underrun inserts
  zero and does not disturb FM state.
- Pause ramps to zero before stopping the playback clock. Stop/reset ramps to
  zero, flushes both FIFOs, resets both cores, and then clears counters.
- An unmute command arriving during the cross-domain core-reset handshake is
  latched and applied after reset completes, including at low valid YM2203
  clocks.
- A natural end advances. A valid loop repeats until the user selects another
  track. A zero-progress loop is rejected.

## Display and controls

The PS drives the ST7789 over PS SPI0 routed through EMIO. `T20` is chip select,
not backlight. `R18` and `N17` are PS-controlled D/C and reset outputs. The five
active-low PL buttons are sampled and debounced in the PL, then read by the PS:

| FPGA pin | Action |
| --- | --- |
| T19 | previous |
| P19 | play/pause |
| U20 | next |
| U19 | volume down |
| V20 | volume up |

MIO5 remains a boot strap. MIO4 is not used as a player control because its
level is sampled during reset.
