#!/usr/bin/env python3
"""Generate deterministic, rights-cleared RetroFM smoke tracks."""

from __future__ import annotations

import gzip
import hashlib
import io
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "generated"


def le32(value: int) -> bytes:
    return struct.pack("<I", value)


def be16(value: int) -> bytes:
    return struct.pack(">H", value & 0xFFFF)


def be32(value: int) -> bytes:
    return struct.pack(">I", value)


def ym_write(stream: bytearray, register: int, value: int) -> None:
    stream.extend((0x55, register & 0xFF, value & 0xFF))


def vgm_wait(stream: bytearray, samples: int) -> None:
    while samples:
        amount = min(samples, 0xFFFF)
        stream.append(0x61)
        stream.extend(struct.pack("<H", amount))
        samples -= amount


def make_gd3(title: str) -> bytes:
    fields = (
        title,
        "",
        "RetroFM generated tests",
        "",
        "YM2203",
        "",
        "RetroFM project",
        "",
        "2026",
        "generate_testdata.py",
        "CC0-1.0 deterministic hardware smoke track",
    )
    payload = "\0".join(fields).encode("utf-16le") + b"\0\0"
    return b"Gd3 " + le32(0x00000100) + le32(len(payload)) + payload


def make_vgm() -> bytes:
    commands = bytearray()

    # YM2203 SSG channel A: a quiet square tone centered into both outputs.
    ym_write(commands, 0x00, 0x80)
    ym_write(commands, 0x01, 0x01)
    ym_write(commands, 0x07, 0x3E)
    ym_write(commands, 0x08, 0x0A)

    # YM2203 FM channel 0, algorithm 7. This intentionally uses only the
    # ordinary register path supported by command 0x55.
    operator_offsets = (0x00, 0x04, 0x08, 0x0C)
    multiples = (0x01, 0x02, 0x03, 0x04)
    levels = (0x18, 0x20, 0x28, 0x00)
    for offset, multiple, level in zip(operator_offsets, multiples, levels):
        ym_write(commands, 0x30 + offset, multiple)
        ym_write(commands, 0x40 + offset, level)
        ym_write(commands, 0x50 + offset, 0x1F)
        ym_write(commands, 0x60 + offset, 0x08)
        ym_write(commands, 0x70 + offset, 0x04)
        ym_write(commands, 0x80 + offset, 0x0F)
    ym_write(commands, 0xB0, 0x07)

    loop_in_stream = len(commands)
    notes = ((0x22, 0x69), (0x22, 0xD2), (0x26, 0x69), (0x26, 0xD2))
    note_samples = 11025
    for high, low in notes:
        ym_write(commands, 0xA4, high)
        ym_write(commands, 0xA0, low)
        ym_write(commands, 0x28, 0xF0)
        vgm_wait(commands, note_samples)
    ym_write(commands, 0x28, 0x00)
    commands.append(0x66)

    header = bytearray(0x100)
    header[0:4] = b"Vgm "
    header[0x08:0x0C] = le32(0x00000171)
    header[0x18:0x1C] = le32(note_samples * len(notes))
    loop_absolute = len(header) + loop_in_stream
    header[0x1C:0x20] = le32(loop_absolute - 0x1C)
    header[0x20:0x24] = le32(note_samples * len(notes))
    header[0x34:0x38] = le32(0x100 - 0x34)
    header[0x44:0x48] = le32(4_000_000)

    gd3 = make_gd3("RetroFM YM2203 FM + SSG Demo")
    gd3_absolute = len(header) + len(commands)
    header[0x14:0x18] = le32(gd3_absolute - 0x14)
    result = header + commands + gd3
    result[0x04:0x08] = le32(len(result) - 4)
    return bytes(result)


def opm_voice() -> bytes:
    voice = bytearray(27)
    voice[0] = 0x00
    voice[1] = 0x07  # feedback 0, algorithm 7
    voice[2] = 0x0F  # all four slots
    voice[3:7] = bytes((0x01, 0x02, 0x03, 0x04))
    voice[7:11] = bytes((0x18, 0x20, 0x28, 0x00))
    voice[11:15] = bytes((0x1F, 0x1F, 0x1F, 0x1F))
    voice[15:19] = bytes((0x08, 0x08, 0x08, 0x08))
    voice[19:23] = bytes((0x04, 0x04, 0x04, 0x04))
    voice[23:27] = bytes((0x0F, 0x0F, 0x0F, 0x0F))
    return bytes(voice)


def add_mdx_loop(track: bytearray, loop_start: int) -> None:
    after = len(track) + 3
    relative = loop_start - after
    if not -32768 <= relative <= 32767:
        raise ValueError("MDX loop offset does not fit signed 16 bits")
    track.append(0xF1)
    track.extend(be16(relative))


