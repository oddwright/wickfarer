class_name AudioService
extends Node
## Plays sound cues and the adaptive music. Reads its tables from
## data/feedback.json; the game only ever says which cue or music state it wants.
## - Buses: Master > Music, SFX, UI, each with its own volume setting.
## - SFX: a fixed pool of voices; when all are busy the oldest lowest-priority
##   one is cut. Each play gets a small random pitch shift so repeats don't drone.
## - Music: every layer is a stem in one AudioStreamSynchronized, so they stay in
##   lock-step; a music state is just which layers are up. The Hush fades the
##   warm layers and closes a low-pass filter: it literally eats the music.
## - Placeholder sounds are synthesised on a worker thread at start-up (about a
##   second of work on a phone), so neither launch nor the first big hit stalls.
##   Until it finishes the game is silent, never frozen.

const VOICES := 12
const SILENT_DB := -60.0
const DUCK_DB := -6.0
const DUCK_TIME := 0.5
const HUSH_LAYER_DB := -12.0
const HUSH_CUTOFF := 600.0
const OPEN_CUTOFF := 20000.0

var music_state := "silent"
var hush := 0.0  ## 0 = far away, 1 = on top of us
var sounds: Dictionary = {}
var music: Dictionary = {}

var _voices: Array[AudioStreamPlayer] = []
var _voice_info: Array[Dictionary] = []  ## {priority, started}
var _streams: Dictionary = {}  ## sound id -> AudioStream, once built
var _built: Dictionary = {}  ## written only by the build task
var _build_task := -1
var _ready_to_play := false
var _suspended := false
var _music_player: AudioStreamPlayer
var _music_stream: AudioStreamSynchronized
var _layer_names: Array[String] = []
var _layer_db: Array[float] = []
var _duck := 0.0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()  # pitch variation only, never game rules
var _lowpass: AudioEffectLowPassFilter


func _ready() -> void:
	setup()


## Builds the buses, voices and music. _ready calls it; tests call it directly.
func setup() -> void:
	if not _voices.is_empty():
		return
	ContentDB.load_all()
	sounds = ContentDB.feedback.get("sounds", {})
	music = ContentDB.feedback.get("music", {})
	_rng.randomize()
	_make_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
		_voice_info.append({"priority": -1, "started": 0.0, "playing": false})
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	_build_task = WorkerThreadPool.add_task(_build_all, false, "build sounds")


## Runs on a worker thread: only reads the tables and makes new streams.
func _build_all() -> void:
	var out := {"sounds": {}, "layers": [], "names": []}
	for id: String in sounds:
		out.sounds[id] = _load_or_synth(sounds[id], false)
	var layers: Dictionary = music.get("layers", {})
	for name: String in layers:
		out.names.append(name)
		out.layers.append(_load_or_synth(layers[name], true))
	_built = out


## Installs the built sounds once the task is done. wait = block until it is.
func finish_build(wait := false) -> void:
	if _build_task == -1:
		return
	if not wait and not WorkerThreadPool.is_task_completed(_build_task):
		return
	WorkerThreadPool.wait_for_task_completion(_build_task)
	_build_task = -1
	_streams = _built.sounds
	_make_music(_built.names, _built.layers)
	_built = {}
	_ready_to_play = true


func _make_buses() -> void:
	for bus in ContentDB.SOUND_BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	# Stacked hits must never clip on a phone speaker.
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		AudioServer.add_bus_effect(master, AudioEffectHardLimiter.new())
	var mi := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(mi) == 0:
		AudioServer.add_bus_effect(mi, AudioEffectLowPassFilter.new())
	_lowpass = AudioServer.get_bus_effect(mi, 0) as AudioEffectLowPassFilter
	_lowpass.cutoff_hz = OPEN_CUTOFF


func apply_settings(s: GameSettings) -> void:
	for bus: String in s.volume:
		var i := AudioServer.get_bus_index(bus)
		if i == -1:
			continue
		var v := float(s.volume[bus])
		AudioServer.set_bus_mute(i, v <= 0.0)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))


