// Animated pictures — an animated GIF or WebP brought in as a photo — as
// elements, the way VideoStore has clips: the original file lives in
// Documents/anim by id, and the element that shows it is an ordinary photo
// element whose source is "anim:<id>". At rest that is the picture's first
// frame, so crop, frames, filters, transparency and every still export work
// unchanged; while the page plays — Play in the editor, Present, and the
// video and GIF exports — the source is stamped with the page's moment,
// "anim:<id>@1.25", and shows the frame that moment falls on, looping for as
// long as the page is up.
//
// Both phones time frames the same way (`frame(at:delays:)`): each frame
// shown for its own delay, any delay under `minDelay` taken as `minDelay`,
// looping for ever whatever loop count the file asks for — the Android
// twin's AnimatedImages, with the same rows of tests. The delays and frames
// come from ImageIO (CGImageSource), which composes each GIF or WebP frame
// over the last as the file says.
//
// A frame decodes in a few milliseconds and is kept once decoded, so the
// picture is drawn there and then wherever it is asked for, live or not.

import Foundation
import ImageIO
import UIKit

enum AnimStore {

    static let prefix = "anim:"

    /// The shortest a frame is shown, in milliseconds: a file asking for
    /// less (many ask for none) is shown for this long.
    static let minDelay = 20

    /// The largest animated picture a design file carries, in bytes; a
    /// larger one travels as its first frame, a still.
    static let maxPackedBytes = 10 * 1024 * 1024

    /// The most a design file carries of animated pictures in all: past it
    /// the rest travel as stills too.
    static let maxPackedTotalBytes = 50 * 1024 * 1024

    /// The file types kept animated: what both phones decode frame by frame.
    static let packableTypes: Set<String> = ["gif", "webp"]

    /// The largest file taken in: an animation past this is a film, and
    /// comes in as its first frame, a photo, as on the Android twin.
    static let maxBytes = 50 * 1024 * 1024

