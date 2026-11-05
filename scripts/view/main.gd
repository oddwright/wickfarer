extends Node
## Phase 0 entry point: one fight, touch only.
## Owns the fixed-step loop, input, saving and the screen setup.

const SAVE_SLOT := "combat"
const LONG_PRESS := 0.4
const AUTOSAVE_EVERY := 10.0
const MAX_STEPS_PER_FRAME := 5

var combat: Combat
var screen: Dictionary = {}
var layout: HudLayout
var container: SubViewportContainer
var viewport: SubViewport
var world: WorldView
var text: TextLayer

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


func _ready() -> void:
	ContentDB.load_all()
	var errors := ContentDB.validate()
	for e in errors:
		push_error("content: " + e)
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
	_start(_load_or_new())
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _load_or_new() -> Combat:
	var data := SaveService.read(SAVE_SLOT)
	if data.has("combat") and str(data.combat.get("state", "")) == "fighting":
		var c := Combat.from_dict(data.combat)
		paused = true
		pause_reason = "UI_TAP_TO_RESUME"
		return c
	return Combat.create(_fresh_seed())


func _fresh_seed() -> int:
	return int(Time.get_unix_time_from_system()) % 1000000


func _start(c: Combat) -> void:
	combat = c
	selected_weapon = -1
	selected_crew = -1
	floaters.clear()
	flashes.clear()
	world.setup(self)
	text.setup(self)
	if layout:
		_rebuild_layout()


func _on_resize() -> void:
	var size := Vector2i(get_viewport().get_visible_rect().size)
	var next := ScreenManager.compute(size)
	if not screen.is_empty() and next.layout != screen.layout and combat.state == "fighting":
		_pause("UI_FOLD_PAUSE")  # folding or unfolding mid-fight pauses it
	screen = next
	container.stretch_shrink = screen.scale
	container.position = Vector2.ZERO
	container.size = Vector2(screen.native * screen.scale)
	world.make_stars(screen.native)
	_rebuild_layout()


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
		combat.player().weapon_ids.size()
	)


func _pause(reason := "") -> void:
	paused = true
	pause_reason = reason
	_save()


func _save() -> void:
	if combat and combat.state == "fighting":
		SaveService.write(SAVE_SLOT, {"combat": combat.to_dict()})


func _notification(what: int) -> void:
	# Phones don't promise a quit event, so save whenever we lose the screen.
	const LEAVING: Array[int] = [
		NOTIFICATION_APPLICATION_PAUSED,
		NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_WM_CLOSE_REQUEST,
	]
	if what in LEAVING:
		_on_leave()


func _on_leave() -> void:
	if combat and combat.state == "fighting":
		_pause("UI_TAP_TO_RESUME")


# ------------------------------------------------------------------ loop


func _process(delta: float) -> void:
	if combat == null or layout == null:
		return
	if not paused and combat.state == "fighting":
		_acc += minf(delta, 0.25)
		var steps := 0
		while _acc >= Combat.TICK and steps < MAX_STEPS_PER_FRAME:
			combat.tick()
			_on_events(combat.events)
			_acc -= Combat.TICK
			steps += 1
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
	world.queue_redraw()
	text.queue_redraw()


func flash_amount(side: int, room_id: String) -> float:
	return clampf(flashes.get("%d:%s" % [side, room_id], 0.0) / 0.15, 0.0, 1.0)


func _on_events(events: Array) -> void:
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
			"won", "lost":
				SaveService.erase(SAVE_SLOT)


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
		if (event as InputEventKey).keycode == KEY_SPACE:
			_toggle_pause()


func _toggle_pause() -> void:
	if paused:
		paused = false
		pause_reason = ""
	else:
		_pause()


func _tap(window_pos: Vector2, long: bool) -> void:
	var p := Vector2i((window_pos / float(screen.scale)).floor())
	if combat.state != "fighting":
		if layout.again_rect().grow(4).has_point(p):
			paused = false
			pause_reason = ""
			_start(Combat.create(_fresh_seed()))
		return
	var b := layout.button_at(p)
	if not b.is_empty():
		_press_button(b, long)
		return
	var enemy_room := world.room_at(1, p)
	if selected_weapon >= 0 and enemy_room:
		combat.apply({"type": "aim", "weapon": selected_weapon, "room": enemy_room.id})
		selected_weapon = -1
		return
	var c := world.crew_at(0, p)
	if c:
		selected_crew = -1 if selected_crew == c.uid else c.uid
		selected_weapon = -1
		return
	var my_room := world.room_at(0, p)
	if selected_crew >= 0 and my_room:
		combat.apply({"type": "move", "crew": selected_crew, "room": my_room.id})
		selected_crew = -1
		return
	selected_weapon = -1
	selected_crew = -1


func _press_button(b: Dictionary, long: bool) -> void:
	match b.kind:
		"system":
			if long:
				combat.apply({"type": "power_down", "system": b.id})
			else:
				combat.apply({"type": "power_up", "system": b.id})
		"weapon":
			var i := int(b.id)
			if long:
				combat.apply({"type": "aim", "weapon": i, "room": ""})
				selected_weapon = -1
			else:
				selected_weapon = -1 if selected_weapon == i else i
				selected_crew = -1
		"ward":
			combat.apply({"type": "ward_deck", "deck": 1 - combat.player().ward_deck})
		"pause":
			_toggle_pause()
