"""Wickfarer combat score: "Ember Rising" (original), rendered as synced stems.

The fight is told in pieces, all at 144 bpm in 4/4 so the game can cut between
them on any bar line (AudioStreamInteractive), and each piece is split into
layers that fade in and out with the fight (AudioStreamSynchronized):

  arrival  4 bars, once  - a horn call, taiko build, riser, one beat of silence
  engage  32 bars, loop  - the fight: A (the rhythmic theme), B (it soars)
  danger  16 bars, loop  - our hull is low: half-time, heartbeat kick, phrygian
  surge    1 bar,  once  - the filler between engage and kill: a climb to B major
  kill     8 bars, loop  - their hull is low: up a step to E, four on the floor
  victory  6 bars, once  - the theme as a fanfare, bVI-bVII-I into E major
  defeat   6 bars, once  - the motif, slow and broken, swallowed by the Hush

The palette is "orchestral but pixely": chip waves (pulse, triangle, saw,
noise) standing in for an orchestra. Bass is driven hard so it still reads on a
phone speaker, which drops everything under ~200 Hz, and the kick ducks the
bass and ostinato (baked side-chain) so every hit pumps.

Usage: python3 tools/music/ember_rising.py audio/music [demo.wav]
Writes audio/music/ember_<piece>_<layer>.ogg and sets its .import (loop, bpm,
beat count; run godot --import after); with a second path it also
writes a demo of a whole fight. Needs numpy, scipy and ffmpeg.
Never hand-edit the .ogg files: change this score and re-render.
"""

import os
import shutil
import subprocess
import sys
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, lfilter, sosfilt
from stem_io import write_import

SR = 44100
BPM = 144
BEAT = 60.0 / BPM
BAR_SAMPLES = int(round(4 * BEAT * SR))  # 73500: every piece is a whole number of these
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
DEMO = sys.argv[2] if len(sys.argv) > 2 else ""
if shutil.which("ffmpeg") is None:
    sys.exit("ffmpeg is needed to write Ogg Vorbis stems")
rng = np.random.default_rng(2026)

NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
        "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(name):
    n, octv = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTE[n] + 12 * (octv + 1) - 69) / 12)


def shift(name, octaves):
    return name[:-1] + str(int(name[-1]) + octaves)


# ---------------------------------------------------------------- dsp helpers


def onepole(x, cutoff):
    a = np.exp(-2 * np.pi * min(cutoff, SR * 0.45) / SR)
    return lfilter([1 - a], [1, -a], x)


def sweep_lowpass(x, cutoff, block=256):
    """A one-pole low-pass whose cutoff follows a per-sample curve (read once a block)."""
    y = np.zeros_like(x)
    z = 0.0
    for i in range(0, len(x), block):
        a = np.exp(-2 * np.pi * min(float(cutoff[i]), SR * 0.45) / SR)
        seg, zf = lfilter([1 - a], [1, -a], x[i : i + block], zi=[z * a])
        y[i : i + block] = seg
        z = seg[-1]
    return y


def highpass(x, cutoff):
    return x - onepole(x, cutoff)


def env(n, attack, release, decay=0.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((n / SR - t) / max(release, 1e-4), 0, 1)
    d = np.exp(-decay * t) if decay > 0 else 1.0
    return a * r * d


def phase(f, n, vib=0.0, vib_delay=0.25, glide_from=None):
    t = np.arange(n) / SR
    inst = np.full(n, f)
    if glide_from:
        inst = f + (glide_from - f) * np.exp(-t * 40)
    depth = vib * np.clip((t - vib_delay) / 0.3, 0, 1)
    inst = inst * (1 + depth * np.sin(2 * np.pi * 5.5 * t))
    return np.cumsum(inst) / SR


def pulse(ph, duty):
    return np.where(np.mod(ph, 1.0) < duty, 1.0, -1.0)


def tri(ph):
    return 4 * np.abs(np.mod(ph, 1.0) - 0.5) - 1


def saw(ph):
    return 2 * np.mod(ph, 1.0) - 1


def crunch(x, hold=2, levels=40, smooth=7000):
    """Sample-and-hold plus amplitude steps: the 'pixel' grain, then a gentle top cut."""
    y = np.repeat(x[::hold], hold)[: len(x)]
    y = np.round(y * levels) / levels
    return onepole(y, smooth)


def noise(n):
    return rng.uniform(-1, 1, n)


def secs(beats):
    return int(round(beats * BEAT * SR))


# ---------------------------------------------------------------- instruments


def kick(amp=0.9):
    n = int(0.38 * SR)
    t = np.arange(n) / SR
    f = 52 + 130 * np.exp(-t * 30)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11)
    knock = np.sin(2 * np.pi * 165 * t) * np.exp(-t * 45) * 0.5  # what a phone speaker can play
    click = highpass(noise(n), 3000) * np.exp(-t * 300) * 0.6
    return np.tanh((body + knock + click) * 2.4) * amp


