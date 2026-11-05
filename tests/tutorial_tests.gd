extends RefCounted
## Coach checks for tests/run_tests.gd: the training lessons, tips, saving mid-step,
## where the coach writes on every screen, and the flow through the real scene.

const FIGHT_TARGETS: Array[String] = [
	"pause", "ward", "weapon:0", "system:mend", "enemy_room:weapons", "rooms"
]


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


static func _ctx(r: Run, screen: String, paused := false, weapon := -1, crew := -1) -> Dictionary:
	return {
		"screen": screen,
		"paused": paused,
		"weapon": weapon,
		"crew": crew,
		"run": r,
		"combat": r.combat,
	}


static func _training() -> Run:
	return Run.create(7, "tallow_wren", Tutorial.TRAINING_REACH)


static func _fight(r: Run) -> void:
	r.state = "fight"
	r._start_fight("ashmarket_skiff")


static func lessons(t: SceneTree) -> void:
	var r := _training()
	var tut := Tutorial.new()
	tut.update(_ctx(r, "chart"))
	_check(t, tut.display.get("text") == "TUT_JUMP", "the chart lesson starts on the chart")
	_check(t, tut.display.target == "beacons" and not tut.holds(), "pointing at the beacons")
	r.jump(r.jump_targets()[0])
	tut.update(_ctx(r, "event"))
	_check(t, tut.lessons_done.has("chart"), "leaving the chart ends its lesson")
	_check(t, tut.display.get("text") == "TUT_CHOOSE", "the first story gets a lesson")
	_fight(r)
	var steps: Array[String] = []
	var ctx := _ctx(r, "fight")
	tut.update(ctx)
	steps.append(str(tut.display.text))
	_check(t, tut.holds(), "the first fight's first step holds the clock")
	tut.update(_ctx(r, "fight", true, 1))
	_check(t, tut.display.text == "TUT_AIM", "the wrong gun keeps pointing at the Rivet Gun")
	tut.update(_ctx(r, "fight", true, 0))
	_check(t, tut.display.text == "TUT_AIM_ROOM", "a selected gun moves the pointer to the room")
	_check(t, tut.display.target == "enemy_room:weapons", "to their weapons room")
	r.combat.apply({"type": "aim", "weapon": 0, "room": "weapons"})
	# play, pause, crew (select, then move), power down, power up, ward, then play to win
	var script: Array = [
		[true, -1, ""],
		[false, -1, ""],
		[true, -1, ""],
		[true, 1, ""],
		[true, -1, "move"],
		[true, -1, "power_down:helm"],
		[true, -1, "power_down:mend"],
		[true, -1, "power_up:mend"],
		[true, -1, "ward"],
		[false, -1, ""],
	]
	for s: Array in script:
		if s[2] != "":
			tut.on_order(str(s[2]).get_slice(":", 0), str(s[2]).get_slice(":", 1))
		tut.update(_ctx(r, "fight", s[0], -1, s[1]))
		if not tut.display.is_empty():
			steps.append(str(tut.display.text))
	var want: Array[String] = [
		"TUT_AIM",
		"TUT_PLAY",
		"TUT_PAUSE",
		"TUT_CREW",
		"TUT_CREW_ROOM",
		"TUT_POWER_DOWN",
		"TUT_POWER_DOWN",
		"TUT_POWER_UP",
		"TUT_WARD",
		"TUT_WIN",
	]
	_check(t, steps == want, "the fight lesson runs in order: %s" % [steps])
	_check(t, tut.lessons_done.has("fight") and tut.lesson == "", "and ends once time runs")
	# out of order: aiming before the coach asks skips the step
	var early := Tutorial.new()
	var r2 := _training()
	_fight(r2)
	r2.combat.apply({"type": "aim", "weapon": 0, "room": "helm"})
	early.lessons_done.assign(["chart", "story"])
	early.update(_ctx(r2, "fight", true))
	_check(t, early.display.get("text") == "TUT_PLAY", "an early aim skips the aim step")
	# the chart's second lesson waits for the fight's
	var again := Tutorial.new()
	again.lessons_done.assign(["chart"])
	again.update(_ctx(_training(), "chart"))
	_check(t, again.display.is_empty(), "the Hush lesson waits for a fight")
	again.lessons_done.append("fight")
	again.update(_ctx(_training(), "chart"))
	_check(t, again.display.get("text") == "TUT_HUSH", "and then shows on the chart")
	# a normal run gets no lessons; skipping turns them off for good
	var plain := Tutorial.new()
	plain.update(_ctx(Run.create(7), "chart"))
	_check(t, plain.display.is_empty(), "no lessons outside the training lane")
	var skipper := Tutorial.new()
	skipper.skip()
	skipper.update(_ctx(_training(), "chart"))
	_check(t, skipper.display.is_empty() and skipper.done, "Skip stops the lessons")
	var ender := Tutorial.new()
	ender.update(_ctx(_training(), "lost"))
	_check(t, ender.done, "losing the training flight finishes training")
	_check(t, ender.display.get("text") == "TUT_LOST", "with a word on what a run is")
	ender.update(_ctx(Run.create(8), "chart"))
	_check(t, ender.lesson == "" and ender.display.is_empty(), "a real run drops the lesson")


