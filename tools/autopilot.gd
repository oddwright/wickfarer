class_name Autopilot
extends RefCounted
## A rough stand-in for a human player, used by tests and balance tools only.
## In fights it aims at whichever enemy deck the ward isn't covering and sends
## crew to fires and repairs. On the chart it heads for the Gate, avoids
## swallowed beacons, spends scrap on repairs and refits, and goes on
## through every Gate.

const SIEGE_TICKS := 8000

var pilot := CombatAI.new()


func combat_step(c: Combat) -> void:
	if c.tick_count % 10 != 0:
		return
	if c.siege != null:
		_siege_step(c)
		return
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


## Puts a run on its Reach's Gate and arrives there, as a jump would: for tests
## and tools that start at the Gate (the Kindling, a Reach's end).
static func arrive_at_gate(run: Run) -> void:
	for n in run.chart.nodes:
		if n.kind == "gate":
			run.at = n.id
	run._arrive()


## The Kindling: shoot the gathering knot, ward the deck it will strike, mend
## what it swallows, and burn every Light into the Cradle once that is allowed.
func _siege_step(c: Combat) -> void:
	var sg := c.siege
	var me := c.player()
	if sg.gathering():
		for i in me.weapon_ids.size():
			if me.weapon_target[i] != sg.knot:
				c.apply({"type": "aim", "weapon": i, "room": sg.knot})
		if me.ward_deck != sg.target_deck and me.max_ward_layers() > 0:
			c.apply({"type": "ward_deck", "deck": sg.target_deck})
	while sg.can_kindle():
		c.apply({"type": "kindle"})
	pilot._crew(c, me, 0)


## Plays the run until it ends or `max_steps` actions pass. Returns the final state.
func play(run: Run, max_steps := 1200, max_fight_ticks := 6000) -> String:
	for step in max_steps:
		match run.state:
			"chart":
				run.jump(_pick_jump(run))
			"fight":
				var ticks := 0
				# The Kindling runs four minutes or more: longer than a fight's cap.
				var cap := (
					maxi(max_fight_ticks, SIEGE_TICKS) if run.combat.siege else max_fight_ticks
				)
				while run.combat.state == "fighting" and ticks < cap:
					combat_step(run.combat)
					run.combat.tick()
					ticks += 1
				if run.combat.state == "fighting":
					return "stalemate"
				run.finish_fight()
			"event":
				var picked := -1
				var choices: Array = run.event().choices
				for i in choices.size():
					if run.can_choose(i):
						picked = i
						break
				run.choose(picked)
			"store":
				while run.ship.hull < run.ship.max_hull - 2 and run.buy("repair"):
					pass
				while run.light < 4 and run.scrap >= 25 and run.buy("light"):
					pass
				_refit(run)
				run.leave_store()
			"wares", "modules", "guns":
				run.store_action("back")  # a save made on a store page
			"reach_done":
				run.next_reach()
			_:
				return run.state
	return run.state


## Spends spare scrap on the cheapest refit, keeping enough for a few repairs,
## and stokes the Ember when it can spare the Light for the jumps ahead.
func _refit(run: Run) -> void:
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
	run.close_refit()


func _pick_jump(run: Run) -> String:
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
