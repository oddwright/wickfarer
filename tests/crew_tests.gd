extends RefCounted
## Crew posts, roles and skills, for tests/run_tests.gd (kept here so that
## file stays under the lint limit). Each takes the runner, whose check()
## records the result.

const J = preload("res://scripts/core/json_util.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


static func _run(c: Combat, ticks: int) -> void:
	for i in ticks:
		c.tick()


## A fight where nothing shoots, so only the crew rules move anything.
static func _quiet(seed_value := 5) -> Combat:
	var c := Combat.create(seed_value)
	for s in c.ships:
		for i in s.weapon_ids.size():
			s.weapon_target[i] = ""
	c.ai = _NoAI.new()
	return c


static func _crew_at(s: Ship, room_id: String) -> Crew:
	for c in s.alive_crew():
		if c.room == room_id:
			return c
	return null


static func posts_and_roles(t: SceneTree) -> void:
	var s := Ship.from_content("tallow_wren", 0)
	for c in s.crew:
		_check(t, c.post == c.room, "%s starts posted where they stand" % c.name)
	var pilot := _crew_at(s, "helm")
	_check(t, s.role_of(pilot) == "ROLE_PILOT", "the crew at the helm is the pilot")
	_check(t, s.set_post(pilot.uid, "galley"), "any room can be a post")
	_check(t, s.role_of(pilot) == Skills.ROLE_NONE, "a post with no station makes a deckhand")
	_check(t, not s.set_post(pilot.uid, "nowhere"), "an unknown room is refused")
	_check(t, s.set_post(pilot.uid, ""), "a post can be cleared")
	_check(t, s.role_of(pilot) == Skills.ROLE_NONE, "no post is a deckhand too")
	var c := _quiet()
	var me := c.player()
	var gunner := _crew_at(me, "weapons")
	_check(
		t, c.apply({"type": "post", "crew": gunner.uid, "room": "ember"}), "post is a player order"
	)
	_check(t, c.apply({"type": "muster"}), "muster sends someone off")
	_check(t, gunner.is_moving() and gunner.path.back() == "ember", "muster walks crew to posts")
	_check(t, not c.apply({"type": "muster"}), "a second muster has nobody left to send")
	_run(c, 200)
	_check(t, gunner.room == "ember" and not gunner.is_moving(), "the gunner reached the Ember")
	_check(t, me.role_of(gunner) == "ROLE_STOKER", "posted at the Ember, they are the stoker")
	gunner.room = "galley"
	gunner.fight_xp["stoke"] = 5.0
	me.recover_after_fight()
	_check(t, gunner.room == "ember", "after a fight crew are back at their posts")
	_check(t, gunner.fight_xp.is_empty(), "each fight starts a fresh practice cap")
	_check(t, gunner.skill_xp("stoke") == 5.0, "the fight's practice is banked")
	_check(t, not c.apply({"type": "post", "crew": 999, "room": "helm"}), "unknown crew refused")


static func learning(t: SceneTree) -> void:
	var c := _quiet()
	var me := c.player()
	var pilot := _crew_at(me, "helm")
	var events: Array = []
	_run(c, 20 * 10)
	_check(t, absf(pilot.practice("steer") - 10.0) < 0.1, "a pilot learns 1/s at a powered helm")
	var gunner := _crew_at(me, "weapons")
	_check(t, absf(gunner.practice("guns") - 10.0) < 0.1, "a gunner learns 1/s at a powered gun")
	var oru := _crew_at(me, "engines")
	oru.room = "wards"
	var wards_before := oru.practice("wards")
	me._tick_learning(1.0, events)
	_check(t, absf(oru.practice("wards") - wards_before - 1.5) < 0.01, "Oru learn Wards 1.5x")
	oru.room = "engines"
	# Cold rooms stop learning.
	var before := gunner.practice("guns")
	for i in 20:
		me.room("weapons").warmth = 10.0
		me._tick_learning(Combat.TICK, events)
	_check(t, gunner.practice("guns") == before, "nobody learns in a cold room")
	# An unpowered station teaches nothing.
	me.room("weapons").warmth = 60.0
	me.room("weapons").power = 0
	me._tick_learning(1.0, events)
	_check(t, gunner.practice("guns") == before, "an unpowered station teaches nothing")
	me.room("weapons").power = 3
	# A better hand in the room doubles it.
	var helper := _crew_at(me, "engines")
	helper.xp["guns"] = Skills.xp_for_rank(2)
	helper.room = "weapons"
	gunner.fight_xp.clear()
	before = gunner.practice("guns")
	me._tick_learning(1.0, events)
	_check(t, absf(gunner.practice("guns") - before - 2.0) < 0.01, "a mentor doubles learning")
	_check(
		t,
		absf(helper.practice("guns") - Skills.xp_for_rank(2) - 1.0) < 0.01,
		"the mentor practises at the gun too"
	)
	# The cap: one fight can't buy more than fight_cap of a skill.
	gunner.fight_xp.clear()
	gunner.xp["guns"] = 0.0
	for i in 200:
		me._tick_learning(1.0, events)
	_check(
		t, gunner.practice("guns") == Skills.num("fight_cap"), "practice is capped once per fight"
	)
	# Rank up raises an event.
	gunner.fight_xp.clear()
	gunner.xp["guns"] = Skills.xp_for_rank(1) - 0.5
	events.clear()
	me._tick_learning(1.0, events)
	var up := events.filter(func(e: Dictionary) -> bool: return e.type == "skill_up")
	_check(t, up.size() >= 1 and int(up[0].rank) == 1, "ranking up raises skill_up")
	_check(t, gunner.rank("guns") == 0, "a rank earned mid-fight waits for the fight to end")
	_check(t, me.promotions().size() >= 1, "the debrief lists the promotion")
	me.recover_after_fight()
	_check(t, gunner.rank("guns") == 1, "after the fight the rank is banked")
	_check(t, me.promotions().is_empty(), "nothing left to promote")
	# Masters stop counting practice.
	gunner.xp["guns"] = Skills.xp_for_rank(Skills.MAX_RANK)
	gunner.fight_xp.clear()
	me._tick_learning(1.0, events)
	_check(t, gunner.rank("guns") == Skills.MAX_RANK, "a master stays a master")
	_check(t, gunner.fight_xp.get("guns", 0.0) == 0.0, "a master gains no more practice")
	# Repairs teach Patch.
	var fixer := helper
	me.room("engines").damage = 1.0
	fixer.room = "engines"
	fixer.fight_xp.clear()
	var patch_before := fixer.practice("patch")
	me._tick_crew(1.0, events)
	_check(t, fixer.practice("patch") > patch_before, "repairing teaches Patch")


static func bonuses(t: SceneTree) -> void:
	var s := Ship.from_content("tallow_wren", 0)
	var pilot := _crew_at(s, "helm")
	var ev0 := s.evasion()
	pilot.xp["steer"] = Skills.xp_for_rank(3)
	_check(
		t,
		absf(s.evasion() - ev0 - 3.0 * Skills.per_rank("steer")) < 0.01,
		"a master pilot adds evasion"
	)
	_check(t, s.station_bonus("weapons", Ship.GUN_BOOST) == Ship.GUN_BOOST, "green gunner boost")
	_crew_at(s, "weapons").xp["guns"] = Skills.xp_for_rank(2)
	_check(
		t,
		s.station_bonus("weapons", Ship.GUN_BOOST) > Ship.GUN_BOOST,
		"a keen gunner charges faster"
	)
	_check(t, s.station_rank("mend") == -1, "nobody at mend")
	# Only the best hand counts: a second, greener gunner adds nothing.
	var keen := s.station_bonus("weapons", Ship.GUN_BOOST)
	_crew_at(s, "engines").room = "weapons"
	_check(t, s.station_bonus("weapons", Ship.GUN_BOOST) == keen, "bonuses don't stack")
	# A stoker makes the Ember room warmer.
	var a := _quiet(7)
	var b := _quiet(7)
	var q := _crew_at(b.player(), "wards")
	q.room = "ember"
	q.xp["stoke"] = Skills.xp_for_rank(3)
	_run(a, 100)
	_run(b, 100)
	_check(
		t,
		b.player().room("ember").warmth > a.player().room("ember").warmth,
		"a stoker heats the Ember room"
	)
	# Patch rank speeds repairs.
	var r1 := _repair_time(0)
	var r3 := _repair_time(3)
	_check(t, r3 < r1, "a master patcher repairs faster (%d vs %d ticks)" % [r3, r1])


static func _repair_time(rank: int) -> int:
	var s := Ship.from_content("tallow_wren", 0)
	var fixer := _crew_at(s, "engines")
	fixer.xp["patch"] = Skills.xp_for_rank(rank)
	s.room("engines").damage = 2.0
	var events: Array = []
	var ticks := 0
	while s.room("engines").damage > 0.0 and ticks < 2000:
		s._tick_crew(Combat.TICK, events)
		s.quantize()
		ticks += 1
	return ticks


static func ai_uses_posts(t: SceneTree) -> void:
	var c := Combat.create(11)
	var foe := c.enemy()
	var gunner := _crew_at(foe, "weapons")
	_check(t, gunner.post == "weapons", "enemy crew have posts too")
	gunner.room = "stores"
	c.ai.think(c, 1)
	_check(
		t,
		gunner.is_moving() and gunner.path.back() == "weapons",
		"the enemy captain sends idle crew back to their post"
	)


static func resume(t: SceneTree) -> void:
	var a := Combat.create(42)
	a.apply({"type": "aim", "weapon": 0, "room": "weapons"})
	a.apply({"type": "aim", "weapon": 1, "room": "weapons"})
	var k := 0
	for c in a.player().crew:
		c.xp["guns"] = Skills.xp_for_rank(k % 4) + 0.37
		c.xp["patch"] = 12.5
		k += 1
	a.apply({"type": "post", "crew": a.player().crew[0].uid, "room": "ember"})
	a.apply({"type": "muster"})
	_run(a, 400)
	var b := Combat.from_dict(JSON.parse_string(J.s(a.to_dict())))
	_check(
		t, J.canonical(b.to_dict()) == J.canonical(a.to_dict()), "crew skills load back the same"
	)
	_run(a, 600)
	_run(b, 600)
	_check(
		t,
		J.canonical(a.to_dict()) == J.canonical(b.to_dict()),
		"a resumed fight with skills in play doesn't drift"
	)
	var fixture: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/run_save_v2.json")
	)
	var up := SaveService.upgrade(fixture)
	var ship: Dictionary = up.data.run.ship
	for c: Dictionary in ship.crew:
		_check(t, c.has("post") and c.has("xp"), "v2 crew get a post and skills")
	var r := Run.from_dict(up.data.run)
	var posted := r.ship.crew.filter(func(c: Crew) -> bool: return c.post != "")
	_check(t, not posted.is_empty(), "v2 crew standing at stations keep them as posts")


