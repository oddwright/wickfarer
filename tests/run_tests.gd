# gdlint: disable=max-public-methods
# (every test_ method is public by design: the runner calls them by name)
extends SceneTree
## Headless test runner: godot --headless --path . -s tests/run_tests.gd
## Exits with code 1 if anything fails, so CI goes red.

const J = preload("res://scripts/core/json_util.gd")
const MAIN = preload("res://scripts/view/main.gd")
const MENU_TESTS = preload("res://tests/menu_tests.gd")
const AUDIO_TESTS = preload("res://tests/audio_tests.gd")
const STORY_TESTS = preload("res://tests/story_tests.gd")
const SCREEN_TESTS = preload("res://tests/screen_tests.gd")
const SHIP_TESTS = preload("res://tests/ship_tests.gd")
const CREW_TESTS = preload("res://tests/crew_tests.gd")
const PROGRESS_TESTS = preload("res://tests/progress_tests.gd")
const PROFILE_TESTS = preload("res://tests/profile_tests.gd")
const RESUME_TESTS = preload("res://tests/resume_tests.gd")
const TUTORIAL_TESTS = preload("res://tests/tutorial_tests.gd")
const AUTOPILOT_TESTS = preload("res://tests/autopilot_tests.gd")
const FACTION_TESTS = preload("res://tests/faction_tests.gd")
const GEAR_TESTS = preload("res://tests/gear_tests.gd")
const CARD_TESTS = preload("res://tests/card_tests.gd")
const WARDEN_TESTS = preload("res://tests/warden_tests.gd")
const SIEGE_TESTS = preload("res://tests/siege_tests.gd")
const FIGHT_TESTS = preload("res://tests/fight_tests.gd")
const SCREENS := {
	"Galaxy S24 (2340x1080)": Vector2i(2340, 1080),
	"generic 20:9 (2400x1080)": Vector2i(2400, 1080),
	"Galaxy Z Fold7 cover (2520x1080)": Vector2i(2520, 1080),
	"Galaxy Z Fold7 open (2184x1968)": Vector2i(2184, 1968),
	"Galaxy Z Fold7 open, portrait (1968x2184)": Vector2i(1968, 2184),
	"Galaxy Z Fold7 cover, portrait (1080x2520)": Vector2i(1080, 2520),
	"Galaxy S24, portrait (1080x2340)": Vector2i(1080, 2340),
	"small 16:9, portrait (720x1280)": Vector2i(720, 1280),
	"iPhone 16 (2556x1179)": Vector2i(2556, 1179),
	"iPhone 16 Pro Max (2868x1320)": Vector2i(2868, 1320),
	"iPad mini (2266x1488)": Vector2i(2266, 1488),
	"iPhone 16, portrait (1179x2556)": Vector2i(1179, 2556),
	"iPad mini, portrait (1488x2266)": Vector2i(1488, 2266),
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
		"test_ship_preview_sprite_survives_to_render",
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
		"test_beacon_openers",
		"test_faction_standing_and_skill_checks",
		"test_both_ships_dying_together_is_a_loss",
		"test_event_results_and_messages_survive_saves",
		"test_run_saves_and_resumes_at_every_step",
		"test_autopilot_runs_always_end",
		"test_crew_posts_and_skills",
		"test_power_rules",
		"test_every_room_reachable_and_ladders_used",
		"test_wards_block_and_strip",
		"test_warmth_needs_the_ember",
		"test_fire_spreads_and_crew_put_it_out",
		"test_layouts_on_every_screen",
		"test_ui_size_setting",
		"test_pixel_font",
		"test_run_screens_on_every_screen",
		"test_view_screens_follow_the_run",
		"test_weapon_ready_event",
		"test_feedback_cues_follow_events",
		"test_feedback_shake_and_hitstop",
		"test_feedback_content_is_checked",
		"test_haptic_patterns",
		"test_settings_save_and_fall_back",
		"test_audio_service_and_music_states",
		"test_music_director_stages",
		"test_music_clips_and_transitions",
		"test_music_clips_are_synced_stems",
		"test_menu_screens_on_every_screen",
		"test_options_adjust_settings",
		"test_progression",
		"test_gear",
		"test_cards_and_chart_key",
		"test_tutorial",
		"test_enemy_factions_and_wardens",
		"test_kindling_siege",
		"test_rents_and_flare",
	]:
		current = t
		call(t)


