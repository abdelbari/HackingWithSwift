#!/usr/bin/env python3
"""Regenerate both phones' built-in music library.

    tools/generate_music.py [path/to/ios/music/folder]

Synthesises each loop in TRACKS the way generate_sounds.py makes its
effects — additive tones and seeded noise shaped by envelopes, nothing
recorded or downloaded: a chord progression on a pad, a bass line, a drum
pattern and an arpeggio. Every loop is 8 bars of 4/4, so 32 beats, which at
120–160 bpm is 12–16 seconds; a note that rings past the loop's end wraps
round to its start, so the loop is seamless when played round and round.
Each is written as a mono 22.05 kHz 16-bit WAV (under 0.75 MB) to
app/src/main/assets/music/<id>.wav, and beside them
core/src/main/resources/com/canvia/core/content/music.json, the list both
phones read: [{"id", "name", "mood", "genre", "bpm", "seconds", "tags"}],
seconds to the thousandth, mood one of upbeat, calm, dramatic, happy, chill
and corporate. Given a folder, the WAVs and music.json are written there too
for the iOS twin to bundle.

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
ASSETS = REPO / 'app/src/main/assets/music'
LIST = REPO / 'core/src/main/resources/com/canvia/core/content/music.json'

RATE = 22050
TAU = 2 * math.pi
BARS = 8
BEATS = BARS * 4
MOODS = ('upbeat', 'calm', 'dramatic', 'happy', 'chill', 'corporate')
MAX_BYTES = 750 * 1024

# A sine table, read with linear steps: far quicker than math.sin per
# sample, and the same on every machine once built.
TABLE_SIZE = 4096
TABLE = [math.sin(TAU * i / TABLE_SIZE) for i in range(TABLE_SIZE + 1)]


def wav(samples, rate):
    """16-bit mono PCM WAV bytes from samples in −1…1."""
    frames = bytearray()
    for s in samples:
        v = int(math.floor(max(-1.0, min(1.0, s)) * 32767 + 0.5))
        frames += struct.pack('<h', v)
    head = struct.pack('<4sI4s4sIHHIIHH4sI', b'RIFF', 36 + len(frames), b'WAVE', b'fmt ', 16, 1, 1, rate, rate * 2, 2, 16, b'data', len(frames))
    return head + bytes(frames)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def oscillator(f, n, partials):
    """[n] samples of a tone at [f] Hz made of [partials], (multiple,
    amplitude) pairs, each partial above the Nyquist left out."""
    out = [0.0] * n
    for mult, amp in partials:
        step = f * mult * TABLE_SIZE / RATE
        if f * mult >= RATE / 2:
            continue
        phase = 0.0
        for i in range(n):
            k = int(phase)
            frac = phase - k
            out[i] += amp * (TABLE[k] + (TABLE[k + 1] - TABLE[k]) * frac)
            phase += step
            if phase >= TABLE_SIZE:
                phase -= TABLE_SIZE
    return out


class Loop:
    """A buffer one loop long that notes are added into, wrapping round."""

    def __init__(self, bpm):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.n = int(round(BEATS * self.beat * RATE))
        self.mix = [0.0] * self.n

    def at(self, beat):
        return int(round(beat * self.beat * RATE))

    def add(self, start, samples, gain):
        n = self.n
        mix = self.mix
        for i, s in enumerate(samples):
            mix[(start + i) % n] += s * gain


def pad(loop, chord, start_beat, beats, gain, bright):
    """A chord held for [beats], slow in and out, a little detuned."""
    n = loop.at(beats) + int(0.6 * RATE)
    attack = 0.35 * RATE
    hold = loop.at(beats)
    partials = [(1.0, 1.0), (2.0, 0.35 * bright), (3.0, 0.18 * bright), (4.0, 0.08 * bright)]
    shape = [min(1.0, i / attack) * (1.0 if i < hold else math.exp(-(i - hold) / (0.18 * RATE))) for i in range(n)]
    for note in chord:
        for detune in (0.997, 1.003):
            tone = oscillator(hz(note) * detune, n, partials)
            loop.add(loop.at(start_beat), [t * s for t, s in zip(tone, shape)], gain / len(chord))


def pluck(loop, note, beat, length, gain, partials=((1.0, 1.0), (2.0, 0.4), (3.0, 0.15))):
    """A short plucked note: quick in, dying away over [length] beats."""
    n = loop.at(length) + int(0.05 * RATE)
    decay = max(0.04, length * loop.beat * 0.45) * RATE
    tone = oscillator(hz(note), n, partials)
    loop.add(loop.at(beat), [t * min(1.0, i / 40.0) * math.exp(-i / decay) for i, t in enumerate(tone)], gain)


def bass(loop, note, beat, length, gain):
    n = loop.at(length)
    tone = oscillator(hz(note), n, [(1.0, 1.0), (2.0, 0.3)])
    release = int(0.02 * RATE)
    loop.add(loop.at(beat), [t * min(1.0, i / 60.0) * min(1.0, (n - i) / release) for i, t in enumerate(tone)], gain)


def kick(loop, beat, gain):
    n = int(0.3 * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase += TAU * (48 + 100 * math.exp(-t * 30)) / RATE
        out.append(math.sin(phase) * math.exp(-t / 0.1))
    loop.add(loop.at(beat), out, gain)


def snare(loop, beat, gain, rng):
    n = int(0.22 * RATE)
    out = [(0.7 * rng.uniform(-1, 1) * math.exp(-i / (0.06 * RATE)) + 0.4 * math.sin(TAU * 190 * i / RATE) * math.exp(-i / (0.04 * RATE))) for i in range(n)]
    loop.add(loop.at(beat), out, gain)


def hat(loop, beat, gain, rng, open_hat=False):
    n = int((0.18 if open_hat else 0.05) * RATE)
    decay = (0.06 if open_hat else 0.012) * RATE
    last = 0.0
    out = []
    for i in range(n):
        w = rng.uniform(-1, 1)
        out.append((w - last) * math.exp(-i / decay))
        last = w
    loop.add(loop.at(beat), out, gain)


def shaker(loop, beat, gain, rng):
    n = int(0.08 * RATE)
    out = [rng.uniform(-1, 1) * math.sin(math.pi * i / n) for i in range(n)]
    loop.add(loop.at(beat), out, gain)


# Scales as semitones from the root.
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def triad(root, scale, degree, size=3):
    """The chord on [degree] (0-based) of [scale] above [root]: stacked
    thirds, [size] notes."""
    notes = []
    for k in range(size):
        d = degree + 2 * k
        notes.append(root + scale[d % 7] + 12 * (d // 7))
    return notes


# Drum patterns over one bar of sixteen steps: kick, snare, hat.
DRUMS = {
    'four': ('x...x...x...x...', '....x.......x...', '..x...x...x...x.'),
    'pop': ('x.....x.x.......', '....x.......x...', 'x.x.x.x.x.x.x.x.'),
    'half': ('x...............', '........x.......', 'x...x...x...x...'),
    'lofi': ('x......x..x.....', '....x.......x...', 'x.x.x.x.x.x.x.xx'),
    'drive': ('x...x...x...x...', '....x.......x...', 'xxxxxxxxxxxxxxxx'),
    'epic': ('x..x..x...x.x...', '....x.......x..x', '................'),
    'none': ('................', '................', '................'),
}


def song(spec):
    loop = Loop(spec['bpm'])
    rng = random.Random(spec['seed'])
    scale = MAJOR if spec['scale'] == 'major' else MINOR
    root = spec['root']
    chords = [triad(root, scale, d, 4 if spec.get('sevenths') else 3) for d in spec['progression']]
    # Two bars a chord: four chords make the eight bars.
    for c, chord in enumerate(chords):
        start = c * 8
        pad(loop, [n + 12 for n in chord], start, 8, spec['pad'], spec.get('bright', 1.0))
        low = root + scale[spec['progression'][c] % 7] - 24
        for b, (at, length, up) in enumerate(spec['bassline']):
            if spec.get('bass', 0) > 0:
                bass(loop, low + up, start + at, length, spec['bass'])
        if spec.get('arp', 0) > 0:
            step = spec['arp_step']
            tones = [n + 24 for n in chord] + [chord[0] + 36]
            order = spec.get('arp_order', 'up')
            seq = tones if order == 'up' else tones + tones[-2:0:-1]
            for i in range(int(8 / step)):
                note = seq[i % len(seq)]
                pluck(loop, note, start + i * step, step * 1.8, spec['arp'] * (0.85 + 0.3 * rng.random()))
    kicks, snares, hats = DRUMS[spec['drums']]
    for bar in range(BARS):
        for s in range(16):
            beat = bar * 4 + s / 4.0
            if kicks[s] == 'x':
                kick(loop, beat, spec['kick'])
            if snares[s] == 'x':
                snare(loop, beat, spec['snare'], rng)
            if hats[s] == 'x':
                hat(loop, beat, spec['hat'] * (0.7 + 0.3 * rng.random()), rng, open_hat=(s == 14 and spec.get('open_hats')))
        if spec.get('shaker'):
            for s in range(0, 16, 2):
                shaker(loop, bar * 4 + s / 4.0 + 0.25, spec['shaker'] * (0.6 + 0.4 * rng.random()), rng)
    top = max(abs(s) for s in loop.mix) or 1.0
    return [s * 0.85 / top for s in loop.mix]


# Bass lines over two bars: (beat, length in beats, semitones above the root).
ROOTS = [(0, 1.8, 0), (2, 1.8, 0), (4, 1.8, 0), (6, 1.8, 7)]
EIGHTHS = [(i * 0.5, 0.45, 0 if i % 4 else 12 if i % 8 == 4 else 0) for i in range(16)]
HELD = [(0, 7.8, 0)]
WALK = [(0, 1.5, 0), (1.5, 0.5, 0), (2, 1.0, 7), (3, 1.0, 5), (4, 1.5, 0), (5.5, 0.5, 0), (6, 1.0, 7), (7, 1.0, 10)]

# id, name, mood, genre, tags, and how it is made. The order the panel
# lists them in.
TRACKS = [
    ('sunny-side', 'Sunny Side', 'upbeat', 'pop', ['bright', 'summer', 'energetic', 'positive'],
     dict(seed=101, bpm=128, root=60, scale='major', progression=[0, 4, 5, 3], pad=0.35, bass=0.5, bassline=EIGHTHS,
          arp=0.25, arp_step=0.5, drums='pop', kick=0.9, snare=0.5, hat=0.18, open_hats=True)),
    ('city-lights', 'City Lights', 'upbeat', 'electronic', ['dance', 'night', 'club', 'synth'],
     dict(seed=102, bpm=124, root=57, scale='minor', progression=[0, 5, 2, 6], pad=0.3, bass=0.55, bassline=EIGHTHS,
          arp=0.22, arp_step=0.25, arp_order='updown', drums='four', kick=1.0, snare=0.45, hat=0.2, bright=1.4)),
    ('little-wins', 'Little Wins', 'happy', 'ukulele', ['cheerful', 'kids', 'playful', 'sunny'],
     dict(seed=103, bpm=140, root=65, scale='major', progression=[0, 3, 4, 0], pad=0.18, bass=0.45, bassline=ROOTS,
          arp=0.35, arp_step=0.5, arp_order='updown', drums='half', kick=0.6, snare=0.3, hat=0.1, shaker=0.08)),
    ('balloon-ride', 'Balloon Ride', 'happy', 'pop', ['fun', 'birthday', 'party', 'bouncy'],
     dict(seed=104, bpm=150, root=62, scale='major', progression=[0, 5, 3, 4], pad=0.25, bass=0.5, bassline=WALK,
          arp=0.25, arp_step=0.5, drums='pop', kick=0.8, snare=0.45, hat=0.15)),
    ('still-water', 'Still Water', 'calm', 'ambient', ['peaceful', 'meditation', 'relax', 'soft'],
     dict(seed=105, bpm=120, root=55, scale='major', progression=[0, 3, 5, 4], pad=0.6, bass=0.3, bassline=HELD,
          arp=0.12, arp_step=1.0, drums='none', kick=0.0, snare=0.0, hat=0.0, bright=0.5, sevenths=True)),
    ('soft-focus', 'Soft Focus', 'calm', 'piano', ['gentle', 'reflective', 'quiet', 'keys'],
     dict(seed=106, bpm=120, root=60, scale='major', progression=[5, 3, 0, 4], pad=0.25, bass=0.35, bassline=ROOTS,
          arp=0.4, arp_step=1.0, arp_order='updown', drums='none', kick=0.0, snare=0.0, hat=0.0, bright=0.6)),
    ('slow-sunday', 'Slow Sunday', 'chill', 'lo-fi', ['study', 'cozy', 'beats', 'relax'],
     dict(seed=107, bpm=120, root=58, scale='minor', progression=[0, 3, 6, 4], pad=0.35, bass=0.45, bassline=ROOTS,
          arp=0.2, arp_step=1.0, drums='lofi', kick=0.7, snare=0.4, hat=0.08, bright=0.5, sevenths=True)),
    ('night-drive', 'Night Drive', 'chill', 'synthwave', ['retro', 'eighties', 'road', 'neon'],
     dict(seed=108, bpm=124, root=57, scale='minor', progression=[0, 5, 6, 4], pad=0.4, bass=0.5, bassline=EIGHTHS,
          arp=0.2, arp_step=0.25, drums='half', kick=0.7, snare=0.45, hat=0.12, bright=1.2)),
    ('rising-storm', 'Rising Storm', 'dramatic', 'cinematic', ['epic', 'trailer', 'tension', 'action'],
     dict(seed=109, bpm=120, root=50, scale='minor', progression=[0, 5, 2, 6], pad=0.55, bass=0.6, bassline=EIGHTHS,
          arp=0.15, arp_step=0.25, drums='epic', kick=1.0, snare=0.6, hat=0.0, bright=1.2)),
    ('final-hour', 'Final Hour', 'dramatic', 'orchestral', ['dark', 'suspense', 'trailer', 'strings'],
     dict(seed=110, bpm=132, root=53, scale='minor', progression=[0, 6, 5, 4], pad=0.6, bass=0.5, bassline=HELD,
          arp=0.2, arp_step=0.5, arp_order='updown', drums='half', kick=0.9, snare=0.3, hat=0.0, bright=0.9)),
    ('forward-motion', 'Forward Motion', 'corporate', 'corporate', ['business', 'presentation', 'inspiring', 'technology'],
     dict(seed=111, bpm=124, root=64, scale='major', progression=[0, 4, 5, 3], pad=0.35, bass=0.45, bassline=EIGHTHS,
          arp=0.25, arp_step=0.5, drums='drive', kick=0.8, snare=0.4, hat=0.08)),
    ('big-idea', 'Big Idea', 'corporate', 'acoustic', ['startup', 'explainer', 'optimistic', 'clean'],
     dict(seed=112, bpm=120, root=60, scale='major', progression=[3, 0, 4, 5], pad=0.3, bass=0.45, bassline=WALK,
          arp=0.3, arp_step=0.5, drums='pop', kick=0.7, snare=0.35, hat=0.12, shaker=0.06)),
]


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    ios = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else None
    ASSETS.mkdir(parents=True, exist_ok=True)
    listed = []
    total = 0
    for key, name, mood, genre, tags, spec in TRACKS:
        assert mood in MOODS, key
        samples = song(spec)
        seconds = len(samples) / RATE
        assert 12.0 <= seconds <= 16.0, key
        data = wav(samples, RATE)
        assert len(data) < MAX_BYTES, key
        total += len(data)
        (ASSETS / (key + '.wav')).write_bytes(data)
        if ios:
            (ios / (key + '.wav')).write_bytes(data)
        listed.append({
            'id': key, 'name': name, 'mood': mood, 'genre': genre, 'bpm': spec['bpm'],
            'seconds': math.floor(seconds * 1000 + 0.5) / 1000, 'tags': tags,
        })
    text = '[\n' + ',\n'.join(json.dumps(e, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for e in listed) + '\n]\n'
    LIST.write_text(text, encoding='utf-8')
    if ios:
        (ios / 'music.json').write_text(text, encoding='utf-8')
    print('%d loops, %d bytes of music' % (len(listed), total))


if __name__ == '__main__':
    main()
