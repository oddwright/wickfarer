extends SceneTree
## Screenshot one screen at a given window size (needs a display; use xvfb-run).
## godot --path . -s tools/shot.gd -- <width> <height> <out.png> [ticks] [screen] [ui size]
## screen is fight (default), chart, event, event:<event id>, store, refit, reach_done, won or lost,
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
		"refit":
			run.state = "refit"
		"lost", "won", "reach_done":
			run.state = which
		"fight":
			run._start_fight("ashmarket_cutter")
	if which in ["title", "pause", "options", "confirm"]:
		run._start_fight("ashmarket_cutter")
	main._set_run(run)
	if main.combat:
		_play_fight(main.combat)
	match which:
		"title", "pause":
			main.open_menu(which)
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
