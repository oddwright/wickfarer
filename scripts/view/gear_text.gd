class_name GearText
extends RefCounted
## Words for gear: a module's gains and costs, a gun's numbers, and the run
## messages that name gear. Built from the content, so a new module or gun
## needs only its name string.

## Effects given as a fraction of a base rate, shown as a percentage.
const PERCENT: Array[String] = [
	"ward_regen", "weapon_charge", "mend", "crew_speed", "chill_resist", "salvage"
]


## "Gyre Vanes: +8 dodge, uses 1 power" for a module, or a gun's numbers.
static func line(item: Dictionary) -> String:
	var e := Gear.entry(item)
	return "%s: %s" % [tr_key(str(e.get("name", ""))), effects(item)]


static func effects(item: Dictionary) -> String:
	var e := Gear.entry(item)
	var parts: Array[String] = []
	if item.get("kind") == "module":
		for part: String in ["gain", "cost"]:
			var fx: Dictionary = e.get(part, {})
			for k: String in fx:
				var key := "GEAR_%s_%s" % [part.to_upper(), k.to_upper()]
				parts.append(tr_key(key) % number(k, float(fx[k])))
		return ", ".join(parts)
	parts.append(
		(
			tr_key("GEAR_WPN")
			% [int(e.get("power", 0)), int(e.get("shots", 1)), int(e.get("hull_damage", 0))]
		)
	)
	if e.has("chill"):
		parts.append(tr_key("GEAR_WPN_CHILL") % int(e.chill))
	if float(e.get("fire_chance", 0.0)) > 0.0:
		parts.append(tr_key("GEAR_WPN_FIRE"))
	return ", ".join(parts)


## A run message: a plain translation key, or "<key>|<name key>" for one
## that names a piece of gear.
static func message(m: String) -> String:
	if not m.contains("|"):
		return tr_key(m)
	return tr_key(m.get_slice("|", 0)) % tr_key(m.get_slice("|", 1))


## Fractions read as percentages; everything else as a plain number.
static func number(effect: String, v: float) -> String:
	if effect in Gear.WHOLE:
		return str(int(v))
	if effect in PERCENT:
		return str(int(round(v * 100.0)))
	return String.num(v, 2).trim_suffix(".0")


static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)
