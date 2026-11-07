class_name Siege
extends RefCounted
## The Kindling: the run's last fight, at the Cradle past Reach 4's Gate. No
## flagship comes; the Hush itself besieges the ship in three phases (see
## data/sieges.json), and the defender wins by kindling the Cradle, not by a kill.
##
## Each wave gathers in one of the Hush maw's knots for a few seconds, showing
## what it will strike: a whole deck (chill) or one system (swallow). The
## defender's guns can break a gathering knot, a ward on the struck deck soaks
## what is left a layer per point, and whatever still lands chills the rooms,
## scrapes the hull, and on a swallow knocks the system out until it is mended.
## In the last phase the defender burns Light into the Ember to kindle faster.
##
## Plain sim code like Combat: it runs at Combat.TICK, rolls on its own
## "siege" stream, and only changes the ships through their own state.

const KINDS: Array[String] = ["chill", "swallow"]

var id: String
var phase: int = 0
var phase_ticks: int = 0  ## ticks into the current phase (counted, so phases never drift)
## Seconds until the next wave may start. It runs from one wave's start to the
## next, so breaking a knot early never brings the next wave sooner.
var wave_timer: float = 0.0
var light: int = 0  ## the defender's Light, carried in from the run and back out
var kindling: float = 0.0  ## progress to the goal; only grows in the last phase
var done: bool = false  ## kindled: the defender has won
## The wave now gathering; knot is "" between waves.
var knot: String = ""  ## the maw room it gathers in
var gather: float = 0.0  ## seconds until it lands
var gather_total: float = 0.0  ## the gather time it started with (its phase's, even after a change)
var strength: int = 0  ## what is left of it; hits on the knot wear it down
var wave_kind: String = ""  ## "chill" or "swallow"
var target_deck: int = -1  ## the defender's deck it strikes
var target_room: String = ""  ## swallow only: the system room it strikes


static func create(siege_id: String, light_value: int) -> Siege:
	var s := Siege.new()
	s.id = siege_id
	s.light = maxi(0, light_value)
	s.wave_timer = float(s.phase_data().first_wave)
	return s


func data() -> Dictionary:
	return ContentDB.sieges[id]


func phases() -> Array:
	return data().phases


func phase_data() -> Dictionary:
	return phases()[phase]


func is_last_phase() -> bool:
	return phase == phases().size() - 1


func goal() -> float:
	return float(data().kindle.goal)


func phase_time() -> float:
	return phase_ticks * Combat.TICK


## Seconds left in a timed phase; the last phase lasts until the Cradle is kindled.
func phase_left() -> float:
	if is_last_phase():
		return 0.0
	return maxf(0.0, float(phase_data().seconds) - phase_time())


func gathering() -> bool:
	return knot != ""


## Defender is side 0, the maw side 1: the siege is set up that way by Run.
func tick(combat: Combat, dt: float, events: Array) -> void:
	if done:
		return
	var me := combat.player()
	phase_ticks += 1
	_tick_kindling(me, dt, events)
	if done:
		_quantize()
		return
	_tick_phase(events)
	_tick_wave(combat, me, dt, events)
	_quantize()


func _tick_kindling(me: Ship, dt: float, events: Array) -> void:
	if not is_last_phase():
		return
	kindling += float(data().kindle.per_second) * _ember_share(me) * dt
	if kindling >= goal():
		kindling = goal()
		done = true
		_end_wave(me)
		events.append({"type": "kindled"})


## How fast the Cradle takes: half from just being here, half from a whole
## Ember. A swallowed Ember slows the kindling but never stops it, so a siege
## always ends.
static func _ember_share(me: Ship) -> float:
	var ember := me.system_room("ember")
	if ember == null or ember.level <= 0:
		return 0.5
	return 0.5 + 0.5 * float(ember.effective_level()) / float(ember.level)


