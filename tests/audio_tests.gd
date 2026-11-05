extends RefCounted
## Audio and music checks for tests/run_tests.gd, kept here so that file stays
## under the lint limit. Each takes the runner, whose check() records the result.

const MAIN = preload("res://scripts/view/main.gd")
const IMMEDIATE := AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE
const NEXT_BEAT := AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BEAT
const NEXT_BAR := AudioStreamInteractive.TRANSITION_FROM_TIME_NEXT_BAR
const AT_END := AudioStreamInteractive.TRANSITION_FROM_TIME_END


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


static func service_and_states(t: SceneTree) -> void:
	for id: String in ContentDB.feedback.sounds:
		var w := SfxSynth.one_shot(ContentDB.feedback.sounds[id].synth)
		_check(t, w.data.size() > 100, "sound %s synthesises" % id)
	# Headless tests run outside the scene tree, so players can't really play:
	# check the voice choice on its own.
	var voices: Array[Dictionary] = []
	for i in 3:
		voices.append({"playing": true, "priority": 2, "started": float(i)})
	_check(t, AudioService.pick_voice(voices, 0) == -1, "a tick can't cut louder cues")
	_check(t, AudioService.pick_voice(voices, 4) == 0, "a kill takes the oldest voice")
	voices[1].priority = 1
	_check(t, AudioService.pick_voice(voices, 4) == 1, "the least important voice goes first")
	voices[2].playing = false
	_check(t, AudioService.pick_voice(voices, 0) == 2, "a free voice is always used")
	var a := AudioService.new()
	a.setup()
	_check(t, not a.play("ui_tick"), "nothing plays until the sounds are built")
	a.finish_build(true)
	_check(t, AudioServer.get_bus_index("SFX") != -1, "the SFX bus exists")
	_check(t, not a.play("no_such_sound"), "an unknown sound doesn't play")
	_check(t, a._streams.size() == ContentDB.feedback.sounds.size(), "every sound is built")
	_check(t, a._clips.size() == ContentDB.feedback.music.clips.size(), "every clip is built")
	a.suspend(true)
	a.set_music_state("chart")
	_check(t, not a._music_player.playing, "a suspended game starts no music")
	a.suspend(false)
	a.set_music_state("engage")
	_check(t, not a.layer_targets().has("lead"), "a fight opens without the theme")
	a.set_music_state("engage_full")
	_check(t, a.layer_targets().has("pressure"), "the full fight brings in the brass")
	a.set_music_state("chart")
	var open: float = a.layer_targets().warm
	a.hush = 1.0
	_check(t, a.layer_targets().warm < open, "the Hush eats the warm layer")
	a.set_music_state("no_such_state")
	_check(t, a.music_state == "chart", "unknown states are ignored")
	var s := GameSettings.new()
	s.volume.Music = 0.0
	a.apply_settings(s)
	_check(t, AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "volume 0 mutes")
	a.free()
	var main: Node = MAIN.new()
	main.run = Run.create(77)
	_check(t, main.music_state() == "chart", "the chart plays the chart music")
	main.run._start_fight("ashmarket_skiff")
	main.combat = main.run.combat
	_check(t, main.music_state() == "engage", "a fight opens on the engage stage")
	_check(t, not main.music_muffled(), "and isn't muffled")
	main.paused = true
	_check(t, main.music_muffled(), "pausing the fight muffles it")
	main.combat.player().hull = 1
	_check(t, main.music_state() == "danger", "low hull plays the danger music")
	main.free()


## The fight's stages only climb, and each has a reason in the fight.
static func director_stages(t: SceneTree) -> void:
	var d := MusicDirector.new()
	var c := Combat.create(5)
	_check(t, d.state_for(c) == "engage", "a fight opens on drums, bass and strings")
	c.enemy().hull -= 1
	_check(t, d.state_for(c) == "engage_theme", "the theme comes in with the first hit")
	c.enemy().hull += 1
	_check(t, d.state_for(c) == "engage_theme", "and stays in")
	c.player().rooms[0].fire = 20.0
	_check(t, d.state_for(c) == "engage_full", "a fire aboard brings in the full band")
	var c2 := Combat.create(6)
	_check(t, d.state_for(c2) == "engage", "the next fight starts over")
	c2.tick_count = ceili(MusicDirector.THEME_AFTER / Combat.TICK)
	_check(t, d.state_for(c2) == "engage_theme", "the theme comes in in time anyway")
	c2.tick_count = ceili(MusicDirector.FULL_AFTER / Combat.TICK)
	_check(t, d.state_for(c2) == "engage_full", "and so does the band")
	var c3 := Combat.create(7)
	d.state_for(c3)
	c3.player().hull -= ceili(c3.player().max_hull * MusicDirector.FULL_HULL_LOST)
	_check(t, d.state_for(c3) == "engage_full", "losing a quarter of our hull raises the stakes")
	c3.enemy().hull = floori(c3.enemy().max_hull * MusicDirector.KILL_HULL)
	_check(t, d.state_for(c3) == "kill", "their hull low: the kill window")
	c3.player().hull = floori(c3.player().max_hull * MusicDirector.DANGER_HULL)
	_check(t, d.state_for(c3) == "danger", "our hull low beats theirs")
	c3.state = "won"
	_check(t, d.state_for(c3) == "victory", "a win plays the victory")
	c3.state = "lost"
	_check(t, d.state_for(c3) == "defeat", "a loss plays the defeat")
	var resumed := Combat.create(8)
	resumed.tick_count = 200
	_check(t, d.state_for(resumed) == "engage_theme", "a fight resumed from a save keeps its theme")


