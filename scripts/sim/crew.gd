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
var post: String = ""  ## home station room id; "" means no post (a deckhand)
var xp: Dictionary = {}  ## skill id -> practice so far
var fight_xp: Dictionary = {}  ## skill id -> practice this fight, banked after it (capped)


func spec() -> Dictionary:
	return ContentDB.species[species]


func is_moving() -> bool:
	return not path.is_empty()


func skill_xp(skill: String) -> float:
	return float(xp.get(skill, 0.0))


func rank(skill: String) -> int:
	return Skills.rank_for(skill_xp(skill)) if skill != "" else 0


func fight_practice(skill: String) -> float:
	return float(fight_xp.get(skill, 0.0))


## Practice banked plus this fight's, which is banked once the fight ends.
func practice(skill: String) -> float:
	return skill_xp(skill) + fight_practice(skill)


## The rank this crew member will have once this fight's practice is banked.
func earned_rank(skill: String) -> int:
	return Skills.rank_for(practice(skill)) if skill != "" else 0


## How fast this species picks up a skill (1 = normal).
func learn_rate(skill: String) -> float:
	return float(spec().get("learns", {}).get(skill, 1.0))


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"name": name,
		"species": species,
		"room": room,
		"hp": hp,
		"path": Array(path),
		"progress": progress,
		"post": post,
		"xp": xp.duplicate(),
		"fight_xp": fight_xp.duplicate()
	}


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
	c.post = str(d.get("post", ""))
	c.xp = _skill_dict(d.get("xp", {}))
	c.fight_xp = _skill_dict(d.get("fight_xp", {}))
	return c


## Practice by skill, dropping skills an update removed.
static func _skill_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		if Skills.ids().has(k):
			out[k] = float(d[k])
	return out
