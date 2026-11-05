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
im = Image.new('RGBA', (len(chars) * CELL, 5), (0, 0, 0, 0))
meta = {}
for n, ch in enumerate(chars):
    r = rows[ch]
    meta[ch] = [n, len(r[0])]
    for j in range(5):
        for i, v in enumerate(r[j]):
            if v == '#':
                im.putpixel((n * CELL + i, j), (255, 255, 255, 255))
out = sys.argv[2]
im.save(os.path.join(out, 'font_3x5.png'))
json.dump(meta, open(os.path.join(out, 'font_3x5.json'), 'w'))
print(len(chars), 'glyphs')
