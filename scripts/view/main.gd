extends Node
## Entry point: a whole run, touch only.
## Owns the fixed-step loop, input, saving and the screen setup, and switches
## between the fight screen (WorldView + TextLayer), the run screens (RunView)
## and the menus (MenuView). The app opens on the title menu.

const SAVE_SLOT := "run"
const OLD_FIGHT_SLOT := "combat"  ## Phase 0 saved a lone fight here
const LONG_PRESS := 0.4
const AUTOSAVE_EVERY := 10.0
const MAX_STEPS_PER_FRAME := 5

var save_dir := SaveService.DIR  ## tests point this at a scratch folder
var run: Run
var combat: Combat  ## the run's current fight, kept after it ends until Continue
var run_layout: RunLayout
var run_view: RunView
var screen: Dictionary = {}
var layout: HudLayout
var container: SubViewportContainer
var viewport: SubViewport
var world: WorldView
var text: TextLayer
var settings: GameSettings
var feedback: FeedbackDirector
var music_director := MusicDirector.new()
var audio: AudioService
var haptics: Haptics
var menu_view: MenuView
var menu_layout: MenuLayout
var crew_view: CrewView
var crew_layout: CrewLayout
var roster_open := false  ## the crew roster is over the fight (and pauses it)
var roster_pick := -1  ## the roster row whose post is being picked, or -1
## The open menu page: "" (playing), "title", "pause", "options" or "confirm".
var menu := ""
## The page Back returns to: "title" hides the game, "pause" dims it.
var menu_base := ""
var confirm_action := ""  ## what the confirm page asks about: "abandon" or "new_run"

var paused := false
var pause_reason := ""
var selected_weapon := -1
var selected_crew := -1
var floaters: Array = []  ## {text, pos, life, color}
var flashes: Dictionary = {}  ## "side:room" -> seconds left

var _acc := 0.0
var _autosave := 0.0
var _press_pos := Vector2.ZERO
var _press_time := 0
var _pressing := false
var _paused_before_menu := false
var _paused_before_roster := false


func _ready() -> void:
	ContentDB.load_all()
	var errors := ContentDB.validate()
	for e in errors:
		push_error("content: " + e)
	_setup_feedback()
	container = SubViewportContainer.new()
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.canvas_item_default_texture_filter = (
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	)
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	container.add_child(viewport)
	world = WorldView.new()
	viewport.add_child(world)
	text = TextLayer.new()
	viewport.add_child(text)  # text lives in the pixel world, above the art
	run_view = RunView.new()
	viewport.add_child(run_view)
	run_view.setup(self)
	crew_view = CrewView.new()
	viewport.add_child(crew_view)
	crew_view.setup(self)
	menu_view = MenuView.new()
	viewport.add_child(menu_view)  # last, so the menus draw over the game
	menu_view.setup(self)
	get_window().go_back_requested.connect(back)  # Android back button
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	run = _load_saved()
	open_menu("title")


func _setup_feedback() -> void:
	settings = GameSettings.load_or_default(save_dir)
	feedback = FeedbackDirector.new(ContentDB.feedback.get("cues", {}), settings)
	audio = AudioService.new()
	add_child(audio)
	audio.apply_settings(settings)
	haptics = Haptics.new(ContentDB.feedback.get("haptics", {}))
	haptics.strength = settings.haptics


## Plays a UI cue (a tap, a refused order). Safe before _ready, for tests.
func ui_cue(what: String) -> void:
	if feedback:
		feedback.cue("ui." + what)


## The saved run to continue, or null if there is none worth continuing.
func _load_saved() -> Run:
	SaveService.erase(OLD_FIGHT_SLOT, save_dir)
	var data := SaveService.read(SAVE_SLOT, save_dir)
	if data.has("run"):
		var r := Run.from_dict(data.run)
		if not r.state in ["lost", "reach_done"]:
			return r
	return null


## Which run screen is showing: a Run state, or "outcome" for an event's result.
func run_screen() -> String:
	return "outcome" if run.outcome != "" else run.state


func _set_run(r: Run) -> void:
	run = r
	close_menu()
	_enter_screen()