## Tests that need the real scene in the tree run on the first frame, once the
## root has entered it (it hasn't during _init).
func _process(_delta: float) -> bool:
	for t in [
		"test_menu_flow", "_test_tutorial_flow", "_test_crew_roster_flow", "_test_gear_pages"
	]:
		current = t
		call(t)
	_finish()
	return false


func _finish() -> void:
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


func _run(c: Combat, ticks: int) -> void:
	for i in ticks:
		c.tick()


func _aim_player(c: Combat) -> void:
	c.apply({"type": "aim", "weapon": 0, "room": "weapons"})
	c.apply({"type": "aim", "weapon": 1, "room": "weapons"})


# ------------------------------------------------------------------ tests


func test_ship_preview_sprite_survives_to_render() -> void:
	SHIP_TESTS.preview_texture_lives(self)


func test_content_is_valid() -> void:
	var errors := ContentDB.validate()
	for e in errors:
		print("  content: ", e)
	check(errors.is_empty(), "content has %d problems" % errors.size())
	SHIP_TESTS.roster(self)
	var bad: Array[String] = []
	var reach: Dictionary = ContentDB.reaches.reach_1.duplicate(true)
	reach.enemies = []
	reach.kinds = {"fight": 0}
	reach.columns = 2
	ContentDB._validate_reach("bad", reach, bad)
	check(bad.size() >= 3, "a reach with no enemies, no beacon weights or 2 columns is caught")
	bad.clear()
	var ev: Dictionary = ContentDB.events.lantern_buoy.duplicate(true)
	ev.choices[1].outcomes[0]["effects"] = {"light": -2}
	ContentDB._validate_event("bad", ev, bad)
	check(not bad.is_empty(), "a choice that spends Light without requiring it is caught")
	var r := RandomNumberGenerator.new()
	var zero: Array[int] = [0, 0]
	check(RngStreams.weighted_pick(zero, r) == -1, "all-zero weights pick nothing")
	var only_last: Array[int] = [0, 0, 5]
	var all_last := true
	for i in 50:
		all_last = all_last and RngStreams.weighted_pick(only_last, r) == 2
	check(all_last, "a weight of 0 is never picked")


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
	_aim_player(a)
	_aim_player(b)
	_run(a, 1200)
	_run(b, 1200)
	check(J.canonical(a.to_dict()) == J.canonical(b.to_dict()), "two fights with one seed differ")


func test_save_mid_fight_resumes_identically() -> void:
	var a := Combat.create(99)
	_aim_player(a)
	_run(a, 300)
	var text := J.s(a.to_dict())
	var b := Combat.from_dict(JSON.parse_string(text))
	check(J.canonical(b.to_dict()) == J.canonical(a.to_dict()), "load then save changes the data")
	_run(a, 600)
	_run(b, 600)
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
	var big := {"version": 0, "data": {"rng_seed": 987654321, "combat": inner.duplicate(true)}}
	var up_big := SaveService.upgrade(JSON.parse_string(J.s(big)))
	check(str(up_big.data.combat.rng.seed) == "987654321", "a JSON seed is read as a whole number")
	var empty := {"version": 0, "data": {}}
	check(not SaveService.upgrade(empty).is_empty(), "a step that returns empty data still counts")
	var from_future := {"version": SaveService.VERSION + 1, "data": {"x": 1}}
	check(SaveService.upgrade(from_future).is_empty(), "a save from a newer game is refused")
	var v1: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/save_v1.json")
	)
	var up1 := SaveService.upgrade(v1)
	var room0: Dictionary = up1.data.combat.ships[0].rooms[0]
	check(room0.wanted_power == room0.power, "v1 rooms get wanted_power from their power")
	var original := J.canonical(v0)
	SaveService.upgrade(v0)
	check(J.canonical(v0) == original, "upgrading never edits the save it was given")


