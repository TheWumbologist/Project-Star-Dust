#!/usr/bin/env python3
"""Synthesises the placeholder sound effects and music loops.

Everything here is generated from oscillators, noise and plucked strings,
with a fixed random seed, so re-running gives the same files. They are
placeholders: drop real sounds over the same file names (or point
scripts/audio/audio.gd at new ones) whenever you like.

Output: assets/_ai_generated/audio/*__AI.wav (mono, 16-bit, 22050 Hz).
Every file is listed in assets/ASSET_LEDGER.csv.

    python3 tools/make_sounds.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "_ai_generated", "audio")
TAU = math.tau


# --- Building blocks ---------------------------------------------------------

def seconds(n):
    return int(n * RATE)


def silence(dur):
    return [0.0] * seconds(dur)


def osc(kind, freq, dur, phase=0.0):
    """freq may be a number or a function of t (seconds)."""
    out = []
    ph = phase
    for i in range(seconds(dur)):
        t = i / RATE
        f = freq(t) if callable(freq) else freq
        ph += f / RATE
        x = ph % 1.0
        if kind == "sine":
            v = math.sin(TAU * x)
        elif kind == "square":
            v = 1.0 if x < 0.5 else -1.0
        elif kind == "saw":
            v = 2.0 * x - 1.0
        elif kind == "tri":
            v = 4.0 * abs(x - 0.5) - 1.0
        else:
            raise ValueError(kind)
        out.append(v)
    return out


def noise(dur, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(seconds(dur))]


def env(sig, attack, decay_rate=None, release=None):
    """Linear attack, then exponential decay (per second) and/or a linear
    release over the last `release` seconds."""
    n = len(sig)
    a = max(seconds(attack), 1)
    r = seconds(release) if release else 0
    out = []
    for i, v in enumerate(sig):
        g = min(i / a, 1.0)
        if decay_rate:
            g *= math.exp(-decay_rate * max(i - a, 0) / RATE)
        if r and i > n - r:
            g *= (n - i) / r
        out.append(v * g)
    return out


def lowpass(sig, cutoff):
    """One-pole lowpass; cutoff may be a function of t."""
    out = []
    y = 0.0
    for i, v in enumerate(sig):
        c = cutoff(i / RATE) if callable(cutoff) else cutoff
        k = 1.0 - math.exp(-TAU * c / RATE)
        y += k * (v - y)
        out.append(y)
    return out


def highpass(sig, cutoff):
    low = lowpass(sig, cutoff)
    return [a - b for a, b in zip(sig, low)]


def mix(*sigs, gains=None):
    n = max(len(s) for s in sigs)
    gains = gains or [1.0] * len(sigs)
    out = [0.0] * n
    for s, g in zip(sigs, gains):
        for i, v in enumerate(s):
            out[i] += v * g
    return out


def place(dest, sig, at, gain=1.0):
    start = seconds(at)
    for i, v in enumerate(sig):
        j = start + i
        if j >= len(dest):
            break
        dest[j] += v * gain


def gain(sig, g):
    return [v * g for v in sig]


def normalize(sig, peak=0.9):
    m = max((abs(v) for v in sig), default=0.0)
    return sig if m == 0 else [v * peak / m for v in sig]


def soft_clip(sig, drive=1.5):
    return [math.tanh(v * drive) / math.tanh(drive) for v in sig]


def pluck(freq, dur, rng, damping=0.996, bright=0.5):
    """Karplus-Strong plucked string (a lute-ish voice for the hub)."""
    period = max(int(RATE / freq), 2)
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    # Darken the initial burst a little.
    for i in range(1, period):
        buf[i] = buf[i] * bright + buf[i - 1] * (1 - bright)
    out = []
    for i in range(seconds(dur)):
        j = i % period
        nxt = buf[(i + 1) % period]
        v = buf[j]
        buf[j] = damping * 0.5 * (v + nxt)
        out.append(v)
    return out


def note(name):
    """'A2', 'C#4', 'Eb3' -> Hz."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    letter, rest = name[0], name[1:]
    semis = names[letter]
    if rest[0] == "#":
        semis += 1
        rest = rest[1:]
    elif rest[0] == "b":
        semis -= 1
        rest = rest[1:]
    octave = int(rest)
    return 440.0 * 2 ** ((semis + (octave - 4) * 12) / 12)


def write(name, sig, peak=0.9):
    sig = normalize(sig, peak)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + "__AI.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in sig)
        w.writeframes(frames)
    print("wrote", os.path.relpath(path))


# --- Sound effects -------------------------------------------------------------