## Call after every run action: shows the right screen and saves.
func _enter_screen() -> void:
	var fighting := run_screen() == "fight"
	_show_game(menu_base != "title")
	if fighting and combat != run.combat:
		_start(run.combat)
	if not fighting:
		combat = null
		layout = null
	_build_run_layout()
	_save()


## The fight and run screens are hidden under the title menu, and dimmed
## under the others.
func _show_game(on: bool) -> void:
	var fighting := run != null and run_screen() == "fight"
	world.visible = on and fighting
	text.visible = on and fighting
	run_view.visible = on and run != null and not fighting
	crew_view.visible = on and fighting and roster_open
	menu_view.visible = menu != ""


func _build_run_layout() -> void:
	if screen.is_empty() or run == null:
		return
	var mode := "next"
	var count := 0
	match run_screen():
		"chart":
			mode = "chart"
		"event":
			mode = "event"
			count = (run.event().get("choices", []) as Array).size()
		"store":
			mode = "store"
			count = run.store_items().size() + 1  # and Leave
	run_layout = RunLayout.build(screen, run.chart, mode, count)


func _fresh_seed() -> int:
	return int(Time.get_unix_time_from_system()) % 1000000


func _start(c: Combat) -> void:
	combat = c
	paused = false
	pause_reason = ""
	selected_weapon = -1
	selected_crew = -1
	roster_open = false
	roster_pick = -1
	floaters.clear()
	flashes.clear()
	if feedback:
		feedback.reset_fight()
	world.setup(self)
	text.setup(self)
	if not screen.is_empty():
		_rebuild_layout()


func _on_resize() -> void:
	var size := window_size()
	var next := ScreenManager.compute(size, settings.ui_size if settings else 0)
	var mid_fight := combat != null and combat.state == "fighting"
	if not screen.is_empty() and next.layout != screen.layout and mid_fight:
		_pause("UI_FOLD_PAUSE")  # folding or unfolding mid-fight pauses it
	screen = next
	container.stretch_shrink = screen.scale
	container.position = Vector2.ZERO
	container.size = Vector2(screen.native * screen.scale)
	world.make_stars(screen.native)
	if combat:
		_rebuild_layout()
	_build_run_layout()
	_build_menu_layout()
	_build_crew_layout()


func _rebuild_layout() -> void:
	var systems: Array[String] = []
	for s in HudLayout.SYSTEM_ORDER:
		if combat.player().system_room(s):
			systems.append(s)
	layout = HudLayout.build(
		screen,
		world.ship_frames[0],
		world.ship_frames[1],
		systems,
		combat.player().weapon_ids.size(),
		world.ship_used[0],
		world.ship_used[1]
	)


func _pause(reason := "") -> void:
	if menu != "":
		_paused_before_menu = true  # a fold or a trip away while in the menu still counts
	if roster_open:
		_paused_before_roster = true  # and in the roster
	paused = true
	pause_reason = reason
	_save()


func _save() -> void:
	if run == null:
		return
	if run.state in ["lost", "reach_done"]:
		SaveService.erase(SAVE_SLOT, save_dir)
	else:
		SaveService.write(SAVE_SLOT, {"run": run.to_dict()}, save_dir)


func _notification(what: int) -> void:
	# Phones don't promise a quit event, so save whenever we lose the screen.
	const LEAVING: Array[int] = [
		NOTIFICATION_APPLICATION_PAUSED,
		NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_WM_CLOSE_REQUEST,
	]
	const BACK: Array[int] = [
		NOTIFICATION_APPLICATION_RESUMED,
		NOTIFICATION_APPLICATION_FOCUS_IN,
	]
	if what in LEAVING:
		_on_leave()
	elif what in BACK and audio:
		audio.suspend(false)


func _on_leave() -> void:
	if audio:
		audio.suspend(true)
		haptics.stop()
	if combat and combat.state == "fighting":
		_pause("UI_TAP_TO_RESUME")
	else:
		_save()


# ------------------------------------------------------------------ loop


func _process(delta: float) -> void:
	if screen.is_empty() or feedback == null:
		return
	feedback.update(delta)
	haptics.update(delta)
	if run != null and menu == "":
		_tick_game(delta)
	_play_feedback()
	world.queue_redraw()
	text.queue_redraw()
	crew_view.queue_redraw()
	run_view.queue_redraw()
	menu_view.queue_redraw()


