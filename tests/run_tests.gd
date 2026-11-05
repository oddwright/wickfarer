extends SceneTree
## Headless test runner: godot --headless --path . -s tests/run_tests.gd
## Exits with code 1 if anything fails, so CI goes red.

const J = preload("res://scripts/core/json_util.gd")
const SCREENS := {
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
		"test_chart_is_connected_and_seeded",
		"test_jumping_costs_light_and_the_hush_follows",
		"test_events_apply_and_respect_requirements",
		"test_store_and_fight_rewards",
		"test_run_saves_and_resumes_at_every_step",
		"test_autopilot_runs_always_end",
		"test_power_rules",
		"test_every_room_reachable_and_ladders_used",
		"test_wards_block_and_strip",
		"test_warmth_needs_the_ember",
		"test_fire_spreads_and_crew_put_it_out",
		"test_layouts_on_every_screen",
		"test_run_screens_on_every_screen",
		"test_view_screens_follow_the_run",
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
	s.system_room("ember").damage = 0.0
	s.system_room("weapons").damage = 3.0
	s.enforce_power()
	check(s.system_power("weapons") == 0, "a broken system loses its power")
	s.system_room("weapons").damage = 0.0
	s.enforce_power()
	check(s.system_power("weapons") == 3, "a repaired system gets its power back")


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
	var screens := SCREENS
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
	var runs := 0
	for name in dir.get_files():
		if not name.begins_with("run_save_v") or not name.ends_with(".json"):
			continue
		runs += 1
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://tests/fixtures/" + name)
		)
		var up := SaveService.upgrade(raw)
		var r := Run.from_dict(up.get("data", {}).get("run", {}))
		var end := Autopilot.new().play(r)
		check(end in ["lost", "reach_done"], "%s resumes and plays to the end (%s)" % [name, end])
	check(runs >= 1, "at least one whole-run save fixture")


# ------------------------------------------------------------------ runs


func test_chart_is_connected_and_seeded() -> void:
	for seed_value in 30:
		var r := Run.create(seed_value)
		var seen := r.chart.reachable(r.chart.start_id())
		check(seen.has(r.chart.gate_id()), "seed %d: the Gate is reachable" % seed_value)
		for n in r.chart.nodes:
			if n.kind != "gate":
				check(
					not (n.links as Array).is_empty(),
					"seed %d: %s has a way on" % [seed_value, n.id]
				)
		var stores := r.chart.nodes.filter(func(n: Dictionary) -> bool: return n.kind == "store")
		check(not stores.is_empty(), "seed %d: has a store" % seed_value)
	var a := Run.create(77)
	var b := Run.create(77)
	check(J.canonical(a.chart.to_dict()) == J.canonical(b.chart.to_dict()), "same seed, same chart")


func test_jumping_costs_light_and_the_hush_follows() -> void:
	var r := Run.create(8)
	var light := r.light
	var hush := r.hush
	check(not r.jump("nowhere"), "can't jump to an unlinked beacon")
	var target: String = r.jump_targets()[0]
	check(r.jump(target), "jump along a link")
	check(r.light == light - 1 or r.state == "fight", "a jump costs 1 Light")
	check(r.hush > hush, "the Hush moves up after every jump")
	# Out of Light: jumping dark costs hull instead.
	var r2 := Run.create(9)
	r2.light = 0
	var hull := r2.ship.hull
	r2.jump(r2.jump_targets()[0])
	check(r2.ship.hull <= hull - 2, "a dark jump costs hull")
	# Caught by the Hush.
	var r3 := Run.create(10)
	r3.hush = 50.0
	var hull3 := r3.ship.hull
	r3.jump(r3.jump_targets()[0])
	check(r3.ship.hull <= hull3 - 3, "a swallowed beacon damages the hull")


func test_events_apply_and_respect_requirements() -> void:
	var r := Run.create(12)
	r.state = "event"
	r.event_id = "ash_toll"
	r.scrap = 0
	check(not r.can_choose(0), "can't pay a toll with no scrap")
	r.scrap = 30
	check(r.can_choose(0), "can pay with scrap")
	check(r.choose(0) and r.scrap == 20 and r.state == "chart", "paying takes 10 scrap")
	r.state = "event"
	r.event_id = "ash_toll"
	check(r.choose(2) and r.state == "fight", "refusing starts a fight")
	var r2 := Run.create(13)
	r2.state = "event"
	r2.event_id = "choir_signal"
	check(r2.can_choose(1), "the Wren has a Sable aboard")
	for c in r2.ship.crew:
		if c.species == "sable":
			c.hp = 0.0
	check(not r2.can_choose(1), "a dead Sable can't answer the Choir")


