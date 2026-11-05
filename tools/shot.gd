extends SceneTree
## Screenshot one screen at a given window size (needs a display; use xvfb-run).
## godot --path . -s tools/shot.gd -- <width> <height> <out.png> [ticks] [screen] [ui size]
## screen is fight (default), chart, event, event:<event id>, store or lost,
## roster or roster_pick (the crew roster over a fight, picker shut or open),
## or a menu over a fight: title, pause, options or confirm. ui size is the
## options setting, a step from auto (-2 to 1); it is not saved.

var frames := 0
var main: Node
var out := ""
var ticks := 500
var which := "fight"
var ui_size := 0


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var size := Vector2i(int(a[0]), int(a[1]))
	out = a[2]
	if a.size() > 3:
		ticks = int(a[3])
	if a.size() > 4:
		which = a[4]
	if a.size() > 5:
		ui_size = int(a[5])
	DisplayServer.window_set_size(size)
	root.size = size
	SaveService.erase("run")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_set_up()
	if frames == 10:
		var img := root.get_texture().get_image()
		img.save_png(out)
		print("saved ", out, " ", img.get_size())
		SaveService.erase("run")
		quit()
	return false


func _set_up() -> void:
	main.settings.ui_size = ui_size
	main._on_resize()
	var run := Run.create(4242)
	for i in 2:  # two jumps in, whatever is at those beacons
		run.jump(run.jump_targets()[0])
		run.combat = null
		run.state = "chart"
	run.messages.clear()
	if which.begins_with("event:"):
		run.state = "event"
		run.event_id = which.trim_prefix("event:")
		if run.event().is_empty():
			push_error("no event called %s" % run.event_id)
	match which:
		"event":
			run.state = "event"
			run.event_id = "ash_toll"
		"store":
			run.state = "store"
		"lost":
			run.state = "lost"
		"fight":
			run._start_fight("ashmarket_cutter")
	if which in ["title", "pause", "options", "confirm", "roster", "roster_pick"]:
		run._start_fight("ashmarket_cutter")
	main._set_run(run)
	if main.combat:
		_play_fight(main.combat)
	match which:
		"title", "pause":
			main.open_menu(which)
		"roster", "roster_pick":
			_open_roster(which == "roster_pick")
		"options":
			main.open_menu("pause")
			main.open_menu("options")
		"confirm":
			main.open_menu("pause")
			main._confirm("abandon")


func _play_fight(c: Combat) -> void:
	c.apply({"type": "aim", "weapon": 0, "room": "weapons"})
	c.apply({"type": "aim", "weapon": 1, "room": "weapons"})
	c.apply({"type": "move", "crew": 3, "room": "galley"})
	for i in ticks:
		c.tick()
		main._on_events(c.events)
	c.apply({"type": "move", "crew": 1, "room": "ember"})
	for i in 12:
		c.tick()
	main.selected_weapon = 1


func _open_roster(picking: bool) -> void:
	var me: Ship = main.combat.player()
	var k := 0
	for c in me.crew:  # show a crew some fights into a run
		c.xp["steer"] = Skills.xp_for_rank(k % 4) + 20.0
		c.xp["patch"] = 35.0
		c.fight_xp["guns"] = 30.0 + 10.0 * k
		k += 1
	main.selected_weapon = -1
	main.open_roster()
	if picking:
		main.roster_pick = 0
		main._build_crew_layout()