func _tick_game(delta: float) -> void:
	if combat and layout and not paused and combat.state == "fighting" and not feedback.frozen():
		_acc += minf(delta, 0.25)
		var steps := 0
		while _acc >= Combat.TICK and steps < MAX_STEPS_PER_FRAME:
			combat.tick()
			_on_events(combat.events)
			_acc -= Combat.TICK
			steps += 1
			if feedback.frozen():
				break  # hit-stop: hold the next tick back until it ends
		_autosave += delta
		if _autosave >= AUTOSAVE_EVERY:
			_autosave = 0.0
			_save()
	for f in floaters:
		f.life -= delta
		f.pos.y -= delta * 10.0
	floaters = floaters.filter(func(f: Dictionary) -> bool: return f.life > 0.0)
	for k in flashes.keys():
		flashes[k] -= delta
		if flashes[k] <= 0.0:
			flashes.erase(k)


func _play_feedback() -> void:
	for f in feedback.drain():
		if f.sound != "":
			audio.play(f.sound, f.priority)
		if f.haptic != "":
			haptics.play(f.haptic, f.priority)
		if f.duck:
			audio.duck()
	world.shake = feedback.shake_offset()
	audio.hush = FeedbackDirector.hush_closeness(run)
	audio.muffle = music_muffled()
	audio.set_music_state(music_state())


## Which music fits the screen: see "states" in data/feedback.json. A fight
## picks its own stage (MusicDirector).
func music_state() -> String:
	if not _in_run():
		return "chart"
	match run_screen():
		"fight":
			return "engage" if combat == null else music_director.state_for(combat)
		"event", "outcome":
			return "event"
		"store":
			return "store"
		"lost":
			return "defeat"
	return "chart"


## A paused fight keeps its music, muffled, so coming back doesn't restart it.
func music_muffled() -> bool:
	return _in_run() and run_screen() == "fight" and paused


## A run is on screen (not hidden under the title menu).
func _in_run() -> bool:
	return run != null and menu_base != "title"


func flash_amount(side: int, room_id: String) -> float:
	var a := clampf(flashes.get("%d:%s" % [side, room_id], 0.0) / 0.15, 0.0, 1.0)
	return a * (0.35 if settings and settings.reduce_flashing else 1.0)


func _on_events(events: Array) -> void:
	if feedback:
		feedback.on_sim_events(events, combat)
	for e: Dictionary in events:
		match e.type:
			"hit":
				_float(e.side, e.room, "-%d" % e.damage, Pixel.c("U"))
				flashes["%d:%s" % [e.side, e.room]] = 0.15
			"miss":
				_float(e.side, e.room, tr("UI_MISS"), Pixel.c("h"))
			"ward_hit", "ward_block":
				_float(e.side, e.room, tr("UI_WARDED"), Pixel.c("j"))
			"crew_died":
				if e.side == 0 and selected_crew == e.uid:
					selected_crew = -1
			"skill_up":
				if e.side == 0:
					var label := (
						tr("UI_SKILL_UP")
						% [tr(Skills.spec(e.skill).name), tr(Skills.rank_name(int(e.rank)))]
					)
					_float(0, e.room, label, Pixel.c("v"))
			"won", "lost":
				_save()


func _float(side: int, room_id: String, s: String, col: Color) -> void:
	var r := combat.ships[side].room(room_id)
	if r == null:
		return
	var rr := world.room_rect(side, r)
	floaters = floaters.slice(-12)  # never let a burst of hits flood the screen
	var stack := 0
	for f in floaters:
		if f.life > 0.6 and absf(f.pos.x - (rr.get_center().x - 30)) < 1.0:
			stack += 1
	floaters.append(
		{
			"text": s,
			"pos": Vector2(rr.get_center().x - 30, rr.position.y - 7 * mini(stack, 2)),
			"life": 1.0,
			"color": col
		}
	)


