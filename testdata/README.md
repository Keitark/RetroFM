# Generated smoke-test music

Run `python generate_testdata.py` to reproduce every file below
`generated/`. The script creates an FM-only YM2151 MDX, a looping YM2151
hard-left/hard-right/center test, an MDX with a matching PDX, and matching
uncompressed/compressed YM2203 VGM files. They are short technical tones
intended for register, timing, panning, and PCM bring-up—not musical
compositions.

The generated files and the musical/test data expressed by the generator are
dedicated to the public domain under CC0-1.0. The player and generator source
remain GPL-3.0-or-later. `generated/manifest.json` records the byte length and
SHA-256 of each reproducible binary.

These files are parser and bench inputs. Their existence does not prove that
the FPGA bitstream, target firmware, external filter, or physical board has
played them successfully.