    /// The setting, of this phone, that plays animated pictures on the
    /// editor's canvas as well — "Play in the editor" — rather than showing
    /// their first frame; off until turned on. The Android twin keeps the
    /// same name.
    static let playKey = "playAnimated"

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("anim", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func isAnim(_ src: String?) -> Bool { src?.hasPrefix(prefix) == true }

    /// "anim:<id>@<seconds>" → the id and the moment; no "@" is at rest.
    static func split(_ src: String) -> (id: String, time: Double?)? {
        guard src.hasPrefix(prefix) else { return nil }
        let body = src.dropFirst(prefix.count)
        if let at = body.lastIndex(of: "@") {
            return (String(body[..<at]), Double(body[body.index(after: at)...]))
        }
        return (String(body), nil)
    }

    /// The source showing picture `id` at `time` seconds into its page, or
    /// its first frame for nil — to a hundredth of a second, as a clip's.
    static func src(_ id: String, at time: Double?) -> String {
        guard let time else { return prefix + id }
        return prefix + id + "@" + String(format: "%.2f", time)
    }

    /// `src` stamped with `time` seconds into the page when it is an
    /// animated picture at rest; anything else as it is.
    static func playing(_ src: String?, at time: Double) -> String? {
        guard let src, let parts = split(src), parts.time == nil else { return src }
        return Self.src(parts.id, at: time)
    }

    // MARK: timing

    /// A frame's delay as it is shown: `raw` milliseconds, or `minDelay` for
    /// anything less.
    static func delay(_ raw: Int) -> Int { max(raw, minDelay) }

    /// How long one pass of frames `delays` (as the file has them, in
    /// milliseconds) takes as shown.
    static func duration(_ delays: [Int]) -> Int {
        delays.reduce(0) { $0 + delay($1) }
    }

    /// The frame shown `time` seconds into the page, for frames whose delays
    /// the file gives as `delays` milliseconds: the moment taken to the
    /// nearest millisecond, looped over one pass (`duration`), and the frame
    /// whose turn — from the sum of the delays before it, up to but not
    /// including the sum with its own — holds it. Before the page starts is
    /// its start; one frame, or none, is frame 0, and so is a moment that is
    /// no number or endless — a design file's "anim:<id>@NaN" — as on the
    /// Android twin.
    static func frame(at time: Double, delays: [Int]) -> Int {
        guard delays.count > 1 else { return 0 }
        let total = duration(delays)
        let whole = (time * 1000).rounded()
        guard whole.isFinite, whole > 0 else { return 0 }
        let ms = Int(whole.truncatingRemainder(dividingBy: Double(total)))
        var start = 0
        for (i, raw) in delays.enumerated() {
            start += delay(raw)
            if ms < start { return i }
        }
        return delays.count - 1
    }

    /// Where frame `index` starts, in seconds into one pass.
    static func start(of index: Int, delays: [Int]) -> Double {
        Double(delays.prefix(max(0, index)).reduce(0) { $0 + delay($1) }) / 1000
    }

    // MARK: designs

    /// Every animated picture a design shows: on a photo, filling a shape,
    /// or behind a page — each of which a design file has to carry, animated
    /// or as a still, as the Android twin counts them.
    static func ids(in design: Design) -> Set<String> {
        var ids = Set<String>()
        for page in design.pages {
            if case .image(let src) = page.background, let parts = split(src) { ids.insert(parts.id) }
            for el in page.elements {
                for src in [el.src, el.fill?.src] {
                    if let src, let parts = split(src) { ids.insert(parts.id) }
                }
            }
        }
        return ids
    }

    /// Of the pictures listed — each one's size in bytes and file type, by
    /// id — the ones a design file carries animated: in id order, each no
    /// larger than `maxPackedBytes` and of a packable type, while the total
    /// stays within `maxPackedTotalBytes`. The Android twin chooses by the
    /// same rule, as for clips; the rest travel as their first frame.
    static func packedIDs(_ files: [String: (bytes: Int, ext: String)]) -> Set<String> {
        var packed = Set<String>()
        var total = 0
        for id in files.keys.sorted() {
            guard let file = files[id] else { continue }
            guard file.bytes <= maxPackedBytes, packableTypes.contains(file.ext.lowercased()) else { continue }
            guard total + file.bytes <= maxPackedTotalBytes else { continue }
            total += file.bytes
            packed.insert(id)
        }
        return packed
    }

    /// The photo id a design file shows picture `id`'s first frame by, when
    /// it carries the frame instead of the animation: "still-<id>", as the
    /// Android twin names it.
    static func stillID(_ id: String) -> String { "still-\(id)" }

    /// The file type of an animated picture by its first bytes — "gif" or
    /// "webp" — or nil for anything else.
    static func type(of data: Data) -> String? {
        let head = [UInt8](data.prefix(12))
        if head.count >= 6, head[0...3] == [0x47, 0x49, 0x46, 0x38] { return "gif" }
        if head.count >= 12, head[0...3] == [0x52, 0x49, 0x46, 0x46], head[8...11] == [0x57, 0x45, 0x42, 0x50] {
            return "webp"
        }
        return nil
    }

    // MARK: files

    /// The picture in `data` kept under a fresh id, when it is an animated
    /// GIF or WebP of two frames or more, no larger than `maxBytes`, whose
    /// first frame decodes; nil for anything else — a still GIF, a plain
    /// photo — which is then brought in as a photo.
    static func store(_ data: Data) -> String? {
        guard data.count <= maxBytes, let ext = type(of: data),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 1,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return nil }
        return write(data, ext: ext)
    }

    /// Bytes written in as they are under a fresh id — a design file's
    /// animated picture, stored for the design it brings.
    static func write(_ data: Data, ext: String) -> String? {
        let id = UID.make("anim")
        let clean = ext.lowercased().filter { $0.isLetter || $0.isNumber }
        do {
            try data.write(to: directory.appendingPathComponent("\(id).\(clean.isEmpty ? "gif" : clean)"))
            return id
        } catch {
            return nil
        }
    }