## Stands in for the enemy captain so nothing moves on its own.
class _NoAI:
	extends CombatAI

	func think(_combat: Combat, _side: int) -> void:
		pass


## The roster fits every screen, with the picker open or shut, for up to 8 crew.
static func layouts(t: SceneTree, screens: Dictionary) -> void:
	var picks: Array[String] = ["helm", "weapons", "wards", "engines", "ember", "mend", ""]
	for name: String in screens:
		var scr: Dictionary = screens[name]
		var probs: Array[String] = []
		for n in [1, 4, 6, 8]:
			for p: Array[String] in [[] as Array[String], picks]:
				var l := CrewLayout.build(scr, n, p)
				for e in l.problems():
					probs.append("%d crew%s: %s" % [n, " picking" if p.size() > 0 else "", e])
				if l.rows.size() != n or l.button("post", n - 1).is_empty():
					probs.append("%d crew: a row is missing" % n)
		_check(t, probs.is_empty(), "%s roster: %s" % [name, probs.slice(0, 3)])


## The roster on the real scene: it pauses, sets posts, musters and gives the
## pause back as it was. Long press makes a crew member's room their post.
static func roster_flow(t: SceneTree) -> void:
	var dir := "user://test_saves"
	DirAccess.make_dir_recursive_absolute(dir)
	SaveService.erase("run", dir)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_dir = dir
	t.root.size = Vector2i(2400, 1080)
	t.root.add_child(main)
	var r := Run.create(9)
	r._start_fight("ashmarket_skiff")
	main._set_run(r)
	main._process(0.2)
	_check(t, not main.paused, "the fight runs")
	_tap(main, main.layout.button("crew").rect)
	_check(t, main.roster_open and main.paused, "Crew opens the roster and pauses")
	_check(t, main.crew_view.visible, "the roster is drawn")
	var t0: float = main.combat.time()
	main._process(1.0)
	_check(t, main.combat.time() == t0, "no ticks behind the roster")
	var crew: Array[Crew] = main.roster_crew()
	_tap(main, main.crew_layout.button("post", 0).rect)
	_check(t, main.roster_pick == 0, "a post button opens the picker")
	var picks: Array[String] = main.roster_picks()
	var ember := picks.find("ember")
	_tap(main, main.crew_layout.button("pick", ember).rect)
	_check(t, crew[0].post == "ember" and main.roster_pick == -1, "picking a station sets the post")
	_check(t, main.combat.player().role_of(crew[0]) == "ROLE_STOKER", "and their role follows")
	_tap(main, main.crew_layout.button("muster").rect)
	_check(t, not main.roster_open and not main.paused, "Muster closes the roster and resumes")
	_check(t, crew[0].is_moving() and crew[0].path.back() == "ember", "Muster sends crew to posts")
	# a fight paused before the roster stays paused after it
	main.paused = true
	main.open_roster()
	main.back()
	_check(t, not main.roster_open and main.paused, "Back closes the roster, still paused")
	main.paused = false
	# long press on a crew member makes their room their post
	var c := crew[1]
	var fp: Vector2 = main.world.crew_pos(0, c) + Vector2(0, -6)
	main._tap(fp * main.screen.scale, true)
	_check(t, c.post == (c.path.back() if c.is_moving() else c.room), "long press sets the post")
	main.queue_free()
	SaveService.erase("run", dir)


static func _tap(main: Node, rect: Rect2i) -> void:
	main._tap(Vector2(rect.get_center()) * main.screen.scale, false)
