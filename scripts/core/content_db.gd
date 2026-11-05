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
	"feedback": "res://data/feedback.json",
}

const EVENT_EFFECTS := ["scrap", "light", "hull", "crew_hp", "hush", "fight", "fight_bonus_scrap"]
const EVENT_REQUIRES := ["scrap", "light", "species"]
const SOUND_BUSES: Array[String] = ["Music", "SFX", "UI"]  ## every bus a sound can play on
const MAX_HITSTOP := 0.15  ## seconds; longer freezes read as lag
const SYNTH_WAVES := ["sine", "tri", "square", "saw", "noise"]

static var ships: Dictionary = {}
static var weapons: Dictionary = {}
static var species: Dictionary = {}
static var systems: Dictionary = {}
static var strings: Dictionary = {}
static var events: Dictionary = {}
static var reaches: Dictionary = {}
static var feedback: Dictionary = {}  ## sounds, haptics, cues and music layers
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
	feedback = _read(FILES.feedback)
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
		_validate_reach(rid, reaches[rid], errors)
	_validate_feedback(feedback, errors)
	return errors


## Every field a Run or StarChart reads, so a bad reach fails here and not
## half way through a run.
static func _validate_reach(rid: String, r: Dictionary, errors: Array[String]) -> void:
	var where := "reach %s" % rid
	_check_string(r.get("name", ""), where, errors)
	var enemies: Array = r.get("enemies", [])
	if enemies.is_empty():
		errors.append("%s: needs at least one enemy" % where)
	for e: String in enemies:
		if not ships.has(e):
			errors.append("%s: unknown enemy ship %s" % [where, e])
	var kinds: Dictionary = r.get("kinds", {})
	var kind_total := 0
	for k: String in kinds:
		kind_total += int(kinds[k])
		if not k in ["fight", "event", "store", "empty"]:
			errors.append("%s: unknown beacon kind %s" % [where, k])
		if int(kinds[k]) < 0:
			errors.append("%s: beacon kind %s has a negative weight" % [where, k])
	if kind_total <= 0:
		errors.append("%s: beacon kind weights must add up to more than 0" % where)
	if int(r.get("columns", 0)) < 3:
		errors.append("%s: needs at least 3 columns (start, a beacon, the Gate)" % where)
	var rows: Array = r.get("rows", [])
	if rows.size() != 2 or int(rows[0]) < 1 or int(rows[1]) < int(rows[0]):
		errors.append("%s: rows must be [min, max] with 1 <= min <= max" % where)
	for f in ["jump_light", "dark_jump_hull", "hush_hull"]:
		if not r.has(f) or int(r[f]) < 0:
			errors.append("%s: %s must be a number of 0 or more" % [where, f])
	for f in ["hush_start", "hush_per_jump", "hush_per_light"]:
		if not r.has(f):
			errors.append("%s: missing %s" % [where, f])
	var start: Dictionary = r.get("start", {})
	if not (start.has("scrap") and start.has("light")):
		errors.append("%s: start needs scrap and light" % where)
	var reward: Dictionary = r.get("fight_reward", {})
	for f in ["scrap", "light"]:
		var span: Array = reward.get(f, [])
		if span.size() != 2 or int(span[0]) > int(span[1]):
			errors.append("%s: fight_reward.%s must be [min, max]" % [where, f])
	var store: Dictionary = r.get("store", {})
	for item in Run.STORE_ITEMS:
		_check_string("UI_STORE_" + item.to_upper(), "store item %s" % item, errors)
	for f in ["repair_scrap", "light_scrap"]:
		if int(store.get(f, 0)) <= 0:
			errors.append("%s: store.%s must be a price above 0" % [where, f])


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
			# A choice that spends scrap or Light must require it, or a player
			# with none gets the reward for free (spending clamps at 0).
			for res in ["scrap", "light"]:
				var cost := -int(o.get("effects", {}).get(res, 0))
				if cost > int(req.get(res, 0)):
					errors.append(
						"%s: a choice can cost %d %s but requires less" % [where, cost, res]
					)
	# A player must never be stuck in an event they can't leave.
	if not has_free_choice:
		errors.append("%s: needs at least one choice with no requirement" % where)


