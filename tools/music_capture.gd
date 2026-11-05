extends SceneTree
## Records the game's adaptive music through real fights, so the score can be
## heard (and checked) away from a phone. The player's ship is flown by the
## enemy's AI; the music follows the fight exactly as in the game.
## xvfb-run godot --path . --write-movie out.avi --fixed-fps 60 --resolution 64x64 \
##     -s tools/music_capture.gd -- 1005 1009 [sfx]
## Each number is a fight seed. "sfx" also plays the sound cues. Then:
## ffmpeg -i out.avi -vn out.mp3

const CHART_TIME := 6.0  ## seconds of chart music before each fight
const AFTER_TIME := 12.0  ## seconds to stay on the end of each fight

var _audio: AudioService
var _feedback: FeedbackDirector
var _director := MusicDirector.new()
var _pilot := CombatAI.new()
var _seeds: Array[int] = []
var _sfx := false
var _combat: Combat
var _clock := 0.0
var _phase_time := 0.0
var _phase := "start"
var _acc := 0.0
var _last_state := ""
var _last_clip := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "sfx":
			_sfx = true
		elif a.is_valid_int():
			_seeds.append(int(a))
	if _seeds.is_empty():
		_seeds = [1005]
	ContentDB.load_all()
	_feedback = FeedbackDirector.new(ContentDB.feedback.cues)
	_audio = AudioService.new()
	root.add_child(_audio)


func _process(delta: float) -> bool:
	_audio.finish_build(true)
	_feedback.update(delta)
	_clock += delta
	_phase_time += delta
	if _audio._playing_clip != _last_clip:
		_last_clip = _audio._playing_clip
		print("%6.1f s    clip %s" % [_clock, _last_clip])
	match _phase:
		"start", "after":
			if _phase == "start":
				_audio.apply_settings(GameSettings.new())  # the default mix a new player hears
			if _phase == "after" and _phase_time < AFTER_TIME:
				return false
			if _seeds.is_empty():
				return true
			_set_music("chart")
			_phase = "chart"
			_phase_time = 0.0
		"chart":
			if _phase_time >= CHART_TIME:
				_combat = Combat.create(_seeds.pop_front())
				_phase = "fight"
				_phase_time = 0.0
		"fight":
			_tick_fight(delta)
	return false


func _tick_fight(delta: float) -> void:
	_acc += delta
	while _acc >= Combat.TICK and _combat.state == "fighting":
		_acc -= Combat.TICK
		_combat.tick()
		if _combat.tick_count % 10 == 0:
			_pilot.think(_combat, 0)
		_feedback.on_sim_events(_combat.events, _combat)
	for f in _feedback.drain():
		if _sfx and f.sound != "":
			_audio.play(f.sound, f.priority)
		if f.duck:
			_audio.duck()
	_set_music(_director.state_for(_combat))
	if _combat.state != "fighting":
		_phase = "after"
		_phase_time = 0.0


func _set_music(state: String) -> void:
	_audio.set_music_state(state)
	if state != _last_state:
		print("%6.1f s  %s" % [_clock, state])
		_last_state = state
