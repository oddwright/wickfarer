class_name EventRules
extends RefCounted
## The rules that decide which stories a run can be told and which choices it
## can take: an event's "when" (story flags, faction standing, Gates crossed),
## a choice's "requires" (scrap, Light, a species, a skill rank, a standing) and
## a choice's crew skill "check", whose odds the player sees before choosing.

const MIN_CHANCE := 5
const MAX_CHANCE := 95
const WHEN_KEYS := ["flag", "no_flag", "gates_at_least", "rep_at_least", "rep_at_most"]
const MAX_REP_STEP := 3  ## the most one outcome may move a faction


## Can this event be told now? Events without a "when" always can.
static func is_open(run: Run, e: Dictionary) -> bool:
	var w: Dictionary = e.get("when", {})
	for f in names(w.get("flag", [])):
		if not run.flags.has(f):
			return false
	for f in names(w.get("no_flag", [])):
		if run.flags.has(f):
			return false
	if run.reaches_crossed < int(w.get("gates_at_least", 0)):
		return false
	var least: Dictionary = w.get("rep_at_least", {})
	for f: String in least:
		if run.standing.of(f) < int(least[f]):
			return false
	var most: Dictionary = w.get("rep_at_most", {})
	for f: String in most:
		if run.standing.of(f) > int(most[f]):
			return false
	return true


