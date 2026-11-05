class_name WorldView
extends Node2D
## Draws the pixel world: stars, ships, rooms, crew, shots and the pixel HUD.
## It only reads the simulation; it never changes it.

const CREW_CELL := Vector2i(17, 14)

var main: Node  ## the Main node, for combat, layout and selection state
var ship_tex: Array[Texture2D] = []
var ship_frames: Array[Vector2i] = []
var ship_used: Array[Rect2i] = []  ## the hull inside each frame, from Pixel.used_rect
var crew_tex: Dictionary = {}
var icons: Texture2D
var icon_index: Dictionary = {}
var stars: Array = []
var anim_time := 0.0
var shake := Vector2i.ZERO  ## native pixels; moves the ships only, never the HUD or taps


func setup(main_node: Node) -> void:
	main = main_node
	var combat: Combat = main.combat
	ship_tex.clear()
	ship_frames.clear()
	ship_used.clear()
	for s in combat.ships:
		var c: Dictionary = ContentDB.ships[s.content_id]
		ship_tex.append(load(c.sprite))
		ship_frames.append(Vector2i(int(c.frame_size[0]), int(c.frame_size[1])))
		ship_used.append(Pixel.used_rect(ship_tex[-1], ship_frames[-1]))
	for sp: String in ContentDB.species:
		crew_tex[sp + ":0"] = load("res://art/crew_%s.png" % sp)
		crew_tex[sp + ":1"] = load("res://art/crew_%s_raider.png" % sp)
	icons = load("res://art/icons.png")
	var names: Array = JSON.parse_string(FileAccess.get_file_as_string("res://art/icons.json"))
	for i in names.size():
		icon_index[names[i]] = i


func make_stars(size: Vector2i) -> void:
	# Hand-clustered look: a few loose clumps plus sparse singles, fixed seed.
	stars.clear()
	var r := RandomNumberGenerator.new()
	r.seed = 1977
	var clusters := []
	for i in 5:
		clusters.append(Vector2(r.randf() * size.x, r.randf() * size.y))
	for i in 140:
		var p: Vector2
		if i % 3 == 0:
			p = Vector2(r.randf() * size.x, r.randf() * size.y)
		else:
			var cl: Vector2 = clusters[i % clusters.size()]
			p = cl + Vector2(r.randfn(0, 22), r.randfn(0, 14))
		var key := "f" if r.randf() < 0.6 else ("g" if r.randf() < 0.8 else "h")
		stars.append([Vector2i(p), key])


func _process(delta: float) -> void:
	anim_time += delta


func ship_origin(side: int) -> Vector2i:
	return main.layout.player_origin if side == 0 else main.layout.enemy_origin


func room_rect(side: int, r: Room) -> Rect2i:
	return Rect2i(r.rect.position + ship_origin(side), r.rect.size)


func room_at(side: int, p: Vector2i) -> Room:
	var s: Ship = main.combat.ships[side]
	for r in s.rooms:
		if room_rect(side, r).grow(1).has_point(p):
			return r
	return null


## Feet position of a crew member on the canvas.
func crew_pos(side: int, c: Crew) -> Vector2:
	var s: Ship = main.combat.ships[side]
	var o := Vector2(ship_origin(side))
	var here := s.room(c.room)
	if c.is_moving():
		var next := s.room(c.path[0])
		if s.is_ladder(here.id, next.id):
			var lx := float(s.ladder_x(here.id, next.id)) + 1.5
			var y0 := float(here.rect.end.y)
			var y1 := float(next.rect.end.y)
			# walk to the ladder, then climb
			return o + Vector2(lx, lerpf(y0, y1, c.progress))
		var a := Vector2(here.center_x(), here.rect.end.y)
		var b := Vector2(next.center_x(), next.rect.end.y)
		return o + a.lerp(b, c.progress)
	var mates := s.crew_in(here.id)
	var idx := mates.find(c)
	var n := maxi(1, mates.size())
	var span := float(here.rect.size.x - 6)
	var x := float(here.rect.position.x) + 3.0 + span * (float(idx) + 0.5) / float(n)
	return o + Vector2(roundf(x), here.rect.end.y)


func crew_at(side: int, p: Vector2i, radius := 10.0) -> Crew:
	var best: Crew = null
	var best_d := radius
	for c in main.combat.ships[side].alive_crew():
		var fp := crew_pos(side, c) + Vector2(0, -6)
		var d := fp.distance_to(Vector2(p))
		if d < best_d:
			best_d = d
			best = c
	return best


# ------------------------------------------------------------------ draw


