class_name SaveService
extends RefCounted
## Saves are plain JSON with a version number.
## - Never load Godot Resources from the save folder: they can run code.
## - Write to a temp file, then swap it in, so a phone killing the app
##   mid-write can't leave a half-written save. The last good save is kept
##   as a .bak and used if the main file is unreadable.
## - Old saves are upgraded one version at a time by migrate().
## - A save from a newer game version is refused, not overwritten.

const VERSION := 6
const DIR := "user://"


## Upgrades a version n save's data to version n + 1, or returns null if there
## is no step. (An empty dictionary is a valid result, so it can't mean "no step".)
## Never delete a step: a player who skipped many updates still needs it.
static func migrate(from_version: int, d: Dictionary) -> Variant:
	match from_version:
		0:
			# Version 0 kept the seed at the top level as "rng_seed".
			var combat: Dictionary = d.get("combat", {})
			if d.has("rng_seed") and not combat.has("rng"):
				combat["rng"] = {"seed": str(int(d.rng_seed)), "states": {}}
			d.erase("rng_seed")
			d["combat"] = combat
			return d
		1:
			# Version 2 rooms remember the power the captain asked for. A version 1
			# save never shed power for damage it could restore, so what it has is
			# what was asked for.
			for ship: Dictionary in _saved_ships(d):
				for room: Dictionary in ship.get("rooms", []):
					if not room.has("wanted_power"):
						room["wanted_power"] = room.get("power", 0)
			return d
		2:
			# Version 3 ships carry refits (room levels, reactor, max hull, stokes)
			# and runs carry their stats and Reach chain. Their defaults (the hull's
			# own numbers, zero stats) are right for a version 2 save, so nothing
			# moves; the bump only stops an older build from loading a newer run.
			return d
		3:
			# Version 4 runs have a Hush Depth and an id for the profile. A version 3
			# run was played without depths (0), and an empty id makes the profile
			# fall back to the seed. Nothing moves; the bump keeps an older build
			# from playing a deep run with none of its rules.
			return d
		4:
			# Version 5 crew have skill practice. Crew from an older save start
			# Green; their post (missing here) is filled in by Ship.from_dict,
			# which knows which rooms are stations.
			for ship: Dictionary in _saved_ships(d):
				for c: Dictionary in ship.get("crew", []):
					if not c.has("xp"):
						c["xp"] = {}
					if not c.has("fight_xp"):
						c["fight_xp"] = {}
			return d
		5:
			# Version 6 fights can be the Kindling siege, with a "siege" block and a
			# "siege" random stream. A version 5 fight is an ordinary one and needs
			# neither (the stream seeds itself); the bump keeps an older build from
			# loading a siege it would play as a fight with no end.
			return d
	return null


## Every saved ship in a save's data, whether it holds a lone fight or a run.
static func _saved_ships(d: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for holder: Dictionary in [d.get("combat", {}), d.get("run", {}).get("combat", {})]:
		for ship: Dictionary in holder.get("ships", []):
			out.append(ship)
	var run_ship: Dictionary = d.get("run", {}).get("ship", {})
	if not run_ship.is_empty():
		out.append(run_ship)
	return out


static func path_for(slot: String, dir := DIR) -> String:
	return dir.path_join(slot + ".json")


static func write(slot: String, payload: Dictionary, dir := DIR) -> bool:
	var data := {"version": VERSION, "saved_at": Time.get_unix_time_from_system(), "data": payload}
	var final_path := path_for(slot, dir)
	var tmp_path := final_path + ".tmp"
	var bak_path := final_path + ".bak"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("Save failed to open %s: %s" % [tmp_path, FileAccess.get_open_error()])
		return false
	f.store_string(JsonUtil.s(data))
	f.flush()
	f.close()
	if FileAccess.file_exists(final_path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		DirAccess.rename_absolute(final_path, bak_path)
	var err := DirAccess.rename_absolute(tmp_path, final_path)
	if err != OK:
		push_error("Save failed to move into place: %s" % err)
		return false
	return true


## Returns {} when there is no usable save.
static func read(slot: String, dir := DIR) -> Dictionary:
	var final_path := path_for(slot, dir)
	for p in [final_path, final_path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("Unreadable save %s, trying the backup" % p)
			continue
		var upgraded := upgrade(parsed)
		if upgraded.is_empty():
			continue
		return upgraded.get("data", {})
	return {}


## Returns the save upgraded to VERSION, or {} if it can't be. Works on a copy,
## so a save that fails half way through is left exactly as it was read.
static func upgrade(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))  # JSON numbers are floats: always int() them
	if v > VERSION:
		push_warning("Save is from a newer version (%d > %d); leaving it alone" % [v, VERSION])
		return {}
	var out := d.duplicate(true)
	while v < VERSION:
		var inner: Variant = migrate(v, out.get("data", {}))
		if not inner is Dictionary:
			push_error("No migration from save version %d" % v)
			return {}
		out["data"] = inner
		v += 1
		out["version"] = v
	return out


static func erase(slot: String, dir := DIR) -> void:
	var final_path := path_for(slot, dir)
	for p in [final_path, final_path + ".bak", final_path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
