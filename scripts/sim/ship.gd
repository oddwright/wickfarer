class_name Ship
extends RefCounted
## One ship's state and rules. The player and every enemy run this same code.

const WALK_TIME := 1.0  ## seconds to cross into a neighbouring room
const LADDER_TIME := 1.6
const COLD := 25.0  ## below this, crew work at half speed
const FREEZING := 15.0  ## below this, crew lose health
const POWER_SHED_ORDER: Array[String] = ["mend", "engines", "helm", "weapons", "wards"]
const WARD_REGEN_TIME := 2.5

var content_id: String
var side: int  ## 0 = player, 1 = enemy
var hull: int
var max_hull: int
var reactor: int
var rooms: Array[Room] = []
var crew: Array[Crew] = []
var weapon_ids: Array[String] = []
var weapon_charge: Array[float] = []
var weapon_target: Array[String] = []
var ward_deck: int = 1
var ward_layers: int = 0
var ward_regen: float = 0.0
var next_uid: int = 1
var stokes: int = 0  ## times the Ember has been stoked this run
var ladders: Array[Dictionary] = []

var _room_by_id: Dictionary = {}
var _neighbors: Dictionary = {}  ## room id -> Array of [room id, seconds]


static func from_content(id: String, side_value: int) -> Ship:
	var c: Dictionary = ContentDB.ships[id]
	var s := Ship.new()
	s.content_id = id
	s.side = side_value
	s.max_hull = int(c.hull)
	s.hull = s.max_hull
	s.reactor = int(c.reactor)
	s.ward_deck = int(c.get("ward_deck", 1))
	for rd: Dictionary in c.rooms:
		var r := Room.new()
		r.id = rd.id
		r.deck = int(rd.deck)
		r.system = rd.get("system", "")
		r.level = int(rd.get("level", 0))
		var rc: Array = rd.rect
		r.rect = Rect2i(
			int(rc[0]), int(rc[1]), int(rc[2]) - int(rc[0]) + 1, int(rc[3]) - int(rc[1]) + 1
		)
		s.rooms.append(r)
	for wid: String in c.weapons:
		s.weapon_ids.append(wid)
		s.weapon_charge.append(0.0)
		s.weapon_target.append("")
	s._build_graph(c)
	for cd: Dictionary in c.crew:
		var m := Crew.new()
		m.uid = s.next_uid
		s.next_uid += 1
		m.name = cd.name
		m.species = cd.species
		m.room = cd.room
		m.max_hp = float(ContentDB.species[m.species].hp)
		m.hp = m.max_hp
		s.crew.append(m)
	for sys: String in c.get("start_power", {}):
		var r := s.system_room(sys)
		if r:
			r.power = mini(int(c.start_power[sys]), r.level)
			r.wanted_power = r.power
	return s


func _build_graph(c: Dictionary) -> void:
	_room_by_id.clear()
	_neighbors.clear()
	for r in rooms:
		_room_by_id[r.id] = r
		_neighbors[r.id] = []
	for deck in [0, 1]:
		var row: Array[Room] = []
		for r in rooms:
			if r.deck == deck:
				row.append(r)
		row.sort_custom(
			func(a: Room, b: Room) -> bool: return a.rect.position.x < b.rect.position.x
		)
		for i in range(row.size() - 1):
			_neighbors[row[i].id].append([row[i + 1].id, WALK_TIME])
			_neighbors[row[i + 1].id].append([row[i].id, WALK_TIME])
	ladders.assign(c.get("ladders", []))
	for l: Dictionary in ladders:
		_neighbors[l.upper].append([l.lower, LADDER_TIME])
		_neighbors[l.lower].append([l.upper, LADDER_TIME])


func room(id: String) -> Room:
	return _room_by_id.get(id)


func system_room(sys: String) -> Room:
	for r in rooms:
		if r.system == sys:
			return r
	return null


func neighbors(id: String) -> Array:
	return _neighbors.get(id, [])


func is_ladder(a: String, b: String) -> bool:
	for l: Dictionary in ladders:
		if (l.upper == a and l.lower == b) or (l.upper == b and l.lower == a):
			return true
	return false


func ladder_x(a: String, b: String) -> int:
	for l: Dictionary in ladders:
		if (l.upper == a and l.lower == b) or (l.upper == b and l.lower == a):
			return int(l.x)
	return 0


