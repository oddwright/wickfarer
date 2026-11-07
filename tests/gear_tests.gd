extends RefCounted
## Gear checks for tests/run_tests.gd: modules and their trade-offs, Chill guns,
## the store's Wares, Modules and Guns pages, gear from fights and events, and
## saves that keep all of it. Each takes the runner, whose check() records the result.

const J = preload("res://scripts/core/json_util.gd")
const MAIN = preload("res://scripts/view/main.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


static func _has(errors: Array[String], part: String) -> bool:
	for e in errors:
		if e.contains(part):
			return true
	return false


static func _item(kind: String, id: String) -> Dictionary:
	return {"kind": kind, "id": id}


## The most buttons each store page can show, for the layout checks.
static func page_sizes() -> Dictionary:
	var slots := 0
	var mounts := 0
	for id in ShipRoster.playable():
		var s := Ship.from_content(id, 0)
		slots = maxi(slots, s.module_slots)
		mounts = maxi(mounts, s.weapon_slots)
	return {
		"store": Run.create(1).store_options().size(),
		"refit": Run.REFIT_SYSTEMS.size() + 2,
		"wares": GearCheck.MAX_STOCK + 1,
		"modules": slots + Run.HOLD_SIZE + 2,
		"guns": mounts + Run.HOLD_SIZE + 2,
	}


static func _in_store(seed_value: int, unlocked: Array[String] = []) -> Run:
	var r := Run.create(seed_value, "tallow_wren", "reach_1", 0, unlocked)
	r.scrap = 500
	Market.open(r)
	return r


## Every module pays for its gain, and fitting one changes the ship the way it says.
static func modules_fit(t: SceneTree) -> void:
	for id: String in ContentDB.modules:
		var m: Dictionary = ContentDB.modules[id]
		var ok: bool = (
			not (m.gain as Dictionary).is_empty() and not (m.cost as Dictionary).is_empty()
		)
		_check(t, ok, "module %s has a gain and a cost" % id)
	var s := Ship.from_content("tallow_wren", 0)
	var power := s.available_power()
	_check(t, Gear.fit(s, "wick_bellows"), "a module fits a free slot")
	_check(t, s.available_power() == power + 1, "Wick Bellows adds a power")
	_check(t, Gear.fit(s, "gyre_vanes"), "a second module fits")
	_check(t, s.available_power() == power, "Gyre Vanes draws a power back")
	var hull := s.hull
	var max_hull := s.max_hull
	_check(t, Gear.fit(s, "slag_plating"), "a third module fits")
	_check(t, s.max_hull == max_hull + 5 and s.hull == hull, "plating raises the cap, not the hull")
	_check(t, not Gear.fit(s, "kiln_coils"), "a full set of slots refuses another")
	s.hull = s.max_hull
	_check(t, Gear.unfit(s, 2) == "slag_plating", "a module comes out of its slot")
	_check(t, s.max_hull == max_hull and s.hull == max_hull, "taking plating off trims the hull")
	Gear.fit(s, "slag_plating")
	_check(t, s.hull == max_hull, "refitting plating never repairs the ship")
	_check(t, not Gear.fit(s, "no_such_module") and Gear.unfit(s, 9) == "", "bad ids are refused")
	# Dodge: the vanes add it while the helm works; the plating's weight takes some.
	var a := Ship.from_content("tallow_wren", 0)
	var b := Ship.from_content("tallow_wren", 0)
	Gear.fit(b, "gyre_vanes")
	_check(t, b.evasion() == a.evasion() + 8.0 or b.evasion() == 45.0, "vanes add dodge")
	var c := Ship.from_content("tallow_wren", 0)
	Gear.fit(c, "slag_plating")
	_check(t, c.evasion() == maxf(0.0, a.evasion() - 8.0), "plating's weight costs dodge")
	# Heat: a hot module draws warmth from every room, coils give it back.
	var cold := Ship.from_content("tallow_wren", 0)
	var warm := Ship.from_content("tallow_wren", 0)
	Gear.fit(cold, "rivet_hopper")
	Gear.fit(warm, "kiln_coils")
	var plain := Ship.from_content("tallow_wren", 0)
	var rng := RandomNumberGenerator.new()
	for i in 200:
		for sh: Ship in [cold, warm, plain]:
			sh.tick(Combat.TICK, rng, [])
	var g := plain.room("galley").warmth
	_check(t, cold.room("galley").warmth < g, "a hot module leaves the decks colder")
	_check(t, warm.room("galley").warmth > g, "kiln coils keep them warmer")
	_check(
		t,
		Gear.sum(["kiln_coils", "kiln_coils", "kiln_coils"]).chill_resist <= Gear.MAX_RESIST,
		"resist is capped"
	)


## Chill guns: no hull damage, a deep cold in the room and half of it next
## door, and the cold goes through a ward.
static func chill_guns(t: SceneTree) -> void:
	var c := Combat.create(4)
	var foe := c.enemy()
	foe.ward_layers = 2
	foe.ward_deck = foe.room("helm").deck
	var hull := foe.hull
	var before := foe.room("helm").warmth
	var next: String = foe.neighbors("helm")[0][0]
	var next_before := foe.room(next).warmth
	var cold := float(ContentDB.weapons.rime_lance.chill)
	# Land a Rime Lance shot directly; evasion is zeroed so the roll can't miss.
	foe.room("helm").power = 0
	c._resolve({"owner": 0, "weapon": "rime_lance", "slot": 0, "target": "helm"})
	_check(t, foe.hull == hull, "Chill does no hull damage")
	_check(t, foe.ward_layers == 2, "Chill neither strips nor stops at the ward")
	_check(
		t, is_equal_approx(foe.room("helm").warmth, maxf(0.0, before - cold)), "it chills the room"
	)
	var spread := maxf(0.0, next_before - cold * Combat.CHILL_SPREAD)
	_check(t, is_equal_approx(foe.room(next).warmth, spread), "half the cold reaches next door")
	var d := Combat.create(4)
	var warm := d.enemy()
	Gear.fit(warm, "kiln_coils")
	warm.room("helm").power = 0
	var w0 := warm.room("helm").warmth
	d._resolve({"owner": 0, "weapon": "rime_lance", "slot": 0, "target": "helm"})
	var shrugged := cold * (1.0 - float(ContentDB.modules.kiln_coils.gain.chill_resist))
	_check(
		t, is_equal_approx(warm.room("helm").warmth, maxf(0.0, w0 - shrugged)), "coils resist it"
	)
	# A Chill-armed fight still plays the same from the same seed and through a save.
	var a := _chill_fight(21)
	var b := _chill_fight(21)
	for i in 300:
		a.tick()
		b.tick()
	var resumed := Combat.from_dict(JSON.parse_string(J.s(a.to_dict())))
	for i in 400:
		a.tick()
		b.tick()
		resumed.tick()
	_check(t, J.canonical(a.to_dict()) == J.canonical(b.to_dict()), "Chill fights are seeded")
	_check(t, J.canonical(a.to_dict()) == J.canonical(resumed.to_dict()), "and resume exactly")


static func _chill_fight(seed_value: int) -> Combat:
	var c := Combat.create(seed_value)
	var me := c.player()
	Gear.unmount(me, 1)
	Gear.mount(me, "frost_needle")
	Gear.fit(me, "tallow_baffles")
	for i in me.weapon_ids.size():
		c.apply({"type": "aim", "weapon": i, "room": "helm"})
	return c


## Wares, Modules and Guns: buying, fitting, the hold, selling and the last gun.
static func store_pages(t: SceneTree) -> void:
	var r := _in_store(3)
	_check(t, r.stock.size() == 3, "a store lays out its wares")
	_check(t, r.stock[0].kind == "weapon" and r.stock[1].kind == "module", "a gun and a module")
	var ids := {}
	for item in r.stock:
		ids[item.id] = true
		_check(
			t, str(Gear.entry(item).get("unlock", "")) == "", "locked gear stays out: %s" % item.id
		)
	_check(t, ids.size() == r.stock.size(), "no ware is laid out twice")
	_check(t, "wares" in r.store_options() and "guns" in r.store_options(), "the pages are listed")
	_check(t, not r.store_action("buy:0"), "wares are bought on the Wares page")
	_check(t, r.store_action("wares") and r.state == "wares", "Wares opens")
	var gun: Dictionary = r.stock[0]
	var price := Market.price(r, gun)
	_check(t, r.store_action("buy:0"), "a gun is bought")
	_check(t, r.scrap == 500 - price and r.hold == [gun], "two mounts full: it goes in the hold")
	_check(t, r.stock.size() == 2, "a bought ware leaves the stock")
	var mod: Dictionary = r.stock[0]
	_check(t, r.store_action("buy:0") and r.ship.modules == [str(mod.id)], "a module fits a slot")
	_check(t, r.store_action("back") and r.state == "store", "back to the price board")
	# Guns: swap the bought gun onto a mount.
	_check(t, r.store_action("guns") and r.state == "guns", "Guns opens")
	var first := r.ship.weapon_ids[0]
	_check(t, not r.store_action("hold:0"), "no free mount for the gun in the hold")
	_check(t, r.store_action("wpn:0") and r.hold.size() == 2, "a gun comes off its mount")
	_check(t, r.store_action("hold:0") and r.ship.weapon_ids.has(str(gun.id)), "the new gun mounts")
	_check(t, r.hold == [_item("weapon", first)], "the old one waits in the hold")
	_check(t, r.store_action("sell") and r.selling, "sell mode")
	var scrap := r.scrap
	var earned := r.scrap_earned
	_check(t, r.store_action("hold:0") and r.hold.is_empty(), "held gear sells")
	_check(t, r.scrap == scrap + Market.sell_price(_item("weapon", first)), "for half its price")
	_check(t, r.scrap_earned == earned, "a sale is a trade, not loot")
	_check(t, r.store_action("wpn:0") and r.ship.weapon_ids.size() == 1, "a mounted gun sells")
	_check(t, not r.store_action("wpn:0"), "the last gun is never sold")
	_check(t, r.store_action("back") and not r.selling, "leaving a page ends sell mode")
	r.leave_store()
	_check(t, r.stock.is_empty() and r.state == "chart", "leaving clears the stall")
	# A full ship and hold refuse a buy rather than break the gear.
	var full := _in_store(5)
	full.hold = [_item("module", "gyre_vanes"), _item("module", "kiln_coils")]
	for id in ["salvage_maw", "mender_lattice", "quickstep_rails"]:
		Gear.fit(full.ship, id)
	full.state = "wares"
	_check(t, not full.store_action("buy:1"), "no room anywhere: no sale")
	full.state = "modules"
	_check(t, not full.store_action("mod:0"), "a full hold can't take a module back")
	_check(t, not full.store_action("hold:0"), "nor fit one with no free slot")
	full.scrap = 0
	full.state = "wares"
	full.hold.clear()
	_check(t, not full.store_action("buy:0"), "no scrap, no sale")
	# Depth markup reaches wares, never the buy-back price.
	var deep := _in_store(3)
	deep.depth = 3
	var base := int(Gear.entry(deep.stock[0]).price)
	_check(
		t, Market.price(deep, deep.stock[0]) == base + int(deep.mod("store_markup")), "marked up"
	)
	_check(t, Market.sell_price(deep.stock[0]) == base / 2, "sold back at half the plain price")
	# Unlocks open more of the pool.
	var all: Array[String] = []
	all.assign(ContentDB.unlocks.keys())
	var pool := Gear.pool(all)
	_check(t, pool.has(_item("weapon", "rime_lance")), "an unlock opens the Rime Lance")
	_check(t, not Gear.pool([]).has(_item("weapon", "rime_lance")), "locked without it")


## Gear from fights and events: fitted if there is room, else held, else scrapped.
static func gear_found(t: SceneTree) -> void:
	var r := Run.create(8)
	r.messages.clear()
	_check(t, r.gain(_item("module", "gyre_vanes")) == "UI_GEAR_FITTED", "found gear fits")
	_check(t, r.messages[-1] == "UI_GEAR_FITTED|MOD_GYRE_VANES", "and says so")
	_check(t, GearText.message(r.messages[-1]).contains("Gyre Vanes"), "with its name")
	_check(t, r.gain(_item("weapon", "frost_needle")) == "UI_GEAR_HELD", "no mount: held")
	r.gain(_item("weapon", "kiln_brand"))
	var scrap := r.scrap
	_check(t, r.gain(_item("weapon", "rivet_gun")) == "UI_GEAR_SCRAPPED", "no room: scrapped")
	_check(t, r.scrap == scrap + Market.sell_price(_item("weapon", "rivet_gun")), "for scrap")
	# Events hand out gear by id or from the pool.
	var e := Run.create(9)
	e._apply({"module": "kiln_coils"})
	_check(t, e.ship.modules == ["kiln_coils"], "an event can name its module")
	e._apply({"weapon": "any"})
	_check(t, e.hold.size() == 1 and e.hold[0].kind == "weapon", "or draw a gun from the pool")
	var kiln := Run.create(10)
	kiln.event_id = "kiln_wreck"
	kiln.state = "event"
	kiln.light = 2
	_check(t, kiln.choose(0) and kiln.ship.modules == ["kiln_coils"], "the kiln wreck gives coils")
	# Fights: a drop when the Reach's chance comes up.
	var keep: Dictionary = ContentDB.reaches.duplicate(true)
	ContentDB.reaches.reach_1.fight_reward.gear_chance = 1.0
	var f := Run.create(12)
	f._start_fight("ashmarket_skiff")
	f.combat.enemy().hull = 0
	f.combat.tick()
	f.finish_fight()
	ContentDB.reaches = keep
	var got := f.ship.modules.size() + f.hold.size() + f.ship.weapon_ids.size() - 2
	_check(t, got == 1, "a won fight can drop gear")


## Module costs that land outside fights: Light per jump, the Hush per jump,
## and gains that pay out after a fight.
static func run_costs(t: SceneTree) -> void:
	var a := Run.create(30)
	var b := Run.create(30)
	Gear.fit(b.ship, "wick_bellows")
	Gear.fit(b.ship, "lamp_siphon")
	var target := a.jump_targets()[0]
	a.jump(target)
	b.jump(target)
	_check(t, b.light == maxi(0, a.light - 1), "Wick Bellows burns a Light each jump")
	_check(t, b.hush > a.hush, "a Lamp Siphon draws the Hush nearer")
	var broke := Run.create(30)
	Gear.fit(broke.ship, "wick_bellows")
	broke.light = 1  # pays the jump, not the bellows
	broke.jump(target)
	var plain := Run.create(30)
	plain.light = 1
	plain.jump(target)
	_check(t, broke.light == 0 and broke.hush > plain.hush, "unpaid upkeep draws the Hush instead")
	var extra := broke.hush - plain.hush
	_check(t, absf(extra - Run.UNPAID_UPKEEP_HUSH) < 0.01, "by a set amount per missing Light")
	_check(t, broke.messages.has("UI_UPKEEP_UNPAID"), "and says so")
	var s1 := Run.create(31)
	var s2 := Run.create(31)
	Gear.fit(s2.ship, "salvage_maw")
	Gear.fit(s2.ship, "lamp_siphon")
	for r: Run in [s1, s2]:
		r._start_fight("ashmarket_skiff")
		r.combat.enemy().hull = 0
		r.combat.tick()
		r.finish_fight()
	_check(t, s2.scrap > s1.scrap, "a Salvage Maw brings more scrap from a fight")
	_check(t, s2.light == s1.light + 1, "a Lamp Siphon a Light")


## The hold, wares, fitted gear and sell mode all survive a save, and a
## version 5 save loads with its hull's own guns and no modules.
static func saves_keep_gear(t: SceneTree) -> void:
	var r := _in_store(14)
	r.store_action("modules")
	r.gain(_item("module", "hush_veil"))
	r.hold.append(_item("weapon", "frost_needle"))
	r.store_action("sell")
	Gear.unmount(r.ship, 0)
	var back := Run.from_dict(JSON.parse_string(J.s(r.to_dict())))
	_check(t, J.canonical(back.to_dict()) == J.canonical(r.to_dict()), "gear round-trips a save")
	_check(t, back.ship.weapon_ids == r.ship.weapon_ids, "the guns as mounted")
	_check(t, back.ship.mod("evasion") == 12.0, "fitted modules work after loading")
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/run_save_v5.json")
	)
	var up := SaveService.upgrade(raw)
	var old := Run.from_dict(up.data.run)
	_check(t, old.ship.modules.is_empty() and old.hold.is_empty(), "an old run has no gear yet")
	var hull_guns: Array = ContentDB.ships[old.ship.content_id].weapons
	_check(t, Array(old.ship.weapon_ids) == hull_guns, "and its hull's own guns")
	var odd := r.to_dict()
	odd.hold = [{"kind": "module", "id": "gone"}, "junk", {"kind": "weapon", "id": "rivet_gun"}]
	odd.ship.modules = ["gone", "kiln_coils"]
	odd.ship.weapons = ["gone"]
	var fixed := Run.from_dict(odd)
	_check(t, fixed.hold == [_item("weapon", "rivet_gun")], "gear an update cut is dropped")
	_check(t, fixed.ship.modules == ["kiln_coils"], "from slots too")
	_check(t, not fixed.ship.weapon_ids.is_empty(), "a ship never loads with no guns")
	# A v5 save docked at a store lays out wares on load, as arrival would have.
	var docked: Dictionary = raw.duplicate(true)
	docked.data.run.state = "store"
	var at_store := Run.from_dict(SaveService.upgrade(docked).data.run)
	_check(
		t, at_store.state == "store" and not at_store.stock.is_empty(), "old docked save gets wares"
	)
	# An event cut by an update docks the run at its store with this run's unlocks.
	var cut := _in_store(15, ["gear_rime_lance"])
	cut.leave_store()
	cut.chart.node(cut.at).kind = "store"
	cut.state = "event"
	cut.event_id = "no_such_event"
	var cut_back := Run.from_dict(JSON.parse_string(J.s(cut.to_dict())))
	_check(
		t, cut_back.state == "store" and not cut_back.stock.is_empty(), "a cut event still stocks"
	)
	_check(t, cut_back.unlocked == ["gear_rime_lance"], "with the run's unlocks loaded first")
	var v6 := FileAccess.get_file_as_string("res://tests/fixtures/run_save_v6.json")
	var fx := SaveService.upgrade(JSON.parse_string(v6))
	var loaded := Run.from_dict(fx.data.run)
	_check(t, not loaded.hold.is_empty() and not loaded.ship.modules.is_empty(), "v6 fixture loads")


