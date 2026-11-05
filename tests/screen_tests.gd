extends RefCounted
## Screen size and UI size checks for tests/run_tests.gd, kept here so that
## file stays under the lint limit. Each takes the runner, whose check() records the result.


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


## Every screen at every UI size the setting can reach on it, keyed "name at Nx",
## so layout checks cover the scales players can actually pick.
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


## The fight layout fits with the real hulls of the player's ship against every enemy.
static func hud(t: SceneTree, screens: Dictionary) -> void:
	var player := _ship("tallow_wren")
	for name: String in screens:
		var scr: Dictionary = screens[name]
		var probs: Array[String] = []
		for id: String in ContentDB.ships:
			if id == "tallow_wren":
				continue
			var enemy := _ship(id)
			var l := HudLayout.build(
				scr, player.frame, enemy.frame, HudLayout.SYSTEM_ORDER, 2, player.used, enemy.used
			)
			for p in l.problems():
				probs.append("vs %s: %s" % [id, p])
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
	_check(t, ScreenManager.compute(cover, -2).scale == 4, "and two")
	_check(t, ScreenManager.compute(Vector2i(600, 300), -2).scale == 1, "never below 1x")
	var tall := ScreenManager.compute(Vector2i(1968, 2184), 1)
	_check(t, tall.scale == 5, "a portrait Fold is too narrow to go larger")
	var narrow := ScreenManager.compute(Vector2i(1000, 2000), 1)
	_check(t, narrow.scale == narrow.auto_scale, "larger is never smaller than auto")
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
	for f in ["settings_v1.json", "settings_v2.json"]:
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://tests/fixtures/" + f)
		)
		var up := SaveService.upgrade(raw)
		var got := GameSettings.from_dict(up.get("data", {}))
		var want := 0 if f == "settings_v1.json" else -1
		_check(t, got.ui_size == want and got.shake == 0.25, "%s loads its UI size" % f)
	s.reset()
	_check(t, s.ui_size == 0, "Defaults puts UI size back on auto")


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
