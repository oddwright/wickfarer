class_name Autopilot
extends RefCounted
## A rough stand-in for a human player, used by tests and balance tools only.
## In fights it aims at whichever enemy deck the ward isn't covering and sends
## crew to fires and repairs. On the chart it heads for the Gate, avoids
## swallowed beacons and spends scrap on repairs.

var pilot := CombatAI.new()


func combat_step(c: Combat) -> void:
	if c.tick_count % 10 != 0:
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


## Plays the run until it ends or `max_steps` actions pass. Returns the final state.
func play(run: Run, max_steps := 400, max_fight_ticks := 6000) -> String:
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
				if run.light < 3:
					run.buy("light")
				run.leave_store()
			_:
				return run.state
	return run.state


func _pick_jump(run: Run) -> String:
	var best := ""
	var best_score := -INF
	for id in run.jump_targets():
		var n := run.chart.node(id)
		var score := float(n.col) * 10.0
		if run.is_swallowed(id):
			score -= 100.0
		if n.kind == "store":
			score += 3.0
		if score > best_score:
			best_score = score
			best = id
	return best