def snare(amp=0.5):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 28)
    rattle = highpass(noise(n), 1200) * np.exp(-t * 16)
    return crunch(0.6 * tone + rattle, hold=2, levels=24, smooth=9000) * amp


def hat(amp=0.12, open_=False):
    n = int((0.25 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    return highpass(noise(n), 7000) * np.exp(-t * (14 if open_ else 70)) * amp


def tom(name, amp=0.55):
    """Pixel taiko: a pitched thump that falls into its note."""
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    f = hz(name)
    ph = np.cumsum(f * (1 + 0.6 * np.exp(-t * 25))) / SR
    body = np.sin(2 * np.pi * ph) * np.exp(-t * 6)
    slap = onepole(noise(n), 1500) * np.exp(-t * 40) * 0.8
    return np.tanh((body + slap) * 1.6) * amp


def crash(amp=0.22):
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    return highpass(noise(n), 4000) * np.exp(-t * 2.2) * amp


def boom(amp=0.8):
    n = int(2.5 * SR)
    t = np.arange(n) / SR
    f = 32 + 50 * np.exp(-t * 6)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.6)
    grit = onepole(noise(n), 600) * np.exp(-t * 3) * 0.6
    return np.tanh((body + grit) * 1.8) * amp


def riser(beats, amp=0.25):
    n = secs(beats)
    t = np.arange(n) / n
    x = noise(n)
    lo, hi = onepole(x, 800), onepole(x, 9000)
    sweep = lo * (1 - t) + hi * t
    tone = np.sin(2 * np.pi * np.cumsum(200 + 1400 * t**2) / SR) * 0.3
    return (sweep + tone) * t**2 * amp


def bass(name, beats, amp=0.32):
    """Driven pulse+saw with a sine sub: the harmonics carry it on phone speakers."""
    n = secs(beats)
    f = hz(name)
    ph = phase(f, n)
    s = 0.6 * pulse(ph, 0.5) + 0.5 * saw(ph)
    s = np.tanh(onepole(s, 1600) * 2.5)
    sub = np.sin(2 * np.pi * ph) * 0.3
    return (s * 0.8 + sub) * env(n, 0.003, 0.03) * amp


def drone(name, beats, amp=0.2):
    n = secs(beats)
    f = hz(name)
    s = saw(phase(f * 0.998, n)) + saw(phase(f * 1.002, n))
    return onepole(onepole(s, 380), 600) * env(n, 0.5, 0.5) * amp


def ost(name, length=0.24, amp=0.24):
    """Staccato 'strings': a narrow pulse that snaps off."""
    n = int(length * SR)
    s = pulse(phase(hz(name), n), 0.25)
    return crunch(onepole(s, 4200), hold=2, levels=32) * env(n, 0.002, 0.02, decay=14) * amp


def brass(names, beats, amp=0.12, stab=True):
    """Chip brass: stacked saw/pulse with a filter that opens on the attack."""
    n = secs(beats) if not stab else int(0.28 * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for nm in names:
        f = hz(nm)
        s += saw(phase(f * 0.997, n)) + 0.7 * pulse(phase(f * 1.004, n), 0.5)
    s /= max(1, len(names))
    opening = np.exp(-t * (18 if stab else 4))
    dark, bright = onepole(s, 700), onepole(s, 4200)
    s = dark * (1 - opening) + bright * opening
    return np.tanh(s * 1.5) * env(n, 0.008, 0.06 if stab else 0.25) * amp


def lead(name, beats, amp=0.2, glide_from=None):
    """The bowed pulse from the hearth theme, doubled an octave down for weight."""
    n = secs(beats)
    f = hz(name)
    ph = phase(f, n, vib=0.007, vib_delay=0.18, glide_from=glide_from)
    s = 0.75 * pulse(ph, 0.25) + 0.35 * pulse(ph * 0.5, 0.5)
    s = crunch(onepole(s, 3600), hold=2, levels=48)
    return s * env(n, 0.03, 0.06) * amp


def choir(names, beats, amp=0.07):
    n = secs(beats)
    s = np.zeros(n)
    for nm in names:
        f = hz(nm)
        for d in (0.996, 1.0, 1.004):
            s += tri(phase(f * d, n)) + 0.4 * pulse(phase(f * d, n), 0.5)
    s = onepole(onepole(s, 1800), 2600) / (3 * len(names))
    return s * env(n, 0.25, 0.4) * amp


def heartbeat(amp=0.75):
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    one = np.sin(2 * np.pi * np.cumsum(55 + 60 * np.exp(-t * 30)) / SR) * np.exp(-t * 12)
    one += onepole(noise(n), 900) * np.exp(-t * 35) * 0.5  # the thud you hear on a speaker
    two = np.zeros(n)
    k = int(0.2 * SR)
    two[k:] = one[: n - k] * 0.6
    return np.tanh((one + two) * 1.8) * amp


# ---------------------------------------------------------------- score helpers


class Piece:
    def __init__(self, name, bars, loop, layers, ring=False):
        """ring = a one-shot that fades away over its last half bar (else it ends hard)."""
        self.name, self.bars, self.loop, self.ring = name, bars, loop, ring
        self.n = bars * BAR_SAMPLES
        self.tracks = {k: np.zeros(self.n + 6 * SR) for k in layers}
        self.kicks = []  # beat positions, for the side-chain

    def put(self, layer, beat, sig):
        i = secs(beat)
        buf = self.tracks[layer]
        j = min(len(buf), i + len(sig))
        buf[i:j] += sig[: j - i]

    def line(self, layer, start_beat, text, voice, beats=None, **kw):
        """'D5:.75 D5:.25 r:.5 ...' -> notes from start_beat. beats = how long it must be."""
        total = sum(float(t.split(":")[1]) for t in text.split())
        assert beats is None or abs(total - beats) < 1e-6, f"{text[:30]}... is {total} beats, not {beats}"
        b = start_beat
        for tok in text.split():
            name, d = tok.split(":")
            d = float(d)
            if name != "r":
                self.put(layer, b, voice(name, d, **kw))
            b += d
        return b


def chord_tones(ch):
    return {
        "Dm": ["D", "F", "A"], "Bb": ["Bb", "D", "F"], "C": ["C", "E", "G"],
        "A": ["A", "C#", "E"], "Gm": ["G", "Bb", "D"], "Eb": ["Eb", "G", "Bb"],
        "Em": ["E", "G", "B"], "G": ["G", "B", "D"], "D": ["D", "F#", "A"],
        "B": ["B", "D#", "F#"], "Am": ["A", "C", "E"], "F": ["F", "A", "C"],
        "E": ["E", "G#", "B"],
    }[ch]


def drums_engage(p, bar, fill=False, layer="core", lift=False):
    b = bar * 4
    for k in [0, 1.5, 2, 2.75]:  # driving kick: syncopated, lands hard on 1 and 3
        if k == 2.75 and fill:
            continue
        p.put(layer, b + k, kick())
        p.kicks.append(b + k)
    p.put(layer, b + 1, snare())
    p.put(layer, b + 3, snare())
    for k in range(8):
        if lift and k % 2 == 1:  # the B section opens up: open hats on the off-beats
            p.put(layer, b + k * 0.5, hat(0.09, open_=True))
        else:
            p.put(layer, b + k * 0.5, hat(0.1 if k % 2 == 0 else 0.07))
    if fill:  # a tom run into the next phrase
        for k, nm in enumerate(["D3", "D3", "A2", "A2", "F2", "D2"]):
            p.put(layer, b + 2.5 + k * 0.25, tom(nm, 0.45))


def ostinato(p, bar, ch, layer="ostinato", sixteenths=True, octave=4, climb=False):
    r, third, fifth = chord_tones(ch)
    root = f"{r}{octave}"
    pattern = [root, root, f"{fifth}{octave}", root, f"{r}{octave + 1}", root, f"{fifth}{octave}", f"{third}{octave}"]
    if climb:  # B section: the strings climb the chord instead of hammering the root
        pattern = [root, f"{third}{octave}", f"{fifth}{octave}", f"{r}{octave + 1}",
                   f"{third}{octave + 1}", f"{r}{octave + 1}", f"{fifth}{octave}", f"{third}{octave}"]
    step = 0.25 if sixteenths else 0.5
    for k in range(int(4 / step)):
        nm = pattern[k % len(pattern)]
        p.put(layer, bar * 4 + k * step, ost(nm, 0.2 if sixteenths else 0.32))


def bassline(p, bar, ch, layer="core", eighths=True, octave=2):
    r = chord_tones(ch)[0]
    root, up = f"{r}{octave}", f"{r}{octave + 1}"
    if eighths:
        for k in range(8):
            p.put(layer, bar * 4 + k * 0.5, bass(up if k in (3, 7) else root, 0.46))
    else:
        p.put(layer, bar * 4, bass(root, 3.8))


# ---------------------------------------------------------------- the pieces


ENGAGE_A = ["Dm", "Dm", "Bb", "Bb", "C", "C", "A", "A", "Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"]
# B lifts into the relative major before the dominant pulls it home.
ENGAGE_B = ["Bb", "Bb", "F", "F", "C", "C", "Dm", "Dm", "Bb", "Bb", "F", "F", "Gm", "Gm", "A", "A"]

# The fight theme is the hearth motif (A-D-E-F) made rhythmic and pushed into minor.
THEME_A = ("D5:.75 D5:.25 A4:.5 D5:.5 E5:.5 F5:1.5 "
           "E5:.5 D5:.5 C5:.5 D5:2.5 "
           "D5:.75 D5:.25 A4:.5 D5:.5 F5:.5 G5:1.5 "
           "F5:.5 E5:.5 D5:.5 F5:2.5 ")
THEME_B = ("E5:1 G5:1 C6:1.5 G5:.5 "
           "A5:.5 G5:.5 E5:.5 C5:2.5 "
           "C#5:1 E5:1 A5:1.5 G5:.5 "
           "F5:.5 E5:.5 C#5:.5 A4:2.5 ")
THEME_A2 = ("D5:.75 D5:.25 A4:.5 D5:.5 E5:.5 F5:1.5 "
            "E5:.5 D5:.5 C5:.5 D5:2.5 "
            "D5:.75 D5:.25 A4:.5 D5:.5 F5:.5 G5:1.5 "
            "A5:.5 G5:.5 F5:.5 A5:2.5 ")
THEME_C = ("G5:.75 G5:.25 D5:.5 G5:.5 A5:.5 Bb5:1.5 "
           "A5:.5 G5:.5 F5:.5 G5:2.5 "
           "E5:1 A5:1 G5:.5 F5:.5 E5:1 "
           "E5:.5 D5:.5 C#5:.5 A4:2.5 ")
# The B section soars: the same 4th-then-step shape, in long notes, an octave up,
# climbing to E6, then a harmonic-minor run that drops straight back into the theme.
SOAR_1 = ("F5:1.5 Bb5:.5 C6:2 D6:3 C6:.5 Bb5:.5 "
          "C6:1.5 A5:.5 F5:2 A5:2 G5:1 F5:1 "
          "E5:1.5 G5:.5 C6:2 D6:2 E6:1 C6:1 "
          "D6:4 A5:1 F5:1 D5:1 E5:1 ")
SOAR_2 = ("F5:1.5 Bb5:.5 C6:2 D6:2 C6:1 D6:1 "
          "A5:1.5 C6:.5 F6:2 E6:1 D6:.5 C6:.5 A5:2 "
          "G5:1.5 Bb5:.5 D6:2 C6:1 Bb5:1 A5:1 G5:1 "
          "A5:1.5 C#6:.5 E6:2 D6:.5 C#6:.5 Bb5:.5 A5:.5 G5:.5 F5:.5 E5:1 ")


def make_engage():
    p = Piece("engage", 32, True, ["core", "ostinato", "lead", "pressure"])
    for bar, ch in enumerate(ENGAGE_A + ENGAGE_B):
        b, lift = bar * 4, bar >= 16
        drums_engage(p, bar, fill=(bar % 4 == 3), lift=lift)
        bassline(p, bar, ch)
        ostinato(p, bar, ch, climb=lift)
        r, third, fifth = chord_tones(ch)
        if bar % 16 == 0:  # the drop: every phrase of the loop lands on a crash
            p.put("core", b, crash(0.2))
        if bar % 16 == 8:
            p.put("pressure", b, crash(0.18))
        p.put("pressure", b, tom(f"{r}2", 0.5))
        p.put("pressure", b + 2, tom(f"{r}2", 0.35))
        if not lift:  # A: brass stabs on the off-beats
            for k in [0, 1.5, 3.5]:
                p.put("pressure", b + k, brass([f"{r}4", f"{third}4", f"{fifth}4"], 0.5, 0.22))
        else:  # B: the horns hold the chord and swell, with taiko on every beat
            p.put("pressure", b, brass([f"{r}3", f"{fifth}3", f"{third}4"], 3.8, 0.13, stab=False))
            for k in [1, 3]:
                p.put("pressure", b + k, tom(f"{r}2", 0.3))
    for start, text in [(0, THEME_A), (16, THEME_B), (32, THEME_A2), (48, THEME_C)]:
        p.line("lead", start, text, lead, beats=16, amp=0.2)
    for start, text in [(64, SOAR_1), (96, SOAR_2)]:
        p.line("lead", start, text, lead, beats=32, amp=0.19)
    return p


def make_danger():
    """Our hull is low: half-time, a heartbeat for a kick, the Eb of D phrygian."""
    p = Piece("danger", 16, True, ["core", "ostinato", "lead"])
    chords = ["Dm", "Eb", "Dm", "Eb", "Bb", "A", "Dm", "A"] * 2
    for bar, ch in enumerate(chords):
        b = bar * 4
        root = chord_tones(ch)[0]
        beats = [0, 2] if bar >= 14 else [0]  # the heart races at the end of the loop
        for k in beats:
            p.put("core", b + k, heartbeat())
            p.kicks.append(b + k)
        p.put("core", b + 2, snare(0.55))  # half-time backbeat
        p.put("core", b, drone(f"{root}2", 4, 0.22))
        p.put("core", b, bass(f"{root}1", 3.5, 0.22))
        for k in range(16):  # a clock ticking in sixteenths: time is running out
            p.put("core", b + k * 0.25, hat(0.06 if k % 4 == 0 else 0.03))
        if bar % 8 == 7:  # and a snare roll throws each phrase into the next
            for k in range(8):
                p.put("core", b + 2 + k * 0.25, snare(0.12 + 0.04 * k))
        ostinato(p, bar, ch, sixteenths=False, octave=4)
        p.put("ostinato", b + 3.5, ost("D6", 0.12, 0.08))  # a thin alarm ping, high and cold
        if bar >= 8:  # second time round the Hush sings: a cold glass choir
            r, third, fifth = chord_tones(ch)
            p.put("ostinato", b, choir([f"{r}5", f"{third}5", f"{fifth}5"], 4, 0.05))
    p.put("core", 0, boom(0.6))  # entering danger hits like a hull breach
    # the hearth motif, broken: it can't finish its phrase
    p.line("lead", 0, "A4:1 D5:.5 E5:1.5 r:1 r:4 r:2 A4:1 D5:1 Eb5:3 r:1", lead, beats=16, amp=0.17)
    p.line("lead", 16, "A4:1 D5:.5 E5:.5 F5:2 r:4 E5:1 D5:1 C#5:2 A4:4", lead, beats=16, amp=0.18)
    # then it tries to climb out, and falls back to the leading tone
    p.line("lead", 32, "D5:1 F5:1 A5:2 Bb5:2 G5:1 Eb5:1 D5:1 F5:1 A5:2 Bb5:3 G5:1",
           lead, beats=16, amp=0.18)
    p.line("lead", 48, "F5:2 D5:2 E5:2 C#5:2 D5:1 F5:1 A5:1 D6:1 C#6:4", lead, beats=16, amp=0.18)
    return p


def make_kill():
    """Their hull is low: up a whole step to E minor, four on the floor, the theme as a war cry."""
    p = Piece("kill", 8, True, ["core", "ostinato", "lead", "pressure"])
    chords = ["Em", "C", "G", "D", "Em", "C", "D", "B"]
    for bar, ch in enumerate(chords):
        b = bar * 4
        for k in range(4):
            p.put("core", b + k, kick())
            p.kicks.append(b + k)
            p.put("core", b + k + 0.5, hat(0.12, open_=True))
        p.put("core", b + 1, snare(0.55))
        p.put("core", b + 3, snare(0.55))
        for k in range(16):
            p.put("core", b + k * 0.25, hat(0.05))
        bassline(p, bar, ch)
        ostinato(p, bar, ch, octave=4)
        r, third, fifth = chord_tones(ch)
        p.put("pressure", b, choir([f"{r}4", f"{third}4", f"{fifth}4"], 4))
        for k in [0, 0.75, 1.5, 2.5, 3, 3.5]:
            p.put("pressure", b + k, tom(f"{r}2", 0.4 if k % 1 else 0.55))
        if bar % 4 == 0:
            p.put("pressure", b, crash(0.2))
    theme = ("B4:1 E5:.5 F#5:.5 G5:1.5 F#5:.5 "
             "E5:1 G5:1 C6:2 "
             "B5:1 D6:.5 B5:.5 G5:1.5 A5:.5 "
             "F#5:1 D5:1 A5:2 "
             "B4:1 E5:.5 F#5:.5 G5:1.5 B5:.5 "
             "C6:1 B5:1 G5:2 "
             "A5:1 F#5:.5 D5:.5 A5:2 "
             "B5:1 A5:.5 F#5:.5 D#5:2 ")
    p.line("lead", 0, theme, lead, amp=0.22)
    p.line("lead", 0, theme, lambda n, d, amp: brass([shift(n, -1)], d, amp, stab=False), amp=0.06)
    return p


def make_arrival():
    """An enemy on the scope: horn call, taiko, then a build that never lets up, a held breath, the drop."""
    p = Piece("arrival", 4, False, ["core"])
    p.put("core", 0, boom(0.7))
    p.put("core", 0, crash(0.18))
    p.put("core", 0, brass(["D3", "A3", "D4"], 3.5, 0.26, stab=False))  # the horn call
    p.put("core", 4, brass(["F3", "C4", "F4"], 2, 0.24, stab=False))
    p.put("core", 6, brass(["E3", "A3", "C#4"], 2, 0.26, stab=False))
    for k in [0, 2, 3, 4, 5, 6, 6.5, 7, 7.5]:
        p.put("core", k, tom("D2", 0.35 + 0.03 * k))
    for k in range(8):  # the taiko speed up: eighths, then sixteenths
        p.put("core", 8 + k * 0.5, tom("D2" if k % 2 == 0 else "A2", 0.35 + 0.02 * k))
    for k in range(12):
        p.put("core", 12 + k * 0.25, tom(["D3", "C3", "A2", "F2"][k % 4], 0.3 + 0.02 * k))
    for k in range(28):  # a snare roll that swells all the way to the edge
        p.put("core", 8 + k * 0.25, snare(0.08 + 0.018 * k))
    for k in [12, 13, 14, 14.5]:  # the dominant, hammered: it has to resolve
        p.put("core", k, brass(["A3", "C#4", "E4"], 0.5, 0.18 + 0.02 * (k - 12)))
    p.put("core", 8, riser(7, 0.45))
    p.put("core", 8, drone("D2", 7, 0.18))
    # beat 4 of bar 4 is left empty: the held breath before engage's first kick
    return p


def make_surge():
    """One bar between engage and kill, the gear change: everything climbs to B, the door to E minor."""
    p = Piece("surge", 1, False, ["core"])
    for k in range(4):
        p.put("core", k, kick())
        p.kicks.append(k)
        p.put("core", k, brass(["B3", "D#4", "F#4"], 0.5, 0.17 + 0.03 * k))
    for k in range(16):
        p.put("core", k * 0.25, snare(0.15 + 0.025 * k))
    for k, nm in enumerate(["B2", "B2", "F#2", "F#2", "D#3", "D#3", "F#3", "B3"]):
        p.put("core", k * 0.5, tom(nm, 0.45))
        p.put("core", k * 0.5, bass("B2" if k % 2 == 0 else "B1", 0.46))
    p.put("core", 0, riser(4, 0.4))
    return p


def make_victory():
    """The theme as a fanfare, bVI-bVII-I: the kill section's E minor turns to E major."""
    p = Piece("victory", 5, False, ["core"], ring=True)  # 4 bars of fanfare, 1 to ring out
    p.put("core", 0, crash(0.25))
    for k, nm in enumerate(["E3", "E3", "B2", "B2", "G2", "G2", "E2", "E2"]):
        p.put("core", 2 + k * 0.25, tom(nm, 0.5))
    p.put("core", 0, brass(["C4", "E4", "G4"], 2, 0.2, stab=False))
    p.put("core", 2, brass(["D4", "F#4", "A4"], 2, 0.2, stab=False))
    p.put("core", 4, brass(["E4", "G#4", "B4"], 15, 0.22, stab=False))
    p.put("core", 4, choir(["E4", "G#4", "B4", "E5"], 15, 0.14))
    p.put("core", 4, kick())
    p.put("core", 4, boom(0.5))
    p.put("core", 4, crash(0.3))
    p.put("core", 0, bass("C2", 2, 0.25))
    p.put("core", 2, bass("D2", 2, 0.25))
    p.put("core", 4, bass("E2", 15, 0.25))
    p.line("core", 0, "B4:.5 E5:.5 G5:.5 C6:.5 B5:1 G5:1 "
                      "A5:.5 F#5:.5 D5:.5 F#5:.5 A5:1 D6:1 "
                      "B5:2 G#5:1 B5:1 E6:4", lead, beats=16, amp=0.3)
    return p


def make_defeat():
    """We lost: the motif once more, slow, never coming home, and the Hush closes over it."""
    p = Piece("defeat", 6, False, ["core"], ring=True)
    p.put("core", 0, boom(0.7))
    p.put("core", 0, crash(0.15))
    for bar, ch in enumerate(["Dm", "Dm", "Bb", "Gm", "A", "A"]):
        r, third, fifth = chord_tones(ch)
        p.put("core", bar * 4, choir([f"{r}3", f"{fifth}3", f"{third}4"], 4.2, 0.12))
        p.put("core", bar * 4, drone(f"{r}2", 4.2, 0.16))
    p.line("core", 0, "A4:2 D5:2 E5:3 F5:1 D5:4 C5:2 Bb4:2 A4:8", lead, beats=24, amp=0.2)
    for k in range(6):  # the last embers: a few soft crackles, thinning out
        p.put("core", 14 + k * 1.3, hat(0.05 - 0.007 * k, open_=True))
    # the Hush eats the music: a low-pass that closes over the last three bars
    x = p.tracks["core"]
    a, z = secs(8), secs(22)
    cut = np.full(len(x), 9000.0)
    cut[a:z] = 9000.0 * (250.0 / 9000.0) ** np.linspace(0, 1, z - a)
    cut[z:] = 250.0
    p.tracks["core"] = sweep_lowpass(x, cut)
    return p


# ---------------------------------------------------------------- render

ir_n = int(2.4 * SR)
IR = onepole(rng.uniform(-1, 1, ir_n) * np.exp(-np.arange(ir_n) / SR * 2.6), 5500)
IR /= np.sqrt(np.sum(IR**2))
SENDS = {"core": 0.12, "ostinato": 0.2, "lead": 0.3, "pressure": 0.22}
PANS = {"core": 0.0, "ostinato": 0.2, "lead": -0.12, "pressure": 0.05}
DUCKED = {"ostinato": 0.45, "pressure": 0.25}  # how deep the kick pumps each layer


HP = butter(2, 35, "highpass", fs=SR, output="sos")


def master(x):
    """Below ~35 Hz nothing is heard, even on headphones: it only eats headroom. Then a soft top."""
    return onepole(onepole(sosfilt(HP, x), 12000), 15000)


def sidechain(p, length):
    """A gain curve that dips under every kick and swells back: the pump."""
    g = np.ones(length)
    rel = int(0.18 * SR)
    curve = 1 - np.exp(-np.arange(rel) / (0.06 * SR))
    for k in p.kicks:
        i = secs(k)
        j = min(length, i + rel)
        if i < length:
            g[i:j] = np.minimum(g[i:j], curve[: j - i])
    return g


def render(p):
    """Each layer as stereo, with its reverb, folded so a looping piece loops seamlessly."""
    out = {}
    pump = sidechain(p, len(next(iter(p.tracks.values()))))
    for layer, x in p.tracks.items():
        if layer in DUCKED:
            x = x * (1 - DUCKED[layer] * (1 - pump))
        wet = fftconvolve(x * SENDS[layer], IR)[: len(x)] * 0.4
        pan = PANS[layer]
        left = x * np.sqrt((1 - pan) / 2) * 1.414 + wet
        right = x * np.sqrt((1 + pan) / 2) * 1.414 + np.roll(wet, int(0.013 * SR))
        lr = np.stack([master(left), master(right)], 1)
        body = lr[: p.n].copy()
        tail = lr[p.n :]
        if p.loop:
            body[: min(len(tail), p.n)] += tail[: p.n]
        else:  # one-shots fade out (over half a bar if they ring, else 5 ms) instead of clicking off
            k = BAR_SAMPLES // 2 if p.ring else int(0.005 * SR)
            body[-k:] *= np.linspace(1, 0, k)[:, None]
        out[layer] = (body, tail)
    return out


def write_ogg(path, lr):
    wav = path[:-4] + ".wav"
    write_wav(wav, lr)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis",
                    "-q:a", "4", path], check=True)
    os.remove(wav)