func test_crew_posts_and_skills() -> void:
	CREW_TESTS.posts_and_roles(self)
	CREW_TESTS.learning(self)
	CREW_TESTS.bonuses(self)
	CREW_TESTS.ai_uses_posts(self)
	CREW_TESTS.resume(self)
	CREW_TESTS.layouts(self, SCREEN_TESTS.variants(SCREENS))


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
	# Once the captain moves power by hand, a broken system stops waiting for it.
	s.system_room("weapons").damage = 2.0
	s.enforce_power()
	var spare_before := s.available_power() - s.used_power()
	check(spare_before > 0, "damage frees power to spend")
	check(s.power_up("helm") or s.power_up("engines"), "the captain spends it elsewhere")
	s.system_room("weapons").damage = 0.0
	s.enforce_power()
	check(s.system_power("weapons") == 1, "a repair doesn't take back power moved elsewhere")


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
	_run(c, 200)
	check(bo.room == "galley" and not bo.is_moving(), "crew arrive (Bo is in %s)" % bo.room)


func test_wards_block_and_strip() -> void:
	var c := Combat.create(11)
	var foe := c.enemy()
	_run(c, 60)  # let the ward charge
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
	SCREEN_TESTS.hud(self, SCREEN_TESTS.variants(SCREENS))


func test_ui_size_setting() -> void:
	SCREEN_TESTS.ui_size(self)


func test_pixel_font() -> void:
	SCREEN_TESTS.font(self)


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
		if not raw is Dictionary:
			check(false, "%s is not a JSON object" % name)
			continue
		var up := SaveService.upgrade(raw)
		check(
			int(up.get("version", -1)) == SaveService.VERSION,
			"%s upgrades to the current version" % name
		)
		if up.is_empty():
			continue  # already failed above; loading {} would only crash the runner
		var c := Combat.from_dict(up.get("data", {}).get("combat", {}))
		var before := c.tick_count
		_run(c, 200)
		check(c.tick_count == before + 200, "%s resumes and plays on" % name)
	check(found >= 1, "at least one save fixture")
	var runs := 0
	for name in dir.get_files():
		if not name.begins_with("run_save_v") or not name.ends_with(".json"):
			continue
		runs += 1
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://tests/fixtures/" + name)
		)
		if not raw is Dictionary:
			check(false, "%s is not a JSON object" % name)
			continue
		var up := SaveService.upgrade(raw)
		check(
			int(up.get("version", -1)) == SaveService.VERSION,
			"%s upgrades to the current version" % name
		)
		if up.is_empty():
			continue
		var r := Run.from_dict(up.get("data", {}).get("run", {}))
		var end := Autopilot.new().play(r)
		check(end in Run.ENDINGS, "%s resumes and plays to the end (%s)" % [name, end])
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


func test_event_results_and_messages_survive_saves() -> void:
	var r := Run.create(30)
	r.state = "event"
	r.event_id = "debris_field"
	check(r.choose(1) and r.outcome != "", "a choice leaves a result to read")
	var back := Run.from_dict(JSON.parse_string(J.s(r.to_dict())))
	check(back.outcome == r.outcome, "an unread result survives a save")
	check(back.read_outcome() and back.outcome == "", "reading it clears it")
	check(not back.read_outcome(), "there is nothing left to read")
	var gone := r.to_dict()
	gone.state = "event"
	gone.event = "an_event_removed_in_an_update"
	var loaded := Run.from_dict(JSON.parse_string(J.s(gone)))
	check(loaded.state == "chart", "a save on a removed event goes back to the chart")
	var f := Run.create(31)
	f.messages.append("UI_HUSH_HIT")
	f._start_fight("ashmarket_skiff")
	f.combat.enemy().hull = 0
	f.combat.tick()
	f.finish_fight()
	check(not f.messages.has("UI_HUSH_HIT"), "old jump news doesn't come back after a fight")
	check(f.store_items() == ["repair", "light"], "the Reach lists what its stores sell")


