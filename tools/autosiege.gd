extends SceneTree
## Plays the Kindling siege with the Autopilot from a range of arrival states and
## prints how often it is won. The whole-run report reaches it too rarely to tune.
## godot --headless --path . -s tools/autosiege.gd -- [sieges per row]

const HULL_SHARES: Array[float] = [1.0, 0.66, 0.5]
const LIGHTS: Array[int] = [0, 5]


func _init() -> void:
	var n := 20
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	ContentDB.load_all()
	for hull in ShipRoster.playable():
		for share in HULL_SHARES:
			for light in LIGHTS:
				_report(hull, share, light, n)
	quit()


func _report(hull: String, share: float, light: int, n: int) -> void:
	var won := 0
	var secs := 0.0
	var left := 0
	for i in n:
		var run := Run.create(7000 + i, hull, "reach_4")
		run.light = light
		run.ship.hull = maxi(1, int(run.ship.max_hull * share))
		for node in run.chart.nodes:
			if node.kind == "gate":
				run.at = node.id
		run._arrive()
		var c := run.combat
		var pilot := Autopilot.new()
		while c.state == "fighting" and c.tick_count < 8000:
			pilot.combat_step(c)
			c.tick()
		if c.state == "won":
			won += 1
			secs += c.time()
			left += c.player().hull
	print(
		(
			"%-16s hull %3d%%  light %d  won %3d%%  avg %3.0fs  avg hull left %.1f"
			% [
				hull,
				int(share * 100),
				light,
				100 * won / n,
				secs / maxf(1, won),
				float(left) / maxf(1, won)
			]
		)
	)
