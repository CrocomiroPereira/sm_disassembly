#!/usr/bin/env python3
"""Render the full composite tile sheet as a labelled contact sheet, 16 tiles
per row (matching Mesen's VRAM/Tile Viewer layout), with a hex tile-index
label under every tile, so exact tile numbers can be read off visually
instead of guessed.

Usage:
    python tools/export_contact_sheet.py <input.bin> <output.png> [scale]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from preview_4bpp import decode_tile, bgr555_to_rgb888, write_png, DEFAULT_PALETTE_BGR555

TILE_BYTES = 32
TILES_PER_ROW = 16

# Minimal 3x5 bitmap digit font for hex labels (0-9, A-F)
FONT = {
    '0': ["111","101","101","101","111"],
    '1': ["010","110","010","010","111"],
    '2': ["111","001","111","100","111"],
    '3': ["111","001","111","001","111"],
    '4': ["101","101","111","001","001"],
    '5': ["111","100","111","001","111"],
    '6': ["111","100","111","101","111"],
    '7': ["111","001","010","010","010"],
    '8': ["111","101","111","101","111"],
    '9': ["111","101","111","001","111"],
    'A': ["111","101","111","101","101"],
    'B': ["110","101","110","101","110"],
    'C': ["111","100","100","100","111"],
    'D': ["110","101","101","101","110"],
    'E': ["111","100","111","100","111"],
    'F': ["111","100","111","100","100"],
}


def draw_text(rows_rgba, width, x0, y0, text, color=(0, 255, 0, 255)):
    for i, ch in enumerate(text):
        glyph = FONT.get(ch.upper())
        if not glyph:
            continue
        gx = x0 + i * 4
        for gy, line in enumerate(glyph):
            for gxx, bit in enumerate(line):
                if bit == '1':
                    px = gx + gxx
                    py = y0 + gy
                    if 0 <= py < len(rows_rgba) and 0 <= px < width:
                        o = px * 4
                        rows_rgba[py][o:o+4] = bytes(color)


def main():
    in_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 4

    data = in_path.read_bytes()
    n_tiles = len(data) // TILE_BYTES
    n_rows = (n_tiles + TILES_PER_ROW - 1) // TILES_PER_ROW

    palette_rgb = [bgr555_to_rgb888(w) for w in DEFAULT_PALETTE_BGR555]

    cell_w = 8 * scale
    label_h = 8  # fixed-size label strip, unscaled
    cell_h = 8 * scale + label_h

    W = TILES_PER_ROW * cell_w
    H = n_rows * cell_h

    rows = [bytearray(W * 4) for _ in range(H)]
    # fill mid-gray background so tile index 0 (transparent) is visible against it
    for row in rows:
        for i in range(0, len(row), 4):
            row[i:i+4] = bytes((60, 60, 60, 255))

    for t in range(n_tiles):
        tx = (t % TILES_PER_ROW) * cell_w
        ty = (t // TILES_PER_ROW) * cell_h
        offset = t * TILE_BYTES
        pixels = decode_tile(data, offset)
        for r in range(8):
            for c in range(8):
                idx = pixels[r][c]
                if idx == 0:
                    continue
                rr, gg, bb = palette_rgb[idx]
                for sy in range(scale):
                    for sx in range(scale):
                        py = ty + r * scale + sy
                        px = tx + c * scale + sx
                        o = px * 4
                        rows[py][o:o+4] = bytes((rr, gg, bb, 255))
        label = f"{t:02X}"
        draw_text(rows, W, tx + 1, ty + cell_w - label_h + 1, label, color=(0, 255, 0, 255))

    write_png(str(out_path), W, H, [bytes(r) for r in rows])
    print(f"Wrote {out_path} ({W}x{H}), {n_tiles} tiles, {n_rows} rows x {TILES_PER_ROW} cols")


if __name__ == "__main__":
    main()
