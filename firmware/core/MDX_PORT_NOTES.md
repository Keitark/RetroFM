# MDX sequencing port notes

The sequencing implementation in `src/retrofm_mdx_sequence.c` is a
GPL-3.0-or-later port of the behavior in these files from mdxtools commit
`606e3a7009aa1a9dfa6bee8bc875dbd5483714e9`:

- `mdx_driver.c` and `mdx_driver.h`
- `fm_driver.c` and `fm_driver.h`
- `fm_opm_driver.c` and `fm_opm_driver.h`
- `timer_driver.c` and `timer_driver.h`

The reference checkout is `samples/retrofm_player/build/deps/mdxtools`. The
a mutable developer checkout is not used or copied.

The low-level `fm_driver`/`fm_opm_driver` sources are vendored under
`vendor/mdxtools`. The bounds-safe sequencer calls that driver for pitch,
total level, voice loading, pan, hardware LFO, key on/off, and direct OPM
writes; its write callback converts the resulting ordered writes into FPGA
events without polling or collapsing repeated register writes.

## Local safety and correctness patches

- The bounds-safe `retrofm_mdx_open` result is the only accepted input. The
  upstream loader reads beyond short offset tables and accepts malformed
  overlapping chunks.
- Repeat counters live in sequencer state. Upstream writes counters into the
  caller's MDX file buffer, preventing read-only media mapping and clean replay.
- Every command is framed again before execution, and a per-track limit of
  4096 commands per timer tick stops zero-time loops and pathological nested
  repeats from hanging the player.
- Sync-wait immediately stops the current track. The upstream inner advance
  loop ignores its newly set `waiting` flag until it encounters another timed
  command.
- Signed detune, portamento, pitch and LFO arithmetic uses defined, saturating
  operations. The upstream implementation can left-shift negative signed
  values and index the note table with a negative remainder.
- Delayed key-on fires while audible note time remains. Upstream tests
  `staccato_counter == 0`, which prevents the normal delayed note from ever
  receiving key-on.
- Amplitude-only LFO state is restarted at key-on. Upstream only performs LFO
  restart when pitch LFO is enabled.
- YM2151 register `0x0f` retains the MDX noise-enable bit. Upstream masks the
  value to five bits, so noise is never enabled.
- Total-level modulation saturates to `0..127` rather than wrapping negative
  or oversized LFO/fade attenuation through an implicit `uint8_t` conversion.
- MDX command `0xe7 0x01 rate` starts the existing fade mechanism; upstream
  frames the command but its driver silently skips it.
- Natural completion emits one timestamped `RETROFM_OP_END`. Long gaps are
  split into `RETROFM_OP_DELAY` records so every 100 MHz delta fits 32 bits.

## Deliberate integration differences

- The bridge does not instantiate or link the mdxtools software YM2151
  emulator. It translates the same high-level FM operations directly into
  timestamped `RETROFM_OP_YM2151` register events for JT51.
- `fm_opm_driver_init` emits its complete 264-write YM2151 register image
  before any song event. PL reset still clears JT51 first, while the driver
  initialization establishes the exact state expected by MDX playback.
- Looped tracks repeat indefinitely. The upstream driver's default is two
  loops followed by an automatic fade; the RetroFM product requirement keeps
  a looped song playing until track navigation.
- MDX+PDX initialization requires a successfully parsed `retrofm_pdx` and a
  PCM callback. The callback receives timestamped play, stop, frequency,
  volume and per-channel pan commands; its fields map directly onto the
  allocation-free `retrofm_pcm` API.

## Remaining upstream-compatible limitations

- PCM8 enable `0xe8` activates tracks Q-W (PCM channels 1-7). The available
  format documentation does not define the informal `0xe0..0xe6` PCM8 bank or
  expansion-shift encodings, so those commands on PCM tracks fail explicitly
  with `RETROFM_MDX_PCM8_BANK_UNSUPPORTED`; the implementation does not guess
  a PDX bank mapping.
- The pinned mdxtools mixer has one global PCM pan value and the pinned MDX
  driver ignores `0xfc` on PCM tracks. This port deliberately carries the MDX
  pan command into the matching `retrofm_pcm` channel, which is required for
  correct eight-channel PCM8 mixing and avoids cross-channel pan coupling.
- The pinned driver inconsistently maps MDX volume for PCM: note-on uses its
  OPM-to-PCM table, while later volume commands pass OPM attenuation directly.
  This port applies the pinned conversion table uniformly to play, volume and
  fade callbacks.
- Sync-wait can intentionally leave a song unfinished when no track sends the
  matching resume command. A higher-level watchdog or user navigation must
  stop such a song.
- The 4096-command zero-time limit is a safety policy. An unusual but finite
  track that legitimately performs more work without advancing time is
  rejected with `RETROFM_MDX_ZERO_TIME_LOOP`.
