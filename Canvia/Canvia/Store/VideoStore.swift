// Video clips as elements: a clip lives in Documents/video by id and the
// element that shows it is an ordinary image element whose source is
// "video:<id>". At rest that resolves to the clip's poster frame, so crop,
// filters, frames and every still export work unchanged; during the page
// preview and the video export the element's source is stamped with the
// moment — "video:<id>@1.25" — and resolves to that frame, looping over
// the clip's length.

import AVFoundation
import Foundation
import UIKit

enum VideoStore {

    static let prefix = "video:"

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("video", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func isVideo(_ src: String?) -> Bool { src?.hasPrefix(prefix) == true }

    /// "video:<id>@<seconds>" → the id and the moment; no "@" is the poster.
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
        return prefix + id + "@" + String(format: "%.2f", time)
    }

    /// Where `t` seconds into the page falls in a clip `duration` long,
    /// looping; a clip with no length shows its start.
    static func loopedTime(_ t: Double, duration: Double) -> Double {
        guard duration > 0.01 else { return 0 }
        let m = t.truncatingRemainder(dividingBy: duration)
        return m < 0 ? m + duration : m
    }

    // MARK: files

    /// Writes the movie bytes in under a fresh id; the poster and duration
    /// are read on first use.
    static func store(_ data: Data, ext: String) -> String? {
        let id = UID.make("vid")
        let clean = ext.isEmpty ? "mov" : ext.lowercased()
        do {
            try data.write(to: directory.appendingPathComponent("\(id).\(clean)"))
            return id
        } catch {
            return nil
        }
    }

    static func url(for id: String) -> URL? {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .first { $0.hasPrefix(id + ".") }
            .map { directory.appendingPathComponent($0) }
    }

    static func delete(_ id: String) {
        if let url = url(for: id) { try? FileManager.default.removeItem(at: url) }
        durations.removeValue(forKey: id)
        posters.removeObject(forKey: id as NSString)
    }

    static func all() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            .sorted()
    }

    // MARK: frames

    private static var durations: [String: Double] = [:]
    private static let posters = NSCache<NSString, UIImage>()
    private static let frames: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 240
        return c
    }()
    private static var generators: [String: AVAssetImageGenerator] = [:]
    private static let lock = NSLock()

    /// The clip's length in seconds, or nil when it cannot be read.
    static func duration(of id: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        if let known = durations[id] { return known }
        guard let url = url(for: id) else { return nil }
        let seconds = AVURLAsset(url: url).duration.seconds
        guard seconds.isFinite else { return nil }
        durations[id] = seconds
        return seconds
    }

    private static func generator(for id: String) -> AVAssetImageGenerator? {
        if let g = generators[id] { return g }
        guard let url = url(for: id) else { return nil }
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        g.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        g.maximumSize = CGSize(width: 1920, height: 1920)
        generators[id] = g
        return g
    }

    /// The frame at `time`, synchronously; the same frame is asked for many
    /// times during a preview, so it is cached at a hundredth of a second.
    static func frame(_ id: String, at time: Double) -> UIImage? {
        let key = "\(id)@\(String(format: "%.2f", time))" as NSString
        if let hit = frames.object(forKey: key) { return hit }
        lock.lock(); defer { lock.unlock() }
        guard let g = generator(for: id) else { return nil }
        let cm = CMTime(seconds: max(0, time), preferredTimescale: 600)
        guard let cg = try? g.copyCGImage(at: cm, actualTime: nil) else { return nil }
        let image = UIImage(cgImage: cg)
        frames.setObject(image, forKey: key)
        return image
    }

    /// The clip's first frame — what the element shows at rest.
    static func poster(_ id: String) -> UIImage? {
        if let hit = posters.object(forKey: id as NSString) { return hit }
        guard let image = frame(id, at: 0) else { return nil }
        posters.setObject(image, forKey: id as NSString)
        return image
    }

    /// Resolves a "video:" source: the poster, or the frame at the stamped
    /// moment, looped over the clip.
    static func resolve(_ src: String) -> UIImage? {
        guard let parts = split(src) else { return nil }
        guard let time = parts.time else { return poster(parts.id) }
        let looped = loopedTime(time, duration: duration(of: parts.id) ?? 0)
        return frame(parts.id, at: looped)
    }
}