## How clips hand over: intros first, bar-line cuts within the fight, the
## victory on the next beat, and other tempos at once.
static func clips_and_transitions(t: SceneTree) -> void:
	var clips: Dictionary = ContentDB.feedback.music.clips
	var nc := func(want: String, now: String) -> String:
		return AudioService.next_clip(clips, want, now)
	_check(t, nc.call("engage", "hearth") == "arrival", "a fight opens with the arrival")
	_check(t, nc.call("engage", "") == "arrival", "even from silence")
	_check(t, nc.call("engage", "arrival") == "engage", "which hands over to engage")
	_check(t, nc.call("kill", "engage") == "surge", "the kill window opens with the surge")
	_check(t, nc.call("kill", "surge") == "kill", "which hands over to the kill")
	_check(t, nc.call("kill", "hearth") == "kill", "the surge only follows engage")
	_check(t, nc.call("victory", "kill") == "victory", "victory has no intro")
	_check(t, nc.call("", "kill") == "", "silence is no clip")
	var s := AudioService.build_music(clips)
	var at := func(from: String, to: String) -> int:
		return s.get_transition_from_time(clips.keys().find(from), clips.keys().find(to))
	_check(t, at.call("arrival", "engage") == AT_END, "the arrival plays to its end")
	_check(t, at.call("surge", "kill") == AT_END, "and so does the surge")
	_check(t, at.call("engage", "surge") == NEXT_BAR, "the surge cuts in on the bar line")
	_check(t, at.call("engage", "danger") == NEXT_BAR, "so does danger")
	_check(t, at.call("kill", "victory") == NEXT_BEAT, "victory lands on the next beat")
	_check(t, at.call("kill", "defeat") == IMMEDIATE, "defeat cuts in at once")
	_check(t, at.call("hearth", "danger") == IMMEDIATE, "another tempo shares no bar line")
	var fade := func(from: String, to: String) -> int:
		return s.get_transition_fade_mode(clips.keys().find(from), clips.keys().find(to))
	_check(t, fade.call("kill", "victory") == AudioStreamInteractive.FADE_OUT, "fights cut in")
	_check(
		t, fade.call("victory", "hearth") == AudioStreamInteractive.FADE_CROSS, "warmth fades in"
	)
	var v := clips.keys().find("victory")
	var advance := s.get_clip_auto_advance(v) == AudioStreamInteractive.AUTO_ADVANCE_ENABLED
	_check(t, advance, "the victory hands over by itself")
	_check(t, s.get_clip_auto_advance_next_clip(v) == clips.keys().find("hearth"), "to the hearth")


## Every clip's stems are real files that share loop, tempo and length, the fight
## music cuts in whole bars, and the main fight loop is long enough not to wear.
static func clips_are_synced_stems(t: SceneTree) -> void:
	var music: Dictionary = ContentDB.feedback.music
	var errors: Array[String] = []
	ContentDB._validate_music(music, errors)
	_check(t, errors.is_empty(), "the music table is valid: %s" % [errors])
	for id: String in music.clips:
		var shape := ContentDB._clip_shape(id, music.clips[id], errors)
		var once: bool = music.clips[id].get("once", false)
		_check(t, not shape.is_empty() and shape[0] != once, "%s loops unless it plays once" % id)
	var engage := ContentDB._clip_shape("engage", music.clips.engage, errors)
	_check(t, int(engage[2]) >= 128, "the fight loop runs 32 bars before it repeats")
	var bad: Dictionary = music.duplicate(true)
	bad.clips.defeat.then = "nowhere"
	bad.clips.kill.enter = "whenever"
	bad.clips.surge.layers.core.file = "res://audio/music/ember_engage_core.ogg"
	bad.clips.hearth.intro = "engage"
	bad.states.chart.clip = "jukebox"
	bad.clips.defeat.fade = "dissolve"
	bad.states.danger.layers = ["core", "pressure"]
	bad.states.store = ["pad"]
	bad.clips.engage.intro_from = "hearth"
	bad.clips.danger.once = true
	errors.clear()
	ContentDB._validate_music(bad, errors)
	_check(t, errors.size() == 10, "every broken music field is caught, got %s" % [errors])
