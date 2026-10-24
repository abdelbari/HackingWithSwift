// The generated motion loops and still textures of Motion.json (MotionArt),
// as Add's Videos and Photos tabs list them and a page shows them. A loop
// on a page is a picture whose source is "motion:<id>", stamped with the
// moment while its page plays ("motion:<id>@1.25") as a clip's is; a frame
// is drawn at `frameSize` the first time it is asked for and kept while
// there is room. At rest, and in every still export, a loop shows its first
// frame.

import UIKit

enum MotionLibrary {

    static let prefix = "motion:"

    /// How many different frames a second a loop shows as it plays: each
    /// moment is taken to the frame it falls in.
    static let framesPerSecond = 24.0

    /// The size a loop's frame is drawn at, 4:3 as the drawn pictures are;
    /// it fills its frame on the page as a photo does.
    static let frameSize = (width: 400, height: 300)

    /// The size a still is drawn at.
    static let stillSize = (width: 800, height: 600)

    private struct Pack: Decodable {
        var loops: [MotionDef]
        var stills: [MotionDef]
    }

    /// Read once, on first use.
    private static let file: Pack = {
        guard let url = Bundle.main.url(forResource: "Motion", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Pack.self, from: data) else {
            assertionFailure("Motion.json missing or invalid")
            return Pack(loops: [], stills: [])
        }
        return decoded
    }()

    /// The motion loops, in the generator's order.
    static var loops: [MotionDef] { file.loops }

    /// The still textures, in the generator's order.
    static var stills: [MotionDef] { file.stills }

    private static let byId: [String: MotionDef] = Dictionary(
        (file.loops + file.stills).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func def(_ id: String?) -> MotionDef? { id.flatMap { byId[$0] } }

    // MARK: sources

    static func isMotion(_ src: String?) -> Bool { src?.hasPrefix(prefix) == true }

    /// "motion:<id>@<seconds>" → the id and the moment; no "@" is at rest.
    static func split(_ src: String) -> (id: String, time: Double?)? {
        guard src.hasPrefix(prefix) else { return nil }
        let body = src.dropFirst(prefix.count)
        if let at = body.lastIndex(of: "@") {
            return (String(body[..<at]), Double(body[body.index(after: at)...]))
        }
        return (String(body), nil)
    }

    static func src(_ id: String, at time: Double?) -> String {
        guard let time else { return prefix + id }
        return prefix + id + "@" + String(format: "%.3f", time)
    }

    /// The source showing loop `src` `time` seconds into its page: the
    /// start of the frame that moment falls in, within one loop, so a loop
    /// played twice shows — and keeps — the same frames. Any other source,
    /// or one stamped already, is as it is.
    static func playing(_ src: String?, at time: Double) -> String? {
        guard let src, let parts = split(src), parts.time == nil else { return src }
        return Self.src(parts.id, at: frameTime(time, period: def(parts.id)?.period ?? 0))
    }

    /// `time` taken round its loop of `period` seconds and down to the
    /// start of its frame.
    static func frameTime(_ time: Double, period: Double) -> Double {
        guard period > 0, time.isFinite else { return 0 }
        let within = time - (time / period).rounded(.down) * period
        let frames = (period * framesPerSecond).rounded(.down)
        let index = min((within * framesPerSecond).rounded(.down), max(frames - 1, 0))
        return index / framesPerSecond
    }

    /// Whether the page's background is a loop, which plays as the page
    /// does.
    static func isBackground(_ page: Page) -> Bool {
        if case .image(let src) = page.background { return isMotion(src) }
        return false
    }

    /// The source a loop shows at rest, its moment taken off.
    static func atRest(_ src: String) -> String {
        guard let parts = split(src) else { return src }
        return Self.src(parts.id, at: nil)
    }

    // MARK: frames

    // An NSCache, as the drawn pictures are kept: a frame is half a
    // megabyte, and the system lets them go under pressure.
    private static let frames: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 96 * 1024 * 1024
        return c
    }()

    /// The frame source `src` shows — its first at rest — drawn the first
    /// time and kept; nil for a loop this build does not have.
    static func resolve(_ src: String) -> UIImage? {
        guard let parts = split(src), let loop = def(parts.id) else { return nil }
        let t = frameTime(parts.time ?? 0, period: loop.period)
        return frame(loop, t: t, width: frameSize.width, height: frameSize.height)
    }

    /// `def`'s frame at `t`, `width` × `height`, kept.
    static func frame(_ def: MotionDef, t: Double, width: Int, height: Int) -> UIImage? {
        let key = "\(def.id)@\(String(format: "%.3f", t))#\(width)x\(height)" as NSString
        if let kept = frames.object(forKey: key) { return kept }
        guard let image = MotionArt.image(def, t: t, width: width, height: height) else { return nil }
        frames.setObject(image, forKey: key, cost: width * height * 4)
        return image
    }

    // MARK: finding

    /// The loops whose name, category or one of whose tags has `query` in
    /// it, case aside; every loop for a blank one.
    static func search(_ query: String) -> [MotionDef] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return loops }
        return loops.filter { loop in
            loop.name.lowercased().contains(needle) || loop.category.lowercased().contains(needle)
                || loop.tags.contains { $0.contains(needle) }
        }
    }
}
