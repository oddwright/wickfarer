extends SceneTree
## Plays whole runs with the Autopilot and prints how far they get.
## godot --headless --path . -s tools/autorun.gd -- [runs] [ship id|all] [profile]
## [runs] novice runs per hull; the skilled player plays half as many.
## With no ship id (or "all") it reports every hull a player can pick, and with
## no profile both of them: the novice should cross the first Gate about 60% of
## the time, and the skilled player should win 35-45% of whole runs.


func _init() -> void:
	var n := 40
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	var hulls := ShipRoster.playable()
	if args.size() > 1 and args[1] != "all":
		if not args[1] in hulls:
			push_error("%s is not a hull a player can pick: %s" % [args[1], hulls])
			quit(1)
			return
		hulls.assign([args[1]])
	var profiles := Autopilot.PROFILES.duplicate()
	if args.size() > 2:
		if not args[2] in profiles:
			push_error("%s is not an autopilot profile: %s" % [args[2], profiles])
			quit(1)
			return
		profiles.assign([args[2]])
	for hull in hulls:
		for profile: String in profiles:
			# A skilled run goes about three times as far, so half as many keep the
			# report's time down; the novice's Gate rate is the noisier target.
			_report(n if profile == "novice" else maxi(1, n / 2), hull, profile)
	quit()


func _report(n: int, hull: String, profile: String) -> void:
	var ends := {}
	var gates := {}
	var jumps := 0
	var earned := 0
	var hull_left := 0
	for i in n:
		var run := Run.create(5000 + i, hull)
		var end := Autopilot.make(profile).play(run, 1200)
		ends[end] = int(ends.get(end, 0)) + 1
		gates[run.reaches_crossed] = int(gates.get(run.reaches_crossed, 0)) + 1
		jumps += run.jumps
		earned += run.scrap_earned
		if end == "won":
			hull_left += run.ship.hull
	var won := int(ends.get("won", 0))
	var first_gate := n - int(gates.get(0, 0))
	print(
		(
			"%-16s %-8s runs %d  won %d%%  crossed the first Gate %d%%  endings %s  Gates crossed %s"
			% [hull, profile, n, 100 * won / n, 100 * first_gate / n, ends, gates]
		)
	)
	print(
		(
			"avg jumps %.1f  avg scrap earned %.0f  avg hull at the end of a win %.1f"
			% [float(jumps) / n, float(earned) / n, float(hull_left) / maxf(1, won)]
		)
	)
