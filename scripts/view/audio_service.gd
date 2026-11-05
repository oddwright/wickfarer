class_name AudioService
extends Node
## Plays sound cues and the adaptive music. Reads its tables from
## data/feedback.json; the game only ever says which cue or music state it wants.
## - Buses: Master > Music, SFX, UI, each with its own volume setting.
## - SFX: a fixed pool of voices; when all are busy the oldest lowest-priority
##   one is cut. Each play gets a small random pitch shift so repeats don't drone.
## - Music: one AudioStreamInteractive whose clips (hearth, arrival, engage,
##   danger, surge, kill, victory, defeat) are each an AudioStreamSynchronized of
##   stems, so a clip's layers stay in lock-step. A music state names a clip and
##   which layers are up: layers fade within a clip, and clips cut on the next
##   beat or bar of the music (data "enter"), so every change lands in time.
##   A clip's intro plays first (arrival before engage, surge before kill).
##   The Hush fades the warm layers and closes a low-pass filter: it literally
##   eats the music. A paused fight muffles it, as if heard through the hull.
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
const MUFFLE_CUTOFF := 900.0
const MUFFLE_DB := -6.0
const LEAVING_TIME := 2.0  ## seconds a clip we just left keeps its mix while it fades
const FADES := {"out": AudioStreamInteractive.FADE_OUT, "cross": AudioStreamInteractive.FADE_CROSS}
const ENTER := {
	"now": AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE,
	"beat": AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BEAT,
	"bar": AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BAR,
}

var music_state := "silent"
var hush := 0.0  ## 0 = far away, 1 = on top of us
var muffle := false  ## a paused fight: the music plays on, muffled
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
var _music_stream: AudioStreamInteractive
var _clips: Array[String] = []  ## clip names, by clip index
var _clip_sync: Array[AudioStreamSynchronized] = []
var _clip_layers: Array[PackedStringArray] = []  ## layer names of each clip
var _clip_db: Array[PackedFloat32Array] = []  ## each layer's volume right now
var _asked := ""  ## the clip we last switched to
var _playing_clip := ""
var _leaving := ""  ## the clip we just left, fading out on its own
var _leaving_time := 0.0
var _muffle_db := 0.0
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
	var out := {"sounds": {}}
	for id: String in sounds:
		if str(sounds[id].get("file", "")) == "":
			out.sounds[id] = SfxSynth.one_shot(sounds[id].synth)
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
	for id: String in sounds:
		if not _streams.has(id):
			_streams[id] = _load_or_synth(sounds[id])  # files load on this thread (see _make_music)
	_make_music()
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


static func _load_or_synth(entry: Dictionary) -> AudioStream:
	var file := str(entry.get("file", ""))
	if file != "" and ResourceLoader.exists(file):
		return load(file)
	if entry.has("synth"):
		return SfxSynth.one_shot(entry.synth)
	return null


# ------------------------------------------------------------------ music


## Stems load here on the main thread: loading resources from the worker
## leaves Godot's load tokens behind. Ogg stems only read their packets, so it's quick.
func _make_music() -> void:
	var clips: Dictionary = music.get("clips", {})
	_music_stream = build_music(clips)
	for i in _music_stream.clip_count:
		_clips.append(_music_stream.get_clip_name(i))
		_clip_sync.append(_music_stream.get_clip_stream(i) as AudioStreamSynchronized)
		_clip_layers.append(PackedStringArray(clips[_clips[i]].layers.keys()))
		var dbs := PackedFloat32Array()
		dbs.resize(_clip_layers[i].size())
		dbs.fill(SILENT_DB)
		_clip_db.append(dbs)
	_music_player.stream = _music_stream