## Breadth-first path. Returns the rooms to walk through, not including start.
func find_path(start: String, goal: String) -> Array[String]:
	var out: Array[String] = []
	if start == goal or not _room_by_id.has(goal):
		return out
	var came := {start: ""}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == goal:
			break
		for n: Array in neighbors(cur):
			if not came.has(n[0]):
				came[n[0]] = cur
				queue.append(n[0])
	if not came.has(goal):
		return out
	var step := goal
	while step != start:
		out.push_front(step)
		step = came[step]
	return out


# ---------------------------------------------------------------- power


func available_power() -> int:
	var ember := system_room("ember")
	var lost := 0
	if ember:
		lost = 2 * (ember.level - ember.effective_level())
	return maxi(0, reactor - lost)


func used_power() -> int:
	var total := 0
	for r in rooms:
		total += r.power
	return total


func power_up(sys: String) -> bool:
	var r := system_room(sys)
	if r == null or not ContentDB.systems[sys].powered:
		return false
	if r.power >= r.effective_level() or used_power() >= available_power():
		return false
	r.power += 1
	_captain_set_power()
	return true


func power_down(sys: String) -> bool:
	var r := system_room(sys)
	if r == null or r.power <= 0:
		return false
	r.power -= 1
	_captain_set_power()
	return true


## A manual power change is the captain's new plan: it also drops any power
## other systems were waiting to get back after repairs, so freed power never
## jumps back into a system the captain has since moved on from.
func _captain_set_power() -> void:
	for r in rooms:
		r.wanted_power = r.power


## Damage and a hurt Ember take power away; once fixed, systems get back what
## the captain last asked for, most important first, as far as the reactor allows.
func enforce_power() -> void:
	for r in rooms:
		r.power = mini(r.power, r.effective_level())
	var over := used_power() - available_power()
	for sys in POWER_SHED_ORDER:
		var r := system_room(sys)
		while over > 0 and r and r.power > 0:
			r.power -= 1
			over -= 1
	for i in range(POWER_SHED_ORDER.size() - 1, -1, -1):
		var r := system_room(POWER_SHED_ORDER[i])
		while (
			r
			and r.power < mini(r.wanted_power, r.effective_level())
			and used_power() < available_power()
		):
			r.power += 1


func system_power(sys: String) -> int:
	var r := system_room(sys)
	return r.power if r else 0


func weapon_powered(i: int) -> bool:
	var budget := system_power("weapons")
	for j in range(i + 1):
		budget -= int(ContentDB.weapons[weapon_ids[j]].power)
	return budget >= 0


# ---------------------------------------------------------------- crew


func alive_crew() -> Array[Crew]:
	var out: Array[Crew] = []
	for c in crew:
		if c.hp > 0.0:
			out.append(c)
	return out


func crew_in(room_id: String, include_moving := false) -> Array[Crew]:
	var out: Array[Crew] = []
	for c in crew:
		if c.hp > 0.0 and c.room == room_id and (include_moving or not c.is_moving()):
			out.append(c)
	return out


func manned(sys: String) -> bool:
	var r := system_room(sys)
	return r != null and not crew_in(r.id).is_empty()


func crew_by_uid(uid: int) -> Crew:
	for c in crew:
		if c.uid == uid:
			return c
	return null


func order_move(uid: int, room_id: String) -> bool:
	var c := crew_by_uid(uid)
	if c == null or c.hp <= 0.0 or room(room_id) == null:
		return false
	# A crew member already walking finishes the step they are on first.
	var from := c.room
	var keep_step := ""
	if c.is_moving() and c.progress > 0.0:
		keep_step = c.path[0]
		from = keep_step
	var p := find_path(from, room_id)
	if keep_step != "":
		p.push_front(keep_step)
	else:
		c.progress = 0.0
	c.path = p
	return true


# ---------------------------------------------------------------- combat stats


func evasion() -> float:
	var helm := system_room("helm")
	if helm == null or helm.power <= 0 or not manned("helm"):
		return 0.0
	var ev := 5.0 * helm.power + 5.0 * system_power("engines")
	if manned("engines"):
		ev += 5.0
	if helm.warmth < COLD:
		ev *= 0.5
	return minf(ev, 45.0)


func max_ward_layers() -> int:
	return system_power("wards") / 2


func is_dead() -> bool:
	return hull <= 0 or alive_crew().is_empty()


# ---------------------------------------------------------------- tick


func tick(dt: float, rng: RandomNumberGenerator, events: Array) -> void:
	if is_dead():
		return
	enforce_power()
	_tick_crew(dt, events)
	_tick_warmth(dt)
	_tick_fire(dt, rng, events)
	_tick_wards(dt)
	_tick_weapons(dt, events)
	quantize()