def sfx(rng):
    # Cannon: a punchy thump with a falling square body.
    body = env(osc("square", lambda t: 520 * math.exp(-t * 18) + 90, 0.22), 0.002, 22)
    crack = env(lowpass(noise(0.22, rng), 3000), 0.001, 40)
    write("sfx_cannon", lowpass(mix(body, crack, gains=[0.6, 0.8]), 2600))

    # Enemy bolt: a thin descending zap.
    zap = env(osc("saw", lambda t: 1400 * math.exp(-t * 9) + 300, 0.14), 0.002, 25)
    write("sfx_enemy_shot", lowpass(zap, 3500), 0.7)

    # Torpedo launch: low thump plus a rising hiss.
    thump = env(osc("sine", lambda t: 140 * math.exp(-t * 8) + 40, 0.6), 0.003, 9)
    hiss = env(lowpass(noise(0.6, rng), lambda t: 400 + t * 5000), 0.05, 5, release=0.2)
    write("sfx_torpedo", mix(thump, hiss, gains=[0.9, 0.5]))

    # Explosions: filtered noise and a sub drop, small and big.
    for name, dur, rate, sub in (("sfx_explosion_small", 0.7, 7, 70), ("sfx_explosion_big", 1.6, 3.2, 50)):
        rumble = env(lowpass(noise(dur, rng), lambda t, d=dur: 2200 * math.exp(-t * 4 / d) + 120), 0.004, rate)
        boom = env(osc("sine", lambda t, s=sub: s * 2 * math.exp(-t * 5) + s, dur), 0.003, rate * 0.8)
        write(name, soft_clip(mix(rumble, boom, gains=[1.0, 0.9]), 1.8))

    # Hull hit: an inharmonic metal clank.
    clank = mix(*[env(osc("sine", f, 0.3), 0.001, d) for f, d in ((310, 18), (523, 24), (847, 30), (1290, 40))])
    click = env(highpass(noise(0.3, rng), 2000), 0.0005, 90)
    write("sfx_hit_hull", mix(clank, click, gains=[0.7, 0.5]), 0.75)

    # Shield hit: a bright shimmer.
    shimmer = env(osc("sine", lambda t: 980 + 60 * math.sin(TAU * 38 * t), 0.22), 0.002, 18)
    write("sfx_hit_shield", mix(shimmer, env(osc("sine", 1960, 0.22), 0.002, 30), gains=[0.8, 0.3]), 0.6)

    # Shield break: a falling glassy arpeggio over noise.
    brk = silence(0.7)
    for k, f in enumerate((1568, 1175, 880, 659)):
        place(brk, env(osc("tri", f, 0.3), 0.002, 14), k * 0.07, 0.6)
    place(brk, env(highpass(noise(0.5, rng), 1500), 0.002, 8), 0.0, 0.4)
    write("sfx_shield_break", brk, 0.8)

    # Rock chip: a short gritty crunch.
    chip = env(lowpass(highpass(noise(0.12, rng), 400), 3000), 0.001, 45)
    write("sfx_rock_chip", chip, 0.6)

    # Pickup: two quick rising blips.
    pk = silence(0.2)
    place(pk, env(osc("square", note("C6"), 0.08), 0.002, 30), 0.0, 0.5)
    place(pk, env(osc("square", note("G6"), 0.1), 0.002, 25), 0.06, 0.5)
    write("sfx_pickup", lowpass(pk, 5000), 0.55)

    # Boost: a rising whoosh.
    whoosh = env(lowpass(noise(0.7, rng), lambda t: 300 + 4000 * min(t / 0.35, 1.0)), 0.08, 4, release=0.3)
    write("sfx_boost", whoosh, 0.7)

    # Drift kick: an upward zap.
    kick = env(osc("square", lambda t: 180 + 900 * t / 0.25, 0.28), 0.002, 9, release=0.08)
    write("sfx_drift_kick", lowpass(kick, 2400), 0.6)

    # Warp in: a falling sine with a noise swell.
    fall = env(osc("sine", lambda t: 900 * math.exp(-t * 4) + 80, 0.8), 0.15, 3, release=0.2)
    swell = env(lowpass(noise(0.8, rng), 1500), 0.3, 2, release=0.3)
    write("sfx_warp_in", mix(fall, swell, gains=[0.8, 0.4]), 0.7)

    # Extracted: a rising major arpeggio chime.
    ex = silence(1.4)
    for k, n in enumerate(("C5", "E5", "G5", "C6")):
        place(ex, env(osc("sine", note(n), 0.9), 0.003, 4), k * 0.11, 0.5)
        place(ex, env(osc("sine", note(n) * 2, 0.6), 0.003, 7), k * 0.11, 0.15)
    write("sfx_extracted", ex, 0.8)

    # Augment cache: a sparkly arpeggio.
    ca = silence(0.9)
    for k, n in enumerate(("E6", "B5", "G#6", "E7", "B6")):
        place(ca, env(osc("tri", note(n), 0.4), 0.002, 9), k * 0.06, 0.4)
    write("sfx_cache", ca, 0.7)

    # Stage alarm: a two-tone klaxon.
    al = silence(0.9)
    for k in range(2):
        place(al, env(lowpass(osc("saw", 440, 0.2), 1800), 0.01, 2, release=0.05), k * 0.4, 0.6)
        place(al, env(lowpass(osc("saw", 330, 0.2), 1800), 0.01, 2, release=0.05), k * 0.4 + 0.2, 0.6)
    write("sfx_alarm", al, 0.6)

    # Compass salvaged: a slow magical chord swell.
    cp = silence(2.2)
    for n in ("A4", "C#5", "E5", "A5"):
        place(cp, env(osc("sine", lambda t, f=note(n): f * (1 + 0.003 * math.sin(TAU * 5 * t)), 2.0), 0.4, 1.5, release=0.6), 0.0, 0.3)
    for k, n in enumerate(("E6", "A6", "C#7")):
        place(cp, env(osc("tri", note(n), 0.5), 0.002, 6), 0.5 + k * 0.15, 0.2)
    write("sfx_compass", cp, 0.8)

    # UI: a tiny tick and a confirm blip.
    write("sfx_ui_click", env(osc("square", 1800, 0.04), 0.0005, 120), 0.35)
    conf = silence(0.14)
    place(conf, env(osc("tri", note("A5"), 0.06), 0.001, 40), 0.0, 0.5)
    place(conf, env(osc("tri", note("E6"), 0.08), 0.001, 35), 0.05, 0.5)
    write("sfx_ui_confirm", conf, 0.45)