func test_store_and_fight_rewards() -> void:
	var r := Run.create(14)
	r.state = "store"
	r.scrap = 10
	r.ship.hull = 15
	check(r.buy("repair") and r.ship.hull == 16 and r.scrap == 7, "repair costs 3 scrap")
	check(r.buy("light") and r.scrap == 2, "Light costs 5 scrap")
	check(not r.buy("light"), "can't buy without scrap")
	check(not r.can_buy("light") and r.can_buy("repair") == false, "the store greys out")
	r.scrap = 50
	r.ship.hull = r.ship.max_hull
	check(not r.can_buy("repair"), "no repairs on a whole hull")
	check(r.can_buy("light") and r.price("light") == 5, "the view reads prices from the sim")
	check(not r.can_buy("scrap"), "the store only sells what the Reach lists")
	check(r.leave_store() and r.state == "chart", "leave the store")
	r._start_fight("ashmarket_cutter")
	r.combat.enemy().hull = 0
	r.combat.tick()
	var scrap := r.scrap
	check(r.finish_fight() and r.state == "chart", "a won fight returns to the chart")
	check(r.scrap > scrap, "a won fight pays scrap")
	check(r.ship.system_room("weapons").damage == 0.0, "crew patch systems after a fight")


func test_run_saves_and_resumes_at_every_step() -> void:
	var pilot := Autopilot.new()
	var r := Run.create(21)
	for step in 12:
		if r.state in ["reach_done", "lost"]:
			break
		var copy := Run.from_dict(JSON.parse_string(J.s(r.to_dict())))
		check(
			J.canonical(copy.to_dict()) == J.canonical(r.to_dict()),
			"step %d: save round-trips" % step
		)
		pilot.play(r, 1)
		Autopilot.new().play(copy, 1)
		check(
			J.canonical(copy.to_dict()) == J.canonical(r.to_dict()),
			"step %d: resumed run plays the same" % step
		)


func test_autopilot_runs_always_end() -> void:
	var ends := {}
	for i in 12:
		var r := Run.create(300 + i)
		var end := Autopilot.new().play(r)
		ends[end] = int(ends.get(end, 0)) + 1
		check(end in ["reach_done", "lost"], "run %d ended properly (got %s)" % [i, end])
	print("  autopilot run endings: ", ends)


func test_run_screens_on_every_screen() -> void:
	for name: String in SCREENS:
		var scr := ScreenManager.compute(SCREENS[name])
		var probs: Array[String] = []
		for seed_value in 30:
			var chart := Run.create(seed_value).chart
			probs.append_array(RunLayout.build(scr, chart, "chart").problems())
			var l := RunLayout.build(scr, chart, "chart")
			for n in chart.nodes:
				if (l.button("beacon", n.id).rect as Rect2i).get_center() != l.beacon_pos(n):
					probs.append("beacon %s is off its hit box" % n.id)
		var chart0 := Run.create(1).chart
		for mode in ["event", "store", "next"]:
			var l := RunLayout.build(scr, chart0, mode, 3)
			probs.append_array(l.problems())
			if l.buttons.is_empty():
				probs.append("%s has no buttons" % mode)
			for b in l.buttons:
				if (b.rect as Rect2i).end.y > scr.native.y - 4:
					probs.append("%s button falls off the bottom" % mode)
				if mode != "next" and (b.rect as Rect2i).intersects(l.text_rect):
					probs.append("%s button covers the text" % mode)
		check(probs.is_empty(), "%s run screens: %s" % [name, probs.slice(0, 4)])


func test_view_screens_follow_the_run() -> void:
	var main: Node = load("res://scripts/view/main.gd").new()
	main.screen = ScreenManager.compute(Vector2i(2400, 1080))
	var r := Run.create(77)
	main.run = r
	check(main.run_screen() == "chart", "a new run opens on the chart")
	main.outcome = "EV_ASH_TOLL_C1_O1"
	check(main.run_screen() == "outcome", "an event result is shown before moving on")
	main.free()
