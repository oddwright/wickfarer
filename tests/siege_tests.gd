extends RefCounted
## The Kindling siege checks for tests/run_tests.gd, kept here so that file stays
## under the lint limit. Each takes the runner, whose check() records the result.

const J = preload("res://scripts/core/json_util.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


## A run standing at Reach 4's Gate with `light` Light, then arriving there.
static func at_the_cradle(seed_value: int, light := 6) -> Run:
	var r := Run.create(seed_value, "tallow_wren", "reach_4")
	r.light = light
	Autopilot.arrive_at_gate(r)
	return r


static func _ticks(c: Combat, n: int, pilot: Autopilot = null) -> void:
	for i in n:
		if c.state != "fighting":
			return
		if pilot:
			pilot.combat_step(c)
		c.tick()


## Ticks until a wave starts gathering (or `limit` ticks pass).
static func _until_wave(c: Combat, limit := 400) -> bool:
	for i in limit:
		if c.siege.gathering():
			return true
		c.tick()
	return c.siege.gathering()


static func _events_of(c: Combat, n: int, type: String) -> Array:
	var out := []
	for i in n:
		if c.state != "fighting":
			break
		c.tick()
		for e: Dictionary in c.events:
			if e.type == type:
				out.append(e)
	return out


static func starts_at_the_last_gate(t: SceneTree) -> void:
	var r := at_the_cradle(1, 5)
	_check(t, r.state == "fight" and r.combat != null, "the last Gate opens on a fight")
	_check(t, r.combat.siege != null, "and that fight is the Kindling")
	_check(t, r.combat.enemy().content_id == "hush_maw", "against the Hush maw, not a hull")
	_check(t, r.combat.siege.light == 5, "the run's Light goes into the siege")
	_check(t, r.reaches_crossed == 0, "the Gate isn't crossed until the Cradle is kindled")
	# Earlier Gates still go to the Reach's end screen with no fight.
	var early := Run.create(1, "tallow_wren", "reach_1")
	Autopilot.arrive_at_gate(early)
	_check(t, early.state == "reach_done" and early.combat == null, "Reach 1's Gate has no siege")
	# An ordinary fight has no siege, and no kindling.
	var plain := Combat.create(3)
	_check(t, plain.siege == null, "ordinary fights have no siege")
	_check(t, not plain.apply({"type": "kindle"}), "kindle is refused outside a siege")


static func phases_follow_the_clock(t: SceneTree) -> void:
	var c := at_the_cradle(2).combat
	var sg := c.siege
	var p0 := float(sg.phases()[0].seconds)
	var p1 := float(sg.phases()[1].seconds)
	_check(t, sg.phase == 0 and not sg.is_last_phase(), "the siege opens in the first phase")
	_check(t, not c.apply({"type": "kindle"}), "no kindling before the last phase")
	# Godmode for the clock check: the waves mustn't end the fight first.
	c.player().max_hull = 999
	c.player().hull = 999
	var seen := []
	var pilot := Autopilot.new()
	for i in int((p0 + p1) / Combat.TICK) + 2:
		pilot.combat_step(c)
		c.tick()
		for e: Dictionary in c.events:
			if e.type == "siege_phase":
				seen.append([int(e.phase), c.time()])
	_check(t, seen.size() == 2, "two phase changes in the timed phases: %s" % [seen])
	if seen.size() == 2:
		_check(t, absf(float(seen[0][1]) - p0) < 0.11, "phase 2 starts on time")
		_check(t, absf(float(seen[1][1]) - p0 - p1) < 0.11, "phase 3 starts on time")
	_check(t, sg.is_last_phase(), "the last phase is reached")
	_check(t, sg.kindling > 0.0, "the Cradle kindles by itself in the last phase")


static func waves_telegraph_and_land(t: SceneTree) -> void:
	var c := at_the_cradle(3).combat
	var sg := c.siege
	var me := c.player()
	me.ward_layers = 0
	_check(t, _until_wave(c), "a wave gathers early in the siege")
	_check(t, sg.wave_kind == "chill", "the first phase only chills")
	_check(t, c.enemy().room(sg.knot).deck == sg.target_deck, "the knot faces the struck deck")
	var deck := sg.target_deck
	var hull := me.hull
	# Nothing to soak it: the ward is moved away and kept empty.
	var before := {}
	for r in me.rooms:
		before[r.id] = r.warmth
	var landed := []
	for i in int(sg.gather / Combat.TICK) + 2:
		me.ward_layers = 0
		c.tick()
		for e: Dictionary in c.events:
			if e.type == "wave_landed":
				landed.append(e)
	_check(t, landed.size() == 1, "the wave lands once its gather time is up")
	_check(t, me.hull == hull - int(sg.data().hull_per_wave), "an unwarded wave scrapes the hull")
	var colder := true
	for r in me.rooms:
		if r.deck == deck and r.warmth > float(before[r.id]) - 10.0:
			colder = false
	_check(t, colder, "an unwarded wave chills every room on its deck")
	_check(t, not sg.gathering(), "the knot sinks back after it lands")


static func wards_soak_waves(t: SceneTree) -> void:
	var c := at_the_cradle(4).combat
	var sg := c.siege
	var me := c.player()
	_check(t, _until_wave(c), "a wave gathers")
	me.ward_deck = sg.target_deck
	_ticks(c, 1)
	me.ward_layers = me.max_ward_layers()
	sg.strength = me.max_ward_layers()
	var layers_before := me.ward_layers
	var hull := me.hull
	var landed := _events_of(c, int(sg.gather / Combat.TICK) + 2, "wave_landed")
	_check(t, landed.size() == 1 and int(landed[0].left) == 0, "a full ward soaks the whole wave")
	_check(t, me.hull == hull, "a soaked wave doesn't touch the hull")
	# The soak spends a layer per point; the ward may have grown back one since.
	var spent := layers_before - me.ward_layers
	_check(
		t, spent >= layers_before - 1 and layers_before >= 1, "it costs ward layers (%d)" % spent
	)


static func guns_break_the_knot(t: SceneTree) -> void:
	var c := at_the_cradle(5).combat
	var sg := c.siege
	var me := c.player()
	_check(t, _until_wave(c), "a wave gathers")
	var knot := sg.knot
	# Ready every gun and aim it at the knot: they fire at once.
	for i in me.weapon_ids.size():
		me.weapon_charge[i] = float(ContentDB.weapons[me.weapon_ids[i]].charge)
		c.apply({"type": "aim", "weapon": i, "room": knot})
	var start := sg.strength
	var hits := 0
	var broken := false
	for i in int(sg.gather / Combat.TICK):
		c.tick()
		for e: Dictionary in c.events:
			hits += 1 if e.type == "knot_hit" else 0
			broken = broken or e.type == "wave_broken"
		if not sg.gathering():
			break
	_check(t, hits > 0, "shots on the gathering knot wear the wave down")
	_check(t, broken or sg.strength < start, "a knot hit takes strength off the wave")
	if broken:
		for i in me.weapon_ids.size():
			_check(t, me.weapon_target[i] != knot, "guns aimed at a broken knot stand down")
	# A shot into any other part of the Hush is swallowed.
	var lost := []
	sg.strike(me, "knot_low_aft" if knot != "knot_low_aft" else "knot_up_fore", 2, lost)
	_check(t, lost.size() == 1 and lost[0].type == "hush_absorb", "the rest of the Hush eats shots")
	# The maw has no hull to lose: shots never end the siege.
	_check(t, c.enemy().hull == int(ContentDB.ships.hush_maw.hull), "the maw's hull never drops")


static func swallow_knocks_out_a_system(t: SceneTree) -> void:
	var c := at_the_cradle(6).combat
	var sg := c.siege
	var me := c.player()
	sg.phase = 1
	sg.wave_timer = 0.0
	# Find a swallow: roll waves until one picks a system.
	var tries := 0
	while tries < 40:
		c.tick()
		if sg.gathering() and sg.wave_kind == "swallow":
			break
		if sg.gathering():
			sg._end_wave(me)
			sg.wave_timer = 0.0
		tries += 1
	_check(t, sg.wave_kind == "swallow", "the second phase sends swallow waves")
	if sg.wave_kind != "swallow":
		return
	var target := me.room(sg.target_room)
	_check(t, target.system in sg.phase_data().targets, "it targets a system from the phase list")
	_check(t, target.deck == sg.target_deck, "a swallow strikes its system's deck")
	me.ward_layers = 0
	var landed := []
	for i in int(sg.gather / Combat.TICK) + 2:
		me.ward_layers = 0
		c.tick()
		for e: Dictionary in c.events:
			if e.type == "swallowed":
				landed.append(e)
	_check(t, landed.size() == 1, "the swallow lands")
	_check(t, target.damage >= 1.0, "a swallowed system is broken until it is mended")


static func kindling_wins_the_run(t: SceneTree) -> void:
	var r := at_the_cradle(7, 4)
	var c := r.combat
	var sg := c.siege
	sg.phase = sg.phases().size() - 1
	var before := sg.kindling
	_check(t, c.apply({"type": "kindle"}), "the last phase takes Light")
	_check(t, sg.light == 3 and r.light == 4, "kindling spends the siege's Light")
	_check(t, sg.kindling == before + float(sg.data().kindle.per_light), "Light kindles the Cradle")
	c.player().hull = 999
	c.player().max_hull = 999
	var won := false
	for i in 4000:
		sg.wave_timer = 999.0  # a quiet Cradle: this checks the end, not the waves
		c.tick()
		if c.state != "fighting":
			won = c.state == "won"
			break
	_check(t, won, "the siege is won once the Cradle is kindled")
	_check(t, r.finish_fight(), "the run takes the siege's end")
	_check(t, r.state == "won" and r.is_over(), "kindling the Cradle wins the run")
	_check(t, r.reaches_crossed == 1, "and crosses the last Gate")
	_check(t, r.light == 3, "unburned Light comes back to the run")
	# A lost siege loses the run.
	var lost := at_the_cradle(8)
	lost.combat.player().hull = 0
	lost.combat.tick()
	_check(t, lost.combat.state == "lost", "a dead ship loses the siege")
	lost.finish_fight()
	_check(t, lost.state == "lost", "and the run")


static func ember_share_slows_kindling(t: SceneTree) -> void:
	var a := at_the_cradle(9).combat
	var b := at_the_cradle(9).combat
	for c: Combat in [a, b]:
		c.siege.phase = c.siege.phases().size() - 1
		c.siege.wave_timer = 999.0
	b.player().system_room("ember").damage = 1.0
	_ticks(a, 100)
	_ticks(b, 100)
	_check(t, b.siege.kindling < a.siege.kindling, "a swallowed Ember kindles slower")


static func siege_resumes_identically(t: SceneTree) -> void:
	var a := at_the_cradle(10).combat
	var pilot := Autopilot.new()
	_ticks(a, 1700, pilot)
	var b := Combat.from_dict(JSON.parse_string(J.s(a.to_dict())))
	_check(t, b.siege != null, "the siege survives a save")
	_check(t, J.canonical(b.to_dict()) == J.canonical(a.to_dict()), "a saved siege loads unchanged")
	_ticks(a, 1500, Autopilot.new())
	_ticks(b, 1500, Autopilot.new())
	_check(t, J.canonical(a.to_dict()) == J.canonical(b.to_dict()), "a resumed siege doesn't drift")
	# And through the whole run's save.
	var r := at_the_cradle(11)
	_ticks(r.combat, 900)
	var loaded := Run.from_dict(JSON.parse_string(J.s(r.to_dict())))
	_check(t, loaded.combat.siege != null and loaded.state == "fight", "a run saved mid-siege")
	_check(t, loaded.ship == loaded.combat.player(), "shares its ship with the siege")


static func autopilot_finishes_sieges(t: SceneTree) -> void:
	var ends := {}
	for s in 6:
		var c := at_the_cradle(100 + s).combat
		var pilot := Autopilot.new()
		var ticks := 0
		while c.state == "fighting" and ticks < 8000:
			pilot.combat_step(c)
			c.tick()
			ticks += 1
		ends[c.state] = int(ends.get(c.state, 0)) + 1
	_check(t, not ends.has("fighting"), "every siege ends inside the autopilot's limit: %s" % ends)


static func content_is_checked(t: SceneTree) -> void:
	var saved: Dictionary = ContentDB.sieges.kindling.duplicate(true)
	var cases := {
		"gather": func(d: Dictionary) -> void: d.phases[0].gather = 0.0,
		"wave_every": func(d: Dictionary) -> void: d.phases[0].wave_every = 1.0,
		"maw": func(d: Dictionary) -> void: d.maw = "ashmarket_cutter",
		"kinds": func(d: Dictionary) -> void: d.phases[0].kinds = {"boil": 1},
		"targets": func(d: Dictionary) -> void: d.phases[1].targets = [],
		"per_second": func(d: Dictionary) -> void: d.kindle.per_second = 0.0,
	}
	for what: String in cases:
		var d: Dictionary = saved.duplicate(true)
		cases[what].call(d)
		var errors: Array[String] = []
		Siege.validate("kindling", d, errors)
		_check(t, not errors.is_empty(), "a bad %s is caught" % what)
	var ok: Array[String] = []
	Siege.validate("kindling", saved, ok)
	_check(t, ok.is_empty(), "the shipped siege is valid: %s" % [ok])
	# The maw can't turn up as an ordinary enemy, and a boss Reach can't lead on.
	var reach: Dictionary = ContentDB.reaches.reach_1.duplicate(true)
	reach.enemies = ["hush_maw"]
	reach.boss = "kindling"
	var errs: Array[String] = []
	ContentDB._validate_reach("reach_1", reach, errs)
	_check(
		t, errs.size() == 2, "maw as an enemy and a boss with a next are both caught: %s" % [errs]
	)
