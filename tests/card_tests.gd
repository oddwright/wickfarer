extends RefCounted
## Item cards, the tap-to-look store flow and the star chart's key, for
## tests/run_tests.gd. Each takes the runner, whose check() records the result.

const GEAR_TESTS = preload("res://tests/gear_tests.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


## Every piece of gear the content has, and every store and refit option, gets a
## card with a name, a sentence, its numbers and what a second tap does.
static func every_option_has_a_card(t: SceneTree) -> void:
	var r: Run = GEAR_TESTS._in_store(3)
	var bad: Array[String] = []
	for id: String in ContentDB.modules:
		r.stock = [{"kind": "module", "id": id}]
		bad.append_array(_card_problems(r, "buy:0", "module " + id))
	for id: String in ContentDB.weapons:
		if ContentDB.weapons[id].has("price"):
			r.stock = [{"kind": "weapon", "id": id}]
			bad.append_array(_card_problems(r, "buy:0", "gun " + id))
	for option in r.store_items():
		bad.append_array(_card_problems(r, option, option))
	r.state = "refit"
	for option in r.refit_options():
		if option != "back":
			bad.append_array(_card_problems(r, option, option))
	_check(t, bad.is_empty(), "every option has a full card: %s" % [bad.slice(0, 4)])
	_check(t, ItemCard.build(r, "back").is_empty(), "Back has no card")
	r.state = "modules"
	_check(t, ItemCard.build(r, "mod:0").is_empty(), "an empty slot has no card")
	var mod: Dictionary = ContentDB.modules.gyre_vanes
	var keep: String = mod.desc
	mod.erase("desc")
	_check(t, GEAR_TESTS._has(ContentDB.validate(), "gyre_vanes desc"), "a module needs a desc")
	mod.desc = keep


static func _card_problems(r: Run, option: String, what: String) -> Array[String]:
	var c := ItemCard.build(r, option)
	var out: Array[String] = []
	for f: String in ["title", "about", "hint"]:
		var s := str(c.get(f, ""))
		if s == "" or s.begins_with("UI_") or s.ends_with("_DESC"):
			out.append("%s has no %s" % [what, f])
	if (c.get("lines", []) as Array).is_empty():
		out.append("%s has no numbers" % what)
	return out


## A card says why a second tap would fail, in the player's terms.
static func cards_explain_refusals(t: SceneTree) -> void:
	var r: Run = GEAR_TESTS._in_store(3)
	r.stock = [{"kind": "weapon", "id": "heavy_rivet"}]
	r.state = "wares"
	r.scrap = 5
	var c := ItemCard.build(r, "buy:0")
	_check(t, not c.ok and str(c.hint).contains("50"), "short of scrap: says how much more")
	r.state = "store"
	r.scrap = 500
	r.ship.hull = r.ship.max_hull
	_check(t, not ItemCard.build(r, "repair").ok, "a whole hull can't be repaired")
	r.ship.hull -= 1
	_check(t, ItemCard.build(r, "repair").ok, "a dented one can")


## First tap looks, second acts; paging acts at once; gear moves close the card
## so the next piece in that slot gets its own look.
static func tap_to_look(t: SceneTree) -> void:
	var r: Run = GEAR_TESTS._in_store(3)
	var f := StoreFocus.new()
	_check(t, f.tap(r, "wares"), "paging acts on the first tap")
	_check(t, not f.tap(r, "repair") and f.current(r) == "repair", "a first tap opens the card")
	_check(t, f.tap(r, "repair") and f.current(r) == "repair", "a second tap acts, card stays")
	_check(t, not f.tap(r, "light") and f.current(r) == "light", "another option moves the card")
	r.state = "wares"
	_check(t, f.current(r) == "", "a new page has no card open")
	_check(t, not f.tap(r, "buy:0"), "a ware opens its card")
	_check(t, f.tap(r, "buy:0"), "a second tap buys it")
	r.store_action("buy:0")
	_check(t, f.current(r) != "buy:0" or r.stock.is_empty(), "the next ware needs its own look")
	r.state = "guns"
	r.ship.weapon_ids.resize(1)
	_check(t, not f.tap(r, "wpn:0"), "the last gun opens its card")
	var c := ItemCard.build(r, "wpn:0")
	_check(t, not c.ok and c.hint == GearText.tr_key("UI_CARD_LAST_GUN"), "it says why it stays")
	_check(t, f.tap(r, "wpn:0") and f.current(r) == "wpn:0", "a refused tap keeps the card")
	r.state = "store"
	f.tap(r, "repair")
	r.at = "elsewhere"
	_check(t, f.current(r) == "", "the next store opens with no card")
	var again: Run = GEAR_TESTS._in_store(3)
	f.tap(again, "repair")
	again = GEAR_TESTS._in_store(3)
	_check(t, f.current(again) == "", "a new run opens with no card")


## Beacons show what the player knows of them, and the key fits every screen
## (RunLayout.problems checks it sits on the canvas, off the fold and clear of beacons).
static func chart_key(t: SceneTree, screens: Dictionary) -> void:
	var r := Run.create(5)
	var start := r.chart.node(r.at)
	_check(t, ChartKey.icon_for(r, start) == "you", "the ship's beacon shows the ship")
	_check(t, ChartKey.icon_for(r, r.chart.node(r.chart.gate_id())) == "gate", "the Gate shows")
	for n in r.chart.nodes:
		if n.kind == "store":
			_check(t, ChartKey.icon_for(r, n) == "store", "a store shows before a visit")
			break
	var hidden := 0
	for n in r.chart.nodes:
		if n.kind in ["fight", "event", "empty"] and ChartKey.icon_for(r, n) != "unknown":
			hidden += 1
	_check(t, hidden == 0, "what waits at other beacons stays unknown")
	var missing: Array[String] = []
	for name: String in screens:
		var l := RunLayout.build(screens[name], r.chart, "chart")
		if l.key.size() != ChartKey.ENTRIES.size():
			missing.append(name)
	_check(t, missing.is_empty(), "the whole key fits: %s" % [missing])
