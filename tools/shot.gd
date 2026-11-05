extends SceneTree
## Screenshot a mid-fight frame at a given screen size (needs a display; use xvfb-run).
## godot --path . -s tools/shot.gd -- <width> <height> <out.png> [ticks]

var frames := 0
var main: Node
var out := ""
var ticks := 500


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var size := Vector2i(int(a[0]), int(a[1]))
	out = a[2]
	if a.size() > 3:
		ticks = int(a[3])
	DisplayServer.window_set_size(size)
	root.size = size
	SaveService.erase("combat")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		main.combat = Combat.create(4242)
		main._start(main.combat)
		main.combat.apply({"type": "aim", "weapon": 0, "room": "weapons"})
		main.combat.apply({"type": "aim", "weapon": 1, "room": "weapons"})
		main.combat.apply({"type": "move", "crew": 3, "room": "galley"})
		for i in ticks:
			main.combat.tick()
			main._on_events(main.combat.events)
		main.combat.apply({"type": "move", "crew": 1, "room": "ember"})
		for i in 12:
			main.combat.tick()
		main.selected_weapon = 1
	if frames == 10:
		var img := root.get_texture().get_image()
		img.save_png(out)
		print("saved ", out, " ", img.get_size())
		quit()
	return false
