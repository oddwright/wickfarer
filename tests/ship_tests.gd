extends RefCounted
## Ship select checks for tests/run_tests.gd: the roster, its data rules, the
## select screen on every device size, and the flow from the title to a run.


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


## Taps a menu button by kind, the way a finger would.
static func _tap(main: Node, kind: String) -> void:
	var b: Dictionary = main.menu_layout.button(kind)
	if b.is_empty():
		for o in main.menu_layout.buttons:
			if str(o.id) == kind:
				b = o
	main._tap(Vector2((b.rect as Rect2i).get_center()) * main.screen.scale, false)


## Which hulls can be picked, which are open, and what the data must hold.
static func roster(t: SceneTree) -> void:
	var ids := ShipRoster.playable()
	_check(
		t, ids.size() >= 3 and ids[0] == "tallow_wren", "three hulls, the Wren first: %s" % [ids]
	)
	_check(t, not ids.has("ashmarket_cutter"), "enemy hulls can't be picked")
	_check(t, ShipRoster.default_ship() == "tallow_wren", "the Wren is open from the start")
	for id in ids:
		var key := str(ContentDB.ships[id].unlock)
		var open := ShipRoster.is_unlocked(id, [])
		_check(t, open == (key == ""), "%s is locked only by its unlock id" % id)
		if key != "":
			_check(t, ShipRoster.is_unlocked(id, [key]), "%s opens with %s" % [id, key])
	_check(t, not ShipRoster.is_unlocked("ashmarket_cutter", []), "an enemy hull is never open")
	var bad: Array[String] = []
	var s: Dictionary = ContentDB.ships.tallow_wren.duplicate(true)
	s.blurb = "NO_SUCH_KEY"
	s.frame_size = [300, 76]
	ContentDB._validate_playable("bad", s, bad)
	_check(t, bad.size() == 2, "a missing blurb and an oversized frame are caught")
	for id in ids:
		var key := str(ContentDB.ships[id].unlock)
		if key != "":
			_check(t, ShipRoster.unlock_hint(id) != "", "%s says how to open it" % id)
	bad.clear()
	s.erase("unlock")
	ContentDB._validate_playable("bad", s, bad)
	_check(t, bad.any(func(e: String) -> bool: return "unlock" in e), "a missing unlock is caught")
	_torch_captain(t)
	_preview_texture_lives(t)
	for id in ids:
		var run := Run.create(7, id)
		_check(t, run.ship.content_id == id and not run.ship.is_dead(), "a run starts in %s" % id)
		var back := Run.from_dict(JSON.parse_string(JsonUtil.s(run.to_dict())))
		_check(t, back.ship.content_id == id, "and resumes in it")


## The select page fits every screen, with every hull's words in their box.
static func screens(t: SceneTree, screen_sizes: Dictionary) -> void:
	if TextLayer.glyph_index.is_empty():
		TextLayer.glyph_index = JSON.parse_string(
			FileAccess.get_file_as_string("res://art/font_3x5.json")
		)
	for name: String in screen_sizes:
		var scr: Dictionary = screen_sizes[name]
		var l := MenuLayout.build(scr, "ship")
		var probs := l.problems()
		for kind in ["prev", "next", "launch", "back"]:
			if l.button(kind).is_empty():
				probs.append("no %s button" % kind)
		if l.hinge.size.x > 0:
			for b in l.buttons:
				if (b.rect as Rect2i).position.x < l.hinge.end.x:
					probs.append("%s is on the left page" % b.kind)
			if l.info_rect.end.x > l.hinge.position.x:
				probs.append("the words cross the fold")
		for id in ShipRoster.playable():
			var c: Dictionary = ContentDB.ships[id]
			var fs := Vector2i(int(c.frame_size[0]), int(c.frame_size[1]))
			var used := Pixel.used_rect(load(c.sprite), fs)
			if used.size.x > l.preview_rect.size.x or used.size.y > l.preview_rect.size.y:
				probs.append("%s doesn't fit the preview" % id)
			var title := str(TranslationServer.translate(c.name)).to_upper()
			if TextLayer.text_width(title, 2) > l.title_rect.size.x:
				probs.append("%s's name is too wide" % id)
			for open in [true, false]:
				var lines := MenuView.ship_info_lines(id, open, l.info_rect.size.x)
				if lines.size() * TextLayer.LINE > l.info_rect.size.y:
					probs.append("%s's words overflow (%d lines)" % [id, lines.size()])
				for line in lines:
					if TextLayer.text_width(line[0]) > l.info_rect.size.x:
						probs.append("%s: '%s' is too wide" % [id, line[0]])
		_check(t, probs.is_empty(), "%s ship select: %s" % [name, probs.slice(0, 4)])


