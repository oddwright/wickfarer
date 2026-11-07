class_name Run
extends RefCounted
## One run across the Reaches: each Reach's star chart, Scrap and Light, the
## Hush closing in from behind, and the fights, events and stores at each
## beacon. Stores also refit the ship: Scrap buys system levels, and Light
## burned in the Ember buys reactor power. The last Reach's Gate wins the run.
## Like Combat, it never touches the screen; the view reads `state` and calls
## the action methods, which return false when an action isn't allowed.

const STORE_ITEMS: Array[String] = ["repair", "light"]  ## each needs a "<item>_scrap" price
const REACH_ENEMY := "reach"  ## an event "fight" that picks from the Reach's enemy pool
const ENDINGS: Array[String] = ["lost", "won"]  ## states a run never leaves
## Systems the refit page offers, in order; "stoke" (reactor for Light) comes after them.
const REFIT_SYSTEMS: Array[String] = ["weapons", "wards", "helm", "engines", "mend"]
const HOLD_SIZE := 2  ## spare gear the hold carries, besides what is fitted
## Run states that are a store's pages: the price board, the refit, and Market's.
const STORE_PAGES: Array[String] = ["store", "refit", "wares", "modules", "guns"]
## Hush a module's unpaid Light upkeep draws instead, per missing Light.
const UNPAID_UPKEEP_HUSH := 0.35

var reach_id: String
var depth: int = 0  ## Hush Depth: every depth's rule up to this one applies
## Names this run in the profile, so it is counted once. Given by whoever starts
## the run (seeds come from the clock and repeat); "" for runs from older saves.
var run_id: String = ""
var reaches_crossed: int = 0  ## Gates passed this run
var fights_won: int = 0
var scrap_earned: int = 0  ## every scrap gained, before spending; for the end screen and records
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
var standing: Standing  ## each faction's view of the ship
var flags: Array[String] = []  ## story beats this run has reached, set by event outcomes
var store_faction: String = ""  ## whose store the ship is docked at; "" for an independent one
var fight_faction: String = ""  ## whose ship the current fight is against; "" for nobody's
## Profile unlocks open when the run began: they decide which gear can turn up.
var unlocked: Array[String] = []
var hold: Array[Dictionary] = []  ## spare gear, {kind: "module"|"weapon", id}
var stock: Array[Dictionary] = []  ## this store's wares; bought ones leave the list
var selling := false  ## the Modules and Guns pages sell what is tapped
var _mods := {}  ## the depth rules summed for _mods_depth
var _mods_depth := -1  ## the depth _mods was summed for; -1 before the first sum


static func create(
	seed_value: int,
	ship_id := "tallow_wren",
	reach := "reach_1",
	depth_value := 0,
	unlocked_ids: Array[String] = []
) -> Run:
	ContentDB.load_all()
	var r := Run.new()
	r.unlocked = unlocked_ids.duplicate()
	r.reach_id = reach
	r.rng = RngStreams.new(seed_value)
	r.chart = StarChart.generate(r.reach(), r.rng.stream("map"))
	r.ship = Ship.from_content(ship_id, 0)
	r.at = r.chart.start_id()
	r.visited.append(r.at)
	r.depth = clampi(depth_value, 0, depth_count())
	r.scrap = maxi(0, int(r.reach().start.scrap) + int(r.mod("start_scrap")))
	r.light = maxi(0, int(r.reach().start.light) + int(r.mod("start_light")))
	r.hush = float(r.reach().hush_start)
	r.standing = Standing.fresh()
	return r


func reach() -> Dictionary:
	return ContentDB.reaches[reach_id]


## How many Hush Depths there are past the plain game (depth 0).
static func depth_count() -> int:
	return (ContentDB.depths.get("depths", []) as Array).size()


