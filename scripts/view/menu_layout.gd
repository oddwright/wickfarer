class_name MenuLayout
extends RefCounted
## Where things sit on the menu screens: the title menu, the pause menu, the
## options screen and the yes/no confirm screen. Pure data so tests can check
## every phone shape without a screen, like HudLayout and RunLayout.
## In the Square layout the title or question sits on the left page and the
## buttons on the right, so nothing you tap sits on the fold.

const BTN_W := 120
const BTN_H := 20
const GAP := 6
const TITLE_H := 30  ## room for a 2x title line and its gap
## Pages with text above their buttons, and the height it gets (0 = all there is).
const TEXT_PAGES := {"depth": 56, "log": 0}
const TOP := 26  ## first options row, under the title
const ROW := 24  ## options row pitch
const CTRL_H := 16  ## options control height
const STEP_W := 18  ## the - and + buttons
const LABEL_W := 58  ## options label column
const FOOT_W := 80  ## Defaults and Back
const LAUNCH_W := 100
const ARROW_W := 20
const PREVIEW := Vector2i(240, 80)  ## room for the largest playable hull frame
const SHIP_BAND_TOP := 18
const SHIP_GROUP_MAX := 600  ## arrows, hull and words stay together on a big canvas
const SHIP_SQUARE_H := 204  ## name, hull, then the button column
const MARGIN := 8
const COL_GAP := 12  ## between the two options columns in Wide
## The two options columns, top to bottom. Volumes are GameSettings bus names.
const AUDIO_ROWS: Array[String] = ["Master", "Music", "SFX", "UI"]
const FEEL_ROWS: Array[String] = ["haptics", "shake", "hitstop", "reduce_flashing", "ui_size"]
const TOGGLES: Array[String] = ["hitstop", "reduce_flashing"]
## Rows that step through a few named values, written between - and +, not a bar.
const STEPPERS: Array[String] = ["ui_size"]

var kind: String
var native: Vector2i
var hinge: Rect2i
var title_rect: Rect2i  ## the title or question text
var buttons: Array[Dictionary] = []  ## {kind, id, rect}
## options only: {id, label_at, bar, value}; bar is a level's slider (empty for toggles
## and steppers), value is where a stepper writes its value.
var rows: Array[Dictionary] = []
## ship select only: the hull on show, its blurb and stats, and the page dots.
var preview_rect: Rect2i
var info_rect: Rect2i
var pips_rect: Rect2i


## The menu button on the fight and run screens: top right, in the status bar,
## clear of the fold and of both ships in every layout.
static func menu_button(native_size: Vector2i) -> Rect2i:
	return Rect2i(native_size.x - 30, 1, 26, 14)


## mode is "title", "pause", "confirm", "options" or "ship". ids are the list
## buttons' ids in order (for "options" and "ship" they are ignored).
static func build(screen: Dictionary, mode: String, ids: Array[String] = []) -> MenuLayout:
	var l := MenuLayout.new()
	l.kind = screen.layout
	l.native = screen.native
	l.hinge = screen.hinge
	if mode == "options":
		l._options()
	elif mode == "ship":
		l._ship()
	else:
		l._list(ids, TEXT_PAGES.get(mode, TITLE_H))
	return l


## A title over a centred column (Wide), or title left and column right (Square).
func _list(ids: Array[String], title_h := TITLE_H) -> void:
	var n := maxi(ids.size(), 1)
	var col_h := n * (BTN_H + GAP) - GAP
	var w := native.x
	var h := native.y
	if title_h <= 0:
		title_h = h - col_h - MARGIN * 2 if hinge.size.x == 0 else h - MARGIN * 2
	title_h = mini(title_h, h - MARGIN * 2)
	var bx: int
	var by: int
	if hinge.size.x == 0:
		var top := maxi(MARGIN, (h - title_h - col_h) / 2)
		title_rect = Rect2i(MARGIN, top, w - MARGIN * 2, title_h - 8)
		bx = (w - BTN_W) / 2
		by = top + title_h
	else:
		var left_w := hinge.position.x - MARGIN * 2
		title_rect = Rect2i(MARGIN, (h - title_h) / 2, left_w, title_h)
		var right_x := hinge.end.x + MARGIN
		bx = right_x + (w - MARGIN - right_x - BTN_W) / 2
		by = (h - col_h) / 2
	var rows := ids.size()
	var two_wide := BTN_W * 2 + GAP
	if hinge.size.x == 0 and by + col_h > h - MARGIN and two_wide <= w - MARGIN * 2:
		# A short Wide canvas (the Fold cover at a large scale): two columns,
		# with the title moved down to sit over them.
		rows = ceili(ids.size() / 2.0)
		var top := maxi(MARGIN, (h - title_h - (rows * (BTN_H + GAP) - GAP)) / 2)
		title_rect.position.y = top
		bx = (w - two_wide) / 2
		by = top + title_h
	for i in ids.size():
		var x := bx + (i / rows) * (BTN_W + GAP)
		_add("item", ids[i], Rect2i(x, by + (i % rows) * (BTN_H + GAP), BTN_W, BTN_H))


