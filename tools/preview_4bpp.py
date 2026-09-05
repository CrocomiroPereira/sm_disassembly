#!/usr/bin/env python3
"""Render a raw SNES 4bpp planar tile sheet .bin to a PNG, using a given
16-colour BGR555 palette (as it appears written in the .asm sources, e.g.
CrocomirePlayer_BGPalette). No external dependencies (pure stdlib PNG writer).

Usage:
    python tools/preview_4bpp.py <input.bin> <output.png> [tiles_per_row] [scale]
"""

import struct
import sys
import zlib
from pathlib import Path

# CrocomirePlayer_BGPalette from src/player_crocomire.asm, as BGR555 words.
DEFAULT_PALETTE_BGR555 = [
    0x0000, 0x7FFF, 0x0DFF, 0x08BF, 0x0895, 0x086C, 0x0447, 0x6B7E,
    0x571E, 0x3A58, 0x2171, 0x0CCB, 0x039F, 0x023A, 0x0176, 0x0000,
]


def bgr555_to_rgb888(word):
    r = word & 0x1F
    g = (word >> 5) & 0x1F
    b = (word >> 10) & 0x1F
    scale = lambda c: (c * 255 + 15) // 31
    return scale(r), scale(g), scale(b)


def decode_tile(data, offset):
    """Decode one 8x8 4bpp planar tile starting at offset. Returns 8x8 list of
    palette indices (0-15)."""
    pixels = [[0] * 8 for _ in range(8)]
    for row in range(8):
        bp0 = data[offset + row * 2]
        bp1 = data[offset + row * 2 + 1]
        bp2 = data[offset + 16 + row * 2]
        bp3 = data[offset + 16 + row * 2 + 1]
        for col in range(8):
            bit = 7 - col
            b0 = (bp0 >> bit) & 1
            b1 = (bp1 >> bit) & 1
            b2 = (bp2 >> bit) & 1
            b3 = (bp3 >> bit) & 1
            pixels[row][col] = b0 | (b1 << 1) | (b2 << 2) | (b3 << 3)
    return pixels


def write_png(path, width, height, rgba_rows):
    """rgba_rows: list of `height` bytes objects, each `width*4` bytes RGBA."""
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = bytearray()
    for row in rgba_rows:
        raw.append(0)  # filter type 0
        raw.extend(row)
    idat = zlib.compress(bytes(raw), 9)

    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    in_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    tiles_per_row = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    scale = int(sys.argv[4]) if len(sys.argv) > 4 else 4

    data = in_path.read_bytes()
    tile_count = len(data) // 32
    if tile_count == 0:
        print("Empty or too-small file")
        sys.exit(1)

    rows_of_tiles = (tile_count + tiles_per_row - 1) // tiles_per_row

    rgb_palette = [bgr555_to_rgb888(w) for w in DEFAULT_PALETTE_BGR555]

    px_w = tiles_per_row * 8
    px_h = rows_of_tiles * 8

    # index 0 = transparent
    canvas = [[None] * px_w for _ in range(px_h)]

    for t in range(tile_count):
        tile_x = (t % tiles_per_row) * 8
        tile_y = (t // tiles_per_row) * 8
        pixels = decode_tile(data, t * 32)
        for r in range(8):
            for c in range(8):
                canvas[tile_y + r][tile_x + c] = pixels[r][c]

    out_w = px_w * scale
    out_h = px_h * scale
    rows = []
    for y in range(out_h):
        row = bytearray(out_w * 4)
        src_y = y // scale
        for x in range(out_w):
            src_x = x // scale
            idx = canvas[src_y][src_x]
            if idx is None or idx == 0:
                r = g = b = 0
                a = 0
            else:
                r, g, b = rgb_palette[idx]
                a = 255
            o = x * 4
            row[o] = r
            row[o + 1] = g
            row[o + 2] = b
            row[o + 3] = a
        rows.append(bytes(row))

    write_png(out_path, out_w, out_h, rows)
    print(f"Wrote {out_path} ({out_w}x{out_h}, {tile_count} tiles, {rows_of_tiles} rows)")


if __name__ == "__main__":
    main()
