#!/usr/bin/env python3
"""Regenerate both phones' built-in sound effects, and the beat fixtures.

    tools/generate_sounds.py [path/to/ios/sfx/folder]

Synthesises each effect in EFFECTS — additive tones and seeded noise, shaped
by envelopes, nothing recorded or downloaded — and writes it as a mono
44.1 kHz 16-bit WAV to app/src/main/assets/sfx/<id>.wav, every one under two
seconds. AAC would be smaller, but no encoder ships with Python, so they stay
WAV, which both phones play and mix as they do any song. Beside them it
writes core/src/main/resources/com/canvia/core/content/sfx.json, the list
both phones read: [{"id", "name", "tags": [...], "seconds"}], seconds to the
thousandth. Given a folder, the WAVs and sfx.json are written there too for
the iOS twin to bundle.

It also writes the shared Beat Sync fixtures to
core/src/test/resources/com/canvia/core/content/beats/, mono 22050 Hz 16-bit
WAVs that both phones' Beats tests read: clicks at 120 bpm, a kick and
hi-hat groove at 100 bpm, and silence.

Every sample is computed the same way on any machine: fixed seeds, no
clock, and each value rounded to the nearest whole 16-bit step.
"""
import json
import math
import pathlib
import random
import struct
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
ASSETS = REPO / 'app/src/main/assets/sfx'
LIST = REPO / 'core/src/main/resources/com/canvia/core/content/sfx.json'
FIXTURES = REPO / 'core/src/test/resources/com/canvia/core/content/beats'

RATE = 44100
TAU = 2 * math.pi


def wav(samples, rate):
    """16-bit mono PCM WAV bytes from samples in −1…1."""
    frames = bytearray()
    for s in samples:
        v = int(math.floor(max(-1.0, min(1.0, s)) * 32767 + 0.5))
        frames += struct.pack('<h', v)
    head = struct.pack('<4sI4s4sIHHIIHH4sI', b'RIFF', 36 + len(frames), b'WAVE', b'fmt ', 16, 1, 1, rate, rate * 2, 2, 16, b'data', len(frames))
    return head + bytes(frames)


def env(t, attack, decay):
    """Rises over [attack] seconds, then dies away exponentially."""
    if t < attack:
        return t / attack if attack > 0 else 1.0
    return math.exp(-(t - attack) / decay)


def fade(samples, seconds=0.01):
    """Ends faded to silence, so no effect ends in a click."""
    n = min(len(samples), int(seconds * RATE))
    for i in range(n):
        samples[-1 - i] *= i / n
    return samples


def normalise(samples, peak=0.85):
    top = max(abs(s) for s in samples) or 1.0
    return [s * peak / top for s in samples]


class Noise:
    """Seeded white noise, and a one-pole low-pass of it."""

    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.last = 0.0

    def white(self):
        return self.rng.uniform(-1.0, 1.0)

    def low(self, k):
        self.last += k * (self.white() - self.last)
        return self.last


def make(seconds, fn):
    return [fn(i / RATE) for i in range(int(seconds * RATE))]


def sweep_noise(seconds, seed, k_from, k_to, shape):
    noise = Noise(seed)
    out = []
    n = int(seconds * RATE)
    for i in range(n):
        x = i / n
        out.append(noise.low(k_from + (k_to - k_from) * x) * shape(x))
    return out


def tone(f, t, phase=0.0):
    return math.sin(TAU * f * t + phase)


def whoosh():
    return sweep_noise(0.9, 1, 0.02, 0.25, lambda x: math.sin(math.pi * x) ** 2)


def swoosh():
    return sweep_noise(0.6, 2, 0.3, 0.04, lambda x: math.sin(math.pi * x ** 0.6) ** 3)


def pop():
    return make(0.18, lambda t: tone(420 + 900 * math.exp(-t * 60), t) * env(t, 0.002, 0.03))


def click():
    noise = Noise(3)
    return make(0.06, lambda t: (0.6 * noise.white() + tone(2200, t)) * env(t, 0.0005, 0.006))


def tick():
    return make(0.05, lambda t: tone(3200, t) * env(t, 0.0005, 0.004))


def ding():
    return make(1.6, lambda t: (tone(1318.5, t) + 0.4 * tone(2637, t) + 0.15 * tone(3955.5, t)) * env(t, 0.003, 0.45))


def chime():
    notes = [(0.0, 1046.5), (0.12, 1318.5), (0.24, 1568.0)]
    return make(1.4, lambda t: sum(tone(f, t - s) * env(t - s, 0.003, 0.35) for s, f in notes if t >= s))


def bell():
    partials = [(1.0, 1.0, 0.9), (2.76, 0.5, 0.5), (5.4, 0.25, 0.3), (8.93, 0.12, 0.2)]
    return make(1.9, lambda t: sum(a * tone(587.3 * r, t) * env(t, 0.002, d) for r, a, d in partials))


