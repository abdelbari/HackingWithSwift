// Enhance voice: a recording or a clip's sound cleaned of its background
// noise and levelled, on the phone — the Android twin's VoiceEnhance, with
// the same arithmetic step for step, so the same samples come out the same
// on both phones (VoiceEnhanceTests and its VoiceEnhanceTest).
//
// `enhanced` takes mono samples at `rate` through four stages:
// 1. A second-order high-pass at 80 Hz (the cookbook biquad, Q = 1/√2,
//    direct form I from silence), which takes out hum and rumble.
// 2. A spectral gate: frames of 1024 samples every 256, Hann-windowed
//    (0.5 − 0.5·cos(2πk/1024)), the sound first padded with 768 zeros in
//    front and zeros behind so every sample is under four frames. Each
//    frame's energy is the sum of its bins' squared magnitudes, bins
//    0…512; the noise floor is each bin's mean magnitude over the quietest
//    10% of the frames (at least one; the earlier frame first on a tie). A
//    bin no louder than twice its floor (6 dB) is turned down by 12 dB;
//    the rest are kept. The frames are added back where they came from and
//    halved — four Hann windows a quarter apart sum to 2.
// 3. A 3:1 compressor over −18 dBFS: a level that follows each sample's
//    size, rising over 5 ms and falling over 50 ms (one-pole), and above
//    the threshold the sound is turned down so the level over it is a
//    third of what it was.
// 4. Normalised to −16 LUFS, taken as an RMS of −16 dBFS: the whole sound
//    scaled so its root mean square is 10^(−16/20), each sample then kept
//    within −1…1. Silence (an RMS under 10^(−100/20)) is left as it is.
//
// It runs once per source and is kept as a WAV beside the peaks
// (AudioStore.enhancedURL), which Play, Present and the video's mix play
// in place of the source's own sound.

import Foundation

enum VoiceEnhance {

    /// The rate a source is read and kept at for its enhanced sound.
    static let rate = 44100
    /// The longest sound enhanced, in seconds; a longer one plays as it is.
    static let maxSeconds = 20.0 * 60

    static let highPassHz = 80.0
    static let frame = 1024
    static let hop = 256
    /// The share of the frames, quietest first, the noise floor is read from.
    static let quietShare = 0.1
    /// How far above its floor a bin must be to be kept as it is: 6 dB.
    static let gateOver = 2.0
    static let reductionDb = 12.0
    static let thresholdDb = -18.0
    static let ratio = 3.0
    static let attackSeconds = 0.005
    static let releaseSeconds = 0.05
    static let targetDb = -16.0

    /// `samples` at `rate`, through the high-pass, the gate, the compressor
    /// and the normalising, in that order.
    static func enhanced(_ samples: [Float], rate: Int) -> [Float] {
        guard !samples.isEmpty, rate > 0 else { return samples }
        return normalised(compressed(gated(highPassed(samples, rate: rate)), rate: rate))
    }

    // MARK: 1. the high-pass

    static func highPassed(_ samples: [Float], rate: Int, cutoff: Double = highPassHz) -> [Float] {
        let w0 = 2 * Double.pi * cutoff / Double(rate)
        let alpha = sin(w0) / (2 * (1 / 2.0.squareRoot()))
        let c = cos(w0)
        let a0 = 1 + alpha
        let b0 = (1 + c) / 2 / a0, b1 = -(1 + c) / a0, b2 = (1 + c) / 2 / a0
        let a1 = -2 * c / a0, a2 = (1 - alpha) / a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var out = [Float](repeating: 0, count: samples.count)
        for i in samples.indices {
            let x = Double(samples[i])
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            out[i] = Float(y)
        }
        return out
    }

    // MARK: 2. the spectral gate

