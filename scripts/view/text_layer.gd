class_name TextLayer
extends Node2D
## Text drawn in the pixel world. Layout works in native (art) pixels against the 3x5 font's
## metrics. On screens at 3x or more the letters themselves come from a finer 4x6 font, each
## font pixel a whole number of screen pixels (4 at 5x and 6x), so text stays pixel text but
## reads more easily; the art keeps its own scale. A 4x6 letter and its outline never take more
## room than the 3x5 letter it replaces, so anything laid out for the 3x5 font still fits.
## Large text (titles) draws each font pixel 2x2, and the game title 3x3.
## On a screen-size canvas the art is scaled by the canvas transform, which costs more fill than
## stretching a native-size texture; it is the price of letters finer than the art.

const CELL := 5  ## glyph slot width in the font strip
const OUTLINE_CELL := CELL + 2  ## outline strip slot: the glyph grown a pixel each side
const GLYPH_H := 5  ## layout height of a line of text, in native pixels at k = 1
const LINE := 7  ## layout line step, in native pixels at k = 1
const FINE_H := 6
const FINE_LINE := 8
## Screen pixels per fine font pixel are at most FINE_NUM/FINE_DEN of the scale, so a 4-wide
## letter plus its gap (5) is never wider than a 3-wide 3x5 one (4), nor 6 rows taller than 5.
const FINE_NUM := 4
const FINE_DEN := 5

static var glyph_index: Dictionary = {}  ## char -> [slot, width], 3x5 font
static var fine_index: Dictionary = {}  ## char -> [slot, width], 4x6 font
static var px_scale := 1  ## screen pixels per native pixel
static var font_px := 0  ## screen pixels per 4x6 font pixel; 0 draws the 3x5 font

var main: Node
var glyphs: Texture2D
var outline: Texture2D
var fine_glyphs: Texture2D
var fine_outline: Texture2D


func setup(main_node: Node) -> void:
	main = main_node
	glyphs = load("res://art/font_3x5.png")
	outline = load("res://art/font_3x5_outline.png")
	fine_glyphs = load("res://art/font_4x6.png")
	fine_outline = load("res://art/font_4x6_outline.png")
	load_glyphs()


## Glyph widths, so layouts can measure text before any layer is set up.
static func load_glyphs() -> void:
	if glyph_index.is_empty():
		glyph_index = JSON.parse_string(FileAccess.get_file_as_string("res://art/font_3x5.json"))
	if fine_index.is_empty():
		fine_index = JSON.parse_string(FileAccess.get_file_as_string("res://art/font_4x6.json"))


## Picks the font for a canvas scale. Returns true when the fine font is on: the canvas must then
## be drawn at screen resolution with the scale as its transform, since fine letters fall
## between native pixels. Otherwise it stays at native size and text draws in native pixels.
static func configure(scale: int) -> bool:
	font_px = fine_px(scale)
	px_scale = scale if font_px > 0 else 1
	return font_px > 0


## Sets up the game canvas for a scale. With fine text it is drawn at screen resolution and the
## art is scaled by the canvas transform instead of by stretching a native-size texture; art
## sits on whole native pixels (see Pixel.frame and Pixel.line), so it looks the same.
static func fit_canvas(container: SubViewportContainer, viewport: SubViewport, scale: int) -> void:
	var fine := configure(scale)
	container.stretch_shrink = 1 if fine else scale
	viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * px_scale)


## Screen pixels per 4x6 font pixel at a canvas scale, or 0 when the 3x5 font stays: below 3x a
## 4x6 pixel would be a single screen pixel, too small to read.
static func fine_px(scale: int) -> int:
	var px := (scale * FINE_NUM) / FINE_DEN
	return px if px >= 2 else 0


static func _fine() -> bool:
	return font_px > 0 and not fine_index.is_empty()


## Advance of one letter in font pixels, gap included.
static func _adv(ch: String, index: Dictionary) -> int:
	var g: Array = index.get(ch, [0, 3])
	return int(g[1]) + 1


## Width of a line in font pixels.
static func _px_width(s: String, index: Dictionary) -> int:
	var w := 0
	for ch in s:
		w += _adv(ch, index)
	return maxi(0, w - 1)


## Width of a line in native pixels, always measured in the 3x5 font so layouts are the same on
## every screen; fine text, drawn inside that room, never needs more.
static func text_width(s: String, k := 1) -> int:
	return _px_width(s, glyph_index) * k


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
	var fine := _fine()
	var index := fine_index if fine else glyph_index
	var u := (font_px if fine else px_scale) * k  # screen pixels per font pixel
	var h := FINE_H if fine else GLYPH_H
	var step := (FINE_LINE if fine else LINE) * u
	# Letters are centred where the 3x5 ones were (for 3x5 text this is the old top exactly), so
	# layouts made for them still line up.
	var y := roundi(native_pos.y * px_scale) - (GLYPH_H * k * px_scale + h * u) / 2
	y -= (lines.size() - 1) * step / 2
	var left := roundi(native_pos.x * px_scale)
	var box := roundi(width * px_scale)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / px_scale)
	for line in lines:
		var x := left
		var w := _px_width(line, index) * u
		if width > 0:
			if align == HORIZONTAL_ALIGNMENT_CENTER:
				x += (box - w) / 2
			elif align == HORIZONTAL_ALIGNMENT_RIGHT:
				x += box - w
		# A one-pixel ink outline keeps text readable over stars, fire and panels. It fades with
		# the text; while a floater fades, the gap column between letters, where two outlines
		# overlap, is a little darker for a moment, which beats the outline vanishing at once.
		var at := Vector2i(x, y)
		var ink := Pixel.c("a", col.a)
		_line(line, at, u, ink, fine_outline if fine else outline, index, h, OUTLINE_CELL, 1)
		_line(line, at, u, col, fine_glyphs if fine else glyphs, index, h, CELL, 0)
		y += step
	draw_set_transform(Vector2.ZERO)


## Draws one line from a glyph strip in screen pixels (the caller has set the transform), u per
## font pixel. An outline strip's slots are the glyphs grown by pad pixels on every side.
func _line(
	s: String,
	at: Vector2i,
	u: int,
	col: Color,
	tex: Texture2D,
	index: Dictionary,
	h: int,
	slot: int,
	pad: int
) -> void:
	var x := at.x
	for ch in s:
		if index.has(ch):
			var g: Array = index[ch]
			var w := int(g[1]) + 2 * pad
			draw_texture_rect_region(
				tex,
				Rect2(x - pad * u, at.y - pad * u, w * u, (h + 2 * pad) * u),
				Rect2(int(g[0]) * slot, 0, w, h + 2 * pad),
				col
			)
		x += _adv(ch, index) * u


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
				combat.evasion(0)
			]
		),
		5.0,
		quiet
	)
	if combat.siege:
		SiegeView.draw_text(self, combat, l)
	else:
		_draw_foe(combat, l)
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
	else:
		msg = rule_text(combat)  # a Warden's twist, once the hint has gone
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
func _draw_foe(combat: Combat, l: HudLayout) -> void:
	var foe := combat.enemy()
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
	var ev := combat.evasion(1)
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


## The Warden's rule, for the message line; "" in an ordinary fight. Each rule's
## line is RULE_<RULE>; the tide's counts down to its next turn.
static func rule_text(combat: Combat) -> String:
	if combat.rule() == "":
		return ""
	var line := TranslationServer.translate(rule_key(combat.rule()))
	return line % ceili(combat.tide_eta()) if combat.rule() == "tide" else line


static func rule_key(rule: String) -> String:
	return "RULE_" + rule.to_upper()
