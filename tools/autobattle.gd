extends SceneTree
## Plays many seeded fights with no screen and prints balance numbers.
## godot --headless --path . -s tools/autobattle.gd -- [fights] [ship id] [enemy id]
## Every hull a player can pick fights the Cutter, unless a ship id is given; an
## enemy id (any hull, "all" for every enemy and Warden) picks the opponent.
## Three player policies:
##   idle:    aims both guns at the enemy weapons room and does nothing else
##   novice:  the Autopilot's new player (aims at the open deck, sends crew to
##            fires and repairs)
##   skilled: the Autopilot's practised player (see tools/autopilot.gd)

const MAX_TIME := 300.0


func _init() -> void:
	var n := 200
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	ContentDB.load_all()
	var hulls := ShipRoster.playable()
	var foes: Array[String] = ["ashmarket_cutter"]
	if args.size() > 2:
		foes.assign([args[2]] if args[2] != "all" else _enemies())
		for foe in foes:
			if not ContentDB.ships.has(foe):
				push_error("%s is not a hull" % foe)
				quit(1)
				return
	if args.size() > 1 and args[1] != "all":
		if not args[1] in hulls:
			push_error("%s is not a hull a player can pick: %s" % [args[1], hulls])
			quit(1)
			return
		hulls.assign([args[1]])
	for hull in hulls:
		for foe in foes:
			print("%s vs %s" % [hull, foe])
			_report(n, hull, foe)
	quit()


func _enemies() -> Array[String]:
	var out: Array[String] = []
	for id: String in ContentDB.ships:
		if not bool(ContentDB.ships[id].get("playable", false)):
			out.append(id)
	return out


func _report(n: int, hull: String, foe: String) -> void:
	for policy in ["idle", "novice", "skilled"]:
		var wins := 0
		var timeouts := 0
		var times: Array[float] = []
		var hull_left := 0
		for seed_value in n:
			var c := Combat.create(seed_value + 1000, hull, foe)
			var auto := Autopilot.make(policy) if policy in Autopilot.PROFILES else null
			if policy == "idle":
				for i in c.player().weapon_ids.size():
					c.apply({"type": "aim", "weapon": i, "room": "weapons"})
			while c.state == "fighting" and c.time() < MAX_TIME:
				if auto:
					auto.combat_step(c)
				c.tick()
			if c.state == "won":
				wins += 1
				hull_left += c.player().hull
			elif c.state == "fighting":
				timeouts += 1
			times.append(c.time())
		times.sort()
		print(
			(
				(
					"%-8s wins %3d%%  stalemates %d  median fight %3.0fs"
					+ "  (10%%: %3.0fs, 90%%: %3.0fs)  avg hull left on a win %.1f/%d"
				)
				% [
					policy,
					100 * wins / n,
					timeouts,
					times[n / 2],
					times[n / 10],
					times[n * 9 / 10],
					float(hull_left) / maxf(1, wins),
					int(ContentDB.ships[hull].hull)
				]
			)
		)
