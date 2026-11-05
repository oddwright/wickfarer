extends SceneTree
## Headless test runner: godot --headless --path . -s tests/run_tests.gd
## Exits with code 1 if anything fails, so CI goes red.

const J = preload("res://scripts/core/json_util.gd")

var failures: Array[String] = []
var passed := 0
var current := ""


func _init() -> void:
	ContentDB.load_all()
	for t in [
		"test_content_is_valid",
		"test_rng_streams_are_independent_and_saveable",
		"test_same_seed_same_fight",
		"test_save_mid_fight_resumes_identically",
		"test_save_file_safety",
		"test_old_save_is_migrated",
		"test_every_save_fixture_still_loads",
		"test_power_rules",
		"test_every_room_reachable_and_ladders_used",
		"test_wards_block_and_strip",
		"test_warmth_needs_the_ember",
		"test_fire_spreads_and_crew_put_it_out",
		"test_layouts_on_every_screen",
	]:
		current = t
		call(t)
	print("")
	if failures.is_empty():
		print("ALL %d CHECKS PASSED" % passed)
		quit(0)
	else:
		for f in failures:
			printerr("FAIL ", f)
		print("%d passed, %d failed" % [passed, failures.size()])
		quit(1)


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
	else:
		failures.append("%s: %s" % [current, what])


func run(c: Combat, ticks: int) -> void:
	for i in ticks:
		c.tick()


func aim_player(c: Combat) -> void:
	c.apply({"type": "aim", "weapon": 0, "room": "weapons"})
	c.apply({"type": "aim", "weapon": 1, "room": "weapons"})


# ------------------------------------------------------------------ tests


func test_content_is_valid() -> void:
	var errors := ContentDB.validate()
	for e in errors:
		print("  content: ", e)
	check(errors.is_empty(), "content has %d problems" % errors.size())


func test_rng_streams_are_independent_and_saveable() -> void:
	var a := RngStreams.new(42)
	var b := RngStreams.new(42)
	for i in 10:
		a.stream("combat").randf()  # extra rolls in one stream...
	check(a.stream("map").randi() == b.stream("map").randi(), "...must not shift another stream")
	var copy := RngStreams.from_dict(JSON.parse_string(J.s(a.to_dict())))
	check(copy.stream("combat").randi() == a.stream("combat").randi(), "rng state survives JSON")


func test_same_seed_same_fight() -> void:
	var a := Combat.create(7)
	var b := Combat.create(7)
	aim_player(a)
	aim_player(b)
	run(a, 1200)
	run(b, 1200)
	check(J.canonical(a.to_dict()) == J.canonical(b.to_dict()), "two fights with one seed differ")


func test_save_mid_fight_resumes_identically() -> void:
	var a := Combat.create(99)
	aim_player(a)
	run(a, 300)
	var text := J.s(a.to_dict())
	var b := Combat.from_dict(JSON.parse_string(text))
	check(J.canonical(b.to_dict()) == J.canonical(a.to_dict()), "load then save changes the data")
	run(a, 600)
	run(b, 600)
	check(
		J.canonical(a.to_dict()) == J.canonical(b.to_dict()),
		"resumed fight drifts from the original"
	)


