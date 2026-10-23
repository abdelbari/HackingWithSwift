// Where the beats fall in a song, and Beat Sync, which sets the pages'
// holds so each cut falls on one — the Android twin's Beats and BeatSync,
// with the same arithmetic step for step, so a song gives the same beats on
// both phones (BeatsTests and its BeatsTest read the same fixture WAVs,
// written by tools/generate_sounds.py).
//
// `detect` reads the song as mono samples at `rate` (the app decodes it at
// 22050 a second), in frames of `frame` samples every `hop`:
// 1. Each frame is windowed (Hann, 0.5 − 0.5·cos(2πk/frame)) and its
//    magnitude spectrum taken, bins 0…frame/2. Its onset strength is the
//    spectral flux — the sum over the bins of how much each grew since the
//    frame before, rises only; the first frame's is 0. The mean of them all
//    is taken off, and what falls below 0 is 0.
// 2. The tempo is the lag, in frames, between minBPM and maxBPM
//    (⌈60·r/maxBPM⌉ to ⌊60·r/minBPM⌋, r = rate/hop frames a second) whose
//    autocorrelation of the onsets, smoothed for it — s[i] = o[i−1] +
//    2·o[i] + o[i+1], 0 past either end; Σ s[i]·s[i−lag] — is highest once
//    weighted towards 120 bpm, exp(−½·log2(bpm/120)²), the first such lag on
//    a tie.
// 3. The beats are picked on that grid: the first is the strongest onset of
//    the first lag's frames; each next one the strongest within a quarter of
//    a lag (lag / 4 frames, whole) either side of one lag on from the last,
//    the first on a tie — the grid point itself where nothing stirs — until
//    the grid runs past the song.
// A beat is at its frame's middle, (i·hop + frame/2)/rate seconds, to the
// thousandth. Silence, or a song too short for two of the slowest beats,
// has none.

import Foundation

enum Beats {

    static let rate = 22050
    static let frame = 1024
    static let hop = 512
    static let minBPM = 60.0
    static let maxBPM = 180.0

    /// The most of a song read for its beats, in seconds: a long one's first
    /// five minutes, which is plenty to sync a design to.
    static let maxSeconds = 300.0

    static func detect(_ samples: [Float], rate: Int = Beats.rate) -> [Double] {
        guard rate > 0, samples.count >= frame else { return [] }
        let frames = (samples.count - frame) / hop + 1
        let onsets = onsetStrengths(samples, frames: frames)
        let perSecond = Double(rate) / Double(hop)
        let minLag = max(1, Int((60 * perSecond / maxBPM).rounded(.up)))
        let maxLag = Int((60 * perSecond / minBPM).rounded(.down))
        guard maxLag >= minLag, frames >= maxLag * 2, onsets.contains(where: { $0 > 0 }) else { return [] }
        // Smoothed for the tempo alone, so a beat a fraction of a frame off
        // the lag still lines up with the next.
        let smooth: [Double] = (0..<frames).map { i in
            let before = i > 0 ? onsets[i - 1] : 0
            let after = i + 1 < frames ? onsets[i + 1] : 0
            return 2 * onsets[i] + before + after
        }
        var lag = 0
        var best = 0.0
        for l in minLag...maxLag {
            var sum = 0.0
            for i in l..<frames { sum += smooth[i] * smooth[i - l] }
            let octaves = log(60 * perSecond / Double(l) / 120.0) / log(2.0)
            let score = sum * exp(-0.5 * octaves * octaves)
            if score > best {
                best = score
                lag = l
            }
        }
        guard lag > 0 else { return [] }
        let reach = lag / 4
        var at = strongest(onsets, from: 0, to: lag - 1)
        var picked: [Int] = []
        while at < frames {
            picked.append(at)
            let expect = at + lag
            if expect >= frames { break }
            let found = strongest(onsets, from: expect - reach, to: expect + reach)
            at = onsets[found] > 0 ? found : expect
        }
        return picked.map { thousandth(Double($0 * hop + frame / 2) / Double(rate)) }
    }

