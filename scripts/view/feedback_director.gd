class_name FeedbackDirector
extends RefCounted
## Turns what happened (sim events, taps) into feel: which sound, which haptic,
## how much shake and hit-stop. Pure logic, so it runs in the headless tests;
## main.gd hands the results to AudioService and Haptics.
##
## Cue names, looked up in data/feedback.json "cues":
## - sim events: "<type>.us" when it happened to the player's ship, "<type>.them"
##   otherwise ("hit.us" = we were hit, "fire.us" = we fired). A fire event first
##   tries "<type>.<who>.<weapon family>" so each family can sound different.
##   "won" and "lost" have no side.
## - taps: "ui.<what>" from main.gd.
## A cue that isn't in the table is simply silent, so new events need no code here.

const MAX_TRAUMA := 1.0
const TRAUMA_DECAY := 1.6  ## per second
const SHAKE_PIXELS := 3.0  ## native pixels at full trauma (15 screen pixels at 5x)
const KICK_DECAY := 14.0
const MAX_KICK := 2.5  ## native pixels: a burst of hits mustn't throw the picture off screen
const MAX_HITSTOP := ContentDB.MAX_HITSTOP
const HITSTOP_REST := 0.3  ## no new hit-stop this soon after the last one ends
const DANGER_HULL := 0.3
const HUSH_NEAR := 3.0  ## columns: the Hush starts eating the music this far behind us

var cues: Dictionary = {}
var settings: GameSettings
var trauma := 0.0
var kick := Vector2.ZERO
var hitstop := 0.0
var danger_played := false

## What to play this frame; main.gd takes them with drain().
var _out: Array[Dictionary] = []
var _clock := 0.0
var _last_played: Dictionary = {}  ## cue -> clock
var _hitstop_ended := -INF


func _init(cue_table: Dictionary = {}, game_settings: GameSettings = null) -> void:
	cues = cue_table
	settings = game_settings if game_settings else GameSettings.new()


## Call once per sim tick with that tick's events.
func on_sim_events(events: Array, combat: Combat) -> void:
	for e: Dictionary in events:
		cue(cue_for(e, combat), e)
	if combat and not danger_played and combat.state == "fighting":
		var me := combat.player()
		if me.hull > 0 and float(me.hull) / me.max_hull <= DANGER_HULL:
			danger_played = true
			cue("danger")


## The most specific cue name in the table for a sim event, or "".
func cue_for(e: Dictionary, combat: Combat) -> String:
	var type := str(e.get("type", ""))
	if not e.has("side"):
		return type if cues.has(type) else ""
	if type == "weapon_ready" and combat and _aimed(combat, e):
		return ""  # it fires by itself this tick; the shot is the cue
	var who := "us" if int(e.side) == 0 else "them"
	var base := "%s.%s" % [type, who]
	if e.has("weapon") and combat:
		var s := combat.ships[int(e.side)]
		var i := int(e.weapon)
		if i >= 0 and i < s.weapon_ids.size():
			var family := str(ContentDB.weapons[s.weapon_ids[i]].get("family", ""))
			if cues.has(base + "." + family):
				return base + "." + family
	return base if cues.has(base) else ""


static func _aimed(combat: Combat, e: Dictionary) -> bool:
	var s := combat.ships[int(e.side)]
	var i := int(e.get("weapon", -1))
	return i >= 0 and i < s.weapon_target.size() and s.weapon_target[i] != ""


## Fires a cue by name. Returns true if it played (it may be on cooldown).
func cue(id: String, e: Dictionary = {}) -> bool:
	if id == "" or not cues.has(id):
		return false
	var c: Dictionary = cues[id]
	var cooldown := float(c.get("cooldown", 0.0))
	if _clock - float(_last_played.get(id, -INF)) < cooldown:
		return false
	_last_played[id] = _clock
	var priority := int(c.get("priority", 0))
	(
		_out
		. append(
			{
				"sound": str(c.get("sound", "")),
				"haptic": str(c.get("haptic", "")),
				"priority": priority,
				"duck": bool(c.get("duck", false)),
			}
		)
	)
	_add_shake(float(c.get("shake", 0.0)), float(c.get("kick", 0.0)), e)
	_add_hitstop(float(c.get("hitstop", 0.0)))
	return true


func _add_shake(amount: float, kick_px: float, e: Dictionary) -> void:
	trauma = minf(MAX_TRAUMA, trauma + amount)
	if kick_px > 0.0:
		# Our ship sits on the left: a hit on it shoves the view left first, so
		# the player feels where it came from.
		var dir := -1.0 if int(e.get("side", 0)) == 0 else 1.0
		kick = (kick + Vector2(dir * kick_px, 0.0)).limit_length(MAX_KICK)


func _add_hitstop(amount: float) -> void:
	if amount <= 0.0 or not settings.hitstop:
		return
	if hitstop <= 0.0 and _clock - _hitstop_ended < HITSTOP_REST:
		return  # two big hits close together: freezing again reads as lag
	hitstop = minf(MAX_HITSTOP, maxf(hitstop, amount))


## Advance by real frame time (this is the view: wall time is fine here).
func update(delta: float) -> void:
	_clock += delta
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	kick = kick.move_toward(Vector2.ZERO, KICK_DECAY * delta)
	if hitstop > 0.0:
		hitstop = maxf(0.0, hitstop - delta)
		if hitstop == 0.0:
			_hitstop_ended = _clock


## Is the sim frozen for hit-stop right now?
func frozen() -> bool:
	return hitstop > 0.0


## Shake in whole native pixels: never sub-pixel, never rotated, so the grid stays crisp.
func shake_offset() -> Vector2i:
	var amount := trauma * trauma * SHAKE_PIXELS * settings.shake
	# Smooth, repeatable wobble rather than white noise: it reads as a jolt, not jitter.
	var wobble := Vector2(sin(_clock * 47.0), sin(_clock * 61.0 + 1.7)) * amount
	var total := (wobble + kick * settings.shake).limit_length(SHAKE_PIXELS + 1.0)
	return Vector2i(roundi(total.x), roundi(total.y))


## Starts a fresh fight's one-off cues (the low-hull warning).
func reset_fight() -> void:
	danger_played = false
	trauma = 0.0
	kick = Vector2.ZERO
	hitstop = 0.0


## 0 when the Hush is far behind, 1 when it is on our beacon.
static func hush_closeness(run: Run) -> float:
	if run == null or run.chart == null:
		return 0.0
	var gap := float(run.here().col) - run.hush
	return clampf(1.0 - gap / HUSH_NEAR, 0.0, 1.0)


func drain() -> Array[Dictionary]:
	var out := _out
	_out = []
	return out
