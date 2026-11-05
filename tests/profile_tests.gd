extends RefCounted
## Profile checks for tests/run_tests.gd: records counted once per run, unlocks
## with visible conditions, the Hush Depth ladder, and a profile that survives
## damage and the app being killed mid-way. Each takes the runner.

const J = preload("res://scripts/core/json_util.gd")
const MAIN = preload("res://scripts/view/main.gd")
const DIR := "user://test_profile"


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


## A run that ended: won after every Gate, or lost after `gates` of them.
static func _ended(seed_value: int, won: bool, gates := 0, depth := 0) -> Run:
	var r := Run.create(seed_value, "tallow_wren", "reach_1", depth)
	r.reaches_crossed = 4 if won else gates
	r.fights_won = 3
	r.scrap_earned = 40
	r.jumps = 9
	r.state = "won" if won else "lost"
	return r


static func records(t: SceneTree) -> void:
	var p := Profile.new()
	var lost := _ended(1, false, 1)
	_check(t, p.record(lost), "a finished run is recorded")
	_check(t, not p.record(lost), "but only once, however often its last save replays")
	_check(
		t,
		p.stats.runs == 1 and p.stats.fights_won == 3 and p.stats.scrap_earned == 40,
		"its numbers add to the lifetime records"
	)
	_check(t, p.stats.best_gates == 1 and p.stats.wins == 0, "best Gate kept; a loss isn't a win")
	_check(t, p.history[0].end == "lost" and p.history[0].gates == 1, "the Wake Log lists it")
	var live := Run.create(2)
	_check(t, not p.record(live), "a run still going isn't recorded")
	var training := Run.create(3, "tallow_wren", "training")
	training.state = "won"
	_check(t, not p.record(training), "the training flight never counts")
	for i in Profile.HISTORY + 5:
		p.record(_ended(100 + i, false))
	_check(t, p.history.size() == Profile.HISTORY, "the Wake Log keeps the latest runs")
	_check(t, p.history[0].seed == 100 + Profile.HISTORY + 4, "newest first")
	_check(t, p.recorded.size() <= Profile.RECORDED, "remembered seeds are capped")


static func unlocks(t: SceneTree) -> void:
	var p := Profile.new()
	var r := Run.create(5)
	_check(t, not p.is_unlocked("hull_brine_cathedral"), "hulls start locked")
	_check(t, p.is_unlocked(""), "an empty unlock id means always open")
	r.reaches_crossed = 1
	r.state = "reach_done"
	_check(t, p.note(r), "crossing the first Gate is noted at once")
	_check(t, p.is_unlocked("hull_brine_cathedral"), "and opens the Brine Cathedral")
	_check(t, p.fresh == ["hull_brine_cathedral"], "the end screen hears what just opened")
	_check(t, not p.note(r), "noting the same Gate again changes nothing")
	_check(t, p.stats.runs == 0, "a Gate isn't a whole run")
	r.reaches_crossed = 3
	p.note(r)
	_check(t, p.is_unlocked("hull_porcelain_saint"), "the third Gate opens the Porcelain Saint")
	# A profile saved before an unlock existed gets it on load if earned.
	var d := Profile.new().to_dict()
	d.stats.best_gates = 3
	var loaded := Profile.from_dict(d)
	_check(t, loaded.is_unlocked("hull_porcelain_saint"), "earned unlocks arrive with new content")
	_check(t, loaded.fresh.is_empty(), "without announcing themselves on load")


static func depth_ladder(t: SceneTree) -> void:
	var p := Profile.new()
	_check(t, not p.step_depth(1), "no deeper depth before a win")
	p.record(_ended(10, true))
	_check(t, p.depth_open == 1 and p.fresh.has("depth"), "a win opens the next depth")
	_check(t, p.step_depth(1) and p.depth == 1, "which can then be chosen")
	p.record(_ended(11, true, 4, 0))
	_check(t, p.depth_open == 1, "winning a shallower depth again opens nothing new")
	for i in Profile.max_depth() + 3:
		p.record(_ended(20 + i, true, 4, p.depth_open))
	_check(t, p.depth_open == Profile.max_depth(), "the ladder stops at its last depth")
	_check(t, p.stats.deepest_win == Profile.max_depth(), "the deepest win is kept")
	# The rules each depth adds, through the run's one sum.
	var plain := Run.create(7)
	var deep := Run.create(7, "tallow_wren", "reach_1", 4)
	_check(t, deep.light == plain.light - 1, "depth 1: one less starting Light")
	_check(t, deep.price("repair") == plain.price("repair") + 1, "depth 4: stores charge more")
	deep.state = "store"
	deep.open_refit()
	plain.state = "store"
	plain.open_refit()
	_check(t, deep.refit_price("helm") == plain.refit_price("helm") + 1, "refits too")
	plain._start_fight("ashmarket_cutter")
	deep._start_fight("ashmarket_cutter")
	_check(
		t,
		deep.combat.enemy().max_hull == plain.combat.enemy().max_hull + 2,
		"depth 3: enemies have more hull"
	)
	var a := Run.create(9)
	var b := Run.create(9, "tallow_wren", "reach_1", 2)
	var target := a.jump_targets()[0]
	a.jump(target)
	b.jump(target)
	_check(t, b.hush > a.hush, "depth 2: the Hush moves faster")
	var copy := Run.from_dict(JSON.parse_string(J.s(b.to_dict())))
	_check(t, copy.depth == 2, "a run's depth survives a save")
	var old := b.to_dict()
	old.erase("depth")
	_check(t, Run.from_dict(old).depth == 0, "a run saved before depths is depth 0")