func _tick_phase(events: Array) -> void:
	if is_last_phase() or phase_time() < float(phase_data().seconds) - 0.001:
		return
	phase += 1
	phase_ticks = 0
	# A wave caught at the change still lands; the next one keeps the new phase's pace.
	if not gathering():
		wave_timer = float(phase_data().first_wave)
	events.append({"type": "siege_phase", "phase": phase})


func _tick_wave(combat: Combat, me: Ship, dt: float, events: Array) -> void:
	wave_timer -= dt
	if gathering():
		gather -= dt
		if gather <= 0.0:
			_land(me, combat.rng.stream("siege"), events)
		return
	if wave_timer <= 0.0:
		_start_wave(combat, me, events)


func _start_wave(combat: Combat, me: Ship, events: Array) -> void:
	var p := phase_data()
	var r := combat.rng.stream("siege")
	var kinds: Dictionary = p.kinds
	var weights: Array[int] = []
	for k in KINDS:
		weights.append(int(kinds.get(k, 0)))
	wave_kind = KINDS[maxi(0, RngStreams.weighted_pick(weights, r))]
	target_room = ""
	if wave_kind == "swallow":
		target_room = _pick_system(me, p.get("targets", []), r)
		if target_room == "":
			wave_kind = "chill"  # nothing left to swallow: it chills instead
	if wave_kind == "swallow":
		target_deck = me.room(target_room).deck
	else:
		target_deck = r.randi_range(0, 1)
	knot = _pick_knot(combat.enemy(), target_deck, r)
	gather = float(p.gather)
	gather_total = gather
	wave_timer = float(p.wave_every)
	strength = int(p.strength)
	events.append(
		{
			"type": "wave_gather",
			"side": 1,
			"room": knot,
			"kind": wave_kind,
			"deck": target_deck,
			"target": target_room
		}
	)


