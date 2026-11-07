class_name Ship
extends RefCounted
## One ship's state and rules. The player and every enemy run this same code.

const WALK_TIME := 1.0  ## seconds to cross into a neighbouring room
const LADDER_TIME := 1.6
const COLD := 25.0  ## below this, crew work at half speed
const FREEZING := 15.0  ## below this, crew lose health
const POWER_SHED_ORDER: Array[String] = ["mend", "engines", "helm", "weapons", "wards"]
const WARD_REGEN_TIME := 2.5
const GUN_BOOST := 1.1  ## weapons charge this much faster with someone at the post
const WARD_BOOST := 1.25
const STOKE_BOOST := 0.1  ## extra Ember heat with a stoker, before skill
const RENT_DRAIN := 12.0  ## warmth a second an open rent lets out to the void
const RENT_SEAL := 12.0  ## how much of a rent a normal hand seals a second
const RENT_HULL := 1  ## hull a sealed rent gives back: the crew plate the hole
const RENT_SNUFF := 10.0  ## fire a second the void starves out of a rented room

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
var modules: Array[String] = []  ## module ids in hull slots (see Gear)
var module_slots: int = Gear.DEFAULT_MODULE_SLOTS
var weapon_slots: int = Gear.MIN_WEAPON_SLOTS
var mods: Dictionary = {}  ## the fitted modules' summed effects, kept by Gear
var flare_time: float = 0.0  ## seconds left of an Ember flare; 0 when not flaring
var flare_cool: float = 0.0  ## seconds until the Ember can flare again

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
	s.module_slots = int(c.get("module_slots", Gear.DEFAULT_MODULE_SLOTS))
	s.weapon_slots = maxi(int(c.get("weapon_slots", 0)), (c.weapons as Array).size())
	s.weapon_slots = maxi(s.weapon_slots, Gear.MIN_WEAPON_SLOTS)
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
		m.post = str(cd.get("post", cd.room if s.room(cd.room).system != "" else ""))
		var start: Dictionary = cd.get("skills", {})
		for k: String in start:
			if int(start[k]) > 0:
				m.xp[k] = Skills.xp_for_rank(int(start[k]))
		s.crew.append(m)
	for mid: String in c.get("modules", []):
		Gear.fit(s, mid)
	s.hull = s.max_hull
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
	return maxi(0, reactor + int(mod("reactor")) - int(mod("power")) - lost)


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


## Makes a room a crew member's post (their role), or clears it with "".
func set_post(uid: int, room_id: String) -> bool:
	var c := crew_by_uid(uid)
	if c == null or c.hp <= 0.0 or (room_id != "" and room(room_id) == null):
		return false
	c.post = room_id
	return true


## Sends everyone who has a post back to it.
func muster() -> bool:
	var sent := false
	for c in alive_crew():
		if c.post == "" or (c.room == c.post and not c.is_moving()):
			continue
		if c.is_moving() and c.path.back() == c.post:
			continue
		sent = order_move(c.uid, c.post) or sent
	return sent


## The translation key for a crew member's role, from their post.
func role_of(c: Crew) -> String:
	var r := room(c.post)
	if r == null or r.system == "":
		return Skills.ROLE_NONE
	return str(ContentDB.systems[r.system].get("role", Skills.ROLE_NONE))


## The best rank at a station's skill among the crew working there, or -1 if
## nobody is. Only the best hand counts, so stacking a room doesn't stack bonuses.
func station_rank(sys: String) -> int:
	var r := system_room(sys)
	if r == null:
		return -1
	var skill := Skills.for_station(sys)
	var best := -1
	for c in crew_in(r.id):
		best = maxi(best, c.rank(skill))
	return best


## The bonus a station gets from whoever works it: 0 when nobody does.
func station_bonus(sys: String, base: float) -> float:
	var rank := station_rank(sys)
	if rank < 0:
		return 0.0
	return base + Skills.per_rank(Skills.for_station(sys)) * rank


# ---------------------------------------------------------------- combat stats


