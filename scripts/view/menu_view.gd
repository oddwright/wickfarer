class_name MenuView
extends TextLayer
## Draws the title menu, the pause menu, the options screen and the confirm
## screen. The title menu and options cover everything; the pause and confirm
## pages dim the game behind them. Like RunView it only reads state; taps go back to Main.

const SEGMENTS := 10  ## one per options step

var _shadow_tex: Dictionary = {}  ## ship id -> a locked hull's silhouette
## ship id -> its sprite. Held here because a texture loaded and dropped inside
## _draw() is freed before the frame renders, which draws a plain white box.
var _ship_tex: Dictionary = {}
var _info_cache: Dictionary = {}  ## "id:open:width" -> the info column's wrapped lines


func _draw() -> void:
	if main == null or main.menu == "" or main.menu_layout == null:
		return
	var l: MenuLayout = main.menu_layout
	# Options fills the screen too: its rows would tangle with the HUD text.
	if main.menu_base == "title" or main.menu == "options":
		draw_rect(Rect2(Vector2.ZERO, l.native), Pixel.c("a"))
		for s in main.world.stars:
			draw_rect(Rect2(s[0], Vector2.ONE), Pixel.c(s[1]))
	else:
		draw_rect(Rect2(Vector2.ZERO, l.native), Pixel.c("a", 0.9))
	match main.menu:
		"options":
			_draw_options(l)
		"confirm":
			_draw_confirm(l)
		"ship":
			_draw_ship(l)
		"depth", "log":
			_draw_profile_page(l)
		_:
			_draw_list(l)


## A phone held upright plays in a cramped stacked layout; an unfolded foldable,
## nearly square, doesn't, so it gets no nudge.
static func held_upright(window: Vector2i) -> bool:
	return window.y * 10 > window.x * 13


func _draw_list(l: MenuLayout) -> void:
	var r := l.title_rect
	var y := r.position.y + r.size.y / 2 + 7
	if main.menu == "title":
		_text(
			Vector2(r.position.x, y),
			tr("UI_GAME_TITLE"),
			15.0,
			Pixel.c("v"),
			HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x
		)
		_draw_ember(Vector2i(r.position.x + r.size.x / 2, y + 6))
		if MenuView.held_upright(main.window_size()):
			_text(
				Vector2(0, l.native.y - 6),
				tr("UI_ROTATE"),
				5.0,
				Pixel.c("g"),
				HORIZONTAL_ALIGNMENT_CENTER,
				l.native.x
			)
	else:
		_text(
			Vector2(r.position.x, y),
			tr("UI_PAUSED"),
			14.0,
			Pixel.c("w"),
			HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x
		)
	for b in l.buttons:
		_button(b.rect, tr("UI_MENU_" + str(b.id).to_upper()), true)


## The wrapped text rows of a page that fit in `height` pixels, as [text, y]
## pairs from the top. A blank line is a half-line gap. Once a row doesn't fit,
## nothing after it is drawn, so a long Wake Log ends cleanly at the bottom.
static func page_rows(lines: Array[String], width: int, height: int) -> Array[Array]:
	var out: Array[Array] = []
	var y := 0
	for line in lines:
		if line == "":
			y += LINE / 2
			continue
		for part in _wrap(line.to_upper(), width, 1):
			if y + LINE > height:
				return out
			out.append([part, y])
			y += LINE
	return out


## The Hush Depth picker or the Wake Log: a heading, wrapped lines under it,
## as many as fit, then the page's buttons.
func _draw_profile_page(l: MenuLayout) -> void:
	var r := l.title_rect
	var lines: Array[String] = []
	var heading := tr("UI_LOG_TITLE")
	if main.menu == "depth":
		var t := ProfilePages.depth_text(main.profile)
		heading = t[0]
		lines.append(t[1])
	else:
		lines = ProfilePages.log_lines(main.profile)
	_text(Vector2(r.position.x, r.position.y + 10), heading, 10.0, Pixel.c("w"))
	var top := r.position.y + 22
	for row: Array in page_rows(lines, r.size.x, r.end.y + 4 - top):
		_text(Vector2(r.position.x, top + int(row[1])), str(row[0]), 5.0, Pixel.c("h"))
	for b in l.buttons:
		var on := true
		if b.id == "depth_less":
			on = main.profile.depth > 0
		elif b.id == "depth_more":
			on = main.profile.depth < main.profile.depth_open
		_button(b.rect, tr("UI_MENU_" + str(b.id).to_upper()), on)


