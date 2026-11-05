extends SceneTree
## Plays whole Reach runs with the Autopilot and prints how they end.
## godot --headless --path . -s tools/autorun.gd -- [runs]


func _init() -> void:
	var n := 40
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	var ends := {}
	var hull_left := 0
	var jumps := 0
	for i in n:
		var run := Run.create(5000 + i)
		var end := Autopilot.new().play(run)
		ends[end] = int(ends.get(end, 0)) + 1
		jumps += run.jumps
		if end == "reach_done":
			hull_left += run.ship.hull
	var done := int(ends.get("reach_done", 0))
	print(
		(
			"runs %d  reached the Gate %d%%  endings %s  avg jumps %.1f  avg hull at the Gate %.1f"
			% [n, 100 * done / n, ends, float(jumps) / n, float(hull_left) / maxf(1, done)]
		)
	)
	quit()
