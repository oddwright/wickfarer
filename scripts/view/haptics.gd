class_name Haptics
extends RefCounted
## Plays named vibration patterns from data/feedback.json.
## A pattern is a list of [ms, amplitude] steps; amplitude 0 is a gap.
## - One pattern at a time: a pattern of equal or higher priority replaces the
##   running one, a lower one is dropped. Long overlapping buzzes feel cheap.
## - A new pattern starts at least MIN_GAP after the last pulse, so bursts
##   can't blur into a drone.
## - The backend is swappable: today Input.vibrate_handheld (Core Haptics on
##   iOS, Vibrator on Android); a native plugin with sharper "click" haptics can
##   replace it later without touching the game. Tests pass a recorder.

const MIN_GAP := 0.05
const MIN_PULSE_MS := 12  ## many Android motors ignore anything shorter

var strength := 1.0  ## 0 turns haptics off
var backend: Callable  ## func(duration_ms: int, amplitude: float)
var patterns: Dictionary = {}

var _clock := 0.0
var _queue: Array[Dictionary] = []  ## {at, ms, amp}, in time order
var _priority := -1
var _free_at := 0.0  ## when the motor is free for a new pattern


func _init(pattern_table: Dictionary = {}, backend_fn := Callable()) -> void:
	patterns = pattern_table
	backend = backend_fn if backend_fn.is_valid() else _vibrate


static func _vibrate(ms: int, amplitude: float) -> void:
	Input.vibrate_handheld(ms, amplitude)


## Returns true if the pattern was started.
func play(pattern: String, priority := 0) -> bool:
	if strength <= 0.0 or not patterns.has(pattern):
		return false
	if not _queue.is_empty() and priority < _priority:
		return false
	_queue.clear()
	_priority = priority
	# A new pattern waits out the gap after the last pulse instead of smearing into it.
	var at := maxf(_clock, _free_at)
	for step: Array in patterns[pattern]:
		var ms := int(step[0])
		var amp := float(step[1])
		if amp > 0.0:
			_queue.append({"at": at, "ms": maxi(ms, MIN_PULSE_MS), "amp": amp})
		at += ms / 1000.0
	update(0.0)
	return true


func update(delta: float) -> void:
	_clock += delta
	while not _queue.is_empty() and _queue[0].at <= _clock:
		var p: Dictionary = _queue.pop_front()
		_free_at = float(p.at) + maxf(MIN_GAP, p.ms / 1000.0)
		backend.call(int(p.ms), clampf(float(p.amp) * strength, 0.0, 1.0))
	if _queue.is_empty():
		_priority = -1


## Stops any running pattern (app paused, settings changed).
func stop() -> void:
	_queue.clear()
	_priority = -1
