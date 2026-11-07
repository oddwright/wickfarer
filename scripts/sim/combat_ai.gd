class_name CombatAI
extends RefCounted
## Enemy captain. Sends the same orders a player can, through Combat.apply.
## Uses its own random stream so AI changes never shift combat rolls.

const TARGET_WEIGHTS := {"weapons": 3, "wards": 2, "helm": 2, "ember": 2, "engines": 1, "mend": 1}
const STATIONS: Array[String] = ["weapons", "helm", "wards", "engines"]
const WARD_REACT := 3.0
## How much more the other deck must be threatened before the ward moves there.
const WARD_MOVE_MARGIN := 1.25
## Extra seconds the ward stays put after a move.
const WARD_SETTLE := 5.0
## How each hull's captain fights comes from its "ai" block in ships.json:
## "targets" (room weights by system), "ward_react" (seconds between ward checks),
## "volley" (hold every gun until all are charged, then fire together) and
## "focus" (every gun on the first gun's room). A hull without one fights like
## an Ashmarket raider.
const TACTICS: Array[String] = ["targets", "ward_react", "volley", "focus"]

var ward_timer := 0.0


static func tactics(ship_id: String) -> Dictionary:
	return ContentDB.ships.get(ship_id, {}).get("ai", {})


static func validate_tactics(where: String, ai: Variant, errors: Array[String]) -> void:
	if not ai is Dictionary:
		errors.append("%s: ai must be an object" % where)
		return
	for k: String in ai:
		if not k in TACTICS:
			errors.append("%s: unknown ai tactic %s" % [where, k])
	var weights: Variant = ai.get("targets", {})
	if not weights is Dictionary:
		errors.append("%s: ai.targets must map systems to weights" % where)
	else:
		var total := 0
		for sys: String in weights:
			if not ContentDB.systems.has(sys):
				errors.append("%s: ai.targets names unknown system %s" % [where, sys])
			if not ContentDB.is_int_in(weights[sys], 0, 20):
				errors.append(
					"%s: ai.targets.%s must be a whole number from 0 to 20" % [where, sys]
				)
			else:
				total += int(weights[sys])
		if ai.has("targets") and total <= 0:
			errors.append("%s: ai.targets must weigh at least one system above 0" % where)
	var react: Variant = ai.get("ward_react", WARD_REACT)
	if not (react is float or react is int) or float(react) < Combat.AI_THINK:
		errors.append("%s: ai.ward_react must be at least %s seconds" % [where, Combat.AI_THINK])
	for flag in ["volley", "focus"]:
		if ai.has(flag) and not ai[flag] is bool:
			errors.append("%s: ai.%s must be true or false" % [where, flag])


func think(combat: Combat, side: int) -> void:
	var me := combat.ships[side]
	var foe := combat.ships[1 - side]
	if me.is_dead():
		return
	var r := combat.rng.stream("ai")
	var t := tactics(me.content_id)
	if bool(t.get("volley", false)) and not _volley_ready(me):
		_hold(combat, me, side)
	else:
		_aim(combat, me, foe, side, r, t)
	_wards(combat, me, foe, side, float(t.get("ward_react", WARD_REACT)))
	_crew(combat, me, side)
	flare_when_it_pays(combat, me, side)


## Flares when it pays: guns aimed and still charging, or the ship going cold,
## and never with the Ember already hurt or burning (the crack would stack).
static func flare_when_it_pays(combat: Combat, me: Ship, side: int) -> void:
	if not EmberFlare.can(me):
		return
	var ember := me.system_room("ember")
	if ember.damage > 0.0 or ember.fire > 0.0:
		return
	# A one-level Ember goes dark when it cracks: only flare one with a hand there to patch it.
	if ember.level <= 1 and me.crew_in(ember.id).is_empty():
		return
	var charging := 0
	for i in me.weapon_ids.size():
		var full := float(ContentDB.weapons[me.weapon_ids[i]].charge)
		if me.weapon_target[i] != "" and me.weapon_powered(i) and me.weapon_charge[i] < full - 3.0:
			charging += 1
	var cold := false
	for st in STATIONS:
		var r := me.system_room(st)
		cold = cold or (r != null and r.warmth < Ship.COLD and not me.crew_in(r.id).is_empty())
	if charging >= 2 or cold:
		combat.apply({"type": "flare"}, side)


