#!/usr/bin/env python3
"""Regenerate both phones' built-in music library.

    tools/generate_music.py [path/to/ios/music/folder]

Synthesises each loop in TRACKS the way generate_sounds.py makes its
effects — additive tones and seeded noise shaped by envelopes, nothing
recorded or downloaded: a chord progression as a pad, a bass line, a drum
pattern and an arpeggio, each switched on or off per track. Every loop is
8 bars of 4/4, 12 to 16 seconds at its tempo, and seamless: what rings on
past the last bar is folded back over the first, so the loop goes round
without a click. Each is a mono 22.05 kHz 16-bit WAV, under 0.75 MB,
written to app/src/main/assets/music/<id>.wav. Beside them it writes
core/src/main/resources/com/canvia/core/content/music.json, the list both
phones read (MusicLibrary): [{"id", "name", "mood", "genre", "bpm",
"seconds", "tags": [...]}], mood one of upbeat, calm, dramatic, happy,
chill and corporate, seconds to the thousandth. Given a folder, the WAVs
and music.json are written there too for the iOS twin to bundle.

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
BEATS = 4
MOODS = ('upbeat', 'calm', 'dramatic', 'happy', 'chill', 'corporate')


def wav(samples, rate):
    """16-bit mono PCM WAV bytes from samples in −1…1."""
    frames = bytearray()
    for s in samples:
        v = int(math.floor(max(-1.0, min(1.0, s)) * 32767 + 0.5))
        frames += struct.pack('<h', v)
    head = struct.pack('<4sI4s4sIHHIIHH4sI', b'RIFF', 36 + len(frames), b'WAVE', b'fmt ', 16, 1, 1, rate, rate * 2, 2, 16, b'data', len(frames))
    return head + bytes(frames)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


# Chord qualities as semitones above the root.
QUALITY = {
    'maj': (0, 4, 7), 'min': (0, 3, 7), 'maj7': (0, 4, 7, 11), 'min7': (0, 3, 7, 10),
    'dom7': (0, 4, 7, 10), 'sus2': (0, 2, 7), 'sus4': (0, 5, 7),
}


class Loop:
    """A loop being written: `n` samples, and anything that rings past the
    end folded back onto the start."""

    def __init__(self, seconds):
        self.n = int(round(seconds * RATE))
        self.out = [0.0] * self.n

    def add(self, start, values, gain):
        n = self.n
        i0 = int(round(start * RATE))
        for k, v in enumerate(values):
            self.out[(i0 + k) % n] += v * gain


def adsr(count, attack, release):
    """A gain shape `count` samples long: up over `attack` seconds, held,
    and down over the last `release` seconds."""
    a = max(1, int(attack * RATE))
    r = max(1, int(release * RATE))
    shape = []
    for i in range(count):
        g = min(1.0, i / a)
        if i > count - r:
            g *= max(0.0, (count - i) / r)
        shape.append(g)
    return shape


def pad(freqs, seconds, detune=0.004):
    """Soft chord: each tone two slightly detuned sines and a quiet octave."""
    count = int(seconds * RATE)
    shape = adsr(count, min(0.6, seconds / 3), min(0.8, seconds / 3))
    out = []
    for i in range(count):
        t = i / RATE
        v = 0.0
        for f in freqs:
            v += math.sin(TAU * f * (1 - detune) * t) + math.sin(TAU * f * (1 + detune) * t) + 0.25 * math.sin(TAU * 2 * f * t)
        out.append(v * shape[i] / (2.25 * len(freqs)))
    return out


def pluck(f, seconds, bright=3):
    """A plucked note: odd harmonics dying away, the higher ones sooner."""
    count = int(seconds * RATE)
    out = []
    for i in range(count):
        t = i / RATE
        v = 0.0
        for h in range(1, bright * 2, 2):
            v += math.sin(TAU * f * h * t) * math.exp(-t * (6 + 4 * h)) / h
        out.append(v * min(1.0, i / 40))
    return out


def bass(f, seconds):
    count = int(seconds * RATE)
    shape = adsr(count, 0.005, min(0.08, seconds / 2))
    return [(math.sin(TAU * f * i / RATE) + 0.35 * math.sin(TAU * 2 * f * i / RATE)) * shape[i] for i in range(count)]


def kick():
    out = []
    phase = 0.0
    for i in range(int(0.35 * RATE)):
        t = i / RATE
        phase += TAU * (48 + 100 * math.exp(-t * 30)) / RATE
        out.append(math.sin(phase) * math.exp(-t / 0.11))
    return out


def snare(rng):
    return [(0.7 * rng.uniform(-1, 1) * math.exp(-(i / RATE) / 0.07) + 0.4 * math.sin(TAU * 190 * i / RATE) * math.exp(-(i / RATE) / 0.04))
            for i in range(int(0.25 * RATE))]


def hat(rng, open_=False):
    decay = 0.09 if open_ else 0.02
    last = 0.0
    out = []
    for i in range(int((0.25 if open_ else 0.06) * RATE)):
        w = rng.uniform(-1, 1)
        out.append((w - last) * 0.5 * math.exp(-(i / RATE) / decay))   # a crude high-pass: the change in the noise
        last = w
    return out


def tom(f):
    return [math.sin(TAU * f * (1 + 0.5 * math.exp(-(i / RATE) * 20)) * i / RATE) * math.exp(-(i / RATE) / 0.25)
            for i in range(int(0.5 * RATE))]


def clap(rng):
    out = []
    for i in range(int(0.2 * RATE)):
        t = i / RATE
        g = max(math.exp(-(t - s) / (0.01 if s < 0.02 else 0.06)) if t >= s else 0.0 for s in (0.0, 0.01, 0.02))
        out.append(rng.uniform(-1, 1) * g)
    return out


def render(track):
    """One track's loop, normalised to a 0.8 peak."""
    bpm = track['bpm']
    beat = 60.0 / bpm
    seconds = BARS * BEATS * beat
    loop = Loop(seconds)
    rng = random.Random(track['seed'])
    root = track['key']
    chords = track['chords']            # one per bar, cycled: (semitones from the key, quality)
    per_bar = [chords[b % len(chords)] for b in range(BARS)]
    layers = track['layers']

    # Pad: the bar's chord, a little past the bar so chords overlap.
    if 'pad' in layers:
        for b, (step, quality) in enumerate(per_bar):
            freqs = [hz(root + step + q) for q in QUALITY[quality]]
            loop.add(b * BEATS * beat, pad(freqs, BEATS * beat + 0.3), layers['pad'])

    # Bass: the chord's root, an octave down, on the pattern's steps (8ths).
    if 'bass' in layers:
        pattern = track.get('bassline', 'x.x.x.x.')
        for b, (step, _) in enumerate(per_bar):
            f = hz(root + step - 24)
            for k, ch in enumerate(pattern):
                if ch == 'x':
                    loop.add((b * BEATS + k / 2) * beat, bass(f, beat * 0.45), layers['bass'])
                elif ch == 'o':
                    loop.add((b * BEATS + k / 2) * beat, bass(f * 2, beat * 0.45), layers['bass'])

    # Arpeggio: the chord's tones up and down, an octave up, in 8ths or 16ths.
    if 'arp' in layers:
        division = track.get('arpDivision', 2)
        for b, (step, quality) in enumerate(per_bar):
            tones = [root + 12 + step + q for q in QUALITY[quality]]
            order = tones + tones[-2:0:-1]
            for k in range(BEATS * division):
                note = order[k % len(order)]
                loop.add((b * BEATS + k / division) * beat, pluck(hz(note), beat * 1.2), layers['arp'])

    # Drums: 16 steps a bar, k kick, s snare, c clap, h hat, o open hat, t tom.
    if 'drums' in layers:
        sounds = {'k': kick(), 's': snare(rng), 'c': clap(rng), 'h': hat(rng), 'o': hat(rng, True),
                  't': tom(hz(root - 12)), 'T': tom(hz(root - 17))}
        pattern = track['drums']
        level = {'k': 1.0, 's': 0.6, 'c': 0.55, 'h': 0.35, 'o': 0.3, 't': 0.8, 'T': 0.8}
        for b in range(BARS):
            bar = pattern[b % len(pattern)]
            for k, cell in enumerate(bar.split('|')):
                for ch in cell:
                    if ch in sounds:
                        loop.add((b * BEATS + k / 4) * beat, sounds[ch], layers['drums'] * level[ch])

    top = max(abs(s) for s in loop.out) or 1.0
    return [s * 0.8 / top for s in loop.out]