def sparkle():
    rng = random.Random(4)
    hits = [(rng.uniform(0, 0.7), rng.uniform(2500, 5200)) for _ in range(14)]
    return make(1.0, lambda t: sum(tone(f, t - s) * env(t - s, 0.001, 0.08) for s, f in hits if t >= s) * 0.5)


def riser():
    noise = Noise(5)
    n = int(1.8 * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        x = i / n
        f = 200 + 1400 * x * x
        phase += TAU * f / RATE
        out.append((0.6 * math.sin(phase) + 0.4 * noise.low(0.05 + 0.5 * x)) * x ** 1.5)
    return out


def drop():
    n = int(1.2 * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 900 * math.exp(-t * 3.2) + 40
        phase += TAU * f / RATE
        out.append(math.sin(phase) * env(t, 0.005, 0.5))
    return out


def boom():
    noise = Noise(6)
    return make(1.8, lambda t: (tone(48 + 30 * math.exp(-t * 8), t) * 0.8 + 0.5 * noise.low(0.02)) * env(t, 0.004, 0.5))


def kick():
    n = int(0.5 * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase += TAU * (50 + 110 * math.exp(-t * 35)) / RATE
        out.append(math.sin(phase) * env(t, 0.001, 0.12))
    return out


def snare():
    noise = Noise(7)
    return make(0.4, lambda t: (0.7 * noise.white() * env(t, 0.001, 0.08) + 0.5 * tone(185, t) * env(t, 0.001, 0.05)))


def clap():
    noise = Noise(8)
    starts = [0.0, 0.011, 0.023, 0.036]
    return make(0.5, lambda t: noise.low(0.5) * max(env(t - s, 0.0005, 0.012 if s < 0.03 else 0.12) for s in starts if t >= s) if t >= 0 else 0.0)


def typewriter():
    noise = Noise(9)
    return make(0.25, lambda t: (noise.white() * env(t, 0.0005, 0.01) + 0.5 * tone(1800, t) * env(t, 0.0005, 0.02)
                                 + (0.4 * noise.white() * env(t - 0.06, 0.0005, 0.015) if t >= 0.06 else 0.0)))


def shutter():
    noise = Noise(10)

    def at(t):
        a = noise.low(0.6) * env(t, 0.0005, 0.012)
        b = noise.low(0.6) * env(t - 0.09, 0.0005, 0.02) if t >= 0.09 else 0.0
        return a + 0.8 * b
    return make(0.3, at)


def notification():
    notes = [(0.0, 880.0), (0.14, 1174.7)]
    return make(0.8, lambda t: sum((tone(f, t - s) + 0.3 * tone(2 * f, t - s)) * env(t - s, 0.004, 0.18) for s, f in notes if t >= s))


def error():
    def at(t):
        square = 1.0 if math.sin(TAU * 140 * t) >= 0 else -1.0
        gate = 1.0 if (t < 0.16 or 0.22 <= t < 0.4) else 0.0
        return 0.5 * square * gate
    return make(0.45, at)


def success():
    notes = [(0.0, 523.3), (0.1, 659.3), (0.2, 784.0), (0.3, 1046.5)]
    return make(1.1, lambda t: sum(tone(f, t - s) * env(t - s, 0.004, 0.25) for s, f in notes if t >= s))


def coin():
    def at(t):
        f = 988 if t < 0.08 else 1319
        return (1.0 if math.sin(TAU * f * t) >= 0 else -1.0) * 0.4 * env(t, 0.001, 0.25)
    return make(0.6, at)


def bubble():
    n = int(0.3 * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase += TAU * (300 + 1500 * t / 0.3) / RATE
        out.append(math.sin(phase) * env(t, 0.003, 0.06))
    return out


def swipe():
    return sweep_noise(0.35, 11, 0.6, 0.1, lambda x: math.sin(math.pi * x) ** 2)


def glitch():
    rng = random.Random(12)
    noise = Noise(13)
    cuts = [(rng.uniform(0, 0.55), rng.choice([0, 1, 2]), rng.uniform(200, 2400)) for _ in range(12)]
    cuts.sort()

    def at(t):
        kind, f = 0, 400.0
        for s, k, freq in cuts:
            if t >= s:
                kind, f = k, freq
        if kind == 0:
            return 0.6 if math.sin(TAU * f * t) >= 0 else -0.6
        if kind == 1:
            return noise.white() * 0.7
        return 0.0
    return make(0.6, at)


# id, name, tags, how it is made. The order the audio panel lists them in.
EFFECTS = [
    ('whoosh', 'Whoosh', ['air', 'fast', 'transition', 'wind'], whoosh),
    ('swoosh', 'Swoosh', ['air', 'fast', 'transition', 'swish'], swoosh),
    ('pop', 'Pop', ['bubble', 'cartoon', 'appear'], pop),
    ('click', 'Click', ['button', 'tap', 'mouse', 'ui'], click),
    ('tick', 'Tick', ['clock', 'tap', 'ui'], tick),
    ('ding', 'Ding', ['bell', 'alert', 'correct'], ding),
    ('chime', 'Chime', ['bell', 'magic', 'notification'], chime),
    ('bell', 'Bell', ['ring', 'church', 'alert'], bell),
    ('sparkle', 'Sparkle', ['magic', 'shine', 'twinkle', 'glitter'], sparkle),
    ('riser', 'Riser', ['build', 'tension', 'transition', 'intro'], riser),
    ('drop', 'Drop', ['fall', 'down', 'transition'], drop),
    ('boom', 'Boom', ['explosion', 'impact', 'bass', 'hit'], boom),
    ('kick', 'Kick drum', ['drum', 'beat', 'bass', 'hit'], kick),
    ('snare', 'Snare', ['drum', 'beat', 'hit'], snare),
    ('clap', 'Clap', ['hands', 'applause', 'beat'], clap),
    ('typewriter-key', 'Typewriter key', ['typing', 'keyboard', 'type'], typewriter),
    ('camera-shutter', 'Camera shutter', ['photo', 'camera', 'snap'], shutter),
    ('notification', 'Notification', ['alert', 'message', 'phone'], notification),
    ('error-buzz', 'Error buzz', ['wrong', 'fail', 'alert', 'buzzer'], error),
    ('success', 'Success', ['win', 'correct', 'done', 'level up'], success),
    ('coin', 'Coin', ['game', 'money', 'collect'], coin),
    ('bubble', 'Bubble', ['water', 'pop', 'blip'], bubble),
    ('swipe', 'Swipe', ['slide', 'transition', 'page'], swipe),
    ('glitch', 'Glitch', ['digital', 'error', 'noise', 'tech'], glitch),
]


def fixture_clicks(rate, bpm, seconds, offset):
    n = int(seconds * rate)
    out = [0.0] * n
    period = 60.0 / bpm
    t = offset
    while t < seconds:
        start = int(t * rate)
        for i in range(int(0.03 * rate)):
            if start + i < n:
                out[start + i] += math.sin(TAU * 1500 * i / rate) * math.exp(-i / (0.004 * rate)) * 0.8
        t += period
    return out


def fixture_groove(rate, bpm, seconds):
    n = int(seconds * rate)
    out = [0.0] * n
    rng = random.Random(21)
    beat = 60.0 / bpm
    i_beat = 0
    t = 0.1
    while t < seconds:
        start = int(t * rate)
        phase = 0.0
        for i in range(int(0.25 * rate)):
            if start + i >= n:
                break
            s = i / rate
            phase += TAU * (50 + 110 * math.exp(-s * 35)) / rate
            out[start + i] += 0.7 * math.sin(phase) * math.exp(-s / 0.09)
        # A hat on the off-beat, much quieter: noise moves every band of
        # the spectrum, so it is kept well under the kick.
        h = int((t + beat / 2) * rate)
        for i in range(int(0.04 * rate)):
            if h + i < n:
                out[h + i] += 0.03 * rng.uniform(-1, 1) * math.exp(-i / (0.01 * rate))
        i_beat += 1
        t += beat
    return out


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    ios = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else None
    ASSETS.mkdir(parents=True, exist_ok=True)
    listed = []
    for key, name, tags, fn in EFFECTS:
        samples = normalise(fade(fn()))
        seconds = len(samples) / RATE
        assert seconds < 2.0, key
        data = wav(samples, RATE)
        (ASSETS / (key + '.wav')).write_bytes(data)
        if ios:
            (ios / (key + '.wav')).write_bytes(data)
        listed.append({'id': key, 'name': name, 'tags': tags, 'seconds': math.floor(seconds * 1000 + 0.5) / 1000})
    text = '[\n' + ',\n'.join(json.dumps(e, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for e in listed) + '\n]\n'
    LIST.write_text(text, encoding='utf-8')
    if ios:
        (ios / 'sfx.json').write_text(text, encoding='utf-8')
    FIXTURES.mkdir(parents=True, exist_ok=True)
    (FIXTURES / 'clicks-120.wav').write_bytes(wav(fixture_clicks(22050, 120, 8.0, 0.25), 22050))
    (FIXTURES / 'groove-100.wav').write_bytes(wav(fixture_groove(22050, 100, 8.0), 22050))
    (FIXTURES / 'silence.wav').write_bytes(wav([0.0] * (3 * 22050), 22050))
    print('%d effects, %d bytes of sound' % (len(listed), sum((ASSETS / (k + '.wav')).stat().st_size for k, *_ in EFFECTS)))


if __name__ == '__main__':
    main()
