extends SceneTree
## Plays many seeded fights with no screen and prints balance numbers.
## godot --headless --path . -s tools/autobattle.gd -- [fights] [ship id]
## Every hull a player can pick fights the Cutter, unless a ship id is given.
## Three player policies:
##   idle:    aims both guns at the enemy weapons room and does nothing else
##   captain: the same AI the enemy uses, playing the player's hull
##   tactician: aims at whichever deck the enemy ward is not covering, and
##              sends crew to fires and repairs (a rough stand-in for a human)

const MAX_TIME := 300.0


func _init() -> void:
	var n := 200
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	var hulls := ShipRoster.playable()
	if args.size() > 1:
		if not args[1] in hulls:
			push_error("%s is not a hull a player can pick: %s" % [args[1], hulls])
			quit(1)
			return
		hulls.assign([args[1]])
	for hull in hulls:
		print(hull)
		_report(n, hull)
	quit()


func _report(n: int, hull: String) -> void:
	for policy in ["idle", "captain", "tactician"]:
		var wins := 0
		var timeouts := 0
		var times: Array[float] = []
		var hull_left := 0
		for seed_value in n:
			var c := Combat.create(seed_value + 1000, hull)
			var pilot := CombatAI.new()
			if policy == "idle":
				for i in c.player().weapon_ids.size():
					c.apply({"type": "aim", "weapon": i, "room": "weapons"})
			while c.state == "fighting" and c.time() < MAX_TIME:
				c.tick()
				if policy == "captain" and c.tick_count % 10 == 0:
					pilot.think(c, 0)
				if policy == "tactician" and c.tick_count % 10 == 0:
					_tactician(c, pilot)
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


func _tactician(c: Combat, pilot: CombatAI) -> void:
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
