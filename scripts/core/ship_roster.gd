class_name ShipRoster
extends RefCounted
## The hulls a player can start a run in, in data order, and which are open.
## A playable hull in data/ships.json has "playable": true, a "blurb" string
## key and an "unlock" id: "" is open from the first run; anything else is
## opened by meta progression, which hands over the ids the player has earned.


static func playable() -> Array[String]:
	ContentDB.load_all()
	var out: Array[String] = []
	for id: String in ContentDB.ships:
		if ContentDB.ships[id].get("playable", false):
			out.append(id)
	return out


static func is_unlocked(ship_id: String, unlocked: Array[String]) -> bool:
	var s: Dictionary = ContentDB.ships.get(ship_id, {})
	if not s.get("playable", false):
		return false
	var key := str(s.get("unlock", ""))
	return key == "" or unlocked.has(key)


## The string key that says how to open a locked hull.
static func unlock_hint(ship_id: String) -> String:
	var key := str(ContentDB.ships.get(ship_id, {}).get("unlock", ""))
	return str(ContentDB.unlocks.get(key, {}).get("hint", ""))


## The first open hull, for a new run when no other choice was made.
static func default_ship(unlocked: Array[String] = []) -> String:
	for id in playable():
		if is_unlocked(id, unlocked):
			return id
	return "tallow_wren"
