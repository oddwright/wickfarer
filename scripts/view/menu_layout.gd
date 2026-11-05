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
const TOP := 26  ## first options row, under the title
const ROW := 24  ## options row pitch
const CTRL_H := 16  ## options control height
const STEP_W := 18  ## the - and + buttons
const LABEL_W := 58  ## options label column
const FOOT_W := 80  ## Defaults and Back
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


## The menu button on the fight and run screens: top right, in the status bar,
## clear of the fold and of both ships in every layout.
static func menu_button(native_size: Vector2i) -> Rect2i:
	return Rect2i(native_size.x - 30, 1, 26, 14)


## mode is "title", "pause", "confirm" or "options". ids are the list buttons'
## ids in order (for "options" they are ignored).
static func build(screen: Dictionary, mode: String, ids: Array[String] = []) -> MenuLayout:
	var l := MenuLayout.new()
	l.kind = screen.layout
	l.native = screen.native
	l.hinge = screen.hinge
	if mode == "options":
		l._options()
	else:
		l._list(ids)
	return l


## A title over a centred column (Wide), or title left and column right (Square).
func _list(ids: Array[String]) -> void:
	var n := maxi(ids.size(), 1)
	var col_h := n * (BTN_H + GAP) - GAP
	var w := native.x
	var h := native.y
	var bx: int
	var by: int
	if hinge.size.x == 0:
		var top := maxi(MARGIN, (h - TITLE_H - col_h) / 2)
		title_rect = Rect2i(MARGIN, top, w - MARGIN * 2, TITLE_H - 8)
		bx = (w - BTN_W) / 2
		by = top + TITLE_H
	else:
		var left_w := hinge.position.x - MARGIN * 2
		title_rect = Rect2i(MARGIN, (h - TITLE_H) / 2, left_w, TITLE_H)
		var right_x := hinge.end.x + MARGIN
		bx = right_x + (w - MARGIN - right_x - BTN_W) / 2
		by = (h - col_h) / 2
	for i in ids.size():
		_add("item", ids[i], Rect2i(bx, by + i * (BTN_H + GAP), BTN_W, BTN_H))


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