# ------------------------------------------------------------------ input


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_press_pos = mb.position
				_press_time = Time.get_ticks_msec()
			elif _pressing:
				_pressing = false
				var held := (Time.get_ticks_msec() - _press_time) / 1000.0
				_tap(_press_pos, held >= LONG_PRESS)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_tap(mb.position, true)  # right click stands in for a long press on desktop
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			back()
		elif key == KEY_SPACE and combat and menu == "" and not roster_open:
			_toggle_pause()  # pause only means something in a fight


func _toggle_pause() -> void:
	if paused:
		paused = false
		pause_reason = ""
	else:
		_pause()


func _tap(window_pos: Vector2, long: bool) -> void:
	var p := Vector2i((window_pos / float(screen.scale)).floor())
	if menu != "":
		_tap_menu(p)
		return
	if run == null:
		return
	if roster_open and combat:
		_tap_roster(p)
		return
	if MenuLayout.menu_button(screen.native).grow(2).has_point(p):
		ui_cue("tap")
		open_menu("pause")
		return
	if combat == null:
		_tap_run(p)
		return
	if combat.state != "fighting":
		if layout.again_rect().grow(4).has_point(p):
			ui_cue("tap")
			paused = false
			pause_reason = ""
			run.finish_fight()
			_enter_screen()
		return
	var b := layout.button_at(p)
	if not b.is_empty():
		_press_button(b, long)
		return
	var enemy_room := world.room_at(1, p)
	if selected_weapon >= 0 and enemy_room:
		var aimed := combat.apply({"type": "aim", "weapon": selected_weapon, "room": enemy_room.id})
		ui_cue("aim" if aimed else "refused")
		selected_weapon = -1
		return
	var c := world.crew_at(0, p)
	if c:
		_tap_crew(c, long)
		return
	var my_room := world.room_at(0, p)
	if selected_crew >= 0 and my_room:
		var moved := combat.apply({"type": "move", "crew": selected_crew, "room": my_room.id})
		ui_cue("tap" if moved else "refused")
		selected_crew = -1
		return
	selected_weapon = -1
	selected_crew = -1


func _press_button(b: Dictionary, long: bool) -> void:
	match b.kind:
		"system":
			var cmd := "power_down" if long else "power_up"
			var ok := combat.apply({"type": cmd, "system": b.id})
			ui_cue(cmd if ok else "refused")
		"weapon":
			var i := int(b.id)
			if long:
				combat.apply({"type": "aim", "weapon": i, "room": ""})
				selected_weapon = -1
				ui_cue("power_down")
			else:
				selected_weapon = -1 if selected_weapon == i else i
				selected_crew = -1
				ui_cue("select")
		"ward":
			combat.apply({"type": "ward_deck", "deck": 1 - combat.player().ward_deck})
			ui_cue("tap")
		"pause":
			_toggle_pause()
			ui_cue("tap")
		"crew":
			ui_cue("tap")
			open_roster()
		"muster":
			ui_cue("tap" if combat.apply({"type": "muster"}) else "refused")


# ------------------------------------------------------------------ crew


## Tap selects a crew member (tap again to let go); long press posts them.
func _tap_crew(c: Crew, long: bool) -> void:
	if long:
		_post_here(c)
		return
	selected_crew = -1 if selected_crew == c.uid else c.uid
	selected_weapon = -1
	ui_cue("select")


## Long press on a crew member: where they stand (or are headed) becomes their post.
func _post_here(c: Crew) -> void:
	var dest: String = c.path.back() if c.is_moving() else c.room
	if not combat.apply({"type": "post", "crew": c.uid, "room": dest}):
		ui_cue("refused")
		return
	ui_cue("select")
	selected_crew = -1
	_float(0, dest, tr("UI_POST_SET") % tr(combat.player().role_of(c)), Pixel.c("w"))


## The crew listed in the roster, top to bottom.
func roster_crew() -> Array[Crew]:
	var out: Array[Crew] = []
	if combat:
		out = combat.player().alive_crew()
	return out


## The posts the picker offers: each station on the ship, in data/systems.json
## order, then "" for none.
func roster_picks() -> Array[String]:
	var out: Array[String] = []
	if combat:
		for sys: String in ContentDB.systems:
			var r := combat.player().system_room(sys)
			if r:
				out.append(r.id)
	out.append("")
	return out


