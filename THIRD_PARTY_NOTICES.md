# Third-party notices

The reproducible source revisions are recorded in `third_party.lock.json`.
The combined RetroFM source is distributed under GPL-3.0-only because the
pinned mdxtools source grants GPLv3 without a verified later-version grant.
Some project-authored files retain their per-file GPL-3.0-or-later grants; those
headers do not relicense mdxtools-derived portions or the combined source. The
full GPLv3 text is in `COPYING`.

- JT51, commit `985a573dcfc1ff135553a39f7eae21d18ba57cbe`, by Jose
  Tejada and contributors: GPLv3-or-later source retained under
  `build/deps/jt51`.
- JT12/JT03, commit `45f4854f9ab43368f5a514857299ab7dfae4e6ab`, by
  Jose Tejada and contributors: GPLv3-or-later source retained under
  `build/deps/jt12`.
- JT49, commit `7f6abfd08a2af9a92dbd5b32c71ea773248a77e2`, by Jose
  Tejada and contributors: GPLv3-or-later source retained under
  `build/deps/jt49`.
- mdxtools, commit `606e3a7009aa1a9dfa6bee8bc875dbd5483714e9`, by its
  authors and contributors: GPLv3 source retained under
  `build/deps/mdxtools`. RetroFM carries a documented, hardened adaptation.
- miniz, commit `77d0dce8627735138c51770d1799a1ef48f2117d`: MIT.
- The CP932/Shift-JIS mapping table and converter were adapted from the
  Keitark M5 player: MIT. The complete notice is retained in
  `firmware/core/SJIS_LICENSE.txt`.
- M5GFX, commit `03565ccc96cb0b73c8b157f5ec3fbde439b034ad`, supplies the
  embedded IPA Gothic font data. M5GFX is MIT-licensed, Copyright (c) 2021
  M5Stack. The MIT notice is reproduced below. The font data is additionally
  governed by the IPA Font License Agreement v1.0 at
  `firmware/target/vendor/IPA_Font_License_Agreement_v1.0.txt`; that agreement
  must remain attached to source and binary distributions of the font.
- The EBAZ4205 PS preset and the ST7789 initialization values follow
  `tomorrow56/EBAZ4205_tutorial`, commit
  `ad2f97c881b06ae54d132e37675aac8543c28917`. Preserve the MIT notice for
  Copyright (c) 2025 tomorrow56 A.K.A. ThousanDIY. The pinned preset is fetched
  into `build/deps/tomorrow56` and is the only board-repository input used here.

## Prototype-only portable_mdx boundary

`portable_mdx`, commit `2429db394a2e1a1dad91b173f1affee5d8797aca`, is not
cleared for public redistribution. Its upstream README applies Apache 2.0 only
to a named subset and describes MXDRVg/MXDRV.X and X68Sound-derived code using
original terms whose scope and compatibility with this GPL source have not
been established. The target firmware currently stages MXDRV/X68Sound code,
including the OPM/ADPCM/PCM8 data paths, so `fetch_dependencies.ps1` skips this
dependency unless `-IncludePrototypeMdx` is explicitly supplied.

That switch is an acknowledgement for private prototype work, not a grant of
redistribution rights. Until the rights review is closed, do not publish or
redistribute any portable_mdx source, staged target source, BOOT.BIN, ELF,
bitstream, XSA, SD-card image, or other binary containing it. The packaging
script requires `-AllowPrivatePrototype` (passed by
`packaging/build_firmware.ps1 -IncludePrototypeMdx`) and must only be used for
non-public output.

## M5GFX MIT notice

Copyright (c) 2021 M5Stack

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## miniz MIT notice

Copyright 2013-2014 RAD Game Tools and Valve Software

Copyright 2010-2014 Rich Geldreich and Tenacious Software LLC

All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