## Bad gear content is caught.
static func content_checked(t: SceneTree) -> void:
	_check(t, ContentDB.validate().is_empty(), "the gear content is valid")
	var keep_m: Dictionary = ContentDB.modules.duplicate(true)
	var keep_w: Dictionary = ContentDB.weapons.duplicate(true)
	var keep_e: Dictionary = ContentDB.events.duplicate(true)
	var keep_s: Dictionary = ContentDB.ships.duplicate(true)
	var keep_r: Dictionary = ContentDB.reaches.duplicate(true)
	ContentDB.modules.gyre_vanes.cost = {}
	_check(t, _has(ContentDB.validate(), "needs at least one cost"), "a free module is caught")
	ContentDB.modules = keep_m.duplicate(true)
	ContentDB.modules.gyre_vanes.gain = {"luck": 1}
	_check(t, _has(ContentDB.validate(), "unknown gain luck"), "an unknown gain is caught")
	ContentDB.modules = keep_m.duplicate(true)
	ContentDB.modules.wick_bellows.gain = {"reactor": 1.5}
	_check(t, _has(ContentDB.validate(), "above 0"), "a fractional reactor is caught")
	ContentDB.modules = keep_m.duplicate(true)
	ContentDB.modules.gyre_vanes.unlock = "nowhere"
	_check(t, _has(ContentDB.validate(), "unknown unlock nowhere"), "a bad gear unlock")
	ContentDB.modules = keep_m
	ContentDB.weapons.frost_needle.erase("chill")
	_check(t, _has(ContentDB.validate(), "needs a chill amount"), "a Chill gun with no chill")
	ContentDB.weapons = keep_w.duplicate(true)
	ContentDB.weapons.rivet_gun.pierces_ward = true
	_check(t, _has(ContentDB.validate(), "not both"), "strip and pierce together are caught")
	ContentDB.weapons = keep_w
	ContentDB.events.kiln_wreck.choices[0].outcomes[0].effects.module = "nothing"
	_check(t, _has(ContentDB.validate(), "module must be a module id"), "a bad event module")
	ContentDB.events = keep_e
	ContentDB.ships.tallow_wren["weapon_slots"] = 3
	_check(t, _has(ContentDB.validate(), "at most 2 mounts"), "the fight bar's gun limit")
	ContentDB.ships = keep_s.duplicate(true)
	ContentDB.ships.ashmarket_cutter["module_slots"] = 5
	_check(t, _has(ContentDB.validate(), "module_slots"), "the Modules page's slot limit")
	ContentDB.ships = keep_s.duplicate(true)
	ContentDB.ships.ashmarket_cutter["modules"] = ["no_such"]
	_check(t, _has(ContentDB.validate(), "unknown module no_such"), "a bad hull module")
	ContentDB.ships = keep_s
	ContentDB.reaches.reach_1.store.stock = 9
	_check(t, _has(ContentDB.validate(), "store.stock"), "too many wares")
	ContentDB.reaches = keep_r