static func tips(t: SceneTree) -> void:
	var r := Run.create(9)
	_fight(r)
	var tut := Tutorial.new()
	tut.on_events([{"type": "fire_start", "side": 1}])
	_check(t, not tut.update(_ctx(r, "fight")), "a fire on their ship is not ours")
	tut.on_events([{"type": "fire_start", "side": 0, "room": "helm"}])
	_check(t, tut.update(_ctx(r, "fight")), "the first fire on our ship shows a tip")
	_check(t, tut.tip == "fire" and tut.display.get("tip", false), "the fire tip")
	_check(t, tut.display.target == "pause", "pointing at play to go on")
	tut.update(_ctx(r, "fight"))
	_check(t, tut.tip == "fire", "it waits for the pause Main gives it")
	tut.update(_ctx(r, "fight", true))
	tut.update(_ctx(r, "fight", false))
	_check(t, tut.tip == "", "pressing play clears it")
	tut.on_events([{"type": "fire_start", "side": 0, "room": "helm"}])
	_check(t, not tut.update(_ctx(r, "fight")), "a tip shows once ever")
	r.combat.player().hull = 2
	_check(t, tut.update(_ctx(r, "fight")) and tut.tip == "low_hull", "low hull has a tip")
	var chart := Run.create(9)
	chart.messages.append("UI_DARK_JUMP")
	var dark := Tutorial.new()
	_check(t, dark.update(_ctx(chart, "chart")) and dark.tip == "dark_jump", "a dark jump tip")
	dark.update(_ctx(chart, "event"))
	_check(t, dark.tip == "", "a run screen's tip clears when the screen changes")
	var busy := Tutorial.new()
	var lane := _training()
	busy.on_events([{"type": "fire_start", "side": 0, "room": "helm"}])
	_fight(lane)
	_check(t, not busy.update(_ctx(lane, "fight")), "tips wait while a lesson talks")
	busy.skip()
	busy.update(_ctx(lane, "fight"))
	_check(t, busy.tip == "fire", "and show once it stops")
	var jumped := Run.create(9)
	jumped.state = "event"
	jumped.messages.append("UI_DARK_JUMP")
	var story := Tutorial.new()
	_check(t, story.update(_ctx(jumped, "event")), "a dark jump that lands on a story tips too")


