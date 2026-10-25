// A clip brought in — from Add, the Gallery, the camera, Share to Canvia or
// Home's Import — made light enough to play smoothly and to travel between
// phones: one over maxEdge pixels on its long side, over maxBytes, or not
// H.264 picture with AAC sound (or none) in an MP4 or a MOV is converted in
// the background to H.264 at most maxEdge on its long side, at most maxFps
// frames a second, about videoBitRate bits a second, its sound AAC, in an
// MP4. The element shows its first frame at once and takes the light file
// under the same `video:<id>` when it is ready, its times the same, so
// trims and playback are as they were. Settings ▸ Optimise imported videos
// turns it off, and Keep original turns it off for one clip. The upload
// remembers it: {"optimised": true, "originalBytes": N}. The same rules on
// both phones (VideoImportTests, the Android twin's VideoImportTest); the
// converting is ClipOptimiser's.

import Foundation

enum VideoImport {

    static let maxEdge = 1920
    /// As many bytes as a design file carries of one clip.
    static let maxBytes = DesignPackage.maxPackedVideoBytes
    static let maxFps = 30
    static let videoBitRate = 8_000_000
    static let audioBitRate = 128_000

    /// The codecs a light clip is in, named as the Android twin names them
    /// (MIME types), whatever this phone's own names (`codec(fourCC:)`).
    static let h264 = "video/avc"
    static let aac = "audio/mp4a-latm"

    /// The containers a light clip may already be in.
    static let containers: Set<String> = ["mp4", "m4v", "mov"]

    /// What a clip is: its size in bytes, its picture's size and codec, its
    /// sound's codec (nil for none) and its file's extension.
    struct Probe: Equatable {
        var bytes: Int64
        var width: Int
        var height: Int
        var videoCodec: String?
        var audioCodec: String?
        var container: String
    }

    /// Whether `clip` is converted when it comes in: too big on its long
    /// side, too many bytes, or not H.264 (and AAC) in an MP4 or a MOV.
    static func needsOptimising(_ clip: Probe) -> Bool {
        max(clip.width, clip.height) > maxEdge
            || clip.bytes > Int64(maxBytes)
            || clip.videoCodec?.lowercased() != h264
            || (clip.audioCodec != nil && clip.audioCodec?.lowercased() != aac)
            || !containers.contains(clip.container.lowercased())
    }

    /// A track's codec as the rule names it: H.264 ("avc1", "avc3") and AAC
    /// ("mp4a", as a clip's sound is written) by their MIME types, HEVC
    /// ("hvc1", "hev1") as "video/hevc", anything else by its four letters.
    static func codec(fourCC: String) -> String {
        switch fourCC.trimmingCharacters(in: .whitespaces).lowercased() {
        case "avc1", "avc3": return h264
        case "hvc1", "hev1": return "video/hevc"
        case "mp4a", "aac": return aac
        case let other: return other
        }
    }

    /// The converted picture's size: `width` by `height` brought within
    /// maxEdge on its long side, its shape kept, each side even (as an
    /// encoder takes it) and at least 2.
    static func targetSize(width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (2, 2) }
        let scale = min(1, Double(maxEdge) / Double(max(width, height)))
        func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }

    /// The converted frame rate: the clip's own, whole, at most maxFps;
    /// maxFps when the clip does not say.
    static func targetFps(_ fps: Double?) -> Int {
        guard let fps, fps.isFinite, fps > 0 else { return maxFps }
        return min(max(Int(fps.rounded()), 1), maxFps)
    }

    /// The converted picture's bit rate: videoBitRate at 1920 by 1080, less
    /// for a smaller picture in proportion to its pixels, never under a
    /// million and a half.
    static func bitRate(width: Int, height: Int) -> Int {
        let scaled = Int64(videoBitRate) * Int64(width) * Int64(height) / (1920 * 1080)
        return Int(min(max(scaled, 1_500_000), Int64(videoBitRate)))
    }

    /// The upload's keys for a converted clip.
    static let optimisedKey = "optimised"
    static let originalBytesKey = "originalBytes"

    /// What Uploads says of a converted clip: "Optimised from 412 MB" —
    /// megabytes of a million bytes, whole, at least one.
    static func label(_ originalBytes: Int64) -> String {
        tr("Optimised from %d MB", max(1, Int((Double(originalBytes) / 1_000_000).rounded())))
    }

    /// A clip's packing allowance a minute: a minute of a converted clip,
    /// picture and sound at their target bit rates (60,960,000 bytes), so
    /// only a clip longer than the design file's whole allowance travels as
    /// a still.
    static let packedBytesPerMinute = Int64(videoBitRate + audioBitRate) / 8 * 60

    /// How many bytes a clip `seconds` long may be and still travel whole in
    /// a design file (DesignPackage.packedVideoIDs): maxPackedVideoBytes, or
    /// about packedBytesPerMinute for each minute of a longer clip.
    static func packedLimit(_ seconds: Double?) -> Int64 {
        let minutes = (seconds ?? 0).isFinite && (seconds ?? 0) > 0 ? (seconds ?? 0) / 60 : 0
        return max(Int64(DesignPackage.maxPackedVideoBytes), Int64((minutes * Double(packedBytesPerMinute)).rounded()))
    }
}
