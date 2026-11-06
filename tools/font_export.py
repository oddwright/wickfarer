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
# Letters with diagonals read as H or U at 3 pixels, so M, N, V and W get five columns
# (the diagonal needs three rows to show), and K gets arms that leave the stem.
WIDE = {
    'M': ["#...#", "##.##", "#.#.#", "#.#.#", "#...#"],
    'W': ["#...#", "#...#", "#.#.#", "#.#.#", ".#.#."],
    'N': ["#...#", "##..#", "#.#.#", "#..##", "#...#"],
    'V': ["#...#", "#...#", "#...#", ".#.#.", "..#.."],
    'K': ["#.#", "##.", "#..", "##.", "#.#"],
}
rows = {}
for k, g in F.items():
    rows[k] = [g[j * 3:(j + 1) * 3] for j in range(5)]
rows.update(WIDE)
chars = sorted(rows.keys())
CELL = 5
im = Image.new('RGBA', (len(chars) * CELL, 5), (0, 0, 0, 0))
meta = {}
for n, ch in enumerate(chars):
    r = rows[ch]
    meta[ch] = [n, len(r[0])]
    for j in range(5):
        for i, v in enumerate(r[j]):
            if v == '#':
                im.putpixel((n * CELL + i, j), (255, 255, 255, 255))
# The same glyphs grown by one pixel on every side, drawn in dark ink under the text so it
# stays readable over fire, stars and panels. Baked here so the game draws one extra quad per
# letter, as it did for the old drop shadow, instead of eight.
OCELL = CELL + 2
ol = Image.new('RGBA', (len(chars) * OCELL, 7), (0, 0, 0, 0))
for n, ch in enumerate(chars):
    r = rows[ch]
    for j in range(5):
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