## The store pages draw and answer taps through Main like the other run screens.
static func pages_in_main(t: SceneTree) -> void:
	var dir := "user://test_gear"
	DirAccess.make_dir_recursive_absolute(dir)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_dir = dir
	t.root.size = Vector2i(2400, 1080)
	t.root.add_child(main)
	main.tutorial.skip()
	var r := _in_store(3)
	main._set_run(r)
	var tap := func(option: String) -> void:
		var i := r.page_options().find(option)
		var b: Dictionary = main.run_layout.buttons[i]
		main._tap(Vector2((b.rect as Rect2i).get_center()) * main.screen.scale, false)
	tap.call("wares")
	_check(t, r.state == "wares" and main.run_layout.buttons.size() == 4, "a tap opens Wares")
	tap.call("buy:1")
	_check(t, r.ship.modules.is_empty(), "the first tap on a ware only opens its card")
	_check(t, main.run_view.focus.current(r) == "buy:1", "and the card is the ware's")
	tap.call("buy:1")
	_check(t, r.ship.modules.size() == 1, "a second tap buys it")
	_check(t, main.run_view.focus.current(r) == "", "the card closes: the slot shows another ware")
	tap.call("back")
	tap.call("modules")
	_check(t, r.state == "modules" and main.run_view.visible, "a tap opens Modules")
	_check(t, main.music_state() == "store", "the store's music plays on its pages")
	tap.call("mod:0")
	_check(t, r.ship.modules.size() == 1, "the first tap on a module opens its card")
	tap.call("mod:0")
	_check(t, r.ship.modules.is_empty() and r.hold.size() == 1, "a second tap stows it")
	_check(t, SaveService.read("run", dir).get("run", {}).get("state") == "modules", "and saves")
	t.root.remove_child(main)
	main.free()
