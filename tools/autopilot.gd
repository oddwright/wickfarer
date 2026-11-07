class_name Autopilot
extends RefCounted
## Stand-ins for human players, used by tests and balance tools only. They play
## through the same entry points the screens use (Combat.apply and the Run
## actions), so they can't do anything a player can't.
##
## Two profiles:
##   novice:  a new player. In fights it aims at the deck the enemy ward isn't
##            covering and sends crew to fires and repairs, but never touches
##            power or its own ward. On the chart it heads straight for the
##            Gate, takes the first choice it can in every story, and spends
##            scrap on repairs and the cheapest refit.
##   skilled: a player who has learned the game. It splits its guns across
##            the enemy decks so the enemy ward has no busier deck to follow,
##            picks the enemy room that hurts most, shares out reactor power so
##            the guns keep firing, keeps crew on repairs, weighs every story
##            choice, refits by a plan, and picks the route to the Gate with the
##            most to gain on it. It leaves its own ward on the hull's starting
##            deck: chasing the enemy's aim with it lost more runs than it saved.

const PROFILES: Array[String] = ["novice", "skilled"]
## The skilled player's refits, most wanted first. Helm and engines dodge whole
## volleys; wards are worth it in pairs, since two power make one layer.
const REFIT_PLAN: Array[String] = ["helm", "engines", "wards", "helm", "wards", "engines", "mend"]
## How the skilled player shares out reactor power: each step tops a system up
## to that much (-1: as far as it goes; -2: the hull's own starting power).
## Every gun first, then the wards the hull was built with.
const POWER_PLAN: Array = [
	["weapons", -1],
	["wards", -2],
	["helm", 1],
	["engines", 1],
	["mend", 1],
	["helm", -1],
	["engines", -1],
	["wards", -1],
	["mend", -1]
]
## Which of its own rooms the skilled player saves first from fire and damage.
## The Ember heats the ship and feeds the reactor, so it comes before the guns.
const RESCUE_ORDER: Array[String] = ["ember", "weapons", "wards", "helm", "engines", "mend"]
const STATIONS: Array[String] = ["weapons", "helm", "wards", "engines", "ember"]
## What one of each is worth to the skilled player, in scrap.
const LIGHT_VALUE := 5.0
const HUSH_VALUE := 6.0  ## per unit of Hush: about two-thirds of a jump of lead lost
const FIGHT_HULL_COST := 4.0  ## hull a fight usually costs, before the Reach's boost

var profile := "novice"
var pilot := CombatAI.new()


static func make(profile_name: String) -> Autopilot:
	assert(profile_name in PROFILES)
	var a := Autopilot.new()
	a.profile = profile_name
	return a


func is_skilled() -> bool:
	return profile == "skilled"


# ---------------------------------------------------------------- fights


## One fight tick's worth of decisions. Call it before every Combat.tick().
func combat_step(c: Combat) -> void:
	if is_skilled():
		_skilled_step(c)
	elif c.tick_count % 10 == 0:
		_novice_step(c)


func _novice_step(c: Combat) -> void:
	var foe := c.enemy()
	var open_deck := 1 - foe.ward_deck if foe.ward_layers > 0 else 1
	var want := ""
	for sys in ["weapons", "ember", "helm", "wards", "engines", "mend"]:
		var r := foe.system_room(sys)
		if r and r.deck == open_deck:
			want = r.id
			break
	for i in c.player().weapon_ids.size():
		var t := c.player().weapon_target[i]
		if t == "" or foe.room(t).deck != open_deck:
			c.apply({"type": "aim", "weapon": i, "room": want})
	pilot._crew(c, c.player(), 0)


func _skilled_step(c: Combat) -> void:
	var me := c.player()
	if c.tick_count % 10 == 0:
		_spend_power(c, me)
		_volley(c, me, c.enemy())
		_crew(c, me)