static func survives_damage(t: SceneTree) -> void:
	var p := Profile.new()
	p.record(_ended(1, true))
	p.step_depth(1)
	var round := Profile.from_dict(JSON.parse_string(J.s(p.to_dict())))
	_check(t, J.canonical(round.to_dict()) == J.canonical(p.to_dict()), "a profile round-trips")
	var bad := {
		"unlocked": ["hull_brine_cathedral", "no_such_unlock", 7],
		"stats": {"runs": "lots", "wins": 2},
		"depth_open": 99,
		"depth": -4,
		"history": [{"seed": 5, "end": "won"}, "junk"],
		"recorded": [5, "x"],
	}
	var q := Profile.from_dict(bad)
	_check(t, q.unlocked == ["hull_brine_cathedral"], "unknown unlocks are dropped")
	_check(t, q.stats.runs == 0 and q.stats.wins == 2, "a damaged stat falls back alone")
	_check(t, q.depth_open == Profile.max_depth() and q.depth == 0, "depths are clamped")
	_check(t, q.history.size() == 1 and q.recorded == [5], "damaged log entries are skipped")
	_check(t, Profile.from_dict({}).to_dict() == Profile.new().to_dict(), "no file, fresh profile")


## The app is killed after a run ends: before the profile is saved, or after
## it but before the run's save is erased. Either way the run counts once.
static func counted_once_after_a_kill(t: SceneTree) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for slot in ["run", Profile.SLOT]:
		SaveService.erase(slot, DIR)
	var r := _ended(4242, false, 1)
	# The run's end was saved, then the app died before the profile was.
	SaveService.write("run", {"run": r.to_dict()}, DIR)
	var main: Node = MAIN.new()
	main.save_dir = DIR
	main.profile = Profile.load_or_default(DIR)
	var resumed: Run = main._load_saved()
	_check(t, resumed == null, "a run saved at its end isn't offered to continue")
	var p := Profile.load_or_default(DIR)
	_check(t, p.stats.runs == 1, "but it is counted when the app comes back")
	# The same save replays again (the erase never happened): still once.
	main.profile = p
	main._load_saved()
	_check(t, Profile.load_or_default(DIR).stats.runs == 1, "and only once")
	main.free()
	SaveService.erase("run", DIR)
	SaveService.erase(Profile.SLOT, DIR)


static func content_checked(t: SceneTree) -> void:
	var keep_u: Dictionary = ContentDB.unlocks.duplicate(true)
	var keep_d: Dictionary = ContentDB.depths.duplicate(true)
	var keep_s: Dictionary = ContentDB.ships.duplicate(true)
	ContentDB.unlocks.hull_brine_cathedral.stat = "luck"
	_check(t, _has(ContentDB.validate(), "unknown stat luck"), "an unknown unlock stat is caught")
	ContentDB.unlocks = keep_u.duplicate(true)
	ContentDB.ships.tallow_wren["unlock"] = "hull_nowhere"
	_check(t, _has(ContentDB.validate(), "unknown unlock hull_nowhere"), "a bad hull unlock")
	ContentDB.ships = keep_s
	ContentDB.depths.depths[0].effects = {"start_light": 2}
	_check(t, _has(ContentDB.validate(), "must make the run harder"), "an easier depth is caught")
	ContentDB.depths = keep_d.duplicate(true)
	ContentDB.depths.depths[1].effects = {"free_scrap": 1}
	_check(t, _has(ContentDB.validate(), "unknown effect free_scrap"), "an unknown depth rule")
	ContentDB.depths = keep_d
	ContentDB.unlocks = keep_u
	_check(t, ContentDB.validate().is_empty(), "the real content is valid again")


static func _has(errors: Array[String], part: String) -> bool:
	for e in errors:
		if part in e:
			return true
	return false
