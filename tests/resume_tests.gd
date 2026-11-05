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


## Drops the app without any leaving notification: only what it already saved
## survives. It is freed at the end of the frame, so it is pointed at a scratch
## folder first, and can't write over the save the next launch reads.
static func _kill(main: Node) -> void:
	main.save_dir = DIR + "/dead"
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.queue_free()


static func _tap_at(main: Node, native: Vector2, long := false) -> void:
	main._tap(native * main.screen.scale, long)


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
	c.paused = false
	c.selected_weapon = -1  # still picked from before the last kill
	var button: Dictionary = c.layout.button("system", "weapons")
	_tap_at(c, Vector2((button.rect as Rect2i).get_center()), true)  # long press: power down
	_tap_at(c, Vector2((c.layout.button("weapon", 0).rect as Rect2i).get_center()))
	var target: Room = c.combat.enemy().rooms[0]
	_tap_at(c, c.world.room_rect(1, target).get_center())
	_check(t, c.selected_weapon == -1, "aiming clears the pick")
	_kill(c)

	var d := _open(t)
	var room_d: Room = d.combat.player().system_room("weapons")
	_check(t, room_d.power == power - 1, "an order is saved the moment it is given")
	_check(t, d.combat.player().weapon_target[0] == target.id, "an aim too")
	_check(t, d.selected_weapon == -1, "with the pick it left, not the one before")
	SaveService.erase("run", DIR)
	d._save()
	_check(t, not FileAccess.file_exists(SaveService.path_for("run", DIR)), "unchanged: no write")
	d._last_save = ""
	d.open_menu("title")
	d.open_menu("options")
	_kill(d)

	var e := _open(t)
	_check(t, e.menu == "options" and e.menu_base == "title", "Options over the title reopens")
	_check(t, not e.world.visible and not e.run_view.visible, "with the game still hidden")
	e.back()
	_check(t, e.menu == "title" and e.run != null, "and Back lands on the title with Continue")
	var old := {"run": e.run.to_dict()}
	_kill(e)
	SaveService.write("run", old, DIR)
	var f := _open(t)
	_check(
		t, f.menu == "title" and f.run != null, "a save from before the ui block opens the title"
	)
	_kill(f)
	_bad_ui_falls_back(t)
	_fixture_reopens(t)
	SaveService.erase("run", DIR)


## A damaged ui block never strands the player or breaks the launch.
static func _bad_ui_falls_back(t: SceneTree) -> void:
	var r := Run.create(3)
	r._start_fight("ashmarket_skiff")
	var bad := [
		{"menu": "options", "menu_base": "options"},
		{"menu": "pause", "menu_base": "title"},
		{"menu": "ship_of_theseus", "menu_base": "pause"},
	]
	for ui: Dictionary in bad:
		SaveService.write("run", {"run": r.to_dict(), "ui": ui}, DIR)
		var m := _open(t)
		_check(t, m.menu == "title", "%s falls back to the title" % ui)
		_kill(m)
	var junk := {"menu": "confirm", "menu_base": "pause", "confirm": 5, "weapon": null}
	junk["music"] = null
	junk["crew"] = "x"
	SaveService.write("run", {"run": r.to_dict(), "ui": junk}, DIR)
	var m := _open(t)
	_check(t, m.menu == "pause" and m.selected_weapon == -1, "junk values are ignored")
	_kill(m)


## A real save with the ui block, kept as a fixture: paused mid-fight on the pause menu.
static func _fixture_reopens(t: SceneTree) -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/run_save_v2_ui.json")
	var f := FileAccess.open(SaveService.path_for("run", DIR), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var m := _open(t)
	_check(t, m.menu == "pause" and m.combat != null, "the ui fixture reopens on the pause menu")
	_check(t, m.combat.state == "fighting" and m.paused, "in its fight, paused")
	_kill(m)
