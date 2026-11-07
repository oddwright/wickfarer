class_name Market
extends RefCounted
## A store's pages past the price board: Wares (gear for sale), Modules and
## Guns (moving gear between the ship and the hold, or selling it). The run
## keeps the state (stock, hold, selling); these are its rules, so Run stays
## small. Every option is a string the view turns into a button:
## "buy:i" a ware, "mod:i" a module slot, "wpn:i" a gun mount, "hold:i" a
## hold space, and "sell" and "back".

const SUB_PAGES: Array[String] = ["wares", "modules", "guns"]
const GEAR_PAGES: Array[String] = ["modules", "guns"]
const SELL_SHARE := 0.5  ## a store buys gear back at half its price


## Docks at a store: the trader lays out this visit's wares. The first is a gun
## and the second a module when the pool has them, so a store always offers both.
static func open(run: Run) -> void:
	run.stock.clear()
	run.selling = false
	var rng := run.rng.stream("store")
	var n := int(run.reach().store.get("stock", 0))
	for i in n:
		var kind := "weapon" if i == 0 else ("module" if i == 1 else "")
		var item := Gear.pick(rng, run.unlocked, kind, run.stock)
		if item.is_empty():
			item = Gear.pick(rng, run.unlocked, "", run.stock)
		if item.is_empty():
			break
		run.stock.append(item)
	run.state = "store"


## The buttons of a store sub-page, top to bottom.
static func options(run: Run) -> Array[String]:
	var out: Array[String] = []
	match run.state:
		"wares":
			for i in run.stock.size():
				out.append("buy:%d" % i)
		"modules":
			for i in run.ship.module_slots:
				out.append("mod:%d" % i)
		"guns":
			for i in run.ship.weapon_slots:
				out.append("wpn:%d" % i)
	if run.state in GEAR_PAGES:
		for i in Run.HOLD_SIZE:
			out.append("hold:%d" % i)
		out.append("sell")
	if run.state in SUB_PAGES:
		out.append("back")
	return out


## The gear an option points at ({kind, id}), or {} for an empty space or a page button.
static func item_at(run: Run, option: String) -> Dictionary:
	var i := _index(option)
	match _verb(option):
		"buy":
			return run.stock[i] if i < run.stock.size() else {}
		"mod":
			return (
				{"kind": "module", "id": run.ship.modules[i]} if i < run.ship.modules.size() else {}
			)
		"wpn":
			return (
				{"kind": "weapon", "id": run.ship.weapon_ids[i]}
				if i < run.ship.weapon_ids.size()
				else {}
			)
		"hold":
			return run.hold[i] if i < run.hold.size() else {}
	return {}


## Does this store or refit option spend scrap or Light? (The view plays the till for it.)
static func pays(option: String) -> bool:
	if option in Run.STORE_ITEMS or option in Run.REFIT_SYSTEMS or option == "stoke":
		return true
	return _verb(option) == "buy"


## A ware's scrap price, with the Hush Depth's markup.
static func price(run: Run, item: Dictionary) -> int:
	return run.marked_up(int(Gear.entry(item).get("price", 0)))


## What a store pays for gear: half its plain price, never marked up.
static func sell_price(item: Dictionary) -> int:
	return int(float(Gear.entry(item).get("price", 0)) * SELL_SHARE)


## Is there anywhere aboard for this gear: a free slot or mount, or hold space?
static func has_room(run: Run, item: Dictionary) -> bool:
	return _hold_space(run) or _fits(run, item)


static func can(run: Run, option: String) -> bool:
	var verb := _verb(option)
	if verb in SUB_PAGES:
		return run.state == "store" and (verb != "wares" or not run.stock.is_empty())
	if verb == "back":
		return run.state in SUB_PAGES
	if verb == "sell":
		return run.state in GEAR_PAGES
	if not run.state in SUB_PAGES or not option in options(run):
		return false
	var item := item_at(run, option)
	if item.is_empty():
		return false
	match verb:
		"buy":
			return run.scrap >= price(run, item) and has_room(run, item)
		"wpn":
			# The last gun stays: a ship with none could never end a fight.
			return run.ship.weapon_ids.size() > 1 and (run.selling or _hold_space(run))
		"mod":
			return run.selling or _hold_space(run)
		"hold":
			return run.selling or _fits(run, item)
	return false


static func act(run: Run, option: String) -> bool:
	if not can(run, option):
		return false
	var verb := _verb(option)
	var i := _index(option)
	match verb:
		"wares", "modules", "guns":
			run.state = verb
		"back":
			run.state = "store"
			run.selling = false
		"sell":
			run.selling = not run.selling
		"buy":
			var item: Dictionary = run.stock[i]
			run.scrap -= price(run, item)
			run.stock.remove_at(i)
			run.gain(item)
		"mod", "wpn":
			var item := item_at(run, option)
			if verb == "mod":
				Gear.unfit(run.ship, i)
			else:
				Gear.unmount(run.ship, i)
			_stow_or_sell(run, item)
		"hold":
			var item: Dictionary = run.hold[i]
			run.hold.remove_at(i)
			if run.selling:
				run.scrap += sell_price(item)
			else:
				Gear.place(run.ship, item)
	return true


## Selling is a trade, not loot: the scrap doesn't count toward scrap earned.
static func _stow_or_sell(run: Run, item: Dictionary) -> void:
	if run.selling:
		run.scrap += sell_price(item)
	else:
		run.hold.append(item)


static func _hold_space(run: Run) -> bool:
	return run.hold.size() < Run.HOLD_SIZE


static func _fits(run: Run, item: Dictionary) -> bool:
	if item.kind == "module":
		return Gear.free_slots(run.ship) > 0
	return Gear.free_mounts(run.ship) > 0


static func _verb(option: String) -> String:
	return option.get_slice(":", 0)


static func _index(option: String) -> int:
	return int(option.get_slice(":", 1)) if option.contains(":") else -1
