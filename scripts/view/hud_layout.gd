class_name HudLayout
extends RefCounted
## Where everything sits on the pixel canvas, for the Wide and Square layouts.
## Pure data so tests can check every phone shape without a screen.

const SYSTEM_ORDER: Array[String] = ["wards", "weapons", "helm", "engines", "mend"]
const SYS_W := 28
const SYS_GAP := 30
const WPN_W := 78
const WPN_GAP := 82
const ROW_H := 44
const SMALL_W := 54

var kind: String
var native: Vector2i
var hinge: Rect2i
var player_origin: Vector2i
var enemy_origin: Vector2i
## Each hull's drawn pixels on the canvas. Frames carry empty edges, so ships
## are placed and checked by these instead; on a narrow canvas the frames may overlap.
var player_body: Rect2i
var enemy_body: Rect2i
var buttons: Array[Dictionary] = []  ## {kind, id, rect}
var message_rect: Rect2i  ## where prompts and hints are written
## Opens the pause menu; kept out of buttons, which are the fight controls.
var menu_rect: Rect2i


static func build(
	screen: Dictionary,
	player_frame: Vector2i,
	enemy_frame: Vector2i,
	systems: Array[String],
	weapon_count: int,
	player_used := Rect2i(),
	enemy_used := Rect2i()
) -> HudLayout:
	## player_used and enemy_used are the non-empty part of each frame; empty means all of it.
	var pu := player_used if player_used.has_area() else Rect2i(Vector2i.ZERO, player_frame)
	var eu := enemy_used if enemy_used.has_area() else Rect2i(Vector2i.ZERO, enemy_frame)
	var l := HudLayout.new()
	l.kind = screen.layout
	l.native = screen.native
	l.hinge = screen.hinge
	var w := l.native.x
	var h := l.native.y
	var row_y := h - ROW_H - 4
	l.menu_rect = MenuLayout.menu_button(l.native)
	if l.kind == "wide":
		# Centre the ships in the band between the top bar and the buttons,
		# leaving a line underneath for prompts.
		var band := row_y - 40 - 14
		var py := 40 + maxi(0, (band - player_frame.y) / 2)
		l.player_origin = Vector2i(2 - pu.position.x, py)
		l.enemy_origin = Vector2i(w - 2 - eu.end.x, py + (player_frame.y - enemy_frame.y) / 2)
		var x := 4
		for s in systems:
			l._add("system", s, Rect2i(x, row_y, SYS_W, ROW_H))
			x += SYS_GAP
		x += 6
		for i in weapon_count:
			l._add("weapon", i, Rect2i(x, row_y, WPN_W, ROW_H))
			x += WPN_GAP
		l._add("ward", 0, Rect2i(x, row_y, SMALL_W, ROW_H))
		l._add("pause", 0, Rect2i(w - 34, row_y + 14, 30, 30))
		l.message_rect = Rect2i(
			4,
			l.player_origin.y + player_frame.y + 2,
			w - 8,
			row_y - (l.player_origin.y + player_frame.y) - 4
		)
	else:
		# Spread the two ships evenly down the space above the buttons.
		var row2_top := row_y - ROW_H - 4
		var free := row2_top - 40 - 14 - enemy_frame.y - player_frame.y
		var gap := maxi(8, free / 3)
		l.enemy_origin = Vector2i(w - 4 - eu.end.x, 40 + gap)
		l.player_origin = Vector2i(4 - pu.position.x, l.enemy_origin.y + enemy_frame.y + gap)
		# Left cluster: systems. Right cluster: weapons. The fold line stays empty.
		var x := 4
		for s in systems:
			l._add("system", s, Rect2i(x, row_y, SYS_W, ROW_H))
			x += SYS_GAP
		var right := l.hinge.end.x + 4
		x = right
		for i in weapon_count:
			l._add("weapon", i, Rect2i(x, row_y, WPN_W, ROW_H))
			x += WPN_GAP
		var row2 := row_y - ROW_H - 4
		l._add("ward", 0, Rect2i(right, row2, SMALL_W, ROW_H))
		l._add("pause", 0, Rect2i(w - 34, row2 + 14, 30, 30))
		var msg_top := l.player_origin.y + player_frame.y + 2
		l.message_rect = Rect2i(4, msg_top, w - 8, row2 - msg_top - 4)
	l.player_body = Rect2i(l.player_origin + pu.position, pu.size)
	l.enemy_body = Rect2i(l.enemy_origin + eu.position, eu.size)
	return l


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


func again_rect() -> Rect2i:
	return Rect2i(native.x / 2 - 50, native.y / 2 + 8, 100, 28)


## Problems with this layout; empty means it is fine. Used by tests.
func problems() -> Array[String]:
	var out: Array[String] = []
	var canvas := Rect2i(Vector2i.ZERO, native)
	var player_rect := player_body
	var enemy_rect := enemy_body
	for r in [player_rect, enemy_rect]:
		if not canvas.encloses(r):
			out.append("ship outside the canvas %s" % r)
	if player_rect.intersects(enemy_rect):
		out.append("ships overlap")
	for b in buttons + [{"kind": "menu", "rect": menu_rect}]:
		var r: Rect2i = b.rect
		if not canvas.encloses(r):
			out.append("%s button outside the canvas" % b.kind)
		if r.intersects(player_rect) or r.intersects(enemy_rect):
			out.append("%s button covers a ship" % b.kind)
		if hinge.size.x > 0 and r.intersects(hinge):
			out.append("%s button sits on the fold" % b.kind)
		for o in buttons:
			if o != b and r.intersects(o.rect):
				out.append("%s and %s buttons overlap" % [b.kind, o.kind])
	return out
