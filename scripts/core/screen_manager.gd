class_name ScreenManager
extends RefCounted
## Picks the pixel scale and layout for any screen, and is the only code
## that knows about phone shapes.
## - The pixel world is always drawn at a whole-number scale (no blur).
## - At 2400 x 1080 that is 5x, a 480 x 216 canvas.
## - Screens wider than 1.8:1 use the Wide layout; squarer screens
##   (an unfolded Fold or iPhone Duo) use Square, with a taller canvas
##   instead of a squashed one.

const BASE_SHORT := 216  ## canvas height on a regular phone
const MIN_LONG := 440  ## Wide: both ships fit side by side
const MIN_LONG_SQUARE := 400  ## Square: ships stack, so less width is needed and an unfolded Fold stays at 5x
const MIN_SHORT_SQUARE := 290  ## Square: room for two stacked ships and two button rows
const WIDE_RATIO := 1.8
const HINGE_HALF := 8  ## native pixels kept clear on each side of a fold


static func compute(window: Vector2i) -> Dictionary:
	var w := maxi(window.x, 1)
	var h := maxi(window.y, 1)
	var short := mini(w, h)
	var long := maxi(w, h)
	var ratio := float(w) / float(h)
	var layout := "wide" if ratio >= WIDE_RATIO else "square"
	var min_long := MIN_LONG if layout == "wide" else MIN_LONG_SQUARE
	var scale := mini(short / BASE_SHORT, long / min_long)
	if layout == "square":
		scale = mini(scale, short / MIN_SHORT_SQUARE)
	scale = maxi(1, scale)
	var native := Vector2i(int(ceil(float(w) / scale)), int(ceil(float(h) / scale)))
	# On a book-style foldable the fold runs down the middle when unfolded.
	var hinge := Rect2i()
	if layout == "square":
		hinge = Rect2i(native.x / 2 - HINGE_HALF, 0, HINGE_HALF * 2, native.y)
	return {"scale": scale, "native": native, "layout": layout, "hinge": hinge}