## A system the wave can swallow: a working one from the phase's list, so the
## same broken room isn't struck twice.
static func _pick_system(me: Ship, targets: Array, r: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	for sys: String in targets:
		var room := me.system_room(sys)
		if room and room.level > 0 and room.effective_level() > 0:
			pool.append(room.id)
	if pool.is_empty():
		return ""
	return pool[r.randi_range(0, pool.size() - 1)]


## A knot on the maw's deck that faces the struck deck, so the threat reads across.
static func _pick_knot(maw: Ship, deck: int, r: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	for room in maw.rooms:
		if room.deck == deck:
			pool.append(room.id)
	if pool.is_empty():
		for room in maw.rooms:
			pool.append(room.id)
	return pool[r.randi_range(0, pool.size() - 1)]


## A shot landed on the maw. Only the gathering knot gives way; the rest of the
## Hush swallows the shot. Returns true if it struck the wave.
func strike(me: Ship, room_id: String, damage: int, events: Array) -> bool:
	if not gathering() or room_id != knot or done:
		events.append({"type": "hush_absorb", "side": 1, "room": room_id})
		return false
	strength = maxi(0, strength - damage)
	events.append({"type": "knot_hit", "side": 1, "room": room_id, "left": strength})
	if strength <= 0:
		events.append({"type": "wave_broken", "side": 1, "room": room_id})
		_end_wave(me)
	return true


func _land(me: Ship, rng: RandomNumberGenerator, events: Array) -> void:
	var left := strength
	var struck := target_room if target_room != "" else _deck_room(me, target_deck)
	if me.ward_layers > 0 and me.ward_deck == target_deck:
		var soaked := mini(me.ward_layers, left)
		me.ward_layers -= soaked
		me.ward_regen = 0.0
		left -= soaked
		events.append({"type": "ward_hit", "side": 0, "room": struck})
	if left > 0:
		_strike_ship(me, left, events)
		# A ship that can dodge slips the worst of it: the cold still gets in,
		# but the hull is spared, the same roll as a shot against its evasion.
		if rng.randf() * 100.0 < me.evasion():
			events.append({"type": "miss", "side": 0, "room": struck})
		else:
			me.hull = maxi(0, me.hull - _hull_hit())
			events.append({"type": "hit", "side": 0, "room": struck, "damage": _hull_hit()})
	events.append(
		{"type": "wave_landed", "side": 0, "room": struck, "kind": wave_kind, "left": left}
	)
	_end_wave(me)


## The cold of what got through: a swallow bites its system, a chill the whole deck.
func _strike_ship(me: Ship, left: int, events: Array) -> void:
	var chill := float(data().chill_per_strength) * left
	if wave_kind == "swallow":
		var r := me.room(target_room)
		var bite := float(data().swallow_per_strength) * left
		r.damage = minf(float(r.level), r.damage + bite)
		r.warmth = maxf(0.0, r.warmth - chill)
		events.append({"type": "swallowed", "side": 0, "room": r.id})
		return
	for r in me.rooms:
		if r.deck == target_deck:
			r.warmth = maxf(0.0, r.warmth - chill)


func _hull_hit() -> int:
	return int(data().hull_per_wave)


## The middle room of a deck, where a deck-wide wave's words and flash go.
static func _deck_room(me: Ship, deck: int) -> String:
	var row: Array[Room] = []
	for r in me.rooms:
		if r.deck == deck:
			row.append(r)
	if row.is_empty():
		return me.rooms[0].id
	row.sort_custom(func(a: Room, b: Room) -> bool: return a.rect.position.x < b.rect.position.x)
	return row[row.size() / 2].id


## The wave is spent and its knot sinks back into the Hush: guns aimed at it
## stand down, so a charged gun waits for the next knot instead of firing into nothing.
func _end_wave(me: Ship) -> void:
	for i in me.weapon_target.size():
		if knot != "" and me.weapon_target[i] == knot:
			me.weapon_target[i] = ""
	knot = ""
	gather = 0.0
	gather_total = 0.0
	strength = 0
	target_room = ""
	target_deck = -1
	wave_kind = ""


## Burns one Light into the Ember for the Cradle. Only in the last phase.
func can_kindle() -> bool:
	return not done and is_last_phase() and light > 0


## No event: an order lands between ticks, and the view cues the tap itself.
func kindle(me: Ship) -> bool:
	if not can_kindle():
		return false
	light -= 1
	kindling = minf(goal(), kindling + float(data().kindle.per_light))
	var ember := me.system_room("ember")
	if ember:
		ember.warmth = minf(100.0, ember.warmth + float(data().kindle.light_warmth))
	return true


func _quantize() -> void:
	wave_timer = Q.q(wave_timer)
	kindling = Q.q(kindling)
	gather = Q.q(gather)
	gather_total = Q.q(gather_total)


# ---------------------------------------------------------------- content


## Every field the siege reads, so a bad sieges.json fails ContentDB.validate().
static func validate(sid: String, d: Dictionary, errors: Array[String]) -> void:
	var where := "siege %s" % sid
	for key in ["name", "intro"]:
		ContentDB.check_string(str(d.get(key, "")), where, errors)
	var maw: Dictionary = ContentDB.ships.get(str(d.get("maw", "")), {})
	if not bool(maw.get("siege_only", false)):
		errors.append("%s: maw must be a siege_only ship" % where)
	elif not (_has_deck(maw, 0) and _has_deck(maw, 1)):
		errors.append("%s: the maw needs knots on both decks" % where)
	for f in ["chill_per_strength", "swallow_per_strength"]:
		if not ContentDB.is_num_in(d.get(f), 0.0, 100.0):
			errors.append("%s: %s must be 0 to 100" % [where, f])
	if not ContentDB.is_int_in(d.get("hull_per_wave"), 0, 10):
		errors.append("%s: hull_per_wave must be 0 to 10" % where)
	var k: Dictionary = d.get("kindle", {})
	if not ContentDB.is_num_in(k.get("goal"), 1.0, 10000.0):
		errors.append("%s: kindle.goal must be above 0" % where)
	if not ContentDB.is_num_in(k.get("per_second"), 0.01, 100.0):
		errors.append("%s: kindle.per_second must be above 0, or it never ends" % where)
	for f in ["per_light", "light_warmth"]:
		if not ContentDB.is_num_in(k.get(f), 0.0, 100.0):
			errors.append("%s: kindle.%s must be 0 to 100" % [where, f])
	var list: Array = d.get("phases", [])
	if list.is_empty():
		errors.append("%s: needs at least one phase" % where)
	for i in list.size():
		_validate_phase("%s phase %d" % [where, i], list[i], i == list.size() - 1, errors)


static func _validate_phase(
	where: String, p: Dictionary, last: bool, errors: Array[String]
) -> void:
	for key in ["name", "hint"]:
		ContentDB.check_string(str(p.get(key, "")), where, errors)
	if not last and not ContentDB.is_num_in(p.get("seconds"), 1.0, 600.0):
		errors.append("%s: seconds must be 1 to 600 (only the last phase runs to the end)" % where)
	if not ContentDB.is_num_in(p.get("gather"), 1.0, 30.0):
		errors.append("%s: gather must be 1 to 30 seconds, time enough to answer" % where)
	elif not ContentDB.is_num_in(p.get("wave_every"), float(p.gather), 120.0):
		errors.append("%s: wave_every must be at least gather" % where)
	if not ContentDB.is_num_in(p.get("first_wave"), 0.0, 120.0):
		errors.append("%s: first_wave must be 0 to 120" % where)
	if not ContentDB.is_int_in(p.get("strength"), 1, 20):
		errors.append("%s: strength must be 1 to 20" % where)
	var kinds: Dictionary = p.get("kinds", {})
	var total := 0
	for kind: String in kinds:
		if not kind in KINDS:
			errors.append("%s: unknown wave kind %s" % [where, kind])
		total += maxi(0, int(kinds[kind]))
	if total <= 0:
		errors.append("%s: kinds must give some wave a weight" % where)
	for sys: Variant in p.get("targets", []):
		if not ContentDB.systems.has(str(sys)):
			errors.append("%s: swallow target %s is not a system" % [where, sys])
	if int(kinds.get("swallow", 0)) > 0 and (p.get("targets", []) as Array).is_empty():
		errors.append("%s: swallow waves need targets" % where)


static func _has_deck(ship: Dictionary, deck: int) -> bool:
	for r: Dictionary in ship.get("rooms", []):
		if int(r.get("deck", -1)) == deck:
			return true
	return false


# ---------------------------------------------------------------- save


func to_dict() -> Dictionary:
	return {
		"id": id,
		"phase": phase,
		"phase_ticks": phase_ticks,
		"wave_timer": wave_timer,
		"light": light,
		"kindling": kindling,
		"done": done,
		"knot": knot,
		"gather": gather,
		"gather_total": gather_total,
		"strength": strength,
		"wave_kind": wave_kind,
		"target_deck": target_deck,
		"target_room": target_room,
	}


static func from_dict(d: Dictionary) -> Siege:
	var s := Siege.new()
	s.id = str(d.id)
	s.phase = clampi(int(d.get("phase", 0)), 0, s.phases().size() - 1)
	s.phase_ticks = int(d.get("phase_ticks", 0))
	s.wave_timer = float(d.get("wave_timer", 0.0))
	s.light = int(d.get("light", 0))
	s.kindling = float(d.get("kindling", 0.0))
	s.done = bool(d.get("done", false))
	s.knot = str(d.get("knot", ""))
	s.gather = float(d.get("gather", 0.0))
	s.gather_total = float(d.get("gather_total", s.gather))
	s.strength = int(d.get("strength", 0))
	s.wave_kind = str(d.get("wave_kind", ""))
	s.target_deck = int(d.get("target_deck", -1))
	s.target_room = str(d.get("target_room", ""))
	return s