## From the title to a run in the picked hull, with the arrows, a swipe and Back.
static func flow(t: SceneTree, main: Node) -> void:
	var ids := ShipRoster.playable()
	main._clear_run()
	main.open_menu("title")
	main.profile.unlocked.clear()
	main.ships.pick = 0
	_tap(main, "new_run")
	_check(t, main.menu == "ship" and main.ships.picked() == ids[0], "New run shows the first hull")
	_tap(main, "prev")
	_check(t, main.ships.picked() == ids[-1], "the arrows wrap round")
	_tap(main, "next")
	_tap(main, "next")
	_check(t, main.ships.picked() == ids[1], "next moves on")
	var pr: Rect2i = main.menu_layout.preview_rect
	var k := float(main.screen.scale)
	var from := Vector2(pr.position.x + pr.size.x / 4, pr.get_center().y) * k  # clear of the fold
	ShipPicker.swipe(main, from, from + Vector2(-30.0 * k, 4.0 * k))
	_check(t, main.ships.picked() == ids[2], "a swipe left shows the next hull")
	ShipPicker.swipe(main, from, from + Vector2(6.0 * k, 0.0))
	_check(t, main.ships.picked() == ids[2], "a nudge is not a swipe")
	var hinge: Rect2i = main.menu_layout.hinge
	if hinge.size.x > 0:
		var on_fold := Vector2(hinge.get_center().x, pr.get_center().y) * k
		ShipPicker.swipe(main, on_fold, on_fold + Vector2(-30.0 * k, 0.0))
		_check(t, main.ships.picked() == ids[2], "a swipe that starts on the fold does nothing")
	var locked := ""
	for id in ids:
		if not main.ships.is_open(id):
			locked = id
	if locked != "":
		main.ships.pick = ids.find(locked)
		_tap(main, "launch")
		_check(t, main.menu == "ship" and main.run == null, "a locked hull can't launch")
		main.profile.unlocked.append(str(ContentDB.ships[locked].unlock))  # as if earned
	main.ships.pick = ids.size() - 1
	_tap(main, "back")
	_check(t, main.menu == "title" and main.run == null, "Back returns to the title")
	_tap(main, "new_run")
	_tap(main, "launch")
	_check(
		t,
		main.menu == "" and main.run != null and main.run.ship.content_id == ids[-1],
		"Launch starts the run in the picked hull"
	)
	_depth_after_ship(t, main, ids[-1])
	main.run.state = "lost"
	main._enter_screen()
	main._tap(
		Vector2((main.run_layout.button("next").rect as Rect2i).get_center()) * main.screen.scale,
		false
	)
	_check(t, main.menu == "ship" and main.run == null, "after a run, the next one picks a hull")
	main.back()
	_check(t, main.menu == "title", "and Back from there is the title")
	main.profile.unlocked.clear()


## With a Hush Depth open, Launch goes on to the depth page. Back from it
## returns to ship select, and a save made there remembers the picked hull.
static func _depth_after_ship(t: SceneTree, main: Node, hull: String) -> void:
	var was: int = main.profile.depth_open
	main.profile.depth_open = maxi(1, was)
	main.open_menu("title")
	_tap(main, "new_run")
	_tap(main, "yes")
	main.ships.show(hull)
	_tap(main, "launch")
	_check(t, main.menu == "depth", "with a depth open, Launch asks for a depth")
	main.back()
	_check(t, main.menu == "ship" and main.ships.picked() == hull, "Back from it is the pick")
	_tap(main, "launch")
	var saved: Dictionary = main._ui_state()
	main.ships.pick = 0
	main._restore_ui(saved)
	_check(
		t,
		main.menu == "depth" and main.ships.picked() == hull,
		"a depth page restored from a save still launches the picked hull"
	)
	main.profile.depth_open = was
	main.close_menu()


## A captain with only torches can't hurt a warded deck, so it aims at the open one,
## and moves a shot that the ward has since covered.
static func _torch_captain(t: SceneTree) -> void:
	var c := Combat.create(3, "porcelain_saint", "ashmarket_cutter")
	var foe := c.enemy()
	foe.ward_deck = 1
	foe.ward_layers = 2
	var ai := CombatAI.new()
	ai.think(c, 0)
	var me := c.player()
	var decks: Array[int] = []
	for target in me.weapon_target:
		decks.append(foe.room(target).deck if target != "" else -1)
	_check(t, decks == [0, 0], "an all-torch captain aims at the open deck: %s" % [decks])
	foe.ward_deck = 0
	for i in me.weapon_ids.size():
		me.weapon_charge[i] = 1.0
	ai.think(c, 0)
	decks.clear()
	for target in me.weapon_target:
		decks.append(foe.room(target).deck)
	_check(t, decks == [1, 1], "and re-aims when the ward moves over its shot: %s" % [decks])


## The select page draws each hull from a texture it holds. One loaded and let go
## inside _draw() is freed before the frame renders: a white box on the phone.
static func _preview_texture_lives(t: SceneTree) -> void:
	for id in ShipRoster.playable():
		var view := MenuView.new()
		var held: WeakRef = weakref(_drawn_texture(view, id))
		_check(t, held.get_ref() != null, "ship select keeps %s's sprite alive to render" % id)
		view.free()


static func _drawn_texture(view: MenuView, id: String) -> Texture2D:
	return view._ship_texture(id)
