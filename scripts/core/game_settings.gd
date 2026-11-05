class_name GameSettings
extends RefCounted
## The player's comfort settings: volumes, haptics, shake, hit-stop, flashing and UI size.
## Kept in their own save slot so they outlive any run and never touch the run save.
## SaveService.migrate() steps only touch run and fight keys, so they pass this
## data through unchanged; a change to the settings shape bumps SETTINGS_VERSION
## and upgrades in from_dict() instead (fixtures: tests/fixtures/settings_v*.json).
## v2 added ui_size; a v1 file loads with it at auto.

const SLOT := "settings"
const SETTINGS_VERSION := 2
const STEP := 0.1  ## one tap of - or + on the options screen
## UI size steps around the auto scale (see ScreenManager.compute): one smaller, one
## larger. Two smaller would shrink tap targets well under a fingertip.
const UI_SIZE_MIN := -1
const UI_SIZE_MAX := 1

var volume := {"Master": 0.8, "Music": 0.7, "SFX": 0.9, "UI": 0.7}  ## 0..1 per bus
var haptics := 1.0  ## 0 turns vibration off
var shake := 1.0  ## screen shake strength, 0..1
var hitstop := true
var reduce_flashing := false
var ui_size := 0  ## whole scale steps from auto; 0 is auto


## A setting's value by options-screen id: a bus name, "haptics" or "shake"
## (0..1), "hitstop" / "reduce_flashing" (1 on, 0 off), or "ui_size" (a step, -1..1).
func value(id: String) -> float:
	if volume.has(id):
		return float(volume[id])
	match id:
		"haptics":
			return haptics
		"shake":
			return shake
		"hitstop":
			return 1.0 if hitstop else 0.0
		"reduce_flashing":
			return 1.0 if reduce_flashing else 0.0
		"ui_size":
			return float(ui_size)
	return 0.0


## One tap on the options screen: dir is +1 or -1 for a level, any value
## flips a toggle. Levels snap to tenths so repeated taps never drift.
func adjust(id: String, dir: int) -> void:
	match id:
		"hitstop":
			hitstop = not hitstop
			return
		"reduce_flashing":
			reduce_flashing = not reduce_flashing
			return
		"ui_size":
			ui_size = clampi(ui_size + signi(dir), UI_SIZE_MIN, UI_SIZE_MAX)
			return
	var v := clampf(snappedf(value(id) + STEP * signi(dir), STEP), 0.0, 1.0)
	if volume.has(id):
		volume[id] = v
	elif id == "haptics":
		haptics = v
	elif id == "shake":
		shake = v


## Back to the defaults, in place, so everything holding this object sees it.
func reset() -> void:
	var d := GameSettings.new()
	volume = d.volume
	haptics = d.haptics
	shake = d.shake
	hitstop = d.hitstop
	reduce_flashing = d.reduce_flashing
	ui_size = d.ui_size


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
		"reduce_flashing": reduce_flashing,
		"ui_size": ui_size
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
	s.ui_size = _step(d.get("ui_size"), s.ui_size)
	return s


static func _unit(v: Variant, fallback: float) -> float:
	if not (v is float or v is int):
		return fallback
	return clampf(float(v), 0.0, 1.0)


static func _step(v: Variant, fallback: int) -> int:
	if not (v is float or v is int):
		return fallback
	return clampi(int(v), UI_SIZE_MIN, UI_SIZE_MAX)


static func _flag(v: Variant, fallback: bool) -> bool:
	return v if v is bool else fallback
