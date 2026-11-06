class_name CrewLayout
extends RefCounted
## Where the crew roster sits on the pixel canvas. The roster pauses the fight
## and lists each crew member (name, role, health and skills) with a button to
## change their post. Tapping that button opens a picker of stations.
## Wide: rows run down in columns, each with its post button beside it.
## Square: the rows sit on the left page and every button on the right page,
## so nothing interactive touches the fold.
## Tall: one column of rows with their post buttons, the picker under them and
## Close and Muster at the bottom, under the thumb.
## Pure data so tests can check every phone shape without a screen.

const ROW_W := 168
const ROW_H := 26
const POST_W := 40
const POST_H := 22
const PICK_W := 30
const PICK_H := 24
const BTN_W := 52
const BTN_H := 24
const TOP := 18  ## the title line

var kind: String
var native: Vector2i
var hinge: Rect2i
var rows: Array[Rect2i] = []  ## one per crew member, information only
var buttons: Array[Dictionary] = []  ## {kind, id, rect}: post, pick, muster, close
var title_rect: Rect2i  ## the roster's title line
var hint_rect: Rect2i  ## a line for the hint or the picker's question


## crew_count rows; picks lists the post choices (room ids, "" for none) and
## is empty when the picker is closed.
static func build(screen: Dictionary, crew_count: int, picks: Array[String] = []) -> CrewLayout:
	var l := CrewLayout.new()
	l.kind = screen.layout
	l.native = screen.native
	l.hinge = screen.hinge
	if l.kind == "tall":
		l._build_tall(crew_count, picks)
	elif l.kind == "wide":
		l._build_wide(crew_count, picks)
	else:
		l._build_square(crew_count, picks)
	return l


func _build_wide(crew_count: int, picks: Array[String]) -> void:
	var bottom := native.y - BTN_H - 6
	var per_col := maxi(1, (bottom - TOP - 4) / ROW_H)
	var cols := maxi(1, ceili(float(crew_count) / per_col))
	var row_w := mini(ROW_W, (native.x - 8) / cols - POST_W - 12)
	var col_w := row_w + 4 + POST_W + 8
	var x0 := maxi(4, (native.x - cols * col_w) / 2)
	for i in crew_count:
		var at := Vector2i(x0 + (i / per_col) * col_w, TOP + (i % per_col) * ROW_H)
		rows.append(Rect2i(at, Vector2i(row_w, ROW_H - 2)))
		var post := Rect2i(
			at + Vector2i(row_w + 4, (ROW_H - 2 - POST_H) / 2), Vector2i(POST_W, POST_H)
		)
		_add("post", i, post)
	_add("close", 0, Rect2i(4, bottom, BTN_W, BTN_H))
	_add("muster", 0, Rect2i(native.x - 4 - BTN_W, bottom, BTN_W, BTN_H))
	var x := 4 + BTN_W + 8
	for i in picks.size():
		_add("pick", i, Rect2i(x + i * (PICK_W + 4), bottom, PICK_W, PICK_H))
	hint_rect = Rect2i(4, 4, native.x - 8, 10)
	title_rect = hint_rect


func _build_tall(crew_count: int, picks: Array[String]) -> void:
	var bottom := native.y - BTN_H - 6
	var row_w := mini(ROW_W, native.x - 8 - 4 - POST_W)
	var post_x := 4 + row_w + 4
	for i in crew_count:
		var at := Vector2i(4, TOP + i * ROW_H)
		rows.append(Rect2i(at, Vector2i(row_w, ROW_H - 2)))
		_add("post", i, Rect2i(post_x, at.y + (ROW_H - 2 - POST_H) / 2, POST_W, POST_H))
	var per_line := maxi(1, (native.x - 4) / (PICK_W + 4))
	var py := TOP + maxi(1, crew_count) * ROW_H + 4
	for i in picks.size():
		var at := Vector2i(4 + (i % per_line) * (PICK_W + 4), py + (i / per_line) * (PICK_H + 4))
		_add("pick", i, Rect2i(at, Vector2i(PICK_W, PICK_H)))
	_add("close", 0, Rect2i(4, bottom, BTN_W, BTN_H))
	_add("muster", 0, Rect2i(native.x - 4 - BTN_W, bottom, BTN_W, BTN_H))
	# Too narrow to share the title's line: the hint sits over Close and Muster.
	title_rect = Rect2i(4, 4, native.x - 8, 10)
	hint_rect = Rect2i(4, bottom - 14, native.x - 8, 10)


func _build_square(crew_count: int, picks: Array[String]) -> void:
	var left_w := hinge.position.x - 8
	var right := hinge.end.x + 4
	var right_w := native.x - 4 - right
	for i in crew_count:
		var at := Vector2i(4, TOP + i * ROW_H)
		rows.append(Rect2i(at, Vector2i(mini(ROW_W, left_w), ROW_H - 2)))
		_add("post", i, Rect2i(right, at.y + (ROW_H - 2 - POST_H) / 2, POST_W, POST_H))
	# The picker sits beside the post buttons, wrapping onto more lines as needed.
	var px := right + POST_W + 8
	var per_line := maxi(1, (native.x - 4 - px + 4) / (PICK_W + 4))
	for i in picks.size():
		var at := Vector2i(px + (i % per_line) * (PICK_W + 4), TOP + (i / per_line) * (PICK_H + 4))
		_add("pick", i, Rect2i(at, Vector2i(PICK_W, PICK_H)))
	var pick_lines := ceili(float(picks.size()) / per_line)
	var below := TOP + maxi(maxi(1, crew_count) * ROW_H, pick_lines * (PICK_H + 4)) + 6
	_add("close", 0, Rect2i(right, below, BTN_W, BTN_H))
	_add("muster", 0, Rect2i(right + BTN_W + 4, below, BTN_W, BTN_H))
	# Title on the left page, hint on the right, so neither runs into the other.
	hint_rect = Rect2i(right, 4, right_w, 10)
	title_rect = Rect2i(4, 4, left_w, 10)


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
	for r in rows:
		if not canvas.encloses(r):
			out.append("a crew row is outside the canvas %s" % r)
		if hinge.size.x > 0 and r.intersects(hinge):
			out.append("a crew row sits on the fold")
	for b in buttons:
		var r: Rect2i = b.rect
		if not canvas.encloses(r):
			out.append("%s %s button outside the canvas %s" % [b.kind, b.id, r])
		if r.size.x < 10 or r.size.y < 10:
			out.append("%s button is too small to tap" % b.kind)
		if hinge.size.x > 0 and r.intersects(hinge):
			out.append("%s button sits on the fold" % b.kind)
		for row in rows:
			if r.intersects(row):
				out.append("%s button covers a crew row" % b.kind)
		for o in buttons:
			if o != b and r.intersects(o.rect):
				out.append("%s and %s buttons overlap" % [b.kind, o.kind])
	return out
