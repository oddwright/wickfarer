class_name GameSettings
extends RefCounted
## The player's comfort settings: volumes, haptics, shake, hit-stop and flashing.
## Kept in their own save slot so they outlive any run and never touch the run save.
## SaveService.migrate() steps only touch run and fight keys, so they pass this
## data through unchanged; a change to the settings shape bumps SETTINGS_VERSION
## and upgrades in from_dict() instead (fixture: tests/fixtures/settings_v1.json).

const SLOT := "settings"
const SETTINGS_VERSION := 1

var volume := {"Master": 0.8, "Music": 0.7, "SFX": 0.9, "UI": 0.7}  ## 0..1 per bus
var haptics := 1.0  ## 0 turns vibration off
var shake := 1.0  ## screen shake strength, 0..1
var hitstop := true
var reduce_flashing := false


static func load_or_default(dir := SaveService.DIR) -> GameSettings:
	return from_dict(SaveService.read(SLOT, dir))


func save(dir := SaveService.DIR) -> bool:
	return SaveService.write(SLOT, to_dict(), dir)


func to_dict() -> Dictionary:
	return {
		"settings_version": SETTINGS_VERSION,
		"volume": volume.duplicate(),
		"haptics": haptics,
		"shake": shake,
		"hitstop": hitstop,
		"reduce_flashing": reduce_flashing
	}


## Missing or damaged fields fall back to the defaults instead of failing.
static func from_dict(d: Dictionary) -> GameSettings:
	var s := GameSettings.new()
	var vol: Variant = d.get("volume", {})
	if vol is Dictionary:
		for bus: String in s.volume:
			s.volume[bus] = _unit(vol.get(bus), s.volume[bus])
	s.haptics = _unit(d.get("haptics"), s.haptics)
	s.shake = _unit(d.get("shake"), s.shake)
	s.hitstop = _flag(d.get("hitstop"), s.hitstop)
	s.reduce_flashing = _flag(d.get("reduce_flashing"), s.reduce_flashing)
	return s


static func _unit(v: Variant, fallback: float) -> float:
	if not (v is float or v is int):
		return fallback
	return clampf(float(v), 0.0, 1.0)


static func _flag(v: Variant, fallback: bool) -> bool:
	return v if v is bool else fallback
