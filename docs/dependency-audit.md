# Dependency and licensing audit gate

No release may be produced while a dependency commit in
third_party.lock.json starts with REPLACE_. A repository default branch is not
a reproducible input.

## Accepted hardware and parser boundaries

- JT51: synthesizable YM2151-compatible hardware only; retain its GPL notice.
- JT03 from JT12: synthesizable YM2203-compatible hardware plus the required
  JT49 sources; retain the GPL notices.
- JT2608 candidate wrapper: the bounded OPNA integration uses the pinned JT12
  and JT49 source family for six FM channels, SSG, and ADPCM-B. Fixed
  YM2608 rhythm-ROM/ADPCM-A audio is intentionally not shipped.
- mdxtools: clean files from commit
  606e3a7009aa1a9dfa6bee8bc875dbd5483714e9, followed by the local hardening
  documented in firmware/core/MDX_PORT_NOTES.md. Always fetch the pinned
  revision rather than copying a mutable local checkout.
- miniz: gzip/deflate and CRC support only; retain the MIT notice.
- M5 player CP932 table/converter: allocation-free code adapted from the
  MIT-licensed Keitark source; retain firmware/core/SJIS_LICENSE.txt.

## MXDRV and portable_mdx target boundary

The target build does use the pinned portable_mdx sources when the dependency is
present. The lockfile identifies commit
2429db394a2e1a1dad91b173f1affee5d8797aca and records Apache-2.0 portions plus
the original MXDRVg/MXDRV.X and X68Sound terms, with prototype-distribution
rights still pending review.

firmware/target/retrofm_mxdrv.cpp is a thin adapter around that checkout.
MXDRV remains the authoritative MDX sequencer. The build retains the
X68Sound timer, command, register, envelope, PCM, and ADPCM paths, converts
ordered OPM writes into timestamped JT51 events, and compiles out the
software-OPM operator/output block. The software FM samples are therefore not
the product audio source; JT51 is.

The target CMake and packaging script generate a build-local patched
x68sound_opm.cpp with RETROFM_SUPPRESS_SOFTWARE_FM. The pinned dependency
checkout remains unchanged. Do not describe portable_mdx as desktop-only, and
do not describe this boundary as clearing its unresolved prototype terms.

## MDX safety and redistribution

The local clean-room integration validates headers, voices, tracks, operands,
repeat targets, and PDX ranges before use. Writable state stays outside the
input, arithmetic is bounded, and tests cover fades, delayed key-on,
modulation, repeats/loops, PCM callbacks, and callback failures. A missing PDX
is fatal only when a PCM note needs it.

PDX tracks P-W are supported; Q-W require the MDX PCM8-enable command. The
upstream PCM8 bank-select commands E0-E6 are intentionally rejected as
RETROFM_MDX_PCM8_BANK_UNSUPPORTED rather than ignored. LZX-wrapped input and
unknown commands are rejected.

Do not redistribute YS_05.MDX, an mdxtools music directory, or any test song
whose rights are not stated in a local manifest. Read
THIRD_PARTY_NOTICES.md, third_party.lock.json, and the per-file rights records
before redistributing a generated build.

## Reproducibility record

The audited HDL revisions are JT51
985a573dcfc1ff135553a39f7eae21d18ba57cbe, JT12
45f4854f9ab43368f5a514857299ab7dfae4e6ab, and JT49
7f6abfd08a2af9a92dbd5b32c71ea773248a77e2. Build logs and generated binaries
are intentionally excluded from the public source snapshot; STATUS.md records
the candidate evidence paths used during review.
