class_name Profile
extends RefCounted
## What outlives a run: lifetime records, the Wake Log of recent runs, which
## unlocks are earned, and how deep the Hush Depth ladder goes.
## It never makes the ship stronger; unlocks add options, not power.
##
## Saved in its own slot the moment it changes (docs/SAVES.md). Runs are
## counted once each: a run's seed is remembered when it is recorded, so a
## kill between saving the profile and erasing the run can't count it twice.

const SLOT := "profile"
const PROFILE_VERSION := 1
const HISTORY := 20  ## runs kept in the Wake Log
const RECORDED := 50  ## seeds remembered so a replayed run isn't counted again
## Lifetime numbers, which unlock conditions can name as their "stat".
const STATS: Array[String] = [
	"runs", "wins", "best_gates", "fights_won", "scrap_earned", "jumps", "deepest_win"
]

var unlocked: Array[String] = []
var stats := {
	"runs": 0,
	"wins": 0,
	"best_gates": 0,
	"fights_won": 0,
	"scrap_earned": 0,
	"jumps": 0,
	"deepest_win": -1,
}
var depth_open := 0  ## the deepest Hush Depth the player may choose
var depth := 0  ## the depth the next run starts at; remembered between runs
var history: Array[Dictionary] = []  ## newest first: {seed, ship, depth, gates, end}
var recorded: Array[int] = []  ## seeds of runs already counted
## What the last note() or record() newly opened: unlock ids, and "depth" when
## a new Hush Depth opened. The end screens show these.
var fresh: Array[String] = []


static func load_or_default(dir := SaveService.DIR) -> Profile:
	return from_dict(SaveService.read(SLOT, dir))


func save(dir := SaveService.DIR) -> bool:
	return SaveService.write(SLOT, to_dict(), dir)


static func counts(run: Run) -> bool:
	## The training flight teaches; it doesn't count toward records or unlocks.
	return run != null and not bool(run.reach().get("training", false))


## Progress that can't be counted twice: the best Gate reached. Called on every
## Gate so an unlock lands the moment it is earned, not only when the run ends.
## Returns true if anything changed.
func note(run: Run) -> bool:
	fresh.clear()
	if not counts(run) or run.reaches_crossed <= int(stats.best_gates):
		return false
	stats.best_gates = run.reaches_crossed
	_check_unlocks()
	return true


## A run has ended: count it once, log it, and open the next depth on a win.
## Returns true if anything changed (false for a run already counted).
func record(run: Run) -> bool:
	fresh.clear()
	if not counts(run) or not run.is_over() or recorded.has(run.rng.run_seed):
		return false
	recorded.push_front(run.rng.run_seed)
	recorded.resize(mini(recorded.size(), RECORDED))
	var won := run.state == "won"
	stats.runs += 1
	stats.fights_won += run.fights_won
	stats.scrap_earned += run.scrap_earned
	stats.jumps += run.jumps
	stats.best_gates = maxi(int(stats.best_gates), run.reaches_crossed)
	if won:
		stats.wins += 1
		stats.deepest_win = maxi(int(stats.deepest_win), run.depth)
		if run.depth >= depth_open and depth_open < Profile.max_depth():
			depth_open = run.depth + 1
			fresh.append("depth")
	(
		history
		. push_front(
			{
				"seed": run.rng.run_seed,
				"ship": run.ship.content_id,
				"depth": run.depth,
				"gates": run.reaches_crossed,
				"end": run.state,
			}
		)
	)
	history.resize(mini(history.size(), HISTORY))
	_check_unlocks()
	return true


func is_unlocked(id: String) -> bool:
	return id == "" or unlocked.has(id)


func _check_unlocks() -> void:
	for id: String in ContentDB.unlocks:
		var u: Dictionary = ContentDB.unlocks[id]
		if not unlocked.has(id) and int(stats.get(str(u.stat), 0)) >= int(u.at_least):
			unlocked.append(id)
			fresh.append(id)


## How many Hush Depths there are past the plain game (depth 0).
static func max_depth() -> int:
	return (ContentDB.depths.get("depths", []) as Array).size()


## Steps the depth the next run starts at, within what is open.
func step_depth(dir: int) -> bool:
	var next := clampi(depth + dir, 0, depth_open)
	if next == depth:
		return false
	depth = next
	return true


func to_dict() -> Dictionary:
	return {
		"profile_version": PROFILE_VERSION,
		"unlocked": Array(unlocked),
		"stats": stats.duplicate(),
		"depth_open": depth_open,
		"depth": depth,
		"history": Array(history),
		"recorded": Array(recorded),
	}


## Missing or damaged fields fall back to a fresh profile's, field by field,
## so a bad value never costs the player the rest of their records.
static func from_dict(d: Dictionary) -> Profile:
	ContentDB.load_all()
	var p := Profile.new()
	for id: Variant in _list(d.get("unlocked")):
		if id is String and ContentDB.unlocks.has(id) and not p.unlocked.has(id):
			p.unlocked.append(id)
	var s: Variant = d.get("stats")
	if s is Dictionary:
		for k: String in STATS:
			if (s as Dictionary).get(k) is float or (s as Dictionary).get(k) is int:
				p.stats[k] = int(s[k])
	p.depth_open = clampi(_int(d.get("depth_open"), 0), 0, max_depth())
	p.depth = clampi(_int(d.get("depth"), 0), 0, p.depth_open)
	for h: Variant in _list(d.get("history")):
		if h is Dictionary and p.history.size() < HISTORY:
			p.history.append(_entry(h))
	for seed_value: Variant in _list(d.get("recorded")):
		if (seed_value is float or seed_value is int) and p.recorded.size() < RECORDED:
			p.recorded.append(int(seed_value))
	p._check_unlocks()  # content may have added an unlock the records already earn
	p.fresh.clear()
	return p


static func _entry(h: Dictionary) -> Dictionary:
	return {
		"seed": _int(h.get("seed"), 0),
		"ship": str(h.get("ship", "")),
		"depth": _int(h.get("depth"), 0),
		"gates": _int(h.get("gates"), 0),
		"end": "won" if str(h.get("end", "")) == "won" else "lost",
	}


static func _list(v: Variant) -> Array:
	return v if v is Array else []


static func _int(v: Variant, fallback: int) -> int:
	return int(v) if v is float or v is int else fallback
