class_name Skills
extends RefCounted
## Crew skills: what each one is called, which stations train it, and how
## practice turns into ranks. The numbers live in data/skills.json; Ship
## applies the bonuses, so player and enemy crew follow the same rules.

const MAX_RANK := 3
const ROLE_NONE := "ROLE_DECKHAND"  ## a crew member with no post

## Read on every tick, so built once from the content rather than per call.
static var _thresholds: Array[float] = []
static var _by_station: Dictionary = {}
static var _cached_for: Dictionary = {}  ## the skills data the caches were built from


static func data() -> Dictionary:
	return ContentDB.skills


static func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign((data().get("skills", {}) as Dictionary).keys())
	return out


static func spec(skill: String) -> Dictionary:
	return data().skills.get(skill, {})


static func per_rank(skill: String) -> float:
	return float(spec(skill).get("per_rank", 0.0))


## The skill a station trains, or "" for a room with no station skill.
static func for_station(sys: String) -> String:
	_cache()
	return _by_station.get(sys, "")


## Practice needed to reach each rank, starting with 0 for Green.
static func thresholds() -> Array[float]:
	_cache()
	return _thresholds


static func _cache() -> void:
	if is_same(_cached_for, data()) and not _thresholds.is_empty():
		return
	_cached_for = data()
	_thresholds.clear()
	for t in data().get("ranks", [0]):
		_thresholds.append(float(t))
	_by_station.clear()
	for id: String in data().get("skills", {}):
		for sys in data().skills[id].get("stations", []):
			_by_station[str(sys)] = id


static func rank_for(xp: float) -> int:
	var t := thresholds()
	var r := 0
	for i in range(1, t.size()):
		if xp >= t[i]:
			r = i
	return r


## The practice a crew member starts with at a given rank.
static func xp_for_rank(rank: int) -> float:
	var t := thresholds()
	return t[clampi(rank, 0, t.size() - 1)]


static func rank_name(rank: int) -> String:
	var names: Array = data().get("rank_names", [])
	return str(names[clampi(rank, 0, names.size() - 1)]) if not names.is_empty() else ""


static func num(key: String) -> float:
	return float(data().get(key, 0.0))


## Problems with data/skills.json and the skill fields other files use.
static func validate(errors: Array[String]) -> void:
	var d := data()
	var ranks: Array = d.get("ranks", [])
	if ranks.size() != MAX_RANK + 1 or float(ranks[0]) != 0.0:
		errors.append("skills: ranks needs %d entries starting at 0" % (MAX_RANK + 1))
	for i in range(1, ranks.size()):
		if float(ranks[i]) <= float(ranks[i - 1]):
			errors.append("skills: ranks must rise")
	var names: Array = d.get("rank_names", [])
	if names.size() != ranks.size():
		errors.append("skills: one rank name per rank")
	for n in names:
		ContentDB.check_string(str(n), "skills rank", errors)
	for k in ["fight_cap", "learn_warmth", "mentor", "patch_xp_per_damage", "patch_xp_per_fire"]:
		if not _is_num(d.get(k)) or float(d[k]) < 0.0:
			errors.append("skills: %s must be a number >= 0" % k)
	var seen := {}
	for id: String in d.get("skills", {}):
		var s: Dictionary = d.skills[id]
		ContentDB.check_string(s.get("name", ""), "skill %s" % id, errors)
		ContentDB.check_string(s.get("short", ""), "skill %s" % id, errors)
		if not _is_num(s.get("per_rank")):
			errors.append("skill %s: missing per_rank" % id)
		for sys in s.get("stations", []):
			if not ContentDB.systems.has(sys):
				errors.append("skill %s: unknown station %s" % [id, sys])
			elif seen.has(sys):
				errors.append("skill %s: station %s already trains %s" % [id, sys, seen[sys]])
			seen[sys] = id
	for id in ["steer", "guns", "wards", "stoke", "patch"]:
		if not (d.get("skills", {}) as Dictionary).has(id):
			errors.append("skills: missing %s (Ship applies it)" % id)
	for sp: String in ContentDB.species:
		for k: String in ContentDB.species[sp].get("learns", {}):
			if not ids().has(k):
				errors.append("species %s: learns unknown skill %s" % [sp, k])
			elif float(ContentDB.species[sp].learns[k]) <= 0.0:
				errors.append("species %s: learns %s must be > 0" % [sp, k])
	for sys: String in ContentDB.systems:
		ContentDB.check_string(ContentDB.systems[sys].get("role", ""), "system %s" % sys, errors)
	ContentDB.check_string(ROLE_NONE, "skills", errors)


static func _is_num(v: Variant) -> bool:
	return v is float or v is int


## Problems with one crew entry's optional post and starting skills.
static func validate_crew(
	where: String, c: Dictionary, rooms: Dictionary, errors: Array[String]
) -> void:
	var post := str(c.get("post", ""))
	if post != "" and not rooms.has(post):
		errors.append("%s: crew post in unknown room %s" % [where, post])
	var start: Dictionary = c.get("skills", {})
	for k: String in start:
		if not ids().has(k):
			errors.append("%s: crew has unknown skill %s" % [where, k])
		elif not ContentDB.is_int_in(start[k], 0, MAX_RANK):
			errors.append("%s: crew skill %s must be 0..%d" % [where, k, MAX_RANK])
