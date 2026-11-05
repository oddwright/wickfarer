class_name Run
extends RefCounted
## One run through a Reach: the star chart, Scrap and Light, the Hush closing
## in from behind, and the fights, events and stores at each beacon.
## Like Combat, it never touches the screen; the view reads `state` and calls
## the action methods, which return false when an action isn't allowed.

const STORE_ITEMS: Array[String] = ["repair", "light"]  ## each needs a "<item>_scrap" price
const REACH_ENEMY := "reach"  ## an event "fight" that picks from the Reach's enemy pool

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
var messages: Array[String] = []  ## translation keys of what the last jump did, newest last
var outcome: String = ""  ## an event result the player hasn't read yet (a translation key)


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


## Every beacon but the Gate opens with a story: an event whose "beacon" is
## this beacon's kind. Its choices lead into, or around, the fight or store.
func _arrive() -> void:
	var kind := str(here().kind)
	if kind == "gate":
		state = "reach_done"
		return
	event_id = _pick_event(kind)
	if event_id != "":
		state = "event"
		return
	_skip_story(kind)


## No story for this beacon: fall straight into what's there.
func _skip_story(kind: String) -> void:
	match kind:
		"fight":
			_start_fight(REACH_ENEMY)
		"store":
			state = "store"
		_:
			state = "chart"


func is_swallowed(id: String) -> bool:
	return float(chart.node(id).col) <= hush


# ---------------------------------------------------------------- fights


func _start_fight(enemy: String, enemy_hull := 0) -> void:
	if enemy == REACH_ENEMY:
		var pool: Array = reach().enemies
		enemy = str(pool[rng.stream("encounters").randi_range(0, pool.size() - 1)])
	combat = Combat.from_ship(rng.stream("combat").randi(), ship, enemy)
	var foe := combat.enemy()
	foe.hull = clampi(foe.hull + enemy_hull, 1, foe.max_hull)
	state = "fight"


## Call once the combat has ended (combat.state is won or lost).
func finish_fight() -> bool:
	if state != "fight" or combat == null or combat.state == "fighting":
		return false
	ship = combat.player()
	if combat.state == "lost" or ship.is_dead():
		state = "lost"
		combat = null
		return true
	var loot := rng.stream("loot")
	var reward: Dictionary = reach().fight_reward
	scrap += loot.randi_range(int(reward.scrap[0]), int(reward.scrap[1])) + fight_bonus_scrap
	light += loot.randi_range(int(reward.light[0]), int(reward.light[1]))
	fight_bonus_scrap = 0
	messages.clear()
	ship.recover_after_fight()
	combat = null
	state = "chart"
	return true


# ---------------------------------------------------------------- events


## A story for a beacon of this kind, one the run hasn't seen if it can.
## Plain events are never repeated. The openers for fights, stores and empty
## beacons start a new cycle once all are seen, since the beacon still needs
## one, but never show the same one twice in a row.
func _pick_event(kind: String) -> String:
	var ids: Array[String] = []
	var seen: Array[String] = []
	for eid: String in ContentDB.events:
		if str(ContentDB.events[eid].get("beacon", "event")) == kind:
			(seen if seen_events.has(eid) else ids).append(eid)
	if ids.is_empty() and kind != "event" and not seen.is_empty():
		var last := ""
		for eid in seen_events:
			if seen.has(eid):
				last = eid
		for eid in seen:
			if eid != last or seen.size() == 1:
				seen_events.erase(eid)
				ids.append(eid)
	var weights: Array[int] = []
	for eid in ids:
		weights.append(int(ContentDB.events[eid].get("weight", 10)))
	var i := RngStreams.weighted_pick(weights, rng.stream("events"))
	if i < 0:
		return ""
	seen_events.append(ids[i])
	return ids[i]


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
	var weights: Array[int] = []
	for o: Dictionary in outcomes:
		weights.append(int(o.weight))
	var picked: Dictionary = outcomes[maxi(
		0, RngStreams.weighted_pick(weights, rng.stream("events"))
	)]
	messages.clear()
	outcome = str(picked.text)
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
		_start_fight(str(fx.fight), int(fx.get("enemy_hull", 0)))
	elif fx.get("store", false):
		state = "store"


## The player has read the event's result; the run moves on.
func read_outcome() -> bool:
	if outcome == "":
		return false
	outcome = ""
	return true


# ---------------------------------------------------------------- store


## What this Reach's stores sell, in order. A Reach drops an item by leaving
## out its "<item>_scrap" price.
func store_items() -> Array[String]:
	var out: Array[String] = []
	for item in STORE_ITEMS:
		if price(item) > 0:
			out.append(item)
	return out


## The scrap price of a store item, or -1 if the store doesn't sell it.
func price(item: String) -> int:
	var prices: Dictionary = reach().store
	return int(prices.get(item + "_scrap", -1)) if item in STORE_ITEMS else -1


func can_buy(item: String) -> bool:
	var p := price(item)
	if state != "store" or p < 0 or scrap < p:
		return false
	return not (item == "repair" and ship.hull >= ship.max_hull)


func buy(item: String) -> bool:
	if not can_buy(item):
		return false
	scrap -= price(item)
	match item:
		"repair":
			ship.hull += 1
		"light":
			light += 1
	return true


func leave_store() -> bool:
	if state != "store":
		return false
	messages.clear()
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
		"outcome": outcome,
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
	r.outcome = str(d.get("outcome", ""))
	if r.state == "event" and not ContentDB.events.has(r.event_id):
		# The event was removed or renamed in an update; don't strand the save
		# on it, but keep the fight or store its beacon holds.
		r.event_id = ""
		r._skip_story(str(r.here().kind))
	for e in d.seen_events:
		r.seen_events.append(str(e))
	r.fight_bonus_scrap = int(d.fight_bonus_scrap)
	for l in d.get("messages", []):
		r.messages.append(str(l))
	return r