    static func gated(_ samples: [Float]) -> [Float] {
        let n = samples.count
        guard n > 0 else { return samples }
        let lead = frame - hop
        let frames = (n - 1 + lead) / hop + 1
        var padded = [Float](repeating: 0, count: (frames - 1) * hop + frame)
        for i in 0..<n { padded[lead + i] = samples[i] }
        let window: [Double] = (0..<frame).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(frame)) }
        let bins = frame / 2 + 1
        var re = [Double](repeating: 0, count: frame)
        var im = [Double](repeating: 0, count: frame)
        // Frame `f` windowed and transformed into re and im.
        func transform(_ f: Int) {
            let start = f * hop
            for k in 0..<frame {
                re[k] = Double(padded[start + k]) * window[k]
                im[k] = 0
            }
            fft(&re, &im)
        }
        // Each frame read twice more rather than kept: a long song's
        // spectra would not fit in memory.
        var energy = [Double](repeating: 0, count: frames)
        for f in 0..<frames {
            transform(f)
            var e = 0.0
            for k in 0..<bins { e += re[k] * re[k] + im[k] * im[k] }
            energy[f] = e
        }
        let quiet = quietest(energy)
        var floor = [Double](repeating: 0, count: bins)
        for f in quiet {
            transform(f)
            for k in 0..<bins { floor[k] += (re[k] * re[k] + im[k] * im[k]).squareRoot() }
        }
        for k in 0..<bins { floor[k] /= Double(quiet.count) }
        let cut = pow(10, -reductionDb / 20)
        var sum = [Float](repeating: 0, count: padded.count)
        for f in 0..<frames {
            transform(f)
            for k in 0..<bins where (re[k] * re[k] + im[k] * im[k]).squareRoot() <= floor[k] * gateOver {
                re[k] *= cut
                im[k] *= cut
                if k > 0 && k < frame / 2 {
                    re[frame - k] *= cut
                    im[frame - k] *= cut
                }
            }
            inverse(&re, &im)
            let start = f * hop
            for k in 0..<frame { sum[start + k] += Float(re[k]) }
        }
        return (0..<n).map { sum[lead + $0] / 2 }
    }

    /// The frames the noise floor is read from: the quietest `quietShare`
    /// of them, at least one, the earlier first on a tie.
    static func quietest(_ energy: [Double]) -> [Int] {
        let count = max(1, Int(Double(energy.count) * quietShare))
        let order = energy.indices.sorted { energy[$0] != energy[$1] ? energy[$0] < energy[$1] : $0 < $1 }
        return Array(order.prefix(count))
    }

    /// The inverse of `fft`: conjugated, transformed, conjugated and scaled
    /// by 1/size, in place.
    private static func inverse(_ re: inout [Double], _ im: inout [Double]) {
        for k in im.indices { im[k] = -im[k] }
        fft(&re, &im)
        let scale = 1 / Double(re.count)
        for k in re.indices {
            re[k] *= scale
            im[k] = -im[k] * scale
        }
    }

    /// An in-place radix-2 FFT: bit-reversed order, then butterflies, the
    /// twiddles cos and −sin of 2π·k/size — Beats' own.
    static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        guard n > 1 else { return }
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

    // MARK: 3. the compressor

    static func compressed(_ samples: [Float], rate: Int) -> [Float] {
        let attack = exp(-1 / (attackSeconds * Double(rate)))
        let release = exp(-1 / (releaseSeconds * Double(rate)))
        var level = 0.0
        var out = samples
        for i in samples.indices {
            let size = abs(Double(samples[i]))
            let coefficient = size > level ? attack : release
            level = coefficient * level + (1 - coefficient) * size
            guard level > 0 else { continue }
            let db = 20 * log10(level)
            guard db > thresholdDb else { continue }
            let wanted = thresholdDb + (db - thresholdDb) / ratio
            out[i] = Float(Double(samples[i]) * pow(10, (wanted - db) / 20))
        }
        return out
    }

    // MARK: 4. the level

    /// The root mean square of `samples`; 0 for none.
    static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for s in samples { sum += Double(s) * Double(s) }
        return (sum / Double(samples.count)).squareRoot()
    }

    static func normalised(_ samples: [Float]) -> [Float] {
        let level = rms(samples)
        guard level >= pow(10, -100.0 / 20) else { return samples }
        let scale = pow(10, targetDb / 20) / level
        return samples.map { Float(min(1, max(-1, Double($0) * scale))) }
    }

    // MARK: the kept file

    /// `samples` as a WAV file: 16-bit mono PCM at `rate`, each sample
    /// kept within −1…1 and rounded to the nearest of 32767 steps.
    static func wav(_ samples: [Float], rate: Int) -> Data {
        var data = Data()
        func word(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func half(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        word(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        word(16)
        half(1)
        half(1)
        word(UInt32(rate))
        word(UInt32(rate * 2))
        half(2)
        half(16)
        data.append(contentsOf: Array("data".utf8))
        word(bytes)
        data.reserveCapacity(data.count + samples.count * 2)
        for s in samples {
            let v = Int16((Double(min(1, max(-1, s))) * 32767).rounded())
            half(UInt16(bitPattern: v))
        }
        return data
    }
}