static func saves(t: SceneTree, dir: String) -> void:
	var r := _training()
	_fight(r)
	var tut := Tutorial.new()
	tut.lessons_done.assign(["chart", "story"])
	tut.update(_ctx(r, "fight", true))
	tut.update(_ctx(r, "fight", true, 0))
	r.combat.apply({"type": "aim", "weapon": 0, "room": "weapons"})
	tut.update(_ctx(r, "fight", true))
	tut.tips_seen.append("fire")
	_check(t, tut.dirty, "progress marks the coach for saving")
	_check(t, tut.save(dir) and not tut.dirty, "it saves to its own slot")
	var back := Tutorial.load_or_default(dir)
	_check(
		t,
		back.lesson == "fight" and back.step == tut.step and back.tips_seen == ["fire"],
		"a swiped-away app comes back on the same step"
	)
	back.update(_ctx(r, "fight", true))
	_check(t, back.display.get("text") == "TUT_PLAY", "showing the same words")
	var junk := Tutorial.from_dict(
		{"done": "yes", "lesson": "gone", "step": "x", "lessons_done": 5, "tip": "nope"}
	)
	_check(t, not junk.done and junk.coaching, "a damaged file falls back to a new player")
	_check(t, junk.lesson == "" and junk.tip == "", "and drops lessons an update removed")
	var past := Tutorial.from_dict({"lesson": "fight", "step": 99.0})
	_check(t, past.step == Tutorial.lessons()[2].steps.size(), "a step past the end is clamped")
	SaveService.erase(Tutorial.SLOT, dir)
	SaveService.erase("run", dir)
	SaveService.erase(GameSettings.SLOT, dir)
	_check(t, Tutorial.load_or_default(dir).to_dict() == Tutorial.new().to_dict(), "no file: new")
	SaveService.write("run", {"run": {}}, dir)
	_check(t, Tutorial.load_or_default(dir).done, "a player from before the coach skips training")
	SaveService.erase("run", dir)
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/tutorial_v1.json")
	)
	var v1 := Tutorial.from_dict(SaveService.upgrade(raw).get("data", {}))
	_check(t, v1.lesson == "fight" and v1.step == 1, "the v1 tutorial fixture loads mid-step")
	_check(t, v1.tips_seen == ["fire"] and v1.lessons_done.size() == 2, "with what it had seen")
	var bad: Array[String] = []
	ContentDB._validate_tutorial(
		{
			"lessons":
			[{"id": "a", "screen": "chart", "after": "a", "steps": [{"text": "TUT_JUMP"}]}, 3],
			"tips": [{"id": "x", "on": "cold", "text": "TIP_COLD"}, {"id": "x", "on": "fire_start"}]
		},
		bad
	)
	var joined := " | ".join(bad)
	for want in ["earlier lesson", "done condition", "must be an object", "unique id"]:
		_check(t, joined.contains(want), "bad tutorial data is reported: %s" % want)


## The coach writes in the screen's message line: clear of buttons and inside the
## canvas on every screen, with room for the longest step, and its fight targets exist.
static func layouts(t: SceneTree, screens: Dictionary) -> void:
	var tl := CoachView.new()
	TextLayer.glyph_index = JSON.parse_string(
		FileAccess.get_file_as_string("res://art/font_3x5.json")
	)
	var fight_texts: Array[String] = []
	var run_texts: Array[String] = ["TIP_DARK_JUMP"]
	for l: Dictionary in Tutorial.lessons():
		for s: Dictionary in l.steps:
			var into := fight_texts if l.screen == "fight" else run_texts
			into.append(tr_key(str(s.text)))
			if s.has("then"):
				into.append(str(s.then.text))
	for tip: Dictionary in Tutorial.tips():
		if tip.on != "dark_jump":
			fight_texts.append(tr_key(str(tip.text)) + " " + tr_key("TIP_GO_ON"))
	var c := Combat.create(1, "tallow_wren", "ashmarket_skiff")
	var r := Run.create(1)
	for name: String in screens:
		var scr: Dictionary = screens[name]
		var probs: Array[String] = []
		var hud := HudLayout.build(
			scr, Vector2i(236, 76), Vector2i(196, 66), HudLayout.SYSTEM_ORDER, 2
		)
		var rect := CoachLayout.text_rect(hud, null)
		probs.append_array(CoachLayout.problems(rect, hud.buttons, hud.native))
		probs.append_array(_fits(tl, rect, fight_texts))
		for target in FIGHT_TARGETS:
			if CoachLayout.targets(target, hud, null, null, c).is_empty():
				probs.append("fight target %s not found" % target)
		for mode: String in ["chart", "event", "store", "next"]:
			var rl := RunLayout.build(scr, r.chart, mode, 3)
			var rr := CoachLayout.text_rect(null, rl)
			for p in CoachLayout.problems(rr, rl.buttons, rl.native):
				probs.append("%s: %s" % [mode, p])
			probs.append_array(_fits(tl, rr, run_texts))
		_check(t, probs.is_empty(), "%s coach: %s" % [name, probs.slice(0, 4)])
	tl.free()


