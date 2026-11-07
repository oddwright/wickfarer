class_name ChartKey
extends RefCounted
## The star chart's icons and the key that names them. Every beacon shows what
## the player knows about it: where the ship is, the store, the Gate, the
## beacons already passed and the unknown ones. What waits at an unknown beacon
## stays hidden until the jump, as the run's stories expect.

const ROW := 9  ## one key row: a 7 pixel icon and a line of text
const ICON := 7
const GAP := 8  ## between key entries
const ENTRIES: Array[String] = ["you", "next", "unknown", "store", "gate", "been", "hush"]

## 7x7 grids; "k" pixels take the colour they are drawn in.
const GRIDS := {
	"you": ".......\nhh.....\n.hhh...\n.hvhhhh\n.hhh...\nhh.....\n.......",
	"unknown": "..kkk..\n.k...k.\n.....k.\n...kk..\n...k...\n.......\n...k...",
	"store": "kkkkkkk\nkk...kk\nk.k.k.k\nk..k..k\nk.k.k.k\nkk...kk\nkkkkkkk",
	"gate": "..kkk..\n.k...k.\nk.....k\nk.....k\nk.....k\nk.....k\nkk...kk",
	"been": ".......\n.......\n..kkk..\n..kkk..\n..kkk..\n.......\n.......",
}


## The icon key for a beacon: what the player knows of it.
static func icon_for(run: Run, n: Dictionary) -> String:
	if n.id == run.at:
		return "you"
	if n.kind in ["store", "gate"]:
		return str(n.kind)
	return "been" if run.visited.has(n.id) else "unknown"


static func color_for(run: Run, n: Dictionary, target: bool) -> Color:
	if run.is_swallowed(n.id):
		return Pixel.c("n")
	match str(n.kind):
		"store":
			return Pixel.c("y")
		"gate":
			return Pixel.c("w")
	if run.visited.has(n.id):
		return Pixel.c("e")
	return Pixel.c("h") if target else Pixel.c("f")


## Draws a key icon centred on c. "you" keeps its own colours.
static func draw_icon(ci: CanvasItem, key: String, c: Vector2i, col: Color) -> void:
	var at := Vector2(c - Vector2i(ICON, ICON) / 2)
	match key:
		"next":
			Pixel.corners(ci, Rect2i(Vector2i(at), Vector2i(ICON, ICON)), Pixel.c("v"), 2)
		"hush":
			ci.draw_texture_rect(Pixel.dither("n", 2), Rect2(at, Vector2(ICON, ICON)), true)
		"you":
			ci.draw_texture(Pixel.grid(GRIDS.you), at)
		_:
			ci.draw_texture(Pixel.grid(GRIDS[key]), at, col)


## The colour an icon wears in the key, matching the chart.
static func key_color(key: String) -> Color:
	match key:
		"store":
			return Pixel.c("y")
		"gate":
			return Pixel.c("w")
		"been":
			return Pixel.c("e")
	return Pixel.c("f")


## Lays the key out left to right in rows inside r, never across the fold.
## Returns [{key, at}] where at is the icon's top left, or [] if it can't fit.
static func flow(r: Rect2i, hinge: Rect2i) -> Array[Dictionary]:
	TextLayer.load_glyphs()
	var out: Array[Dictionary] = []
	var x := r.position.x
	var y := r.position.y
	for key in ENTRIES:
		var w := ICON + 3 + TextLayer.text_width(label(key).to_upper())
		var end := x + w
		var blocked := hinge.size.x > 0 and x < hinge.end.x + 2 and end > hinge.position.x - 2
		if blocked:
			x = hinge.end.x + 4  # jump the fold, then try the same row
			end = x + w
		if end > r.end.x:
			x = r.position.x
			y += ROW
			end = x + w
		if y + ROW > r.end.y or end > r.end.x:
			return []
		out.append({"key": key, "at": Vector2i(x, y)})
		x = end + GAP
	return out


## How many rows the key takes across a width, with the fold in the way.
static func rows(r: Rect2i, hinge: Rect2i) -> int:
	for n in range(1, ENTRIES.size() + 1):
		if not flow(Rect2i(r.position, Vector2i(r.size.x, n * ROW)), hinge).is_empty():
			return n
	return ENTRIES.size()


static func label(key: String) -> String:
	return TranslationServer.translate("UI_KEY_" + key.to_upper())