## Sounds, haptic patterns, cues and music layers, so a typo in a cue fails
## here and not as a silent hit on someone's phone.
static func _validate_feedback(f: Dictionary, errors: Array[String]) -> void:
	var sounds: Dictionary = f.get("sounds", {})
	var haptics: Dictionary = f.get("haptics", {})
	for id: String in sounds:
		_validate_sound("sound %s" % id, sounds[id], errors)
		if not str(sounds[id].get("bus", "SFX")) in SOUND_BUSES:
			errors.append("sound %s: unknown bus %s" % [id, sounds[id].bus])
	for id: String in haptics:
		var steps: Variant = haptics[id]
		if not steps is Array or (steps as Array).is_empty():
			errors.append("haptic %s: needs [ms, amplitude] steps" % id)
			continue
		for step: Variant in steps:
			var ok: bool = step is Array and step.size() == 2
			if not ok or float(step[0]) <= 0.0 or float(step[1]) < 0.0 or float(step[1]) > 1.0:
				errors.append("haptic %s: each step is [ms > 0, amplitude 0..1]" % id)
	for id: String in f.get("cues", {}):
		var c: Dictionary = f.cues[id]
		var where := "cue %s" % id
		if c.has("sound") and not sounds.has(c.sound):
			errors.append("%s: unknown sound %s" % [where, c.sound])
		if c.has("haptic") and not haptics.has(c.haptic):
			errors.append("%s: unknown haptic %s" % [where, c.haptic])
		for k in ["shake", "kick", "hitstop", "cooldown"]:
			if float(c.get(k, 0.0)) < 0.0:
				errors.append("%s: %s can't be negative" % [where, k])
		if float(c.get("shake", 0.0)) > 1.0:
			errors.append("%s: shake is 0..1" % where)
		if float(c.get("hitstop", 0.0)) > MAX_HITSTOP:
			errors.append("%s: hitstop over %.2f s reads as lag" % [where, MAX_HITSTOP])
		if not _int_in(c.get("priority", 0), 0, 9):
			errors.append("%s: priority is a whole number 0..9" % where)
		if not c.get("duck", false) is bool:
			errors.append("%s: duck is true or false" % where)
	var music: Dictionary = f.get("music", {})
	if float(music.get("fade", 1.5)) <= 0.0:
		errors.append("music: fade must be > 0")
	var layers: Dictionary = music.get("layers", {})
	if layers.size() > 32:
		errors.append("music: at most 32 layers")
	for id: String in layers:
		_validate_sound("music layer %s" % id, layers[id], errors)
	for state: String in music.get("states", {}):
		for layer: Variant in music.states[state]:
			if not layers.has(layer):
				errors.append("music state %s: unknown layer %s" % [state, layer])
	for layer: Variant in music.get("hush_layers", []):
		if not layers.has(layer):
			errors.append("music: unknown hush layer %s" % layer)


static func _validate_sound(where: String, s: Dictionary, errors: Array[String]) -> void:
	var file := str(s.get("file", ""))
	if file != "" and not ResourceLoader.exists(file):
		errors.append("%s: file not found %s" % [where, file])
	if file == "" and not s.has("synth"):
		errors.append("%s: needs a file or a synth recipe" % where)
	if not _num_in(s.get("volume_db", 0), -60.0, 12.0):
		errors.append("%s: volume_db is -60..12" % where)
	if not _num_in(s.get("pitch_jitter", 0), 0.0, 0.5):
		errors.append("%s: pitch_jitter is 0..0.5" % where)
	if s.has("synth"):
		_validate_synth(where, s.synth, errors)


static func _validate_synth(where: String, r: Dictionary, errors: Array[String]) -> void:
	if not str(r.get("wave", "sine")) in SYNTH_WAVES:
		errors.append("%s: unknown wave %s" % [where, r.get("wave")])
	if not _num_in(r.get("ms", 100), 1.0, 20000.0):
		errors.append("%s: ms is 1..20000" % where)
	for k in ["freq", "freq_end"]:
		if not _num_in(r.get(k, 440), 1.0, 11000.0):
			errors.append("%s: %s is 1..11000 Hz" % [where, k])
	if not _num_in(r.get("decay", 0), 0.0, 100.0):
		errors.append("%s: decay is 0..100" % where)
	if not _num_in(r.get("noise", 0), 0.0, 1.0):
		errors.append("%s: noise is 0..1" % where)
	if not _int_in(r.get("beats", 0), 0, 32):
		errors.append("%s: beats is a whole number 0..32" % where)
	var notes: Variant = r.get("notes", [220])
	if not notes is Array or (notes as Array).is_empty():
		errors.append("%s: notes must be a list of frequencies" % where)
	else:
		for n: Variant in notes:
			if not _num_in(n, 1.0, 11000.0):
				errors.append("%s: note %s is not 1..11000 Hz" % [where, n])


static func _num_in(v: Variant, lo: float, hi: float) -> bool:
	return (v is float or v is int) and float(v) >= lo and float(v) <= hi


static func _int_in(v: Variant, lo: int, hi: int) -> bool:
	return _num_in(v, lo, hi) and float(v) == floorf(float(v))
