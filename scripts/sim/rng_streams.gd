class_name RngStreams
extends RefCounted
## One seed per run, split into named streams so that an extra roll in one
## place (say, combat) never shifts another (say, the map).
## RNG state is a 64-bit int, so it is saved as a string: JSON numbers are
## doubles and would silently lose precision.

const NAMES: Array[String] = ["map", "events", "combat", "loot", "ai"]

var run_seed: int = 0
var _streams: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	run_seed = seed_value
	for n in NAMES:
		var r := RandomNumberGenerator.new()
		r.seed = hash("%d:%s" % [seed_value, n])
		_streams[n] = r


func stream(name: String) -> RandomNumberGenerator:
	return _streams[name]


func to_dict() -> Dictionary:
	var states := {}
	for n: String in _streams:
		states[n] = str(_streams[n].state)
	return {"seed": str(run_seed), "states": states}


static func from_dict(d: Dictionary) -> RngStreams:
	var r := RngStreams.new(int(str(d.get("seed", "0"))))
	var states: Dictionary = d.get("states", {})
	for n: String in states:
		if r._streams.has(n):
			r._streams[n].state = int(str(states[n]))
	return r