## Opens the roster. It pauses the fight; closing it puts the pause back as it was.
func open_roster() -> void:
	if combat == null or combat.state != "fighting" or roster_open:
		return
	_paused_before_roster = paused
	paused = true
	roster_open = true
	roster_pick = -1
	selected_crew = -1
	selected_weapon = -1
	_build_crew_layout()
	_show_game(menu_base != "title")


func close_roster() -> void:
	if not roster_open:
		return
	roster_open = false
	roster_pick = -1
	paused = _paused_before_roster
	if not paused:
		pause_reason = ""
	_show_game(menu_base != "title")


func _build_crew_layout() -> void:
	if screen.is_empty() or not roster_open:
		return
	var picks: Array[String] = []
	if roster_pick >= 0:
		picks = roster_picks()
	crew_layout = CrewLayout.build(screen, roster_crew().size(), picks)


func _tap_roster(p: Vector2i) -> void:
	var b := crew_layout.button_at(p) if crew_layout else {}
	if b.is_empty():
		return
	var crew := roster_crew()
	match b.kind:
		"post":
			var i := int(b.id)
			roster_pick = -1 if roster_pick == i or i >= crew.size() else i
			ui_cue("select")
		"pick":
			var picks := roster_picks()
			var ok := roster_pick >= 0 and roster_pick < crew.size()
			if ok:
				var cmd := {"type": "post", "crew": crew[roster_pick].uid, "room": picks[int(b.id)]}
				ok = combat.apply(cmd)
			ui_cue("tap" if ok else "refused")
			roster_pick = -1
		"muster":
			ui_cue("tap" if combat.apply({"type": "muster"}) else "refused")
			close_roster()
			return
		"close":
			ui_cue("tap")
			close_roster()
			return
	_build_crew_layout()


func _tap_run(p: Vector2i) -> void:
	if run_layout == null:
		return
	var b := run_layout.button_at(p)
	if b.is_empty():
		return
	match b.kind:
		"beacon":
			if not run.jump(str(b.id)):
				ui_cue("refused")
				return
			ui_cue("jump")
		"choice":
			if not run.choose(int(b.id)):
				ui_cue("refused")
				return
			ui_cue("choose")
		"store":
			var items := run.store_items()
			var i := int(b.id)
			var done := run.buy(items[i]) if i < items.size() else run.leave_store()
			if not done:
				ui_cue("refused")
				return
			ui_cue("buy" if i < items.size() else "tap")
		"next":
			if run.state in ["lost", "reach_done"] and run.outcome == "":
				ui_cue("tap")
				_set_run(Run.create(_fresh_seed()))
				return
			if not run.read_outcome():
				return
			ui_cue("tap")
	_enter_screen()


# ------------------------------------------------------------------ menus


## The buttons on a title, pause or confirm page, top to bottom.
func menu_items(page: String) -> Array[String]:
	var out: Array[String] = []
	match page:
		"title":
			if run != null:
				out.append("continue")
			out.append_array(["new_run", "options"])
			if can_quit():
				out.append("quit")
		"pause":
			out.assign(["resume", "options"])
			if not run_over():
				out.append("abandon")
			out.append("to_title")
		"confirm":
			out.assign(["yes", "no"])
	return out


## A lost or finished run waiting on its ending screen; nothing to continue.
func run_over() -> bool:
	return run != null and run.state in ["lost", "reach_done"]


## iOS apps must not quit themselves (Apple rejects it); Android and desktop may.
func can_quit() -> bool:
	return not OS.has_feature("ios") and not OS.has_feature("web")


func open_menu(page: String) -> void:
	if page == "title" or page == "pause":
		if menu == "" and page == "pause":
			_paused_before_menu = paused
			paused = true
		menu_base = page
	menu = page
	_build_menu_layout()
	_show_game(menu_base != "title")
	_save()


func close_menu() -> void:
	menu = ""
	menu_base = ""
	menu_layout = null
	_show_game(true)


func _build_menu_layout() -> void:
	if screen.is_empty() or menu == "":
		return
	menu_layout = MenuLayout.build(screen, menu, menu_items(menu))


