class_name FightMarks
extends RefCounted
## Drawing for rents and the Ember flare, kept out of WorldView so it stays short.

## A jagged tear with frost-blue edges; the void shows through it.
const TEAR := ".j...\njaj..\n.jaj.\n..jaj\n...j."
## Half sealed: plate over most of the tear.
const PATCHED := ".j...\njff..\n.fff.\n..ffj\n...j."
const FLAME := "..w..\n.wvw.\nwvxvw\n.wvw.\n..w.."


## A rent in the bottom-right of a room (its word sits top-right), with specks of
## warmth pulled out through it.
## The room's cold shading already shows the warmth it costs.
static func draw_rent(world: WorldView, r: Room, rr: Rect2i, t: float) -> void:
	if r.rent <= 0.0:
		return
	var at := Vector2(rr.end.x - 8, rr.end.y - 7)
	world.draw_texture(Pixel.grid(TEAR if r.rent > 50.0 else PATCHED), at)
	# Two specks drift toward the tear and vanish into it, a second apart.
	for k in 2:
		var f := fmod(t + k * 0.5, 1.0)
		var from := Vector2(rr.position.x + 4 + k * 6, rr.position.y + 10)
		var p := from.lerp(at + Vector2(2, 2), f).round()
		world.draw_rect(Rect2(p, Vector2.ONE), Pixel.c("j", 1.0 - f))


## While a ship flares, its Ember room glows and pulses; only the Ember glows.
static func draw_flare(world: WorldView, s: Ship, rr: Rect2i, t: float) -> void:
	if s.flare_time <= 0.0:
		return
	var pulse := 0.35 + 0.25 * (1.0 if int(t * 6.0) % 2 == 0 else 0.0)
	var inner := Rect2(rr.position + Vector2i(0, 1), rr.size - Vector2i(0, 1))
	world.draw_texture_rect_region(
		Pixel.dither("v", 2), inner, Rect2(Vector2.ZERO, inner.size), Color(1, 1, 1, pulse)
	)


## The Flare button: a flame, lit when ready, glowing while burning, dim while
## the Ember rests; its bar shows the burn left, or the rest still to wait.
static func draw_button(world: WorldView, s: Ship, r: Rect2i) -> void:
	var ready := s.can_flare()
	var burning := s.flare_time > 0.0
	Pixel.panel(world, r, burning)
	var tint := Color(1, 1, 1, 1.0 if ready or burning else 0.35)
	world.draw_texture(Pixel.grid(FLAME), Vector2(r.position + Vector2i(r.size.x / 2 - 2, 4)), tint)
	var f := Ship.flare_data()
	var bar := Rect2(r.position.x + 4, r.end.y - 6, r.size.x - 8, 2)
	var k := 0.0
	var col := Pixel.c("v")
	if burning:
		k = s.flare_time / float(f.seconds)
	elif s.flare_cool > 0.0:
		k = 1.0 - s.flare_cool / float(f.cooldown)
		col = Pixel.c("f")
	if burning or s.flare_cool > 0.0:
		world.draw_rect(bar, Pixel.c("c"))
		world.draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * k), 2)), col)


## The word on the Flare button.
static func draw_button_text(tl: TextLayer, s: Ship, r: Rect2i) -> void:
	var lit := s.can_flare() or s.flare_time > 0.0
	tl._text(
		Vector2(r.position.x, r.position.y + r.size.y / 2 + 5),
		tl.tr("UI_FLARE"),
		5.0,
		Pixel.c("w") if lit else Pixel.c("f"),
		HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x
	)
