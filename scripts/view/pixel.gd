class_name Pixel
extends RefCounted
## The Wickfarer master palette (same keys as the concept-art generators)
## and a helper that turns small text grids into textures.

const PAL := {
	"a": "#08081a",
	"b": "#121434",
	"c": "#1c1f4a",
	"d": "#2a2f63",
	"e": "#3d4580",
	"f": "#5a66a3",
	"g": "#8794c9",
	"h": "#c3cdee",
	"r": "#4a1424",
	"s": "#8a2a2c",
	"t": "#c94a2c",
	"u": "#f27a32",
	"v": "#ffb04a",
	"w": "#ffe08a",
	"x": "#fff8e0",
	"i": "#6aa6d8",
	"j": "#b4e2ff",
	"k": "#ffffff",
	"m": "#0b2e33",
	"n": "#1b6b67",
	"o": "#3fd1b9",
	"p": "#4a301e",
	"q": "#8a5a2a",
	"y": "#c99a4c",
	"z": "#ecd28a",
	"A": "#3a1d1d",
	"B": "#7a3f2f",
	"C": "#c27a54",
	"D": "#eab088",
	"E": "#13302f",
	"F": "#24574f",
	"G": "#3f8a72",
	"H": "#6fbf95",
	"I": "#2e1220",
	"J": "#5c2128",
	"K": "#8f3a33",
	"L": "#c0613f",
	"M": "#6f6880",
	"N": "#a9a1b3",
	"O": "#ddd5d3",
	"P": "#f7f1e6",
	"Q": "#241640",
	"R": "#47296e",
	"S": "#7449a6",
	"T": "#a985d6",
	"U": "#e8394a",
}

const FIRE: Array[String] = [
	"..u..\n.uvu.\n.uvu.\nuvwvu\nuvwwu\ntuwut\n.ttt.",
	".u...\n.uu..\n.uvu.\nuvvvu\nuvwwu\ntuwvt\n.ttt.",
	"...u.\n..uu.\n.uvu.\nuvvu.\nuvwwu\ntvwut\n.ttt.",
]

static var _cache: Dictionary = {}


static func c(key: String, alpha := 1.0) -> Color:
	var col := Color(PAL[key])
	col.a = alpha
	return col


static func grid(text: String) -> ImageTexture:
	if _cache.has(text):
		return _cache[text]
	var rows := text.strip_edges().split("\n")
	var w := 0
	for r in rows:
		w = maxi(w, r.strip_edges().length())
	var img := Image.create(w, rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var r := rows[y].strip_edges()
		for x in r.length():
			var k := r[x]
			if k != "." and PAL.has(k):
				img.set_pixel(x, y, Color(PAL[k]))
	var tex := ImageTexture.create_from_image(img)
	_cache[text] = tex
	return tex


## A tileable dither: density 2 = checkerboard, 4 = sparse.
static func dither(key: String, density: int) -> ImageTexture:
	var ck := "dither:%s:%d" % [key, density]
	if _cache.has(ck):
		return _cache[ck]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(PAL[key])
	for y in 64:
		for x in 64:
			var on := false
			if density == 2:
				on = (x + y) % 2 == 0
			else:
				on = x % 2 == 0 and y % 2 == 0 and ((y / 2 + x / 2) % 2 == 0)
			if on:
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_cache[ck] = tex
	return tex


## A HUD panel: dark fill, a lit top edge, and a bright outline when active.
## Shared by every view so buttons look the same on every screen.
static func panel(ci: CanvasItem, r: Rect2i, active: bool) -> void:
	ci.draw_rect(Rect2(r), c("b"))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), c("e"))
	ci.draw_rect(Rect2(r), c("v") if active else c("d"), false, 1.0)


## Corner brackets n pixels long, used for aim marks and selections.
static func corners(ci: CanvasItem, r: Rect2i, col: Color, n: int) -> void:
	var p := r.position
	var e := r.end - Vector2i.ONE
	for k in n:
		ci.draw_rect(Rect2(p.x + k, p.y, 1, 1), col)
		ci.draw_rect(Rect2(p.x, p.y + k, 1, 1), col)
		ci.draw_rect(Rect2(e.x - k, p.y, 1, 1), col)
		ci.draw_rect(Rect2(e.x, p.y + k, 1, 1), col)
		ci.draw_rect(Rect2(p.x + k, e.y, 1, 1), col)
		ci.draw_rect(Rect2(p.x, e.y - k, 1, 1), col)
		ci.draw_rect(Rect2(e.x - k, e.y, 1, 1), col)
		ci.draw_rect(Rect2(e.x, e.y - k, 1, 1), col)