## The sum of one Hush Depth rule over every depth up to this run's.
func mod(effect: String) -> float:
	# Summed again if the depth changed since. The starting Scrap and Light are
	# the one part a later change can't reach: they were paid out in create().
	if _mods_depth != depth:
		_mods.clear()
		_mods_depth = depth
		var list: Array = ContentDB.depths.get("depths", [])
		for i in mini(depth, list.size()):
			var fx: Dictionary = list[i].get("effects", {})
			for k: String in fx:
				_mods[k] = float(_mods.get(k, 0.0)) + float(fx[k])
	return float(_mods.get(effect, 0.0))


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
		ship.hull = maxi(0, ship.hull - int(reach().dark_jump_hull) - int(mod("dark_jump_hull")))
		messages.append("UI_DARK_JUMP")
	_pay_upkeep()
	jumps += 1
	var per_jump := float(reach().hush_per_jump) + mod("hush_per_jump") + ship.mod("hush")
	hush = Q.q(hush + per_jump + float(reach().hush_per_light) * light)
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
		# The Gate's dock patches the hull on arrival, so a Warden meets a ship fit to
		# fight. A Reach with a Warden holds its Gate: it is crossed once it is beaten.
		_patch_at_gate()
		var warden := str(reach().get("warden", ""))
		if warden != "":
			_start_fight(warden, 0, "", false)
			return
		_cross_gate()
		return
	event_id = _pick_event(kind)
	if event_id != "":
		state = "event"
		return
	_skip_story(kind)


## The Gate's dock patches some hull.
func _patch_at_gate() -> void:
	ship.hull = mini(ship.max_hull, ship.hull + int(reach().get("gate_repair", 0)))


func _cross_gate() -> void:
	reaches_crossed += 1
	state = "reach_done" if str(reach().get("next", "")) != "" else "won"


## The fight under way is this Reach's Warden, at the Gate.
func is_warden_fight() -> bool:
	return state == "fight" and str(here().kind) == "gate"


## No story for this beacon: fall straight into what's there.
func _skip_story(kind: String) -> void:
	match kind:
		"fight":
			_start_fight(REACH_ENEMY)
		"store":
			Market.open(self)
		_:
			state = "chart"


## The run has ended, lost or won; nothing more can happen in it.
func is_over() -> bool:
	return state in ENDINGS


## From a Gate's screen into the next Reach: a new chart and a fresh Hush.
## The ship, crew, Scrap and Light carry on (the Gate patches a little hull),
## and stories already told stay told.
func next_reach() -> bool:
	var next := str(reach().get("next", ""))
	if state != "reach_done" or next == "":
		return false
	reach_id = next
	chart = StarChart.generate(reach(), rng.stream("map"))
	at = chart.start_id()
	visited.assign([at])
	hush = float(reach().hush_start)
	messages.clear()
	state = "chart"
	return true


## Hungry modules burn Light each jump. Light the run doesn't have is taken
## from the dark instead: the Hush comes on faster, so the gain is never free.
func _pay_upkeep() -> void:
	var upkeep := int(ship.mod("light_upkeep"))
	var unpaid := maxi(0, upkeep - light)
	light -= upkeep - unpaid
	if unpaid > 0:
		hush = Q.q(hush + UNPAID_UPKEEP_HUSH * unpaid)
		messages.append("UI_UPKEEP_UNPAID")


func is_swallowed(id: String) -> bool:
	return float(chart.node(id).col) <= hush


# ---------------------------------------------------------------- fights


## faction "" means the enemy ship's own faction, if it has one. A Warden is
## built for its Reach, so it skips the Reach's enemy boost (boosted false); the
## Hush Depth's extra hull still applies to every enemy.
func _start_fight(enemy: String, enemy_hull := 0, faction := "", boosted := true) -> void:
	if enemy == REACH_ENEMY:
		enemy = _pick_enemy(faction)
	fight_faction = faction if faction != "" else str(ContentDB.ships[enemy].get("faction", ""))
	combat = Combat.from_ship(rng.stream("combat").randi(), ship, enemy)
	var foe := combat.enemy()
	if boosted:
		foe.boost(reach().get("enemy_boost", {}))
	foe.boost({"hull": int(mod("enemy_hull"))})
	foe.hull = clampi(foe.hull + enemy_hull, 1, foe.max_hull)
	state = "fight"


