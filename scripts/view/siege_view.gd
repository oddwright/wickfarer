class_name SiegeView
extends RefCounted
## Draws the Kindling's own pieces over an ordinary fight screen: the knot a
## wave gathers in (with what is left of it), what that wave will strike on
## our ship, the kindling bar where the enemy's hull would be, and the Kindle
## button. Like WorldView it only reads the sim.

const BAR_W := 100  ## the kindling bar, top right, clear of the menu button


## The gathering knot and the threat it points at.
static func draw_world(world: WorldView, combat: Combat) -> void:
	var sg := combat.siege
	if not sg.gathering():
		return
	var knot := combat.enemy().room(sg.knot)
	if knot == null:
		return
	var kr := world.room_rect(1, knot)
	var total := maxf(0.1, sg.gather_total)
	var swell := clampf(1.0 - sg.gather / total, 0.0, 1.0)
	# The knot fills with the Hush's light as the wave swells.
	var inner := Rect2(kr.position + Vector2i(2, 2), kr.size - Vector2i(4, 4))
	world.draw_texture_rect_region(
		Pixel.dither("o", 2 if swell > 0.6 else 4), inner, Rect2(Vector2.ZERO, inner.size)
	)
	for k in sg.strength:
		world.draw_rect(Rect2(kr.position.x + 3 + k * 4, kr.position.y - 4, 3, 2), Pixel.c("o"))
	# What it will strike blinks faster as it nears, so a glance tells how long is left.
	var rate := 2.0 + 6.0 * swell
	if int(world.anim_time * rate) % 2 == 1:
		return
	var me := combat.player()
	if sg.wave_kind == "swallow" and me.room(sg.target_room):
		Pixel.corners(world, world.room_rect(0, me.room(sg.target_room)).grow(1), Pixel.c("o"), 4)
		return
	Pixel.corners(world, world.deck_rect(0, sg.target_deck).grow(3), Pixel.c("o"), 5)


## The kindling bar takes the enemy hull's place: the Hush has no hull to lose.
static func draw_hud(world: WorldView, combat: Combat, l: HudLayout) -> void:
	var sg := combat.siege
	var right := l.native.x - 34
	var at := Vector2i(maxi(right - BAR_W, _left_edge(l)), 14)
	var w := right - at.x
	world.draw_rect(Rect2(at, Vector2(w, 6)), Pixel.c("m"))
	var k := sg.kindling / sg.goal()
	if k > 0.0:
		world.draw_rect(Rect2(at, Vector2(maxf(1.0, roundf(w * k)), 6)), Pixel.c("v"))


static func draw_kindle_button(world: WorldView, combat: Combat, r: Rect2i) -> void:
	var sg := combat.siege
	var ready := sg.can_kindle()
	Pixel.panel(world, r, ready)
	var flame := Pixel.grid("..w..\n.wvw.\nwvxvw\n.wvw.\n..w..")
	var tint := Color(1, 1, 1, 1.0 if ready else 0.35)
	world.draw_texture(flame, Vector2(r.position + Vector2i(4, 6)), tint)


## The top-right words: the siege, its phase and time, and the Light in hand.
static func draw_text(tl: TextLayer, combat: Combat, l: HudLayout) -> void:
	var sg := combat.siege
	var right := l.native.x - 34
	var width := right - _left_edge(l)
	var phase := tl.tr(str(sg.phase_data().name))
	var line := ""
	if sg.is_last_phase():
		line = tl.tr("UI_SIEGE_KINDLING") % int(100.0 * sg.kindling / sg.goal())
	else:
		line = tl.tr("UI_SIEGE_LEFT") % [phase, int(ceil(sg.phase_left()))]
	tl._text(Vector2(right - width, 11), line, 6.5, Pixel.c("h"), HORIZONTAL_ALIGNMENT_RIGHT, width)
	var sub := phase if sg.is_last_phase() else tl.tr(str(sg.data().name))
	tl._text(Vector2(right - width, 30), sub, 5.0, Pixel.c("g"), HORIZONTAL_ALIGNMENT_RIGHT, width)


## Where the top-right words may start: the middle, or past any button in the
## top bar (Wide puts the crew and Kindle buttons there).
static func _left_edge(l: HudLayout) -> int:
	var edge := l.native.x / 2
	for b in l.buttons:
		var r: Rect2i = b.rect
		if r.position.y < HudLayout.BAR_H:
			edge = maxi(edge, r.end.x + 4)
	return edge


## The words on the Kindle button.
## The words on the Kindle button, with the Light left to burn written out, so
## the spend is planned, not guessed.
static func draw_button_text(tl: TextLayer, combat: Combat, r: Rect2i) -> void:
	var ready := combat.siege.can_kindle()
	var ink := Pixel.c("w") if ready else Pixel.c("f")
	tl._text(Vector2(r.position.x + 12, r.position.y + 13), tl.tr("UI_KINDLE"), 5.0, ink)
	var left := tl.tr("UI_LIGHT_LEFT") % combat.siege.light
	tl._text(
		Vector2(r.position.x + 4, r.position.y + 25), left, 5.0, Pixel.c("v") if ready else ink
	)


## The line under the ships: the siege's opening words, then each phase's
## advice, when nothing more pressing is being said.
static func hint(combat: Combat) -> String:
	var sg := combat.siege
	if combat.time() < 6.0:
		return TranslationServer.translate(str(sg.data().intro))
	return TranslationServer.translate(str(sg.phase_data().hint))