## Shares the reactor out by plan: every gun first, then wards in pairs, then
## the rest. When damage takes power away the sim sheds weapons before wards,
## so this also moves power back from the wards to keep the guns firing.
func _spend_power(c: Combat, me: Ship) -> void:
	var left := me.available_power()
	var want := {}
	for step: Array in POWER_PLAN:
		var sys: String = step[0]
		var r := me.system_room(sys)
		if r == null:
			continue
		var cap := r.effective_level()
		if int(step[1]) == -2:
			var built: Dictionary = ContentDB.ships[me.content_id].get("start_power", {})
			cap = mini(cap, int(built.get(sys, 0)))
		elif int(step[1]) >= 0:
			cap = mini(cap, int(step[1]))
		if sys == "weapons":
			cap = _gun_power(me, mini(cap, left))
		var had := int(want.get(sys, 0))
		var n := clampi(cap - had, 0, left)
		if sys == "wards":
			n -= (had + n) % 2  # a single extra ward power does nothing until its pair arrives
		want[sys] = had + n
		left -= n
	for sys: String in want:
		while (
			me.system_power(sys) > int(want[sys]) and c.apply({"type": "power_down", "system": sys})
		):
			pass
	for sys: String in want:
		while (
			me.system_power(sys) < int(want[sys]) and c.apply({"type": "power_up", "system": sys})
		):
			pass


## The power that runs as many guns as `limit` allows. Guns take power in
## order, so a level that can't run the next gun is left for other systems.
func _gun_power(me: Ship, limit: int) -> int:
	var total := 0
	for wid in me.weapon_ids:
		var need := int(ContentDB.weapons[wid].power)
		if total + need > limit:
			break
		total += need
	return total


## Guns stay aimed, as a player leaves them, and the enemy moves its ward to
## whichever deck more of them point at. So the skilled player keeps the count
## even: guns that strip wards work on the warded deck, the rest hit the open
## one, and if there are more of those, the weakest is a decoy on the warded
## deck. With the count even the ward stays put and the open deck stays open.
## A gun is re-aimed within its deck only when that is free, just after it
## fires; it moves decks, paying to re-sight, only when its job changes.
func _volley(c: Combat, me: Ship, foe: Ship) -> void:
	var decks := _gun_decks(me, foe)
	for i in me.weapon_ids.size():
		var deck: int = decks[i]
		var t := me.weapon_target[i]
		var best := _best_room(foe, deck)
		if best == "":
			continue
		var off_deck: bool = t != "" and deck >= 0 and foe.room(t).deck != deck
		if t == "" or off_deck or (_just_fired(me, i) and t != best):
			c.apply({"type": "aim", "weapon": i, "room": best})


## A gun fired since the last decision (half a second back): re-aiming it now
## costs nothing, as its charge is still under the re-sighting cost.
func _just_fired(me: Ship, i: int) -> bool:
	var rate := maxf(1.0, me.station_bonus("weapons", Ship.GUN_BOOST))
	return me.weapon_charge[i] <= Combat.AI_THINK * rate + 0.01


## The deck each gun should aim at, or -1 for either. See _volley.
func _gun_decks(me: Ship, foe: Ship) -> Array[int]:
	var out: Array[int] = []
	out.resize(me.weapon_ids.size())
	out.fill(-1)
	if foe.ward_layers <= 0 and foe.max_ward_layers() <= 0:
		return out  # no ward to dodge
	var shut := foe.ward_deck
	var strippers: Array[int] = []
	var others: Array[int] = []
	for i in me.weapon_ids.size():
		# A gun without power keeps pointing at the best room anywhere. Measured,
		# that beat both dropping its aim and keeping it in the split: Wren
		# whole-run wins 52% against 30%.
		if not me.weapon_powered(i):
			continue
		(strippers if ContentDB.weapons[me.weapon_ids[i]].strips_ward else others).append(i)
		out[i] = 1 - shut
	var on_shut := 0
	for i in strippers:
		if on_shut < (strippers.size() + others.size()) / 2:
			out[i] = shut
			on_shut += 1
	# Not enough strippers to even the count: the weakest of the rest is the decoy.
	others.sort_custom(func(a: int, b: int) -> bool: return _gun_punch(me, a) < _gun_punch(me, b))
	for i in others:
		if on_shut < (strippers.size() + others.size()) / 2:
			out[i] = shut
			on_shut += 1
	return out


## Damage a gun does per second of charging, to pick the decoy.
func _gun_punch(me: Ship, i: int) -> float:
	var w: Dictionary = ContentDB.weapons[me.weapon_ids[i]]
	return float(w.shots) * float(int(w.hull_damage) + int(w.system_damage)) / float(w.charge)