## One interactive stream: a clip per entry in "clips", each the clip's stems in
## lock-step, all silent until a state brings their layers up.
static func build_music(clips: Dictionary) -> AudioStreamInteractive:
	var s := AudioStreamInteractive.new()
	s.clip_count = clips.size()
	var i := 0
	for name: String in clips:
		var layers: Dictionary = clips[name].layers
		var sync := AudioStreamSynchronized.new()
		sync.stream_count = layers.size()
		var k := 0
		for layer: String in layers:
			sync.set_sync_stream(k, load(str(layers[layer].file)))  # validated
			sync.set_sync_stream_volume(k, SILENT_DB)
			k += 1
		s.set_clip_name(i, name)
		s.set_clip_stream(i, sync)
		i += 1
	add_transitions(s, clips)
	return s


## Every pair of clips gets a transition: wait for the new clip's beat or bar
## ("enter") and fade the old one out over "fade_beats" ("fade": "cross" also
## fades the new one in). An intro hands over
## exactly at its end; music at another tempo shares no bar line, so cuts at once.
static func add_transitions(s: AudioStreamInteractive, clips: Dictionary) -> void:
	var names: Array = clips.keys()
	for to in names.size():
		var c: Dictionary = clips[names[to]]
		var fade := float(c.get("fade_beats", 1))
		for from in names.size():
			if from == to:
				continue
			var when: int = ENTER.get(str(c.get("enter", "now")), ENTER.now)
			if _bpm(s, from) != _bpm(s, to):
				when = ENTER.now
			var mode: int = FADES.get(str(c.get("fade", "out")), FADES.out)
			if fade <= 0.0:
				mode = AudioStreamInteractive.FADE_DISABLED
			var beats := fade
			if str(c.get("intro", "")) == names[from]:
				when = AudioStreamInteractive.TRANSITION_FROM_TIME_END
				mode = AudioStreamInteractive.FADE_DISABLED
				beats = 0.0
			s.add_transition(
				from, to, when, AudioStreamInteractive.TRANSITION_TO_TIME_START, mode, beats
			)
		if c.has("then"):
			s.set_clip_auto_advance(to, AudioStreamInteractive.AUTO_ADVANCE_ENABLED)
			s.set_clip_auto_advance_next_clip(to, names.find(c.then))


static func _bpm(s: AudioStreamInteractive, clip: int) -> float:
	var sync := s.get_clip_stream(clip) as AudioStreamSynchronized
	if sync == null or sync.stream_count == 0:
		return 0.0
	var stem := sync.get_sync_stream(0) as AudioStreamOggVorbis
	return stem.bpm if stem else 0.0


## The clip to switch to on the way to `want`: its intro first, unless we are
## in the intro already or come from a clip the intro doesn't fit ("intro_from").
static func next_clip(clips: Dictionary, want: String, current: String) -> String:
	if want == "" or want == current or not clips.has(want):
		return want
	var intro := str(clips[want].get("intro", ""))
	var from: Array = clips[want].get("intro_from", [])
	if intro == "" or current == intro or (not from.is_empty() and not current in from):
		return want
	return intro


func set_music_state(state: String) -> void:
	if not (music.get("states", {}) as Dictionary).has(state):
		return
	music_state = state
	_start_music()


func _state() -> Dictionary:
	return music.get("states", {}).get(music_state, {})


func _start_music() -> void:
	# A paused player also reports playing == false, and play() would restart it.
	var idle := not _music_player.playing and not _music_player.stream_paused
	var want := str(_state().get("clip", ""))
	if not (_ready_to_play and not _suspended and idle and want != ""):
		return
	if not _music_player.is_inside_tree():
		return
	_asked = next_clip(music.clips, want, "")
	_music_stream.initial_clip = _clips.find(_asked)
	_set_levels(0.0, true)  # the first clip starts at its mix, not from silence
	_music_player.play()


