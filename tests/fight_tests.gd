extends RefCounted
## Rents and the Ember flare, for tests/run_tests.gd (kept here so that file
## stays under the lint limit). Each takes the runner, whose check() records it.

const J = preload("res://scripts/core/json_util.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


static func _ticks(c: Combat, n: int) -> Array:
	var seen := []
	for i in n:
		c.tick()
		seen.append_array(c.events)
	return seen


static func _has(events: Array, type: String, side := -1) -> bool:
	for e: Dictionary in events:
		if e.type == type and (side < 0 or int(e.side) == side):
			return true
	return false


## A fight where the player's ship can't dodge or block, so every shot lands.
static func _open_fight(seed_value := 3) -> Combat:
	var c := Combat.create(seed_value)
	var me := c.player()
	me.power_down("helm")
	me.power_down("wards")
	me.ward_layers = 0
	return c


## The enemy's guns lose their power, so a test's hull counts stay put.
static func _disarm(c: Combat) -> void:
	while c.enemy().power_down("weapons"):
		pass


## Lands one shot from the enemy's gun on a player room, with its rent chance forced.
static func _shoot(c: Combat, weapon: String, room: String, rent_chance: float) -> void:
	var w: Dictionary = ContentDB.weapons[weapon]
	var old: Variant = w.get("rent_chance", null)
	w.rent_chance = rent_chance
	c.events.clear()
	c._resolve({"owner": 1, "weapon": weapon, "slot": 0, "target": room, "t": 0.0, "total": 1.0})
	if old == null:
		w.erase("rent_chance")
	else:
		w.rent_chance = old


static func rents_tear_and_drain(t: SceneTree) -> void:
	var c := _open_fight()
	var me := c.player()
	var hull := me.hull
	_shoot(c, "heavy_rivet", "galley", 1.0)
	var galley := me.room("galley")
	_check(t, galley.rent == 100.0, "a hit that rolls a rent tears the room open")
	_check(t, _has(c.events, "rent_open", 0), "and says so")
	_check(t, me.hull == hull - 2, "the hit still does its hull damage")
	_shoot(c, "torch_lance", "hold", 1.0)
	_check(t, me.room("hold").rent > 0.0, "any gun with a rent chance can tear")
	_shoot(c, "frost_needle", "cells", 1.0)
	_check(t, me.room("cells").rent == 0.0, "a gun that can't hurt the hull never tears")
	# Same room, torn and whole: the rent pulls the warmth right out.
	var a := _open_fight()
	var b := _open_fight()
	a.player().room("galley").rent = 100.0
	_ticks(a, 200)
	_ticks(b, 200)
	var torn := a.player().room("galley").warmth
	_check(t, torn < b.player().room("galley").warmth - 20.0, "a rent drains its room's warmth")
	_check(t, torn < Ship.COLD, "ten seconds of rent leaves even the room by the Ember cold")
	_check(
		t,
		a.player().room("ember").warmth < b.player().room("ember").warmth,
		"and pulls down the room next door"
	)
	# The void takes the air: a fire in a torn, empty room dies down instead of growing.
	var f := _open_fight()
	var hold := f.player().room("hold")
	hold.fire = 50.0
	hold.rent = 100.0
	_ticks(f, 20)
	_check(t, hold.fire < 50.0, "a rent starves a fire")


static func crew_seal_rents(t: SceneTree) -> void:
	var c := _open_fight()
	var me := c.player()
	_disarm(c)
	me.hull = me.max_hull - 3
	var helm := me.room("helm")
	helm.rent = 100.0
	helm.damage = 1.0
	_ticks(c, 20)
	_check(t, helm.damage == 1.0, "crew seal a rent before they repair the room")
	_check(t, helm.rent < 100.0, "crew in a torn room seal it")
	var events := _ticks(c, 400)
	_check(t, helm.rent == 0.0, "until it is shut")
	_check(t, _has(events, "rent_sealed", 0), "and say so")
	_check(t, me.hull >= me.max_hull - 3 + Ship.RENT_HULL, "a sealed rent plates a hull point back")
	var full := _open_fight()
	_disarm(full)
	full.player().room("helm").rent = 100.0
	_ticks(full, 400)
	_check(t, full.player().hull == full.player().max_hull, "plating never goes past full hull")
	# Nobody in the room: the rent stays open.
	var empty := _open_fight()
	empty.player().room("galley").rent = 100.0
	_ticks(empty, 40)
	_check(t, empty.player().room("galley").rent == 100.0, "a rent needs crew to seal it")
	me.room("galley").rent = 100.0
	me.recover_after_fight()
	_check(t, me.room("galley").rent == 0.0, "rents are sealed between fights")


static func flare_burns_then_cracks(t: SceneTree) -> void:
	var f := Ship.flare_data()
	var c := _open_fight()
	var me := c.player()
	var calm := _open_fight()
	for x in [c, calm]:
		x.apply({"type": "aim", "weapon": 0, "room": "weapons"})
	_check(t, me.can_flare(), "a fresh Ember can flare")
	_check(t, c.apply({"type": "flare"}), "the flare order is taken")
	_check(t, not c.apply({"type": "flare"}), "but not twice")
	var lit := _ticks(c, 1)
	_ticks(calm, 1)
	_check(t, _has(lit, "flare", 0), "the flare is seen on the next tick")
	_ticks(c, 59)
	_ticks(calm, 59)
	_check(
		t, me.weapon_charge[0] > calm.player().weapon_charge[0] + 1.0, "a flare charges guns faster"
	)
	_check(
		t,
		me.room("hold").warmth > calm.player().room("hold").warmth + 5.0,
		"and warms the whole ship"
	)
	var ember := me.system_room("ember")
	_check(t, ember.damage == 0.0, "the Ember holds while it burns")
	var after := _ticks(c, int(float(f.seconds) / Combat.TICK) - 60 + 1)
	_check(t, me.flare_time == 0.0, "the flare burns for its seconds")
	_check(t, ember.damage > 0.0 and _has(after, "flare_spent", 0), "then the Ember cracks")
	_check(t, me.available_power() < calm.player().available_power(), "costing power")
	_check(t, not me.can_flare(), "and it rests before it can flare again")
	ember.damage = 0.0
	me.flare_cool = 0.0
	_check(t, me.can_flare(), "once rested and patched it can flare again")
	ember.damage = float(ember.level)
	_check(t, not me.can_flare(), "a broken Ember can't flare")
	ember.damage = 0.0
	me.flare()
	me.recover_after_fight()
	_check(t, me.flare_time == 0.0 and me.can_flare(), "every fight starts with a rested Ember")
	var maw := Ship.from_content("hush_maw", 1)
	_check(t, not maw.can_flare(), "a hull with no Ember never flares")


static func enemies_use_them(t: SceneTree) -> void:
	var flared := false
	var sealed := false
	for seed_value in range(1, 13):
		var c := Combat.create(seed_value, "tallow_wren", "ashmarket_cutter")
		c.apply({"type": "aim", "weapon": 0, "room": "weapons"})
		c.apply({"type": "aim", "weapon": 1, "room": "weapons"})
		c.enemy().room("stores").rent = 100.0
		for i in 2400:
			if c.state != "fighting":
				break
			c.tick()
			for e: Dictionary in c.events:
				flared = flared or (e.type == "flare" and int(e.side) == 1)
				sealed = sealed or (e.type == "rent_sealed" and int(e.side) == 1)
	_check(t, flared, "enemy captains flare their Ember")
	_check(t, sealed, "enemy crew go and seal a rent")


static func resume_mid_flare(t: SceneTree) -> void:
	var a := _open_fight(77)
	a.apply({"type": "aim", "weapon": 0, "room": "weapons"})
	a.player().room("galley").rent = 60.0
	_ticks(a, 30)
	a.apply({"type": "flare"})
	_ticks(a, 40)
	var b := Combat.from_dict(JSON.parse_string(J.s(a.to_dict())))
	_check(t, b.player().flare_time == a.player().flare_time, "a save keeps the flare's burn")
	_check(t, b.player().room("galley").rent == a.player().room("galley").rent, "and the rent")
	_ticks(a, 300)
	_ticks(b, 300)
	_check(t, J.canonical(a.to_dict()) == J.canonical(b.to_dict()), "a flaring, torn fight resumes")


static func content_is_checked(t: SceneTree) -> void:
	_check(t, ContentDB.validate().is_empty(), "rent and flare content is valid")
	var keep_w: Dictionary = ContentDB.weapons.duplicate(true)
	var keep_s: Dictionary = ContentDB.systems.duplicate(true)
	var weapon_cases := {
		"rent_chance must be a number from 0 to 1": ["rivet_gun", 1.5],
		"rent_chance must be a number": ["heavy_rivet", "x"],
		"only a gun that hurts the hull": ["frost_needle", 0.2],
	}
	for want: String in weapon_cases:
		ContentDB.weapons = keep_w.duplicate(true)
		ContentDB.weapons[weapon_cases[want][0]].rent_chance = weapon_cases[want][1]
		_check(t, _has_error(ContentDB.validate(), want), "caught: %s" % want)
	ContentDB.weapons = keep_w
	var flare_cases := {
		"needs a flare block": func(f: Dictionary) -> void: f.clear(),
		"flare seconds must be a number above 0": func(f: Dictionary) -> void: f.seconds = 0,
		"flare warmth must be a number above 0": func(f: Dictionary) -> void: f.warmth = "hot",
		"rest at least as long": func(f: Dictionary) -> void: f.cooldown = 2,
	}
	for want: String in flare_cases:
		ContentDB.systems = keep_s.duplicate(true)
		flare_cases[want].call(ContentDB.systems.ember.flare)
		if ContentDB.systems.ember.flare.is_empty():
			ContentDB.systems.ember.erase("flare")
		_check(t, _has_error(ContentDB.validate(), want), "caught: %s" % want)
	ContentDB.systems = keep_s


static func _has_error(errors: Array[String], part: String) -> bool:
	for e in errors:
		if part in e:
			return true
	return false


## The enemy's status line in the top bar must clear the buttons there (Crew,
## Muster, Flare and, in a siege, Kindle) for every enemy hull on every screen.
static func foe_line_clears_buttons(t: SceneTree, screens: Dictionary) -> void:
	if TextLayer.glyph_index.is_empty():
		TextLayer.glyph_index = JSON.parse_string(
			FileAccess.get_file_as_string("res://art/font_3x5.json")
		)
	var bad: Array[String] = []
	for name: String in screens:
		var scr: Dictionary = screens[name]
		var l := HudLayout.build(scr, Vector2i(120, 60), Vector2i(120, 60), [], 2)
		if l.kind == "tall":
			continue  # Tall gives the enemy's lines the top bar to itself
		var left := 0
		for b in l.buttons:
			var r: Rect2i = b.rect
			if r.position.y < HudLayout.BAR_H:
				left = maxi(left, r.end.x + 2)
		for id: String in ContentDB.ships:
			if ContentDB.ships[id].get("siege_only", false):
				continue
			var line := (
				"%s   %s %d/%d"
				% [
					TranslationServer.translate(str(ContentDB.ships[id].name)),
					TranslationServer.translate("UI_HULL"),
					99,
					99
				]
			)
			var right := l.native.x - 34
			if right - TextLayer.text_width(line.to_upper()) < left:
				bad.append("%s on %s" % [id, name])
	_check(t, bad.is_empty(), "the enemy's name and hull clear the top-bar buttons: %s" % [bad])


static func fixtures_load(t: SceneTree) -> void:
	for v in [8, 9]:
		var raw: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://tests/fixtures/run_save_v%d.json" % v)
		)
		var r := Run.from_dict(SaveService.upgrade(raw).data.run)
		var ship := r.combat.player() if r.combat else r.ship
		if v == 8:
			_check(t, ship.flare_time == 0.0 and ship.can_flare(), "a v8 ship starts unflared")
		else:
			_check(t, ship.flare_time > 0.0, "the v9 fixture is caught mid-flare")
			_check(t, ship.room("galley").rent > 0.0, "with a rent open")