func test_both_ships_dying_together_is_a_loss() -> void:
	var r := Run.create(21)
	r._start_fight("ashmarket_skiff")
	r.combat.player().hull = 0
	r.combat.enemy().hull = 0
	r.combat.tick()
	check(r.combat.state == "lost", "a fight where both ships die is lost")
	r.finish_fight()
	check(r.state == "lost", "the run ends instead of carrying a dead ship on")
	var r2 := Run.create(22)
	r2._start_fight("ashmarket_skiff")
	r2.combat.state = "won"  # as an older save could hold
	r2.combat.player().hull = 0
	r2.finish_fight()
	check(r2.state == "lost", "finish_fight never pays out to a dead ship")


func test_store_and_fight_rewards() -> void:
	var r := Run.create(14)
	r.state = "store"
	r.scrap = 10
	r.ship.hull = r.ship.max_hull - 5
	var hull := r.ship.hull
	check(r.buy("repair") and r.ship.hull == hull + 1 and r.scrap == 7, "repair costs 3 scrap")
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


# The opener bodies live in tests/story_tests.gd to keep this file under the lint limit.


## Every beacon opens with a story; see tests/story_tests.gd for each check.
func test_beacon_openers() -> void:
	STORY_TESTS.every_beacon(self)
	STORY_TESTS.lead_in(self)
	STORY_TESTS.effects_checked(self)
	STORY_TESTS.text_fits(self, SCREEN_TESTS.variants(SCREENS))


## Reputation, story flags and crew skill checks; see tests/faction_tests.gd.
func test_faction_standing_and_skill_checks() -> void:
	FACTION_TESTS.standing_rules(self)
	FACTION_TESTS.store_prices(self)
	FACTION_TESTS.events_and_fights(self)
	FACTION_TESTS.ambush_weights(self)
	FACTION_TESTS.story_gates(self)
	FACTION_TESTS.skill_checks(self)
	FACTION_TESTS.saves_keep_standing(self)
	FACTION_TESTS.content_checked(self)
	FACTION_TESTS.fixture_keeps_standing(self)


func test_run_saves_and_resumes_at_every_step() -> void:
	var pilot := Autopilot.new()
	var r := Run.create(21)
	for step in 60:  # long enough to refit at a store and cross a Gate
		if r.is_over():
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


## The balance tools' players; see tests/autopilot_tests.gd for each check.
func test_autopilot_runs_always_end() -> void:
	AUTOPILOT_TESTS.runs_end(self)
	AUTOPILOT_TESTS.skilled_resumes(self)
	AUTOPILOT_TESTS.split_aim(self)
	AUTOPILOT_TESTS.keeps_guns_powered(self)


func test_run_screens_on_every_screen() -> void:
	var screens := SCREEN_TESTS.variants(SCREENS)
	for name: String in screens:
		var scr: Dictionary = screens[name]
		var probs: Array[String] = []
		for seed_value in 30:
			var chart := Run.create(seed_value).chart
			probs.append_array(RunLayout.build(scr, chart, "chart").problems())
			var l := RunLayout.build(scr, chart, "chart")
			for n in chart.nodes:
				if (l.button("beacon", n.id).rect as Rect2i).get_center() != l.beacon_pos(n):
					probs.append("beacon %s is off its hit box" % n.id)
		var chart0 := Run.create(1).chart
		var counts := {"event": 3, "next": 1}
		counts.merge(GEAR_TESTS.page_sizes())
		for mode: String in counts:
			var l := RunLayout.build(scr, chart0, mode, counts[mode])
			probs.append_array(l.problems())
			var own: String = {"event": "choice"}.get(mode, mode)
			if l.button(own).is_empty():
				probs.append("%s has no %s button" % [mode, own])
			for b in l.buttons:
				if (b.rect as Rect2i).end.y > scr.native.y - 4:
					probs.append("%s button falls off the bottom" % mode)
				if mode != "next" and (b.rect as Rect2i).intersects(l.text_rect):
					probs.append("%s button covers the text" % mode)
		check(probs.is_empty(), "%s run screens: %s" % [name, probs.slice(0, 4)])