## The enemy room a hit hurts most, on the given deck (-1: either).
func _best_room(foe: Ship, deck: int) -> String:
	var best := ""
	var best_value := -INF
	for r in foe.rooms:
		if deck >= 0 and r.deck != deck:
			continue
		var v := _room_value(foe, r)
		if v > best_value:
			best_value = v
			best = r.id
	return best


func _room_value(foe: Ship, r: Room) -> float:
	var v := 0.5 * foe.crew_in(r.id, true).size()
	if r.level <= 0 or r.damage >= float(r.level):
		return v  # only hull and crew left to hurt here
	match r.system:
		"ember":
			v += 5.0  # every level of damage takes two reactor power away
		"weapons":
			v += 4.5
		"helm":
			v += 3.0 if foe.evasion() > 0.0 else 1.0
		"wards":
			v += 3.0 if foe.max_ward_layers() > 0 else 0.5
		"mend":
			v += 1.5
		_:
			v += 1.0
	return v


## The skilled player's crew orders. Anyone fixing or fighting a fire stays
## at it; the badly hurt rest in mend; fires and damage get hands next, most
## important room first, two on a bad one, taking spare crew before anyone at a
## station; and whoever is still spare takes an empty station. Crew already at
## a station stay there, so nobody walks back and forth between them.
func _crew(c: Combat, me: Ship) -> void:
	var heading := {}  ## room id -> crew walking or working there
	var spare: Array[Crew] = []
	var stationed: Array[Crew] = []
	var mend := me.system_room("mend")
	for cr in me.alive_crew():
		var dest: String = cr.path.back() if cr.is_moving() else cr.room
		var here := me.room(cr.room)
		var resting := mend != null and cr.room == mend.id and not cr.is_moving()
		var hurt := cr.hp < cr.max_hp * (0.8 if resting else 0.35)
		if hurt and mend and mend.power > 0 and mend.fire <= 0.0:
			if dest != mend.id:
				c.apply({"type": "move", "crew": cr.uid, "room": mend.id})
			heading[mend.id] = int(heading.get(mend.id, 0)) + 1
			continue
		heading[dest] = int(heading.get(dest, 0)) + 1
		if cr.is_moving() or here.fire > 0.0 or here.damage > 0.0:
			continue
		(stationed if here.system in STATIONS else spare).append(cr)
	for room in _jobs(me):
		var need := 2 if room.fire > 30.0 or room.damage > 1.0 else 1
		while (
			int(heading.get(room.id, 0)) < need and not (spare.is_empty() and stationed.is_empty())
		):
			var pool := spare if not spare.is_empty() else stationed
			var cr := _nearest(me, pool, room.id)
			c.apply({"type": "move", "crew": cr.uid, "room": room.id})
			pool.erase(cr)
			heading[cr.room] = int(heading[cr.room]) - 1
			heading[room.id] = int(heading.get(room.id, 0)) + 1
	for sys in STATIONS:
		var room := me.system_room(sys)
		if room == null or int(heading.get(room.id, 0)) > 0 or spare.is_empty():
			continue
		var cr := _nearest(me, spare, room.id)
		for o in spare:
			if o.post == room.id:
				cr = o  # whoever's post it is takes it, so their skill keeps growing
		c.apply({"type": "move", "crew": cr.uid, "room": room.id})
		spare.erase(cr)
		heading[room.id] = 1


## Rooms that need hands: fires, then damage, the most important first.
func _jobs(me: Ship) -> Array[Room]:
	var fires: Array[Room] = []
	var broken: Array[Room] = []
	var rooms: Array[Room] = []
	for sys in RESCUE_ORDER:
		var r := me.system_room(sys)
		if r:
			rooms.append(r)
	for r in me.rooms:
		if not r in rooms:
			rooms.append(r)
	for r in rooms:
		if r.fire > 0.0:
			fires.append(r)
		elif r.damage > 0.0:
			broken.append(r)
	fires.append_array(broken)
	return fires


func _nearest(me: Ship, crew: Array[Crew], room_id: String) -> Crew:
	var best: Crew = crew[0]
	var best_len := 999
	for cr in crew:
		var n := me.find_path(cr.room, room_id).size()
		if n < best_len:
			best_len = n
			best = cr
	return best


