class_name MenuView
extends TextLayer
## Draws the title menu, the pause menu, the options screen and the confirm
## screen. The title menu and options cover everything; the pause and confirm
## pages dim the game behind them. Like RunView it only reads state; taps go back to Main.

const SEGMENTS := 10  ## one per options step


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
	var y := r.position.y + 22
	for line in lines:
		for part in _wrap(line.to_upper(), r.size.x, 1):
			if y + LINE > r.end.y + 4:
				break
			_text(Vector2(r.position.x, y), part, 5.0, Pixel.c("h"))
			y += LINE
		if line == "":
			y += LINE / 2
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
