class_name RunLayout
extends RefCounted
## Where things sit on the run screens (star chart, event, store, endings),
## for the Wide, Square and Tall layouts. Pure data so tests can check every phone
## shape without a screen, like HudLayout.
## In the Square layout the text goes on the left page and buttons on the
## right, so nothing you tap sits on the fold. In Tall (a phone held upright) the
## text is on top and the buttons stack at the bottom, under the thumb, and the
## chart runs from the bottom up to the Gate.

const BEACON := 12  ## beacon hit box; the tap area grows it by 2 on each side
const TOP := 20  ## below the status bar
const TOP_TALL := 28  ## Tall: the status bar takes two lines, the Reach's name on the second
const BOTTOM := 26  ## room for a message line under the chart
const CHOICE_H := 20
const CHOICE_H_SQUARE := 30  ## the right page is narrow, so labels may take two lines
const CHOICE_GAP := 4
const NEXT_W := 90
const WIDE_ROWS := 3  ## buttons a Wide page stacks before it splits into columns
const WIDE_COLS := 3  ## at most; nine buttons is the most a Wide page holds

var kind: String
var native: Vector2i
var hinge: Rect2i
var top := TOP  ## below the status bar
var chart_rect: Rect2i  ## the area beacons are spread over
var text_rect: Rect2i  ## the story or store text
var message_rect: Rect2i  ## a one or two line note at the bottom
var buttons: Array[Dictionary] = []  ## {kind, id, rect}
## Opens the pause menu; it sits in the status bar, so it is kept out of buttons.
var menu_rect: Rect2i
## The chart's key, above the message line: [{key, at}] (see ChartKey.flow).
var key: Array[Dictionary] = []
var key_rect: Rect2i
## Where each beacon sits across its column (its height; left to right in Tall), by
## node id, nudged so a column's beacons never touch on a short canvas.
var _beacon_across: Dictionary = {}


## mode is "chart", "event", "next" (one Continue button), or a store page
## ("store", "refit", "wares", "modules", "guns"), whose buttons take its name.
static func build(
	screen: Dictionary, chart: StarChart, mode: String, choice_count := 0
) -> RunLayout:
	var l := RunLayout.new()
	l.kind = screen.layout
	l.native = screen.native
	l.hinge = screen.hinge
	var w := l.native.x
	var h := l.native.y
	if l.kind == "tall":
		l.top = TOP_TALL
	l.chart_rect = Rect2i(10, l.top + 6, w - 20, h - l.top - BOTTOM - 12)
	l.message_rect = Rect2i(4, h - BOTTOM, w - 8, BOTTOM - 4)
	if l.kind == "wide":
		l.text_rect = Rect2i(12, TOP + 8, w - 24, 60)
	elif l.kind == "tall":
		# The buttons' column decides how far down the text may run.
		l.text_rect = Rect2i(12, l.top + 8, w - 24, h - l.top - 24)
	else:
		l.text_rect = Rect2i(12, TOP + 8, l.hinge.position.x - 20, h - TOP - 24)
	l.menu_rect = MenuLayout.menu_button(l.native)
	match mode:
		"chart":
			l._place_key()
			l._spread_columns(chart)
			for n in chart.nodes:
				var c := l.beacon_pos(n)
				l._add(
					"beacon", n.id, Rect2i(c - Vector2i(BEACON, BEACON) / 2, Vector2i.ONE * BEACON)
				)
		"event":
			l._choices(maxi(choice_count, 1), "choice")
		"next":
			l._add("next", 0, l._button_column(1)[0])
		_:  # a store page: its buttons are named after it
			l._choices(maxi(choice_count, 1), mode)
	if l.kind == "tall" and not l.buttons.is_empty() and mode != "chart":
		l.text_rect.end = Vector2i(l.text_rect.end.x, l.buttons[0].rect.position.y - 8)
	return l


## The key sits just above the message line, on as many rows as the width needs,
## and the chart gives up that height so no beacon's hit box reaches it.
func _place_key() -> void:
	var across := Rect2i(10, 0, native.x - 20, 0)
	var h := ChartKey.rows(across, hinge) * ChartKey.ROW
	key_rect = Rect2i(10, message_rect.position.y - h, native.x - 20, h)
	key = ChartKey.flow(key_rect, hinge)
	chart_rect.size.y -= h + 1


## Spreads beacons over the chart area, skipping the fold in the Square layout.
## Tall turns the chart a quarter: columns run from the bottom up to the Gate.
func beacon_pos(n: Dictionary) -> Vector2i:
	var r := chart_rect
	if kind == "tall":
		var x_at: int = _beacon_across.get(
			n.get("id", ""), r.position.x + int(round(float(n.y) * r.size.x))
		)
		return Vector2i(x_at, r.end.y - int(round(float(n.x) * r.size.y)))
	var y: int = _beacon_across.get(
		n.get("id", ""), r.position.y + int(round(float(n.y) * r.size.y))
	)
	if hinge.size.x == 0:
		return Vector2i(r.position.x + int(round(float(n.x) * r.size.x)), y)
	var gap := hinge.size.x + BEACON + 4
	var span := r.size.x - gap
	var x := r.position.x + int(round(float(n.x) * span))
	if x > hinge.position.x - BEACON / 2 - 2:
		x += gap
	return Vector2i(x, y)


