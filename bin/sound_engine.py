#!/usr/bin/env python3
"""
callmeback — Sound Engine
Usage: python3 sound_engine.py <sound_name> [reminder]
  sound_name : chime | bell | pop | ping | soft | water | whoosh | gentle
  reminder   : optional flag — plays a softer/shorter version for repeat beeps
"""
import struct, wave, tempfile, os, subprocess, math, sys

sound_type = sys.argv[1] if len(sys.argv) > 1 else "gentle"
is_reminder = len(sys.argv) > 2 and sys.argv[2] == "reminder"

rate = 44100

def sine(freq, dur, vol=0.6):
    n, fade = int(rate * dur), int(rate * 0.015)
    out = []
    for i in range(n):
        s = math.sin(2 * math.pi * freq * i / rate)
        if i < fade:       s *= i / fade
        elif i > n - fade: s *= (n - i) / fade
        out.append(int(32767 * vol * s))
    return out

def sine_exp(freq, dur, vol=0.6, decay=6.0):
    n = int(rate * dur)
    return [int(32767 * vol * math.exp(-decay * i / n) *
                math.sin(2 * math.pi * freq * i / rate)) for i in range(n)]

def silence(dur):
    return [0] * int(rate * dur)

# ── Full "task done" sounds ───────────────────────────────────────────
SOUNDS = {
    "chime":  sine(523, 0.18) + sine(659, 0.28),
    "bell":   sine(440, 0.25, 0.8),
    "pop":    sine(220, 0.12, 0.5) + sine(180, 0.08, 0.3),
    "ping":   sine(880, 0.15, 0.5) + sine(1047, 0.2, 0.4),
    "soft":   sine(330, 0.20, 0.28) + sine(392, 0.25, 0.18),
    "water":  sine_exp(1200, 0.35, 0.55, 7.0) + silence(0.04) + sine_exp(900, 0.28, 0.3, 9.0),
    "whoosh": [
        int(32767 * 0.3 *
            math.sin(2 * math.pi * (300 + 400 * (i / int(rate * 0.4))) * i / rate) *
            math.exp(-3.5 * i / int(rate * 0.4)))
        for i in range(int(rate * 0.4))
    ],
    "gentle": (sine_exp(528, 0.30, 0.35, 5.0) + silence(0.06) +
               sine_exp(660, 0.30, 0.28, 5.5) + silence(0.06) +
               sine_exp(792, 0.35, 0.22, 6.0)),
}

# ── Reminder variants — same character, quieter & shorter ────────────
# Recognisably the same sound but clearly softer — "hey, still waiting"
REMINDERS = {
    "chime":  sine(523, 0.12, 0.25),
    "bell":   sine(440, 0.14, 0.30),
    "pop":    sine(220, 0.10, 0.20),
    "ping":   sine(880, 0.10, 0.22),
    "soft":   sine(330, 0.12, 0.12),
    "water":  sine_exp(1200, 0.20, 0.25, 9.0),
    "whoosh": [
        int(32767 * 0.12 *
            math.sin(2 * math.pi * (300 + 300 * (i / int(rate * 0.22))) * i / rate) *
            math.exp(-5.0 * i / int(rate * 0.22)))
        for i in range(int(rate * 0.22))
    ],
    "gentle": sine_exp(528, 0.20, 0.18, 7.0) + silence(0.04) + sine_exp(660, 0.18, 0.13, 8.0),
}

pool = REMINDERS if is_reminder else SOUNDS
samples = pool.get(sound_type, pool["gentle"])

def to_bytes(s):
    return b"".join(struct.pack("<h", max(-32767, min(32767, v))) for v in s)

with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
    path = f.name
    with wave.open(f, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(to_bytes(samples))

played = False
for cmd in [
    ["afplay", path],
    ["paplay", path],
    ["aplay", "-q", path],
    ["pw-play", path],
    ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", path],
]:
    try:
        if subprocess.run(cmd, capture_output=True, timeout=5).returncode == 0:
            played = True
            break
    except:
        continue

os.unlink(path)
sys.exit(0 if played else 1)
