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
	"tutorial": "res://data/tutorial.json",
	"unlocks": "res://data/unlocks.json",
	"depths": "res://data/depths.json",
}
## What a Hush Depth's rules may change, and the sign each must have (+1: only
## harder when positive, -1: only harder when negative).
const DEPTH_EFFECTS := {
	"start_scrap": -1,
	"start_light": -1,
	"hush_per_jump": 1,
	"enemy_hull": 1,
	"store_markup": 1,
	"fight_scrap": -1,
	"dark_jump_hull": 1,
}

const EVENT_EFFECTS := [
	"scrap", "light", "hull", "crew_hp", "hush", "fight", "fight_bonus_scrap", "enemy_hull", "store"
]
const BEACON_KINDS := ["fight", "event", "store", "empty"]  ## the Gate has no story
const MAX_CHOICES := 3  ## what the Square layout's right page has room for
const EVENT_REQUIRES := ["scrap", "light", "species"]
const SOUND_BUSES: Array[String] = ["Music", "SFX", "UI"]  ## every bus a sound can play on
const MUSIC_ENTRIES: Array[String] = ["now", "beat", "bar"]  ## when a music clip may cut in
const PHONE_LOW_HZ := 150  ## phone speakers barely play anything lower
const MAX_HITSTOP := 0.15  ## seconds; longer freezes read as lag
const SYNTH_WAVES := ["sine", "tri", "square", "saw", "noise"]
const PLAYABLE_FRAME := Vector2i(240, 80)  ## the largest frame the ship select preview shows

static var ships: Dictionary = {}
static var weapons: Dictionary = {}
static var species: Dictionary = {}
static var systems: Dictionary = {}
static var strings: Dictionary = {}
static var events: Dictionary = {}
static var reaches: Dictionary = {}
static var feedback: Dictionary = {}  ## sounds, haptics, cues and music layers
static var tutorial: Dictionary = {}  ## the training flight's lessons and the one-time tips
static var unlocks: Dictionary = {}  ## unlock id -> {name, hint, stat, at_least}
static var depths: Dictionary = {}  ## {"depths": [{name, text, effects}]}, depth 1 first
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
	tutorial = _read(FILES.tutorial)
	unlocks = _read(FILES.unlocks)
	depths = _read(FILES.depths)
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
		_validate_system(sys_id, systems[sys_id], errors)
	if not systems.has("ember") or not systems.ember.get("stoke_light", []) is Array:
		errors.append("system ember: needs a stoke_light price list")
	for sys_id in Run.REFIT_SYSTEMS:
		if not systems.has(sys_id):
			errors.append("refit offers unknown system %s" % sys_id)
	for ship_id: String in ships:
		_validate_ship(ship_id, ships[ship_id], errors)
	if not ShipRoster.is_unlocked(ShipRoster.default_ship(), []):
		errors.append("ships: at least one playable hull must be open from the start")
	for eid: String in events:
		_validate_event(eid, events[eid], errors)
	for rid: String in reaches:
		_validate_reach(rid, reaches[rid], errors)
	_validate_reach_chain(errors)
	_validate_unlocks(errors)
	_validate_depths(errors)
	_validate_feedback(feedback, errors)
	_validate_tutorial(tutorial, errors)
	return errors


static func _validate_system(sys_id: String, sys: Dictionary, errors: Array[String]) -> void:
	var where := "system %s" % sys_id
	_check_string(sys.get("name", ""), where, errors)
	for f in ["upgrade_scrap", "stoke_light"]:
		if not sys.has(f):
			continue
		if not sys[f] is Array:
			errors.append("%s: %s must be a list of prices" % [where, f])
			continue
		for p: Variant in sys[f]:
			if not (p is float or p is int) or int(p) <= 0 or float(p) != float(int(p)):
				errors.append("%s: %s prices must be whole numbers above 0" % [where, f])
	if sys.has("stoke_light") and sys_id != "ember":
		errors.append("%s: only the Ember can be stoked" % where)


