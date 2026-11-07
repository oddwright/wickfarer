class_name GearCheck
extends RefCounted
## Checks the gear content: modules, the gun fields stores and Chill need, hull
## slots, and the event effects, store stock and fight drops that hand gear out.
## It lives beside ContentDB.validate() (which calls it) so gear rules stay in one place.

const FAMILIES: Array[String] = ["kinetic", "torch", "chill"]
const MAX_SLOTS := 6
const MAX_STOCK := 5  ## a store's wares plus Back fit one page on every screen


static func validate(errors: Array[String]) -> void:
	for id: String in ContentDB.modules:
		_module(id, ContentDB.modules[id], errors)
	for wid: String in ContentDB.weapons:
		_weapon(wid, ContentDB.weapons[wid], errors)
	for sid: String in ContentDB.ships:
		_ship(sid, ContentDB.ships[sid], errors)
	for eid: String in ContentDB.events:
		for c: Dictionary in ContentDB.events[eid].get("choices", []):
			for o: Dictionary in c.get("outcomes", []):
				_event_gear("event %s" % eid, o.get("effects", {}), errors)
	for rid: String in ContentDB.reaches:
		_reach(rid, ContentDB.reaches[rid], errors)


## A module needs a name, a price, at least one gain and at least one cost.
static func _module(id: String, m: Dictionary, errors: Array[String]) -> void:
	var where := "module %s" % id
	ContentDB.check_string(str(m.get("name", "")), where, errors)
	_shop_fields(where, m, errors)
	for part: String in ["gain", "cost"]:
		var fx: Variant = m.get(part, {})
		var known := Gear.GAINS if part == "gain" else Gear.COSTS
		if not fx is Dictionary or (fx as Dictionary).is_empty():
			errors.append("%s: needs at least one %s" % [where, part])
			continue
		for k: String in fx:
			if not k in known:
				errors.append("%s: unknown %s %s" % [where, part, k])
				continue
			if not _positive(fx[k], k in Gear.WHOLE):
				errors.append("%s: %s %s must be a number above 0" % [where, part, k])
			ContentDB.check_string("GEAR_%s_%s" % [part.to_upper(), k.to_upper()], where, errors)
	var resist := float((m.get("gain", {}) as Dictionary).get("chill_resist", 0.0))
	if resist > Gear.MAX_RESIST:
		errors.append("%s: chill_resist is at most %s" % [where, Gear.MAX_RESIST])


## Price, weight and unlock, shared by modules and guns.
static func _shop_fields(where: String, e: Dictionary, errors: Array[String]) -> void:
	if e.has("price") and not ContentDB.is_int_in(e.price, 0, 999):
		errors.append("%s: price must be a whole number from 0 to 999" % where)
	if e.has("weight") and not ContentDB.is_int_in(e.weight, 0, 100):
		errors.append("%s: weight must be a whole number from 0 to 100" % where)
	var need: Variant = e.get("unlock", "")
	if not need is String or (need != "" and not ContentDB.unlocks.has(need)):
		errors.append("%s: unknown unlock %s" % [where, need])


static func _weapon(wid: String, w: Dictionary, errors: Array[String]) -> void:
	var where := "weapon %s" % wid
	_shop_fields(where, w, errors)
	if not str(w.get("family", "")) in FAMILIES:
		errors.append("%s: family must be one of %s" % [where, FAMILIES])
	if w.has("chill") and not _positive(w.chill, false):
		errors.append("%s: chill must be a number above 0" % where)
	if w.get("family") == "chill" and not w.has("chill"):
		errors.append("%s: a Chill gun needs a chill amount" % where)
	if w.has("pierces_ward") and not w.pierces_ward is bool:
		errors.append("%s: pierces_ward must be true or false" % where)
	if w.get("pierces_ward", false) and w.get("strips_ward", false):
		errors.append("%s: a gun either strips wards or passes them, not both" % where)


static func _ship(sid: String, s: Dictionary, errors: Array[String]) -> void:
	var where := "ship %s" % sid
	for f: String in ["module_slots", "weapon_slots"]:
		var top := Gear.MAX_MODULE_SLOTS if f == "module_slots" else MAX_SLOTS
		if s.has(f) and not ContentDB.is_int_in(s[f], 0, top):
			errors.append("%s: %s must be a whole number from 0 to %d" % [where, f, top])
	var mods: Array = s.get("modules", [])
	for m: Variant in mods:
		if not ContentDB.modules.has(str(m)):
			errors.append("%s: unknown module %s" % [where, m])
	if mods.size() > int(s.get("module_slots", Gear.DEFAULT_MODULE_SLOTS)):
		errors.append("%s: more modules than slots" % where)
	# The fight bar has room for two guns on every screen.
	if s.get("playable", false) and int(s.get("weapon_slots", 0)) > Gear.MIN_WEAPON_SLOTS:
		errors.append("%s: a playable hull has at most %d mounts" % [where, Gear.MIN_WEAPON_SLOTS])
	if s.get("playable", false) and (s.get("weapons", []) as Array).size() > Gear.MIN_WEAPON_SLOTS:
		errors.append("%s: a playable hull starts with at most 2 guns" % where)


static func _event_gear(where: String, fx: Dictionary, errors: Array[String]) -> void:
	for kind: String in ["module", "weapon"]:
		if not fx.has(kind):
			continue
		var id := str(fx[kind])
		var table: Dictionary = ContentDB.modules if kind == "module" else ContentDB.weapons
		if id != "any" and not table.has(id):
			errors.append('%s: %s must be a %s id or "any"' % [where, kind, kind])


static func _reach(rid: String, r: Dictionary, errors: Array[String]) -> void:
	var where := "reach %s" % rid
	var stock: Variant = (r.get("store", {}) as Dictionary).get("stock", 0)
	if not ContentDB.is_int_in(stock, 0, MAX_STOCK):
		errors.append("%s: store.stock must be a whole number from 0 to %d" % [where, MAX_STOCK])
	var chance: Variant = (r.get("fight_reward", {}) as Dictionary).get("gear_chance", 0.0)
	if not (chance is float or chance is int) or float(chance) < 0.0 or float(chance) > 1.0:
		errors.append("%s: fight_reward.gear_chance must be from 0 to 1" % where)


static func _positive(v: Variant, whole: bool) -> bool:
	if not (v is float or v is int) or float(v) <= 0.0:
		return false
	return not whole or float(v) == floorf(float(v))