## A ship from the Reach's pool. A faction that dislikes the ship sends its
## hulls more often, and one that trusts it sends them less. A fight an event
## gives to a faction draws only that faction's hulls, if the Reach has any.
func _pick_enemy(faction := "") -> String:
	var pool: Array = reach().enemies
	if faction != "":
		var own := pool.filter(
			func(id: Variant) -> bool:
				return str(ContentDB.ships[str(id)].get("faction", "")) == faction
		)
		pool = own if not own.is_empty() else pool
	var weights: Array[int] = []
	for id: Variant in pool:
		weights.append(standing.ambush(str(ContentDB.ships[str(id)].get("faction", ""))))
	return str(pool[maxi(0, RngStreams.weighted_pick(weights, rng.stream("encounters")))])


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
	var won_scrap := loot.randi_range(int(reward.scrap[0]), int(reward.scrap[1]))
	won_scrap = int(won_scrap * (1.0 + ship.mod("salvage")))
	_gain_scrap(maxi(0, won_scrap + int(mod("fight_scrap"))) + fight_bonus_scrap)
	light += loot.randi_range(int(reward.light[0]), int(reward.light[1]))
	light += int(ship.mod("fight_light"))
	# What the Choir sang out of the Ember is gone once the fight ends.
	light = maxi(0, light - combat.light_drained[0])
	fights_won += 1
	fight_bonus_scrap = 0
	messages.clear()
	messages.append_array(standing.fight_won(fight_faction))
	fight_faction = ""
	if combat.light_drained[0] > 0:
		messages.append("UI_LIGHT_SUNG")
	var gear_roll := rng.stream("gear")
	if gear_roll.randf() < float(reward.get("gear_chance", 0.0)):
		var found := Gear.pick(gear_roll, unlocked)
		if not found.is_empty():
			gain(found)
	ship.recover_after_fight()
	var gate := str(here().kind) == "gate"
	combat = null
	state = "chart"
	if gate:
		_cross_gate()
	return true


# ---------------------------------------------------------------- events


## A story for a beacon of this kind, one the run hasn't seen if it can.
## Once every story of a kind is seen, a new cycle starts, since a run across
## four Reaches outlasts them and a beacon still needs one, but the same story
## never shows twice in a row.
func _pick_event(kind: String) -> String:
	var ids: Array[String] = []
	var seen: Array[String] = []
	for eid: String in ContentDB.events:
		var e: Dictionary = ContentDB.events[eid]
		if str(e.get("beacon", "event")) == kind and EventRules.is_open(self, e):
			(seen if seen_events.has(eid) else ids).append(eid)
	if ids.is_empty() and not seen.is_empty():
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
	return EventRules.meets(self, choices[i].get("requires", {}))


## The percent chance choice i's crew skill check passes, or -1 if it has none.
func check_chance(i: int) -> int:
	var choices: Array = event().get("choices", [])
	return EventRules.chance(self, choices[i]) if i >= 0 and i < choices.size() else -1


func choose(i: int) -> bool:
	if not can_choose(i):
		return false
	var ev := event()
	var outcomes := EventRules.outcomes_for(self, ev.choices[i])
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
	_apply(picked.get("effects", {}), str(ev.get("faction", "")))
	return true


