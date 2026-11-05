extends RefCounted
## Menu checks for tests/run_tests.gd, kept here so that file stays under the
## lint limit. Each takes the runner, whose check() records the result.


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


static func screens(t: SceneTree, screen_sizes: Dictionary) -> void:
	var pf := Vector2i(236, 76)
	var ef := Vector2i(196, 66)
	var pages := {
		"title": ["continue", "new_run", "options", "quit"],
		"title, no save": ["new_run", "options", "quit"],
		"pause": ["resume", "options", "abandon", "to_title"],
		"confirm": ["yes", "no"],
		"options": [],
	}
	for name: String in screen_sizes:
		var scr := ScreenManager.compute(screen_sizes[name])
		var probs: Array[String] = []
		for page: String in pages:
			var ids: Array[String] = []
			ids.assign(pages[page])
			var l := MenuLayout.build(scr, page.get_slice(",", 0), ids)
			for p in l.problems():
				probs.append("%s: %s" % [page, p])
			if l.buttons.is_empty():
				probs.append("%s has no buttons" % page)
		var opts := MenuLayout.build(scr, "options")
		for id in MenuLayout.AUDIO_ROWS + MenuLayout.FEEL_ROWS:
			var has := (
				not opts.button("toggle", id).is_empty() or not opts.button("more", id).is_empty()
			)
			if not has:
				probs.append("options has no control for %s" % id)
		# the menu button is on every fight and run screen, clear of the fold
		var hud := HudLayout.build(scr, pf, ef, HudLayout.SYSTEM_ORDER, 2)
		var run_l := RunLayout.build(scr, Run.create(1).chart, "chart")
		for l: Variant in [hud, run_l]:
			var r: Rect2i = l.menu_rect
			if r.size.x < 10 or r.size.y < 10:
				probs.append("a screen has no menu button")
			elif scr.hinge.size.x > 0 and r.intersects(scr.hinge):
				probs.append("the menu button sits on the fold")
		_check(t, probs.is_empty(), "%s menus: %s" % [name, probs.slice(0, 4)])


static func options_adjust(t: SceneTree) -> void:
	var s := GameSettings.new()
	s.adjust("Master", -1)
	_check(t, is_equal_approx(s.volume.Master, 0.7), "- lowers a volume one step")
	for i in 20:
		s.adjust("Music", -1)
	_check(t, s.volume.Music == 0.0, "volumes stop at off")
	for i in 10:
		s.adjust("Music", 1)
	_check(t, s.volume.Music == 1.0, "ten taps from off is exactly full, no drift")
	s.adjust("haptics", 1)
	_check(t, s.haptics == 1.0, "levels stop at full")
	s.adjust("shake", -1)
	_check(t, is_equal_approx(s.value("shake"), 0.9), "shake steps too")
	s.adjust("hitstop", 1)
	s.adjust("reduce_flashing", -1)
	_check(t, not s.hitstop and s.reduce_flashing, "toggles flip whichever way they are tapped")
	_check(t, s.value("hitstop") == 0.0 and s.value("reduce_flashing") == 1.0, "and read as 0 or 1")
	s.reset()
	var d := GameSettings.new()
	_check(t, s.to_dict() == d.to_dict(), "defaults restores everything")


## Taps a menu button the way a finger would, in window pixels.
static func _tap_menu(main: Node, id: String) -> bool:
	var l: MenuLayout = main.menu_layout
	for b in l.buttons:
		if str(b.id) == id or b.kind == id:
			var c: Vector2 = Vector2((b.rect as Rect2i).get_center()) * main.screen.scale
			main._tap(c, false)
			return true
	return false


