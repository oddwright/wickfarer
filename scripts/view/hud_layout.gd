class_name HudLayout
extends RefCounted
## Where everything sits on the pixel canvas, for the Wide, Square and Tall layouts.
## Pure data so tests can check every phone shape without a screen.

const SYSTEM_ORDER: Array[String] = ["wards", "weapons", "helm", "engines", "mend"]
const SYS_W := 28
const SYS_GAP := 30
const WPN_W := 78
const WPN_GAP := 82
const ROW_H := 44
const SMALL_W := 54
const CREW_W := 34  ## the Crew and Muster buttons
const CREW_H := 30
const CREW_X := 128  ## clear of the longest ship name and hull count in the top bar
const KINDLE_W := 54
const BAR_H := 40  ## a ship's status lines: name and hull, hull pips, reactor, power
const MSG_H := 24  ## Tall: three lines of the hint between the player ship and the buttons

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
## Top of the player's status lines: the top bar, or just over their hull in Tall,
## where the enemy's lines take the top bar to themselves.
var player_bar_y := 0
## Opens the pause menu; kept out of buttons, which are the fight controls.
var menu_rect: Rect2i


static func build(
	screen: Dictionary,
	player_frame: Vector2i,
	enemy_frame: Vector2i,
	systems: Array[String],
	weapon_count: int,
	player_used := Rect2i(),
	enemy_used := Rect2i(),
	siege := false
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
	if l.kind == "tall":
		l._build_tall(player_frame, enemy_frame, pu, eu, systems, weapon_count)
	elif l.kind == "wide":
		# Centre the ships in the band between the top bar and the buttons,
		# leaving a line underneath for prompts.
		var band := row_y - BAR_H - 14
		var py := BAR_H + maxi(0, (band - player_frame.y) / 2)
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
		l._add_crew_buttons(Vector2i(CREW_X, 4))
		l.message_rect = Rect2i(
			4,
			l.player_origin.y + player_frame.y + 2,
			w - 8,
			row_y - (l.player_origin.y + player_frame.y) - 4
		)
	else:
		# Spread the two ships evenly down the space above the buttons.
		var row2_top := row_y - ROW_H - 4
		var free := row2_top - BAR_H - 14 - enemy_frame.y - player_frame.y
		var gap := maxi(8, free / 3)
		l.enemy_origin = Vector2i(w - 4 - eu.end.x, BAR_H + gap)
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
		l._add_crew_buttons(Vector2i(right + SMALL_W + 4, row2 + ROW_H - CREW_H))
		var msg_top := l.player_origin.y + player_frame.y + 2
		l.message_rect = Rect2i(4, msg_top, w - 8, row2 - msg_top - 4)
	l.player_body = Rect2i(l.player_origin + pu.position, pu.size)
	l.enemy_body = Rect2i(l.enemy_origin + eu.position, eu.size)
	if siege:
		l._add_kindle()
	return l


## The Kindling's one extra order. The bottom rows are full on the narrowest
## canvases, so it sits in the top bar beside the crew buttons in Wide, at the
## top bar just right of the fold in Square (its crew buttons are down by the ward), and
## beside the crew buttons over the guns in Tall.
func _add_kindle() -> void:
	var crew: Rect2i = button("crew").rect
	var size := Vector2i(KINDLE_W, CREW_H)
	match kind:
		"wide":
			_add("kindle", 0, Rect2i(crew.position + Vector2i((CREW_W + 4) * 2, 0), size))
		"tall":
			_add("kindle", 0, Rect2i(crew.position - Vector2i(KINDLE_W + 4, 0), size))
		_:
			_add("kindle", 0, Rect2i(Vector2i(hinge.end.x + 4, 4), size))


## Tall (a phone held upright): the enemy under the top bar, the player's status lines
## and hull below it, then three rows of buttons at the bottom, under the thumb:
## crew orders, guns and the ward, systems and pause.
func _build_tall(
	pf: Vector2i, ef: Vector2i, pu: Rect2i, eu: Rect2i, systems: Array[String], weapon_count: int
) -> void:
	var w := native.x
	var row1 := native.y - ROW_H - 4
	var row2 := row1 - ROW_H - 4
	var row3 := row2 - CREW_H - 4
	var x := 4
	for s in systems:
		_add("system", s, Rect2i(x, row1, SYS_W, ROW_H))
		x += SYS_GAP
	_add("pause", 0, Rect2i(w - 34, row1 + 14, 30, 30))
	var ward_x := w - 4 - SMALL_W
	var n := maxi(weapon_count, 1)
	var wpn_w := mini(WPN_W, (ward_x - 8 - (n - 1) * 4) / n)
	for i in weapon_count:
		_add("weapon", i, Rect2i(4 + i * (wpn_w + 4), row2, wpn_w, ROW_H))
	_add("ward", 0, Rect2i(ward_x, row2, SMALL_W, ROW_H))
	_add_crew_buttons(Vector2i(w - 4 - CREW_W * 2 - 4, row3))
	# Spare height goes into even gaps around the ships, then into the message line.
	var free := row3 - 4 - BAR_H - ef.y - BAR_H - pf.y - MSG_H
	var gap := clampi(free / 3, 2, 40)
	enemy_origin = Vector2i(w - 4 - eu.end.x, BAR_H + gap)
	player_bar_y = enemy_origin.y + ef.y + gap
	# The widest hulls are wider than a 5x phone held upright: keep the bow on
	# screen and let the engines run off the left edge.
	player_origin = Vector2i(mini(4 - pu.position.x, w - 2 - pu.end.x), player_bar_y + BAR_H)
	var msg_top := player_origin.y + pf.y + 2
	message_rect = Rect2i(4, msg_top, w - 8, row3 - msg_top - 2)


## Crew opens the roster; Muster sends everyone to their posts.
func _add_crew_buttons(at: Vector2i) -> void:
	_add("crew", 0, Rect2i(at, Vector2i(CREW_W, CREW_H)))
	_add("muster", 0, Rect2i(at + Vector2i(CREW_W + 4, 0), Vector2i(CREW_W, CREW_H)))


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


## Where the big PAUSED is written: mid-screen, over the ships. In Tall the middle of
## the canvas is the player's status lines, so it goes over the player's hull instead.
func paused_y() -> int:
	if kind == "tall":
		return player_body.get_center().y + 7
	return native.y / 2 - 26


func again_rect() -> Rect2i:
	return Rect2i(native.x / 2 - 50, native.y / 2 + 8, 100, 28)


## Problems with this layout; empty means it is fine. Used by tests.
func problems() -> Array[String]:
	var out: Array[String] = []
	var canvas := Rect2i(Vector2i.ZERO, native)
	var player_rect := player_body
	var enemy_rect := enemy_body
	var room := canvas
	if kind == "tall":
		room = canvas.grow_individual(ScreenManager.TALL_BLEED, 0, ScreenManager.TALL_BLEED, 0)
		var bar := Rect2i(0, player_bar_y, native.x, BAR_H)
		if bar.intersects(enemy_rect) or bar.intersects(player_rect):
			out.append("the player's status lines cover a ship")
		if message_rect.size.y < MSG_H:
			out.append("no room for the hint under the player ship")
	for r in [player_rect, enemy_rect]:
		if not room.encloses(r):
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