## Asks for the next clip once the last ask has been heard, or at once for a clip
## that can't wait (victory, defeat): a pending bar-line cut is simply replaced.
func _follow_state() -> void:
	if not _music_player.playing:
		_playing_clip = ""
		return
	var pb := _music_player.get_stream_playback() as AudioStreamPlaybackInteractive
	var now := _clips[pb.get_current_clip_index()] if pb.get_current_clip_index() >= 0 else ""
	if now != _playing_clip:
		_leaving = _playing_clip
		_leaving_time = LEAVING_TIME
		_playing_clip = now
	var want := str(_state().get("clip", ""))
	var next := next_clip(music.clips, want, now)
	if next == "" or next == now or next == _asked:
		return
	pb.switch_to_clip(_clips.find(next))
	_asked = next


## Duck a big hit.
func duck() -> void:
	_duck = DUCK_TIME


## The volume each layer is heading for in the current state and Hush.
func layer_targets() -> Dictionary:
	var out := {}
	var hushed: Array = music.get("hush_layers", [])
	var clip := str(_state().get("clip", ""))
	var spec: Dictionary = music.get("clips", {})
	for name: String in _state().get("layers", []):
		out[name] = _layer_db_in(spec, clip, name)
		if name in hushed:
			out[name] += HUSH_LAYER_DB * hush
	return out


## A layer's mix level: from the state's clip, or else from any clip that has it
## (a state's layers can live in its clip's intro or "then" clip).
static func _layer_db_in(clips: Dictionary, clip: String, layer: String) -> float:
	if clips.get(clip, {}).get("layers", {}).has(layer):
		return float(clips[clip].layers[layer].get("volume_db", 0))
	for c: String in clips:
		if clips[c].layers.has(layer):
			return float(clips[c].layers[layer].get("volume_db", 0))
	return 0.0


func _process(delta: float) -> void:
	finish_build()
	_clock += delta
	_duck = maxf(0.0, _duck - delta)
	_leaving_time = maxf(0.0, _leaving_time - delta)
	_muffle_db = move_toward(
		_muffle_db, MUFFLE_DB if muffle else 0.0, absf(MUFFLE_DB) * delta * 2.0
	)
	if _music_stream == null:
		return
	_start_music()
	_follow_state()
	_set_levels(delta)
	_stop_when_silent()
	if _lowpass:
		var goal_hz := lerpf(OPEN_CUTOFF, HUSH_CUTOFF, hush)
		if muffle:
			goal_hz = minf(goal_hz, MUFFLE_CUTOFF)
		_lowpass.cutoff_hz = lerpf(_lowpass.cutoff_hz, goal_hz, clampf(delta * 2.0, 0.0, 1.0))


## Layers of the playing clip fade toward the state; every other clip is set at
## once, so it starts at the right mix. The clip we just left keeps its levels
## while the transition fades it out.
func _set_levels(delta: float, snap := false) -> void:
	var targets := layer_targets()
	var fade := maxf(0.05, float(music.get("fade", 1.5)))
	var step := absf(SILENT_DB) * delta / fade
	var extra := DUCK_DB * (_duck / DUCK_TIME) + _muffle_db
	for c in _clips.size():
		var live := _clips[c] == _playing_clip and not snap
		if _clips[c] == _leaving and _leaving_time > 0.0:
			continue
		for k in _clip_layers[c].size():
			var goal := float(targets.get(_clip_layers[c][k], SILENT_DB))
			_clip_db[c][k] = move_toward(_clip_db[c][k], goal, step) if live else goal
			_clip_sync[c].set_sync_stream_volume(k, _clip_db[c][k] + extra)


## Every stem decodes even at -60 dB, which costs battery: stop once silent.
func _stop_when_silent() -> void:
	if str(_state().get("clip", "")) != "" or not _music_player.playing:
		return
	for dbs in _clip_db:
		for db in dbs:
			if db > SILENT_DB:
				return
	_music_player.stop()
	_asked = ""


## Phones can pause the app at any time: silence everything until it's back.
func suspend(on: bool) -> void:
	_suspended = on
	_music_player.stream_paused = on
	if on:
		for p in _voices:
			p.stop()


func _exit_tree() -> void:
	finish_build(true)  # never free this node with the worker still writing to it
