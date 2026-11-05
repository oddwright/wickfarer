class_name Tutorial
extends RefCounted
## The coach: the training flight's lessons and the one-time tips, from data/tutorial.json.
## It only reads the run, the fight and what the player has selected, and never sends
## orders, so the sim stays the same with or without it.
## - A lesson starts the first time its screen shows in a training run and ends when
##   the player leaves that screen. Each step ends when its "done" condition holds, so
##   doing things early just skips steps.
## - Progress is kept in its own save slot, written on every change, so a phone that
##   kills the app comes back on the same step. Steps rebuild from what is on screen;
##   the worst a kill can cost is redoing one small action.
## - A tip shows once ever, the first time its moment comes, in any run.

const SLOT := "tutorial"
const TUTORIAL_VERSION := 1
const TRAINING_REACH := "training"
## Every condition a step can wait for; "aimed:<slot>" and "did:<order>" take an argument.
const CONDITIONS: Array[String] = ["left", "running", "paused", "aimed", "did"]
## "weapon_selected:<slot>" names the gun; "crew_selected" is any crew member.
const WHENS: Array[String] = ["weapon_selected", "crew_selected"]
const TARGETS: Array[String] = [
	"",
	"beacons",
	"choices",
	"next",
	"pause",
	"ward",
	"crew",
	"rooms",
	"weapon",
	"system",
	"enemy_room"
]
const ORDERS: Array[String] = ["aim", "move", "power_up", "power_down", "ward"]
const TIP_MOMENTS: Array[String] = ["fire_start", "ward_block", "cold", "low_hull", "dark_jump"]
## Run screens a lesson can belong to (Main.run_screen(), and "fight" while it is on).
const SCREENS: Array[String] = [
	"chart", "event", "outcome", "store", "fight", "reach_done", "won", "lost"
]

var done := false  ## finished or skipped training at least once: New Run skips it from then on
var coaching := true  ## off once skipped; a training run then plays without lessons
var lessons_done: Array[String] = []
var lesson := ""  ## the lesson on screen, or ""
var step := 0
var tips_seen: Array[String] = []
var tip := ""  ## the tip on screen, or ""
var tip_screen := ""
var tip_paused := false  ## the fight has been paused since the tip showed
## What to show now: {text, target, hold, tip}; empty when the coach is quiet.
var display: Dictionary = {}
var dirty := false  ## progress changed since the last save

var _did: Dictionary = {}  ## orders given since the step began (not saved: redo one tap)
## Tip moments from sim events, kept until a tip can show (a lesson or another tip may
## be talking) and dropped when the fight ends.
var _moments: Dictionary = {}


static func lessons() -> Array:
	return ContentDB.tutorial.get("lessons", [])


static func tips() -> Array:
	return ContentDB.tutorial.get("tips", [])


static func is_training(run: Run) -> bool:
	return run != null and bool(run.reach().get("training", false))


## Lessons run in a training run until the player skips them.
func active(run: Run) -> bool:
	return coaching and is_training(run)


## The current step holds the fight's clock until it is done.
func holds() -> bool:
	return bool(display.get("hold", false))


## A fresh training flight: every lesson again, tips stay seen.
func start_training() -> void:
	coaching = true
	lessons_done.clear()
	_set_lesson("")
	display = {}
	dirty = true


func skip() -> void:
	coaching = false
	done = true
	_set_lesson("")
	display = {}
	dirty = true


## The player gave an order (see ORDERS), on a system or weapon if detail is set.
## A step can wait for "did:power_down" (any system) or "did:power_down:mend".
func on_order(what: String, detail := "") -> void:
	_did[what] = true
	if detail != "":
		_did[what + ":" + detail] = true


func on_events(events: Array) -> void:
	for e: Dictionary in events:
		match str(e.get("type", "")):
			"fire_start":
				if int(e.side) == 0:
					_moments["fire_start"] = true
			"ward_block":
				if int(e.side) == 1:  # the player's shot hit the enemy's ward
					_moments["ward_block"] = true