## faction is the event's own: a store or fight the event opens is that faction's.
func _apply(fx: Dictionary, faction := "") -> void:
	_gain_scrap(int(fx.get("scrap", 0)))
	light = maxi(0, light + int(fx.get("light", 0)))
	ship.hull = clampi(ship.hull + int(fx.get("hull", 0)), 0, ship.max_hull)
	hush = Q.q(hush + float(fx.get("hush", 0.0)))
	var heal := float(fx.get("crew_hp", 0.0))
	if heal != 0.0:
		for c in ship.alive_crew():
			# Events can hurt crew but never kill them outright.
			c.hp = Q.q(clampf(c.hp + heal, 1.0, c.max_hp))
	var rep: Dictionary = fx.get("rep", {})
	for f: String in rep:
		messages.append_array(Standing.news_for(f, standing.change(f, int(rep[f]))))
	for f in EventRules.names(fx.get("flag", [])):
		if not flags.has(f):
			flags.append(f)
	if ship.hull <= 0:
		state = "lost"
		return
	for kind: String in ["module", "weapon"]:
		if fx.has(kind):
			var id := str(fx[kind])
			var item := {"kind": kind, "id": id}
			if id == "any":
				item = Gear.pick(rng.stream("gear"), unlocked, kind)
			if not item.is_empty():
				gain(item)
	if fx.has("fight"):
		fight_bonus_scrap = int(fx.get("fight_bonus_scrap", 0))
		# A fight an event starts is the event's faction's, unless it names another.
		var whose := str(fx.get("fight_faction", faction))
		_start_fight(str(fx.fight), int(fx.get("enemy_hull", 0)), whose)
	elif fx.get("store", false):
		store_faction = faction
		Market.open(self)


## The player has read the event's result; the run moves on.
func read_outcome() -> bool:
	if outcome == "":
		return false
	outcome = ""
	messages.clear()  # its standing news was on the result screen; the chart starts fresh
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
	var p := int(prices.get(item + "_scrap", -1)) if item in STORE_ITEMS else -1
	return marked_up(p)


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
	store_faction = ""
	stock.clear()
	selling = false
	state = "chart"
	return true


func _gain_scrap(n: int) -> void:
	scrap = maxi(0, scrap + n)
	scrap_earned += maxi(0, n)


## New gear: fitted or mounted if there is a free space, else into the hold,
## else broken down for its sale price. Leaves a message naming it, as
## "<key>|<name key>" for the view to fill in.
func gain(item: Dictionary) -> String:
	var placed := Gear.place(ship, item)
	var key := "UI_GEAR_FITTED"
	if not placed:
		if hold.size() < HOLD_SIZE:
			hold.append(item)
			key = "UI_GEAR_HELD"
		else:
			_gain_scrap(Market.sell_price(item))
			key = "UI_GEAR_SCRAPPED"
	messages.append("%s|%s" % [key, str(Gear.entry(item).name)])
	return key


# ---------------------------------------------------------------- refit


## The store's refit page, and back. It is a run state so a save made on it
## reopens on it.
## What the store's buttons do, top to bottom: its items, the pages, then Leave.
## Wares shows only where the Reach's stores carry stock.
func store_options() -> Array[String]:
	var out := store_items()
	if int(reach().store.get("stock", 0)) > 0:
		out.append("wares")
	out.append_array(["refit", "modules", "guns", "leave"])
	return out


## The buttons of whichever store page is open, or [] off the store.
func page_options() -> Array[String]:
	match state:
		"store":
			return store_options()
		"refit":
			return refit_options()
	return Market.options(self)


## What the refit page's buttons do: one per system, then Stoke, then Back.
func refit_options() -> Array[String]:
	var out: Array[String] = REFIT_SYSTEMS.duplicate()
	out.append_array(["stoke", "back"])
	return out


## Does what a store or refit button says. Returns false if it can't.
func store_action(option: String) -> bool:
	match option:
		"refit":
			return open_refit()
		"leave":
			return leave_store()
		"stoke":
			return stoke()
		"back":
			return close_refit() if state == "refit" else Market.act(self, option)
	if option in REFIT_SYSTEMS:
		return refit(option)
	if option in STORE_ITEMS:
		return buy(option)
	return Market.act(self, option)


func open_refit() -> bool:
	if state != "store":
		return false
	state = "refit"
	return true


func close_refit() -> bool:
	if state != "refit":
		return false
	state = "store"
	return true


