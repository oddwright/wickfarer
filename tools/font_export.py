"""Export the 3x5 pixel font from the concept art (pixel-src/font.py) as a glyph strip.
Usage: python3 tools/font_export.py /mnt/project-files/concept-art/pixel-src art/
"""
import sys, os, json
sys.path.insert(0, sys.argv[1])
from PIL import Image
import font
F = dict(font.F)
EXTRA = {
    '%': "#.. ..# .#. #.. ..#", '?': "##. ..# .#. ... .#.", '!': ".#. .#. .#. ... .#.",
    ',': "... ... ... .#. #..", '(': ".#. #.. #.. #.. .#.", ')': ".#. ..# ..# ..# .#.",
    '=': "... ### ... ### ...",
}
for k, v in EXTRA.items():
    F[k] = v.replace(' ', '')
# Wide letters read badly at 3 pixels, so M, N and W get extra columns.
WIDE = {
    'M': ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    'W': ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
    'N': ["#..#", "##.#", "#.##", "#..#", "#..#"],
}
rows = {}
for k, g in F.items():
    rows[k] = [g[j * 3:(j + 1) * 3] for j in range(5)]
rows.update(WIDE)
chars = sorted(rows.keys())
CELL = 5
GLYPH_H = 5
im = Image.new('RGBA', (len(chars) * CELL, GLYPH_H), (0, 0, 0, 0))
meta = {}
for n, ch in enumerate(chars):
    r = rows[ch]
    meta[ch] = [n, len(r[0])]
    for j in range(GLYPH_H):
        for i, v in enumerate(r[j]):
            if v == '#':
                im.putpixel((n * CELL + i, j), (255, 255, 255, 255))
# The same glyphs grown by one pixel on every side, drawn in dark ink under the text so it
# stays readable over fire, stars and panels. Baked here so the game draws one extra quad per
# letter, as it did for the old drop shadow, instead of eight.
OCELL = CELL + 2
ol = Image.new('RGBA', (len(chars) * OCELL, GLYPH_H + 2), (0, 0, 0, 0))
for n, ch in enumerate(chars):
    r = rows[ch]
    for j in range(GLYPH_H):
        for i, v in enumerate(r[j]):
            if v == '#':
                for dx in (0, 1, 2):
                    for dy in (0, 1, 2):
                        ol.putpixel((n * OCELL + i + dx, j + dy), (255, 255, 255, 255))
out = sys.argv[2]
im.save(os.path.join(out, 'font_3x5.png'))
ol.save(os.path.join(out, 'font_3x5_outline.png'))
json.dump(meta, open(os.path.join(out, 'font_3x5.json'), 'w'))
print(len(chars), 'glyphs')