static func _validate_unlocks(errors: Array[String]) -> void:
	for id: String in unlocks:
		var u: Dictionary = unlocks[id]
		var where := "unlock %s" % id
		_check_string(str(u.get("name", "")), where, errors)
		_check_string(str(u.get("hint", "")), where, errors)
		if not str(u.get("stat", "")) in Profile.STATS:
			errors.append("%s: unknown stat %s" % [where, u.get("stat", "")])
		if not _int_in(u.get("at_least"), 1, 1000000):
			errors.append("%s: at_least must be a whole number of 1 or more" % where)
	for ship_id: String in ships:
		var need := str(ships[ship_id].get("unlock", ""))
		if need != "" and not unlocks.has(need):
			errors.append("ship %s: unknown unlock %s" % [ship_id, need])


## Each depth adds one rule that only ever makes the run harder.
static func _validate_depths(errors: Array[String]) -> void:
	var list: Variant = depths.get("depths")
	if not list is Array:
		errors.append('depths.json needs a "depths" list')
		return
	for i in (list as Array).size():
		var dep: Variant = list[i]
		var where := "hush depth %d" % (i + 1)
		if not dep is Dictionary:
			errors.append("%s: must be an object" % where)
			continue
		_check_string(str(dep.get("name", "")), where, errors)
		_check_string(str(dep.get("text", "")), where, errors)
		var fx: Variant = dep.get("effects", {})
		if not fx is Dictionary or (fx as Dictionary).is_empty():
			errors.append("%s: needs at least one effect" % where)
			continue
		for k: String in fx:
			if not DEPTH_EFFECTS.has(k):
				errors.append("%s: unknown effect %s" % [where, k])
			elif not (fx[k] is float or fx[k] is int) or float(fx[k]) * DEPTH_EFFECTS[k] <= 0.0:
				errors.append("%s: %s must make the run harder" % [where, k])
			elif k != "hush_per_jump" and float(fx[k]) != floorf(float(fx[k])):
				errors.append("%s: %s must be a whole number" % [where, k])


## The Reaches form one chain from reach_1, each "next" naming a real Reach,
## with no loops, so every run ends at a last Gate.
static func _validate_reach_chain(errors: Array[String]) -> void:
	if not reaches.has("reach_1"):
		errors.append("there must be a reach_1, where runs start")
		return
	var seen := {}
	var rid := "reach_1"
	while rid != "":
		if seen.has(rid):
			errors.append("reach %s: the chain of next Reaches loops" % rid)
			return
		seen[rid] = true
		rid = str(reaches[rid].get("next", ""))
		if rid != "" and not reaches.has(rid):
			errors.append("reach chain: unknown next Reach %s" % rid)
			return
	for other: String in reaches:
		# The training flight is its own one-Reach run, outside the chain.
		if not seen.has(other) and not bool(reaches[other].get("training", false)):
			errors.append("reach %s: no Reach leads to it" % other)


## Every field a Run or StarChart reads, so a bad reach fails here and not
## half way through a run.
static func _validate_reach(rid: String, r: Dictionary, errors: Array[String]) -> void:
	var where := "reach %s" % rid
	_check_string(r.get("name", ""), where, errors)
	if r.has("training") and not r.training is bool:
		errors.append("%s: training must be true or false" % where)
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
		if not k in BEACON_KINDS:
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
	if int(r.get("gate_repair", 0)) < 0:
		errors.append("%s: gate_repair can't be negative" % where)
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
	var boost: Dictionary = r.get("enemy_boost", {})
	for f in ["hull", "reactor"]:
		if int(boost.get(f, 0)) < 0:
			errors.append("%s: enemy_boost.%s can't be negative" % [where, f])
	for sys: Variant in boost.get("systems", []):
		if not systems.has(str(sys)):
			errors.append("%s: enemy_boost raises unknown system %s" % [where, sys])
		elif Ship.max_level(str(sys)) <= 1:
			errors.append("%s: enemy_boost raises %s, which has no levels to buy" % [where, sys])
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
	_validate_playable(where, s, errors)
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


## A hull the player can pick needs words for the select screen, a valid
## unlock, and a frame the select screen's preview can hold.
static func _validate_playable(where: String, s: Dictionary, errors: Array[String]) -> void:
	var playable: Variant = s.get("playable", false)
	if not playable is bool:
		errors.append("%s: playable must be true or false" % where)
		return
	if not playable:
		return
	_check_string(str(s.get("blurb", "")), where + " blurb", errors)
	if not s.get("unlock", null) is String:
		errors.append('%s: unlock must be an unlock id, or "" for open from the start' % where)
	var fs: Array = s.get("frame_size", [0, 0])
	if fs.size() != 2 or int(fs[0]) > PLAYABLE_FRAME.x or int(fs[1]) > PLAYABLE_FRAME.y:
		errors.append("%s: a playable frame must fit %s" % [where, PLAYABLE_FRAME])