# --- Music -----------------------------------------------------------------------

def pad(freq, dur, detune=0.004):
    """Two slightly detuned saws through a soft lowpass: a warm pad."""
    a = osc("saw", freq * (1 - detune), dur, 0.0)
    b = osc("saw", freq * (1 + detune), dur, 0.37)
    return lowpass(mix(a, b, gains=[0.5, 0.5]), 900)


def loop(sig, tail):
    """Folds the tail (last `tail` seconds) back over the start so the loop
    point is seamless, then trims it off."""
    n = seconds(tail)
    body = sig[:-n]
    for i in range(n):
        body[i] += sig[len(sig) - n + i] * (1 - i / n)
    return body


def music_rift(rng):
    # A minor, 80 bpm: brooding pads, a pulsing bass and a sparse bell motif.
    beat = 60 / 80
    bars = 16
    length = bars * 4 * beat
    tail = 3.0
    out = silence(length + tail)
    chords = [("A2", "E3", "C4"), ("F2", "C3", "A3"), ("D2", "A2", "F3"), ("E2", "B2", "G#3")]
    for bar in range(bars):
        notes = chords[(bar // 2) % len(chords)]
        if bar % 2 == 0:
            for n in notes:
                place(out, env(pad(note(n), 2 * 4 * beat + 1.5), 1.2, None, release=1.5), bar * 4 * beat, 0.16)
        # Bass pulse on every beat.
        for b in range(4):
            f = note(notes[0]) / 2
            place(out, env(lowpass(osc("square", f, beat * 0.9), 300), 0.005, 5), (bar * 4 + b) * beat, 0.22)
    bell_notes = ["E5", "C5", "A4", "B4", "E5", "G#4"]
    for bar in range(0, bars, 2):
        n = bell_notes[(bar // 2) % len(bell_notes)]
        at = (bar * 4 + 2.5) * beat
        place(out, env(mix(osc("sine", note(n), 2.5), osc("sine", note(n) * 2.76, 2.5), gains=[0.7, 0.2]), 0.002, 2.2), at, 0.25)
    # A faint airy noise bed.
    place(out, lowpass(noise(length + tail, rng), 500), 0.0, 0.03)
    write("music_rift", soft_clip(loop(out, tail), 1.2), 0.7)


def music_hub(rng):
    # D major-ish tavern lilt at 96 bpm in 6/8: plucked lute over warm pads.
    eighth = 60 / 96 / 2
    bars = 16
    bar_len = 6 * eighth
    length = bars * bar_len
    tail = 3.0
    out = silence(length + tail)
    chords = [("D3", "A3", "F#4"), ("G2", "D3", "B3"), ("A2", "E3", "C#4"), ("D3", "A3", "F#4"),
              ("B2", "F#3", "D4"), ("G2", "D3", "B3"), ("E3", "B3", "G4"), ("A2", "E3", "C#4")]
    melody = [
        ["F#5", None, "E5", "D5", None, "A4"], ["B4", None, "D5", "G5", None, "F#5"],
        ["E5", None, "C#5", "A4", None, "E5"], ["D5", None, None, "A4", "B4", "C#5"],
        ["D5", None, "F#5", "B5", None, "A5"], ["G5", None, "F#5", "E5", None, "D5"],
        ["E5", None, "G5", "B4", None, "E5"], ["C#5", None, "E5", "A4", None, None],
    ]
    for bar in range(bars):
        start = bar * bar_len
        notes = chords[bar % len(chords)]
        for n in notes:
            place(out, env(pad(note(n), bar_len + 1.0, 0.003), 0.4, None, release=0.9), start, 0.1)
        # Lute arpeggio on the chord.
        arp = [notes[0], notes[1], notes[2], notes[1], notes[2], notes[1]]
        for k, n in enumerate(arp):
            place(out, pluck(note(n) * 2, 1.2, rng, 0.994), start + k * eighth, 0.18)
        # Melody on the second pass only, so the loop breathes.
        if bar >= 8:
            for k, n in enumerate(melody[bar % len(melody)]):
                if n:
                    place(out, pluck(note(n), 1.5, rng, 0.996, 0.7), start + k * eighth, 0.3)
    write("music_hub", soft_clip(loop(out, tail), 1.2), 0.7)


# --- Enemy roster sounds (milestone 6c) --------------------------------------------
# Own random stream, so adding these leaves the older files byte-identical.

def sfx_roster(rng):
    # Fuse: three quickening beeps (spark mites, mines).
    fz = silence(0.5)
    for k, at in enumerate((0.0, 0.17, 0.3, 0.4)):
        place(fz, env(osc("square", 1300 + k * 120, 0.06), 0.002, 40), at, 0.5)
    write("sfx_fuse", lowpass(fz, 4000), 0.55)

    # Charge: a rising whine with a tremolo, the lancer's aim line.
    whine = env(osc("saw", lambda t: 220 + 900 * (t / 1.1) ** 2, 1.1), 0.05, 0.4, release=0.05)
    trem = [v * (0.7 + 0.3 * math.sin(TAU * (6 + 20 * i / RATE) * i / RATE)) for i, v in enumerate(whine)]
    write("sfx_charge", lowpass(trem, lambda t: 800 + 2600 * t), 0.5)

    # Lance: a sharp crack with a ringing metal tail.
    crack = env(highpass(noise(0.5, rng), 1200), 0.0005, 30)
    ring = mix(*[env(osc("sine", f, 0.5), 0.001, d) for f, d in ((180, 6), (412, 9), (733, 12))])
    thump = env(osc("sine", lambda t: 160 * math.exp(-t * 10) + 45, 0.5), 0.001, 9)
    write("sfx_lance", soft_clip(mix(crack, ring, thump, gains=[0.7, 0.5, 0.9]), 1.6), 0.85)

    # Broadside: a deep cannon boom with a little rattle.
    boom = env(osc("sine", lambda t: 110 * math.exp(-t * 6) + 38, 0.6), 0.002, 7)
    rattle = env(lowpass(noise(0.6, rng), 1400), 0.001, 14)
    write("sfx_broadside", soft_clip(mix(boom, rattle, gains=[1.0, 0.6]), 1.7), 0.85)

    # Blink: a reversed swell snapping into a falling chirp (the warden).
    swell = env(lowpass(noise(0.25, rng), lambda t: 300 + 6000 * t / 0.25), 0.2, 0.5)
    chirp = env(osc("sine", lambda t: 2400 * math.exp(-t * 14) + 200, 0.3), 0.001, 12)
    bl = silence(0.6)
    place(bl, swell, 0.0, 0.5)
    place(bl, chirp, 0.24, 0.6)
    write("sfx_blink", bl, 0.6)

    # Mine drop: a dull metal clunk and a tick.
    clunk = mix(*[env(osc("sine", f, 0.25), 0.001, d) for f, d in ((150, 20), (370, 28), (610, 40))])
    tick = env(highpass(noise(0.25, rng), 3000), 0.0005, 120)
    write("sfx_mine_drop", mix(clunk, tick, gains=[0.8, 0.3]), 0.6)


def main():
    rng = random.Random(1987)
    sfx(rng)
    music_rift(rng)
    music_hub(rng)
    sfx_roster(random.Random(2026))


if __name__ == "__main__":
    main()
