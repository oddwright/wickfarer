class_name Standing
extends RefCounted
## How each faction (Tidewardens, Ashmarket, the Hollow Choir) feels about the
## ship this run: a whole number per faction, read through tiers in
## data/factions.json. A tier sets the faction's store prices and how often its
## ships turn up in a Reach's fights; events can ask for a tier or open only at one.

var rep: Dictionary = {}  ## faction id -> int


static func data() -> Dictionary:
	return ContentDB.factions


static func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign((data().get("factions", {}) as Dictionary).keys())
	return out


static func has_faction(f: String) -> bool:
	return (data().get("factions", {}) as Dictionary).has(f)


static func spec(f: String) -> Dictionary:
	return data().get("factions", {}).get(f, {})


static func floor_rep() -> int:
	return int(data().get("range", [-5, 5])[0])


static func ceil_rep() -> int:
	return int(data().get("range", [-5, 5])[1])


## A new run's standing: each faction's "start".
static func fresh() -> Standing:
	var s := Standing.new()
	for f in ids():
		s.rep[f] = int(spec(f).get("start", 0))
	return s


func of(f: String) -> int:
	return int(rep.get(f, 0))


## Moves a faction's standing, kept inside the range. Returns how far it moved.
func change(f: String, n: int) -> int:
	if not has_faction(f):
		return 0
	var before := of(f)
	rep[f] = clampi(before + n, floor_rep(), ceil_rep())
	return of(f) - before


## The tier a standing value falls in: the last one whose at_least it reaches.
static func tier_for(value: int) -> Dictionary:
	var out: Dictionary = {}
	for t: Dictionary in data().get("tiers", []):
		if value >= int(t.at_least):
			out = t
	return out


## A faction's tier, or the neutral tier (standing 0) for "" or a ship with no faction.
func tier(f: String) -> Dictionary:
	return tier_for(of(f) if has_faction(f) else 0)


## Scrap added to (or taken off) each price at this faction's stores.
func price_delta(f: String) -> int:
	return int(tier(f).get("price", 0)) if has_faction(f) else 0


## How heavily this faction's ships weigh in a Reach's fight pool.
func ambush(f: String) -> int:
	return int(tier(f).get("ambush", 1))


## Winning a fight against a faction: it likes the ship less, and its rival more.
## Returns the translation keys that tell the player what moved.
func fight_won(f: String) -> Array[String]:
	var news: Array[String] = []
	if not has_faction(f):
		return news
	news.append_array(news_for(f, change(f, int(data().get("fight_won", 0)))))
	var rival := str(spec(f).get("rival", ""))
	if rival != "":
		news.append_array(news_for(rival, change(rival, int(data().get("rival_won", 0)))))
	return news


## The line that says a faction's standing went up or down; none if it didn't move.
static func news_for(f: String, moved: int) -> Array[String]:
	var out: Array[String] = []
	if moved > 0:
		out.append(str(spec(f).get("up", "")))
	elif moved < 0:
		out.append(str(spec(f).get("down", "")))
	return out


func to_dict() -> Dictionary:
	return rep.duplicate()


## A save from before factions, or one missing a faction added since, starts
## that faction where a new run would.
static func from_dict(d: Dictionary) -> Standing:
	var s := fresh()
	for f: String in d:
		if has_faction(f):
			s.rep[f] = clampi(int(d[f]), floor_rep(), ceil_rep())
	return s


## Checks data/factions.json; see ContentDB.validate().
static func validate(errors: Array[String]) -> void:
	var d := data()
	var span: Variant = d.get("range")
	if not span is Array or span.size() != 2 or int(span[0]) >= 0 or int(span[1]) <= 0:
		errors.append("factions: range is [lowest < 0, highest > 0]")
		return
	var tiers: Array = d.get("tiers", [])
	var last := -1000000
	for t: Dictionary in tiers:
		ContentDB.check_string(str(t.get("name", "")), "faction tier", errors)
		if int(t.get("at_least", last)) <= last:
			errors.append("factions: tiers go from the lowest at_least up, no repeats")
		last = int(t.get("at_least", last))
		if int(t.get("ambush", 0)) < 1:
			errors.append("factions: a tier's ambush weight is at least 1")
		if float(t.get("price", 0)) != float(int(t.get("price", 0))):
			errors.append("factions: a tier's price is a whole number of scrap")
	if tiers.is_empty() or int(tiers[0].get("at_least", 1)) != floor_rep():
		errors.append("factions: the first tier starts at the bottom of the range")
	for k in ["fight_won", "rival_won"]:
		if not d.has(k):
			errors.append("factions: missing %s" % k)
	for f in ids():
		var s := spec(f)
		var where := "faction %s" % f
		for k in ["name", "up", "down"]:
			ContentDB.check_string(str(s.get(k, "")), "%s %s" % [where, k], errors)
		var rival := str(s.get("rival", ""))
		if rival != "" and (rival == f or not has_faction(rival)):
			errors.append('%s: rival must be another faction, or ""' % where)
		var start := int(s.get("start", 0))
		if start < floor_rep() or start > ceil_rep():
			errors.append("%s: start is outside the range" % where)


## Is this a {faction: whole number} map with every number in the range?
static func valid_map(v: Variant, lo: int, hi: int) -> bool:
	if not v is Dictionary or (v as Dictionary).is_empty():
		return false
	for f: Variant in v:
		var n: Variant = v[f]
		if not has_faction(str(f)) or not (n is float or n is int):
			return false
		if float(n) != float(int(n)) or int(n) < lo or int(n) > hi:
			return false
	return true
