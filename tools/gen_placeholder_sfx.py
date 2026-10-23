#!/usr/bin/env python3
"""Generates the placeholder sound effects in assets/audio/sfx/.

Pure standard library: simple synthesized blips and noise bursts so every
gameplay event has *a* sound until real ones exist. To replace one, drop a
file with the same name (.wav or .ogg) in assets/audio/sfx/ and delete the
placeholder; Sfx (autoload/Sfx.gd) prefers .wav, then .ogg.

    python3 tools/gen_placeholder_sfx.py
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
rng = random.Random(1)


def env(i, n, attack=0.005, release=1.0):
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = (1.0 - i / n) ** (2.0 * release)
    return a * r


def tone(dur, f0, f1=None, shape="square", vol=0.5, release=1.0, vibrato=0.0):
    f1 = f0 if f1 is None else f1
    n = int(dur * RATE)
    out, ph = [], 0.0
    for i in range(n):
        k = i / n
        f = f0 * (f1 / f0) ** k
        if vibrato:
            f *= 1.0 + vibrato * math.sin(i / RATE * 2 * math.pi * 18)
        ph += f / RATE
        x = ph % 1.0
        if shape == "square":
            s = 1.0 if x < 0.5 else -1.0
        elif shape == "saw":
            s = 2.0 * x - 1.0
        elif shape == "tri":
            s = 4.0 * abs(x - 0.5) - 1.0
        else:
            s = math.sin(2 * math.pi * x)
        out.append(s * vol * env(i, n, release=release))
    return out


def noise(dur, vol=0.5, lp=0.5, release=1.0, lp_end=None):
    n = int(dur * RATE)
    out, y = [], 0.0
    lp_end = lp if lp_end is None else lp_end
    for i in range(n):
        a = lp + (lp_end - lp) * (i / n)
        y += a * (rng.uniform(-1, 1) - y)
        out.append(y * vol * env(i, n, release=release) * 2.0)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))


SOUNDS = {
    "fire_default": lambda: mix(tone(0.06, 900, 300, "square", 0.3), noise(0.05, 0.3, 0.6)),
    "fire_gun_nail": lambda: mix(tone(0.05, 1400, 500, "square", 0.25), noise(0.04, 0.35, 0.8)),
    "fire_gun_rivet": lambda: mix(tone(0.12, 300, 80, "square", 0.4, 0.6), noise(0.1, 0.5, 0.4)),
    "fire_gun_laser": lambda: tone(0.35, 1800, 300, "saw", 0.4, 0.5, vibrato=0.03),
    "fire_gun_flamethrower": lambda: noise(0.18, 0.5, 0.15, 0.4, 0.05),
    "fire_gun_boomerang": lambda: tone(0.25, 300, 700, "tri", 0.4, 0.6, vibrato=0.08),
    "fire_gun_drone_bay": lambda: tone(0.05, 2200, 1400, "square", 0.2),
    "fire_melee_chain_sword": lambda: mix(noise(0.16, 0.4, 0.9, 0.7), tone(0.16, 140, 110, "saw", 0.3, vibrato=0.2)),
    "fire_sig_tesla_coil": lambda: mix(noise(0.2, 0.4, 0.95, 0.6), tone(0.2, 60, 60, "square", 0.25, vibrato=0.4)),
    "fire_sig_mortar": lambda: mix(tone(0.25, 160, 50, "sine", 0.7, 0.6), noise(0.2, 0.4, 0.2)),
    "enemy_die": lambda: mix(noise(0.12, 0.5, 0.5, 0.8, 0.1), tone(0.1, 400, 120, "square", 0.2)),
    "robot_hit": lambda: mix(tone(0.12, 220, 140, "square", 0.4), noise(0.08, 0.3, 0.7)),
    "robot_die": lambda: mix(noise(1.2, 0.6, 0.3, 0.5, 0.02), tone(1.2, 200, 30, "saw", 0.4, 0.5)),
    "scrap": lambda: tone(0.06, 1320, 1760, "sine", 0.4),
    "part_pickup": lambda: seq(tone(0.07, 660, 660, "square", 0.3), tone(0.1, 990, 990, "square", 0.3)),
    "attach": lambda: mix(noise(0.05, 0.5, 0.7), tone(0.08, 180, 120, "square", 0.4)),
    "level_up": lambda: seq(tone(0.08, 523, None, "square", 0.3), tone(0.08, 659, None, "square", 0.3),
                            tone(0.08, 784, None, "square", 0.3), tone(0.25, 1047, None, "square", 0.3, 0.5)),
    "vent": lambda: noise(0.6, 0.6, 0.6, 0.6, 0.05),
    "stomp": lambda: mix(tone(0.25, 90, 40, "sine", 0.8, 0.6), noise(0.15, 0.4, 0.15)),
    "warn_heat": lambda: seq(tone(0.1, 880, None, "square", 0.3), [0.0] * 1500, tone(0.1, 880, None, "square", 0.3)),
    "warn_power": lambda: tone(0.4, 440, 110, "square", 0.3, 0.4),
    "ui_open": lambda: tone(0.06, 600, 900, "tri", 0.4),
    "ui_close": lambda: tone(0.06, 900, 600, "tri", 0.4),
}

if __name__ == "__main__":
    for name, make in SOUNDS.items():
        write(name, make())
    print("wrote %d sounds to %s" % (len(SOUNDS), os.path.normpath(OUT)))