## Call once a frame while no menu is open. ctx: {screen, paused, weapon, crew, run,
## combat}; screen is Main.run_screen(), or "fight_over" once a fight has ended.
## Returns true when a tip has just appeared (Main pauses the fight for it).
func update(ctx: Dictionary) -> bool:
	var run: Run = ctx.get("run")
	_update_tip(ctx)
	if active(run):
		_update_lesson(ctx)
	elif lesson != "":
		_set_lesson("")  # the training run ended or was left; its lesson goes with it
	var fresh := false
	if lesson == "" and tip == "":
		fresh = _maybe_tip(ctx)
	if str(ctx.screen) != "fight":
		_moments.clear()
	_refresh_display(ctx)
	return fresh


func _update_lesson(ctx: Dictionary) -> void:
	var screen := str(ctx.screen)
	if lesson != "":
		var l := _lesson(lesson)
		if l.is_empty() or str(l.screen) != screen:
			_finish_lesson(l)
	if lesson == "":
		for l: Dictionary in lessons():
			if _can_start(l, screen):
				_set_lesson(str(l.id))
				if screen in Run.ENDINGS:
					done = true  # the flight is over either way; the next New Run is real
				break
	if lesson == "":
		return
	var steps: Array = _lesson(lesson).steps
	while step < steps.size() and _met(str(steps[step].done), ctx):
		step += 1
		_did.clear()
		dirty = true
	if step >= steps.size():
		_finish_lesson(_lesson(lesson))


func _can_start(l: Dictionary, screen: String) -> bool:
	if lessons_done.has(str(l.id)) or str(l.screen) != screen:
		return false
	var after := str(l.get("after", ""))
	return after == "" or lessons_done.has(after)


func _finish_lesson(l: Dictionary) -> void:
	if not l.is_empty():
		lessons_done.append(str(l.id))
	_set_lesson("")


func _set_lesson(id: String) -> void:
	lesson = id
	step = 0
	_did.clear()
	dirty = true


func _lesson(id: String) -> Dictionary:
	for l: Dictionary in lessons():
		if str(l.id) == id:
			return l
	return {}


func _met(cond: String, ctx: Dictionary) -> bool:
	var arg := cond.get_slice(":", 1)
	match cond.get_slice(":", 0):
		"running":
			return not bool(ctx.paused)
		"paused":
			return bool(ctx.paused)
		"did":
			return _did.has(cond.substr(4))
		"aimed":
			var c: Combat = ctx.get("combat")
			var i := int(arg)
			return (
				c != null
				and i < c.player().weapon_target.size()
				and (c.player().weapon_target[i] != "")
			)
	return false  # "left" ends with the lesson


func _when(cond: String, ctx: Dictionary) -> bool:
	match cond.get_slice(":", 0):
		"weapon_selected":
			var want := cond.get_slice(":", 1)
			var got := int(ctx.get("weapon", -1))
			return got >= 0 and (want == "" or got == int(want))
		"crew_selected":
			return int(ctx.get("crew", -1)) >= 0
	return false


# ------------------------------------------------------------------ tips


func _update_tip(ctx: Dictionary) -> void:
	if tip == "":
		return
	var screen := str(ctx.screen)
	if screen != tip_screen:
		tip = ""
	elif screen == "fight":
		if bool(ctx.paused):
			tip_paused = true
		elif tip_paused:
			tip = ""  # the player read it and pressed play
	if tip == "":
		dirty = true


func _maybe_tip(ctx: Dictionary) -> bool:
	for t: Dictionary in tips():
		var id := str(t.id)
		if tips_seen.has(id) or not _moment(str(t.on), ctx):
			continue
		tips_seen.append(id)
		_moments.erase(str(t.on))
		tip = id
		tip_screen = str(ctx.screen)
		tip_paused = bool(ctx.paused)
		dirty = true
		return true
	return false