    /// The first frame with the strongest onset in `from`…`to`, kept within
    /// the song.
    private static func strongest(_ onsets: [Double], from: Int, to: Int) -> Int {
        let last = onsets.count - 1
        let a = min(max(from, 0), last)
        let b = min(max(to, 0), last)
        var best = a
        if b > a {
            for i in a...b where onsets[i] > onsets[best] { best = i }
        }
        return best
    }

    private static func onsetStrengths(_ samples: [Float], frames: Int) -> [Double] {
        let window: [Double] = (0..<frame).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(frame)) }
        let bins = frame / 2 + 1
        var previous = [Double](repeating: 0, count: bins)
        var flux = [Double](repeating: 0, count: frames)
        var re = [Double](repeating: 0, count: frame)
        var im = [Double](repeating: 0, count: frame)
        for f in 0..<frames {
            let start = f * hop
            for k in 0..<frame {
                re[k] = Double(samples[start + k]) * window[k]
                im[k] = 0
            }
            fft(&re, &im)
            var magnitude = [Double](repeating: 0, count: bins)
            for k in 0..<bins { magnitude[k] = (re[k] * re[k] + im[k] * im[k]).squareRoot() }
            if f > 0 {
                var sum = 0.0
                for k in 0..<bins { sum += max(0, magnitude[k] - previous[k]) }
                flux[f] = sum
            }
            previous = magnitude
        }
        let mean = flux.reduce(0, +) / Double(max(frames, 1))
        return flux.map { max(0, $0 - mean) }
    }

    /// An in-place radix-2 FFT: bit-reversed order, then butterflies, the
    /// twiddles cos and −sin of 2π·k/size.
    private static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }
        var size = 2
        while size <= n {
            let half = size / 2
            let step = 2 * Double.pi / Double(size)
            for s in stride(from: 0, to: n, by: size) {
                for k in 0..<half {
                    let wr = cos(step * Double(k))
                    let wi = -sin(step * Double(k))
                    let a = s + k
                    let b = a + half
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                }
            }
            size *= 2
        }
    }

    static func thousandth(_ v: Double) -> Double { (v * 1000 + 0.5).rounded(.down) / 1000 }

    // MARK: the cache

    /// Beats as the cache keeps them, "<id>.beats" beside the song's peaks:
    /// the seconds to the thousandth, comma-separated ("0.255,0.755").
    static func encode(_ beats: [Double]) -> String {
        beats.map { formatted(thousandth($0)) }.joined(separator: ",")
    }

    /// Beats the cache kept, or nil when the file is not a list of numbers;
    /// an empty file is a song with no beats.
    static func decode(_ text: String) -> [Double]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var out: [Double] = []
        for part in trimmed.split(separator: ",", omittingEmptySubsequences: false) {
            guard let v = Double(part.trimmingCharacters(in: .whitespaces)), v.isFinite else { return nil }
            out.append(v)
        }
        return out
    }

    /// A number as the cache writes it: to three places, trailing zeros and
    /// a trailing point dropped ("2", "0.5", "1.255").
    private static func formatted(_ v: Double) -> String {
        var text = String(format: "%.3f", v)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    // MARK: in the film

    /// A track's beats where they fall in the film: each beat of its song
    /// from its trim's start up to its trim's end (`length` seconds of the
    /// file, when known), moved to start where the track does — beat −
    /// trimStart + start — and, for a track that loops, again each time it
    /// comes round, up to `film` seconds.
    static func inFilm(_ beats: [Double], track: AudioTrack, length: Double?, film: Double) -> [Double] {
        let end = track.trimEnd ?? length ?? Double.greatestFiniteMagnitude
        let once = beats.filter { $0 >= track.trimStart - 1e-9 && $0 < end }.map { $0 - track.trimStart }
        let span = end - track.trimStart
        var out: [Double] = []
        var round = 0
        while true {
            let offset = track.start + Double(round) * span
            if round > 0 && (!track.loop || span <= 0.01 || span >= Double.greatestFiniteMagnitude / 2 || offset >= film) {
                break
            }
            for b in once where offset + b <= film + 1e-9 { out.append(thousandth(offset + b)) }
            if !track.loop { break }
            round += 1
        }
        return out
    }

    /// `t` moved to the nearest of `beats` within `tolerance` seconds — the
    /// earlier on a tie — or left as it is with none that near.
    static func snapped(_ t: Double, beats: [Double], tolerance: Double = BeatSync.snapSeconds) -> Double {
        var best: Double?
        for b in beats {
            let d = abs(b - t)
            guard d <= tolerance + 1e-9 else { continue }
            if let current = best, d >= abs(current - t) - 1e-12 { continue }
            best = b
        }
        return best ?? t
    }
}

