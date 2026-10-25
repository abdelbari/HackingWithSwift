// An HDR clip's colours brought to an ordinary screen's (SDR), as the
// Android twin's HdrToneMap.kt tone maps the frames its codec cannot: a
// BT.2020 R'G'B' signal, HLG or PQ, to BT.709 R'G'B', each 0…1. In order:
// the signal to light — HLG's inverse OETF with the 1.2 system gamma of a
// 1000-nit display (`peakNits`) on each channel, as AVFoundation converts
// HLG, or PQ's EOTF, in nits — then the BT.2020
// to BT.709 matrix in that light, negatives cut to 0, then BT.2390's
// roll-off from `peakNits` down to SDR white (`whiteNits`), worked in PQ,
// then BT.709's gamma. Each channel on its own, the simplest rule both
// phones keep, held to the shared fixture hdr-tonemap.json (HdrClipsTests,
// the Android twin's HdrToneMapTest). This phone converts a clip's frames
// itself (ClipReader, ClipPlayer and ClipOptimiser ask AVFoundation for
// BT.709); this is the rule those frames are checked against.

import Foundation

enum HdrToneMap {

    /// The transfers a clip can be tone mapped from, as the upload records
    /// them (`toneMapped`).
    static let hlg = "hlg"
    static let pq = "pq"

    /// The brightest an HDR clip is taken to be, and SDR's white, in nits.
    static let peakNits = 1000.0
    static let whiteNits = 203.0

    /// BT.2020 to BT.709, in linear light.
    static let matrix: [[Double]] = [
        [1.6605, -0.5876, -0.0728],
        [-0.1246, 1.1329, -0.0083],
        [-0.0182, -0.1006, 1.1187],
    ]

    // PQ (SMPTE ST 2084).
    private static let m1 = 2610.0 / 16384
    private static let m2 = 2523.0 / 4096 * 128
    private static let c1 = 3424.0 / 4096
    private static let c2 = 2413.0 / 4096 * 32
    private static let c3 = 2392.0 / 4096 * 32

    // HLG (BT.2100).
    private static let a = 0.17883277
    private static let b = 1 - 4 * a
    private static let c = 0.5 - a * log(4 * a)

    /// Nits for a PQ signal 0…1.
    static func pqToNits(_ e: Double) -> Double {
        let p = pow(min(max(e, 0), 1), 1 / m2)
        return 10000 * pow(max(p - c1, 0) / (c2 - c3 * p), 1 / m1)
    }

    /// A PQ signal 0…1 for `nits`.
    static func nitsToPq(_ nits: Double) -> Double {
        let p = pow(min(max(nits / 10000, 0), 1), m1)
        return pow((c1 + c2 * p) / (1 + c3 * p), m2)
    }

    /// Scene light 0…1 for an HLG signal 0…1 (the inverse OETF).
    static func hlgToScene(_ e: Double) -> Double {
        let v = min(max(e, 0), 1)
        return v <= 0.5 ? v * v / 3 : (exp((v - c) / a) + b) / 12
    }

    /// `nits` rolled off as BT.2390's EETF does, from `peakNits` to
    /// `whiteNits`, black left where it is: a straight line to its knee,
    /// a Hermite curve above it, worked in PQ.
    static func rolledOff(_ nits: Double) -> Double {
        let source = nitsToPq(peakNits)
        let e1 = min(nitsToPq(nits) / source, 1)
        let top = nitsToPq(whiteNits) / source
        let knee = 1.5 * top - 0.5
        guard e1 >= knee else { return pqToNits(e1 * source) }
        let t = (e1 - knee) / (1 - knee)
        let t2 = t * t, t3 = t2 * t
        let e2 = (2 * t3 - 3 * t2 + 1) * knee + (t3 - 2 * t2 + t) * (1 - knee) + (-2 * t3 + 3 * t2) * top
        return pqToNits(e2 * source)
    }

    /// BT.709's gamma for light 0…1.
    static func bt709(_ l: Double) -> Double {
        let v = min(max(l, 0), 1)
        return v < 0.018 ? 4.5 * v : 1.099 * pow(v, 0.45) - 0.099
    }

    /// HLG's system gamma (BT.2100's OOTF) on a 1000-nit display.
    static let hlgGamma = 1.2

    /// A signal's light in nits, by `transfer`: HLG's scene light through
    /// the system gamma, channel by channel.
    static func nits(_ signal: Double, transfer: String) -> Double {
        transfer == pq ? pqToNits(signal) : peakNits * pow(hlgToScene(signal), hlgGamma)
    }

    /// `rgb`, a BT.2020 signal in `transfer` ("hlg" or "pq"; anything else
    /// is taken as HLG), as BT.709 R'G'B'.
    static func toneMap(_ rgb: [Double], transfer: String) -> [Double] {
        guard rgb.count == 3 else { return rgb }
        let light = rgb.map { nits($0, transfer: transfer) }
        return matrix.map { row in
            let mixed = max(0, row[0] * light[0] + row[1] * light[1] + row[2] * light[2])
            return bt709(rolledOff(mixed) / whiteNits)
        }
    }

    /// The 10-bit video-range sample `y`, `cb`, `cr`, read with BT.2020's
    /// non-constant-luminance matrix, as SDR red, green and blue 0…255 —
    /// the fixture's pixels, the Android twin's rgb.
    static func rgb(y: Int, cb: Int, cr: Int, transfer: String) -> [Int] {
        let kr = 0.2627, kb = 0.0593
        let l = Double(y - 64) / 876, u = Double(cb - 512) / 896, v = Double(cr - 512) / 896
        let r = l + 2 * (1 - kr) * v
        let b = l + 2 * (1 - kb) * u
        let g = (l - kr * r - kb * b) / (1 - kr - kb)
        return toneMap([r, g, b], transfer: transfer).map { min(255, max(0, Int((255 * $0 + 0.5).rounded(.down)))) }
    }
}
