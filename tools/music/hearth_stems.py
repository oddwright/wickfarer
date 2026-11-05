"""Wickfarer music: "Hearth in the Cold" combat and chart loop, rendered as synced stems.

Renders a ~60 s demo of the adaptive score idea in an "orchestral but pixely"
style: a small fixed set of chip-style voices (like a pixel palette), each one
standing in for an acoustic instrument.
  bowed lead  - 25% pulse, slow bow attack, late vibrato, 22 kHz sample-hold crunch
  harmonium   - two detuned soft squares, slow swell
  kalimba     - triangle pluck with a quick decay
  bass        - triangle (warm, round)
  felt drum   - pitched sine thump + noise click; brush = filtered noise
  glass       - pure sines, long reverb (the cold of space)
Writes one 16-bar loop as stems of exactly equal length; the game plays them
together in an AudioStreamSynchronized and fades layers per music state
(data/feedback.json "music"). The Hush filter is applied live by the game.
Key D dorian, 92 bpm. Usage: python3 tools/music/hearth_stems.py audio/music
Needs numpy, scipy and ffmpeg (for Ogg Vorbis). Never hand-edit the .ogg files:
change this score and re-render.
"""

import sys
import numpy as np
from scipy.signal import fftconvolve, lfilter

SR = 44100
BPM = 92
BEAT = 60.0 / BPM
BAR = 4
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
rng = np.random.default_rng(1977)

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name):
    n, octv = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((NOTE[n] + 12 * (octv + 1) - 69) / 12)


LOOP_BARS = 16
LOOP = int(round(LOOP_BARS * BAR * BEAT * SR))
N = LOOP + int(6.0 * SR)  # room for tails, folded back onto the start


def track():
    return np.zeros(N)


