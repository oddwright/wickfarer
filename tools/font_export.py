"""Export the 3x5 pixel font from the concept art (pixel-src/font.py) as a glyph strip
(font_3x5.png + .json) and a matching outline strip (font_3x5_outline.png), and the finer
4x6 text font drawn here (font_4x6.png + .json + _outline.png) the same way.
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
# The 4x6 face game text uses on screens at 2x and up: the 3x5 letters' footprint, a step finer
# (four screen pixels per font pixel at 5x and 6x), so text reads more easily but stays pixel text.
SMALL = {
    'A': ".##. #..# #..# #### #..# #..#", 'B': "###. #..# ###. #..# #..# ###.",
    'C': ".### #... #... #... #... .###", 'D': "###. #..# #..# #..# #..# ###.",
    'E': "#### #... ###. #... #... ####", 'F': "#### #... ###. #... #... #...",
    'G': ".### #... #.## #..# #..# .###", 'H': "#..# #..# #### #..# #..# #..#",
    'I': "### .#. .#. .#. .#. ###", 'J': "..## ...# ...# ...# #..# .##.",
    'K': "#..# #.#. ##.. #.#. #..# #..#", 'L': "#... #... #... #... #... ####",
    'M': "#...# ##.## #.#.# #...# #...# #...#", 'N': "#..# ##.# #.## #..# #..# #..#",
    'O': ".##. #..# #..# #..# #..# .##.", 'P': "###. #..# #..# ###. #... #...",
    'Q': ".##. #..# #..# #..# #.#. .#.#", 'R': "###. #..# #..# ###. #.#. #..#",
    'S': ".### #... .##. ...# ...# ###.", 'T': "### .#. .#. .#. .#. .#.",
    'U': "#..# #..# #..# #..# #..# .##.", 'V': "#..# #..# #..# #..# .##. .##.",
    'W': "#...# #...# #.#.# #.#.# ##.## #...#", 'X': "#..# #..# .##. .##. #..# #..#",
    'Y': "#.# #.# #.# .#. .#. .#.", 'Z': "#### ...# ..#. .#.. #... ####",
    '0': ".##. #..# #.## ##.# #..# .##.", '1': ".#. ##. .#. .#. .#. ###",
    '2': ".##. #..# ..#. .#.. #... ####", '3': "###. ...# .##. ...# ...# ###.",
    '4': "#..# #..# #### ...# ...# ...#", '5': "#### #... ###. ...# ...# ###.",
    '6': ".##. #... ###. #..# #..# .##.", '7': "#### ...# ..#. .#.. .#.. .#..",
    '8': ".##. #..# .##. #..# #..# .##.", '9': ".##. #..# #..# .### ...# .##.",
    '!': "# # # # . #", '%': "#..# ...# ..#. .#.. #... #..#", "'": "# # . . . .",
    '(': ".# #. #. #. #. .#", ')': "#. .# .# .# .# #.", '+': "... .#. ### .#. ... ...",
    ',': ".. .. .. .. .# #.", '-': "... ... ### ... ... ...", '.': ". . . . . #",
    '/': "...# ..#. ..#. .#.. .#.. #...", ':': ". # . . # .", '<': "..# .#. #.. .#. ..# ...",
    '>': "#.. .#. ..# .#. #.. ...", '=': "... ### ... ### ... ...",
    '?': "###. ...# .##. .#.. .... .#..", 'x': ".... .... #..# .##. .##. #..#",
}


def export(rows, cell, h, name, out):
    """A glyph strip, its index and an outline strip: the glyphs grown by one pixel on every
    side, drawn in dark ink under the text so it stays readable over fire, stars and panels.
    Baked here so the game draws one extra quad per letter instead of eight."""
    chars = sorted(rows.keys())
    im = Image.new('RGBA', (len(chars) * cell, h), (0, 0, 0, 0))
    ocell = cell + 2
    ol = Image.new('RGBA', (len(chars) * ocell, h + 2), (0, 0, 0, 0))
    meta = {}
    for n, ch in enumerate(chars):
        r = rows[ch]
        assert len(r) == h and all(len(row) == len(r[0]) <= cell for row in r), ch
        meta[ch] = [n, len(r[0])]
        for j in range(h):
            for i, v in enumerate(r[j]):
                if v == '#':
                    im.putpixel((n * cell + i, j), (255, 255, 255, 255))
                    for dx in (0, 1, 2):
                        for dy in (0, 1, 2):
                            ol.putpixel((n * ocell + i + dx, j + dy), (255, 255, 255, 255))
    im.save(os.path.join(out, name + '.png'))
    ol.save(os.path.join(out, name + '_outline.png'))
    json.dump(meta, open(os.path.join(out, name + '.json'), 'w'))
    print(name, len(chars), 'glyphs')


out = sys.argv[2]
export(rows, 5, 5, 'font_3x5', out)
export({k: v.split(' ') for k, v in SMALL.items()}, 5, 6, 'font_4x6', out)
