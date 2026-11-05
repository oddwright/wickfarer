class_name ContentDB
extends RefCounted
## Loads every JSON content file once and checks it.
## Content is data, never code: adding a ship or weapon means editing data/*.json.

const FILES := {
	"ships": "res://data/ships.json",
	"weapons": "res://data/weapons.json",
	"species": "res://data/species.json",
	"systems": "res://data/systems.json",
	"strings": "res://data/strings_en.json",
	"events": "res://data/events.json",
	"reaches": "res://data/reaches.json",
}

const EVENT_EFFECTS := ["scrap", "light", "hull", "crew_hp", "hush", "fight", "fight_bonus_scrap"]
const EVENT_REQUIRES := ["scrap", "light", "species"]

static var ships: Dictionary = {}
static var weapons: Dictionary = {}
static var species: Dictionary = {}
static var systems: Dictionary = {}
static var strings: Dictionary = {}
static var events: Dictionary = {}
static var reaches: Dictionary = {}
static var loaded := false


static func load_all() -> void:
	if loaded:
		return
	ships = _read(FILES.ships)
	weapons = _read(FILES.weapons)
	species = _read(FILES.species)
	systems = _read(FILES.systems)
	strings = _read(FILES.strings)
	events = _read(FILES.events)
	reaches = _read(FILES.reaches)
	_install_translation()
	loaded = true