## A small lit ember under the title, the one warm thing on the screen.
func _draw_ember(c: Vector2i) -> void:
	var flicker := int(main.world.anim_time * 5.0) % 3
	draw_rect(Rect2(c.x - 1, c.y, 3, 3), Pixel.c("u"))
	draw_rect(Rect2(c.x, c.y - 1 - (flicker % 2), 1, 2), Pixel.c("w"))
	draw_rect(Rect2(c.x, c.y + 1, 1, 1), Pixel.c("x"))


func _draw_confirm(l: MenuLayout) -> void:
	var r := l.title_rect
	_text(
		Vector2(r.position.x, r.position.y + r.size.y / 2 + 3),
		tr("UI_CONFIRM_" + main.confirm_action.to_upper()),
		5.0,
		Pixel.c("h"),
		HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x
	)
	for b in l.buttons:
		var label := "UI_MENU_" + str(b.id).to_upper()
		if b.id == "yes":
			label = "UI_YES_" + main.confirm_action.to_upper()
		_button(b.rect, tr(label), true)


func _draw_ship(l: MenuLayout) -> void:
	var id: String = main.ships.picked()
	var c: Dictionary = ContentDB.ships[id]
	var open: bool = main.ships.is_open(id)
	var r := l.title_rect
	_text(
		Vector2(r.position.x, r.end.y),
		tr(c.name),
		10.0,
		Pixel.c("w") if open else Pixel.c("g"),
		HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x
	)
	_draw_hull_preview(l.preview_rect, id, open)
	_draw_ship_info(l.info_rect, id, open)
	_draw_pips(l.pips_rect)
	for b in l.buttons:
		match b.kind:
			"prev":
				_button(b.rect, "<", true)
			"next":
				_button(b.rect, ">", true)
			"launch":
				_button(b.rect, tr("UI_MENU_LAUNCH"), open)
			"back":
				_button(b.rect, tr("UI_MENU_BACK"), true)


## The hull centred on its drawn pixels, animated like in a fight. A locked
## hull is a flat silhouette: you see its shape, not its rooms.
func _draw_hull_preview(box: Rect2i, id: String, open: bool) -> void:
	var c: Dictionary = ContentDB.ships[id]
	var fs := Vector2i(int(c.frame_size[0]), int(c.frame_size[1]))
	var tex := _ship_texture(id)
	var used := Pixel.used_rect(tex, fs)
	var at := box.get_center() - used.get_center()
	if open:
		var frame := int(main.world.anim_time * 6.0) % 4
		draw_texture_rect_region(tex, Rect2(at, fs), Rect2(Vector2(fs.x * frame, 0), fs))
	else:
		draw_texture_rect_region(_shadow(id, fs), Rect2(at, fs), Rect2(Vector2.ZERO, fs))


func _ship_texture(id: String) -> Texture2D:
	if not _ship_tex.has(id):
		_ship_tex[id] = load(ContentDB.ships[id].sprite)
	return _ship_tex[id]


func _shadow(id: String, fs: Vector2i) -> Texture2D:
	if not _shadow_tex.has(id):
		var img := _ship_texture(id).get_image()
		if img.is_compressed():
			img.decompress()
		img = img.get_region(Rect2i(Vector2i.ZERO, fs))
		img.convert(Image.FORMAT_RGBA8)
		var ink := Pixel.c("c")
		for y in fs.y:
			for x in fs.x:
				if img.get_pixel(x, y).a > 0.0:
					img.set_pixel(x, y, ink)
		_shadow_tex[id] = ImageTexture.create_from_image(img)
	return _shadow_tex[id]


## The blurb, then one line per stat. A locked hull shows how to open it instead.
func _draw_ship_info(box: Rect2i, id: String, open: bool) -> void:
	var key := "%s:%s:%d" % [id, open, box.size.x]
	if not _info_cache.has(key):  # wrapping every frame is wasted work
		_info_cache[key] = ship_info_lines(id, open, box.size.x)
	var y := box.position.y + GLYPH_H
	for l: Array in _info_cache[key]:
		_text(Vector2(box.position.x, y), l[0], 5.0, Pixel.c(l[1]))
		y += LINE