## Faction hulls, captains' tactics, Reach Wardens and the intent readout:
## see tests/warden_tests.gd.
func test_enemy_factions_and_wardens() -> void:
	WARDEN_TESTS.factions_in_the_reaches(self)
	WARDEN_TESTS.weapon_eta(self)
	WARDEN_TESTS.volley_tactic(self)
	WARDEN_TESTS.focus_tactic(self)
	WARDEN_TESTS.warden_rules(self)
	WARDEN_TESTS.light_drain(self)
	WARDEN_TESTS.warden_holds_the_gate(self)
	WARDEN_TESTS.intent_readout(self)
	WARDEN_TESTS.enemy_crew_drawn_in_place(self)


## Reaches, refits and stoking (tests/progress_tests.gd), and the profile
## that outlives runs (tests/profile_tests.gd).
func test_progression() -> void:
	PROGRESS_TESTS.reaches_chain(self)
	PROGRESS_TESTS.refit_and_stoke(self)
	PROGRESS_TESTS.stories_last_the_run(self)
	PROGRESS_TESTS.enemies_grow(self)
	PROGRESS_TESTS.saves_keep_refits(self)
	PROGRESS_TESTS.content_checked(self)
	PROFILE_TESTS.records(self)
	PROFILE_TESTS.unlocks(self)
	PROFILE_TESTS.depth_ladder(self)
	PROFILE_TESTS.survives_damage(self)
	PROFILE_TESTS.counted_once_after_a_kill(self)
	PROFILE_TESTS.fixture_loads(self)
	PROFILE_TESTS.review_fixes(self)
	PROFILE_TESTS.content_checked(self)


## Modules, Chill guns and the store's gear pages (tests/gear_tests.gd).
func test_gear() -> void:
	GEAR_TESTS.modules_fit(self)
	GEAR_TESTS.chill_guns(self)
	GEAR_TESTS.store_pages(self)
	GEAR_TESTS.gear_found(self)
	GEAR_TESTS.run_costs(self)
	GEAR_TESTS.saves_keep_gear(self)
	GEAR_TESTS.content_checked(self)


## Item cards, tap to look, and the chart's key (tests/card_tests.gd).
func test_cards_and_chart_key() -> void:
	CARD_TESTS.every_option_has_a_card(self)
	CARD_TESTS.cards_explain_refusals(self)
	CARD_TESTS.tap_to_look(self)
	CARD_TESTS.chart_key(self, SCREEN_TESTS.variants(SCREENS))


func _test_gear_pages() -> void:
	GEAR_TESTS.pages_in_main(self)


func test_view_screens_follow_the_run() -> void:
	var main: Node = MAIN.new()
	main.screen = ScreenManager.compute(Vector2i(2400, 1080))
	var r := Run.create(77)
	main.run = r
	check(main.run_screen() == "chart", "a new run opens on the chart")
	r.outcome = "EV_ASH_TOLL_C1_O1"
	r._start_fight("ashmarket_skiff")  # results can start fights
	check(main.run_screen() == "outcome", "an event result is shown before the fight it starts")
	r.read_outcome()
	check(main.run_screen() == "fight", "then the fight")
	main.free()


# ------------------------------------------------------------------ feedback


func _feedback() -> FeedbackDirector:
	return FeedbackDirector.new(ContentDB.feedback.cues, GameSettings.new())


