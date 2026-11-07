class_name CrewView
extends TextLayer
## Draws the crew roster over a paused fight: each crew member's name, role,
## health and skills, a button for their post, and the station picker.
## Like the other views it only reads state; taps go back to Main.

const SKILL_PIP := 3

var drawn_open := false  ## whether the last frame drew the roster, so closing clears it


func _process(_delta: float) -> void:
	if needs_redraw():
		queue_redraw()


## While the roster is open, and once more after it closes to clear it away.
func needs_redraw() -> bool:
	return main != null and (main.roster.open or drawn_open)


func _draw() -> void:
	drawn_open = false
	if main == null or not main.roster.open or main.combat == null:
		return
	var l: CrewLayout = main.roster.layout
	if l == null:
		return
	drawn_open = true
	var me: Ship = main.combat.player()
	draw_rect(Rect2(Vector2.ZERO, l.native), Pixel.c("a", 0.93))
	var crew: Array[Crew] = main.roster.crew()
	var hint := tr("UI_ROSTER_HINT")
	if main.roster.pick >= 0 and main.roster.pick < crew.size():
		hint = tr("UI_PICK_POST") % tr(crew[main.roster.pick].name)
	_text(
		Vector2(l.title_rect.position.x, l.title_rect.end.y),
		tr("UI_ROSTER_TITLE"),
		5.0,
		Pixel.c("w")
	)
	_text(
		Vector2(l.hint_rect.position.x, l.hint_rect.end.y),
		hint,
		5.0,
		Pixel.c("v"),
		HORIZONTAL_ALIGNMENT_RIGHT,
		l.hint_rect.size.x
	)
	for i in mini(crew.size(), l.rows.size()):
		_draw_row(me, crew[i], l.rows[i])
	var picks: Array[String] = main.roster.picks()
	var current := ""
	if main.roster.pick >= 0 and main.roster.pick < crew.size():
		current = crew[main.roster.pick].post
	for b in l.buttons:
		var r: Rect2i = b.rect
		match b.kind:
			"post":
				var i := int(b.id)
				if i < crew.size():
					_post_button(me, r, crew[i].post, me.role_of(crew[i]), main.roster.pick == i)
			"pick":
				var id: String = picks[int(b.id)]
				_post_button(me, r, id, "", id == current)
			"close":
				_button(r, tr("UI_CLOSE"), false)
			"muster":
				_button(r, tr("UI_MUSTER"), true)


func _draw_row(me: Ship, c: Crew, r: Rect2i) -> void:
	draw_rect(Rect2(r), Pixel.c("b", 0.8))
	var tex: Texture2D = main.world.crew_tex.get(c.species + ":0")
	if tex:
		draw_texture_rect_region(
			tex,
			Rect2(r.position + Vector2i(1, 2), WorldView.CREW_CELL),
			Rect2(Vector2.ZERO, WorldView.CREW_CELL)
		)
	var x := r.position.x + 19
	_text(Vector2(x, r.position.y + 7), tr(c.name), 5.0, Pixel.c("w"))
	var name_w := text_width(tr(c.name).to_upper()) + 5
	_text(Vector2(x + name_w, r.position.y + 7), tr(me.role_of(c)), 5.0, Pixel.c("g"))
	# health
	var hp_w := r.end.x - 4 - x
	draw_rect(Rect2(x, r.position.y + 9, hp_w, 1), Pixel.c("r"))
	var hp_col := Pixel.c("H") if c.hp > c.max_hp * 0.35 else Pixel.c("U")
	draw_rect(Rect2(x, r.position.y + 9, maxf(1.0, roundf(hp_w * c.hp / c.max_hp)), 1), hp_col)
	# skills: a short name, then one pip per rank
	var ids := Skills.ids()
	var cell := (r.end.x - x) / maxi(1, ids.size())
	for k in ids.size():
		_draw_skill(c, ids[k], Vector2i(x + k * cell, r.position.y + 12))


## Banked ranks are solid; a rank earned this fight (banked once it ends)
## blinks; a line underneath shows the way to the next rank.
func _draw_skill(c: Crew, skill: String, at: Vector2i) -> void:
	_text(Vector2(at.x, at.y + 5), tr(Skills.spec(skill).short), 5.0, Pixel.c("g"))
	var px := at.x + 15
	var have := c.rank(skill)
	var earned := c.earned_rank(skill)
	var blink := int(main.world.anim_time * 3.0) % 2 == 0
	for k in Skills.MAX_RANK:
		var pip := Rect2(px + k * (SKILL_PIP + 1), at.y, SKILL_PIP, SKILL_PIP)
		if k < have:
			draw_rect(pip, Pixel.c("v"))
		elif k < earned:
			draw_rect(pip, Pixel.c("v") if blink else Pixel.c("e"))
		else:
			Pixel.frame(self, Rect2i(pip), Pixel.c("e"))
	if earned < Skills.MAX_RANK:
		var lo := Skills.xp_for_rank(earned)
		var hi := Skills.xp_for_rank(earned + 1)
		var span := SKILL_PIP * Skills.MAX_RANK + Skills.MAX_RANK - 1
		var k := clampf((c.practice(skill) - lo) / maxf(1.0, hi - lo), 0.0, 1.0)
		draw_rect(Rect2(px, at.y + 5, span, 1), Pixel.c("c"))
		draw_rect(Rect2(px, at.y + 5, roundf(span * k), 1), Pixel.c("u"))


## A station button: its icon, and a role word underneath when given.
func _post_button(me: Ship, r: Rect2i, room_id: String, role: String, active: bool) -> void:
	Pixel.panel(self, r, active)
	var room := me.room(room_id)
	var icon_y := r.position.y + (3 if role != "" else (r.size.y - 9) / 2)
	if room and room.system != "":
		var idx: int = main.world.icon_index.get(room.system, -1)
		if idx >= 0:
			draw_texture_rect_region(
				main.world.icons,
				Rect2(Vector2(r.position.x + (r.size.x - 9) / 2, icon_y), Vector2(9, 9)),
				Rect2(idx * 9, 0, 9, 9)
			)
	else:
		var word := "-" if room else tr("UI_NO_POST")  # "-": a post with no station
		_text(
			Vector2(r.position.x, icon_y + 7),
			word,
			5.0,
			Pixel.c("g"),
			HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x
		)
	if role != "":
		_text(
			Vector2(r.position.x, r.end.y - 3),
			tr(role),
			4.5,
			Pixel.c("w") if active else Pixel.c("g"),
			HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x
		)


func _button(r: Rect2i, label: String, active: bool) -> void:
	Pixel.panel(self, r, active)
	var col := Pixel.c("w") if active else Pixel.c("g")
	var y := r.position.y + r.size.y / 2 + 3
	_text(Vector2(r.position.x, y), label, 5.0, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