def write_wav(path, lr):
    pcm = (np.clip(lr, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


pieces = [make_arrival(), make_engage(), make_danger(), make_surge(), make_kill(), make_victory(),
          make_defeat()]
rendered = {p.name: render(p) for p in pieces}
# One gain for everything, so pieces keep their relative weight and the loudest
# full mix sits just under clipping.
loudest = max(np.max(np.abs(sum(b for b, _ in r.values()))) for r in rendered.values())
GAIN = 0.9 / loudest
for p in pieces:
    for layer, (body, _) in rendered[p.name].items():
        write_ogg(f"{OUT}/ember_{p.name}_{layer}.ogg", body * GAIN)
        write_import(f"{OUT}/ember_{p.name}_{layer}.ogg", p.loop, BPM, p.bars * 4)
    print("%-8s %2d bars %6.2f s  %s  layers: %s" % (
        p.name, p.bars, p.n / SR, "loop" if p.loop else "once", ", ".join(p.tracks)))

if DEMO:
    # Two fights back to back. One we win: the enemy arrives, the theme comes in
    # with the first hits, pressure builds, the kill window, victory. One we
    # lose: our hull is low, then defeat. Layers come and go as the game would.
    plan = [("arrival", 1, ["core"]),
            ("engage", 0.25, ["core", "ostinato"]),
            ("engage", 0.25, ["core", "ostinato", "lead"]),
            ("engage", 0.5, ["core", "ostinato", "lead", "pressure"]),
            ("surge", 1, ["core"]),
            ("kill", 1, ["core", "ostinato", "lead", "pressure"]),
            ("victory", 1, ["core"]),
            ("gap", 1.5, []),
            ("danger", 1, ["core", "ostinato", "lead"]),
            ("defeat", 1, ["core"])]
    parts = []
    offsets = {}
    for name, frac, layers in plan:
        if name == "gap":
            parts.append(np.zeros((int(frac * SR), 2)))
            continue
        r = rendered[name]
        p = next(q for q in pieces if q.name == name)
        start = offsets.get(name, 0)
        n = int(p.n * frac)
        seg = sum(r[l][0][start : start + n] for l in layers)
        offsets[name] = (start + n) % p.n
        parts.append(seg)
    demo = np.concatenate(parts) * GAIN
    fade = np.ones(len(demo))
    fade[-int(1.0 * SR):] = np.linspace(1, 0, int(1.0 * SR))
    write_wav(DEMO, demo * fade[:, None])
    print("demo %.1f s -> %s" % (len(demo) / SR, DEMO))