static func _validate_event(eid: String, e: Dictionary, errors: Array[String]) -> void:
	var where := "event %s" % eid
	_check_string(e.get("text", ""), where, errors)
	if not str(e.get("beacon", "event")) in BEACON_KINDS:
		errors.append("%s: unknown beacon kind %s" % [where, e.beacon])
	var choices: Array = e.get("choices", [])
	if choices.is_empty():
		errors.append("%s: no choices" % where)
	if choices.size() > MAX_CHOICES:
		errors.append("%s: more than %d choices" % [where, MAX_CHOICES])
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
			_validate_effects(where, o.get("effects", {}), errors)
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


static func _validate_effects(where: String, fx: Dictionary, errors: Array[String]) -> void:
	var fight := str(fx.get("fight", ""))
	if fight != "" and fight != Run.REACH_ENEMY and not ships.has(fight):
		errors.append("%s: fights unknown ship %s" % [where, fight])
	if fx.has("enemy_hull") and (fight == "" or not _int_in(fx.enemy_hull, -99, 0)):
		errors.append("%s: enemy_hull is a whole number <= 0, with a fight" % where)
	if fx.has("fight_bonus_scrap") and fight == "":
		errors.append("%s: fight_bonus_scrap needs a fight" % where)
	if fx.has("store") and (fx.store != true or fight != ""):
		errors.append("%s: store is true, and can't come with a fight" % where)


## Sounds, haptic patterns, cues and music, so a typo in a cue fails
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
	_validate_music(f.get("music", {}), errors)


## Music is clips, each a set of stems that play in lock-step, and states: a
## clip and which of its layers are up. A clip's stems must share their length
## and tempo, or the layers drift apart and bar-line cuts land off the beat.
static func _validate_music(music: Dictionary, errors: Array[String]) -> void:
	if float(music.get("fade", 1.5)) <= 0.0:
		errors.append("music: fade must be > 0")
	var clips: Variant = music.get("clips", {})
	if not clips is Dictionary or (clips as Dictionary).is_empty():
		errors.append("music: clips must be a table of clips")
		return
	var shapes := {}  ## clip -> [loops, bpm, beats, samples] of its stems
	var names := {}  ## every layer name in any clip
	for id: String in clips:
		if not clips[id] is Dictionary or not clips[id].get("layers") is Dictionary:
			errors.append("music clip %s: needs a table of layers" % id)
			continue
		shapes[id] = _clip_shape("music clip %s" % id, clips[id], errors)
		names.merge(clips[id].layers)
	for id: String in shapes:
		_validate_clip(id, clips, shapes, errors)
	var states: Variant = music.get("states", {})
	if not states is Dictionary:
		errors.append("music: states must be a table of states")
		return
	for state: String in states:
		_validate_state(state, states[state], shapes.keys(), clips, errors)
	for layer: Variant in music.get("hush_layers", []):
		if not names.has(layer):
			errors.append("music: unknown hush layer %s" % layer)


static func _validate_clip(
	id: String, clips: Dictionary, shapes: Dictionary, errors: Array[String]
) -> void:
	var where := "music clip %s" % id
	var c: Dictionary = clips[id]
	if not str(c.get("enter", "now")) in MUSIC_ENTRIES:
		errors.append("%s: enter is now, beat or bar" % where)
	if not str(c.get("fade", "out")) in ["out", "cross"]:
		errors.append("%s: fade is out or cross" % where)
	if not _num_in(c.get("fade_beats", 1), 0.0, 8.0):
		errors.append("%s: fade_beats is 0..8" % where)
	var once: Variant = c.get("once", false)
	var from: Variant = c.get("intro_from", [])
	if not once is bool or not from is Array:
		errors.append("%s: once is true or false, intro_from a list of clips" % where)
		return
	var linked: Array = from.duplicate()
	for k in ["intro", "then"]:
		if c.has(k):
			linked.append(c[k])
	for other: Variant in linked:
		if not shapes.has(str(other)):
			errors.append("%s: unknown clip %s" % [where, other])
	if c.has("then") and not once:
		errors.append("%s: only a clip that plays once ends, to hand over to %s" % [where, c.then])
	var intro := str(c.get("intro", ""))
	if shapes.has(intro) and not clips[intro].get("once", false):
		errors.append("%s: its intro must play once, or it would never start" % where)
	var shape: Array = shapes[id]
	if shape.is_empty():
		return
	if shape[0] == once:
		errors.append("%s: stems must loop unless the clip plays once (and not if it does)" % where)
	if str(c.get("enter", "now")) != "now" and float(shape[1]) <= 0.0:
		errors.append("%s: entering on a beat or bar needs a bpm in its stems' .import" % where)
	if float(shape[1]) > 0.0 and int(shape[2]) % 4 != 0:
		errors.append("%s: %d beats isn't whole 4/4 bars" % [where, shape[2]])