func _draw() -> void:
	if main == null or main.layout == null:
		return
	var combat: Combat = main.combat
	var native: Vector2i = main.layout.native
	draw_rect(Rect2(Vector2.ZERO, native), Pixel.c("a"))
	for s in stars:
		draw_rect(Rect2(s[0], Vector2.ONE), Pixel.c(s[1]))
	var frame := int(anim_time * 6.0) % 4
	# Shake the ships, not the buttons: a jolt must never move a tap target.
	draw_set_transform(Vector2(shake))
	for side in 2:
		var o := ship_origin(side)
		var fs := ship_frames[side]
		draw_texture_rect_region(ship_tex[side], Rect2(o, fs), Rect2(Vector2(fs.x * frame, 0), fs))
		_draw_rooms(side)
		_draw_wards(side)
	_draw_aims()
	for side in 2:
		_draw_crew(side)
	_draw_projectiles()
	draw_set_transform(Vector2.ZERO)
	_draw_hud()
	if main.paused or combat.state != "fighting":
		draw_texture_rect(Pixel.dither("a", 2), Rect2(Vector2.ZERO, native), true)
	if combat.state != "fighting":
		_draw_panel(main.layout.again_rect(), true)


func _draw_rooms(side: int) -> void:
	var s: Ship = main.combat.ships[side]
	for r in s.rooms:
		var rr := room_rect(side, r)
		var inner := Rect2(rr.position + Vector2i(0, 1), rr.size - Vector2i(0, 1))
		if r.warmth < 25.0:
			draw_texture_rect_region(Pixel.dither("i", 2), inner, Rect2(Vector2.ZERO, inner.size))
		elif r.warmth < 40.0:
			draw_texture_rect_region(Pixel.dither("i", 4), inner, Rect2(Vector2.ZERO, inner.size))
		if r.fire > 0.0:
			var n := clampi(int(r.fire / 25.0) + 1, 1, 4)
			for k in n:
				var fx := rr.position.x + 2 + k * int(max(1, (rr.size.x - 7) / n))
				var tex := Pixel.grid(Pixel.FIRE[(int(anim_time * 8.0) + k) % 3])
				draw_texture(tex, Vector2(fx, rr.end.y - 7))
		var flash: float = main.flash_amount(side, r.id)
		if flash > 0.0:
			draw_rect(inner, Pixel.c("x", flash * 0.8))
		if r.system != "":
			_draw_system_icon(r, rr)
		if side == 1 and r.system == "ember":
			var t := Pixel.grid("..w..\n.wvw.\nwvxvw\n.wvw.\n..w..")
			draw_texture(t, Vector2(rr.get_center()) + Vector2(-2, 0))


func _draw_system_icon(r: Room, rr: Rect2i) -> void:
	var idx: int = icon_index.get(r.system, -1)
	if idx < 0:
		return
	var pos := Vector2(rr.position + Vector2i(2, 3))
	var col := Color(1, 1, 1, 1)
	if r.effective_level() < r.level:
		col = Pixel.c("U") if int(anim_time * 4.0) % 2 == 0 else Color(1, 1, 1)
	elif r.system != "ember" and r.power == 0:
		col = Color(0.45, 0.45, 0.55, 1)
	draw_texture_rect_region(icons, Rect2(pos, Vector2(9, 9)), Rect2(idx * 9, 0, 9, 9), col)
	# damage pips under the icon
	var dmg := int(ceil(r.damage - 0.001))
	for k in dmg:
		draw_rect(Rect2(pos + Vector2(k * 3, 10), Vector2(2, 2)), Pixel.c("U"))


func _draw_wards(side: int) -> void:
	var s: Ship = main.combat.ships[side]
	if s.ward_layers <= 0 and s.max_ward_layers() <= 0:
		return
	var box := Rect2i()
	var first := true
	for r in s.rooms:
		if r.deck == s.ward_deck:
			var rr := room_rect(side, r)
			box = rr if first else box.merge(rr)
			first = false
	box = box.grow(2)
	for k in s.max_ward_layers():
		var on := k < s.ward_layers
		var b := box.grow(k * 2)
		var col := Pixel.c("j") if on else Pixel.c("e", 0.8)
		if on or int(anim_time * 2.0) % 2 == 0:
			_dashed_rect(b, col, 2 if on else 1)


func _dashed_rect(b: Rect2i, col: Color, gap: int) -> void:
	for x in range(b.position.x, b.end.x, gap + 1):
		draw_rect(Rect2(x, b.position.y, 1, 1), col)
		draw_rect(Rect2(x, b.end.y - 1, 1, 1), col)
	for y in range(b.position.y, b.end.y, gap + 1):
		draw_rect(Rect2(b.position.x, y, 1, 1), col)
		draw_rect(Rect2(b.end.x - 1, y, 1, 1), col)