static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)


## Every step's words, and every jump note the chart's coach may show alone instead.
static func _fits(tl: CoachView, r: Rect2i, keys: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for k in keys + ["UI_HUSH_HIT", "UI_DARK_JUMP"]:
		if not tl.fits(tr_key(k), r):
			out.append("%s does not fit in %d px" % [k.left(14), r.size.y])
	return out


## The real scene: a new player's New Run is training, the coach holds the clock,
## and the step survives the app being swiped away.
static func flow(t: SceneTree) -> void:
	var dir := "user://test_saves"
	DirAccess.make_dir_recursive_absolute(dir)
	for slot in ["run", GameSettings.SLOT, Tutorial.SLOT]:
		SaveService.erase(slot, dir)
	var main := _open(t, dir)
	_check(t, main.menu_items("title") == ["new_run", "options", "quit"], "no Training yet")
	main._tap_menu(_item_point(main, "new_run"))
	_check(t, Tutorial.is_training(main.run), "a new player's New Run is the training lane")
	main._process(0.05)
	_check(t, main.coach_speaking(), "the coach speaks on the chart")
	var r: Run = main.run
	r.jump(r.jump_targets()[0])
	_fight(r)
	main._set_run(r)
	main._process(0.2)
	_check(t, main.paused and main.combat.time() == 0.0, "the first fight opens with time held")
	_tap(main, main.layout.button("pause").rect)
	_check(t, main.paused, "play is refused while a step holds the clock")
	_tap(main, main.layout.button("weapon", 0).rect)
	var room: Room = main.combat.enemy().system_room("weapons")
	_tap(main, Rect2i(room.rect.position + main.layout.enemy_origin, room.rect.size))
	_check(t, main.combat.player().weapon_target[0] == "weapons", "tapping gun then room aims")
	main._process(0.05)
	_check(t, main.tutorial.display.get("text") == "TUT_PLAY", "then the coach asks for play")
	var step: int = main.tutorial.step
	main._on_leave()  # the phone takes the screen away; the app is then killed
	main.queue_free()
	main = _open(t, dir)
	_check(t, main.tutorial.lesson == "fight" and main.tutorial.step == step, "same step after")
	if main.menu == "title":
		main._tap_menu(_item_point(main, "continue"))
	_check(t, main.menu == "" and main.combat != null, "back in the training fight")
	main._process(0.05)
	_check(t, main.paused and main.tutorial.display.get("text") == "TUT_PLAY", "same words")
	_tap(main, main.layout.button("pause").rect)
	main._process(0.2)
	_check(t, not main.paused and main.combat.time() > 0.0, "play now runs the fight")
	main._tap(Vector2(main.layout.menu_rect.get_center()) * main.screen.scale, false)
	_check(t, main.menu_items("pause").has("skip_training"), "the pause menu offers Skip")
	main._tap_menu(_item_point(main, "skip_training"))
	main._process(0.05)
	_check(t, main.tutorial.done and not main.coach_speaking(), "Skip quiets the coach")
	main._abandon()
	_check(t, main.menu_items("title").has("training"), "the title offers Training after")
	main.queue_free()
	for slot in ["run", GameSettings.SLOT, Tutorial.SLOT]:
		SaveService.erase(slot, dir)


static func _open(t: SceneTree, dir: String) -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_dir = dir
	t.root.size = Vector2i(2400, 1080)
	t.root.add_child(main)
	return main


static func _tap(main: Node, r: Rect2i) -> void:
	main._tap(Vector2(r.get_center()) * main.screen.scale + Vector2.ONE, false)


static func _item_point(main: Node, id: String) -> Vector2i:
	return (main.menu_layout.button("item", id).rect as Rect2i).get_center()