# ---------------------------------------------------------------- runs


## Plays the run until it ends or `max_steps` actions pass. Returns the final state.
func play(run: Run, max_steps := 1200, max_fight_ticks := 6000) -> String:
	for step in max_steps:
		match run.state:
			"chart":
				run.jump(_pick_jump(run))
			"fight":
				var ticks := 0
				while run.combat.state == "fighting" and ticks < max_fight_ticks:
					combat_step(run.combat)
					run.combat.tick()
					ticks += 1
				if run.combat.state == "fighting":
					return "stalemate"
				run.finish_fight()
			"event":
				run.choose(_pick_choice(run))
			"store", "refit":
				if is_skilled():
					_skilled_store(run)
				else:
					_novice_store(run)
				run.close_refit()
				run.leave_store()
			"reach_done":
				run.next_reach()
			_:
				return run.state
	return run.state


func _pick_choice(run: Run) -> int:
	var choices: Array = run.event().choices
	var picked := -1
	var best := -INF
	for i in choices.size():
		if not run.can_choose(i):
			continue
		if not is_skilled():
			return i
		var v := _choice_value(run, choices[i])
		if v > best:
			best = v
			picked = i
	return picked


## The skilled player's guess at what a choice is worth, in scrap, averaged
## over its outcomes.
func _choice_value(run: Run, choice: Dictionary) -> float:
	var total := 0.0
	var weight := 0.0
	for o: Dictionary in choice.outcomes:
		total += float(o.weight) * _effects_value(run, o.get("effects", {}))
		weight += float(o.weight)
	return total / maxf(1.0, weight)


func _effects_value(run: Run, fx: Dictionary) -> float:
	var hull_value := _hull_value(run)
	var v := float(fx.get("scrap", 0)) + LIGHT_VALUE * float(fx.get("light", 0))
	v += hull_value * float(fx.get("hull", 0)) - HUSH_VALUE * float(fx.get("hush", 0.0))
	v += 0.1 * float(fx.get("crew_hp", 0.0)) * run.ship.alive_crew().size()
	if fx.has("fight"):
		v += _fight_value(run, hull_value) + float(fx.get("fight_bonus_scrap", 0))
		v -= hull_value * float(fx.get("enemy_hull", 0))  # a weaker foe hits back less
	elif fx.get("store", false):
		v += minf(float(run.scrap), 30.0) * 0.3
	if run.ship.hull + int(fx.get("hull", 0)) <= 0:
		v -= 1000.0
	return v


## Scrap a point of hull is worth: a repair's price when healthy, much more
## when the next hit could end the run.
func _hull_value(run: Run) -> float:
	var missing := 1.0 - float(run.ship.hull) / float(run.ship.max_hull)
	var p := float(maxi(1, run.price("repair")))
	return p * (1.0 + 4.0 * missing * missing) + (20.0 if run.ship.hull <= 6 else 0.0)


func _fight_value(run: Run, hull_value: float) -> float:
	var reward: Dictionary = run.reach().fight_reward
	var scrap := (float(reward.scrap[0]) + float(reward.scrap[1])) / 2.0
	var light := (float(reward.light[0]) + float(reward.light[1])) / 2.0
	var cost := FIGHT_HULL_COST + float(run.reach().get("enemy_boost", {}).get("hull", 0))
	return scrap + LIGHT_VALUE * light - hull_value * cost


## Buys repairs while hull is low, then a little Light, then the cheapest refit,
## keeping enough for a few repairs; stokes when it can spare the Light.
func _novice_store(run: Run) -> void:
	while run.ship.hull < run.ship.max_hull - 2 and run.buy("repair"):
		pass
	while run.light < 4 and run.scrap >= 25 and run.buy("light"):
		pass
	run.open_refit()
	var bought := true
	while bought:
		bought = false
		var cheapest := ""
		for sys in Run.REFIT_SYSTEMS:
			var p := run.refit_price(sys)
			if p >= 0 and (cheapest == "" or p < run.refit_price(cheapest)):
				cheapest = sys
		if cheapest != "" and run.scrap - run.refit_price(cheapest) >= 10:
			bought = run.refit(cheapest)
	if run.stoke_price() >= 0 and run.light - run.stoke_price() >= 4:
		run.stoke()


