class_name Roster
extends RefCounted
## The fight's crew controls: the roster panel (open, picking a post, closing),
## Muster, and long press to post a crew member where they stand. A part of Main
## kept in its own file (so it calls Main's own helpers) to keep Main under the
## lint limit. Orders go through Combat.apply.

var main: Node
var open := false  ## the roster is over the fight (and pauses it)
var pick := -1  ## the row whose post is being picked, or -1
var layout: CrewLayout
var paused_before := false  ## the fight's pause state when the roster opened
var view: CrewView  ## draws the roster; it only draws while the roster is open


func _init(main_node: Node) -> void:
	main = main_node


## Adds the roster's view to the pixel world, above the fight and run screens.
func attach(viewport: Node) -> void:
	view = CrewView.new()
	viewport.add_child(view)
	view.setup(main)


## A rank earned this fight floats over the crew member who earned it.
func on_events(events: Array) -> void:
	for e: Dictionary in events:
		if e.type == "skill_up" and int(e.side) == 0:
			var skill := tr(Skills.spec(e.skill).name)
			var label := tr("UI_SKILL_UP") % [skill, tr(Skills.rank_name(int(e.rank)))]
			main._float(0, e.room, label, Pixel.c("v"))


## Tap selects a crew member (tap again to let go); long press posts them.
func tap_crew(c: Crew, long: bool) -> void:
	if long:
		post_here(c)
		return
	main.selected_crew = -1 if main.selected_crew == c.uid else c.uid
	main.selected_weapon = -1
	main.ui_cue("select")


## The crew listed in the roster, top to bottom.
func crew() -> Array[Crew]:
	var out: Array[Crew] = []
	if main.combat:
		out = main.combat.player().alive_crew()
	return out


## The posts the picker offers: each station on the ship, in data/systems.json
## order, then "" for none.
func picks() -> Array[String]:
	var out: Array[String] = []
	if main.combat:
		for sys: String in ContentDB.systems:
			var r: Room = main.combat.player().system_room(sys)
			if r:
				out.append(r.id)
	out.append("")
	return out


## Opens the roster. It pauses the fight; closing it puts the pause back as it was.
func show() -> void:
	var c: Combat = main.combat
	if c == null or c.state != "fighting" or open:
		main.ui_cue("refused")
		return
	main.ui_cue("tap")
	paused_before = main.paused
	main.paused = true
	open = true
	pick = -1
	main.selected_crew = -1
	main.selected_weapon = -1
	rebuild()
	main._show_game(main.menu_base != "title")


## Returns false if the roster wasn't open.
func close() -> bool:
	if not open:
		return false
	open = false
	pick = -1
	main.paused = paused_before
	if not main.paused:
		main.pause_reason = ""
	main._show_game(main.menu_base != "title")
	return true


## Forgets the roster without touching the pause (a new fight starts).
func reset() -> void:
	open = false
	pick = -1


func rebuild() -> void:
	if main.screen.is_empty() or not open:
		return
	var offered: Array[String] = []
	if pick >= 0:
		offered = picks()
	layout = CrewLayout.build(main.screen, crew().size(), offered)


## A HUD button: Crew opens the roster, Muster sends everyone to their posts.
func press(kind: String) -> void:
	if kind == "crew":
		show()
	else:
		muster()


## A tap while the roster is open. Returns false (and does nothing) when it isn't.
func tap(p: Vector2i) -> bool:
	if not open or main.combat == null:
		return false
	var b := layout.button_at(p) if layout else {}
	if b.is_empty():
		return true
	var list := crew()
	match b.kind:
		"post":
			var i := int(b.id)
			pick = -1 if pick == i or i >= list.size() else i
			main.ui_cue("select")
		"pick":
			var ok := pick >= 0 and pick < list.size()
			if ok:
				var room: String = picks()[int(b.id)]
				ok = main.combat.apply({"type": "post", "crew": list[pick].uid, "room": room})
			main.ui_cue("tap" if ok else "refused")
			if ok:
				main._order("post")
			pick = -1
		"muster":
			muster()
			close()
			return true
		"close":
			main.ui_cue("tap")
			close()
			return true
	rebuild()
	return true


## Sends everyone to their posts (from the HUD or the roster). Counts as the
## order for the coach even when everyone is already in place, or its Muster
## step could never finish.
func muster() -> void:
	var ok: bool = main.combat.apply({"type": "muster"})
	main.ui_cue("tap" if ok else "refused")
	main._order("muster")


## Long press on a crew member: where they stand (or are headed) becomes their post.
func post_here(c: Crew) -> void:
	var dest: String = c.path.back() if c.is_moving() else c.room
	if not main.combat.apply({"type": "post", "crew": c.uid, "room": dest}):
		main.ui_cue("refused")
		return
	main.ui_cue("select")
	main.selected_crew = -1
	main._order("post")
	var role := tr(main.combat.player().role_of(c))
	main._float(0, dest, tr("UI_POST_SET") % role, Pixel.c("w"))