## Android back, Escape on desktop: up one level, and out of the app from the title.
func back() -> void:
	match menu:
		"":
			if roster_open:
				close_roster()
			elif run != null:
				open_menu("pause")
		"options", "confirm":
			open_menu(menu_base)
		"pause":
			_resume()
		"title":
			if can_quit():
				_quit()


func _resume() -> void:
	paused = _paused_before_menu
	close_menu()


func _tap_menu(p: Vector2i) -> void:
	if menu_layout == null:
		return
	var b := menu_layout.button_at(p)
	if b.is_empty():
		return
	ui_cue("tap")
	if menu == "options":
		_press_option(b)
		return
	match str(b.id):
		"continue":
			_continue()
		"new_run":
			if run == null:
				_new_run()
			else:
				_confirm("new_run")
		"options":
			open_menu("options")
		"quit":
			_quit()
		"resume":
			_resume()
		"abandon":
			_confirm("abandon")
		"to_title":
			if run_over():
				run = null  # its save is already gone; the title offers no Continue
				combat = null
				layout = null
				run_layout = null
			open_menu("title")
		"yes":
			if confirm_action == "abandon":
				_abandon()
			else:
				_new_run()
		"no":
			open_menu(menu_base)


func _confirm(what: String) -> void:
	confirm_action = what
	open_menu("confirm")


func _continue() -> void:
	close_menu()
	_enter_screen()
	if combat and combat.state == "fighting":
		_pause("UI_TAP_TO_RESUME")  # never drop a player straight back into a live fight
	else:
		paused = false
		pause_reason = ""


func _new_run() -> void:
	close_menu()
	_set_run(Run.create(_fresh_seed()))


## Ends the run for good: the save goes, and the title has no Continue.
func _abandon() -> void:
	SaveService.erase(SAVE_SLOT, save_dir)
	run = null
	combat = null
	layout = null
	run_layout = null
	paused = false
	pause_reason = ""
	open_menu("title")


func _quit() -> void:
	_save()
	get_tree().quit()


func _press_option(b: Dictionary) -> void:
	var size_before := settings.ui_size
	match b.kind:
		"less", "more":
			var dir := -1 if b.kind == "less" else 1
			if not option_can_step(str(b.id), dir):
				return  # the tap cue has played; the greyed button says why
			settings.adjust(str(b.id), dir)
			_preview(str(b.id))
		"toggle":
			settings.adjust(str(b.id), 1)
			_preview(str(b.id))
		"defaults":
			settings.reset()
		"back":
			open_menu(menu_base)
			return
	if settings.ui_size != size_before:
		_on_resize()  # rescales the canvas and rebuilds every layout, this page too
	audio.apply_settings(settings)
	haptics.strength = settings.haptics
	settings.save(save_dir)


## Whether a - or + tap on the options screen would change anything. UI size
## only steps away from auto when the scale really moves, so a tap that can't
## fit is refused instead of saving a step that does nothing.
func option_can_step(id: String, dir: int) -> bool:
	if id != "ui_size":
		var v := settings.value(id)
		return v > 0.0 if dir < 0 else v < 1.0
	var next := settings.ui_size + dir
	if next < GameSettings.UI_SIZE_MIN or next > GameSettings.UI_SIZE_MAX:
		return false
	if absi(next) < absi(settings.ui_size):
		return true  # back toward auto always works, even where the step did nothing
	return ScreenManager.compute(window_size(), next).scale != screen.scale


## A stepper row's value on the options screen, by row id.
func stepper_text(id: String) -> String:
	return ui_size_text() if id == "ui_size" else ""


## The UI size control's value: the current scale, and "auto" when it is the default.
func ui_size_text() -> String:
	var t := tr("UI_SIZE_SCALE") % int(screen.get("scale", 1))
	if settings.ui_size == 0:
		t += " " + tr("UI_SIZE_AUTO")
	return t.to_upper()


func window_size() -> Vector2i:
	return Vector2i(get_viewport().get_visible_rect().size)


## Lets the player feel or hear the level they just picked.
func _preview(id: String) -> void:
	match id:
		"haptics":
			haptics.strength = settings.haptics
			feedback.cue("ui.preview_haptics")
		"SFX":
			audio.apply_settings(settings)
			feedback.cue("ui.preview_sfx")