func _moment(on: String, ctx: Dictionary) -> bool:
	var screen := str(ctx.screen)
	var run: Run = ctx.get("run")
	var c: Combat = ctx.get("combat")
	if on == "dark_jump":
		# A jump lands on a story more often than the chart; the note lives until the
		# next action clears the run's messages.
		return run != null and run.messages.has("UI_DARK_JUMP")
	if screen != "fight" or c == null:
		return false
	match on:
		"cold":
			for r in c.player().rooms:
				if r.warmth < Ship.COLD:
					return true
			return false
		"low_hull":
			return c.player().hull * 3 <= c.player().max_hull
	return _moments.has(on)


func _tip(id: String) -> Dictionary:
	for t: Dictionary in tips():
		if str(t.id) == id:
			return t
	return {}


# ------------------------------------------------------------------ display


func _refresh_display(ctx: Dictionary) -> void:
	display = {}
	if tip != "":
		var t := _tip(tip)
		var go_on := "pause" if tip_screen == "fight" else ""
		display = {"text": str(t.get("text", "")), "target": go_on, "hold": false, "tip": true}
		return
	if lesson == "":
		return
	var steps: Array = _lesson(lesson).steps
	if step >= steps.size():
		return
	var s: Dictionary = steps[step]
	display = {
		"text": str(s.text),
		"target": str(s.get("target", "")),
		"hold": bool(s.get("hold", false)),
		"tip": false
	}
	var then: Dictionary = s.get("then", {})
	if not then.is_empty() and _when(str(then.when), ctx):
		display.text = str(then.text)
		display.target = str(then.get("target", ""))


# ------------------------------------------------------------------ save


## A player from before the coach (a run or settings already saved, but no tutorial
## file) has learned the game, so New Run doesn't send them into training.
static func load_or_default(dir := SaveService.DIR) -> Tutorial:
	var saved := SaveService.read(SLOT, dir)
	var t := from_dict(saved)
	if saved.is_empty():
		for slot in ["run", GameSettings.SLOT]:
			if FileAccess.file_exists(SaveService.path_for(slot, dir)):
				t.done = true
	return t


func save(dir := SaveService.DIR) -> bool:
	dirty = false
	return SaveService.write(SLOT, to_dict(), dir)


func to_dict() -> Dictionary:
	return {
		"tutorial_version": TUTORIAL_VERSION,
		"done": done,
		"coaching": coaching,
		"lessons_done": Array(lessons_done),
		"lesson": lesson,
		"step": step,
		"tips_seen": Array(tips_seen),
		"tip": tip,
		"tip_screen": tip_screen,
		"tip_paused": tip_paused,
	}


## Missing or damaged fields fall back to a new player's, and lessons or tips that
## an update removed are dropped, so an old file never strands the coach.
static func from_dict(d: Dictionary) -> Tutorial:
	ContentDB.load_all()
	var t := Tutorial.new()
	t.done = d.get("done") if d.get("done") is bool else false
	t.coaching = d.get("coaching") if d.get("coaching") is bool else true
	for id: Variant in _list(d.get("lessons_done")):
		if not t._lesson(str(id)).is_empty():
			t.lessons_done.append(str(id))
	for id: Variant in _list(d.get("tips_seen")):
		t.tips_seen.append(str(id))
	var l := t._lesson(str(d.get("lesson", "")))
	if not l.is_empty():
		t.lesson = str(l.id)
		var at: Variant = d.get("step")
		t.step = clampi(int(at) if at is float or at is int else 0, 0, l.steps.size())
	if not t._tip(str(d.get("tip", ""))).is_empty():
		t.tip = str(d.tip)
		t.tip_screen = str(d.get("tip_screen", ""))
		t.tip_paused = d.get("tip_paused") if d.get("tip_paused") is bool else false
	return t


static func _list(v: Variant) -> Array:
	return v if v is Array else []