## Two columns of rows: sound on the left, feel on the right (each on its own
## page in Square), then Defaults and Back along the bottom.
func _options() -> void:
	var w := native.x
	var lx := MARGIN
	var lw: int
	var rx: int
	var rw: int
	if hinge.size.x == 0:
		lw = (w - MARGIN * 2 - COL_GAP) / 2
		rx = lx + lw + COL_GAP
		rw = w - MARGIN - rx
	else:
		lw = hinge.position.x - 4 - lx
		rx = hinge.end.x + 4
		rw = w - MARGIN - rx
	title_rect = Rect2i(lx, 6, w - MARGIN * 2, 10)
	for i in AUDIO_ROWS.size():
		_row(AUDIO_ROWS[i], lx, lw, TOP + i * ROW)
	for i in FEEL_ROWS.size():
		_row(FEEL_ROWS[i], rx, rw, TOP + i * ROW)
	var deepest := maxi(AUDIO_ROWS.size(), FEEL_ROWS.size())
	var foot_y := maxi(TOP + deepest * ROW + 4, native.y - BTN_H - MARGIN)
	_add("defaults", 0, Rect2i(lx, foot_y, FOOT_W, BTN_H))
	_add("back", 0, Rect2i(rx + rw - FOOT_W, foot_y, FOOT_W, BTN_H))


## Ship select. Wide: arrows either side of the hull, its blurb and stats to
## the right, Back and Launch in the thumb corners. Square: the hull spans the
## fold (it is only a picture), the words sit on the left page and every
## button on the right.
func _ship() -> void:
	if hinge.size.x == 0:
		_ship_wide()
	else:
		_ship_square()


func _ship_wide() -> void:
	var w := native.x
	var fy := native.y - BTN_H - MARGIN
	var group_w := mini(w - MARGIN * 2, SHIP_GROUP_MAX)
	var ox := (w - group_w) / 2
	var cy := (SHIP_BAND_TOP + fy - 4) / 2
	var py := cy - PREVIEW.y / 2
	title_rect = Rect2i(ox + ARROW_W + 2, py - 18, PREVIEW.x, 12)
	preview_rect = Rect2i(Vector2i(ox + ARROW_W + 2, py), PREVIEW)
	var info_x := preview_rect.end.x + ARROW_W + 10
	info_rect = Rect2i(info_x, py, ox + group_w - info_x, fy - 4 - py)
	_add("prev", 0, Rect2i(ox, cy - 15, ARROW_W, 30))
	_add("next", 0, Rect2i(preview_rect.end.x + 2, cy - 15, ARROW_W, 30))
	_add("back", 0, Rect2i(MARGIN, fy, FOOT_W, BTN_H))
	_add("launch", 0, Rect2i(w - MARGIN - LAUNCH_W, fy, LAUNCH_W, BTN_H))
	pips_rect = Rect2i(MARGIN + FOOT_W + 4, fy, w - MARGIN * 2 - FOOT_W - LAUNCH_W - 8, BTN_H)