def bar(pattern):
    """A drum bar written as 16 cells of one or more sounds, '.' for none."""
    cells = [c if c != '.' else '' for c in pattern.split()]
    assert len(cells) == 16, pattern
    return '|'.join(cells)


FOUR = bar('kh . h . sh . h . kh . h . sh . h .')
FOUR_OPEN = bar('kh . ho . sh . ho . kh . ho . sh . ho .')
POP = bar('kh . h . sh . h kh kh . h . sh . h .')
FUNK = bar('kh . h kh sh . h . h kh h . sh . kh h')
LOFI = bar('k . . . s . . k . . k . s . . .')
CHILL = bar('kh . h . ch . h . h kh h . ch . h .')
TOMS = bar('kt . . t T . t . kt . t . T . T t')
EPIC = bar('kt . . kt s . . t kt . kt . s t T T')
CORP = bar('kh . h . ch . h . kh . kh . ch . h h')
SOFT = bar('k . . . . . . . k . . . . . . .')

# id, name, mood, genre, bpm (32 beats: 120 bpm is 16 s, 160 is 12 s),
# key (MIDI root), one chord a bar cycled, the layers and their levels,
# drum bars cycled, and tags. The order the Audio sheet lists them in.
TRACKS = [
    dict(id='sunny-skip', name='Sunny Skip', mood='happy', genre='Pop', bpm=128, key=60, seed=101,
         chords=[(0, 'maj'), (7, 'maj'), (9, 'min'), (5, 'maj')],
         layers={'pad': 0.5, 'bass': 0.6, 'arp': 0.35, 'drums': 0.8}, drums=[POP],
         tags=['bright', 'cheerful', 'summer', 'fun', 'positive']),
    dict(id='bright-side', name='Bright Side', mood='happy', genre='Acoustic', bpm=120, key=67, seed=102,
         chords=[(0, 'maj'), (5, 'maj'), (0, 'maj'), (7, 'maj')], arpDivision=4,
         layers={'pad': 0.35, 'bass': 0.5, 'arp': 0.5, 'drums': 0.5}, drums=[FOUR],
         tags=['guitar', 'warm', 'family', 'sunny', 'light']),
    dict(id='city-rush', name='City Rush', mood='upbeat', genre='Electronic', bpm=128, key=57, seed=103,
         chords=[(0, 'min'), (8, 'maj'), (3, 'maj'), (10, 'maj')], bassline='xoxoxoxo', arpDivision=4,
         layers={'pad': 0.4, 'bass': 0.6, 'arp': 0.4, 'drums': 0.9}, drums=[FOUR_OPEN],
         tags=['dance', 'energy', 'fast', 'club', 'sport']),
    dict(id='high-five', name='High Five', mood='upbeat', genre='Funk', bpm=124, key=64, seed=104,
         chords=[(0, 'min7'), (5, 'dom7'), (0, 'min7'), (10, 'dom7')], bassline='x.xox.xo',
         layers={'pad': 0.35, 'bass': 0.7, 'arp': 0.3, 'drums': 0.85}, drums=[FUNK],
         tags=['groove', 'party', 'bass', 'retro', 'energy']),
    dict(id='still-water', name='Still Water', mood='calm', genre='Ambient', bpm=120, key=62, seed=105,
         chords=[(0, 'maj7'), (9, 'min7'), (5, 'maj7'), (7, 'sus2')],
         layers={'pad': 0.8, 'arp': 0.2}, tags=['relax', 'peaceful', 'meditation', 'soft', 'spa']),
    dict(id='morning-light', name='Morning Light', mood='calm', genre='Piano', bpm=120, key=65, seed=106,
         chords=[(0, 'maj'), (4, 'min'), (9, 'min'), (5, 'maj7')],
         layers={'pad': 0.4, 'bass': 0.3, 'arp': 0.55}, bassline='x.......',
         tags=['gentle', 'sunrise', 'soft', 'hope', 'keys']),
    dict(id='rising-storm', name='Rising Storm', mood='dramatic', genre='Cinematic', bpm=120, key=50, seed=107,
         chords=[(0, 'min'), (8, 'maj'), (10, 'maj'), (0, 'sus4')], bassline='x.x.x.xx',
         layers={'pad': 0.6, 'bass': 0.6, 'drums': 0.8}, drums=[TOMS],
         tags=['epic', 'tension', 'trailer', 'drums', 'dark']),
    dict(id='last-stand', name='Last Stand', mood='dramatic', genre='Epic', bpm=132, key=48, seed=108,
         chords=[(0, 'min'), (3, 'maj'), (10, 'maj'), (7, 'maj')], bassline='xxxxxxxx', arpDivision=4,
         layers={'pad': 0.55, 'bass': 0.6, 'arp': 0.3, 'drums': 0.9}, drums=[EPIC],
         tags=['battle', 'heroic', 'intense', 'trailer', 'power']),
    dict(id='lazy-sunday', name='Lazy Sunday', mood='chill', genre='Lo-fi', bpm=120, key=58, seed=109,
         chords=[(2, 'min7'), (7, 'dom7'), (0, 'maj7'), (9, 'min7')], bassline='x...x.x.',
         layers={'pad': 0.55, 'bass': 0.5, 'drums': 0.6}, drums=[LOFI],
         tags=['study', 'relaxed', 'jazzy', 'cafe', 'beats']),
    dict(id='night-drive', name='Night Drive', mood='chill', genre='Synthwave', bpm=124, key=54, seed=110,
         chords=[(0, 'min'), (8, 'maj'), (3, 'maj'), (10, 'maj')], arpDivision=4, bassline='xxxxxxxx',
         layers={'pad': 0.5, 'bass': 0.45, 'arp': 0.35, 'drums': 0.55}, drums=[CHILL],
         tags=['retro', 'neon', 'night', '80s', 'cruise']),
    dict(id='big-pitch', name='Big Pitch', mood='corporate', genre='Corporate', bpm=120, key=60, seed=111,
         chords=[(0, 'maj'), (9, 'min'), (5, 'maj'), (7, 'maj')], arpDivision=4,
         layers={'pad': 0.45, 'bass': 0.45, 'arp': 0.45, 'drums': 0.6}, drums=[CORP],
         tags=['business', 'presentation', 'success', 'tech', 'clean']),
    dict(id='forward-plan', name='Forward Plan', mood='corporate', genre='Inspiring', bpm=126, key=57, seed=112,
         chords=[(0, 'maj'), (7, 'maj'), (9, 'min'), (5, 'sus2')], arpDivision=4,
         layers={'pad': 0.5, 'bass': 0.5, 'arp': 0.4, 'drums': 0.55}, drums=[CORP, SOFT],
         tags=['motivation', 'growth', 'startup', 'uplifting', 'explainer']),
]


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    ios = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else None
    ASSETS.mkdir(parents=True, exist_ok=True)
    listed = []
    total = 0
    for track in TRACKS:
        assert track['mood'] in MOODS, track['id']
        samples = render(track)
        seconds = len(samples) / RATE
        assert 12.0 <= seconds <= 16.0, track['id']
        data = wav(samples, RATE)
        assert len(data) < 0.75 * 1024 * 1024, track['id']
        total += len(data)
        (ASSETS / (track['id'] + '.wav')).write_bytes(data)
        if ios:
            (ios / (track['id'] + '.wav')).write_bytes(data)
        listed.append({'id': track['id'], 'name': track['name'], 'mood': track['mood'], 'genre': track['genre'],
                       'bpm': track['bpm'], 'seconds': math.floor(seconds * 1000 + 0.5) / 1000, 'tags': track['tags']})
    text = '[\n' + ',\n'.join(json.dumps(e, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for e in listed) + '\n]\n'
    LIST.parent.mkdir(parents=True, exist_ok=True)
    LIST.write_text(text, encoding='utf-8')
    if ios:
        (ios / 'music.json').write_text(text, encoding='utf-8')
    print('%d loops, %d bytes of music' % (len(listed), total))


if __name__ == '__main__':
    main()
