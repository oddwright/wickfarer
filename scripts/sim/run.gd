class_name Run
extends RefCounted
## One run through a Reach: the star chart, Scrap and Light, the Hush closing
## in from behind, and the fights, events and stores at each beacon.
## Like Combat, it never touches the screen; the view reads `state` and calls
## the action methods, which return false when an action isn't allowed.

const STATES: Array[String] = ["chart", "fight", "event", "store", "reach_done", "lost"]

var reach_id: String
var rng: RngStreams
var chart: StarChart
var ship: Ship
var combat: Combat  ## only while state == "fight"
var state: String = "chart"
var at: String  ## current beacon id
var visited: Array[String] = []
var scrap: int = 0
var light: int = 0
var hush: float = 0.0  ## beacons in columns at or below this are swallowed
var jumps: int = 0
var event_id: String = ""
var seen_events: Array[String] = []
var fight_bonus_scrap: int = 0
var messages: Array[String] = []  ## translation keys of what just happened, newest last


static func create(seed_value: int, ship_id := "tallow_wren", reach := "reach_1") -> Run:
	ContentDB.load_all()
	var r := Run.new()
	r.reach_id = reach
	r.rng = RngStreams.new(seed_value)
	r.chart = StarChart.generate(r.reach(), r.rng.stream("map"))
	r.ship = Ship.from_content(ship_id, 0)
	r.at = r.chart.start_id()
	r.visited.append(r.at)
	r.scrap = int(r.reach().start.scrap)
	r.light = int(r.reach().start.light)
	r.hush = float(r.reach().hush_start)
	return r


func reach() -> Dictionary:
	return ContentDB.reaches[reach_id]


func here() -> Dictionary:
	return chart.node(at)


# ---------------------------------------------------------------- chart


func jump_targets() -> Array[String]:
	var out: Array[String] = []
	if state != "chart":
		return out
	for id: String in here().links:
		out.append(id)
	return out


func jump(target: String) -> bool:
	if not target in jump_targets():
		return false
	messages.clear()
	var cost := int(reach().jump_light)
	if light >= cost:
		light -= cost
	else:
		ship.hull = maxi(0, ship.hull - int(reach().dark_jump_hull))
		messages.append("UI_DARK_JUMP")
	jumps += 1
	hush = Q.q(hush + float(reach().hush_per_jump) + float(reach().hush_per_light) * light)
	at = target
	if not visited.has(at):
		visited.append(at)
	if float(here().col) <= hush:
		ship.hull = maxi(0, ship.hull - int(reach().hush_hull))
		messages.append("UI_HUSH_HIT")
	if ship.hull <= 0:
		state = "lost"
		return true
	_arrive()
	return true


func _arrive() -> void:
	match str(here().kind):
		"fight":
			var pool: Array = reach().enemies
			var enemy: String = pool[rng.stream("map").randi_range(0, pool.size() - 1)]
			_start_fight(enemy)
		"event":
			event_id = _pick_event()
			state = "event" if event_id != "" else "chart"
		"store":
			state = "store"
		"gate":
			state = "reach_done"
		_:
			state = "chart"


func is_swallowed(id: String) -> bool:
	return float(chart.node(id).col) <= hush


# ---------------------------------------------------------------- fights


func _start_fight(enemy: String) -> void:
	combat = Combat.from_ship(rng.stream("combat").randi(), ship, enemy)
	state = "fight"


## Call once the combat has ended (combat.state is won or lost).
func finish_fight() -> bool:
	if state != "fight" or combat == null or combat.state == "fighting":
		return false
	ship = combat.player()
	if combat.state == "lost":
		state = "lost"
		combat = null
		return true
	var loot := rng.stream("loot")
	var reward: Dictionary = reach().fight_reward
	scrap += loot.randi_range(int(reward.scrap[0]), int(reward.scrap[1])) + fight_bonus_scrap
	light += loot.randi_range(int(reward.light[0]), int(reward.light[1]))
	fight_bonus_scrap = 0
	ship.recover_after_fight()
	combat = null
	state = "chart"
	return true


# ---------------------------------------------------------------- events


func _pick_event() -> String:
	var pool: Array[String] = []
	for eid: String in ContentDB.events:
		if seen_events.has(eid):
			continue
		for k in int(ContentDB.events[eid].get("weight", 10)):
			pool.append(eid)
	if pool.is_empty():
		return ""
	var picked := pool[rng.stream("events").randi_range(0, pool.size() - 1)]
	seen_events.append(picked)
	return picked