## Snap every continuous value to a multiple of 1/1024 after each tick.
## Those numbers print and parse back exactly in JSON, so a saved fight
## resumes bit-for-bit instead of drifting by a rounding error.
func quantize() -> void:
	for r in rooms:
		r.warmth = Q.q(r.warmth)
		r.fire = Q.q(r.fire)
		r.damage = Q.q(r.damage)
	for c in crew:
		c.hp = Q.q(c.hp)
		c.progress = Q.q(c.progress)
	for i in weapon_charge.size():
		weapon_charge[i] = Q.q(weapon_charge[i])
	ward_regen = Q.q(ward_regen)


func _work_rate(c: Crew) -> float:
	var r := room(c.room)
	return 0.5 if r.warmth < COLD else 1.0


func _tick_crew(dt: float, events: Array) -> void:
	var mend := system_room("mend")
	for c in crew:
		if c.hp <= 0.0:
			continue
		var spec := c.spec()
		var here := room(c.room)
		# movement
		if c.is_moving():
			var next: String = c.path[0]
			var t := LADDER_TIME if is_ladder(c.room, next) else WALK_TIME
			var speed := float(spec.speed) * (0.6 if here.warmth < COLD else 1.0)
			c.progress += dt * speed / t
			if c.progress >= 1.0:
				c.room = next
				c.path.pop_front()
				c.progress = 0.0
			continue
		# work: fire first, then repairs
		var rate := _work_rate(c)
		if here.fire > 0.0:
			here.fire = maxf(0.0, here.fire - 15.0 * float(spec.firefight) * rate * dt)
		elif here.damage > 0.0:
			here.damage = maxf(0.0, here.damage - 0.25 * float(spec.repair) * rate * dt)
	# harm and healing
	for c in crew:
		if c.hp <= 0.0:
			continue
		var here := room(c.room)
		if here.fire > 0.0:
			c.hp -= 5.0 * dt * here.fire / 100.0
		if here.warmth < FREEZING and not c.spec().cold_proof:
			c.hp -= 2.0 * dt
		if mend and c.room == mend.id and mend.power > 0 and not c.is_moving():
			c.hp = minf(c.max_hp, c.hp + 6.0 * mend.power * dt)
		if c.hp <= 0.0:
			c.hp = 0.0
			c.path.clear()
			events.append({"type": "crew_died", "side": side, "uid": c.uid, "room": c.room})


func _tick_warmth(dt: float) -> void:
	var delta := {}
	for r in rooms:
		var d := -1.2
		if r.system == "ember" and r.level > 0:
			d += 7.0 * float(r.effective_level()) / float(r.level)
		d += 0.3 * r.power
		d += 4.0 * r.fire / 100.0
		delta[r.id] = d * dt
	# Heat spreads sideways through doors and rises through ladders.
	for r in rooms:
		for n: Array in neighbors(r.id):
			var o := room(n[0])
			if is_ladder(r.id, o.id):
				if r.deck < o.deck:
					var up := 0.35 * maxf(0.0, r.warmth - o.warmth) * dt
					delta[r.id] -= up
					delta[o.id] += up
					var down := 0.08 * maxf(0.0, o.warmth - r.warmth) * dt
					delta[o.id] -= down
					delta[r.id] += down
			elif r.rect.position.x < o.rect.position.x:
				var flow := 0.25 * (r.warmth - o.warmth) * dt
				delta[r.id] -= flow
				delta[o.id] += flow
	for r in rooms:
		r.warmth = clampf(r.warmth + delta[r.id], 0.0, 100.0)


func _tick_fire(dt: float, rng: RandomNumberGenerator, events: Array) -> void:
	for r in rooms:
		if r.fire <= 0.0:
			continue
		if crew_in(r.id).is_empty():
			r.fire = minf(100.0, r.fire + 6.0 * dt)
		if r.level > 0:
			r.damage = minf(float(r.level), r.damage + 0.12 * dt * r.fire / 100.0)
		if r.fire > 60.0:
			for n: Array in neighbors(r.id):
				var o := room(n[0])
				if o.fire <= 0.0 and rng.randf() < 0.04 * dt:
					o.fire = 20.0
					events.append({"type": "fire_spread", "side": side, "room": o.id})


func _tick_wards(dt: float) -> void:
	var cap := max_ward_layers()
	if ward_layers > cap:
		ward_layers = cap
	if ward_layers < cap:
		ward_regen += dt * (1.25 if manned("wards") else 1.0)
		if ward_regen >= WARD_REGEN_TIME:
			ward_layers += 1
			ward_regen = 0.0
	else:
		ward_regen = 0.0