func _draw_aims() -> void:
	var combat: Combat = main.combat
	var me := combat.player()
	var cols := [Pixel.c("v"), Pixel.c("u")]
	for i in me.weapon_ids.size():
		var t := me.weapon_target[i]
		if t == "":
			continue
		var rr := room_rect(1, combat.enemy().room(t)).grow(-1 - i * 2)
		_corners(rr, cols[i % 2], 3)
	# The enemy's aim is shown too, so the ward choice is readable.
	var foe := combat.enemy()
	for i in foe.weapon_ids.size():
		var t := foe.weapon_target[i]
		if t == "":
			continue
		var rr := room_rect(0, me.room(t)).grow(-1 - i * 2)
		_corners(rr, Pixel.c("U"), 2)
	if main.selected_weapon >= 0:
		var blink := int(anim_time * 4.0) % 2 == 0
		for r in foe.rooms:
			if blink:
				_corners(room_rect(1, r), Pixel.c("h"), 2)


func _corners(r: Rect2i, col: Color, n: int) -> void:
	Pixel.corners(self, r, col, n)


func _draw_crew(side: int) -> void:
	var s: Ship = main.combat.ships[side]
	for c in s.alive_crew():
		var tex: Texture2D = crew_tex[c.species + ":" + str(side)]
		var fp := crew_pos(side, c)
		var f: int
		if c.is_moving():
			f = 2 + int(anim_time * 8.0 + c.uid) % 4
		else:
			f = int(anim_time * 2.0 + c.uid * 0.37) % 2
		var dst := Rect2(
			Vector2(roundf(fp.x) - CREW_CELL.x / 2, fp.y - CREW_CELL.y), Vector2(CREW_CELL)
		)
		var src := Rect2(f * CREW_CELL.x, 0, CREW_CELL.x, CREW_CELL.y)
		if side == 1:
			dst.position.x += dst.size.x
			dst.size.x = -dst.size.x
		draw_texture_rect_region(tex, dst, src)
		if side == 0 and main.selected_crew == c.uid:
			var y := fp.y + 1
			draw_rect(Rect2(roundf(fp.x) - 4, y, 9, 1), Pixel.c("w"))
			draw_rect(Rect2(roundf(fp.x) - 4, y - 1, 1, 1), Pixel.c("w"))
			draw_rect(Rect2(roundf(fp.x) + 4, y - 1, 1, 1), Pixel.c("w"))
		if c.hp < c.max_hp:
			var w := 7.0 * c.hp / c.max_hp
			var top := fp.y - CREW_CELL.y - 2
			draw_rect(Rect2(roundf(fp.x) - 3, top, 7, 1), Pixel.c("r"))
			draw_rect(
				Rect2(roundf(fp.x) - 3, top, maxf(1.0, roundf(w)), 1),
				Pixel.c("H") if c.hp > c.max_hp * 0.35 else Pixel.c("U")
			)


func _draw_projectiles() -> void:
	var combat: Combat = main.combat
	for p in combat.projectiles:
		var owner := int(p.owner)
		var src_ship := combat.ships[owner]
		var dst_ship := combat.ships[1 - owner]
		var a := Vector2(room_rect(owner, src_ship.system_room("weapons")).get_center())
		var b := Vector2(room_rect(1 - owner, dst_ship.room(p.target)).get_center())
		var k := 1.0 - float(p.t) / float(p.total)
		var start_delay := (float(p.total) - Combat.FLIGHT_TIME) / float(p.total)
		if k < start_delay:
			continue
		k = (k - start_delay) / (1.0 - start_delay)
		var pos := a.lerp(b, k).round()
		var dir := signf(b.x - a.x)
		if ContentDB.weapons[p.weapon].family == "torch":
			draw_rect(Rect2(pos + Vector2(-dir * 3, 0), Vector2(3, 2)), Pixel.c("t"))
			draw_rect(Rect2(pos, Vector2(3, 2)), Pixel.c("w"))
		else:
			draw_rect(Rect2(pos + Vector2(-dir * 4, 0), Vector2(4, 1)), Pixel.c("q"))
			draw_rect(Rect2(pos, Vector2(2, 1)), Pixel.c("z"))


# ------------------------------------------------------------------ HUD


func _draw_panel(r: Rect2i, active: bool) -> void:
	Pixel.panel(self, r, active)


