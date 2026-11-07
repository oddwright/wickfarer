class_name TextLayer
extends Node2D
## Text drawn in the pixel world with the 3x5 pixel font from the concept art,
## so it scales with the same whole-number pixels as everything else.
## Large text (titles) draws each font pixel as 2x2 canvas pixels, and the game
## title as 3x3.

const CELL := 5  ## glyph slot width in the font strip
const OUTLINE_CELL := CELL + 2  ## outline strip slot: the glyph grown a pixel each side
const GLYPH_H := 5
const LINE := 7

static var glyph_index: Dictionary = {}  ## char -> [slot, width]

var main: Node
var glyphs: Texture2D
var outline: Texture2D


func setup(main_node: Node) -> void:
	main = main_node
	glyphs = load("res://art/font_3x5.png")
	outline = load("res://art/font_3x5_outline.png")
	glyph_index = JSON.parse_string(FileAccess.get_file_as_string("res://art/font_3x5.json"))


static func _adv(ch: String) -> int:
	var g: Array = glyph_index.get(ch, [0, 3])
	return int(g[1]) + 1


static func text_width(s: String, k := 1) -> int:
	var w := 0
	for ch in s:
		w += _adv(ch)
	return maxi(0, w - 1) * k


static func _wrap(s: String, max_w: int, k: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var cur := ""
	for word in s.split(" "):
		var trial := word if cur == "" else cur + " " + word
		if cur != "" and text_width(trial, k) > max_w:
			lines.append(cur)
			cur = word
		else:
			cur = trial
	if cur != "":
		lines.append(cur)
	return lines


## native_pos is the text baseline (bottom of the letters), as before.
func _text(
	native_pos: Vector2,
	s: String,
	size_px: float,
	col: Color,
	align := HORIZONTAL_ALIGNMENT_LEFT,
	width := -1.0
) -> void:
	var k := 3 if size_px >= 15.0 else (2 if size_px >= 10.0 else 1)
	var up := s.to_upper()
	var lines: PackedStringArray = [up] if width <= 0 else _wrap(up, int(width), k)
	var y := int(round(native_pos.y)) - GLYPH_H * k - (lines.size() - 1) * LINE * k / 2
	for line in lines:
		var x := int(round(native_pos.x))
		var w := text_width(line, k)
		if width > 0:
			if align == HORIZONTAL_ALIGNMENT_CENTER:
				x += (int(width) - w) / 2
			elif align == HORIZONTAL_ALIGNMENT_RIGHT:
				x += int(width) - w
		# A one-pixel ink outline keeps text readable over stars, fire and panels. It fades with
		# the text; while a floater fades, the gap column between letters, where two outlines
		# overlap, is a little darker for a moment, which beats the outline vanishing at once.
		_line(line, Vector2i(x, y), k, Pixel.c("a", col.a), true)
		_line(line, Vector2i(x, y), k, col)
		y += LINE * k


func _line(s: String, at: Vector2i, k: int, col: Color, outlined := false) -> void:
	var x := at.x
	for ch in s:
		if glyph_index.has(ch):
			var g: Array = glyph_index[ch]
			# the outline slot is the glyph grown by one font pixel (pad) on every side
			var pad := 1 if outlined else 0
			var w := int(g[1]) + 2 * pad
			var h := GLYPH_H + 2 * pad
			draw_texture_rect_region(
				outline if outlined else glyphs,
				Rect2(x - pad * k, at.y - pad * k, w * k, h * k),
				Rect2(int(g[0]) * (OUTLINE_CELL if outlined else CELL), 0, w, h),
				col
			)
		x += _adv(ch) * k


func _draw() -> void:
	if main == null or main.layout == null:
		return
	var combat: Combat = main.combat
	var l: HudLayout = main.layout
	var me := combat.player()
	var foe := combat.enemy()
	var ink := Pixel.c("h")
	var quiet := Pixel.c("g")
	_text(
		Vector2(4, l.player_bar_y + 11),
		(
			"%s   %s %d/%d"
			% [tr(ContentDB.ships[me.content_id].name), tr("UI_HULL"), me.hull, me.max_hull]
		),
		6.5,
		ink
	)
	_text(
		Vector2(4, l.player_bar_y + 37),
		(
			"%s %d/%d    %s %d%%"
			% [
				tr("UI_POWER"),
				me.used_power(),
				me.available_power(),
				tr("UI_EVASION"),
				me.evasion()
			]
		),
		5.0,
		quiet
	)
	if combat.siege:
		SiegeView.draw_text(self, combat, l)
	else:
		_draw_foe(foe, l)
	for b in l.buttons:
		var r: Rect2i = b.rect
		match b.kind:
			"system":
				pass
			"weapon":
				var i := int(b.id)
				if i < me.weapon_ids.size():
					_text(
						Vector2(r.position.x + 15, r.position.y + 10),
						tr(ContentDB.weapons[me.weapon_ids[i]].name),
						5.5,
						ink
					)
			"crew", "muster":
				var label := tr("UI_CREW") if b.kind == "crew" else tr("UI_MUSTER")
				_text(
					Vector2(r.position.x, r.position.y + r.size.y / 2 + 3),
					label,
					5.0,
					ink,
					HORIZONTAL_ALIGNMENT_CENTER,
					r.size.x
				)
			"kindle":
				SiegeView.draw_button_text(self, combat, r)
			"flare":
				FightMarks.draw_button_text(self, me, r)
			"ward":
				_text(Vector2(r.position.x + 17, r.position.y + 25), tr("UI_WARD_UP"), 4.5, quiet)
				_text(Vector2(r.position.x + 17, r.position.y + 35), tr("UI_WARD_LOW"), 4.5, quiet)
	# cold and rented rooms get a word, so neither is read from colour alone
	for side in 2:
		for room in combat.ships[side].rooms:
			if room.warmth < Ship.COLD or room.rent > 0.0:
				var rr: Rect2i = main.world.room_rect(side, room)
				_text(
					Vector2(rr.position.x, rr.position.y + 7),
					tr("UI_RENT") if room.rent > 0.0 else tr("UI_COLD"),
					4.0,
					Pixel.c("j"),
					HORIZONTAL_ALIGNMENT_RIGHT,
					rr.size.x - 2
				)
	for f in main.floaters:
		var a := clampf(f.life / 0.4, 0.0, 1.0)
		var col: Color = f.color
		col.a = a
		_text(f.pos, f.text, 6.0, col, HORIZONTAL_ALIGNMENT_CENTER, 60)
	# prompts and hints
	var msg := ""
	if main.selected_weapon >= 0:
		msg = tr("UI_AIM_PROMPT")
	elif main.selected_crew >= 0:
		msg = tr("UI_MOVE_PROMPT")
	elif main.paused:
		msg = tr(main.pause_reason) if main.pause_reason != "" else tr("UI_PAUSED")
	elif combat.siege:
		msg = SiegeView.hint(combat)
	elif combat.time() < 15.0:
		msg = tr("UI_HINT")
	if msg != "" and combat.state == "fighting" and not main.coach_speaking():
		var mr := l.message_rect
		_text(
			Vector2(mr.position.x, mr.position.y + mr.size.y / 2 + 3),
			msg,
			6.0,
			Pixel.c("w"),
			HORIZONTAL_ALIGNMENT_CENTER,
			mr.size.x
		)
	# The menu says it, and so does a coach step that holds the clock ("time is stopped").
	var held: bool = main.tutorial != null and main.tutorial.holds()
	var said: bool = main.menu != "" or held or main.roster.open
	if main.paused and combat.state == "fighting" and not said:
		_text(
			Vector2(0, l.paused_y()),
			tr("UI_PAUSED"),
			14.0,
			Pixel.c("w"),
			HORIZONTAL_ALIGNMENT_CENTER,
			l.native.x
		)
	if combat.state != "fighting":
		var title := tr("UI_WON") if combat.state == "won" else tr("UI_LOST")
		if combat.siege and combat.state == "won":
			title = tr("UI_KINDLED")
		_text(
			Vector2(0, l.native.y / 2 - 12),
			title,
			12.0,
			Pixel.c("w"),
			HORIZONTAL_ALIGNMENT_CENTER,
			l.native.x
		)
		var ar := l.again_rect()
		_text(
			Vector2(ar.position.x, ar.position.y + 18),
			tr("UI_CONTINUE"),
			7.0,
			Pixel.c("w"),
			HORIZONTAL_ALIGNMENT_CENTER,
			ar.size.x
		)
		_text(
			Vector2(0, ar.end.y + 12),
			"%s %d" % [tr("UI_SEED"), combat.rng.run_seed],
			5.0,
			quiet,
			HORIZONTAL_ALIGNMENT_CENTER,
			l.native.x
		)
		if combat.state == "won":
			_draw_promotions(me, Vector2i(0, ar.end.y + 22), l.native.x)


## The enemy's name, hull and evasion, top right.
func _draw_foe(foe: Ship, l: HudLayout) -> void:
	var ink := Pixel.c("h")
	var quiet := Pixel.c("g")
	_text(
		Vector2(l.native.x - 34 - 200, 11),
		(
			"%s   %s %d/%d"
			% [tr(ContentDB.ships[foe.content_id].name), tr("UI_HULL"), foe.hull, foe.max_hull]
		),
		6.5,
		ink,
		HORIZONTAL_ALIGNMENT_RIGHT,
		200
	)
	var ev := foe.evasion()
	_text(
		Vector2(l.native.x - 34 - 200, 37),
		"%s %d%%" % [tr("UI_EVASION"), ev],
		5.0,
		quiet,
		HORIZONTAL_ALIGNMENT_RIGHT,
		200
	)


## The crew who earned a rank this fight; it is theirs once the player continues.
func _draw_promotions(me: Ship, at: Vector2i, width: int) -> void:
	var y := at.y
	for p in me.promotions().slice(0, 4):
		var c := me.crew_by_uid(int(p.uid))
		var line := (
			tr("UI_PROMOTED")
			% [tr(c.name), tr(Skills.rank_name(int(p.rank))), tr(Skills.spec(p.skill).name)]
		)
		_text(Vector2(at.x, y), line, 5.0, Pixel.c("v"), HORIZONTAL_ALIGNMENT_CENTER, width)
		y += 8