## A state's layers must belong to its clip, or to the clips that play for it:
## its intro and the clip it hands over to.
static func _validate_state(
	state: String, s: Variant, ok: Array, clips: Dictionary, errors: Array[String]
) -> void:
	var where := "music state %s" % state
	if not s is Dictionary or not s.get("layers", []) is Array:
		errors.append("%s: needs a clip and a list of layers" % where)
		return
	var clip := str(s.get("clip", ""))
	if clip != "" and not clip in ok:
		errors.append("%s: unknown clip %s" % [where, clip])
		return
	var names := {}
	if clip != "":
		for c in [clip, str(clips[clip].get("intro", "")), str(clips[clip].get("then", ""))]:
			if c in ok:
				names.merge(clips[c].layers)
	for layer: Variant in s.get("layers", []):
		if not names.has(layer):
			errors.append("%s: layer %s isn't in its clip" % [where, layer])


## The shape every stem of a clip must share: [loops, bpm, beats, samples].
static func _clip_shape(where: String, c: Dictionary, errors: Array[String]) -> Array:
	var layers: Dictionary = c.get("layers", {})
	if layers.is_empty() or layers.size() > 8:
		errors.append("%s: needs 1..8 layers" % where)
	var shape := []
	for id: String in layers:
		var s: Dictionary = layers[id]
		var file := str(s.get("file", ""))
		if not _num_in(s.get("volume_db", 0), -60.0, 12.0):
			errors.append("%s layer %s: volume_db is -60..12" % [where, id])
		if not ResourceLoader.exists(file):
			errors.append("%s layer %s: stem not found %s" % [where, id, file])
			continue
		var stem: AudioStream = load(file)
		var ogg := stem as AudioStreamOggVorbis
		var bpm := ogg.bpm if ogg else 0.0
		var beats := ogg.beat_count if ogg else 0
		var samples := roundi(stem.get_length() * 44100.0)
		var this := [_loops(stem), bpm, beats, samples]
		if bpm > 0.0 and absi(samples - roundi(beats * 60.0 / bpm * 44100.0)) > 44:
			errors.append(
				"%s layer %s: %d beats at %d bpm isn't its length" % [where, id, beats, bpm]
			)
		if shape.is_empty():
			shape = this
		elif this != shape:
			errors.append(
				"%s layer %s: loop, tempo or length differs from the others" % [where, id]
			)
	return shape


static func _loops(stream: Resource) -> bool:
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return false


## A sound is a one-shot: a file that doesn't loop, or a synth recipe.
static func _validate_sound(where: String, s: Dictionary, errors: Array[String]) -> void:
	var file := str(s.get("file", ""))
	if file != "" and not ResourceLoader.exists(file):
		errors.append("%s: file not found %s" % [where, file])
	elif file != "" and _loops(load(file)):
		errors.append("%s: %s loops, but sounds play once" % [where, file])
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
	var top := maxf(float(r.get("freq", 440)), float(r.get("freq_end", r.get("freq", 440))))
	if str(r.get("wave", "sine")) == "sine" and top < PHONE_LOW_HZ:
		errors.append("%s: a sine under %d Hz is silent on a phone speaker" % [where, PHONE_LOW_HZ])
	if not _num_in(r.get("decay", 0), 0.0, 100.0):
		errors.append("%s: decay is 0..100" % where)
	if not _num_in(r.get("noise", 0), 0.0, 1.0):
		errors.append("%s: noise is 0..1" % where)