func evasion() -> float:
	var helm := system_room("helm")
	if helm == null or helm.power <= 0 or not manned("helm"):
		return 0.0
	var ev := 5.0 * helm.power + 5.0 * system_power("engines")
	ev += station_bonus("helm", 0.0) + station_bonus("engines", 5.0)
	ev = maxf(0.0, ev + mod("evasion") - mod("helm"))
	if helm.warmth < COLD:
		ev *= 0.5
	return minf(ev, 45.0)


func max_ward_layers() -> int:
	return system_power("wards") / 2


func is_dead() -> bool:
	return hull <= 0 or alive_crew().is_empty()


## One summed module effect (Gear.GAINS and Gear.COSTS), 0 when nothing gives it.
func mod(effect: String) -> float:
	return float(mods.get(effect, 0.0))


# ---------------------------------------------------------------- tick


func tick(dt: float, rng: RandomNumberGenerator, events: Array) -> void:
	if is_dead():
		return
	enforce_power()
	_tick_crew(dt, events)
	_tick_learning(dt, events)
	_tick_warmth(dt)
	_tick_fire(dt, rng, events)
	_tick_wards(dt)
	_tick_weapons(dt, events)
	_tick_flare(dt, events)
	quantize()


## Snap every continuous value to a multiple of 1/1024 after each tick.
## Those numbers print and parse back exactly in JSON, so a saved fight
## resumes bit-for-bit instead of drifting by a rounding error.
func quantize() -> void:
	for r in rooms:
		r.warmth = Q.q(r.warmth)
		r.fire = Q.q(r.fire)
		r.rent = Q.q(r.rent)
		r.damage = Q.q(r.damage)
	for c in crew:
		c.hp = Q.q(c.hp)
		c.progress = Q.q(c.progress)
		for k: String in c.xp:
			c.xp[k] = Q.q(c.xp[k])
		for k: String in c.fight_xp:
			c.fight_xp[k] = Q.q(c.fight_xp[k])
	for i in weapon_charge.size():
		weapon_charge[i] = Q.q(weapon_charge[i])
	ward_regen = Q.q(ward_regen)
	flare_time = Q.q(flare_time)
	flare_cool = Q.q(flare_cool)


func _work_rate(c: Crew) -> float:
	var r := room(c.room)
	var skill := 1.0 + Skills.per_rank("patch") * c.rank("patch")
	return skill * (0.5 if r.warmth < COLD else 1.0)


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
			speed *= 1.0 + mod("crew_speed")
			c.progress += dt * speed / t
			if c.progress >= 1.0:
				c.room = next
				c.path.pop_front()
				c.progress = 0.0
			continue
		# work: fire first, then rents, then repairs
		var rate := _work_rate(c)
		if here.fire > 0.0:
			var put_out := minf(here.fire, 15.0 * float(spec.firefight) * rate * dt)
			here.fire -= put_out
			_practice(c, "patch", put_out * Skills.num("patch_xp_per_fire"), events)
		elif here.rent > 0.0:
			_seal(c, here, rate * dt, events)
		elif here.damage > 0.0:
			var fixed := minf(here.damage, 0.25 * float(spec.repair) * rate * dt)
			here.damage -= fixed
			_practice(c, "patch", fixed * Skills.num("patch_xp_per_damage"), events)
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
			c.hp = minf(c.max_hp, c.hp + 6.0 * mend.power * (1.0 + mod("mend")) * dt)
		if c.hp <= 0.0:
			c.hp = 0.0
			c.path.clear()
			events.append({"type": "crew_died", "side": side, "uid": c.uid, "room": c.room})


## Sealing works like repairs (a good repairer seals faster). Plating over the
## hole gives a hull point back: the only way to mend the hull mid-fight, and
## it costs crew time in the coldest room on the ship.
func _seal(c: Crew, here: Room, work: float, events: Array) -> void:
	var sealed := minf(here.rent, RENT_SEAL * float(c.spec().repair) * work)
	here.rent -= sealed
	_practice(c, "patch", sealed * Skills.num("patch_xp_per_rent"), events)
	if here.rent <= 0.0:
		here.rent = 0.0
		hull = mini(max_hull, hull + RENT_HULL)
		events.append({"type": "rent_sealed", "side": side, "room": here.id})


## Crew at a working station practise its skill.
func _tick_learning(dt: float, events: Array) -> void:
	for c in crew:
		if c.hp <= 0.0 or c.is_moving():
			continue
		var here := room(c.room)
		var skill := Skills.for_station(here.system)
		if skill != "" and _station_working(here):
			_practice(c, skill, dt, events)


