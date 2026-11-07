extends RefCounted
## Checks on the balance tools' stand-in players (tools/autopilot.gd) for
## tests/run_tests.gd. The balance numbers only mean something if both players
## keep to the rules a player has, finish their runs, and resume the same.

const J = preload("res://scripts/core/json_util.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


## Both profiles play whole runs to a proper end. Skilled runs last far longer
## (they cross more Gates), so fewer of them are played.
static func runs_end(t: SceneTree) -> void:
	for profile: String in Autopilot.PROFILES:
		var ends := {}
		var runs := 12 if profile == "novice" else 2
		for i in runs:
			var r := Run.create(300 + i)
			var end := Autopilot.make(profile).play(r)
			ends[end] = int(ends.get(end, 0)) + 1
			_check(t, end in Run.ENDINGS, "%s run %d ended properly (got %s)" % [profile, i, end])
		print("  %s autopilot run endings: %s" % [profile, ends])


## The skilled player keeps no state of its own, so a run saved at any step
## and played on by a fresh one goes exactly the same way.
static func skilled_resumes(t: SceneTree) -> void:
	var pilot := Autopilot.make("skilled")
	var r := Run.create(21)
	for step in 30:
		if r.is_over():
			break
		var copy := Run.from_dict(JSON.parse_string(J.s(r.to_dict())))
		pilot.play(r, 1)
		Autopilot.make("skilled").play(copy, 1)
		_check(
			t,
			J.canonical(copy.to_dict()) == J.canonical(r.to_dict()),
			"skilled step %d: resumed run plays the same" % step
		)


## Every powered gun goes on the deck the enemy ward leaves open.
static func split_aim(t: SceneTree) -> void:
	var pilot := Autopilot.make("skilled")
	for hull in ShipRoster.playable():
		var c := Combat.create(1, hull)
		var me := c.player()
		var foe := c.enemy()
		var decks := pilot._gun_decks(me, foe)
		for i in me.weapon_ids.size():
			var want := 1 - foe.ward_deck if me.weapon_powered(i) else -1
			_check(t, decks[i] == want, "%s: gun %d aims at the open deck %s" % [hull, i, decks])


## When damage takes reactor power away, the skilled player moves power from
## the wards to keep its guns firing (left alone, the ship sheds guns first).
static func keeps_guns_powered(t: SceneTree) -> void:
	var c := Combat.create(1, "tallow_wren")
	var me := c.player()
	me.system_room("ember").damage = 2.0  # four reactor power gone: 8 -> 4
	me.enforce_power()
	_check(t, me.system_power("weapons") < 3, "the sim shed gun power")
	Autopilot.make("skilled").combat_step(c)
	_check(t, me.system_power("weapons") == 3, "the guns got their power back")
	_check(t, me.used_power() <= me.available_power(), "within the reactor")
	_check(t, me.system_power("wards") % 2 == 0, "wards keep whole layers")