func _ship_square() -> void:
	var w := native.x
	var top := maxi(MARGIN, (native.y - SHIP_SQUARE_H) / 2)
	var left_w := hinge.position.x - MARGIN * 2
	title_rect = Rect2i(MARGIN, top, left_w, 12)
	preview_rect = Rect2i(Vector2i((w - PREVIEW.x) / 2, top + 18), PREVIEW)
	var y0 := preview_rect.end.y + 8
	info_rect = Rect2i(MARGIN, y0, left_w, native.y - MARGIN - y0)
	var rx := hinge.end.x + MARGIN
	var rw := w - MARGIN - rx
	var bx := rx + (rw - BTN_W) / 2
	_add("prev", 0, Rect2i(rx, y0, 36, BTN_H))
	_add("next", 0, Rect2i(w - MARGIN - 36, y0, 36, BTN_H))
	_add("launch", 0, Rect2i(bx, y0 + 34, BTN_W, BTN_H))
	_add("back", 0, Rect2i(bx, y0 + 60, BTN_W, BTN_H))
	pips_rect = Rect2i(rx + 40, y0, rw - 80, BTN_H)


func _row(id: String, x: int, width: int, y: int) -> void:
	var ctrl_x := x + LABEL_W
	var ctrl_w := width - LABEL_W
	var row := {
		"id": id, "label_at": Vector2i(x, y + CTRL_H / 2 + 3), "bar": Rect2i(), "value": Rect2i()
	}
	if id in TOGGLES:
		_add("toggle", id, Rect2i(ctrl_x, y, ctrl_w, CTRL_H))
	else:
		var minus := Rect2i(ctrl_x, y, STEP_W, CTRL_H)
		var plus := Rect2i(x + width - STEP_W, y, STEP_W, CTRL_H)
		_add("less", id, minus)
		_add("more", id, plus)
		var between := Rect2i(minus.end.x + 4, y, plus.position.x - minus.end.x - 8, CTRL_H)
		if id in STEPPERS:
			row.value = between
		else:
			row.bar = Rect2i(between.position.x, y + 5, between.size.x, CTRL_H - 10)
	rows.append(row)


func _add(kind_name: String, id: Variant, rect: Rect2i) -> void:
	buttons.append({"kind": kind_name, "id": id, "rect": rect})


func button_at(p: Vector2i) -> Dictionary:
	for b in buttons:
		if (b.rect as Rect2i).grow(2).has_point(p):
			return b
	return {}


func button(kind_name: String, id: Variant = 0) -> Dictionary:
	for b in buttons:
		if b.kind == kind_name and b.id == id:
			return b
	return {}


## Problems with this layout; empty means it is fine. Used by tests.
func problems() -> Array[String]:
	var out: Array[String] = []
	var canvas := Rect2i(Vector2i.ZERO, native)
	for b in buttons:
		var r: Rect2i = b.rect
		var name := "%s %s" % [b.kind, b.id]
		if not canvas.encloses(r):
			out.append("%s outside the canvas" % name)
		if hinge.size.x > 0 and r.intersects(hinge):
			out.append("%s sits on the fold" % name)
		if r.size.y < 10 or r.size.x < 10:
			out.append("%s is smaller than a fingertip" % name)
		if r.intersects(title_rect):
			out.append("%s covers the title" % name)
		for o in buttons:
			if o != b and r.grow(1).intersects(o.rect):
				out.append("%s and %s %s overlap" % [name, o.kind, o.id])
	if preview_rect.has_area():
		if not canvas.encloses(preview_rect) or not canvas.encloses(info_rect):
			out.append("the ship preview or its words leave the canvas")
		for b in buttons:
			if (b.rect as Rect2i).intersects(preview_rect):
				out.append("%s covers the ship" % b.kind)
			if (b.rect as Rect2i).intersects(info_rect):
				out.append("%s covers the ship's words" % b.kind)
		if hinge.size.x > 0 and info_rect.intersects(hinge):
			out.append("the ship's words sit on the fold")
	for row in rows:
		var bar: Rect2i = row.bar
		if bar.size.x != 0 and bar.size.x < 20:
			out.append("%s slider is too short to read" % row.id)
		var value: Rect2i = row.value
		if row.id in STEPPERS and value.size.x < 28:
			out.append("%s has no room for its value" % row.id)
		if hinge.size.x > 0 and bar.intersects(hinge):
			out.append("%s slider sits on the fold" % row.id)
	return out
