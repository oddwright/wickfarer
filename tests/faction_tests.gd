extends RefCounted
## Faction standing, story flags and crew skill checks, for tests/run_tests.gd
## (kept here so that file stays under the lint limit). Each takes the runner,
## whose check() records the result.

const J = preload("res://scripts/core/json_util.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


## A run sitting on one event, as if the ship had just arrived at it.
static func _at_event(eid: String, seed_value := 7) -> Run:
	var r := Run.create(seed_value)
	r.state = "event"
	r.event_id = eid
	return r


static func _set_rank(r: Run, skill: String, rank: int) -> void:
	for c in r.ship.alive_crew():
		c.xp[skill] = Skills.xp_for_rank(rank)


static func standing_rules(t: SceneTree) -> void:
	var s := Standing.fresh()
	_check(t, s.of("ashmarket") == 0 and s.of("choir") == 0, "every faction starts neutral")
	_check(t, s.change("ashmarket", -99) == -5 - 0, "standing stops at the bottom of the range")
	_check(t, str(s.tier("ashmarket").name) == "REP_HOSTILE", "the bottom is Hostile")
	_check(t, s.price_delta("ashmarket") == 2, "a hostile faction charges more")
	s.change("ashmarket", 9)
	_check(t, s.of("ashmarket") == 4 and s.price_delta("ashmarket") == -2, "a sworn one less")
	_check(t, s.change("nobody", 3) == 0 and s.price_delta("") == 0, "no faction, no change")
	var news := s.fight_won("ashmarket")
	_check(t, s.of("ashmarket") == 3 and s.of("tidewarden") == 1, "a win angers, the rival likes")
	_check(t, Array(news) == ["REP_BEATEN_ASHMARKET"], "a win says so in one line")
	_check(t, Standing.from_dict({"choir": 99, "gone": 2}).of("choir") == 5, "a save is clamped")


## A faction's store prices follow its view of the ship, and only its own store.
static func store_prices(t: SceneTree) -> void:
	var r := _at_event("chained_bazaar")
	var plain := r.price("repair")
	r.standing.change("ashmarket", -5)
	r.choose(0)
	_check(t, r.state == "store" and r.store_faction == "ashmarket", "the bazaar is Ashmarket's")
	_check(t, r.price("repair") == plain + 2, "a hostile market marks prices up")
	r.standing.change("ashmarket", 10)
	_check(t, r.price("repair") == maxi(1, plain - 2), "a friendly market marks them down")
	_check(t, r.price("repair") >= 1, "a discount never makes anything free")
	r.leave_store()
	_check(t, r.store_faction == "" and r.price("repair") == plain, "other stores pay plain prices")
	var indie := _at_event("lit_post")
	indie.standing.change("ashmarket", -5)
	indie.choose(0)
	_check(t, indie.store_faction == "", "an independent post has no faction")


## Events move standing and say so, and fights against a faction move it once won.
static func events_and_fights(t: SceneTree) -> void:
	var r := _at_event("tidewarden_patrol")
	r.light = 3
	r.choose(0)
	_check(t, r.standing.of("tidewarden") == 1, "showing the Ember pleases the wardens")
	_check(t, r.messages.has("REP_UP_TIDEWARDEN"), "the result says the wardens noticed")
	r.read_outcome()
	_check(t, r.messages.is_empty(), "once read, the news leaves the chart's message line")
	var b := _at_event("buoy_toll")
	b.ship.crew[0].species = "kith"
	while b.state == "event" or b.state == "chart":  # until the trick turns into a fight
		b = _at_event("buoy_toll", b.rng.run_seed + 1)
		b.ship.crew[0].species = "kith"
		b.choose(2)
	_check(t, b.fight_faction == "ashmarket", "an event's fight is its faction's by default")
	var f := _at_event("ash_toll")
	f.choose(2)
	_check(t, f.state == "fight" and f.fight_faction == "ashmarket", "refusing fights the market")
	f.combat.state = "won"
	f.finish_fight()
	_check(t, f.standing.of("ashmarket") == -1, "beating the market's cutter angers it")
	_check(t, f.standing.of("tidewarden") == 1, "and pleases its rival")
	_check(t, Array(f.messages) == ["REP_BEATEN_ASHMARKET"], "the chart says so")
	_check(t, f.fight_faction == "", "the fight's faction is cleared")


## A Reach's pool sends more of a faction's hulls the less it likes the ship.
static func ambush_weights(t: SceneTree) -> void:
	var cutter: Dictionary = ContentDB.ships.ashmarket_cutter
	var before := cutter.duplicate()
	cutter["faction"] = ""  # the skiff stays the market's; the cutter is nobody's here
	var counts := {}
	for rep in [-5, 5]:
		var r := Run.create(11)
		r.standing.change("ashmarket", rep)
		var skiffs := 0
		for i in 600:
			skiffs += 1 if r._pick_enemy() == "ashmarket_skiff" else 0
		counts[rep] = skiffs
	_check(
		t, int(counts[-5]) > int(counts[5]) + 100, "a hostile faction ambushes more: %s" % counts
	)
	var f := Run.create(12)
	f._start_fight("ashmarket_skiff")
	_check(t, f.fight_faction == "ashmarket", "a fight takes its faction from the hull")
	f._start_fight("ashmarket_cutter")
	_check(t, f.fight_faction == "", "a hull with no faction is nobody's")
	var own := 0
	for i in 40:
		own += 1 if f._pick_enemy("ashmarket") == "ashmarket_skiff" else 0
	_check(t, own == 40, "a faction's fight draws only its own hulls")
	_check(t, f._pick_enemy("choir") != "", "a faction with no hulls in the Reach gets any")
	cutter.clear()
	cutter.merge(before)


## Stories wait on flags, Gates and standing; a chain plays in order.
static func story_gates(t: SceneTree) -> void:
	var r := Run.create(3)
	var ev: Dictionary = ContentDB.events
	_check(t, EventRules.is_open(r, ev.rival_first), "the rival can turn up from the start")
	_check(t, not EventRules.is_open(r, ev.rival_ambush), "her ambush waits for a grudge")
	_check(t, not EventRules.is_open(r, ev.warden_escort), "an escort waits for trust")
	_check(t, not EventRules.is_open(r, ev.ash_hunters), "hunters wait for a grudge")
	r.standing.change("ashmarket", -3)
	_check(t, EventRules.is_open(r, ev.ash_hunters), "a hostile market sends hunters")
	r.standing.change("tidewarden", 2)
	_check(t, EventRules.is_open(r, ev.warden_escort), "trusted wardens offer an escort")
	var a := _at_event("rival_first", 3)
	_set_rank(a, "steer", 3)
	a.choose(0)
	_check(t, a.flags.has("met_gall") and a.flags.has("gall_grudge"), "racing her sets a grudge")
	_check(t, not EventRules.is_open(a, ev.rival_first), "she is only met once")
	_check(t, not EventRules.is_open(a, ev.rival_ambush), "she comes back after a Gate")
	a.reaches_crossed = 1
	_check(t, EventRules.is_open(a, ev.rival_ambush), "and then she does")
	_check(t, not EventRules.is_open(a, ev.rival_aid), "a rival with a grudge brings no gifts")
	# The pick only offers open stories.
	var p := Run.create(4)
	for i in 40:
		var eid := p._pick_event("fight")
		_check(t, EventRules.is_open(p, ev[eid]), "picked fight story %s is open" % eid)


## Skill checks show their odds, roll once, and take the pass or the fail side.
static func skill_checks(t: SceneTree) -> void:
	var r := _at_event("cracked_core")
	_set_rank(r, "patch", 0)
	_check(t, r.check_chance(0) == 30, "a Green crew has the base odds")
	_check(t, r.check_chance(2) == -1, "a choice with no check has no odds")
	_check(t, not r.can_choose(1), "the Keen mender's choice is locked without one")
	r.ship.alive_crew()[0].xp["patch"] = Skills.xp_for_rank(2)
	_check(t, r.check_chance(0) == 70, "the best crew member makes the attempt")
	_check(t, r.can_choose(1), "and a Keen mender opens the sure choice")
	var passes := 0
	for s in 60:
		var c := _at_event("cracked_core", s)
		_set_rank(c, "patch", 0)
		var light := c.light
		c.choose(0)
		var won := c.light == light + 2
		_check(t, won or c.outcome == "EV_CRACKED_CORE_C1_O2", "seed %d: pass or fail only" % s)
		passes += 1 if won else 0
	_check(t, passes > 6 and passes < 32, "a 30%% check passes about that often: %d/60" % passes)
	# The roll is part of the saved RNG, so a resumed save makes the same choice come out the same.
	var a := _at_event("ion_squall", 21)
	var b := Run.from_dict(JSON.parse_string(J.s(a.to_dict())))
	a.choose(0)
	b.choose(0)
	_check(t, a.outcome == b.outcome and a.hush == b.hush, "a check resumes identically")
	var w := _at_event("warden_depot")
	_check(t, not w.can_choose(2), "a favor needs the wardens' trust")
	w.standing.change("tidewarden", 2)
	_check(t, w.can_choose(2), "and trust opens it")


static func saves_keep_standing(t: SceneTree) -> void:
	var r := _at_event("tide_dock")
	r.standing.change("choir", -4)
	r.flags.append("met_cantor")
	r.choose(0)
	var back := Run.from_dict(JSON.parse_string(J.s(r.to_dict())))
	_check(t, back.standing.of("choir") == -4, "standing survives a save")
	_check(t, back.flags == r.flags, "story flags survive a save")
	_check(t, back.store_faction == "tidewarden", "the store's faction survives a save")
	var f := _at_event("ash_toll")
	f.choose(2)
	var fb := Run.from_dict(JSON.parse_string(J.s(f.to_dict())))
	_check(t, fb.fight_faction == "ashmarket", "the fight's faction survives a save")
	var old := r.to_dict()
	for k in ["standing", "flags", "store_faction", "fight_faction"]:
		old.erase(k)
	var o := Run.from_dict(JSON.parse_string(J.s(old)))
	_check(t, o.standing.of("choir") == 0 and o.flags.is_empty(), "an older run starts neutral")


static func content_checked(t: SceneTree) -> void:
	var bad: Array[String] = []
	var ev := {
		"x":
		{
			"text": "EV_LIT_POST",
			"faction": "lamplighters",
			"when": {"flag": "never_set", "soon": 1, "rep_at_most": {"choir": 9}},
			"choices":
			[
				{
					"text": "EV_LIT_POST_C1",
					"requires": {"rank": 2, "rep": {"choir": 1}},
					"check": {"skill": "dance", "base": 120, "per_rank": 20},
					"outcomes":
					[
						{
							"weight": 1,
							"text": "EV_LIT_POST_C1_O1",
							"on": "pass",
							"effects": {"rep": {"choir": 4}, "fight_faction": "choir"}
						}
					]
				},
				{
					"text": "EV_LIT_POST_C2",
					"requires": {},
					"outcomes":
					[{"weight": 1, "text": "EV_LIT_POST_C2_O1", "on": "fail", "effects": {}}]
				}
			]
		}
	}
	EventRules.validate(ev, bad)
	var all := " | ".join(bad)
	for want in [
		"unknown faction lamplighters",
		"unknown when soon",
		"no outcome sets the flag never_set",
		"rep_at_most maps",
		"needs a rank",
		"a check needs a known skill",
		"a base of 0 to 100",
		"each on pass or fail",
		"at most 3",
		"fight_faction is a known faction, with a fight",
		"pass and fail outcomes need a check",
		"requires rep is where a tier starts",
	]:
		_check(t, all.contains(want), "the story check catches: %s" % want)
	bad.clear()
	Standing.validate(bad)
	_check(t, bad.is_empty(), "factions.json is valid: %s" % [bad])


## A real version 6 save, kept as a fixture: docked at a Tidewarden store.
static func fixture_keeps_standing(t: SceneTree) -> void:
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/run_save_v6.json")
	)
	var up := SaveService.upgrade(raw)
	var r := Run.from_dict(up.get("data", {}).get("run", {}))
	_check(t, r.state == "store" and r.store_faction == "tidewarden", "the fixture is docked")
	_check(
		t, r.standing.of("tidewarden") == 3 and r.standing.of("ashmarket") == -2, "standing kept"
	)
	_check(t, r.flags.has("gall_friend"), "story flags kept")
	_check(t, r.price("repair") == int(r.reach().store.repair_scrap) - 1, "trusted prices kept")
