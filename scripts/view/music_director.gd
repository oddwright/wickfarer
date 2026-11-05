class_name MusicDirector
extends RefCounted
## Picks the fight's music state from the fight itself (states in data/feedback.json):
##   engage        drums, bass and strings: the enemy is on the scope
##   engage_theme  + the theme, once the first shot lands (or after THEME_AFTER)
##   engage_full   + brass and taiko, once the damage mounts (or after FULL_AFTER)
##   kill          their hull is low and ours isn't: up a key, four on the floor
##   danger        our hull is low: half-time, a heartbeat for a kick
##   victory, defeat
## Hull never comes back mid-fight, so a fight only climbs these stages; the
## escalation flags never drop, so the music doesn't flap back and forth.

const THEME_AFTER := 15.0  ## seconds before the theme comes in even if nobody hits
const FULL_AFTER := 45.0  ## seconds before the full band comes in regardless
const FULL_ENEMY_HULL := 0.6  ## their hull fraction that brings in the full band
const FULL_HULL_LOST := 0.25  ## or this much of our max hull lost in this fight
const DANGER_HULL := FeedbackDirector.DANGER_HULL  ## our hull: danger music and heartbeat
const KILL_HULL := 0.3  ## their hull: the kill window

var _combat: Combat
var _start_hull: Array[int] = [0, 0]
var _theme := false
var _full := false


func state_for(combat: Combat) -> String:
	if combat != _combat:
		_begin(combat)
	if combat.state != "fighting":
		return "victory" if combat.state == "won" else "defeat"
	var me := combat.player()
	var them := combat.enemy()
	var mine := float(me.hull) / me.max_hull
	var theirs := float(them.hull) / them.max_hull
	if mine <= DANGER_HULL:
		return "danger"
	if theirs <= KILL_HULL:
		return "kill"
	var t := combat.time()
	var hit := me.hull < _start_hull[0] or them.hull < _start_hull[1]
	_theme = _theme or hit or t >= THEME_AFTER
	var lost := float(_start_hull[0] - me.hull) / me.max_hull
	var heat := theirs <= FULL_ENEMY_HULL or lost >= FULL_HULL_LOST or _burning(me)
	_full = _full or heat or t >= FULL_AFTER
	if _full:
		return "engage_full"
	return "engage_theme" if _theme else "engage"


func _begin(combat: Combat) -> void:
	_combat = combat
	_start_hull = [combat.player().hull, combat.enemy().hull]
	# A fight that is already underway (resumed from a save) keeps its theme; its
	# starting hulls are lost, so damage counts from the resume.
	_theme = combat.time() > 0.0
	_full = combat.time() >= FULL_AFTER


static func _burning(ship: Ship) -> bool:
	for r in ship.rooms:
		if r.fire > 0.0:
			return true
	return false
