class_name Gear
extends RefCounted
## What a ship carries besides its rooms: modules in hull slots and guns on
## mounts. Every module buys its gain with a cost (heat, power, helm, Light
## upkeep or the Hush), so a full set of slots is a plan, not a pile of
## bonuses. The ship reads the summed effects through Ship.mod(); this file
## holds the rules for fitting and mounting, which the player's stores and
## any enemy hull that lists modules both go through.

## What a module's "gain" may hold. Fractions are shares of a base rate.
const GAINS: Array[String] = [
	"reactor",  ## more reactor power
	"max_hull",
	"evasion",  ## dodge points, while the helm works
	"ward_regen",  ## fraction faster ward layers
	"weapon_charge",  ## fraction faster gun charge
	"mend",  ## fraction faster healing in mend
	"crew_speed",  ## fraction faster walking
	"warmth",  ## warmth a second added to every room
	"chill_resist",  ## fraction of a Chill hit's cold shrugged off, up to MAX_RESIST
	"salvage",  ## fraction more scrap from fights
	"fight_light",  ## Light after each won fight
]
## What a module's "cost" may hold. Every module needs at least one.
const COSTS: Array[String] = [
	"power",  ## reactor power the module draws
	"heat",  ## warmth a second drawn from every room
	"helm",  ## dodge points lost
	"light_upkeep",  ## Light burned each jump
	"hush",  ## how much nearer the Hush comes each jump
]
## Effects that must be whole numbers.
const WHOLE: Array[String] = ["reactor", "max_hull", "fight_light", "power", "light_upkeep"]
const MAX_RESIST := 0.8  ## no stack of modules makes a ship immune to cold
const DEFAULT_MODULE_SLOTS := 3
const MIN_WEAPON_SLOTS := 2  ## the fight bar has room for two guns on every screen


## The summed effects of a list of module ids.
static func sum(modules: Array[String]) -> Dictionary:
	var out := {}
	for id in modules:
		var m: Dictionary = ContentDB.modules.get(id, {})
		for part: String in ["gain", "cost"]:
			var fx: Dictionary = m.get(part, {})
			for k: String in fx:
				out[k] = float(out.get(k, 0.0)) + float(fx[k])
	if out.has("chill_resist"):
		out.chill_resist = minf(float(out.chill_resist), MAX_RESIST)
	return out


static func free_slots(s: Ship) -> int:
	return s.module_slots - s.modules.size()


static func free_mounts(s: Ship) -> int:
	return s.weapon_slots - s.weapon_ids.size()


## Fits a module to a free slot. Extra hull plating raises the cap but
## brings no fresh plate: refitting it again must never repair the ship.
static func fit(s: Ship, id: String) -> bool:
	if not ContentDB.modules.has(id) or free_slots(s) <= 0:
		return false
	s.modules.append(id)
	s.max_hull += _whole(id, "max_hull")
	s.mods = sum(s.modules)
	s.enforce_power()
	return true


## Takes the module out of slot i and returns its id, or "" if there is none.
static func unfit(s: Ship, i: int) -> String:
	if i < 0 or i >= s.modules.size():
		return ""
	var id: String = s.modules[i]
	s.modules.remove_at(i)
	s.max_hull = maxi(1, s.max_hull - _whole(id, "max_hull"))
	s.hull = clampi(s.hull, 1, s.max_hull)
	s.mods = sum(s.modules)
	s.enforce_power()
	return id


## Puts a gun on a free mount, last in the power order.
static func mount(s: Ship, wid: String) -> bool:
	if not ContentDB.weapons.has(wid) or free_mounts(s) <= 0:
		return false
	s.weapon_ids.append(wid)
	s.weapon_charge.append(0.0)
	s.weapon_target.append("")
	return true


## Takes gun i off its mount. A ship always keeps one gun.
static func unmount(s: Ship, i: int) -> String:
	if i < 0 or i >= s.weapon_ids.size() or s.weapon_ids.size() <= 1:
		return ""
	var wid: String = s.weapon_ids[i]
	s.weapon_ids.remove_at(i)
	s.weapon_charge.remove_at(i)
	s.weapon_target.remove_at(i)
	return wid


## The content entry for a gear item: {kind: "module"|"weapon", id}.
static func entry(item: Dictionary) -> Dictionary:
	var table: Dictionary = ContentDB.modules if item.get("kind") == "module" else ContentDB.weapons
	return table.get(str(item.get("id", "")), {})


static func is_item(item: Variant) -> bool:
	return (
		item is Dictionary
		and str(item.get("kind", "")) in ["module", "weapon"]
		and not entry(item).is_empty()
	)


## Every item a run may find or buy: priced gear whose unlock (if any) is open.
static func pool(unlocked: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: String in ["weapon", "module"]:
		var table: Dictionary = ContentDB.weapons if kind == "weapon" else ContentDB.modules
		for id: String in table:
			var e: Dictionary = table[id]
			var need := str(e.get("unlock", ""))
			if int(e.get("price", 0)) > 0 and (need == "" or unlocked.has(need)):
				out.append({"kind": kind, "id": id})
	return out


## A weighted pick from the pool, leaving out what's in skip; {} if nothing is left.
static func pick(
	rng: RandomNumberGenerator, unlocked: Array[String], kind := "", skip: Array = []
) -> Dictionary:
	var items: Array[Dictionary] = []
	var weights: Array[int] = []
	for item in pool(unlocked):
		if (kind == "" or item.kind == kind) and not skip.has(item):
			items.append(item)
			weights.append(int(entry(item).get("weight", 10)))
	var i := RngStreams.weighted_pick(weights, rng)
	return {} if i < 0 else items[i]


static func _whole(id: String, effect: String) -> int:
	return int((ContentDB.modules[id].get("gain", {}) as Dictionary).get(effect, 0))