## A story flag field is one name or a list of them.
static func names(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for n: Variant in v:
			out.append(str(n))
	elif v is String:
		out.append(v)
	return out


## Does the ship have what a choice asks for?
static func meets(run: Run, req: Dictionary) -> bool:
	if run.scrap < int(req.get("scrap", 0)) or run.light < int(req.get("light", 0)):
		return false
	if req.has("species") and not _has_species(run.ship, str(req.species)):
		return false
	if req.has("skill") and best_rank(run.ship, str(req.skill)) < int(req.get("rank", 1)):
		return false
	var rep: Dictionary = req.get("rep", {})
	for f: String in rep:
		if run.standing.of(f) < int(rep[f]):
			return false
	return true


static func _has_species(ship: Ship, sp: String) -> bool:
	for c in ship.alive_crew():
		if c.species == sp:
			return true
	return false


## The highest rank any living crew member has in a skill.
static func best_rank(ship: Ship, skill: String) -> int:
	var best := 0
	for c in ship.alive_crew():
		best = maxi(best, c.rank(skill))
	return best


## The percent chance a choice's skill check passes, or -1 if it has no check.
## The best crew member at the skill makes the attempt.
static func chance(run: Run, choice: Dictionary) -> int:
	var check: Dictionary = choice.get("check", {})
	if check.is_empty():
		return -1
	var rank := best_rank(run.ship, str(check.skill))
	var pct := int(check.get("base", 50)) + int(check.get("per_rank", 0)) * rank
	return clampi(pct, MIN_CHANCE, MAX_CHANCE)


## The outcomes a choice can lead to: for a skill check, only the pass or the
## fail ones, by one roll on the events stream.
static func outcomes_for(run: Run, choice: Dictionary) -> Array:
	var outcomes: Array = choice.get("outcomes", [])
	var pct := chance(run, choice)
	if pct < 0:
		return outcomes
	var side := "pass" if run.rng.stream("events").randi_range(1, 100) <= pct else "fail"
	return outcomes.filter(func(o: Dictionary) -> bool: return str(o.get("on", "")) == side)


# ---------------------------------------------------------------- content checks


## Checks the story parts of data/events.json that ContentDB leaves to these
## rules: "when", "faction", skill and standing requirements, checks, and the
## rep, flag and fight_faction effects. Every flag an event waits on must be set
## by some outcome, or that event could never be told.
static func validate(events: Dictionary, errors: Array[String]) -> void:
	var set_flags := {}
	for eid: String in events:
		for c: Dictionary in events[eid].get("choices", []):
			for o: Dictionary in c.get("outcomes", []):
				for flag in names(o.get("effects", {}).get("flag", [])):
					set_flags[flag] = true
	for eid: String in events:
		var e: Dictionary = events[eid]
		var where := "event %s" % eid
		if e.has("faction") and not Standing.has_faction(str(e.faction)):
			errors.append("%s: unknown faction %s" % [where, e.faction])
		_validate_when(where, e.get("when", {}), set_flags, errors)
		for c: Dictionary in e.get("choices", []):
			_validate_choice(where, c, errors)


static func _validate_when(
	where: String, w: Dictionary, set_flags: Dictionary, errors: Array[String]
) -> void:
	for k: String in w:
		if not k in WHEN_KEYS:
			errors.append("%s: unknown when %s" % [where, k])
	for k in ["flag", "no_flag"]:
		for f in names(w.get(k, [])):
			if not set_flags.has(f):
				errors.append("%s: no outcome sets the flag %s" % [where, f])
	var gates: Variant = w.get("gates_at_least", 0)
	if not (gates is float or gates is int) or int(gates) < 0 or float(gates) != int(gates):
		errors.append("%s: gates_at_least is a whole number of 0 or more" % where)
	for k in ["rep_at_least", "rep_at_most"]:
		if w.has(k) and not Standing.valid_map(w[k], Standing.floor_rep(), Standing.ceil_rep()):
			errors.append("%s: %s maps factions to standings in the range" % [where, k])


static func _validate_choice(where: String, c: Dictionary, errors: Array[String]) -> void:
	var req: Dictionary = c.get("requires", {})
	if req.has("skill") and not Skills.ids().has(str(req.skill)):
		errors.append("%s: unknown skill %s" % [where, req.skill])
	if req.has("rank") != req.has("skill") or int(req.get("rank", 1)) < 1:
		errors.append("%s: a skill requirement needs a rank of 1 or more" % where)
	if int(req.get("rank", 1)) > Skills.MAX_RANK:
		errors.append("%s: no rank above %d" % [where, Skills.MAX_RANK])
	if (
		req.has("rep")
		and not Standing.valid_map(req.rep, Standing.floor_rep(), Standing.ceil_rep())
	):
		errors.append("%s: requires rep maps factions to standings in the range" % where)
	var check: Dictionary = c.get("check", {})
	var sides := {}
	for o: Dictionary in c.get("outcomes", []):
		sides[str(o.get("on", ""))] = true
		_validate_story_effects(where, o.get("effects", {}), errors)
	if check.is_empty():
		if sides.has("pass") or sides.has("fail"):
			errors.append("%s: pass and fail outcomes need a check" % where)
		return
	if not Skills.ids().has(str(check.get("skill", ""))):
		errors.append("%s: a check needs a known skill" % where)
	var base := int(check.get("base", -1))
	var per := int(check.get("per_rank", -1))
	if base < 0 or base > 100 or per < 0 or per > 50:
		errors.append("%s: a check has a base of 0 to 100 and a per_rank of 0 to 50" % where)
	if sides.size() != 2 or not sides.has("pass") or not sides.has("fail"):
		errors.append("%s: a check's outcomes are each on pass or fail, with both" % where)


static func _validate_story_effects(where: String, fx: Dictionary, errors: Array[String]) -> void:
	if fx.has("rep") and not Standing.valid_map(fx.rep, -MAX_REP_STEP, MAX_REP_STEP):
		errors.append("%s: rep moves a faction by at most %d" % [where, MAX_REP_STEP])
	if fx.has("flag") and (names(fx.flag).is_empty() or names(fx.flag).has("")):
		errors.append("%s: a flag is a name or a list of names" % where)
	if fx.has("fight_faction"):
		if not fx.has("fight") or not Standing.has_faction(str(fx.fight_faction)):
			errors.append("%s: fight_faction is a known faction, with a fight" % where)
