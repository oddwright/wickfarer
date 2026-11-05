class_name SfxSynth
extends RefCounted
## Builds placeholder sounds from the "synth" recipes in data/feedback.json, so
## the game has sound before a sound designer delivers real files. A cue with a
## "file" uses that file instead; nothing in the game changes either way.
## Recipe fields: wave (sine | tri | square | saw | noise), freq, freq_end, ms,
## decay (how fast it fades, 0 = flat), noise (0..1 mixed in).
## Music layers loop and use notes (a chord) and beats (re-strikes per loop).

const RATE := 22050


static func one_shot(r: Dictionary) -> AudioStreamWAV:
	var n := maxi(1, int(float(r.get("ms", 100)) * RATE / 1000.0))
	var f0 := float(r.get("freq", 440))
	var f1 := float(r.get("freq_end", f0))
	var decay := float(r.get("decay", 3))
	var noise := clampf(float(r.get("noise", 0)), 0.0, 1.0)
	var wave := str(r.get("wave", "sine"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(r)  # the same recipe always makes the same sound
	var data := PackedFloat32Array()
	data.resize(n)
	var phase := 0.0
	var low := 0.0  # a one-pole filter gives the noise some body instead of hiss
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var tone := _wave(wave, phase, rng)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), clampf(lerpf(f0, f1, t) / 2000.0, 0.02, 1.0))
		var s := lerpf(tone, low * 2.0, noise if wave != "noise" else 1.0)
		data[i] = s * _envelope(i, n, decay)
	return _to_wav(data, false)


## A seamless loop: every note is nudged to a whole number of cycles per loop.
static func loop(r: Dictionary) -> AudioStreamWAV:
	var n := maxi(1, int(float(r.get("ms", 4000)) * RATE / 1000.0))
	var seconds := float(n) / RATE
	var beats := int(r.get("beats", 0))
	var decay := float(r.get("decay", 0))
	var wave := str(r.get("wave", "sine"))
	var notes: Array = r.get("notes", [220])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(r)
	var data := PackedFloat32Array()
	data.resize(n)
	var low := 0.0
	for i in n:
		var s := 0.0
		for f: Variant in notes:
			var cycles := maxf(1.0, roundf(float(f) * seconds))
			s += _wave(wave, cycles * i / n, rng)
		s /= maxf(1.0, notes.size())
		if wave == "noise":
			low = lerpf(low, s, 0.15)
			s = low * 3.0
		if beats > 0:
			var per := maxi(1, n / beats)
			s *= exp(-decay * float(i % per) / per)
		data[i] = s * 0.8
	return _to_wav(data, true)


static func _wave(wave: String, phase: float, rng: RandomNumberGenerator) -> float:
	var p := fposmod(phase, 1.0)
	match wave:
		"tri":
			return 4.0 * absf(p - 0.5) - 1.0
		"square":
			return 1.0 if p < 0.5 else -1.0
		"saw":
			return 2.0 * p - 1.0
		"noise":
			return rng.randf_range(-1.0, 1.0)
	return sin(TAU * p)


static func _envelope(i: int, n: int, decay: float) -> float:
	var attack := mini(int(RATE * 0.002), n / 4)  # 2 ms: no click on the way in
	var a := 1.0 if attack == 0 or i >= attack else float(i) / attack
	var t := float(i) / n
	var release := clampf((1.0 - t) * 20.0, 0.0, 1.0)  # no click on the way out
	return a * exp(-decay * t) * release


static func _to_wav(data: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w
