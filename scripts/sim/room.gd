class_name Room
extends RefCounted

var id: String
var deck: int
var system: String
var level: int
var rect: Rect2i
var power: int = 0
var wanted_power: int = 0  ## what the captain asked for; power returns to it after repairs
var damage: float = 0.0  ## 0..level; each whole point removes one level
var warmth: float = 60.0  ## 0..100
var fire: float = 0.0  ## 0..100


func effective_level() -> int:
	return maxi(0, level - int(ceil(damage - 0.001)))


func center_x() -> float:
	return (rect.position.x + rect.end.x) * 0.5


func to_dict() -> Dictionary:
	return {
		"id": id,
		"level": level,
		"power": power,
		"wanted_power": wanted_power,
		"damage": damage,
		"warmth": warmth,
		"fire": fire
	}


func load_dict(d: Dictionary) -> void:
	level = int(d.get("level", level))  # saves from before refits keep the hull's level
	power = int(d.get("power", 0))
	wanted_power = int(d.get("wanted_power", power))
	damage = float(d.get("damage", 0.0))
	warmth = float(d.get("warmth", 60.0))
	fire = float(d.get("fire", 0.0))
