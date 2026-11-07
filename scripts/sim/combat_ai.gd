class_name CombatAI
extends RefCounted
## Enemy captain. Sends the same orders a player can, through Combat.apply.
## Uses its own random stream so AI changes never shift combat rolls.

const TARGET_WEIGHTS := {"weapons": 3, "wards": 2, "helm": 2, "ember": 2, "engines": 1, "mend": 1}
const STATIONS: Array[String] = ["weapons", "helm", "wards", "engines"]
const WARD_REACT := 3.0

var ward_timer := 0.0


func think(combat: Combat, side: int) -> void:
	var me := combat.ships[side]
	var foe := combat.ships[1 - side]
	if me.is_dead():
		return
	var r := combat.rng.stream("ai")
	_aim(combat, me, foe, side, r)
	_wards(combat, me, foe, side)
	_crew(combat, me, side)


func _aim(combat: Combat, me: Ship, foe: Ship, side: int, r: RandomNumberGenerator) -> void:
	# With nothing that strips a ward, only the deck the ward leaves open can be hurt.
	var shut := foe.ward_deck if foe.ward_layers > 0 and not _strips_wards(me) else -1
	for i in me.weapon_ids.size():
		# A gun that passes wards (Chill) can hit the warded deck as well.
		var skip := -1 if ContentDB.weapons[me.weapon_ids[i]].get("pierces_ward", false) else shut
		var aimed := me.weapon_target[i]
		var wasted := aimed != "" and foe.room(aimed).deck == skip
		if aimed != "" and me.weapon_charge[i] > 0.0 and not wasted:
			continue
		var pool := _targets(foe, skip)
		if pool.is_empty():
			pool = _targets(foe, -1)
		if pool.is_empty():
			continue
		# Kinetics go wherever; a torch follows the first gun so it lands on a stripped ward.
		var pick := pool[r.randi_range(0, pool.size() - 1)]
		var torch: bool = ContentDB.weapons[me.weapon_ids[i]].family == "torch"
		if torch and i > 0 and me.weapon_target[0] != "":
			pick = me.weapon_target[0]
		combat.apply({"type": "aim", "weapon": i, "room": pick}, side)


func _targets(foe: Ship, skip_deck: int) -> Array[String]:
	var pool: Array[String] = []
	for room in foe.rooms:
		if room.deck != skip_deck:
			for k in TARGET_WEIGHTS.get(room.system, 0):
				pool.append(room.id)
	return pool


func _strips_wards(me: Ship) -> bool:
	for wid in me.weapon_ids:
		if ContentDB.weapons[wid].strips_ward:
			return true
	return false


## Watches where the player is aiming and moves its ward to the busier deck.
## It reacts on a delay so a quick player can catch it out.
func _wards(combat: Combat, me: Ship, foe: Ship, side: int) -> void:
	ward_timer += Combat.AI_THINK
	if ward_timer < WARD_REACT:
		return
	ward_timer = 0.0
	var counts := [0, 0]
	for t in foe.weapon_target:
		if t != "":
			counts[me.room(t).deck] += 1
	if counts[0] > counts[1]:
		combat.apply({"type": "ward_deck", "deck": 0}, side)
	elif counts[1] > counts[0]:
		combat.apply({"type": "ward_deck", "deck": 1}, side)


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
	# Emergencies next: fires, then broken systems.
	var jobs: Array[String] = []
	for room in me.rooms:
		if room.fire > 0.0 and me.crew_in(room.id).is_empty() and not busy.has(room.id):
			jobs.append(room.id)
	for room in me.rooms:
		if (
			room.damage > 0.0
			and room.fire <= 0.0
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