static func flow(t: SceneTree) -> void:
	var dir := "user://test_saves"
	DirAccess.make_dir_recursive_absolute(dir)
	for slot in ["run", GameSettings.SLOT]:
		SaveService.erase(slot, dir)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_dir = dir
	t.root.size = Vector2i(2184, 1968)  # the unfolded Fold, the main test device
	t.root.add_child(main)
	_check(t, main.menu == "title", "the app opens on the title menu")
	_check(t, main.menu_items("title") == ["new_run", "options", "quit"], "no save, no Continue")
	_check(t, not main.world.visible and not main.run_view.visible, "the title hides the game")
	_tap_menu(main, "new_run")
	_check(t, main.menu == "" and main.run != null, "New run starts a run")
	_check(t, main.run_view.visible, "on the chart")
	_tap_rect(main, main.run_layout.menu_rect)
	_check(
		t, main.menu == "pause" and main.run_view.visible, "the chart's menu button pauses over it"
	)
	main.back()
	_check(t, main.menu == "", "back resumes")
	# a fight: the pause menu stops the clock and puts it back as it was
	var r: Run = main.run
	r._start_fight("ashmarket_skiff")
	main._set_run(r)
	main._process(0.2)
	var t0: float = main.combat.time()
	_check(t, t0 > 0.0, "the fight runs")
	_tap_rect(main, main.layout.menu_rect)
	_check(t, main.menu == "pause" and main.paused, "the fight's menu button pauses it")
	main._process(1.0)
	_check(t, main.combat.time() == t0, "no ticks behind the pause menu")
	_tap_menu(main, "resume")
	_check(t, main.menu == "" and not main.paused, "Resume carries on unpaused")
	main.paused = true
	main.back()
	main.back()
	_check(t, main.paused, "a fight paused before the menu stays paused")
	# options, from the pause menu
	main.back()
	_tap_menu(main, "options")
	_check(t, main.menu == "options", "Options opens")
	var b: Dictionary = main.menu_layout.button("less", "Master")
	_tap_menu_button(main, b)
	_check(t, is_equal_approx(main.settings.volume.Master, 0.7), "- turns the volume down")
	_check(
		t,
		is_equal_approx(GameSettings.load_or_default(dir).volume.Master, 0.7),
		"and it is saved at once"
	)
	_tap_menu_button(main, main.menu_layout.button("toggle", "reduce_flashing"))
	_check(t, main.settings.reduce_flashing, "toggles work")
	_tap_menu(main, "defaults")
	_check(t, main.settings.volume.Master == 0.8 and not main.settings.reduce_flashing, "Defaults")
	_tap_menu(main, "back")
	_check(t, main.menu == "pause", "Back returns to the pause menu")
	# quit to the title and continue
	_tap_menu(main, "to_title")
	_check(t, main.menu == "title" and not main.world.visible, "Quit to menu shows the title")
	_check(t, main.menu_items("title")[0] == "continue", "with Continue")
	_check(t, SaveService.read("run", dir).has("run"), "and the run is saved")
	_tap_menu(main, "continue")
	_check(
		t,
		main.menu == "" and main.world.visible and main.paused,
		"Continue lands paused in the fight"
	)
	# new run over a saved one asks first
	main.back()
	_tap_menu(main, "to_title")
	_tap_menu(main, "new_run")
	_check(
		t, main.menu == "confirm" and main.confirm_action == "new_run", "New run over a save asks"
	)
	_tap_menu(main, "no")
	_check(t, main.menu == "title" and main.run == r, "No keeps the run")
	# abandon
	_tap_menu(main, "continue")
	main.back()
	_tap_menu(main, "abandon")
	_tap_menu(main, "yes")
	_check(t, main.menu == "title" and main.run == null, "Abandon ends the run")
	_check(t, not SaveService.read("run", dir).has("run"), "and deletes its save")
	_check(t, main.menu_items("title")[0] == "new_run", "so there is nothing to continue")
	# a fold while the pause menu is open still leaves the fight paused
	_tap_menu(main, "new_run")
	var r2: Run = main.run
	r2._start_fight("ashmarket_skiff")
	main._set_run(r2)
	check_fold_pause(t, main)
	# after a won fight, Quit to menu and Continue leave nothing paused
	main.combat.state = "won"
	main.back()
	_tap_menu(main, "to_title")
	_tap_menu(main, "continue")
	_check(t, not main.paused, "Continue after a won fight is not left paused")
	# a lost run can't be continued or abandoned from the menus
	r2.state = "lost"
	main.combat = null
	main._enter_screen()
	main.back()
	_check(t, not main.menu_items("pause").has("abandon"), "no Abandon on a lost run")
	_tap_menu(main, "to_title")
	_check(t, main.run == null, "Quit to menu after a loss drops the run")
	_check(t, main.menu_items("title")[0] == "new_run", "so the title has no Continue")
	main.queue_free()
	for slot in ["run", GameSettings.SLOT]:
		SaveService.erase(slot, dir)


static func _tap_menu_button(main: Node, b: Dictionary) -> void:
	var c: Vector2 = Vector2((b.rect as Rect2i).get_center()) * main.screen.scale
	main._tap(c, false)


static func _tap_rect(main: Node, r: Rect2i) -> void:
	main._tap(Vector2(r.get_center()) * main.screen.scale, false)


static func check_fold_pause(t: SceneTree, main: Node) -> void:
	main.paused = false
	main.back()
	main._pause("UI_FOLD_PAUSE")  # what _on_resize does when the layout changes mid-fight
	main.back()
	_check(
		t, main.menu == "" and main.paused, "a fold during the pause menu keeps the fight paused"
	)