func _draw_hud() -> void:
	var combat: Combat = main.combat
	var l: HudLayout = main.layout
	var me := combat.player()
	_draw_hull(me, Vector2i(4, 4), false)
	_draw_hull(combat.enemy(), Vector2i(l.native.x - 34, 4), true)  # clear of the menu button
	Pixel.menu_icon(self, l.menu_rect)
	# reactor: green = in use, outline = spare, red = lost to Ember damage
	var used := me.used_power()
	for k in me.reactor:
		var pip := Rect2(4 + k * 5, 26, 4, 3)
		if k < used:
			draw_rect(pip, Pixel.c("H"))
		elif k < me.available_power():
			draw_rect(pip, Pixel.c("f"), false, 1.0)
		else:
			draw_rect(pip, Pixel.c("s"))
	for b in l.buttons:
		var r: Rect2i = b.rect
		match b.kind:
			"system":
				_draw_system_button(me, b.id, r)
			"weapon":
				_draw_weapon_button(me, int(b.id), r)
			"ward":
				_draw_panel(r, false)
				var ic: int = icon_index.wards
				draw_texture_rect_region(
					icons, Rect2(r.position + Vector2i(4, 4), Vector2(9, 9)), Rect2(ic * 9, 0, 9, 9)
				)
				for d in 2:
					var y := r.position.y + 18 + (1 - d) * 10
					var on := me.ward_deck == d
					draw_rect(
						Rect2(r.position.x + 4, y, 10, 7), Pixel.c("j") if on else Pixel.c("c")
					)
			"pause":
				_draw_panel(r, main.paused)
				var cx := r.position.x + 11
				if main.paused:
					draw_texture(
						Pixel.grid("w....\nwww..\nwwwww\nwww..\nw...."),
						Vector2(cx, r.position.y + 12)
					)
				else:
					draw_rect(Rect2(cx, r.position.y + 11, 3, 8), Pixel.c("w"))
					draw_rect(Rect2(cx + 5, r.position.y + 11, 3, 8), Pixel.c("w"))


func _draw_hull(s: Ship, at: Vector2i, right: bool) -> void:
	for k in s.max_hull:
		var x := at.x + k * 4
		if right:
			x = at.x - (k + 1) * 4
		var col := Pixel.c("H") if k < s.hull else Pixel.c("c")
		if k < s.hull and s.hull <= s.max_hull / 3:
			col = Pixel.c("U")
		draw_rect(Rect2(x, at.y + 10, 3, 6), col)


func _draw_system_button(me: Ship, sys: String, r: Rect2i) -> void:
	var room := me.system_room(sys)
	_draw_panel(r, false)
	if room == null:
		return
	var ic: int = icon_index.get(sys, 0)
	draw_texture_rect_region(
		icons,
		Rect2(r.position + Vector2i((r.size.x - 9) / 2, 3), Vector2(9, 9)),
		Rect2(ic * 9, 0, 9, 9)
	)
	var eff := room.effective_level()
	for k in room.level:
		var y := r.end.y - 5 - k * 5
		var pip := Rect2(r.position.x + 5, y, r.size.x - 10, 3)
		if k < room.power:
			draw_rect(pip, Pixel.c("H"))
		elif k >= eff:
			draw_rect(pip, Pixel.c("U"))
		else:
			draw_rect(pip, Pixel.c("e"), false, 1.0)


func _draw_weapon_button(me: Ship, i: int, r: Rect2i) -> void:
	if i >= me.weapon_ids.size():
		return
	var w: Dictionary = ContentDB.weapons[me.weapon_ids[i]]
	var selected: bool = main.selected_weapon == i
	_draw_panel(r, selected)
	var powered := me.weapon_powered(i)
	var k := me.weapon_charge[i] / float(w.charge)
	var bar := Rect2(r.position.x + 4, r.end.y - 7, r.size.x - 8, 3)
	draw_rect(bar, Pixel.c("c"))
	var fill_col := Pixel.c("w") if k >= 1.0 else Pixel.c("v")
	if not powered:
		fill_col = Pixel.c("f")
	draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * k), 3)), fill_col)
	# power cost pips
	for p in int(w.power):
		draw_rect(
			Rect2(r.position.x + 4 + p * 5, r.end.y - 13, 4, 3),
			Pixel.c("H") if powered else Pixel.c("e")
		)
	if me.weapon_target[i] != "":
		_corners(
			Rect2i(r.end.x - 12, r.end.y - 16, 8, 8), Pixel.c("v") if i == 0 else Pixel.c("u"), 2
		)