func test_weapon_ready_event() -> void:
	var c := Combat.create(5)
	var ready := 0
	for i in 400:  # 20 s: an unaimed gun charges once and then waits
		c.tick()
		for e: Dictionary in c.events:
			if e.type == "weapon_ready" and e.side == 0 and e.weapon == 0:
				ready += 1
	check(ready == 1, "an idle weapon says it is ready once, got %d" % ready)
	var a := Combat.create(5)
	var b := Combat.create(5)
	_aim_player(a)
	_aim_player(b)
	_run(a, 600)
	_run(b, 600)
	check(J.canonical(a.to_dict()) == J.canonical(b.to_dict()), "ready events keep fights seeded")


func test_feedback_cues_follow_events() -> void:
	var c := Combat.create(3)
	var f := _feedback()
	check(f.cue_for({"type": "hit", "side": 0, "room": "helm"}, c) == "hit.us", "we were hit")
	check(f.cue_for({"type": "hit", "side": 1, "room": "helm"}, c) == "hit.them", "we hit them")
	check(
		f.cue_for({"type": "fire", "side": 0, "weapon": 0}, c) == "fire.us.kinetic",
		"a fire cue picks the weapon family"
	)
	check(
		f.cue_for({"type": "fire", "side": 1, "weapon": 0}, c) == "fire.them",
		"falls back to the side cue when there is no family cue"
	)
	check(f.cue_for({"type": "won"}, c) == "won", "won has no side")
	check(f.cue_for({"type": "no_such_event", "side": 0}, c) == "", "unknown events are silent")
	check(
		f.cue_for({"type": "weapon_ready", "side": 0, "weapon": 0}, c) == "weapon_ready.us",
		"an idle gun pings when ready"
	)
	_aim_player(c)
	check(
		f.cue_for({"type": "weapon_ready", "side": 0, "weapon": 0}, c) == "",
		"an aimed gun fires instead of pinging"
	)
	f.on_sim_events([{"type": "hit", "side": 0, "room": "helm"}], c)
	var out := f.drain()
	check(out.size() == 1 and out[0].sound == "hull_hit_heavy", "a hit on us plays the heavy hit")
	check(out[0].haptic == "thud" and out[0].duck, "and thuds and ducks the music")
	check(f.drain().is_empty(), "drain empties the queue")
	f.on_sim_events([{"type": "hit", "side": 0, "room": "helm"}], c)
	check(f.drain().is_empty(), "the same cue on the same frame is merged by its cooldown")
	f.update(0.1)
	f.on_sim_events([{"type": "hit", "side": 0, "room": "helm"}], c)
	check(f.drain().size() == 1, "and plays again after it")
	c.player().hull = 1
	f.on_sim_events([], c)
	f.on_sim_events([], c)
	var danger := f.drain()
	check(danger.size() == 1 and danger[0].sound == "heartbeat", "low hull warns once")


func test_feedback_shake_and_hitstop() -> void:
	var c := Combat.create(3)
	var f := _feedback()
	check(f.shake_offset() == Vector2i.ZERO and not f.frozen(), "calm at the start")
	f.on_sim_events([{"type": "hit", "side": 0, "room": "helm"}], c)
	check(f.frozen(), "a heavy hit on us freezes the sim briefly")
	check(f.trauma > 0.0 and f.kick.x < 0.0, "and shoves the view toward our side")
	var off := f.shake_offset()
	check(off.x < 0, "the first jolt goes left, got %s" % off)
	for i in 4:
		f.update(0.02)
	check(not f.frozen(), "hit-stop ends within 80 ms")
	f.update(0.05)
	f.on_sim_events([{"type": "crew_died", "side": 0, "uid": 1, "room": "helm"}], c)
	check(not f.frozen(), "no second freeze right after the first: it would read as lag")
	for i in 60:
		f.update(0.05)
	check(f.shake_offset() == Vector2i.ZERO, "shake settles to nothing")
	f.on_sim_events([{"type": "won"}], c)
	check(f.frozen() and f.hitstop <= FeedbackDirector.MAX_HITSTOP, "a kill freezes, capped")
	var calm := FeedbackDirector.new(ContentDB.feedback.cues, GameSettings.new())
	calm.settings.shake = 0.0
	calm.settings.hitstop = false
	calm.on_sim_events([{"type": "won"}], c)
	check(calm.shake_offset() == Vector2i.ZERO, "shake 0 means no shake")
	check(not calm.frozen(), "hit-stop off means no freeze")
	var r := Run.create(8)
	r.hush = float(r.here().col) - FeedbackDirector.HUSH_NEAR
	check(FeedbackDirector.hush_closeness(r) == 0.0, "a far Hush leaves the music alone")
	r.hush = float(r.here().col)
	check(is_equal_approx(FeedbackDirector.hush_closeness(r), 1.0), "and eats it when it is here")