static func _num_in(v: Variant, lo: float, hi: float) -> bool:
	return (v is float or v is int) and float(v) >= lo and float(v) <= hi


static func _int_in(v: Variant, lo: int, hi: int) -> bool:
	return _num_in(v, lo, hi) and float(v) == floorf(float(v))


## Lessons and tips may only use the conditions, targets and moments the coach knows,
## so a typo fails here instead of leaving a step that can never finish.
static func _validate_tutorial(t: Dictionary, errors: Array[String]) -> void:
	var ids: Array[String] = []
	for l: Variant in _array(t.get("lessons")):
		if not l is Dictionary:
			errors.append("tutorial: every lesson must be an object")
			continue
		var where := "lesson %s" % l.get("id", "?")
		if str(l.get("id", "")) == "" or ids.has(str(l.id)):
			errors.append("%s: needs a unique id" % where)
		if not str(l.get("screen", "")) in Tutorial.SCREENS:
			errors.append("%s: unknown screen %s" % [where, l.get("screen", "")])
		var after := str(l.get("after", ""))
		if after != "" and not ids.has(after):  # checked before this id joins the list
			errors.append("%s: after must name an earlier lesson" % where)
		ids.append(str(l.get("id", "")))
		var steps := _array(l.get("steps"))
		if steps.is_empty():
			errors.append("%s: needs steps" % where)
		for s: Variant in steps:
			if not s is Dictionary:
				errors.append("%s: every step must be an object" % where)
				continue
			_validate_step("%s step %s" % [where, s.get("id", "?")], s, errors)
	var tip_ids: Array[String] = []
	for tip: Variant in _array(t.get("tips")):
		if not tip is Dictionary:
			errors.append("tutorial: every tip must be an object")
			continue
		var where := "tip %s" % tip.get("id", "?")
		if str(tip.get("id", "")) == "" or tip_ids.has(str(tip.id)):
			errors.append("%s: needs a unique id" % where)
		tip_ids.append(str(tip.get("id", "")))
		if not str(tip.get("on", "")) in Tutorial.TIP_MOMENTS:
			errors.append("%s: unknown moment %s" % [where, tip.get("on", "")])
		_check_string(str(tip.get("text", "")), where, errors)


static func _validate_step(where: String, s: Dictionary, errors: Array[String]) -> void:
	_check_string(str(s.get("text", "")), where, errors)
	var done := str(s.get("done", ""))
	var cond := done.get_slice(":", 0)
	if not cond in Tutorial.CONDITIONS:
		errors.append("%s: unknown done condition %s" % [where, done])
	elif cond == "did" and not done.get_slice(":", 1) in Tutorial.ORDERS:
		errors.append("%s: did needs one of %s" % [where, Tutorial.ORDERS])
	elif cond == "aimed" and not done.get_slice(":", 1).is_valid_int():
		errors.append("%s: aimed needs a weapon slot" % where)
	if s.has("hold") and not s.hold is bool:
		errors.append("%s: hold must be true or false" % where)
	_validate_target(where, str(s.get("target", "")), errors)
	if s.has("then") and not s.then is Dictionary:
		errors.append("%s: then must be an object" % where)
		return
	var then: Dictionary = s.get("then", {})
	if not then.is_empty():
		if not str(then.get("when", "")).get_slice(":", 0) in Tutorial.WHENS:
			errors.append("%s: unknown then.when %s" % [where, then.get("when", "")])
		_check_string(str(then.get("text", "")), where + " then", errors)
		_validate_target(where + " then", str(then.get("target", "")), errors)


static func _validate_target(where: String, target: String, errors: Array[String]) -> void:
	var kind := target.get_slice(":", 0)
	if not kind in Tutorial.TARGETS:
		errors.append("%s: unknown target %s" % [where, target])
	elif kind in ["system", "enemy_room"] and not systems.has(target.get_slice(":", 1)):
		errors.append("%s: unknown system in %s" % [where, target])
	elif kind == "weapon" and not target.get_slice(":", 1).is_valid_int():
		errors.append("%s: weapon target needs a slot" % where)


static func _array(v: Variant) -> Array:
	return v if v is Array else []