## Plays a sound from the table. Returns false if it doesn't exist.
func play(id: String, priority := 0) -> bool:
	var stream: AudioStream = _streams.get(id)
	if stream == null or not _ready_to_play or _suspended:
		return false
	var s: Dictionary = sounds[id]
	var v := _pick_voice(priority)
	if v == -1:
		return false
	var p := _voices[v]
	p.stream = stream
	p.bus = str(s.get("bus", "SFX"))
	p.volume_db = float(s.get("volume_db", 0))
	var jitter := float(s.get("pitch_jitter", 0))
	p.pitch_scale = 1.0 + _rng.randf_range(-jitter, jitter)
	p.play()
	_voice_info[v] = {"priority": priority, "started": _clock, "playing": true}
	return true


func _pick_voice(priority: int) -> int:
	for i in _voices.size():
		_voice_info[i]["playing"] = _voices[i].playing
	return pick_voice(_voice_info, priority)


## A free voice, else the oldest of the quietest-priority voices at or below
## this priority, else -1 (everything playing matters more).
static func pick_voice(voices: Array[Dictionary], priority: int) -> int:
	var best := -1
	for i in voices.size():
		var v := voices[i]
		if not v.get("playing", false):
			return i
		if int(v.priority) > priority:
			continue
		if best == -1:
			best = i
			continue
		var b := voices[best]
		var lower := int(v.priority) < int(b.priority)
		var older := int(v.priority) == int(b.priority) and float(v.started) < float(b.started)
		if lower or older:
			best = i
	return best


static func _load_or_synth(entry: Dictionary, looped: bool) -> AudioStream:
	var file := str(entry.get("file", ""))
	if file != "" and ResourceLoader.exists(file):
		var stream: AudioStream = load(file)
		if looped and stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true  # stems must loop together
		return stream
	if entry.has("synth"):
		return SfxSynth.loop(entry.synth) if looped else SfxSynth.one_shot(entry.synth)
	return null


# ------------------------------------------------------------------ music


func _make_music(names: Array, streams: Array) -> void:
	_music_stream = AudioStreamSynchronized.new()
	_music_stream.stream_count = streams.size()
	for i in streams.size():
		_music_stream.set_sync_stream(i, streams[i])
		_music_stream.set_sync_stream_volume(i, SILENT_DB)
		_layer_names.append(str(names[i]))
		_layer_db.append(SILENT_DB)
	_music_player.stream = _music_stream


func set_music_state(state: String) -> void:
	if not (music.get("states", {}) as Dictionary).has(state):
		return
	music_state = state
	_start_music()


func _start_music() -> void:
	# A paused player also reports playing == false, and play() would restart it.
	var idle := not _music_player.playing and not _music_player.stream_paused
	if (
		_ready_to_play
		and not _suspended
		and idle
		and _music_player.is_inside_tree()
		and not layer_targets().is_empty()
	):
		_music_player.play()


## Briefly lowers the music so a big hit cuts through.
func duck() -> void:
	_duck = DUCK_TIME


## The volume each layer is heading for in the current state and Hush.
func layer_targets() -> Dictionary:
	var out := {}
	var up: Array = music.get("states", {}).get(music_state, [])
	var hushed: Array = music.get("hush_layers", [])
	for name: String in up:
		var db := float(music.layers[name].get("volume_db", 0))
		if name in hushed:
			db += HUSH_LAYER_DB * hush
		out[name] = db
	return out


func _process(delta: float) -> void:
	finish_build()
	_clock += delta
	_duck = maxf(0.0, _duck - delta)
	var targets := layer_targets()
	var fade := maxf(0.05, float(music.get("fade", 1.5)))
	var step := absf(SILENT_DB) * delta / fade
	var duck_db := DUCK_DB * (_duck / DUCK_TIME)
	for i in _layer_names.size():
		var goal := float(targets.get(_layer_names[i], SILENT_DB))
		_layer_db[i] = move_toward(_layer_db[i], goal, step)
		_music_stream.set_sync_stream_volume(i, _layer_db[i] + duck_db)
	_start_music()
	if _lowpass:
		var goal_hz := lerpf(OPEN_CUTOFF, HUSH_CUTOFF, hush)
		_lowpass.cutoff_hz = lerpf(_lowpass.cutoff_hz, goal_hz, clampf(delta * 2.0, 0.0, 1.0))


## Phones can pause the app at any time: silence everything until it's back.
func suspend(on: bool) -> void:
	_suspended = on
	_music_player.stream_paused = on
	if on:
		for p in _voices:
			p.stop()


func _exit_tree() -> void:
	finish_build(true)  # never free this node with the worker still writing to it