/// Beat Sync: the pages' holds set so each cut falls on a beat of a music
/// track — the Android twin's BeatSync, rule for rule.
///
/// Turned on (`on`), as one step: going through the pages the film shows,
/// in order, each page's end — where it started plus its hold — moves to the
/// nearest beat at least `minHold` after its start, the earlier on a tie;
/// its hold is then from its start to that beat, to the thousandth. A page
/// with no such beat within the longest hold (MotionSettings.pageHoldRange)
/// keeps its hold. The holds as they were are kept in the design's
/// `beatSyncRestore` — page id to its own hold, nil for one that followed
/// the design's — written only the first time, so turning it on for a second
/// track still keeps the first holds. The track says it is on in its own
/// `beatSync`.
///
/// Turned off (`off`), the kept holds come back, page by page, and the key
/// goes. While it is on, a page's end dragged on the timeline snaps to a
/// beat within `snapSeconds` (Beats.snapped).
enum BeatSync {

    /// The shortest hold Beat Sync gives a page.
    static let minHold = 0.5

    /// How near a beat a dragged end must come to snap to it.
    static let snapSeconds = 0.15

    /// The longest hold a page can have.
    static var maxHold: Double { MotionSettings.pageHoldRange.upperBound }

    /// Whether `design` has a track with Beat Sync on.
    static func active(_ design: Design) -> Bool {
        design.audioTracks.contains { $0.beatSync }
    }

    /// The holds Beat Sync gives pages holding `holds`, in film order, for
    /// `beats` seconds into the film.
    static func holds(_ holds: [Double], beats: [Double]) -> [Double] {
        let sorted = beats.sorted()
        var start = 0.0
        return holds.map { hold in
            let target = start + hold
            var best: Double?
            for b in sorted {
                let length = b - start
                if length < minHold - 1e-9 || length > maxHold + 1e-9 { continue }
                if let current = best, abs(b - target) >= abs(current - target) - 1e-12 { continue }
                best = b
            }
            let next = best.map { Beats.thousandth($0 - start) } ?? hold
            start += next
            return next
        }
    }

    /// `design` with its shown pages' holds on `beats`, the holds as they
    /// were kept to come back to.
    static func on(_ design: Design, beats: [Double]) -> Design {
        let shown = Timeline.pages(of: design)
        let synced = holds(shown.map { $0.hold }, beats: beats)
        var out = design
        if out.beatSyncRestore == nil {
            var kept: [String: Double?] = [:]
            for page in shown { kept[design.pages[page.index].id] = .some(design.pages[page.index].holdSeconds) }
            out.beatSyncRestore = kept
        }
        for (n, page) in shown.enumerated() { out.pages[page.index].holdSeconds = synced[n] }
        return out
    }

    /// `design` with the holds kept by `on` back, and the key gone; as it is
    /// when none were kept.
    static func off(_ design: Design) -> Design {
        guard let kept = design.beatSyncRestore else { return design }
        var out = design
        for i in out.pages.indices {
            guard let hold = kept[out.pages[i].id] else { continue }
            out.pages[i].holdSeconds = hold
        }
        out.beatSyncRestore = nil
        return out
    }
}