func _station_working(r: Room) -> bool:
	return r.effective_level() > 0 if r.system == "ember" else r.power > 0


## Adds practice. Crew only learn somewhere warm; a better hand in the same
## room doubles it; and each skill can only grow so much a fight, so dragging
## a fight out never pays. Practice is banked after the fight (see
## recover_after_fight), so ranks never change mid-fight: a fresh fight is
## balanced the same however long it runs, and enemy crew never grow.
func _practice(c: Crew, skill: String, amount: float, events: Array) -> void:
	var here := room(c.room)
	if amount <= 0.0 or here.warmth < Skills.num("learn_warmth"):
		return
	var earned := c.earned_rank(skill)
	if earned >= Skills.MAX_RANK:
		return
	for o in crew_in(here.id):
		if o != c and o.rank(skill) > c.rank(skill):
			amount *= Skills.num("mentor")
			break
	amount *= c.learn_rate(skill)
	var room_left := Skills.num("fight_cap") - c.fight_practice(skill)
	amount = minf(amount, room_left)
	if amount <= 0.0:
		return
	c.fight_xp[skill] = c.fight_practice(skill) + amount
	if c.earned_rank(skill) > earned:
		events.append(
			{
				"type": "skill_up",
				"side": side,
				"uid": c.uid,
				"room": c.room,
				"skill": skill,
				"rank": c.earned_rank(skill)
			}
		)


## Crew who would rank up once this fight's practice is banked: {uid, skill, rank}.
func promotions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in alive_crew():
		for skill: String in c.fight_xp:
			if c.earned_rank(skill) > c.rank(skill):
				out.append({"uid": c.uid, "skill": skill, "rank": c.earned_rank(skill)})
	return out


func _tick_warmth(dt: float) -> void:
	var delta := {}
	var fitted := mod("warmth") - mod("heat")
	for r in rooms:
		var d := -1.2 + fitted
		if r.system == "ember" and r.level > 0:
			var stoked := 1.0 + station_bonus("ember", STOKE_BOOST)
			d += 7.0 * stoked * float(r.effective_level()) / float(r.level)
		d += 0.3 * r.power
		d += 4.0 * r.fire / 100.0
		d -= RENT_DRAIN * r.rent / 100.0
		if flare_time > 0.0:
			d += float(flare_data().warmth)
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
		if r.rent > 0.0:  # the void takes the air: fire dies down instead of growing
			r.fire = maxf(0.0, r.fire - RENT_SNUFF * dt * r.rent / 100.0)
		elif crew_in(r.id).is_empty():
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
		var rate := maxf(1.0, station_bonus("wards", WARD_BOOST)) * (1.0 + mod("ward_regen"))
		ward_regen += dt * rate
		if ward_regen >= WARD_REGEN_TIME:
			ward_layers += 1
			ward_regen = 0.0
	else:
		ward_regen = 0.0


func _tick_weapons(dt: float, events: Array) -> void:
	var boost := maxf(1.0, station_bonus("weapons", GUN_BOOST)) * (1.0 + mod("weapon_charge"))
	if flare_time > 0.0:
		boost *= 1.0 + float(flare_data().charge)
	for i in weapon_ids.size():
		var full := float(ContentDB.weapons[weapon_ids[i]].charge)
		if weapon_powered(i):
			var was := weapon_charge[i]
			weapon_charge[i] = minf(full, weapon_charge[i] + dt * boost)
			if was < full and weapon_charge[i] >= full:
				events.append({"type": "weapon_ready", "side": side, "weapon": i})
		else:
			weapon_charge[i] = maxf(0.0, weapon_charge[i] - dt * 2.0)


# ---------------------------------------------------------------- flare


## The Ember's flare numbers from systems.json.
static func flare_data() -> Dictionary:
	return ContentDB.systems.ember.flare


## A flare needs a working Ember and a rested one.
func can_flare() -> bool:
	var ember := system_room("ember")
	return ember != null and ember.effective_level() > 0 and flare_time <= 0.0 and flare_cool <= 0.0


