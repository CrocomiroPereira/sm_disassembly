#!/usr/bin/env python3
"""Assemble a %spritemapEntry block from a .asm source into a PNG, using a
raw 4bpp tile sheet .bin as the graphics source. This mimics how the SNES
would actually lay the OBJs out on screen (16x16 blocks made of 4 8x8
subtiles: N, N+1, N+0x10, N+0x11), so you can see the real in-game pose
instead of just the raw tile sheet.

Usage:
    python tools/preview_spritemap.py <source.asm> <LabelName> <tiles.bin> <output.png> [scale]
"""

import re
import struct
import sys
import zlib
from pathlib import Path

DEFAULT_PALETTE_BGR555 = [
    0x0000, 0x7FFF, 0x0DFF, 0x08BF, 0x0895, 0x086C, 0x0447, 0x6B7E,
    0x571E, 0x3A58, 0x2171, 0x0CCB, 0x039F, 0x023A, 0x0176, 0x0000,
]

ENTRY_RE = re.compile(
    r"%spritemapEntry\(\s*(\d+)\s*,\s*\$?([0-9A-Fa-f]+)\s*,\s*\$?([0-9A-Fa-f]+)\s*,"
    r"\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*\$?([0-9A-Fa-f]+)\s*\)"
)


def bgr555_to_rgb888(word):
    r = word & 0x1F
    g = (word >> 5) & 0x1F
    b = (word >> 10) & 0x1F
    scale = lambda c: (c * 255 + 15) // 31
    return scale(r), scale(g), scale(b)


def decode_tile(data, offset):
    pixels = [[0] * 8 for _ in range(8)]
    if offset + 32 > len(data):
        return pixels
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


def signed15(v):
    v &= 0x7FFF
    if v & 0x4000:
        return v - 0x8000
    return v


def signed8(v):
    v &= 0xFF
    if v & 0x80:
        return v - 0x100
    return v


def write_png(path, width, height, rgba_rows):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = bytearray()
    for row in rgba_rows:
        raw.append(0)
        raw.extend(row)
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        sys.exit(1)

    asm_path = Path(sys.argv[1])
    label = sys.argv[2]
    bin_path = Path(sys.argv[3])
    out_path = Path(sys.argv[4])
    scale = int(sys.argv[5]) if len(sys.argv) > 5 else 8
    # Optional crop, in un-scaled canvas pixel coords: cx,cy,cw,ch
    crop = None
    if len(sys.argv) > 9:
        crop = tuple(int(a) for a in sys.argv[6:10])

    text = asm_path.read_text(encoding="utf-8", errors="replace")
    label_pat = re.compile(re.escape(label) + r"\s*:")
    m = label_pat.search(text)
    if not m:
        print(f"Label {label} not found in {asm_path}")
        sys.exit(1)

    # Grab text from label to the next blank-line-preceded label or 'warnpc'
    rest = text[m.end():]
    end_m = re.search(r"\n\s*\n\S|\nwarnpc", rest)
    block = rest[: end_m.start()] if end_m else rest

    entries = []
    for em in ENTRY_RE.finditer(block):
        size, x, y, yflip, xflip, prio, pal, tile = em.groups()
        entries.append(dict(
            size=int(size),
            x=signed15(int(x, 16)),
            y=signed8(int(y, 16)),
            yflip=int(yflip),
            xflip=int(xflip),
            tile=int(tile, 16),
        ))

    if not entries:
        print("No spritemap entries parsed")
        sys.exit(1)

    data = bin_path.read_bytes()
    tiles_per_row = 16

    min_x = min(e["x"] for e in entries)
    min_y = min(e["y"] for e in entries)
    max_x = max(e["x"] + (16 if e["size"] else 8) for e in entries)
    max_y = max(e["y"] + (16 if e["size"] else 8) for e in entries)

    off_x = -min_x
    off_y = -min_y
    W = max_x - min_x
    H = max_y - min_y

    canvas = [[None] * W for _ in range(H)]

    def blit_tile(tile_no, dst_x, dst_y, xflip, yflip):
        tile_offset = tile_no * 32
        px = decode_tile(data, tile_offset)
        for r in range(8):
            for c in range(8):
                sr = 7 - r if yflip else r
                sc = 7 - c if xflip else c
                v = px[sr][sc]
                yy = dst_y + r
                xx = dst_x + c
                if 0 <= yy < H and 0 <= xx < W and v != 0:
                    canvas[yy][xx] = v

    for e in entries:
        dst_x = e["x"] + off_x
        dst_y = e["y"] + off_y
        if e["size"] == 1:
            # 16x16: subtiles N, N+1 (top row), N+0x10, N+0x11 (bottom row)
            t = e["tile"]
            subtiles = [
                (t, 0, 0), (t + 1, 8, 0),
                (t + 0x10, 0, 8), (t + 0x11, 8, 8),
            ]
            for sub_t, sx, sy in subtiles:
                # account for flips swapping quadrant positions
                qx, qy = sx, sy
                if e["xflip"]:
                    qx = 8 - sx
                if e["yflip"]:
                    qy = 8 - sy
                blit_tile(sub_t, dst_x + qx, dst_y + qy, e["xflip"], e["yflip"])
        else:
            blit_tile(e["tile"], dst_x, dst_y, e["xflip"], e["yflip"])

    rgb_palette = [bgr555_to_rgb888(w) for w in DEFAULT_PALETTE_BGR555]

    if crop:
        cx, cy, cw, ch = crop
    else:
        cx, cy, cw, ch = 0, 0, W, H

    out_w = cw * scale
    out_h = ch * scale
    rows = []
    for y in range(out_h):
        row = bytearray(out_w * 4)
        sy = cy + y // scale
        for x in range(out_w):
            sx = cx + x // scale
            if sy < 0 or sy >= H or sx < 0 or sx >= W:
                idx = None
            else:
                idx = canvas[sy][sx]
            o = x * 4
            if idx is None:
                row[o] = row[o + 1] = row[o + 2] = 0
                row[o + 3] = 0
            else:
                r, g, b = rgb_palette[idx]
                row[o] = r
                row[o + 1] = g
                row[o + 2] = b
                row[o + 3] = 255
        rows.append(bytes(row))

    write_png(out_path, out_w, out_h, rows)
    print(f"Wrote {out_path} ({out_w}x{out_h}), {len(entries)} entries, canvas {W}x{H}, origin offset ({off_x},{off_y})")


if __name__ == "__main__":
    main()
