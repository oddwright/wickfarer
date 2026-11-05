class_name Crew
extends RefCounted

var uid: int
var name: String
var species: String
var room: String
var hp: float
var max_hp: float
var path: Array[String] = []  ## rooms still to walk through
var progress: float = 0.0  ## 0..1 toward path[0]


func spec() -> Dictionary:
	return ContentDB.species[species]


func is_moving() -> bool:
	return not path.is_empty()


func to_dict() -> Dictionary:
	return {"uid": uid, "name": name, "species": species, "room": room, "hp": hp,
		"path": Array(path), "progress": progress}


static func from_dict(d: Dictionary) -> Crew:
	var c := Crew.new()
	c.uid = int(d.uid)
	c.name = d.name
	c.species = d.species
	c.room = d.room
	c.hp = float(d.hp)
	c.max_hp = float(ContentDB.species[c.species].hp)
	for r in d.get("path", []):
		c.path.append(str(r))
	c.progress = float(d.get("progress", 0.0))
	return c