static func _read(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Content file missing or empty: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Content file is not a JSON object: %s" % path)
		return {}
	return parsed


static func _install_translation() -> void:
	var t := Translation.new()
	t.locale = "en"
	for key: String in strings:
		t.add_message(key, strings[key])
	TranslationServer.add_translation(t)


## Returns a list of human-readable problems. Empty means the content is good.
static func validate() -> Array[String]:
	load_all()
	var errors: Array[String] = []
	for wid: String in weapons:
		var w: Dictionary = weapons[wid]
		for field in [
			"name",
			"family",
			"power",
			"charge",
			"shots",
			"hull_damage",
			"system_damage",
			"crew_damage",
			"fire_chance",
			"strips_ward"
		]:
			if not w.has(field):
				errors.append("weapon %s: missing %s" % [wid, field])
		if w.get("charge", 0.0) <= 0.0:
			errors.append("weapon %s: charge must be > 0" % wid)
		_check_string(w.get("name", ""), "weapon %s" % wid, errors)
	for sid: String in species:
		var s: Dictionary = species[sid]
		for field in ["name", "hp", "speed", "repair", "firefight", "cold_proof"]:
			if not s.has(field):
				errors.append("species %s: missing %s" % [sid, field])
		_check_string(s.get("name", ""), "species %s" % sid, errors)
	for sys_id: String in systems:
		_check_string(systems[sys_id].get("name", ""), "system %s" % sys_id, errors)
	for ship_id: String in ships:
		_validate_ship(ship_id, ships[ship_id], errors)
	for eid: String in events:
		_validate_event(eid, events[eid], errors)
	for rid: String in reaches:
		var r: Dictionary = reaches[rid]
		_check_string(r.get("name", ""), "reach %s" % rid, errors)
		for e: String in r.get("enemies", []):
			if not ships.has(e):
				errors.append("reach %s: unknown enemy ship %s" % [rid, e])
		for k: String in r.get("kinds", {}):
			if not k in ["fight", "event", "store", "empty"]:
				errors.append("reach %s: unknown beacon kind %s" % [rid, k])
	return errors


static func _check_string(key: String, where: String, errors: Array[String]) -> void:
	if key == "" or not strings.has(key):
		errors.append("%s: untranslated string '%s'" % [where, key])


static func _validate_ship(ship_id: String, s: Dictionary, errors: Array[String]) -> void:
	var where := "ship %s" % ship_id
	_check_string(s.get("name", ""), where, errors)
	if not ResourceLoader.exists(s.get("sprite", "")):
		errors.append("%s: sprite not found %s" % [where, s.get("sprite", "")])
	var room_ids := {}
	var has_ember := false
	for r: Dictionary in s.get("rooms", []):
		if room_ids.has(r.id):
			errors.append("%s: duplicate room %s" % [where, r.id])
		room_ids[r.id] = r
		var sys: String = r.get("system", "")
		if sys != "" and not systems.has(sys):
			errors.append("%s: room %s has unknown system %s" % [where, r.id, sys])
		if sys == "ember":
			has_ember = true
		if sys != "" and int(r.get("level", 0)) < 1:
			errors.append("%s: room %s needs a level" % [where, r.id])
		var rect: Array = r.get("rect", [])
		if rect.size() != 4 or rect[2] <= rect[0] or rect[3] <= rect[1]:
			errors.append("%s: room %s has a bad rect" % [where, r.id])
	if not has_ember:
		errors.append("%s: every ship needs an ember room" % where)
	for l: Dictionary in s.get("ladders", []):
		if not room_ids.has(l.upper) or not room_ids.has(l.lower):
			errors.append("%s: ladder joins unknown rooms" % where)
		elif int(room_ids[l.upper].deck) != int(room_ids[l.lower].deck) + 1:
			errors.append("%s: ladder %s-%s must join adjacent decks" % [where, l.upper, l.lower])
	for wid: String in s.get("weapons", []):
		if not weapons.has(wid):
			errors.append("%s: unknown weapon %s" % [where, wid])
	for c: Dictionary in s.get("crew", []):
		if not species.has(c.species):
			errors.append("%s: unknown species %s" % [where, c.species])
		if not room_ids.has(c.room):
			errors.append("%s: crew starts in unknown room %s" % [where, c.room])
		_check_string(c.get("name", ""), where + " crew", errors)
	var total := 0
	for sys: String in s.get("start_power", {}):
		total += int(s.start_power[sys])
	if total > int(s.get("reactor", 0)):
		errors.append("%s: start power %d is over the reactor %d" % [where, total, s.reactor])
	# Every room must be reachable, or crew can get stuck.
	if room_ids.size() > 0:
		var ship := Ship.from_content(ship_id, 0)
		var first: String = room_ids.keys()[0]
		for rid: String in room_ids:
			if rid != first and ship.find_path(first, rid).is_empty():
				errors.append("%s: room %s can't be reached" % [where, rid])


static func _validate_event(eid: String, e: Dictionary, errors: Array[String]) -> void:
	var where := "event %s" % eid
	_check_string(e.get("text", ""), where, errors)
	var choices: Array = e.get("choices", [])
	if choices.is_empty():
		errors.append("%s: no choices" % where)
	var has_free_choice := false
	for c: Dictionary in choices:
		_check_string(c.get("text", ""), where, errors)
		var req: Dictionary = c.get("requires", {})
		if req.is_empty():
			has_free_choice = true
		for k: String in req:
			if not k in EVENT_REQUIRES:
				errors.append("%s: unknown requirement %s" % [where, k])
			if k == "species" and not species.has(req[k]):
				errors.append("%s: unknown species %s" % [where, req[k]])
		var outcomes: Array = c.get("outcomes", [])
		if outcomes.is_empty():
			errors.append("%s: a choice has no outcomes" % where)
		for o: Dictionary in outcomes:
			_check_string(o.get("text", ""), where, errors)
			if int(o.get("weight", 0)) < 1:
				errors.append("%s: outcome weight must be at least 1" % where)
			for k: String in o.get("effects", {}):
				if not k in EVENT_EFFECTS:
					errors.append("%s: unknown effect %s" % [where, k])
			var fight: String = o.get("effects", {}).get("fight", "")
			if fight != "" and not ships.has(fight):
				errors.append("%s: fights unknown ship %s" % [where, fight])
	# A player must never be stuck in an event they can't leave.
	if not has_free_choice:
		errors.append("%s: needs at least one choice with no requirement" % where)
