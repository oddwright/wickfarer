class_name CoachLayout
extends RefCounted
## Where the coach writes and what it points at, on the fight and run screens.
## Pure data so tests can check every phone shape without a screen. The coach writes
## in the screen's own message line, which sits clear of every button, ship and the
## fold, so it never covers the thing it points at.

const CREW_BOX := Vector2i(10, 14)  ## around a crew member's feet


## Fight screens pass hud, run screens run_l; the other is null.
static func text_rect(hud: HudLayout, run_l: RunLayout) -> Rect2i:
	if hud != null:
		return _fight_rect(hud)
	if run_l != null:
		return _run_rect(run_l)
	return Rect2i()


## Wide: the line between the ships and the buttons. Square: that line can be a
## sliver on a squat tablet, but the left page of the second button row is empty
## past the Flare button (the ward and pause sit on the right page), so the coach
## writes there.
static func _fight_rect(hud: HudLayout) -> Rect2i:
	var ward := hud.button("ward")
	if hud.kind == "wide" or ward.is_empty() or hud.hinge.size.x == 0:
		return hud.message_rect
	var row: Rect2i = ward.rect
	var left := 4
	var flare := hud.button("flare")
	if not flare.is_empty():
		left = (flare.rect as Rect2i).end.x + 4  # the Flare button sits at the page's left end
	return Rect2i(left, row.position.y, hud.hinge.position.x - 4 - left, row.size.y)


## The bottom line, moved down below any button that reaches into it: on a short
## canvas (a Fold's cover screen at 6x) a story's choices run down that far.
static func _run_rect(l: RunLayout) -> Rect2i:
	var r := Rect2i(l.message_rect.position, Vector2i(l.message_rect.size.x, 0))
	r.end = Vector2i(r.end.x, l.native.y - 1)
	for b in l.buttons:
		var br: Rect2i = b.rect
		if br.intersects(r):
			r = Rect2i(r.position.x, br.end.y + 1, r.size.x, r.end.y - br.end.y - 1)
	return r


## The rects a step's target names (see Tutorial.TARGETS); empty when it names nothing
## on this screen. crew_feet are the player's crew positions on the canvas.
static func targets(
	target: String,
	hud: HudLayout,
	run_l: RunLayout,
	run: Run,
	combat: Combat,
	crew_feet: Array[Vector2i] = []
) -> Array[Rect2i]:
	var kind := target.get_slice(":", 0)
	var arg := target.get_slice(":", 1)
	var out: Array[Rect2i] = []
	if run_l != null and run != null:
		var jumps := run.jump_targets()
		for b in run_l.buttons:
			var hit := false
			match kind:
				"beacons":
					hit = b.kind == "beacon" and jumps.has(str(b.id))
				"choices":
					hit = b.kind in ["choice", "store"]
				"next":
					hit = b.kind == "next"
			if hit:
				out.append(b.rect)
		return out
	if hud == null or combat == null:
		return out
	match kind:
		"pause", "ward", "muster":
			_add(out, hud.button(kind))
		"weapon":
			_add(out, hud.button("weapon", int(arg)))
		"system":
			_add(out, hud.button("system", arg))
		"enemy_room":
			var r := combat.enemy().system_room(arg)
			if r:
				out.append(Rect2i(r.rect.position + hud.enemy_origin, r.rect.size))
		"rooms":
			for r in combat.player().rooms:
				out.append(Rect2i(r.rect.position + hud.player_origin, r.rect.size))
		"crew":
			for p in crew_feet:
				out.append(Rect2i(p - Vector2i(CREW_BOX.x / 2, CREW_BOX.y), CREW_BOX))
	return out


static func _add(out: Array[Rect2i], b: Dictionary) -> void:
	if not b.is_empty():
		out.append(b.rect)


## Problems with where the coach writes; empty means it is fine. Used by tests.
## lines is how many lines of 3x5 text the longest step wraps to at this width.
static func problems(r: Rect2i, buttons: Array[Dictionary], native: Vector2i) -> Array[String]:
	var out: Array[String] = []
	if not Rect2i(Vector2i.ZERO, native).encloses(r):
		out.append("coach text outside the canvas")
	for b in buttons:
		if r.intersects(b.rect):
			out.append("coach text covers the %s button" % b.kind)
	return out
