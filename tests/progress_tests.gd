extends RefCounted
## In-run progression checks for tests/run_tests.gd: the chain of Reaches,
## refits, stoking the Ember, enemies that grow with the Reach, and saves that
## keep all of it. Each takes the runner, whose check() records the result.

const J = preload("res://scripts/core/json_util.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


## Puts the run on the Gate of its current Reach, as if it had just jumped there.
static func _arrive_at_gate(r: Run) -> void:
	for n in r.chart.nodes:
		if n.kind == "gate":
			r.at = n.id
	r.state = "chart"
	r._arrive()


static func _in_store(seed_value: int) -> Run:
	var r := Run.create(seed_value)
	r.state = "store"
	return r


static func reaches_chain(t: SceneTree) -> void:
	var r := Run.create(11)
	_check(t, not r.next_reach(), "next_reach is refused away from a Gate")
	r.scrap = 33
	r.light = 5
	r.ship.hull -= 4
	var hull := r.ship.hull
	_arrive_at_gate(r)
	_check(t, r.state == "reach_done" and r.reaches_crossed == 1, "the first Gate opens the next")
	_check(t, not r.is_over(), "crossing a Gate is not the end of the run")
	var old_chart := J.canonical(r.chart.to_dict())
	r.hush = 3.0
	_check(t, r.next_reach(), "the player jumps through the Gate")
	_check(t, r.reach_id == "reach_2" and r.state == "chart", "into the second Reach, on its chart")
	_check(t, J.canonical(r.chart.to_dict()) != old_chart, "with a new chart")
	_check(t, r.visited == [r.at] and r.at == r.chart.start_id(), "starting at its start")
	_check(t, r.hush == float(r.reach().hush_start), "and the Hush starts over")
	_check(t, r.scrap == 33 and r.light == 5, "Scrap and Light carry on")
	var patched := mini(r.ship.max_hull, hull + int(ContentDB.reaches.reach_1.gate_repair))
	_check(t, r.ship.hull == patched, "and the ship, with the Gate's patch on its hull")
	_check(t, not r.next_reach(), "only once per Gate")
	var guard := 0
	while r.state != "won" and guard < 10:
		_arrive_at_gate(r)
		r.next_reach()
		guard += 1
	_check(t, r.state == "won" and r.is_over(), "the last Gate wins the run")
	_check(t, r.reaches_crossed == ContentDB.reaches.size(), "after crossing every Reach")
	_check(t, not r.next_reach() and r.jump_targets().is_empty(), "a won run goes nowhere")


static func refit_and_stoke(t: SceneTree) -> void:
	var r := _in_store(5)
	r.scrap = 500
	_check(t, not r.can_refit("helm"), "refits happen on the refit page only")
	_check(t, r.open_refit() and r.state == "refit", "the store opens the refit page")
	var helm := r.ship.system_room("helm")
	var lvl := helm.level
	var price := int(ContentDB.systems.helm.upgrade_scrap[lvl - 1])
	_check(t, r.refit_price("helm") == price, "the price comes from systems.json")
	var power := helm.power
	_check(t, r.refit("helm"), "a refit with scrap to spare goes through")
	_check(t, helm.level == lvl + 1 and r.scrap == 500 - price, "it raises the level for its price")
	_check(
		t,
		helm.power == power + 1 or r.ship.used_power() >= r.ship.available_power(),
		"the new level is powered when the reactor has room"
	)
	while r.refit("helm"):
		pass
	_check(t, helm.level == Ship.max_level("helm"), "refits stop at the cap")
	_check(t, r.refit_price("helm") == -1, "a capped system has no price")
	r.scrap = 0
	_check(t, not r.refit("mend"), "no refit without the scrap")
	_check(t, r.refit_price("weapons") == -1, "weapons aren't sold as refits yet")
	# Stoking: Light for reactor.
	var reactor := r.ship.reactor
	var light_price := int(ContentDB.systems.ember.stoke_light[0])
	r.light = light_price
	_check(t, r.stoke_price() == light_price and r.stoke(), "stoking costs Light")
	_check(t, r.ship.reactor == reactor + 1 and r.light == 0, "and adds one reactor power")
	_check(t, r.ship.stokes() == 1, "the ship counts its stokes")
	_check(t, not r.stoke(), "no stoking without the Light")
	r.light = 999
	while r.stoke():
		pass
	var cap: int = (ContentDB.systems.ember.stoke_light as Array).size()
	_check(t, r.ship.stokes() == cap and r.stoke_price() == -1, "stoking stops at its cap")
	_check(t, r.close_refit() and r.state == "store", "Back returns to the store")
	_check(t, not r.stoke() and not r.close_refit(), "nothing refits from the store itself")


static func enemies_grow(t: SceneTree) -> void:
	var base := Ship.from_content("ashmarket_cutter", 1)
	var r := Run.create(8, "tallow_wren", "reach_4")
	r._start_fight("ashmarket_cutter")
	var foe := r.combat.enemy()
	var boost: Dictionary = r.reach().enemy_boost
	_check(t, foe.max_hull == base.max_hull + int(boost.hull), "deep Reaches add enemy hull")
	_check(t, foe.reactor == base.reactor + int(boost.get("reactor", 0)), "and reactor")
	var raised := 0
	for sys: String in boost.systems:
		raised += foe.system_room(sys).level - base.system_room(sys).level
	_check(t, raised > 0, "and system levels, through the same upgrade as refits")
	_check(t, foe.used_power() <= foe.available_power(), "a boosted enemy stays within its reactor")
	var r1 := Run.create(8)
	r1._start_fight("ashmarket_cutter")
	_check(t, r1.combat.enemy().max_hull == base.max_hull, "the first Reach's enemies are as built")


static func saves_keep_refits(t: SceneTree) -> void:
	var r := _in_store(14)
	r.scrap = 200
	r.light = 20
	r.open_refit()
	r.refit("wards")
	r.refit("engines")
	r.stoke()
	var copy := Run.from_dict(JSON.parse_string(J.s(r.to_dict())))
	_check(
		t, J.canonical(copy.to_dict()) == J.canonical(r.to_dict()), "a refitted ship round-trips"
	)
	_check(
		t,
		copy.ship.system_room("wards").level == r.ship.system_room("wards").level,
		"room levels survive a save"
	)
	_check(t, copy.ship.reactor == r.ship.reactor, "the stoked reactor survives a save")
	_check(t, copy.state == "refit", "a save on the refit page reopens on it")
	# Through a Gate and into a fight in the next Reach, saved mid-fight.
	_arrive_at_gate(copy)
	copy.next_reach()
	copy._start_fight("ashmarket_cutter")
	for i in 40:
		copy.combat.tick()
	var again := Run.from_dict(JSON.parse_string(J.s(copy.to_dict())))
	_check(
		t,
		J.canonical(again.to_dict()) == J.canonical(copy.to_dict()),
		"a boosted fight round-trips"
	)
	for i in 100:
		copy.combat.tick()
		again.combat.tick()
	_check(
		t,
		J.canonical(again.to_dict()) == J.canonical(copy.to_dict()),
		"and plays on the same after loading"
	)
	# Saves from before refits keep the hull's own numbers.
	var d := r.to_dict()
	var ship_d: Dictionary = d.ship
	ship_d.erase("max_hull")
	ship_d.erase("reactor")
	for room: Dictionary in ship_d.rooms:
		room.erase("level")
	for k in ["reaches_crossed", "fights_won", "scrap_earned"]:
		d.erase(k)
	var old := Run.from_dict(d)
	var fresh := Ship.from_content(r.ship.content_id, 0)
	_check(t, old.ship.reactor == fresh.reactor, "an old save's reactor is the hull's own")
	_check(
		t,
		old.ship.system_room("wards").level == fresh.system_room("wards").level,
		"an old save's room levels are the hull's own"
	)
	_check(t, old.fights_won == 0 and old.reaches_crossed == 0, "old saves start run stats at 0")


static func content_checked(t: SceneTree) -> void:
	var keep: Dictionary = ContentDB.reaches.duplicate(true)
	var keep_sys: Dictionary = ContentDB.systems.duplicate(true)
	ContentDB.reaches.reach_2.next = "reach_1"
	_check(t, _has(ContentDB.validate(), "loops"), "a loop in the Reach chain is caught")
	ContentDB.reaches = keep.duplicate(true)
	ContentDB.reaches.reach_1.next = "reach_9"
	_check(t, _has(ContentDB.validate(), "unknown next Reach"), "an unknown next Reach is caught")
	ContentDB.reaches = keep.duplicate(true)
	ContentDB.reaches.reach_3.enemy_boost = {"systems": ["lasers"]}
	_check(t, _has(ContentDB.validate(), "unknown system lasers"), "a bad enemy boost is caught")
	ContentDB.reaches = keep
	ContentDB.systems.helm.upgrade_scrap = [10, 0]
	_check(t, _has(ContentDB.validate(), "whole numbers above 0"), "a bad refit price is caught")
	ContentDB.systems = keep_sys
	_check(t, ContentDB.validate().is_empty(), "the real content is valid again")


static func _has(errors: Array[String], part: String) -> bool:
	for e in errors:
		if part in e:
			return true
	return false
