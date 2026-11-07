class_name Combat
extends RefCounted
## A fight between two ships. Runs at a fixed 20 ticks a second and never
## touches the screen. The view reads `events` after each tick.

const TICK := 0.05
const FLIGHT_TIME := 1.0
const SHOT_SPACING := 0.2
const AI_THINK := 0.5
const RESIGHT_COST := 2.0
const HIT_CHILL := 15.0  ## warmth any hit knocks out of its room; Chill guns set their own
const CHILL_SPREAD := 0.5  ## share of a Chill hit's cold that reaches each neighbouring room
## A fight's one rule twist, set by the enemy hull's "rule" (the Reach Wardens).
## Each applies to both ships alike:
## tether: neither ship can evade. tide: every TIDE_EVERY seconds both wards
## swap decks. hymn: every room on both ships cools HYMN_CHILL a second faster.
const RULES: Array[String] = ["", "tether", "tide", "hymn"]
const TIDE_EVERY := 10.0
const HYMN_CHILL := 1.0

var ships: Array[Ship] = []
var projectiles: Array[Dictionary] = []
var rng: RngStreams
var tick_count: int = 0
var state: String = "fighting"  ## fighting | won | lost
var events: Array = []
var ai_timer: float = 0.0
var ai: CombatAI
var siege: Siege  ## the Kindling's waves and progress; null in an ordinary fight
## Light each side lost to hits from "light_drain" weapons; the run pays it after the fight.
var light_drained: Array[int] = [0, 0]
## The enemy hull's rule, read once when the fight is built or loaded (see rule()).
var _rule := ""


static func create(
	seed_value: int, player_ship := "tallow_wren", enemy_ship := "ashmarket_cutter"
) -> Combat:
	ContentDB.load_all()
	return from_ship(seed_value, Ship.from_content(player_ship, 0), enemy_ship)


## A fight inside a run: the player's ship carries over between fights.
static func from_ship(seed_value: int, player_ship: Ship, enemy_ship: String) -> Combat:
	ContentDB.load_all()
	var c := Combat.new()
	c.rng = RngStreams.new(seed_value)
	player_ship.side = 0
	c.ships.append(player_ship)
	c.ships.append(Ship.from_content(enemy_ship, 1))
	c.ai = CombatAI.new()
	c._apply_rule()
	return c


## The fight's rule twist (see RULES): "" in an ordinary fight.
func rule() -> String:
	return _rule


func _apply_rule() -> void:
	_rule = str(ContentDB.ships[enemy().content_id].get("rule", ""))


## Extra warmth every room on both ships loses a second, under the hymn.
func rule_chill() -> float:
	return HYMN_CHILL if _rule == "hymn" else 0.0


static func _tide_ticks() -> int:
	return roundi(TIDE_EVERY / TICK)


## A ship's chance to dodge a shot, in percent, after the fight's rule.
func evasion(side: int) -> float:
	return 0.0 if _rule == "tether" else ships[side].evasion()


## Seconds until the tide next turns, or -1 in a fight without one.
func tide_eta() -> float:
	if rule() != "tide":
		return -1.0
	return float(_tide_ticks() - tick_count % _tide_ticks()) * TICK


func player() -> Ship:
	return ships[0]


func enemy() -> Ship:
	return ships[1]


func time() -> float:
	return tick_count * TICK


## Orders from the player (or a test, or the AI). Returns true if accepted.
func apply(cmd: Dictionary, side := 0) -> bool:
	var s := ships[side]
	match cmd.get("type", ""):
		"power_up":
			return s.power_up(cmd.system)
		"power_down":
			return s.power_down(cmd.system)
		"aim":
			return _aim(s, side, cmd)
		"move":
			return s.order_move(int(cmd.crew), cmd.room)
		"post":
			return s.set_post(int(cmd.crew), str(cmd.get("room", "")))
		"muster":
			return s.muster()
		"ward_deck":
			s.set_ward_deck(int(cmd.deck))
			return true
		"kindle":
			return siege != null and siege.kindle(s)
		"flare":
			return EmberFlare.light(s)
	return false


func _aim(s: Ship, side: int, cmd: Dictionary) -> bool:
	var i := int(cmd.weapon)
	if i < 0 or i >= s.weapon_ids.size():
		return false
	var target_room: String = cmd.get("room", "")
	if target_room != "" and ships[1 - side].room(target_room) == null:
		return false
	# Re-sighting a gun that was already aimed elsewhere costs 2 s of charge,
	# so chasing the open deck every few seconds isn't free.
	if s.weapon_target[i] != "" and target_room != "" and target_room != s.weapon_target[i]:
		s.weapon_charge[i] = maxf(0.0, s.weapon_charge[i] - RESIGHT_COST)
	s.weapon_target[i] = target_room
	return true


func tick() -> void:
	events.clear()
	if state != "fighting":
		return
	var combat_rng := rng.stream("combat")
	for s in ships:
		s.tick(TICK, combat_rng, events, rule_chill())
	ai_timer = Q.q(ai_timer + TICK)
	if ai_timer >= AI_THINK:
		ai_timer = Q.q(ai_timer - AI_THINK)
		ai.think(self, 1)
	if siege:
		siege.tick(self, TICK, events)
	_fire_weapons()
	_move_projectiles()
	tick_count += 1
	_tick_tide()
	for s in ships:
		s.quantize()  # hits after the ship ticks change values too
	# If both ships die on the same tick the player loses: a dead ship can't
	# carry on through the run.
	if player().is_dead():
		state = "lost"
		events.append({"type": "lost"})
	elif siege.done if siege else enemy().is_dead():
		state = "won"
		events.append({"type": "won"})


