extends RefCounted
## Enemy factions, their captains' tactics, the Reach Wardens and their rule
## twists, the Choir's Light drain, and the intent readout, for tests/run_tests.gd.
## Each takes the runner, whose check() records the result.

const J = preload("res://scripts/core/json_util.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


static func _ticks(c: Combat, n: int) -> void:
	for i in n:
		c.tick()


## Reaches 2 to 4 meet the new factions, and Reaches 1 to 3 each end at a Warden.
static func factions_in_the_reaches(t: SceneTree) -> void:
	var met := {}
	for rid in ["reach_2", "reach_3", "reach_4"]:
		for e: String in ContentDB.reaches[rid].enemies:
			met[str(ContentDB.ships[e].get("faction", ""))] = true
	for f in ["ashmarket", "tidewarden", "choir"]:
		_check(t, met.has(f), "the deeper Reaches meet the %s" % f)
	var rules := {}
	for rid in ["reach_1", "reach_2", "reach_3"]:
		var w := str(ContentDB.reaches[rid].get("warden", ""))
		_check(t, ContentDB.ships.has(w), "%s has a Warden at its Gate" % rid)
		var rule := str(ContentDB.ships.get(w, {}).get("rule", ""))
		_check(t, rule != "", "%s's Warden has a rule twist" % rid)
		rules[rule] = true
	_check(t, rules.size() == 3, "each Warden twists a different rule")
	_check(
		t,
		str(ContentDB.reaches.reach_4.get("warden", "")) == "",
		"the last Gate is left to the boss"
	)
	_validation_catches_bad_enemies(t)


static func _validation_catches_bad_enemies(t: SceneTree) -> void:
	var ship: Dictionary = ContentDB.ships.tidewarden_ketch
	var saved := ship.duplicate(true)
	ship["faction"] = "pirates"
	ship["rule"] = "gravity"
	ship["ai"] = {"volley": "yes", "targets": {"bridge": 2}, "ward_react": 0.1, "dance": true}
	var errors := " ".join(ContentDB.validate())
	for bit in ["unknown faction", "unknown fight rule", "ai.volley", "unknown system bridge"]:
		_check(t, bit in errors, "validation names a bad enemy field: %s" % bit)
	_check(t, "ai.ward_react" in errors and "unknown ai tactic dance" in errors, "and bad tactics")
	ContentDB.ships.tidewarden_ketch = saved
	ContentDB.reaches.reach_1["warden"] = "tallow_wren"
	_check(
		t,
		"is a hull the player can pick" in " ".join(ContentDB.validate()),
		"a Warden is no player hull"
	)
	ContentDB.reaches.reach_1["warden"] = "warden_tollkeeper"
	_check(t, ContentDB.validate().is_empty(), "content is valid again afterwards")


## A gun's countdown is its missing charge over its charge rate; unpowered, it has none.
static func weapon_eta(t: SceneTree) -> void:
	var c := Combat.create(5, "tallow_wren", "ashmarket_cutter")
	var foe := c.enemy()
	foe.weapon_charge[0] = 3.0
	var full := float(ContentDB.weapons[foe.weapon_ids[0]].charge)
	_check(
		t, absf(foe.weapon_eta(0) - (full - 3.0) / foe.charge_rate()) < 0.001, "eta is charge left"
	)
	foe.weapon_charge[0] = full
	_check(t, foe.weapon_eta(0) == 0.0, "a charged gun's eta is 0")
	while foe.system_power("weapons") > 0:
		foe.power_down("weapons")
	_check(t, foe.weapon_eta(0) < 0.0, "an unpowered gun has no eta")


## The Tidewarden holds its guns until all are charged, then they fire on one tick.
static func volley_tactic(t: SceneTree) -> void:
	var c := Combat.create(21, "tallow_wren", "tidewarden_ketch")
	var foe := c.enemy()
	var volleys := 0
	var alone := 0
	var aimed_early := 0
	for i in 600:
		var both := foe.weapon_powered(0) and foe.weapon_powered(1)
		c.tick()
		var shots := 0
		for e: Dictionary in c.events:
			if e.type == "fire" and int(e.side) == 1:
				shots += 1
		if shots == 2:
			volleys += 1
		elif shots == 1 and both:
			alone += 1
		# just after the captain looks, a gun is aimed only if every gun was ready
		if c.ai_timer == 0.0 and both and foe.weapon_target[0] != "":
			if foe.weapon_charge[0] > 0.0 and foe.weapon_charge[1] > 0.0:
				aimed_early += 1
	_check(t, volleys >= 2, "a volley captain fires (%d volleys)" % volleys)
	_check(t, alone == 0, "both guns fire on the same tick")
	_check(t, aimed_early == 0, "and its guns stay unaimed while they charge")


## The Choir puts every gun on one room, and it is usually the Ember.
static func focus_tactic(t: SceneTree) -> void:
	var same := true
	var ember := 0
	var looks := 0
	for s in 10:
		var c := Combat.create(300 + s, "tallow_wren", "choir_psalter")
		var foe := c.enemy()
		for i in 400:
			c.tick()
			if c.tick_count % 10 == 1 and foe.weapon_target[0] != "":
				looks += 1
				same = same and foe.weapon_target[1] in ["", foe.weapon_target[0]]
				if c.player().room(foe.weapon_target[0]).system == "ember":
					ember += 1
	_check(t, same, "a focused captain's guns follow the first gun")
	_check(t, ember * 3 > looks, "the Choir mostly sings at the Ember (%d of %d)" % [ember, looks])


## Tether: nobody evades. Tide: every 10 s both wards swap decks and keep their layers.
## Hymn: every room on both ships cools faster, only in that fight.
static func warden_rules(t: SceneTree) -> void:
	var c := Combat.create(8, "tallow_wren", "warden_tollkeeper")
	_check(t, c.rule() == "tether", "the Tollkeeper tethers")
	c.player().system_room("helm").power = 2
	_check(t, c.player().evasion() > 0.0 and c.evasion(0) == 0.0, "tethered ships can't evade")
	_check(t, c.evasion(1) == 0.0, "either of them")
	var plain := Combat.create(8)
	_check(t, plain.rule() == "" and plain.tide_eta() < 0.0, "an ordinary fight has no rule")
	_check(t, plain.evasion(1) == plain.enemy().evasion(), "and evasion as the ship has it")
	var tide := Combat.create(9, "tallow_wren", "warden_breakwater")
	_check(t, absf(tide.tide_eta() - Combat.TIDE_EVERY) < 0.001, "the tide turns 10 s in")
	_ticks(tide, roundi(Combat.TIDE_EVERY / Combat.TICK) - 1)
	var decks := [tide.player().ward_deck, tide.enemy().ward_deck]
	var layers := [tide.player().ward_layers, tide.enemy().ward_layers]
	_check(t, absf(tide.tide_eta() - Combat.TICK) < 0.001, "one tick before, the readout says so")
	tide.tick()
	var turned := tide.events.any(func(e: Dictionary) -> bool: return e.type == "tide")
	_check(t, turned, "the tide turns with an event")
	_check(
		t,
		tide.player().ward_deck == 1 - decks[0] and tide.enemy().ward_deck == 1 - decks[1],
		"both wards swap decks"
	)
	_check(
		t,
		tide.player().ward_layers >= layers[0] and tide.enemy().ward_layers >= layers[1],
		"and keep their layers"
	)
	var hymn := Combat.create(10, "tallow_wren", "warden_cantor")
	_check(t, hymn.rule() == "hymn" and hymn.chill() > 0.0, "the Cantor sings the hymn")
	var calm := Combat.create(10)
	_ticks(hymn, 200)
	_ticks(calm, 200)
	_check(
		t,
		hymn.player().room("galley").warmth < calm.player().room("galley").warmth,
		"a room cools faster under the hymn"
	)
	var back := Combat.from_dict(JSON.parse_string(J.s(hymn.to_dict())))
	_check(
		t, back.rule() == "hymn" and back.chill() == hymn.chill(), "a loaded fight keeps its rule"
	)
	var next := Combat.from_ship(11, hymn.player(), "ashmarket_cutter")
	_check(t, next.chill() == 0.0 and next.rule() == "", "the hymn ends with its fight")


## A Choir bell that lands takes Light; the run pays it once the fight is won.
static func light_drain(t: SceneTree) -> void:
	var c := Combat.create(4, "tallow_wren", "choir_psalter")
	var me := c.player()
	me.ward_layers = 0
	me.system_room("helm").power = 0  # no evasion, so the bell lands
	c._resolve({"owner": 1, "weapon": "dirge_bell", "slot": 0, "target": "galley", "t": 0.0})
	_check(t, c.light_drained[0] == 1, "a bell hit drains one Light")
	var back := Combat.from_dict(JSON.parse_string(J.s(c.to_dict())))
	_check(t, back.light_drained == c.light_drained, "the drain survives a save")
	var r2 := Run.create(31)
	r2._start_fight("choir_psalter")
	r2.light = 10
	r2.combat.light_drained[0] = 3
	r2.combat.enemy().hull = 0
	r2.combat.tick()
	var loot := RngStreams.from_dict(r2.rng.to_dict()).stream("loot")
	loot.randi_range(int(r2.reach().fight_reward.scrap[0]), int(r2.reach().fight_reward.scrap[1]))
	var reward: Array = r2.reach().fight_reward.light
	var gained := loot.randi_range(int(reward[0]), int(reward[1]))
	r2.finish_fight()
	_check(t, r2.light == 10 + gained - 3, "the run loses the drained Light after the reward")
	_check(t, r2.messages.has("UI_LIGHT_SUNG"), "and says where the Light went")
	var r3 := Run.create(31)
	r3._start_fight("choir_psalter")
	r3.light = 0
	r3.combat.light_drained[0] = 9
	r3.combat.enemy().hull = 0
	r3.combat.tick()
	r3.finish_fight()
	_check(t, r3.light == 0, "Light never goes below none")


static func _to_gate(r: Run) -> void:
	r.at = r.chart.gate_id()
	r.state = "chart"
	r._arrive()


## A Warden holds each Gate it is set for: the Gate is crossed only once it is beaten.
static func warden_holds_the_gate(t: SceneTree) -> void:
	var r := Run.create(12)
	r.ship.hull = 5
	_to_gate(r)
	_check(t, r.state == "fight" and r.is_warden_fight(), "the Gate opens with its Warden")
	var repair := int(r.reach().gate_repair)
	_check(t, r.ship.hull == 5 + repair, "the Gate's dock patches the hull before the Warden")
	_check(t, r.combat.enemy().content_id == "warden_tollkeeper", "Reach 1's Warden")
	_check(t, r.reaches_crossed == 0, "the Gate isn't crossed yet")
	var hull := r.combat.enemy().max_hull
	_check(t, hull == int(ContentDB.ships.warden_tollkeeper.hull), "a Warden skips the Reach boost")
	# saved mid-fight, it is still the Warden's fight
	var back := Run.from_dict(JSON.parse_string(J.s(r.to_dict())))
	_check(t, back.is_warden_fight() and back.combat.rule() == "tether", "a save keeps the Warden")
	back.combat.enemy().hull = 0
	back.combat.tick()
	back.finish_fight()
	_check(
		t, back.state == "reach_done" and back.reaches_crossed == 1, "beating it crosses the Gate"
	)
	_check(t, back.fights_won == 1, "and counts as a fight won")
	var after := back.ship.hull
	back.next_reach()
	_check(
		t, back.ship.hull == after, "and the hull isn't patched a second time on the way through"
	)
	# a Gate with no Warden still patches on the way through
	var warden: String = back.reach().warden
	back.reach().erase("warden")
	back.ship.hull = 5
	var patch := int(back.reach().gate_repair)
	_to_gate(back)
	_check(t, back.state == "reach_done", "a Gate with no Warden is open")
	_check(t, back.ship.hull == 5 + patch, "and patches the hull on arrival too")
	back.next_reach()
	_check(t, back.ship.hull == 5 + patch, "once")
	ContentDB.reaches.reach_2["warden"] = warden
	var lost := Run.create(12)
	_to_gate(lost)
	lost.combat.player().hull = 0
	lost.combat.tick()
	lost.finish_fight()
	_check(t, lost.state == "lost" and lost.reaches_crossed == 0, "losing to it ends the run")
	var deep := Run.create(12, "tallow_wren", "reach_3", 4)
	_to_gate(deep)
	var extra := int(deep.mod("enemy_hull"))
	_check(
		t,
		deep.combat.enemy().max_hull == int(ContentDB.ships.warden_cantor.hull) + extra,
		"the Hush Depth still toughens a Warden"
	)
	var last := Run.create(12, "tallow_wren", "reach_4")
	_to_gate(last)
	_check(t, last.state == "won", "a Gate with no Warden is crossed on arrival")


## The readout says, for each enemy gun, where it aims and when it fires.
static func intent_readout(t: SceneTree) -> void:
	var c := Combat.create(6, "tallow_wren", "ashmarket_cutter")
	var foe := c.enemy()
	c.apply({"type": "aim", "weapon": 0, "room": "ember"}, 1)
	foe.weapon_charge[0] = 4.0
	var eta := ceili(foe.weapon_eta(0))
	var wpn := TranslationServer.translate(ContentDB.weapons[foe.weapon_ids[0]].name)
	var line := IntentLayer.line(c, 0)
	_check(
		t, wpn in line and TranslationServer.translate("SYS_EMBER") in line, "it names gun and room"
	)
	_check(t, ("%d" % eta) in line, "and the seconds left (%s)" % line)
	foe.weapon_target[1] = ""
	_check(
		t,
		(
			IntentLayer.line(c, 1)
			== (
				TranslationServer.translate("UI_INTENT_IDLE")
				% TranslationServer.translate(ContentDB.weapons[foe.weapon_ids[1]].name)
			)
		),
		"an unaimed gun says so"
	)
	while foe.system_power("weapons") > 0:
		foe.power_down("weapons")
	_check(t, "NO POWER" in IntentLayer.line(c, 0).to_upper(), "an unpowered gun says so")
	var k := Combat.create(6, "tallow_wren", "tidewarden_ketch")
	_check(t, "VOLLEY" in IntentLayer.line(k, 0).to_upper(), "a held gun names the volley")
	_check(t, IntentLayer.rule_text(c) == "", "an ordinary fight has no rule line")
	var tide := Combat.create(6, "tallow_wren", "warden_breakwater")
	_check(t, "10" in IntentLayer.rule_text(tide), "the tide's line counts down")


## Enemy crew are drawn mirrored over the same box as the player's, so they stand in
## the room they are really in (they were drawn a cell aft, often in the next room).
static func enemy_crew_drawn_in_place(t: SceneTree) -> void:
	var fp := Vector2(120, 60)
	var mine := WorldView.crew_rect(0, fp)
	var theirs := WorldView.crew_rect(1, fp)
	_check(t, theirs.position == mine.position, "an enemy hand is drawn where it stands")
	_check(t, theirs.size.x == -mine.size.x and mine.size.x > 0, "facing the other way")