func test_feedback_content_is_checked() -> void:
	var bad: Dictionary = ContentDB.feedback.duplicate(true)
	bad.cues["hit.us"].sound = "no_such_sound"
	bad.haptics["tick"] = [[12, 3.0]]
	bad.sounds["ui_tick"].synth.wave = "kazoo"
	bad.music.states["chart"].layers = ["no_such_layer"]
	bad.cues["won"].hitstop = 1.0
	bad.sounds["ui_nope"].pitch_jitter = 1.5
	bad.music.clips.engage.layers.core = {"file": "res://audio/music/missing.ogg"}
	bad.cues["ui.tap"].priority = -1
	bad.sounds["crew_bell"].synth.freq_end = 55  # stays a sine: under 150 Hz a phone is silent
	bad.sounds["crew_bell"].synth.freq = 55
	var errors: Array[String] = []
	ContentDB._validate_feedback(bad, errors)
	check(errors.size() == 9, "every broken feedback field is caught, got %s" % [errors])
	var cues: Dictionary = ContentDB.feedback.cues
	check(cues.lost.sound != cues.won.sound, "losing doesn't sound like winning")


func test_haptic_patterns() -> void:
	var pulses: Array = []
	var rec := func(ms: int, amp: float) -> void: pulses.append([ms, amp])
	var h := Haptics.new(ContentDB.feedback.haptics, rec)
	check(h.play("thud", 3), "thud plays")
	check(pulses.size() == 1 and pulses[0][0] == 45, "its first pulse starts at once")
	check(not h.play("tick", 0), "a lower priority pattern can't cut in")
	h.update(0.05)
	check(pulses.size() == 2 and is_equal_approx(pulses[1][1], 0.4), "the second pulse follows")
	h.update(0.1)
	check(h.play("tick", 0), "once it is done anything can play")
	h.strength = 0.5
	h.update(0.1)
	h.play("tap", 0)
	check(is_equal_approx(pulses[-1][1], 0.3), "strength scales the amplitude")
	pulses.clear()
	h.play("tick", 0)
	check(pulses.is_empty(), "a new pattern waits out the gap after the last pulse")
	h.update(Haptics.MIN_GAP)
	check(pulses.size() == 1, "then plays")
	h.strength = 0.0
	check(not h.play("big_rumble", 4), "strength 0 is off")
	check(not h.play("no_such_pattern", 4), "unknown patterns are ignored")


