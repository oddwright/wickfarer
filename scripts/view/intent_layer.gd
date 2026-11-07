class_name IntentLayer
extends TextLayer
## The fight's text, plus what the enemy means to do next, so a fight can be
## planned: a seconds tag in each of the player's rooms an enemy gun is aimed at,
## a line per enemy gun under its status lines where the screen has room, and the
## Warden's rule in the message line. Like the rest of the view it only reads the sim.

const TAG_COL := "U"  ## the enemy's aim corners are this red too
const HOLD_COL := "v"


func _draw() -> void:
	super._draw()
	if main == null or main.layout == null or main.combat == null:
		return
	var combat: Combat = main.combat
	if combat.state != "fighting":
		return
	_draw_tags(combat)
	_draw_hold(combat)
	_draw_list(combat, main.layout)


## Seconds until weapon i fires, rounded up, as the player reads a countdown.
static func eta_seconds(foe: Ship, i: int) -> int:
	return ceili(foe.weapon_eta(i))


## One line of the enemy's intent for weapon i.
static func line(combat: Combat, i: int) -> String:
	var foe := combat.enemy()
	var name := TranslationServer.translate(ContentDB.weapons[foe.weapon_ids[i]].name)
	var eta := foe.weapon_eta(i)
	var t := foe.weapon_target[i]
	if eta < 0.0:
		return TranslationServer.translate("UI_INTENT_NO_POWER") % name
	if t == "":
		if bool(CombatAI.tactics(foe.content_id).get("volley", false)):
			return TranslationServer.translate("UI_INTENT_HOLD") % [name, ceili(volley_eta(foe))]
		return TranslationServer.translate("UI_INTENT_IDLE") % name
	var room := room_name(combat.player(), t)
	if eta <= 0.0:
		return TranslationServer.translate("UI_INTENT_FIRING") % [name, room]
	return TranslationServer.translate("UI_INTENT_AIM") % [name, room, ceili(eta)]


## Seconds until a volley captain's last powered gun is charged, when they all fire.
static func volley_eta(foe: Ship) -> float:
	var latest := -1.0
	for i in foe.weapon_ids.size():
		latest = maxf(latest, foe.weapon_eta(i))
	return latest


## A room an enemy gun aims at, named by the system in it (guns only aim at systems).
static func room_name(ship: Ship, room_id: String) -> String:
	var sys := ship.room(room_id).system
	if sys == "":
		return TranslationServer.translate("UI_INTENT_ROOM")
	return TranslationServer.translate(ContentDB.systems[sys].name)


func _draw_tags(combat: Combat) -> void:
	var foe := combat.enemy()
	var me := combat.player()
	var per_room := {}
	for i in foe.weapon_ids.size():
		var t := foe.weapon_target[i]
		if t == "" or foe.weapon_eta(i) < 0.0:
			continue
		var tags: Array = per_room.get(t, [])
		tags.append(tr("UI_INTENT_TAG") % eta_seconds(foe, i))
		per_room[t] = tags
	for room_id: String in per_room:
		var r := me.room(room_id)
		var rr: Rect2i = main.world.room_rect(0, r)
		# A cold room's word sits on the first line; the countdown goes under it.
		var y := rr.position.y + (14 if r.warmth < Ship.COLD else 7)
		_text(Vector2(rr.position.x + 2, y), " ".join(per_room[room_id]), 4.0, Pixel.c(TAG_COL))


## A volley captain holds its guns unaimed; its weapons room shows when they fire.
func _draw_hold(combat: Combat) -> void:
	var foe := combat.enemy()
	if not bool(CombatAI.tactics(foe.content_id).get("volley", false)):
		return
	for t in foe.weapon_target:
		if t != "":
			return  # the volley is aimed: the player's rooms carry the countdown
	var latest := volley_eta(foe)
	var r := foe.system_room("weapons")
	if r == null or latest < 0.0:
		return
	var rr: Rect2i = main.world.room_rect(1, r)
	_text(
		Vector2(rr.position.x + 2, rr.position.y + 7),
		tr("UI_INTENT_TAG") % ceili(latest),
		4.0,
		Pixel.c(HOLD_COL)
	)


func _draw_list(combat: Combat, l: HudLayout) -> void:
	var foe := combat.enemy()
	var n := mini(foe.weapon_ids.size(), l.intent_lines())
	for i in n:
		var y := l.intent_rect.position.y + (i + 1) * HudLayout.INTENT_LINE - 1
		_text(
			Vector2(l.intent_rect.position.x, y),
			line(combat, i),
			4.0,
			Pixel.c("g"),
			HORIZONTAL_ALIGNMENT_RIGHT,
			l.intent_rect.size.x
		)
