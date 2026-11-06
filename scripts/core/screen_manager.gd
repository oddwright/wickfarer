class_name ScreenManager
extends RefCounted
## Picks the pixel scale and layout for any screen, and is the only code
## that knows about phone shapes.
## - The pixel world is always drawn at a whole-number scale (no blur).
## - Auto picks the biggest scale whose canvas still fits the layout: 5x on a
##   2400 x 1080 phone and on an unfolded Fold, 6x on a Fold's 2520 x 1080
##   cover screen, whose pixels are physically smaller.
## - The UI size setting moves that up or down a step; larger never goes past
##   the tightest canvas the layout is checked at.
## - Screens wider than 1.8:1 use the Wide layout; squarer screens
##   (an unfolded Fold or iPhone Duo) use Square, with a taller canvas
##   instead of a squashed one. A phone held upright (narrower than 3:4) uses
##   Tall: the ships stack and every button sits low, in reach of a thumb.

## Wide: both hulls side by side (their frames may overlap at the empty edges)
## between the status bar and one row of buttons.
const MIN_LONG := 420
const MIN_SHORT := 180
## Square: ships stack, so less width is needed and an unfolded Fold stays at 5x.
const MIN_LONG_SQUARE := 400
const MIN_SHORT_SQUARE := 290  ## Square: room for two stacked ships and two button rows
## Square at a larger UI size: the narrowest canvas (across, not the long side,
## since a portrait Fold is too narrow for the button rows) the stacked layout still fits.
const TIGHT_WIDTH_SQUARE := 360
const WIDE_RATIO := 1.8
## Tall: a phone held upright. 216 across keeps a 1080-wide phone at 5x, as it is
## held sideways; the widest hulls then lose their engine glow past the left edge.
const MIN_TALL_W := 216
const MIN_TALL_H := 400  ## two stacked ships, their status lines and three button rows
const TALL_RATIO := 0.75
## How far a hull's drawn pixels may run past the side of a Tall canvas: the engine
## glow of the widest hulls (the nozzle itself stays on screen).
const TALL_BLEED := 12
const HINGE_HALF := 8  ## native pixels kept clear on each side of a fold


## size_step is the player's UI size setting: 0 is auto, -1 one scale smaller, +1 larger.
static func compute(window: Vector2i, size_step := 0) -> Dictionary:
	var w := maxi(window.x, 1)
	var h := maxi(window.y, 1)
	var ratio := float(w) / float(h)
	var layout := "wide" if ratio >= WIDE_RATIO else "square"
	if ratio <= TALL_RATIO:
		layout = "tall"
	var auto_scale := fit(window, layout, false)
	var scale := auto_scale + size_step
	if size_step > 0:
		scale = maxi(auto_scale, mini(scale, fit(window, layout, true)))
	scale = maxi(1, scale)
	var native := Vector2i(int(ceil(float(w) / scale)), int(ceil(float(h) / scale)))
	# On a book-style foldable the fold runs down the middle when unfolded.
	var hinge := Rect2i()
	if layout == "square":
		hinge = Rect2i(native.x / 2 - HINGE_HALF, 0, HINGE_HALF * 2, native.y)
	return {
		"scale": scale, "auto_scale": auto_scale, "native": native, "layout": layout, "hinge": hinge
	}


## The biggest whole-number scale whose canvas fits the layout; tight allows
## the smallest canvas the layout is checked at instead of the comfortable one.
static func fit(window: Vector2i, layout: String, tight: bool) -> int:
	var short := maxi(mini(window.x, window.y), 1)
	var long := maxi(maxi(window.x, window.y), 1)
	if layout == "wide":
		return maxi(1, mini(short / MIN_SHORT, long / MIN_LONG))
	if layout == "tall":
		# No tighter fit: a scale up would push the hulls well off the sides.
		return maxi(1, mini(window.x / MIN_TALL_W, window.y / MIN_TALL_H))
	if tight:
		return maxi(1, mini(window.x / TIGHT_WIDTH_SQUARE, window.y / MIN_SHORT_SQUARE))
	# Held upright, the canvas must still be wide enough for the two button clusters.
	var across := window.x / TIGHT_WIDTH_SQUARE
	return maxi(1, mini(mini(short / MIN_SHORT_SQUARE, long / MIN_LONG_SQUARE), across))


## Why a fight pauses when the layout changes under it. Only Wide and Tall swap by
## turning the phone; Square comes and goes with a fold (a Fold's inner screen).
static func change_reason(before: String, after: String) -> String:
	var turned := before != after and before in ["wide", "tall"] and after in ["wide", "tall"]
	return "UI_TURN_PAUSE" if turned else "UI_FOLD_PAUSE"


## Lets the phone turn the game upright, or holds it sideways when the player asks.
## Only phones and tablets turn; on a desktop this does nothing.
static func orient(force_landscape: bool) -> void:
	var want := (
		DisplayServer.SCREEN_SENSOR_LANDSCAPE if force_landscape else DisplayServer.SCREEN_SENSOR
	)
	if DisplayServer.screen_get_orientation() != want:
		DisplayServer.screen_set_orientation(want)
