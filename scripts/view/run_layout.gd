class_name RunLayout
extends RefCounted
## Where things sit on the run screens (star chart, event, store, endings),
## for the Wide and Square layouts. Pure data so tests can check every phone
## shape without a screen, like HudLayout.
## In the Square layout the text goes on the left page and buttons on the
## right, so nothing you tap sits on the fold.

const BEACON := 12  ## beacon hit box; the tap area grows it by 2 on each side
const TOP := 20  ## below the status bar
const BOTTOM := 26  ## room for a message line under the chart
const CHOICE_H := 20
const CHOICE_H_SQUARE := 30  ## the right page is narrow, so labels may take two lines
const CHOICE_GAP := 4
const NEXT_W := 90

var kind: String
var native: Vector2i
var hinge: Rect2i
var chart_rect: Rect2i  ## the area beacons are spread over
var text_rect: Rect2i  ## the story or store text
var message_rect: Rect2i  ## a one or two line note at the bottom
var buttons: Array[Dictionary] = []  ## {kind, id, rect}


## mode is "chart", "event", "store" or "next" (one Continue button).
static func build(
	screen: Dictionary, chart: StarChart, mode: String, choice_count := 0
) -> RunLayout:
	var l := RunLayout.new()
	l.kind = screen.layout
	l.native = screen.native
	l.hinge = screen.hinge
	var w := l.native.x
	var h := l.native.y
	l.chart_rect = Rect2i(10, TOP + 6, w - 20, h - TOP - BOTTOM - 12)
	l.message_rect = Rect2i(4, h - BOTTOM, w - 8, BOTTOM - 4)
	if l.kind == "wide":
		l.text_rect = Rect2i(12, TOP + 8, w - 24, 60)
	else:
		l.text_rect = Rect2i(12, TOP + 8, l.hinge.position.x - 20, h - TOP - 24)
	l._add("menu", 0, MenuLayout.menu_button(l.native))
	match mode:
		"chart":
			for n in chart.nodes:
				var c := l.beacon_pos(n)
				l._add(
					"beacon", n.id, Rect2i(c - Vector2i(BEACON, BEACON) / 2, Vector2i.ONE * BEACON)
				)
		"event":
			l._choices(maxi(choice_count, 1), "choice")
		"store":
			l._choices(maxi(choice_count, 1), "store")
		"next":
			l._add("next", 0, l._button_column(1)[0])
	return l


## Spreads beacons over the chart area, skipping the fold in the Square layout.
func beacon_pos(n: Dictionary) -> Vector2i:
	var r := chart_rect
	var y := r.position.y + int(round(float(n.y) * r.size.y))
	if hinge.size.x == 0:
		return Vector2i(r.position.x + int(round(float(n.x) * r.size.x)), y)
	var gap := hinge.size.x + BEACON + 4
	var span := r.size.x - gap
	var x := r.position.x + int(round(float(n.x) * span))
	if x > hinge.position.x - BEACON / 2 - 2:
		x += gap
	return Vector2i(x, y)


func _choices(count: int, kind_name: String) -> void:
	var rects := _button_column(count)
	for i in count:
		_add(kind_name, i, rects[i])


## Buttons stack under the text (Wide) or down the right page (Square).
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
	else:
		x = hinge.end.x + 8
		bw = native.x - x - 10
		y = text_rect.position.y + 4
	var bh := CHOICE_H if kind == "wide" else CHOICE_H_SQUARE
	for i in count:
		out.append(Rect2i(x, y + i * (bh + CHOICE_GAP), bw, bh))
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
		if r.position.y < TOP and b.kind != "menu":  # the menu button lives in the bar
			out.append("%s %s under the status bar" % [b.kind, b.id])
		if hinge.size.x > 0 and r.intersects(hinge):
			out.append("%s %s sits on the fold" % [b.kind, b.id])
		if r.size.y < 10 or r.size.x < 10:
			out.append("%s %s is smaller than a fingertip" % [b.kind, b.id])
		for o in buttons:
			if o != b and r.grow(1).intersects(o.rect):
				out.append("%s %s and %s %s overlap" % [b.kind, b.id, o.kind, o.id])
	return out