## The part of the chart the Hush has swallowed, up to edge (0 is the start column,
## 1 the Gate): from the left, or from the bottom in Tall.
func hush_rect(edge: float) -> Rect2i:
	var p := beacon_pos({"x": minf(edge, 1.0), "y": 0.0})
	if kind == "tall":
		return Rect2i(0, p.y, native.x, native.y - p.y)
	return Rect2i(0, top - 3, p.x, native.y - top + 3)


## Beacons in a column sit at least a hit box and a gap apart. A tall chart
## already is; a short one (a larger UI) pushes them apart and back up from the bottom.
## In Tall a column runs across the screen, so it is spread across instead.
func _spread_columns(chart: StarChart) -> void:
	var cols := {}
	for n: Dictionary in chart.nodes:
		if not cols.has(n.col):
			cols[n.col] = []
		cols[n.col].append(n)
	var gap := BEACON + 3
	var r := chart_rect
	var lo := r.position.y
	var span := r.size.y
	if kind == "tall":
		lo = r.position.x
		span = r.size.x
	for col: Variant in cols:
		var ns: Array = cols[col]
		ns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
		var ys: Array[int] = []
		for n: Dictionary in ns:
			ys.append(lo + int(round(float(n.y) * span)))
		for i in range(1, ys.size()):
			ys[i] = maxi(ys[i], ys[i - 1] + gap)
		ys[-1] = mini(ys[-1], lo + span)
		for i in range(ys.size() - 2, -1, -1):
			ys[i] = mini(ys[i], ys[i + 1] - gap)
		# A column too tall for the chart overlaps rather than leaving it; the
		# layout test reports the overlap.
		for i in ys.size():
			ys[i] = clampi(ys[i], lo, lo + span)
		for i in ns.size():
			_beacon_across[ns[i].id] = ys[i]


func _choices(count: int, kind_name: String) -> void:
	var rects := _button_column(count)
	for i in count:
		_add(kind_name, i, rects[i])


## Buttons stack under the text (Wide), down the right page (Square), or up from
## the bottom (Tall), where a thumb reaches.
func _button_column(count: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var x: int
	var bw: int
	var y: int
	if kind == "wide":
		x = 40
		bw = native.x - 80
		y = text_rect.end.y + 8
		if count == 1:
			x = (native.x - NEXT_W) / 2
			bw = NEXT_W
	elif kind == "tall":
		x = 10
		bw = native.x - 20
		if count == 1:
			x = (native.x - NEXT_W) / 2
			bw = NEXT_W
		y = message_rect.position.y - 4 - count * (CHOICE_H_SQUARE + CHOICE_GAP) + CHOICE_GAP
	else:
		x = hinge.end.x + 8
		bw = native.x - x - 10
		y = text_rect.position.y + 4
	var bh := CHOICE_H if kind == "wide" else CHOICE_H_SQUARE
	# A long list (the refit page, the store) goes in two or three columns where
	# one would run off the bottom of a short Wide canvas.
	var cols := mini(ceili(float(count) / WIDE_ROWS), WIDE_COLS) if kind == "wide" else 1
	var rows := ceili(float(count) / cols)
	var cw := (bw - (cols - 1) * CHOICE_GAP) / cols
	for i in count:
		var c := i / rows
		var row := i % rows
		out.append(Rect2i(x + c * (cw + CHOICE_GAP), y + row * (bh + CHOICE_GAP), cw, bh))
	return out


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
		if not canvas.encloses(r):
			out.append("%s %s outside the canvas" % [b.kind, b.id])
		if r.position.y < top:
			out.append("%s %s under the status bar" % [b.kind, b.id])
		if hinge.size.x > 0 and r.intersects(hinge):
			out.append("%s %s sits on the fold" % [b.kind, b.id])
		if r.size.y < 10 or r.size.x < 10:
			out.append("%s %s is smaller than a fingertip" % [b.kind, b.id])
		for o in buttons:
			if o != b and r.grow(1).intersects(o.rect):
				out.append("%s %s and %s %s overlap" % [b.kind, b.id, o.kind, o.id])
		if r.grow(1).intersects(menu_rect):
			out.append("%s %s covers the menu button" % [b.kind, b.id])
	for k in key:
		var kr := Rect2i(k.at, Vector2i(ChartKey.ICON, ChartKey.ICON))
		if not canvas.encloses(kr) or (hinge.size.x > 0 and kr.intersects(hinge)):
			out.append("chart key %s is off the canvas or on the fold" % k.key)
		for b in buttons:
			if kr.intersects(b.rect):
				out.append("chart key %s is under %s %s" % [k.key, b.kind, b.id])
	if not canvas.encloses(menu_rect) or (hinge.size.x > 0 and menu_rect.intersects(hinge)):
		out.append("the menu button is off the canvas or on the fold")
	return out