## A volley captain fires only when every powered gun is charged.
static func _volley_ready(me: Ship) -> bool:
	var any := false
	for i in me.weapon_ids.size():
		if me.weapon_powered(i):
			any = true
			if me.weapon_eta(i) > 0.0:
				return false
	return any


## Holding is an order any captain can give: aim at nothing, so the gun keeps its charge.
func _hold(combat: Combat, me: Ship, side: int) -> void:
	for i in me.weapon_ids.size():
		if me.weapon_target[i] != "":
			combat.apply({"type": "aim", "weapon": i, "room": ""}, side)


func _aim(
	combat: Combat, me: Ship, foe: Ship, side: int, r: RandomNumberGenerator, t: Dictionary
) -> void:
	# With nothing that strips a ward, only the deck the ward leaves open can be hurt.
	var shut := foe.ward_deck if foe.ward_layers > 0 and not _strips_wards(me) else -1
	var weights: Dictionary = t.get("targets", TARGET_WEIGHTS)
	var focus := bool(t.get("focus", false))
	for i in me.weapon_ids.size():
		# A gun that passes wards (Chill) can hit the warded deck as well.
		var skip := -1 if ContentDB.weapons[me.weapon_ids[i]].get("pierces_ward", false) else shut
		var aimed := me.weapon_target[i]
		var wasted := aimed != "" and foe.room(aimed).deck == skip
		# A focused gun follows the first gun wherever it goes.
		var lead := me.weapon_target[0] if focus and i > 0 else ""
		if lead != "" and not wasted:
			if aimed != lead:
				combat.apply({"type": "aim", "weapon": i, "room": lead}, side)
			continue
		if aimed != "" and me.weapon_charge[i] > 0.0 and not wasted:
			continue
		var pool := _targets(foe, skip, weights)
		if pool.is_empty():
			pool = _targets(foe, -1, weights)
		if pool.is_empty():
			continue
		# Kinetics go wherever; a torch follows the first gun so it lands on a stripped ward.
		var pick := pool[r.randi_range(0, pool.size() - 1)]
		var torch: bool = ContentDB.weapons[me.weapon_ids[i]].family == "torch"
		if torch and i > 0 and me.weapon_target[0] != "":
			pick = me.weapon_target[0]
		combat.apply({"type": "aim", "weapon": i, "room": pick}, side)


func _targets(foe: Ship, skip_deck: int, weights: Dictionary) -> Array[String]:
	var pool: Array[String] = []
	for room in foe.rooms:
		if room.deck != skip_deck:
			for k in int(weights.get(room.system, 0)):
				pool.append(room.id)
	return pool


func _strips_wards(me: Ship) -> bool:
	for wid in me.weapon_ids:
		if ContentDB.weapons[wid].strips_ward:
			return true
	return false


## Watches where the player is aiming and moves its ward to the deck where it
## would stop the most. It reacts on a delay so a quick player can catch it out.
func _wards(combat: Combat, me: Ship, foe: Ship, side: int, react: float) -> void:
	ward_timer += Combat.AI_THINK
	if ward_timer < react:
		return
	ward_timer = 0.0
	var here := ward_threat(me, foe, me.ward_deck)
	var there := ward_threat(me, foe, 1 - me.ward_deck)
	# Counting guns let one gun per deck pin the ward in place for good, even
	# with the heavier gun free on the open deck. Moving halves the layers, so
	# it only moves for a clear gain.
	if there > here * WARD_MOVE_MARGIN:
		combat.apply({"type": "ward_deck", "deck": 1 - me.ward_deck}, side)
		# Then let the layers grow back before thinking again: chasing every
		# re-aim kept the ward at no layers at all.
		ward_timer = -WARD_SETTLE