## Patches the hull up to a safe level first, keeps enough Light for the jumps
## left, then refits by plan and stokes so the new levels have power, and
## spends what is left on hull.
func _skilled_store(run: Run) -> void:
	var safe := int(run.ship.max_hull * 0.6)
	while run.ship.hull < safe and run.buy("repair"):
		pass
	var jumps_left := _jumps_to_gate(run) * int(run.reach().jump_light)
	while run.light < jumps_left and run.buy("light"):
		pass
	run.open_refit()
	var keep := run.price("repair") * 3
	var step := _next_refit(run)
	while step != "" and run.scrap - run.refit_price(step) >= keep and run.refit(step):
		step = _next_refit(run)
	var p_stoke := run.stoke_price()
	if p_stoke >= 0 and run.light - p_stoke >= jumps_left:
		run.stoke()
	run.close_refit()
	while run.ship.hull < run.ship.max_hull and run.buy("repair"):
		pass


## The first step of REFIT_PLAN the ship hasn't had yet: the n-th time a system
## appears it wants n levels over the hull's own. Steps a hull can't take (no
## such room, or at its cap) are passed over. "" once the plan is done.
func _next_refit(run: Run) -> String:
	var seen := {}
	var built := {}
	for r: Dictionary in ContentDB.ships[run.ship.content_id].rooms:
		built[str(r.get("system", ""))] = int(r.get("level", 0))
	for sys in REFIT_PLAN:
		seen[sys] = int(seen.get(sys, 0)) + 1
		var r := run.ship.system_room(sys)
		if r == null or run.refit_price(sys) < 0:
			continue
		if r.level < int(built.get(sys, 0)) + int(seen[sys]):
			return sys
	return ""


## The fewest jumps from here to this Reach's Gate (times jump_light: the Light they take).
func _jumps_to_gate(run: Run) -> int:
	return run.chart.columns - 1 - int(run.here().col)


func _pick_jump(run: Run) -> String:
	if is_skilled():
		return _plan_jump(run)
	var best := ""
	var best_score := -INF
	for id in run.jump_targets():
		var n := run.chart.node(id)
		var score := float(n.col) * 10.0
		if run.is_swallowed(id):
			score -= 100.0
		if n.kind == "store":
			# Worth a sideways jump once there is scrap to spend on refits.
			score += 12.0 if run.scrap >= 40 else 3.0
		if score > best_score:
			best_score = score
			best = id
	return best


## Looks along every route to the Gate and takes the first jump of the one
## with the most to gain, counting where the Hush will be at each step.
func _plan_jump(run: Run) -> String:
	var step := float(run.reach().hush_per_jump) + run.mod("hush_per_jump")
	step += float(run.reach().hush_per_light) * run.light
	var best := ""
	var best_value := -INF
	var hull_value := _hull_value(run)
	var values := {
		"fight": _fight_value(run, hull_value) * 0.6,
		"store": minf(float(run.scrap), 60.0) * 0.4 + (10.0 if run.ship.hull < 12 else 0.0),
		"event": 4.0,
		"swallowed": hull_value * float(run.reach().hush_hull) + 10.0,
	}
	var plan := {"step": step, "values": values, "max": run.chart.columns + 2}
	for id in run.jump_targets():
		var v := _route_value(run.chart, id, 1, run.hush + step, plan, {run.at: true})
		if v > best_value:
			best_value = v
			best = id
	return best


## The most a route on from `id` can be worth. The beacon values don't change
## along one plan, so _plan_jump works them out once.
func _route_value(
	chart: StarChart, id: String, jumps: int, hush: float, plan: Dictionary, seen: Dictionary
) -> float:
	var n := chart.node(id)
	var v := float(plan.values.get(str(n.kind), 1.0)) - 2.0  # a jump costs Light, lets the Hush in
	if float(n.col) <= hush:
		v -= float(plan.values.swallowed)
	if n.kind == "gate":
		return v
	if jumps > int(plan.max):
		return -INF
	var best := -INF
	seen[id] = true
	for nxt: String in n.links:
		if not seen.has(nxt):
			var step := float(plan.step)
			best = maxf(best, _route_value(chart, nxt, jumps + 1, hush + step, plan, seen))
	seen.erase(id)
	return v + best