## Pours the Ember out: guns charge faster and every room warms for a few
## seconds, then the Ember cracks and costs power until someone patches it.
func flare() -> bool:
	if not can_flare():
		return false
	var f := flare_data()
	flare_time = float(f.seconds)
	flare_cool = float(f.cooldown)
	return true


func _tick_flare(dt: float, events: Array) -> void:
	flare_cool = maxf(0.0, flare_cool - dt)
	if flare_time <= 0.0:
		return
	var ember := system_room("ember")
	# Orders land between ticks, where events are cleared: say it on the first tick.
	if flare_time >= float(flare_data().seconds):
		events.append({"type": "flare", "side": side, "room": ember.id})
	flare_time = maxf(0.0, flare_time - dt)
	if flare_time > 0.0:
		return
	ember.damage = minf(float(ember.level), ember.damage + float(flare_data().crack))
	events.append({"type": "flare_spent", "side": side, "room": ember.id})


## Between fights: crew bank what they practised, patch systems, put out
## fires, rest and go back to their posts. Hull damage stays.
func recover_after_fight() -> void:
	var survivors: Array[Crew] = []
	for c in crew:
		if c.hp > 0.0:
			c.path.clear()
			c.progress = 0.0
			for skill: String in c.fight_xp:
				c.xp[skill] = Q.q(c.skill_xp(skill) + float(c.fight_xp[skill]))
			c.fight_xp.clear()
			if room(c.post):
				c.room = c.post
			c.hp = Q.q(minf(c.max_hp, c.hp + (c.max_hp - c.hp) * 0.5))
			survivors.append(c)
	crew = survivors
	for r in rooms:
		r.damage = 0.0
		r.fire = 0.0
		r.rent = 0.0
		r.warmth = 60.0
	for i in weapon_ids.size():
		weapon_charge[i] = 0.0
		weapon_target[i] = ""
	ward_layers = 0
	ward_regen = 0.0
	flare_time = 0.0
	flare_cool = 0.0
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
		"weapons": Array(weapon_ids),
		"modules": Array(modules),
		"weapon_charge": Array(weapon_charge),
		"weapon_target": Array(weapon_target),
		"ward_deck": ward_deck,
		"ward_layers": ward_layers,
		"ward_regen": ward_regen,
		"flare_time": flare_time,
		"flare_cool": flare_cool,
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
		var c := Crew.from_dict(cd)
		if not cd.has("post"):  # saved before posts: posted where they stand, if a station
			c.post = c.room if s.room(c.room) and s.room(c.room).system != "" else ""
		s.crew.append(c)
	_load_gear(s, d)
	var charge: Array = d.weapon_charge
	var aim: Array = d.weapon_target
	var same := charge.size() == s.weapon_ids.size() and aim.size() == charge.size()
	for i in s.weapon_ids.size():
		s.weapon_charge[i] = float(charge[i]) if same else 0.0
		s.weapon_target[i] = str(aim[i]) if same else ""
	s.ward_deck = int(d.ward_deck)
	s.ward_layers = int(d.ward_layers)
	s.ward_regen = float(d.ward_regen)
	s.flare_time = float(d.get("flare_time", 0.0))
	s.flare_cool = float(d.get("flare_cool", 0.0))
	s.next_uid = int(d.next_uid)
	return s


## Guns and modules as saved; a save from before stores had the hull's own.
## Unknown ids (cut in an update) are dropped rather than breaking the save;
## from_dict drops the saved charge if the gun list no longer matches it.
static func _load_gear(s: Ship, d: Dictionary) -> void:
	if d.has("weapons"):
		var kept: Array[String] = []
		for w: Variant in d.weapons:
			if ContentDB.weapons.has(str(w)):
				kept.append(str(w))
		if not kept.is_empty():
			s.weapon_ids = kept
	var n := s.weapon_ids.size()
	s.weapon_charge.resize(n)
	s.weapon_target.resize(n)
	if d.has("modules"):
		s.modules.clear()
		for m: Variant in d.modules:
			if ContentDB.modules.has(str(m)):
				s.modules.append(str(m))
	s.weapon_slots = maxi(s.weapon_slots, n)
	s.module_slots = maxi(s.module_slots, s.modules.size())
	s.mods = Gear.sum(s.modules)