## Damage a ward on this deck would stop each second from the foe's powered,
## aimed guns: every shot of a gun it blocks, one shot per layer of a gun that
## strips it, nothing of one that passes through. Fire and crew harm count too.
static func ward_threat(me: Ship, foe: Ship, deck: int) -> float:
	var layers := maxi(1, me.max_ward_layers())
	var total := 0.0
	for i in foe.weapon_ids.size():
		var t := foe.weapon_target[i]
		if t == "" or me.room(t).deck != deck or not foe.weapon_powered(i):
			continue
		var w: Dictionary = ContentDB.weapons[foe.weapon_ids[i]]
		if w.get("pierces_ward", false):
			continue
		var shot := float(int(w.hull_damage) + int(w.system_damage))
		shot += 0.1 * float(w.crew_damage) + 4.0 * float(w.fire_chance)
		var shots := int(w.shots)
		var stopped := mini(shots, layers) if w.strips_ward else shots
		total += shot * float(stopped) / float(w.charge)
	return total


func _crew(combat: Combat, me: Ship, side: int) -> void:
	var busy := {}
	var idle: Array[Crew] = []
	for c in me.alive_crew():
		if c.is_moving():
			busy[c.path.back()] = true
		else:
			idle.append(c)
	# Hurt crew go to mend if it has power.
	var mend := me.system_room("mend")
	for c in idle.duplicate():
		if mend and mend.power > 0 and c.hp < c.max_hp * 0.35 and c.room != mend.id:
			combat.apply({"type": "move", "crew": c.uid, "room": mend.id}, side)
			idle.erase(c)
	# One hand already fighting a fire, sealing a rent or repairing stays at it:
	# pulling the last one off to fill a station left broken guns broken for good
	# (crew bounced between the two). Anyone else in the room is free for jobs.
	var held := {}
	for c in idle.duplicate():
		var here := me.room(c.room)
		if (here.fire > 0.0 or here.rent > 0.0 or here.damage > 0.0) and not held.has(c.room):
			held[c.room] = true
			idle.erase(c)
	# Emergencies next: fires, then rents, then broken systems.
	var jobs: Array[String] = []
	for room in me.rooms:
		if room.fire > 0.0 and me.crew_in(room.id).is_empty() and not busy.has(room.id):
			jobs.append(room.id)
	for room in me.rooms:
		if (
			room.rent > 0.0
			and room.fire <= 0.0
			and not held.has(room.id)
			and me.crew_in(room.id).is_empty()
			and not busy.has(room.id)
		):
			jobs.append(room.id)
	for room in me.rooms:
		if (
			room.damage > 0.0
			and room.fire <= 0.0
			and room.rent <= 0.0
			and me.crew_in(room.id).is_empty()
			and not busy.has(room.id)
		):
			jobs.append(room.id)
	for job in jobs:
		if idle.is_empty():
			return
		var best: Crew = null
		var best_len := 999
		for c in idle:
			var n := me.find_path(c.room, job).size()
			if n < best_len:
				best_len = n
				best = c
		combat.apply({"type": "move", "crew": best.uid, "room": job}, side)
		idle.erase(best)
	# Everyone else goes back to a station.
	var taken := {}
	for c in me.alive_crew():
		if c.is_moving():
			taken[c.path.back()] = true
		elif me.room(c.room).system in STATIONS:
			taken[c.room] = true
	var spare: Array[Crew] = []
	for c in idle:
		var here := me.room(c.room)
		# Crew stay at a station, or at their own post (a stoker at the Ember).
		var at_post := here.system in STATIONS or (c.room == c.post and here.system != "")
		if not (at_post and here.fire <= 0.0 and here.damage <= 0.0):
			spare.append(c)
	# Fill empty stations most important first; whoever's post it is takes it,
	# so their skill keeps growing there.
	for st in STATIONS:
		var room := me.system_room(st)
		if spare.is_empty():
			return
		if room == null or taken.has(room.id):
			continue
		var pick: Crew = spare[0]
		for c in spare:
			if c.post == room.id:
				pick = c
				break
		combat.apply({"type": "move", "crew": pick.uid, "room": room.id}, side)
		taken[room.id] = true
		spare.erase(pick)
	# Anyone left over whose post is another station (the Ember) goes back to it.
	for c in spare:
		if c.post != "" and c.post != c.room and not taken.has(c.post):
			if me.room(c.post).system != "":
				combat.apply({"type": "move", "crew": c.uid, "room": c.post}, side)
				taken[c.post] = true