    /// A picture brought in — picked or dropped — when it is animated: its
    /// source and the size of its first frame; nil when it is not, and it
    /// comes in as a photo.
    static func bringIn(_ data: Data) -> (src: String, natural: CGSize)? {
        guard let id = store(data) else { return nil }
        guard let first = poster(id) else {
            delete(id)
            return nil
        }
        return (src(id, at: nil), first.size)
    }

    static func url(for id: String) -> URL? {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .first { $0.hasPrefix(id + ".") }
            .map { directory.appendingPathComponent($0) }
    }

    static func delete(_ id: String) {
        if let url = url(for: id) { try? FileManager.default.removeItem(at: url) }
        lock.lock()
        sources.removeValue(forKey: id)
        timings.removeValue(forKey: id)
        lock.unlock()
    }

    static func all() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            .sorted()
    }

    // MARK: frames

    /// Each picture's file, open for its frames.
    private static var sources: [String: CGImageSource] = [:]
    /// Each picture's delays as its file gives them, in milliseconds.
    private static var timings: [String: [Int]] = [:]
    /// Guards the two above, and every read from an open file.
    private static let lock = NSLock()
    /// Held by what they cost, as a clip's frames are.
    private static let frames: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        c.totalCostLimit = 120 * 1024 * 1024
        return c
    }()

    /// Picture `id`'s file, opened once; under `lock`.
    private static func source(_ id: String) -> CGImageSource? {
        if let open = sources[id] { return open }
        guard let url = url(for: id), let made = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        sources[id] = made
        return made
    }

    /// Each frame's delay as the file gives it, in whole milliseconds —
    /// unclamped, so a frame asking for none is 0 here and `minDelay` as it
    /// is shown. Empty for a picture that cannot be read.
    static func delays(of id: String) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        if let known = timings[id] { return known }
        guard let source = source(id) else { return [] }
        let read = (0..<CGImageSourceGetCount(source)).map { rawDelay(source, at: $0) }
        timings[id] = read
        return read
    }

    /// One frame's delay as its file says it, GIF or WebP.
    private static func rawDelay(_ source: CGImageSource, at index: Int) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0 }
        var seconds: Double?
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            seconds = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
        } else if let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            seconds = (webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double) ?? (webp[kCGImagePropertyWebPDelayTime] as? Double)
        }
        guard let seconds, seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds * 1000).rounded())
    }

    /// Frame `index` of picture `id`, decoded once and kept.
    static func image(_ id: String, frame index: Int) -> UIImage? {
        let key = "\(id)#\(index)" as NSString
        if let hit = frames.object(forKey: key) { return hit }
        lock.lock()
        var decoded: CGImage?
        if let source = source(id), index >= 0, index < CGImageSourceGetCount(source) {
            decoded = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        lock.unlock()
        guard let cg = decoded else { return nil }
        let image = UIImage(cgImage: cg)
        frames.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }

    /// The picture's first frame — what the element shows at rest.
    static func poster(_ id: String) -> UIImage? {
        image(id, frame: 0)
    }

    /// The frame an "anim:" source shows: the first at rest, else the one
    /// its stamped moment falls on.
    static func frameIndex(_ src: String) -> Int? {
        guard let parts = split(src) else { return nil }
        guard let time = parts.time else { return 0 }
        return frame(at: time, delays: delays(of: parts.id))
    }

    /// Resolves an "anim:" source to the frame it shows; the first frame
    /// stands in for one that will not decode.
    static func resolve(_ src: String) -> UIImage? {
        guard let parts = split(src), let index = frameIndex(src) else { return nil }
        return image(parts.id, frame: index) ?? poster(parts.id)
    }

    /// The source a frame is kept by downstream — its looks, its subject —
    /// the same for every moment that falls on that frame: the frame's own
    /// start, or the picture at rest for the first. Keyed by the moment
    /// asked for, every frame of a playing picture would be a new look.
    static func shownKey(_ src: String) -> String {
        guard let parts = split(src), let index = frameIndex(src) else { return src }
        guard index > 0 else { return Self.src(parts.id, at: nil) }
        return Self.src(parts.id, at: start(of: index, delays: delays(of: parts.id)))
    }
}
