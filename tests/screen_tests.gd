extends RefCounted
## Screen size and UI size checks for tests/run_tests.gd, kept here so that
## file stays under the lint limit. Each takes the runner, whose check() records the result.


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


## Each font's outline strip is exactly its glyph strip grown a pixel each way, glyph for glyph.
static func font(t: SceneTree) -> void:
	_font_strips(t, "3x5", TextLayer.GLYPH_H)
	_font_strips(t, "4x6", TextLayer.FINE_H)
	fine_text(t)


static func _font_strips(t: SceneTree, name: String, h: int) -> void:
	var index: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://art/font_%s.json" % name)
	)
	var glyphs := (load("res://art/font_%s.png" % name) as Texture2D).get_image()
	var outline := (load("res://art/font_%s_outline.png" % name) as Texture2D).get_image()
	_check(t, outline.get_height() == h + 2, "%s outline strip is %d pixels tall" % [name, h + 2])
	_check(
		t,
		outline.get_width() == index.size() * TextLayer.OUTLINE_CELL,
		"%s outline strip has a slot for every glyph" % name
	)
	var bad: Array[String] = []
	for ch: String in index:
		if not _outline_matches(glyphs, outline, int(index[ch][0]), int(index[ch][1]), h):
			bad.append(ch)
	_check(
		t,
		bad.is_empty(),
		"every %s outline is its glyph grown by a pixel (%s)" % [name, ", ".join(bad)]
	)


## The finer text font: picked by scale, and never bigger than the 3x5 letters it replaces.
static func fine_text(t: SceneTree) -> void:
	var coarse: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://art/font_3x5.json")
	)
	var fine: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://art/font_4x6.json")
	)
	_check(t, fine.keys() == coarse.keys(), "the 4x6 font has every 3x5 glyph")
	var n := TextLayer.FINE_NUM
	var d := TextLayer.FINE_DEN
	var bad: Array[String] = []
	for ch: String in fine:
		var wf := int(fine[ch][1])
		var wc := int(coarse.get(ch, [0, 3])[1])
		# advance (letter + gap), and the outlined letter, at the largest fine pixel size
		if (wf + 1) * n > (wc + 1) * d or (wf + 2) * n > (wc + 2) * d:
			bad.append(ch)
	_check(t, bad.is_empty(), "no 4x6 letter is wider than its 3x5 one (%s)" % ", ".join(bad))
	_check(t, (TextLayer.FINE_H + 2) * n <= (TextLayer.GLYPH_H + 2) * d, "4x6 text is no taller")
	_check(t, (TextLayer.FINE_LINE) * n <= TextLayer.LINE * d, "4x6 lines are no further apart")
	_check(t, TextLayer.fine_px(1) == 0, "a 1x canvas keeps the 3x5 font")
	_check(
		t, TextLayer.fine_px(5) == 4 and TextLayer.fine_px(6) == 4, "4x6 pixels are 4 at 5x and 6x"
	)
	TextLayer.load_glyphs()
	var word := "MUSTER THE CREW, 14/20 HULL"
	var wide := TextLayer.text_width(word)
	var c := SubViewportContainer.new()
	var v := SubViewport.new()
	TextLayer.fit_canvas(c, v, 5)
	_check(t, c.stretch_shrink == 1, "fine text draws the canvas at screen size")
	_check(t, v.canvas_transform.get_scale() == Vector2(5, 5), "the art keeps its 5x scale")
	_check(t, TextLayer.text_width(word) < wide, "4x6 text measures narrower than 3x5")
	TextLayer.fit_canvas(c, v, 1)
	_check(t, c.stretch_shrink == 1 and v.canvas_transform.get_scale() == Vector2.ONE, "1x canvas")
	_check(t, TextLayer.text_width(word) == wide, "a 1x canvas measures in the 3x5 font")
	c.free()
	v.free()