def fm_track() -> bytes:
    track = bytearray((
        0xFF, 0xC0,  # tempo
        0xFD, 0x00,  # voice 0
        0xFC, 0x03,  # left + right
        0xFB, 0x0F,  # volume
    ))
    loop_start = len(track)
    for note in (0x98, 0x9C, 0x9F, 0xA4):
        track.extend((note, 0x30))
    add_mdx_loop(track, loop_start)
    return bytes(track)


def fm_lr_test_track() -> bytes:
    """Hard-left, hard-right, then centered YM2151 channel test."""
    track = bytearray((
        0xFF, 0xC0,  # tempo
        0xFD, 0x00,  # voice 0
        0xFB, 0x0F,  # maximum MDX volume
    ))
    loop_start = len(track)

    # MXDRV maps MDX pan 1 to YM2151 bit 6, which JT51 routes left;
    # pan 2 maps to bit 7/right, and pan 3 enables both outputs.
    # Short rests make leakage obvious.
    for pan, notes in (
        (0x01, (0x98, 0x98, 0x98)),       # three low left beeps
        (0x02, (0xA4, 0xA4, 0xA4)),       # three high right beeps
        (0x03, (0x98, 0xA4, 0x98, 0xA4)), # centered alternating beeps
    ):
        track.extend((0xFC, pan))
        for note in notes:
            track.extend((note, 0x18, 0x08))
        track.append(0x18)

    add_mdx_loop(track, loop_start)
    return bytes(track)


def pcm_track() -> bytes:
    track = bytearray((
        0xED, 0x04,  # PCM rate selector
        0xFB, 0x0F,  # volume
    ))
    loop_start = len(track)
    track.extend((0x80, 0x60, 0x20))
    add_mdx_loop(track, loop_start)
    return bytes(track)


def make_mdx(title: str, pdx_name: str = "", with_pcm: bool = False,
             fm_data: bytes | None = None) -> bytes:
    prefix = title.encode("ascii") + b"\r\n\x1a" + pdx_name.encode("ascii") + b"\0"
    tracks = [fm_track() if fm_data is None else fm_data]
    tracks.extend([b"\xF1\x00"] * 7)
    tracks.append(pcm_track() if with_pcm else b"\xF1\x00")
    table_bytes = 2 * (len(tracks) + 1)
    track_offsets = []
    cursor = table_bytes
    for track in tracks:
        track_offsets.append(cursor)
        cursor += len(track)
    voice_offset = cursor
    table = b"".join(be16(offset) for offset in
                     [voice_offset, *track_offsets])
    return prefix + table + b"".join(tracks) + opm_voice()


def make_pdx() -> bytes:
    # Low-nibble-first ADPCM codes. Alternating ramps make a short, obvious
    # percussive waveform without embedding any copyrighted sample.
    sample = bytes((0x77,) * 64 + (0xFF,) * 64 + (0x17, 0x9F) * 64)
    table = bytearray(96 * 8)
    table[0:4] = be32(len(table))
    table[4:8] = be32(len(sample))
    return bytes(table) + sample


def gzip_deterministic(payload: bytes) -> bytes:
    buffer = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=buffer,
                       compresslevel=9, mtime=0) as archive:
        archive.write(payload)
    return buffer.getvalue()


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    vgm = make_vgm()
    artifacts = {
        "retrofm_ym2203_demo.vgm": vgm,
        "retrofm_ym2203_demo.vgz": gzip_deterministic(vgm),
        "retrofm_ym2151_demo.mdx": make_mdx(
            "RetroFM YM2151 generated demo"),
        "retrofm_ym2151_lr_test.mdx": make_mdx(
            "RetroFM YM2151 Left Right Both Test",
            fm_data=fm_lr_test_track()),
        "retrofm_ym2151_pdx_demo.mdx": make_mdx(
            "RetroFM YM2151 plus PDX generated demo",
            "RETROFM_YM2151_PDX_DEMO.PDX", True),
        "retrofm_ym2151_pdx_demo.pdx": make_pdx(),
    }
    hashes = {}
    for name, payload in artifacts.items():
        path = OUTPUT / name
        path.write_bytes(payload)
        hashes[name] = {
            "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
        }
    (OUTPUT / "manifest.json").write_text(
        json.dumps({"schema": 1, "license": "CC0-1.0", "files": hashes},
                   indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    for name, record in hashes.items():
        print(f"{record['sha256']}  {name}  ({record['bytes']} bytes)")


if __name__ == "__main__":
    main()
