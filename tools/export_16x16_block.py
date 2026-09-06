#!/usr/bin/env python3
"""Export a 16x16 (2x2 tile) OBJ sprite block from the Crocomire composite
sheet as an editable PNG, given the base (top-left) tile number.

Layout for a SNES large (16x16) OBJ sprite built from 8x8 subtiles, base tile B:
    top-left  = B
    top-right = B+1
    bot-left  = B+$10
    bot-right = B+$11

Usage:
    python tools/export_16x16_block.py <input.bin> <base_tile_hex> <output.png> [scale]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from preview_4bpp import decode_tile, bgr555_to_rgb888, write_png, DEFAULT_PALETTE_BGR555

TILE_BYTES = 32


def main():
    in_path = Path(sys.argv[1])
    base = int(sys.argv[2], 16)
    out_path = Path(sys.argv[3])
    scale = int(sys.argv[4]) if len(sys.argv) > 4 else 32

    data = in_path.read_bytes()
    subtiles = [base, base + 1, base + 0x10, base + 0x11]

    palette_rgb = [bgr555_to_rgb888(w) for w in DEFAULT_PALETTE_BGR555]

    # Build 16x16 index grid
    grid = [[0] * 16 for _ in range(16)]
    for i, t in enumerate(subtiles):
        tx = (i % 2) * 8
        ty = (i // 2) * 8
        offset = t * TILE_BYTES
        if offset + TILE_BYTES > len(data):
            print(f"WARNING: tile ${t:02X} out of range, skipping")
            continue
        pixels = decode_tile(data, offset)
        for row in range(8):
            for col in range(8):
                grid[ty + row][tx + col] = pixels[row][col]

    width = 16 * scale
    height = 16 * scale
    rows = []
    for y in range(height):
        src_y = y // scale
        row_bytes = bytearray()
        for x in range(width):
            src_x = x // scale
            idx = grid[src_y][src_x]
            if idx == 0:
                row_bytes.extend((0, 0, 0, 0))
            else:
                r, g, b = palette_rgb[idx]
                row_bytes.extend((r, g, b, 255))
        rows.append(bytes(row_bytes))

    write_png(str(out_path), width, height, rows)
    print(f"Wrote {out_path} ({width}x{height}) from tiles: " + ", ".join(f"${t:02X}" for t in subtiles))


if __name__ == "__main__":
    main()