## True when every pixel of the outline slot is set exactly where a glyph pixel is within one.
static func _outline_matches(glyphs: Image, outline: Image, slot: int, w: int, h: int) -> bool:
	for y in h + 2:
		for x in TextLayer.OUTLINE_CELL:
			var near := false
			for d in 9:
				var gx := x - 1 + d % 3 - 1
				var gy := y - 1 + d / 3 - 1
				if gx >= 0 and gx < w and gy >= 0 and gy < h:
					near = near or glyphs.get_pixel(slot * TextLayer.CELL + gx, gy).a > 0.0
			var lit := outline.get_pixel(slot * TextLayer.OUTLINE_CELL + x, y).a > 0.0
			if lit != near:
				return false
	return true


static func variants(screens: Dictionary) -> Dictionary:
	var out := {}
	for name: String in screens:
		var seen: Array[int] = []
		for step in range(GameSettings.UI_SIZE_MIN, GameSettings.UI_SIZE_MAX + 1):
			var scr := ScreenManager.compute(screens[name], step)
			if int(scr.scale) in seen:
				continue
			seen.append(int(scr.scale))
			out["%s at %dx" % [name, scr.scale]] = scr
	return out


## The fight layout fits with the real hulls of every playable ship against every enemy,
## with that ship's own systems and guns.
static func hud(t: SceneTree, screens: Dictionary) -> void:
	for name: String in screens:
		var scr: Dictionary = screens[name]
		var probs: Array[String] = []
		for pid in ShipRoster.playable():
			var player := _ship(pid)
			var s := Ship.from_content(pid, 0)
			var systems: Array[String] = []
			for sys in HudLayout.SYSTEM_ORDER:
				if s.system_room(sys):
					systems.append(sys)
			for id: String in ContentDB.ships:
				if ContentDB.ships[id].get("playable", false):
					continue
				var enemy := _ship(id)
				var l := HudLayout.build(
					scr,
					player.frame,
					enemy.frame,
					systems,
					s.weapon_ids.size(),
					player.used,
					enemy.used,
					bool(ContentDB.ships[id].get("siege_only", false))
				)
				for p in l.problems():
					probs.append("%s vs %s: %s" % [pid, id, p])
		print(
			(
				"  %-52s %s  canvas %dx%d  %s"
				% [name, scr.layout, scr.native.x, scr.native.y, "ok" if probs.is_empty() else ""]
			)
		)
		_check(t, probs.is_empty(), "%s layout: %s" % [name, probs.slice(0, 3)])


static func _ship(id: String) -> Dictionary:
	var c: Dictionary = ContentDB.ships[id]
	var frame := Vector2i(int(c.frame_size[0]), int(c.frame_size[1]))
	return {"frame": frame, "used": Pixel.used_rect(load(c.sprite), frame)}


