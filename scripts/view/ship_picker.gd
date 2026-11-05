class_name ShipPicker
extends RefCounted
## What the ship select page is showing: which hull, and which are open, and
## what its taps and swipes do. Kept out of main.gd, which is at the lint line
## limit; like ProfilePages it acts on Main only through Main's own methods.

const SWIPE := 20  ## native pixels across the hull that flip to the next one

var pick := 0  ## an index into ShipRoster.playable()
var profile: Profile  ## says which unlocks the player has earned; none without one


## The hull on show.
func picked() -> String:
	var ids := ShipRoster.playable()
	return ids[posmod(pick, ids.size())]


func is_open(id: String) -> bool:
	return ShipRoster.is_unlocked(id, _unlocked())


## Shows the next (1) or previous (-1) hull, wrapping round.
func step(dir: int) -> void:
	pick = posmod(pick + dir, ShipRoster.playable().size())


## The hull a run starts in: the one on show, or the first open one if that is locked.
func start_hull() -> String:
	return picked() if is_open(picked()) else ShipRoster.default_ship(_unlocked())


func _unlocked() -> Array[String]:
	return profile.unlocked if profile else ([] as Array[String])


func show(id: String) -> void:
	pick = maxi(0, ShipRoster.playable().find(id))


## A sideways drag that starts on the hull steps through hulls: returns the
## step (1 or -1), or 0 when the drag was a tap, a nudge or mostly vertical.
## A drag that starts on the fold does nothing: nothing there may respond.
## Positions are in native pixels.
static func swipe_step(preview: Rect2i, hinge: Rect2i, from: Vector2, to: Vector2) -> int:
	var d := to - from
	var at := Vector2i(from.floor())
	if not preview.has_point(at) or hinge.has_point(at):
		return 0
	if absf(d.x) < SWIPE or absf(d.x) <= 2.0 * absf(d.y):
		return 0
	return -1 if d.x > 0 else 1


## Opens ship select. From an end screen, the finished run goes and the page
## sits over the title.
static func open(main: Node) -> void:
	if main.menu == "":
		if main.run_over():
			main._clear_run()
		main.open_menu("title")
	main.open_menu("ship")


## A tap on one of the page's buttons, by kind.
static func press(main: Node, kind: String) -> void:
	var me: ShipPicker = main.ships
	match kind:
		"prev", "next":
			main.ui_cue("tap")
			me.step(-1 if kind == "prev" else 1)
		"launch":
			if not me.is_open(me.picked()):
				main.ui_cue("refused")  # the locked hull says how to open it
				return
			main.ui_cue("tap")
			if main.profile and main.profile.depth_open > 0:
				main.open_menu("depth")  # once a Hush Depth is open, pick one too
				return
			main.start_run()
		"back":
			main.ui_cue("tap")
			main.open_menu(main.menu_base)


## A sideways drag across the hull on ship select shows the next or last one.
## The arrows do the same; this is a shortcut. Positions are window pixels.
static func swipe(main: Node, from: Vector2, to: Vector2) -> bool:
	if main.menu != "ship" or main.menu_layout == null:
		return false
	var k := float(main.screen.scale)
	var l: MenuLayout = main.menu_layout
	var dir := swipe_step(l.preview_rect, l.hinge, from / k, to / k)
	if dir != 0:
		main.ui_cue("tap")
		main.ships.step(dir)
	return dir != 0