func event() -> Dictionary:
	return ContentDB.events.get(event_id, {})


func can_choose(i: int) -> bool:
	var choices: Array = event().get("choices", [])
	if state != "event" or i < 0 or i >= choices.size():
		return false
	var req: Dictionary = choices[i].get("requires", {})
	if scrap < int(req.get("scrap", 0)) or light < int(req.get("light", 0)):
		return false
	if req.has("species"):
		var found := false
		for c in ship.alive_crew():
			if c.species == req.species:
				found = true
		if not found:
			return false
	return true


func choose(i: int) -> bool:
	if not can_choose(i):
		return false
	var outcomes: Array = event().choices[i].outcomes
	var total := 0
	for o: Dictionary in outcomes:
		total += int(o.weight)
	var roll := rng.stream("events").randi_range(1, total)
	var picked: Dictionary = outcomes[0]
	for o: Dictionary in outcomes:
		roll -= int(o.weight)
		if roll <= 0:
			picked = o
			break
	messages.clear()
	messages.append(str(picked.text))
	event_id = ""
	state = "chart"
	_apply(picked.get("effects", {}))
	return true


func _apply(fx: Dictionary) -> void:
	scrap = maxi(0, scrap + int(fx.get("scrap", 0)))
	light = maxi(0, light + int(fx.get("light", 0)))
	ship.hull = clampi(ship.hull + int(fx.get("hull", 0)), 0, ship.max_hull)
	hush = Q.q(hush + float(fx.get("hush", 0.0)))
	var heal := float(fx.get("crew_hp", 0.0))
	if heal != 0.0:
		for c in ship.alive_crew():
			# Events can hurt crew but never kill them outright.
			c.hp = Q.q(clampf(c.hp + heal, 1.0, c.max_hp))
	if ship.hull <= 0:
		state = "lost"
		return
	if fx.has("fight"):
		fight_bonus_scrap = int(fx.get("fight_bonus_scrap", 0))
		_start_fight(str(fx.fight))


# ---------------------------------------------------------------- store


func buy(item: String) -> bool:
	if state != "store":
		return false
	var prices: Dictionary = reach().store
	match item:
		"repair":
			var price := int(prices.repair_scrap)
			if scrap < price or ship.hull >= ship.max_hull:
				return false
			scrap -= price
			ship.hull += 1
			return true
		"light":
			var price := int(prices.light_scrap)
			if scrap < price:
				return false
			scrap -= price
			light += 1
			return true
	return false


func leave_store() -> bool:
	if state != "store":
		return false
	state = "chart"
	return true


# ---------------------------------------------------------------- save


func to_dict() -> Dictionary:
	return {
		"reach": reach_id,
		"rng": rng.to_dict(),
		"chart": chart.to_dict(),
		"ship": ship.to_dict(),
		"combat": combat.to_dict() if combat else {},
		"state": state,
		"at": at,
		"visited": Array(visited),
		"scrap": scrap,
		"light": light,
		"hush": hush,
		"jumps": jumps,
		"event": event_id,
		"seen_events": Array(seen_events),
		"fight_bonus_scrap": fight_bonus_scrap,
		"messages": Array(messages),
	}


static func from_dict(d: Dictionary) -> Run:
	ContentDB.load_all()
	var r := Run.new()
	r.reach_id = str(d.reach)
	r.rng = RngStreams.from_dict(d.rng)
	r.chart = StarChart.from_dict(d.chart)
	r.state = str(d.state)
	if r.state == "fight" and not (d.combat as Dictionary).is_empty():
		r.combat = Combat.from_dict(d.combat)
		r.ship = r.combat.player()  # one ship object, shared with the fight
	else:
		r.ship = Ship.from_dict(d.ship)
	r.at = str(d.at)
	for v in d.visited:
		r.visited.append(str(v))
	r.scrap = int(d.scrap)
	r.light = int(d.light)
	r.hush = float(d.hush)
	r.jumps = int(d.jumps)
	r.event_id = str(d.event)
	for e in d.seen_events:
		r.seen_events.append(str(e))
	r.fight_bonus_scrap = int(d.fight_bonus_scrap)
	for l in d.get("messages", []):
		r.messages.append(str(l))
	return r