## What the folded and unfolded Fold get, and how far the setting can move them.
static func ui_size(t: SceneTree) -> void:
	var cover := Vector2i(2520, 1080)
	var open := Vector2i(2184, 1968)
	var phone := Vector2i(2400, 1080)
	_check(t, ScreenManager.compute(cover).scale == 6, "the Fold cover screen is 6x on auto")
	_check(t, ScreenManager.compute(open).scale == 5, "the unfolded Fold stays 5x on auto")
	_check(t, ScreenManager.compute(phone).native == Vector2i(480, 216), "2400x1080 is 5x")
	_check(t, ScreenManager.compute(open, 1).scale == 6, "larger takes the unfolded Fold to 6x")
	_check(t, ScreenManager.compute(cover, 1).scale == 6, "larger never goes past what fits")
	_check(t, ScreenManager.compute(cover, -1).scale == 5, "smaller is one scale down")
	_check(t, ScreenManager.compute(Vector2i(600, 300), -1).scale == 1, "never below 1x")
	var tall := ScreenManager.compute(Vector2i(1968, 2184), 1)
	_check(t, tall.scale == 5, "a portrait Fold is too narrow to go larger")
	var narrow := ScreenManager.compute(Vector2i(1000, 2000), 1)
	_check(t, narrow.scale == narrow.auto_scale, "larger is never smaller than auto")
	var upright := ScreenManager.compute(Vector2i(1080, 2520))
	_check(t, upright.layout == "tall", "a phone held upright uses the Tall layout")
	_check(t, upright.native == Vector2i(216, 504), "at 5x, the pixel size it has sideways")
	_check(t, upright.hinge.size.x == 0, "with no fold to keep clear")
	_check(t, ScreenManager.compute(Vector2i(1080, 2520), 1).scale == 5, "and no larger step")
	_check(t, ScreenManager.compute(Vector2i(1968, 2184)).layout == "square", "a Fold stays Square")
	_check(
		t,
		(
			ScreenManager.change_reason("wide", "tall") == "UI_TURN_PAUSE"
			and ScreenManager.change_reason("wide", "square") == "UI_FOLD_PAUSE"
			and ScreenManager.change_reason("tall", "square") == "UI_FOLD_PAUSE"
		),
		"turning the phone says why the fight paused"
	)
	var tiny := ScreenManager.compute(Vector2i(300, 200))
	_check(t, tiny.scale == 1 and tiny.native == Vector2i(300, 200), "a tiny window is 1x")
	# the setting itself
	var s := GameSettings.new()
	for i in 5:
		s.adjust("ui_size", 1)
	_check(t, s.ui_size == GameSettings.UI_SIZE_MAX, "UI size stops at its largest step")
	for i in 9:
		s.adjust("ui_size", -1)
	_check(t, s.ui_size == GameSettings.UI_SIZE_MIN, "and at its smallest")
	var back := GameSettings.from_dict(s.to_dict())
	_check(t, back.ui_size == GameSettings.UI_SIZE_MIN, "UI size saves")
	_check(t, GameSettings.from_dict({"ui_size": 9}).ui_size == 1, "a bad UI size clamps")
	_check(t, GameSettings.from_dict({"ui_size": "big"}).ui_size == 0, "or falls back to auto")
	for f in ["settings_v1.json", "settings_v2.json", "settings_v3.json"]:
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://tests/fixtures/" + f)
		)
		var up := SaveService.upgrade(raw)
		var got := GameSettings.from_dict(up.get("data", {}))
		var want := 0 if f == "settings_v1.json" else -1
		_check(t, got.ui_size == want and got.shake == 0.25, "%s loads its UI size" % f)
		var lock: bool = f == "settings_v3.json"
		_check(t, got.force_landscape == lock, "%s loads landscape only as %s" % [f, lock])
	s.adjust("force_landscape", 1)
	_check(t, s.force_landscape and s.value("force_landscape") == 1.0, "Landscape only toggles")
	_check(t, GameSettings.from_dict(s.to_dict()).force_landscape, "and saves")
	_check(
		t, not GameSettings.from_dict({"force_landscape": 1}).force_landscape, "a bad one is off"
	)
	s.reset()
	_check(t, s.ui_size == 0, "Defaults puts UI size back on auto")
	_check(t, not s.force_landscape, "and lets the phone turn again")


## On the options screen: + and - change the real scale, a step that can't fit
## is refused, and Defaults goes back to auto. main is on the unfolded Fold.
static func options_flow(t: SceneTree, main: Node) -> void:
	var start: int = main.screen.scale
	_check(t, main.ui_size_text() == "%dX AUTO" % start, "UI size shows the scale and auto")
	_tap(main, main.menu_layout.button("more", "ui_size"))
	_check(t, main.screen.scale == start + 1, "+ makes everything a scale bigger")
	_check(t, main.menu == "options" and main.menu_layout.native == main.screen.native, "at once")
	_check(t, not main.option_can_step("ui_size", 1), "and stops where the layout would not fit")
	_tap(main, main.menu_layout.button("less", "ui_size"))
	_tap(main, main.menu_layout.button("less", "ui_size"))
	_check(t, main.screen.scale == start - 1 and main.settings.ui_size == -1, "- goes smaller")
	_tap(main, main.menu_layout.button("defaults"))
	_check(t, main.screen.scale == start and main.settings.ui_size == 0, "Defaults restores auto")


static func _tap(main: Node, b: Dictionary) -> void:
	main._tap(Vector2((b.rect as Rect2i).get_center()) * main.screen.scale, false)
