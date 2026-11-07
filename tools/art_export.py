"""Export Phase 0 placeholder sprites from the concept-art generators.

Usage: python3 tools/art_export.py /mnt/project-files/concept-art/pixel-src art/

Ships are rendered without crew, fires or baked room states, because the game
draws those live. Crew are exported as sheets of 17x14 cells:
frames 0-1 idle, frames 2-5 walk. Every crew species also gets an Ashmarket
("raider") colour variant for enemy crews.
"""
import sys, os, json, types
SRC = sys.argv[1]
OUT = sys.argv[2]
sys.path.insert(0, SRC)
from PIL import Image
from canvas import Cv, clean_orphans
import ships, wren, cutter, minis, brine, saint, hush

os.makedirs(OUT, exist_ok=True)

def blank(*a, **k):
    return Cv(1, 1)

dummy = types.SimpleNamespace(drifter=blank, kith=blank, lumen=blank, sable_m=blank, RAIDER_MAP={})
real_room = ships.room

def plain_room(c, x0, y0, x1, y1, state='plain', *a, **k):
    if state != 'core':
        state = 'plain'
    return real_room(c, x0, y0, x1, y1, state, *a, **k)

for mod in (wren, cutter, brine, saint):
    mod.minis = dummy
    mod.room = plain_room
cutter.FIRE = ['.', '.', '.']

def sheet(frames):
    w, h = frames[0].w, frames[0].h
    im = Image.new('RGBA', (w * len(frames), h), (0, 0, 0, 0))
    for i, c in enumerate(frames):
        im.paste(c.img(), (i * w, 0))
    return im

def ship_frame_wren(f):
    c = wren.wren(f, breach=False)
    clean_orphans(c)
    return c

sheet([ship_frame_wren(f) for f in range(4)]).save(os.path.join(OUT, 'ship_tallow_wren.png'))
sheet([cutter.cutter(f) for f in range(4)]).save(os.path.join(OUT, 'ship_ashmarket_cutter.png'))
sheet([brine.brine(f) for f in range(4)]).save(os.path.join(OUT, 'ship_brine_cathedral.png'))
sheet([saint.saint(f) for f in range(4)]).save(os.path.join(OUT, 'ship_porcelain_saint.png'))
sheet([hush.maw(f) for f in range(4)]).save(os.path.join(OUT, 'ship_hush_maw.png'))

ORU = """
..aaaaa..
.aSSSSSa.
aSTTSSSRa
aShaShaRa
aSSSSSSRa
.aRSSSRa.
aSSRRRSSa
aSRSSSRSa
aRRSSSRRa
.aRRRRRa.
..aQaQa..
..aa.aa..
"""

def oru(f=0):
    c = Cv(9, 13)
    c.blit(ORU, 0, 1 + (f % 2))
    if f % 2:
        c.hl(0, 8, 12, None)
        c.blit("..aQaQa..\n..aa.aa..", 0, 11)
    return c

CELL_W, CELL_H = 17, 14

def pad(c):
    o = Cv(CELL_W, CELL_H)
    o.paste(c, (CELL_W - c.w) // 2, CELL_H - c.h)
    return o

def remap_cv(c, m):
    o = Cv(c.w, c.h)
    for y in range(c.h):
        for x in range(c.w):
            v = c.p[y][x]
            if v is not None:
                o.p[y][x] = m.get(v, v)
    return o

species = {
    'drifter': [minis.drifter(0), minis.drifter(1)] + [minis.drifter(i, walk=True) for i in range(4)],
    'kith': [minis.kith(0), minis.kith(1)] + [minis.kith(i) for i in range(4)],
    'oru': [oru(0), oru(1), oru(0), oru(1), oru(0), oru(1)],
    'sable': [minis.sable_m(0), minis.sable_m(1)] * 3,
}
RAIDER = dict(minis.RAIDER_MAP)
RAIDER.update({'S': 'K', 'T': 'L', 'R': 'J', 'O': 'L', 'N': 'K', 'M': 'J', 'P': 'z'})
for name, frames in species.items():
    sheet([pad(f) for f in frames]).save(os.path.join(OUT, f'crew_{name}.png'))
    sheet([pad(remap_cv(f, RAIDER)) for f in frames]).save(os.path.join(OUT, f'crew_{name}_raider.png'))

ICONS = {
    'ember': """
....w....
...wvw...
..wvxvw..
.wvxxxvw.
wvxxkxxvw
.wvxxxvw.
..wvxvw..
...wvw...
....w....
""",
    'helm': """
...aaa...
.aayzyaa.
.ay.q.ya.
azqaaaqza
azaqzqaza
azqaaaqza
.ay.q.ya.
.aayzyaa.
...aaa...
""",
    'wards': """
aaaaaaaaa
ajjjjjjia
ajkjjjjia
ajjjjjjia
ajjjjjiia
.ajjjjia.
.aijjiia.
..aiiia..
...aaa...
""",
    'weapons': """
.........
..aaa....
.azzya...
.ayyyqaaa
.ayyyqzza
.ayyyqaaa
.aqqqa...
..aaa....
.........
""",
    'engines': """
aaa..aaa.
avua.avua
.avua.avu
..avua.av
..avua.av
.avua.avu
avua.avua
aaa..aaa.
.........
""",
    'mend': """
...aaa...
...aHa...
...aHa...
aaaaHaaaa
aHHHHHHHa
aaaaHaaaa
...aHa...
...aHa...
...aaa...
""",
}
icons = Cv(9 * len(ICONS), 9)
for i, (k, g) in enumerate(ICONS.items()):
    icons.blit(g, i * 9, 0)
icons.img().save(os.path.join(OUT, 'icons.png'))
json.dump(list(ICONS.keys()), open(os.path.join(OUT, 'icons.json'), 'w'))
print('exported to', OUT)