func _tick_tide() -> void:
	if _rule == "tide" and tick_count % _tide_ticks() == 0:
		for s in ships:
			s.turn_tide()
		events.append({"type": "tide"})


func _fire_weapons() -> void:
	for side in 2:
		var s := ships[side]
		if s.is_dead():
			continue
		for i in s.weapon_ids.size():
			var w: Dictionary = ContentDB.weapons[s.weapon_ids[i]]
			if s.weapon_target[i] == "" or not s.weapon_powered(i):
				continue
			if s.weapon_charge[i] < float(w.charge):
				continue
			s.weapon_charge[i] = 0.0
			for k in int(w.shots):
				var t := Q.q(FLIGHT_TIME + SHOT_SPACING * k)
				projectiles.append(
					{
						"owner": side,
						"weapon": s.weapon_ids[i],
						"slot": i,
						"target": s.weapon_target[i],
						"t": t,
						"total": t
					}
				)
			events.append({"type": "fire", "side": side, "weapon": i})


func _move_projectiles() -> void:
	var landed: Array[Dictionary] = []
	for p in projectiles:
		p.t = Q.q(float(p.t) - TICK)
		if p.t <= 0.0:
			landed.append(p)
	for p in landed:
		projectiles.erase(p)
		_resolve(p)


func _resolve(p: Dictionary) -> void:
	var target := ships[1 - int(p.owner)]
	var w: Dictionary = ContentDB.weapons[p.weapon]
	if siege and target == enemy():  # the Hush maw: its knots, not a hull
		siege.strike(ships[int(p.owner)], p.target, int(w.hull_damage), events)
		return
	var r := target.room(p.target)
	var where := {"side": target.side, "room": r.id}
	var pierces: bool = w.get("pierces_ward", false)
	if target.ward_layers > 0 and r.deck == target.ward_deck and not pierces:
		if w.strips_ward:
			target.ward_layers -= 1
			target.ward_regen = 0.0
			events.append(where.merged({"type": "ward_hit"}))
		else:
			events.append(where.merged({"type": "ward_block"}))
		return
	var combat_rng := rng.stream("combat")
	if combat_rng.randf() * 100.0 < evasion(target.side):
		events.append(where.merged({"type": "miss"}))
		return
	target.hull = maxi(0, target.hull - int(w.hull_damage))
	var drain := int(w.get("light_drain", 0))
	if drain > 0:
		light_drained[target.side] += drain
		events.append(where.merged({"type": "light_drain", "amount": drain}))
	if r.level > 0:
		r.damage = minf(float(r.level), r.damage + float(w.system_damage))
	_chill(target, r, float(w.get("chill", HIT_CHILL)), w.has("chill"))
	for c in target.crew_in(r.id, true):
		c.hp = maxf(0.0, c.hp - float(w.crew_damage))
	if combat_rng.randf() < float(w.fire_chance):
		r.fire = maxf(r.fire, 30.0)
		events.append(where.merged({"type": "fire_start"}))
	_tear(r, w, where)
	events.append(where.merged({"type": "hit", "damage": int(w.hull_damage)}))


## A hit from a gun with a rent chance can tear the room open. It rolls on its
## own stream, so adding rents left every other combat roll where it was.
func _tear(r: Room, w: Dictionary, where: Dictionary) -> void:
	var chance := float(w.get("rent_chance", 0.0))
	if chance <= 0.0:  # validation keeps rent chances to guns that hurt the hull
		return
	if rng.stream("rents").randf() < chance:
		var fresh := r.rent <= 0.0
		r.rent = 100.0
		if fresh:
			events.append(where.merged({"type": "rent_open"}))


## Every hit lets some cold in; a Chill gun lets in far more, and half of it
## reaches the rooms next door. A warm-fitted ship shrugs some of it off.
func _chill(target: Ship, r: Room, cold: float, spreads: bool) -> void:
	cold *= 1.0 - target.mod("chill_resist")
	r.warmth = maxf(0.0, r.warmth - cold)
	if not spreads:
		return
	for n: Array in target.neighbors(r.id):
		var o := target.room(n[0])
		o.warmth = maxf(0.0, o.warmth - cold * CHILL_SPREAD)


# ---------------------------------------------------------------- save


func to_dict() -> Dictionary:
	return {
		"ships": [ships[0].to_dict(), ships[1].to_dict()],
		"projectiles": projectiles.duplicate(true),
		"rng": rng.to_dict(),
		"tick": tick_count,
		"state": state,
		"ai_timer": ai_timer,
		"ai_ward_timer": ai.ward_timer,
		"light_drained": Array(light_drained),
		"siege": siege.to_dict() if siege else {}
	}


static func from_dict(d: Dictionary) -> Combat:
	ContentDB.load_all()
	var c := Combat.new()
	c.rng = RngStreams.from_dict(d.rng)
	for sd: Dictionary in d.ships:
		c.ships.append(Ship.from_dict(sd))
	for p: Dictionary in d.get("projectiles", []):
		c.projectiles.append(
			{
				"owner": int(p.owner),
				"weapon": str(p.weapon),
				"slot": int(p.slot),
				"target": str(p.target),
				"t": float(p.t),
				"total": float(p.total)
			}
		)
	c.tick_count = int(d.tick)
	c.state = str(d.state)
	c.ai_timer = float(d.get("ai_timer", 0.0))
	c.ai = CombatAI.new()
	c.ai.ward_timer = float(d.get("ai_ward_timer", 0.0))
	var drained: Array = d.get("light_drained", [0, 0])
	for side in 2:
		c.light_drained[side] = int(drained[side]) if side < drained.size() else 0
	c._apply_rule()
	var sd: Dictionary = d.get("siege", {})
	if not sd.is_empty():
		c.siege = Siege.from_dict(sd)
	return c