## Scrap for the system's next level, or -1 if it is at its cap or the ship has none.
func refit_price(sys: String) -> int:
	if not ship.can_upgrade(sys):
		return -1
	var prices: Array = ContentDB.systems[sys].get("upgrade_scrap", [])
	return marked_up(int(prices[ship.system_room(sys).level - 1]))


## A store or refit price with the Hush Depth's markup and the store's faction's
## view of the ship. Only a real price changes: -1 (not for sale) and 0 (dropped
## by the Reach) stay as they are, and a friendly discount never makes one free.
func marked_up(p: int) -> int:
	if p <= 0:
		return p
	return maxi(1, p + int(mod("store_markup")) + standing.price_delta(store_faction))


func can_refit(sys: String) -> bool:
	var p := refit_price(sys)
	return state == "refit" and p >= 0 and scrap >= p


func refit(sys: String) -> bool:
	if not can_refit(sys):
		return false
	scrap -= refit_price(sys)
	ship.upgrade(sys)
	ship.power_up(sys)  # the new level comes powered if the reactor has room
	return true


## Light to stoke the Ember once more (one more reactor power), or -1 at the cap.
func stoke_price() -> int:
	var prices: Array = ContentDB.systems.ember.get("stoke_light", [])
	return int(prices[ship.stokes]) if ship.stokes < prices.size() else -1


func can_stoke() -> bool:
	var p := stoke_price()
	return state == "refit" and p >= 0 and light >= p


## Burns Light into the Ember for one more reactor power. Holding less Light
## also slows the Hush, which is why a player might stoke before a long jump.
func stoke() -> bool:
	if not can_stoke():
		return false
	light -= stoke_price()
	ship.stoke()
	return true


# ---------------------------------------------------------------- save


func to_dict() -> Dictionary:
	return {
		"reach": reach_id,
		"depth": depth,
		"id": run_id,
		"reaches_crossed": reaches_crossed,
		"fights_won": fights_won,
		"scrap_earned": scrap_earned,
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
		"standing": standing.to_dict(),
		"flags": Array(flags),
		"store_faction": store_faction,
		"fight_faction": fight_faction,
		"unlocked": Array(unlocked),
		"hold": hold.duplicate(true),
		"stock": stock.duplicate(true),
		"selling": selling,
	}


static func from_dict(d: Dictionary) -> Run:
	ContentDB.load_all()
	var r := Run.new()
	r.reach_id = str(d.reach)
	r.depth = clampi(int(d.get("depth", 0)), 0, depth_count())  # an update may drop depths
	r.run_id = str(d.get("id", ""))
	r.reaches_crossed = int(d.get("reaches_crossed", 0))
	r.fights_won = int(d.get("fights_won", 0))
	r.scrap_earned = int(d.get("scrap_earned", 0))
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
	r.standing = Standing.from_dict(d.get("standing", {}))
	for f in d.get("flags", []):
		r.flags.append(str(f))
	r.store_faction = str(d.get("store_faction", ""))
	r.fight_faction = str(d.get("fight_faction", ""))
	_load_gear(r, d)
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


## The hold, a store's wares and the unlocks gear is drawn from. Loaded before
## anything that may dock the run at a store, which draws fresh wares.
static func _load_gear(r: Run, d: Dictionary) -> void:
	for u: Variant in d.get("unlocked", []):
		r.unlocked.append(str(u))
	r.hold = _gear_list(d.get("hold", []))
	r.stock = _gear_list(d.get("stock", []))
	r.selling = bool(d.get("selling", false)) and r.state in Market.GEAR_PAGES
	if not d.has("stock") and r.state in STORE_PAGES:
		# Docked when the game updated to stores with wares: lay them out now.
		var page := r.state
		Market.open(r)
		r.state = page


## Saved gear, keeping only items the content still has.
static func _gear_list(saved: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not saved is Array:
		return out
	for item: Variant in saved:
		if Gear.is_item(item):
			out.append({"kind": str(item.kind), "id": str(item.id)})
	return out