func _tick_weapons(dt: float, events: Array) -> void:
	var boost := 1.1 if manned("weapons") else 1.0
	for i in weapon_ids.size():
		var full := float(ContentDB.weapons[weapon_ids[i]].charge)
		if weapon_powered(i):
			var was := weapon_charge[i]
			weapon_charge[i] = minf(full, weapon_charge[i] + dt * boost)
			if was < full and weapon_charge[i] >= full:
				events.append({"type": "weapon_ready", "side": side, "weapon": i})
		else:
			weapon_charge[i] = maxf(0.0, weapon_charge[i] - dt * 2.0)


## Between fights: crew patch systems, put out fires and rest. Hull damage stays.
func recover_after_fight() -> void:
	var survivors: Array[Crew] = []
	for c in crew:
		if c.hp > 0.0:
			c.path.clear()
			c.progress = 0.0
			c.hp = Q.q(minf(c.max_hp, c.hp + (c.max_hp - c.hp) * 0.5))
			survivors.append(c)
	crew = survivors
	for r in rooms:
		r.damage = 0.0
		r.fire = 0.0
		r.warmth = 60.0
	for i in weapon_ids.size():
		weapon_charge[i] = 0.0
		weapon_target[i] = ""
	ward_layers = 0
	ward_regen = 0.0
	enforce_power()


# ---------------------------------------------------------------- refits


## The highest level a system can be refitted to: systems.json lists the
## price of each level from 2 up, so the list's length sets the cap.
static func max_level(sys: String) -> int:
	return (ContentDB.systems.get(sys, {}).get("upgrade_scrap", []) as Array).size() + 1


func can_upgrade(sys: String) -> bool:
	var r := system_room(sys)
	return r != null and r.level < max_level(sys)


## One more level for a system. Who pays, and with what, is the run's business:
## the player's refits and an enemy's Reach boost both come through here.
func upgrade(sys: String) -> bool:
	if not can_upgrade(sys):
		return false
	system_room(sys).level += 1
	return true


## Burns Light's worth into the Ember: one more reactor power, counted so
## the next stoke's price and the cap don't depend on where the power came from.
func stoke() -> void:
	reactor += 1
	stokes += 1


## A deeper Reach's enemy: more hull and reactor, and system levels bought
## through upgrade() like the player's refits. Each level brings the reactor
## power to run it, since enemy captains don't reshuffle power.
func boost(b: Dictionary) -> void:
	max_hull += int(b.get("hull", 0))
	hull += int(b.get("hull", 0))
	reactor += int(b.get("reactor", 0))
	for sys: String in b.get("systems", []):
		if upgrade(sys):
			reactor += 1
			power_up(sys)


func set_ward_deck(deck: int) -> void:
	if deck == ward_deck or deck < 0 or deck > 1:
		return
	ward_deck = deck
	ward_layers = ward_layers / 2  # moving the ward costs half its layers
	ward_regen = 0.0


# ---------------------------------------------------------------- save


func to_dict() -> Dictionary:
	var rd := []
	for r in rooms:
		rd.append(r.to_dict())
	var cd := []
	for c in crew:
		cd.append(c.to_dict())
	return {
		"content_id": content_id,
		"side": side,
		"hull": hull,
		"max_hull": max_hull,
		"reactor": reactor,
		"stokes": stokes,
		"rooms": rd,
		"crew": cd,
		"weapon_charge": Array(weapon_charge),
		"weapon_target": Array(weapon_target),
		"ward_deck": ward_deck,
		"ward_layers": ward_layers,
		"ward_regen": ward_regen,
		"next_uid": next_uid
	}


static func from_dict(d: Dictionary) -> Ship:
	var s := Ship.from_content(d.content_id, int(d.side))
	# Refits change these; saves from before refits keep the hull's own numbers.
	s.max_hull = int(d.get("max_hull", s.max_hull))
	s.reactor = int(d.get("reactor", s.reactor))
	s.stokes = int(d.get("stokes", 0))
	s.hull = int(d.hull)
	for rd: Dictionary in d.rooms:
		var r := s.room(rd.id)
		if r:
			r.load_dict(rd)
	s.crew.clear()
	for cd: Dictionary in d.crew:
		s.crew.append(Crew.from_dict(cd))
	for i in s.weapon_ids.size():
		s.weapon_charge[i] = float(d.weapon_charge[i])
		s.weapon_target[i] = str(d.weapon_target[i])
	s.ward_deck = int(d.ward_deck)
	s.ward_layers = int(d.ward_layers)
	s.ward_regen = float(d.ward_regen)
	s.next_uid = int(d.next_uid)
	return s
