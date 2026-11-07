class_name ItemCard
extends RefCounted
## What a store option is, for the card a store page shows once it is tapped:
## its name, a sentence on what it is for, its numbers one to a line, and what a
## second tap does (or why it can't). Built from the content, so a new gun,
## module or system needs only its name and desc strings.
## A card is {title, note, about, lines: [[text, palette key]], hint, ok}; {} when
## the option has nothing to show (an empty slot, Back).

const GAIN := "H"  ## green: what a module gives
const COST := "u"  ## orange: what it takes
const PLAIN := "g"


static func build(run: Run, option: String) -> Dictionary:
	if option in Run.STORE_ITEMS:
		return _store_item(run, option)
	if option == "stoke":
		return _stoke(run)
	if option in Run.REFIT_SYSTEMS:
		return _refit(run, option)
	var item := Market.item_at(run, option)
	if item.is_empty():
		return {}
	return _gear(run, option, item)


static func _card(title: String, about: String) -> Dictionary:
	return {"title": title, "note": "", "about": about, "lines": [], "hint": "", "ok": true}


static func _store_item(run: Run, option: String) -> Dictionary:
	var c := _card(_t("UI_STORE_" + option.to_upper()), _t("UI_STORE_%s_DESC" % option.to_upper()))
	var p := run.price(option)
	c.note = "%d %s" % [p, _t("UI_SCRAP")]
	if option == "repair":
		c.lines.append([_t("UI_CARD_HAVE_HULL") % [run.ship.hull, run.ship.max_hull], PLAIN])
	else:
		c.lines.append([_t("UI_CARD_HAVE_LIGHT") % run.light, PLAIN])
	if option == "repair" and run.ship.hull >= run.ship.max_hull:
		_refuse(c, _t("UI_CARD_FULL_HULL"))
	elif run.scrap < p:
		_refuse(c, _t("UI_CARD_SHORT") % [p - run.scrap, _t("UI_SCRAP")])
	else:
		c.hint = _t("UI_CARD_BUY")
	return c


static func _refit(run: Run, sys: String) -> Dictionary:
	var spec: Dictionary = ContentDB.systems[sys]
	var c := _card(_t(str(spec.name)), _t(str(spec.get("desc", ""))))
	var room := run.ship.system_room(sys)
	if room == null:
		_refuse(c, _t("UI_CARD_NONE"))
		return c
	c.lines.append([_t("UI_CARD_LEVEL") % [room.level, Ship.max_level(sys)], PLAIN])
	var p := run.refit_price(sys)
	if p < 0:
		_refuse(c, _t("UI_CARD_MAXED"))
		return c
	c.note = "%d %s" % [p, _t("UI_SCRAP")]
	if run.scrap < p:
		_refuse(c, _t("UI_CARD_SHORT") % [p - run.scrap, _t("UI_SCRAP")])
	else:
		c.hint = _t("UI_CARD_REFIT")
	return c


static func _stoke(run: Run) -> Dictionary:
	var spec: Dictionary = ContentDB.systems.ember
	var c := _card(_t("UI_STOKE"), _t(str(spec.get("desc", ""))))
	c.lines.append([_t("UI_CARD_REACTOR") % run.ship.reactor, PLAIN])
	c.lines.append([_t("UI_CARD_HAVE_LIGHT") % run.light, PLAIN])
	var p := run.stoke_price()
	if p < 0:
		_refuse(c, _t("UI_STOKE_MAXED"))
		return c
	c.note = "%d %s" % [p, _t("UI_LIGHT")]
	if run.light < p:
		_refuse(c, _t("UI_CARD_SHORT") % [p - run.light, _t("UI_LIGHT")])
	else:
		c.hint = _t("UI_CARD_STOKE")
	return c


## A gun or module, for sale, fitted or in the hold.
static func _gear(run: Run, option: String, item: Dictionary) -> Dictionary:
	var e := Gear.entry(item)
	var c := _card(_t(str(e.get("name", ""))), _t(str(e.get("desc", ""))))
	var gun: bool = item.get("kind") == "weapon"
	c.lines = _gun_lines(e) if gun else _module_lines(item)
	var kind := _t("UI_CARD_GUN" if gun else "UI_CARD_MODULE")
	var in_hold := option.begins_with("hold")
	var p := Market.price(run, item)
	if option.begins_with("buy"):
		c.note = "%s, %d %s" % [kind, p, _t("UI_SCRAP")]
		c.hint = _t("UI_CARD_BUY")
	else:
		c.note = "%s, %s" % [kind, _t("UI_IN_HOLD" if in_hold else "UI_FITTED")]
		c.hint = _t("UI_CARD_FIT" if in_hold else "UI_CARD_UNFIT")
		if run.selling:
			c.hint = _t("UI_CARD_SELL") % Market.sell_price(item)
	var why := Market.refusal(run, option)
	if why == "UI_CARD_SHORT":
		_refuse(c, _t(why) % [p - run.scrap, _t("UI_SCRAP")])
	elif why != "":
		_refuse(c, _t(why))
	return c


static func _gun_lines(e: Dictionary) -> Array:
	var out: Array = []
	out.append([_t("UI_CARD_POWER") % int(e.get("power", 0)), PLAIN])
	out.append([_t("UI_CARD_CHARGE") % _num(float(e.get("charge", 0.0))), PLAIN])
	var shots := int(e.get("shots", 1))
	out.append([_t("UI_CARD_SHOT") if shots == 1 else _t("UI_CARD_SHOTS") % shots, PLAIN])
	if int(e.get("hull_damage", 0)) > 0:
		out.append([_t("UI_CARD_HULL") % int(e.hull_damage), PLAIN])
	if e.has("chill"):
		out.append([_t("UI_CARD_CHILL") % int(e.chill), PLAIN])
	if int(e.get("system_damage", 0)) > 0:
		out.append([_t("UI_CARD_SYSTEM") % int(e.system_damage), PLAIN])
	if int(e.get("crew_damage", 0)) > 0:
		out.append([_t("UI_CARD_CREW") % int(e.crew_damage), PLAIN])
	var fire := float(e.get("fire_chance", 0.0))
	if fire > 0.0:
		out.append([_t("UI_CARD_FIRE") % int(round(fire * 100.0)), PLAIN])
	var wards := "UI_CARD_BLOCKED"
	if e.get("strips_ward", false):
		wards = "UI_CARD_STRIPS"
	elif e.get("pierces_ward", false):
		wards = "UI_CARD_PIERCES"
	out.append([_t(wards), GAIN if wards != "UI_CARD_BLOCKED" else COST])
	return out


## The same words as the old one-line summary, a line each: gains, then costs.
static func _module_lines(item: Dictionary) -> Array:
	var out: Array = []
	for fx: Array in GearText.module_effects(item):
		out.append([fx[0], GAIN if fx[1] == "gain" else COST])
	return out


static func _refuse(c: Dictionary, why: String) -> void:
	c.hint = why
	c.ok = false


static func _num(v: float) -> String:
	return String.num(v, 1).trim_suffix(".0")


static func _t(key: String) -> String:
	return GearText.tr_key(key)