## The info column's lines, wrapped to width: [text, colour key] each.
static func ship_info_lines(id: String, open: bool, width: int) -> Array[Array]:
	var lines: Array[Array] = []
	if open:
		for line in _wrap(_t(ContentDB.ships[id].blurb).to_upper(), width, 1):
			lines.append([line, "h"])
	else:
		lines.append([_t("UI_SHIP_LOCKED").to_upper(), "U"])
		for line in _wrap(_t(ShipRoster.unlock_hint(id)).to_upper(), width, 1):
			lines.append([line, "h"])
	lines.append(["", "h"])
	for stat in ship_stats(id, open):
		for line in _wrap(stat.to_upper(), width, 1):
			lines.append([line, "g" if open else "e"])
	return lines


## What a hull brings to a run, one translated line each. Unknown until it opens.
static func ship_stats(id: String, open := true) -> Array[String]:
	var c: Dictionary = ContentDB.ships[id]
	var guns: Array[String] = []
	for w: String in c.weapons:
		guns.append(_t(ContentDB.weapons[w].name))
	var vals: Array[String] = [
		str(int(c.hull)), str(int(c.reactor)), str((c.crew as Array).size()), ", ".join(guns)
	]
	var out: Array[String] = []
	var keys: Array[String] = ["UI_SHIP_HULL", "UI_SHIP_REACTOR", "UI_SHIP_CREW", "UI_SHIP_GUNS"]
	for i in keys.size():
		out.append(_t(keys[i]) % (vals[i] if open else "?"))
	return out


static func _t(key: String) -> String:
	return str(TranslationServer.translate(key))


## One dot per hull, the shown one lit. Decoration: the arrows and swipes move.
func _draw_pips(box: Rect2i) -> void:
	var ids := ShipRoster.playable()
	var x0 := box.get_center().x - (ids.size() * 6 - 2) / 2
	for i in ids.size():
		var col := Pixel.c("v") if i == main.ships.pick else Pixel.c("d")
		draw_rect(Rect2(x0 + i * 6, box.get_center().y - 2, 4, 4), col)


func _draw_options(l: MenuLayout) -> void:
	var r := l.title_rect
	_text(Vector2(r.position.x, r.end.y), tr("UI_MENU_OPTIONS"), 10.0, Pixel.c("w"))
	var s: GameSettings = main.settings
	for row in l.rows:
		var id: String = row.id
		_text(Vector2(row.label_at), tr("UI_OPT_" + id.to_upper()), 5.0, Pixel.c("h"))
		if (row.bar as Rect2i).size.x > 0:
			_draw_level(row.bar, s.value(id))
		if (row.value as Rect2i).size.x > 0:
			var v: Rect2i = row.value
			var y := v.position.y + v.size.y / 2 + 3
			_text(
				Vector2(v.position.x, y),
				main.stepper_text(id),
				5.0,
				Pixel.c("w"),
				HORIZONTAL_ALIGNMENT_CENTER,
				v.size.x
			)
	for b in l.buttons:
		match b.kind:
			"less":
				_button(b.rect, "-", main.option_can_step(str(b.id), -1))
			"more":
				_button(b.rect, "+", main.option_can_step(str(b.id), 1))
			"toggle":
				var on := s.value(b.id) > 0.0
				_button(b.rect, tr("UI_ON") if on else tr("UI_OFF"), on)
			"defaults":
				_button(b.rect, tr("UI_MENU_DEFAULTS"), true)
			"back":
				_button(b.rect, tr("UI_MENU_BACK"), true)


## Ten segments, lit up to the level; "off" is written over an empty bar so
## zero isn't read from colour alone.
func _draw_level(bar: Rect2i, v: float) -> void:
	var lit := roundi(v * SEGMENTS)
	var seg_w := float(bar.size.x + 1) / SEGMENTS
	for i in SEGMENTS:
		var x0 := bar.position.x + int(i * seg_w)
		var x1 := bar.position.x + int((i + 1) * seg_w) - 1
		var col := Pixel.c("v") if i < lit else Pixel.c("c")
		draw_rect(Rect2(x0, bar.position.y, maxi(1, x1 - x0), bar.size.y), col)
	if lit == 0:
		_text(
			Vector2(bar.position.x, bar.end.y),
			tr("UI_OFF"),
			5.0,
			Pixel.c("g"),
			HORIZONTAL_ALIGNMENT_CENTER,
			bar.size.x
		)


func _button(r: Rect2i, label: String, active: bool) -> void:
	Pixel.panel(self, r, active)
	var col := Pixel.c("w") if active else Pixel.c("g")
	var y := r.position.y + r.size.y / 2 + 3
	_text(Vector2(r.position.x, y), label, 5.0, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