func test_settings_save_and_fall_back() -> void:
	var dir := "user://test_saves"
	DirAccess.make_dir_recursive_absolute(dir)
	SaveService.erase(GameSettings.SLOT, dir)
	var fresh := GameSettings.load_or_default(dir)
	check(fresh.hitstop and fresh.shake == 1.0, "no file means the defaults")
	fresh.shake = 0.25
	fresh.reduce_flashing = true
	fresh.volume.Music = 0.0
	check(fresh.save(dir), "settings save")
	var back := GameSettings.load_or_default(dir)
	check(back.shake == 0.25 and back.reduce_flashing, "and load back")
	check(back.volume.Music == 0.0 and back.volume.SFX == 0.9, "per-bus volume survives")
	var keys: Array = GameSettings.new().volume.keys()
	keys.sort()
	var buses: Array = ["Master"] + Array(ContentDB.SOUND_BUSES)
	buses.sort()
	check(keys == buses, "settings hold a volume for exactly the sound buses")
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/settings_v1.json")
	)
	var up := SaveService.upgrade(raw)
	check(not up.is_empty(), "the settings fixture upgrades through the save versions")
	var old := GameSettings.from_dict(up.get("data", {}))
	check(old.shake == 0.25 and not old.hitstop and old.volume.Music == 0.0, "and loads as saved")
	var odd := GameSettings.from_dict({"shake": "loud", "haptics": 7, "hitstop": "yes"})
	check(odd.shake == 1.0 and odd.haptics == 1.0 and odd.hitstop, "bad values fall back or clamp")
	SaveService.erase(GameSettings.SLOT, dir)


# ------------------------------------------------------------------ audio
# The bodies live in tests/audio_tests.gd to keep this file under the lint limit.


func test_audio_service_and_music_states() -> void:
	AUDIO_TESTS.service_and_states(self)


func test_music_director_stages() -> void:
	AUDIO_TESTS.director_stages(self)


func test_music_clips_and_transitions() -> void:
	AUDIO_TESTS.clips_and_transitions(self)


func test_music_clips_are_synced_stems() -> void:
	AUDIO_TESTS.clips_are_synced_stems(self)


# ------------------------------------------------------------------ menus
# The bodies live in tests/menu_tests.gd to keep this file under the lint limit.


func test_menu_screens_on_every_screen() -> void:
	MENU_TESTS.screens(self, SCREEN_TESTS.variants(SCREENS))


func test_options_adjust_settings() -> void:
	MENU_TESTS.options_adjust(self)


## Also the cold-start resume: the app killed and reopened on its save.
func test_menu_flow() -> void:
	MENU_TESTS.flow(self)
	RESUME_TESTS.flow(self)


## The training lessons, tips, saving mid-step and where the coach writes, everywhere.
func test_tutorial() -> void:
	TUTORIAL_TESTS.lessons(self)
	TUTORIAL_TESTS.tips(self)
	var dir := "user://test_saves"
	DirAccess.make_dir_recursive_absolute(dir)
	TUTORIAL_TESTS.saves(self, dir)
	TUTORIAL_TESTS.layouts(self, SCREEN_TESTS.variants(SCREENS))


## Private so the runner stays under gdlint's public method limit; called by name.
func _test_tutorial_flow() -> void:
	TUTORIAL_TESTS.flow(self)


## The crew roster, driven through the real scene. Private like the tutorial flow.
func _test_crew_roster_flow() -> void:
	CREW_TESTS.roster_flow(self)


## The Kindling boss siege; see tests/siege_tests.gd for each check.
func test_kindling_siege() -> void:
	SIEGE_TESTS.starts_at_the_last_gate(self)
	SIEGE_TESTS.phases_follow_the_clock(self)
	SIEGE_TESTS.waves_telegraph_and_land(self)
	SIEGE_TESTS.wards_soak_waves(self)
	SIEGE_TESTS.guns_break_the_knot(self)
	SIEGE_TESTS.swallow_knocks_out_a_system(self)
	SIEGE_TESTS.kindling_wins_the_run(self)
	SIEGE_TESTS.ember_share_slows_kindling(self)
	SIEGE_TESTS.siege_resumes_identically(self)
	SIEGE_TESTS.autopilot_finishes_sieges(self)
	SIEGE_TESTS.content_is_checked(self)


func test_rents_and_flare() -> void:
	FIGHT_TESTS.run_all(self, SCREEN_TESTS.variants(SCREENS))
