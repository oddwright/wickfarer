extends RefCounted
## Cold-start resume checks for tests/run_tests.gd: the app is killed with no
## warning (as iOS does to a swiped-away app) and opened again on the same save.

const J = preload("res://scripts/core/json_util.gd")
const MAIN = preload("res://scripts/view/main.gd")
const DIR := "user://test_resume"


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


static func _open(t: SceneTree) -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_dir = DIR
	t.root.size = Vector2i(2400, 1080)
	t.root.add_child(main)
	return main


## Removes the app without any leaving notification: only what it already saved survives.
static func _kill(main: Node) -> void:
	main.queue_free()


static func _state(main: Node) -> String:
	return J.canonical(main.run.to_dict())


static func flow(t: SceneTree) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	SaveService.erase("run", DIR)
	var a := _open(t)
	_check(t, a.menu == "title", "with no save the app opens on the title")
	a._new_run()
	var r: Run = a.run
	r._start_fight("ashmarket_skiff")
	a._set_run(r)
	for i in 30:
		a._process(0.1)
	a.selected_weapon = 0
	a.open_menu("pause")
	a.open_menu("options")
	var fight_time: float = a.combat.time()
	var state := _state(a)
	var music: Dictionary = a.music_director.to_dict(a.combat)
	_kill(a)

	var b := _open(t)
	_check(t, b.menu == "options" and b.menu_base == "pause", "reopens on the same menu page")
	_check(t, b.combat != null and b.combat.time() == fight_time, "in the same fight, same tick")
	_check(t, _state(b) == state, "with the run exactly as it was")
	_check(t, b.selected_weapon == 0 and b.paused, "the weapon still picked, the fight paused")
	_check(t, b.music_director.to_dict(b.combat) == music, "and the music on the same stage")
	_check(t, b.world.visible and b.menu_view.visible, "the fight shows dimmed under the menu")
	b.back()
	b.back()
	_check(t, b.menu == "" and not b.paused, "Back twice resumes the fight")
	for i in 30:
		b._process(0.1)
	var ran: float = b.combat.time()
	_check(t, ran > fight_time, "the resumed fight runs")
	_kill(b)

	var c := _open(t)
	_check(t, c.menu == "" and c.combat != null, "a kill mid-fight reopens in the fight")
	_check(t, c.paused and c.pause_reason == "UI_TAP_TO_RESUME", "paused, waiting for a tap")
	var lost: float = ran - c.combat.time()
	_check(t, lost >= 0.0 and lost <= MAIN.AUTOSAVE_EVERY + 0.001, "losing at most %.1fs" % lost)
	var room: Room = c.combat.player().system_room("weapons")
	var power: int = room.power
	_check(t, c._order({"type": "power_down", "system": "weapons"}), "an order is taken")
	_kill(c)

	var d := _open(t)
	var room_d: Room = d.combat.player().system_room("weapons")
	_check(t, room_d.power == power - 1, "an order is saved the moment it is given")
	SaveService.erase("run", DIR)
	d._save()
	_check(t, not FileAccess.file_exists(SaveService.path_for("run", DIR)), "unchanged: no write")
	d._last_save = ""
	d.open_menu("title")
	_kill(d)

	var e := _open(t)
	_check(t, e.menu == "title" and e.run != null, "left on the title, reopens on it with Continue")
	var old := {"run": e.run.to_dict()}
	_kill(e)
	SaveService.write("run", old, DIR)
	var f := _open(t)
	_check(
		t, f.menu == "title" and f.run != null, "a save from before the ui block opens the title"
	)
	_kill(f)
	SaveService.erase("run", DIR)