func test_save_file_safety() -> void:
	var dir := "user://test_saves"
	DirAccess.make_dir_recursive_absolute(dir)
	SaveService.erase("slot", dir)
	check(SaveService.read("slot", dir).is_empty(), "no save reads as empty")
	check(SaveService.write("slot", {"n": 1}, dir), "first write")
	check(SaveService.write("slot", {"n": 2}, dir), "second write")
	check(int(SaveService.read("slot", dir).get("n", 0)) == 2, "reads the newest save")
	# Corrupt the main file: the backup should be used.
	var f := FileAccess.open(SaveService.path_for("slot", dir), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	check(
		int(SaveService.read("slot", dir).get("n", 0)) == 1,
		"falls back to the backup when the save is corrupt"
	)
	# A save from the future is left alone.
	f = FileAccess.open(SaveService.path_for("future", dir), FileAccess.WRITE)
	f.store_string(J.s({"version": SaveService.VERSION + 5, "data": {"n": 3}}))
	f.close()
	check(SaveService.read("future", dir).is_empty(), "refuses a save from a newer version")
	SaveService.erase("slot", dir)
	SaveService.erase("future", dir)


func test_old_save_is_migrated() -> void:
	var c := Combat.create(5)
	var inner := c.to_dict()
	inner.erase("rng")
	var v0 := {"version": 0, "data": {"rng_seed": 5, "combat": inner}}
	var up := SaveService.upgrade(JSON.parse_string(J.s(v0)))
	check(int(up.get("version", -1)) == SaveService.VERSION, "upgraded to the current version")
	var restored := Combat.from_dict(up.data.combat)
	check(restored.rng.run_seed == 5, "seed carried over from the old layout")


func test_power_rules() -> void:
	var c := Combat.create(1)
	var s := c.player()
	check(s.used_power() <= s.available_power(), "start power fits the reactor")
	check(s.used_power() == 8, "Wren starts with all 8 power used")
	check(not s.power_up("helm"), "can't go over the reactor")
	check(s.power_down("mend") and s.power_up("helm"), "power moves between systems")
	check(not s.power_up("ember"), "the Ember itself takes no power")
	s.system_room("ember").damage = 1.0
	s.enforce_power()
	check(s.available_power() == 6, "a damaged Ember loses 2 power per level")
	check(s.used_power() <= 6, "systems shed power when the Ember is hurt")
	check(s.system_power("wards") == 2, "wards are the last to lose power")


func test_every_room_reachable_and_ladders_used() -> void:
	var s := Ship.from_content("tallow_wren", 0)
	var p := s.find_path("galley", "hold")
	check(not p.is_empty() and p.back() == "hold", "galley to hold has a path")
	var used_ladder := false
	var prev := "galley"
	for r in p:
		if s.is_ladder(prev, r):
			used_ladder = true
		prev = r
	check(used_ladder, "changing decks goes through a ladder")
	var c := Combat.create(3)
	var bo := c.player().crew[2]
	c.apply({"type": "move", "crew": bo.uid, "room": "galley"})
	run(c, 200)
	check(bo.room == "galley" and not bo.is_moving(), "crew arrive (Bo is in %s)" % bo.room)


func test_wards_block_and_strip() -> void:
	var c := Combat.create(11)
	var foe := c.enemy()
	run(c, 60)  # let the ward charge
	check(foe.ward_layers == 1, "enemy ward charged to 1 layer")
	c.projectiles.append(
		{
			"owner": 0,
			"weapon": "torch_lance",
			"slot": 1,
			"target": "weapons",
			"t": 0.01,
			"total": 1.0
		}
	)
	var hull := foe.hull
	c.tick()
	check(foe.hull == hull and foe.ward_layers == 1, "a torch can't get through a ward")
	c.projectiles.append(
		{"owner": 0, "weapon": "rivet_gun", "slot": 0, "target": "weapons", "t": 0.01, "total": 1.0}
	)
	c.tick()
	check(foe.ward_layers == 0 and foe.hull == hull, "a rivet strips one ward layer")
	c.projectiles.append(
		{"owner": 0, "weapon": "torch_lance", "slot": 1, "target": "ember", "t": 0.01, "total": 1.0}
	)
	var ev := foe.evasion()
	c.tick()
	check(foe.hull < hull or ev > 0.0, "the unwarded deck takes hits")


func test_warmth_needs_the_ember() -> void:
	var c := Combat.create(2)
	var s := c.player()
	for i in 1200:
		s.tick(Combat.TICK, c.rng.stream("combat"), [])
	var coldest := 100.0
	for r in s.rooms:
		coldest = minf(coldest, r.warmth)
	print("  warmth with a healthy Ember: ", _warmths(s))
	check(
		coldest > Ship.COLD, "a healthy ship keeps every room above cold (coldest %.0f)" % coldest
	)
	check(
		s.room("helm").warmth > s.room("hold").warmth,
		"heat rises: the helm stays warmer than the hold below it"
	)
	s.system_room("ember").damage = 2.0
	for i in 1200:
		s.tick(Combat.TICK, c.rng.stream("combat"), [])
	print("  warmth with a dead Ember:    ", _warmths(s))
	check(s.room("hold").warmth < Ship.COLD, "without the Ember the ship goes cold")


func _warmths(s: Ship) -> String:
	var parts: Array[String] = []
	for r in s.rooms:
		parts.append("%s %.0f" % [r.id, r.warmth])
	return ", ".join(parts)


func test_fire_spreads_and_crew_put_it_out() -> void:
	var c := Combat.create(4)
	var s := c.player()
	var galley := s.room("galley")
	galley.fire = 100.0
	for i in 400:
		s.tick(Combat.TICK, c.rng.stream("combat"), [])
	check(galley.fire > 0.0, "an empty room keeps burning")
	var ness := s.crew[0]
	c.apply({"type": "move", "crew": ness.uid, "room": "galley"})
	for i in 600:
		s.tick(Combat.TICK, c.rng.stream("combat"), [])
	check(galley.fire == 0.0, "crew put the fire out")


func test_layouts_on_every_screen() -> void:
	var screens := {
		"Galaxy S24 (2340x1080)": Vector2i(2340, 1080),
		"generic 20:9 (2400x1080)": Vector2i(2400, 1080),
		"Galaxy Z Fold7 cover (2520x1080)": Vector2i(2520, 1080),
		"Galaxy Z Fold7 open (2184x1968)": Vector2i(2184, 1968),
		"Galaxy Z Fold7 open, portrait (1968x2184)": Vector2i(1968, 2184),
		"iPhone 16 (2556x1179)": Vector2i(2556, 1179),
		"iPhone 16 Pro Max (2868x1320)": Vector2i(2868, 1320),
		"iPad mini (2266x1488)": Vector2i(2266, 1488),
		"small 16:9 (1280x720)": Vector2i(1280, 720),
		"desktop window (1200x540)": Vector2i(1200, 540),
	}
	var pf := Vector2i(236, 76)
	var ef := Vector2i(196, 66)
	for name: String in screens:
		var scr := ScreenManager.compute(screens[name])
		var l := HudLayout.build(scr, pf, ef, HudLayout.SYSTEM_ORDER, 2)
		var probs := l.problems(pf, ef)
		print(
			(
				"  %-44s %dx  %s  canvas %dx%d  %s"
				% [
					name,
					scr.scale,
					scr.layout,
					scr.native.x,
					scr.native.y,
					"ok" if probs.is_empty() else str(probs)
				]
			)
		)
		check(probs.is_empty(), "%s layout: %s" % [name, probs])
	check(
		ScreenManager.compute(Vector2i(2400, 1080)).native == Vector2i(480, 216),
		"2400x1080 is 5x, 480x216"
	)


## Saves from every released version live in tests/fixtures. They must always load and play on.
func test_every_save_fixture_still_loads() -> void:
	var dir := DirAccess.open("res://tests/fixtures")
	check(dir != null, "fixtures folder exists")
	if dir == null:
		return
	var found := 0
	for name in dir.get_files():
		if not name.begins_with("save_v") or not name.ends_with(".json"):
			continue
		found += 1
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://tests/fixtures/" + name)
		)
		var up := SaveService.upgrade(raw)
		check(
			int(up.get("version", -1)) == SaveService.VERSION,
			"%s upgrades to the current version" % name
		)
		var c := Combat.from_dict(up.get("data", {}).get("combat", {}))
		run(c, 200)
		check(c.tick_count >= 400, "%s resumes and plays on" % name)
	check(found >= 1, "at least one save fixture")