def env(n, attack, release, decay=0.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((n / SR - t) / max(release, 1e-4), 0, 1)
    d = np.exp(-decay * t) if decay > 0 else 1.0
    return a * r * d


def place(buf, start_beat, sig):
    i = int(start_beat * BEAT * SR)
    j = min(N, i + len(sig))
    buf[i:j] += sig[: j - i]


def phase(f, n, vib=0.0, vib_delay=0.3):
    t = np.arange(n) / SR
    depth = vib * np.clip((t - vib_delay) / 0.4, 0, 1)
    inst = f * (1 + depth * np.sin(2 * np.pi * 5.2 * t))
    return np.cumsum(inst) / SR


def pulse(ph, duty):
    return np.where(np.mod(ph, 1.0) < duty, 1.0, -1.0)


def tri(ph):
    return 4 * np.abs(np.mod(ph, 1.0) - 0.5) - 1


def crunch(x, hold=2, levels=48):
    """Sample-and-hold + amplitude steps: the 'pixel' grain."""
    y = np.repeat(x[::hold], hold)[: len(x)]
    y = np.round(y * levels) / levels
    return onepole(y, 7000)  # keep the grain, lose the fizz


def onepole(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    return lfilter([1 - a], [1, -a], x)


# ---------------------------------------------------------------- voices


def bowed(name, beats, amp=0.22):
    n = int(beats * BEAT * SR)
    f = hz(name)
    ph = phase(f, n, vib=0.006, vib_delay=0.25)
    s = 0.7 * pulse(ph, 0.25) + 0.3 * pulse(ph * 2, 0.5) * 0.4
    s = onepole(s, 3200)
    return crunch(s) * env(n, 0.07, 0.12) * amp


def harmonium(name, beats, amp=0.06):
    n = int(beats * BEAT * SR)
    f = hz(name)
    s = pulse(phase(f * 0.997, n), 0.5) + pulse(phase(f * 1.003, n), 0.5)
    s = onepole(onepole(s, 1400), 2200)
    return s * env(n, 0.35, 0.4) * amp


def kalimba(name, beats, amp=0.12):
    n = int(min(beats, 2) * BEAT * SR) + int(0.3 * SR)
    f = hz(name)
    s = tri(phase(f, n)) + 0.35 * np.sin(2 * np.pi * np.cumsum(np.full(n, f * 4.02)) / SR)
    return crunch(s, hold=2, levels=32) * env(n, 0.002, 0.05, decay=7) * amp


def bass(name, beats, amp=0.26):
    n = int(beats * BEAT * SR)
    s = tri(phase(hz(name), n))
    return crunch(s, hold=1, levels=16) * env(n, 0.005, 0.05) * amp


def drum(amp=0.5):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 55 + 70 * np.exp(-t * 30)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    click = rng.uniform(-1, 1, n) * np.exp(-t * 120) * 0.3
    return onepole(body + click, 900) * amp


def brush(amp=0.07):
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    x = rng.uniform(-1, 1, n)
    x = x - onepole(x, 2500)  # high-passed noise
    return x * np.exp(-t * 25) * amp


def heart(amp=0.45):
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    beat1 = np.sin(2 * np.pi * 48 * t) * np.exp(-t * 14)
    beat2 = np.roll(np.sin(2 * np.pi * 44 * t) * np.exp(-t * 16), int(0.22 * SR)) * 0.6
    beat2[: int(0.22 * SR)] = 0
    return (beat1 + beat2) * amp


def glass(name, beats, amp=0.05):
    n = int(beats * BEAT * SR)
    f = hz(name)
    s = np.sin(2 * np.pi * np.cumsum(np.full(n, f)) / SR) + 0.3 * np.sin(
        2 * np.pi * np.cumsum(np.full(n, f * 2.76)) / SR
    )
    return s * env(n, 0.6, 1.2) * amp


# ---------------------------------------------------------------- score

CHORDS = {
    "Dm": ["D3", "F3", "A3", "D4"],
    "G": ["G2", "B3", "D4", "G3"],
    "F": ["F2", "A3", "C4", "F3"],
    "C": ["C3", "E3", "G3", "C4"],
    "A": ["A2", "C#4", "E4", "A3"],
    "Bb": ["A#2", "D4", "F4", "A#3"],
}
ARP = {
    "Dm": ["D5", "A4", "F5", "A4"], "G": ["D5", "B4", "G5", "B4"],
    "F": ["C5", "A4", "F5", "A4"], "C": ["C5", "G4", "E5", "G4"],
    "A": ["C#5", "A4", "E5", "A4"], "Bb": ["D5", "A#4", "F5", "A#4"],
}
PROG = ["Dm", "G", "F", "C"] * 2 + ["Dm", "G", "F", "C", "Dm", "G", "Bb", "A"]

# The hearth motif: rises a fifth, leans on the dorian sixth (B), comes home.
MOTIF = [("A4", 1), ("D5", 0.5), ("E5", 0.5), ("F5", 1.5), ("E5", 0.5),
         ("D5", 1), ("C5", 1), ("A4", 2)]
ANSWER = [("A4", 0.5), ("C5", 0.5), ("D5", 0.5), ("F5", 1.5), ("G5", 1),
          ("E5", 1), ("D5", 1), ("C5", 2)]
TURN = [("A4", 1), ("D5", 0.5), ("E5", 0.5), ("F5", 1.5), ("E5", 0.5),
        ("D5", 1), ("E5", 1), ("B4", 2)]
HOME = [("A4", 0.5), ("C5", 0.5), ("F5", 2), ("E5", 1), ("D5", 1), ("C5", 1), ("D5", 2)]
LIFT = [("A4", 0.5), ("C5", 0.5), ("D5", 0.5), ("F5", 1.5), ("G5", 1),
        ("F5", 1), ("E5", 1), ("C#5", 2)]

stems = {k: np.zeros(N) for k in ["pad", "warm", "pluck", "pulse", "drum", "heart"]}


def melody(buf, start_bar, line, amp):
    b = start_bar * BAR
    for name, d in line:
        place(buf, b, bowed(name, d, amp))
        b += d


for bar, ch in enumerate(PROG):
    b0 = bar * BAR
    root = CHORDS[ch][0]
    for note in CHORDS[ch]:
        place(stems["pad"], b0, harmonium(note, 4, 0.03))
    place(stems["pad"], b0, bass(root, 4, 0.12))  # a soft held root under the calm layers
    for k in range(8):
        place(stems["pluck"], b0 + k * 0.5, kalimba(ARP[ch][k % 4], 0.5, 0.15))
    if bar % 2 == 0:
        place(stems["warm"], b0 + 1, glass(ARP[ch][2][:-1] + "6", 6, 0.04))
    for k in range(8):
        up = root[:-1] + str(int(root[-1]) + 1)
        place(stems["pulse"], b0 + k * 0.5, bass(up if k % 4 == 3 else root, 0.45, 0.2))
        place(stems["pulse"], b0 + k * 0.5 + 0.25, kalimba(ARP[ch][(k + 2) % 4], 0.25, 0.05))
    for k in [0, 1.5, 2.5]:
        place(stems["drum"], b0 + k, drum())
    for k in [1, 3]:
        place(stems["drum"], b0 + k, brush(0.12))
    for k in range(8):
        place(stems["drum"], b0 + k * 0.5 + 0.25, brush(0.03))
    place(stems["heart"], b0, heart())
    place(stems["heart"], b0 + 2, heart(0.3))

for start, line in [(0, MOTIF), (2, ANSWER), (4, TURN), (6, HOME),
                    (8, MOTIF), (10, ANSWER), (12, MOTIF), (14, LIFT)]:
    melody(stems["warm"], start, line, 0.2)

# ---------------------------------------------------------------- render

ir_n = int(2.8 * SR)
ir = rng.uniform(-1, 1, ir_n) * np.exp(-np.arange(ir_n) / SR * 2.2)
ir = onepole(ir, 5000)
ir /= np.sqrt(np.sum(ir**2))
SENDS = {"pad": 0.3, "warm": 0.35, "pluck": 0.3, "pulse": 0.08, "drum": 0.15, "heart": 0.1}
PANS = {"pad": 0.0, "warm": -0.1, "pluck": 0.25, "pulse": 0.0, "drum": 0.0, "heart": 0.0}


def fold(x):
    """Wrap everything that rings past the loop end back onto the start: seamless loop."""
    y = x[:LOOP].copy()
    tail = x[LOOP:]
    y[: len(tail)] += tail[:LOOP]
    return y


def write_ogg(path, lr):
    import subprocess, wave

    wav = path[:-4] + ".wav"
    pcm = (np.clip(lr, -1, 1) * 32767).astype("<i2")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis",
                    "-q:a", "5", path], check=True)
    import os

    os.remove(wav)


peak = 0.0
out = {}
for k, x in stems.items():
    wet = fftconvolve(x * SENDS[k], ir)[:N] * 0.35
    p = PANS[k]
    left = x * np.sqrt((1 - p) / 2) * 1.414 + wet
    right = x * np.sqrt((1 + p) / 2) * 1.414 + np.roll(wet, int(0.011 * SR))
    left = onepole(onepole(left, 11000), 14000)
    right = onepole(onepole(right, 11000), 14000)
    out[k] = np.stack([fold(left), fold(right)], axis=1)
# One gain for all stems, so their balance stays and the full mix never clips.
full = sum(out.values())
gain = 0.85 / np.max(np.abs(full))
for k, lr in out.items():
    write_ogg(f"{OUT}/hearth_{k}.ogg", lr * gain)
print("loop %.3f s (%d samples), stems: %s" % (LOOP / SR, LOOP, ", ".join(out)))
