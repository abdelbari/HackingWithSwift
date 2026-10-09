// Video clips as elements: a clip lives in Documents/video by id and the
// element that shows it is an ordinary image element whose source is
// "video:<id>". At rest that resolves to the clip's poster frame, so crop,
// filters, frames and every still export work unchanged; during the page
// preview and the video export the element's source is stamped with the
// moment in the clip — "video:<id>@1.25", where its trim, speed and loop
// (`clipTime`) put the page's time — and resolves to that frame. A clip
// trimmed to start later shows the frame at its start at rest too.
//
// A frame takes tens of milliseconds to decode. The video export waits for
// each (`resolve`), so no frame of a movie is ever a stale one; what plays
// live — Present, and Play in the editor — never waits (`peek`): it shows
// the clip's latest frame while the next is decoded off the main thread,
// and draws again when it lands, as the Android twin's presenter does.

import AVFoundation
import Foundation
import Observation
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

    /// Where a stamped moment falls in a clip `duration` long. A stamp has
    /// been through `clipTime` already, so it is taken as it is, kept within
    /// the clip; one past the end can only have been stamped before the
    /// clip's length was known, and loops over the whole file.
    static func stampedTime(_ t: Double, duration: Double) -> Double {
        guard duration > 0.01 else { return 0 }
        if t > duration { return loopedTime(t, duration: duration) }
        return min(max(0, t), duration - 0.01)
    }

    /// The moment in the file a clip shows `pageTime` seconds into its page:
    /// from its start, at its speed, round again or held on its last frame
    /// at its end. With no end and no known length it runs on from the
    /// start, and the store loops it over the file until the length is in.
    static func clipTime(_ pageTime: Double, clip: ClipPlayback, duration: Double?) -> Double {
        let start = max(0, clip.start)
        let local = max(pageTime, 0) * clip.playbackSpeed
        let end = min(clip.end ?? .infinity, duration ?? .infinity)
        guard end.isFinite else { return start + local }
        guard end - start > 0.01 else { return start }
        if clip.loop { return start + local.truncatingRemainder(dividingBy: end - start) }
        return min(start + local, end - 0.01)
    }

    /// The page hold that plays the clip through once: its trimmed length at
    /// its speed, to a tenth of a second, within the half second to the
    /// minute a page's hold can be.
    static func fitHold(_ clip: ClipPlayback, duration: Double) -> Double {
        let end = min(clip.end ?? duration, duration)
        let seconds = ((end - max(0, clip.start)) / clip.playbackSpeed * 10).rounded() / 10
        return min(max(seconds, MotionSettings.pageHoldRange.lowerBound), MotionSettings.pageHoldRange.upperBound)
    }

    /// A moment in a clip as the Clip sheet shows it: "m:ss.s".
    static func timeLabel(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }

    /// A clip's trim as the Clip sheet shows it: "0:02.0 – 0:06.0".
    static func rangeLabel(_ start: Double, _ end: Double) -> String {
        "\(timeLabel(start)) – \(timeLabel(end))"
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
        lock.lock()
        durations.removeValue(forKey: id)
        generators.removeValue(forKey: id)
        lock.unlock()
        liveLock.lock()
        liveLengths.removeValue(forKey: id)
        latest.removeValue(forKey: id)
        wanted.removeValue(forKey: id)
        liveLock.unlock()
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
    /// Held by what they cost, not only by how many: a frame can be 1920
    /// pixels on its long side, some 8 MB, and 240 of those came to nearly
    /// 2 GB before anything was let go.
    private static let frames: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 240
        c.totalCostLimit = 150 * 1024 * 1024
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

    /// Where the frame at `time` is cached: to a hundredth of a second.
    private static func frameKey(_ id: String, _ time: Double) -> NSString {
        "\(id)@\(String(format: "%.2f", time))" as NSString
    }

    /// The frame at `time`, synchronously; the same frame is asked for many
    /// times during a preview, so it is cached at a hundredth of a second.
    static func frame(_ id: String, at time: Double) -> UIImage? {
        let key = frameKey(id, time)
        if let hit = frames.object(forKey: key) { return hit }
        lock.lock(); defer { lock.unlock() }
        guard let g = generator(for: id) else { return nil }
        let cm = CMTime(seconds: max(0, time), preferredTimescale: 600)
        var read = try? g.copyCGImage(at: cm, actualTime: nil)
        if read == nil {
            // A generator can fail once and then read the same frame — its
            // decoder taken back under memory pressure, on a busy simulator
            // especially — so a fresh one is tried before a blank frame goes
            // into a preview or an export.
            generators[id] = nil
            read = try? generator(for: id)?.copyCGImage(at: cm, actualTime: nil)
        }
        guard let cg = read else { return nil }
        let image = UIImage(cgImage: cg)
        frames.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
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
    /// moment (see `stampedTime`). Decoded there and then if it has to be
    /// — what an export needs, and never what plays live; see `peek`.
    static func resolve(_ src: String) -> UIImage? {
        guard let parts = split(src) else { return nil }
        guard let time = parts.time else { return poster(parts.id) }
        return frame(parts.id, at: stampedTime(time, duration: duration(of: parts.id) ?? 0))
    }

    // MARK: playing live

    /// Moves on each time a frame asked for by `peek` is ready, so the views
    /// drawing clips live — which read it — draw again.
    @Observable
    final class Frames {
        fileprivate(set) var version = 0
    }

    static let live = Frames()

    /// Each clip's length as the live path knows it: read on the worker the
    /// first time, never on the main thread; one that cannot be read is
    /// taken as none, once, rather than tried again every frame.
    private static var liveLengths: [String: Double] = [:]
    /// The moment each clip last showed live, for the frames in between.
    private static var latest: [String: Double] = [:]
    /// A moment asked for: the stamped time, not yet kept within the clip,
    /// or nil for the clip at rest.
    private struct Want { var time: Double? }
    /// The latest moment asked for of each clip.
    private static var wanted: [String: Want] = [:]
    /// The clips with a decode waiting on the worker.
    private static var queued = Set<String>()
    /// Guards the four above; never held across a decode, so the main
    /// thread never waits on one.
    private static let liveLock = NSLock()
    private static let worker = DispatchQueue(label: "canvia.video-frames", qos: .userInitiated)

    /// The clip's length as the live path has read it, without reading it:
    /// nil until it has, and for a clip whose length cannot be read — what
    /// a clip playing live is timed by, as the main thread never waits.
    static func knownLength(_ id: String) -> Double? {
        liveLock.lock(); defer { liveLock.unlock() }
        guard let length = liveLengths[id], length > 0.01 else { return nil }
        return length
    }

    /// What a "video:" source shows, without waiting: its frame if that has
    /// been decoded, else the clip's latest frame shown, else its poster,
    /// while the frame is decoded on a worker. Only the latest moment asked
    /// for is decoded, so a clip that plays faster than frames decode skips
    /// rather than falls behind. Nil until the clip has shown anything.
    ///
    /// The key names the picture actually returned — the source that
    /// resolves to that same frame — for caches downstream: keyed by the
    /// moment asked for, a filtered copy would keep a stale frame for good.
    static func peek(_ source: String) -> (image: UIImage, key: String)? {
        guard let parts = split(source) else { return nil }
        let id = parts.id
        let rest = VideoStore.src(id, at: nil)
        guard let time = parts.time else {
            if let poster = posters.object(forKey: id as NSString) { return (poster, rest) }
            ask(id, Want(time: nil))
            return nil
        }
        liveLock.lock()
        let length = liveLengths[id]
        liveLock.unlock()
        // Until its length is known a playing clip cannot say which frame it
        // is at, so it asks the worker rather than take its first frame for
        // the answer.
        if let length {
            let at = stampedTime(time, duration: length)
            if let hit = frames.object(forKey: frameKey(id, at)) {
                liveLock.lock()
                latest[id] = at
                // Nothing older is worth decoding now.
                wanted.removeValue(forKey: id)
                liveLock.unlock()
                return (hit, VideoStore.src(id, at: at))
            }
        }
        ask(id, Want(time: time))
        liveLock.lock()
        let shown = latest[id]
        liveLock.unlock()
        if let shown, let image = frames.object(forKey: frameKey(id, shown)) {
            return (image, VideoStore.src(id, at: shown))
        }
        if let poster = posters.object(forKey: id as NSString) { return (poster, rest) }
        return nil
    }

    /// Records the moment wanted of clip `id`, and queues it on the worker
    /// unless it is already waiting there.
    private static func ask(_ id: String, _ want: Want) {
        liveLock.lock()
        wanted[id] = want
        let start = queued.insert(id).inserted
        liveLock.unlock()
        if start { worker.async { VideoStore.decodeNext(id) } }
    }

    /// One frame of clip `id` — the latest moment asked for — on the worker;
    /// then its turn passes on. A clip still asking goes to the back of the
    /// queue, so two clips on a page take turns rather than one starving the
    /// other.
    private static func decodeNext(_ id: String) {
        liveLock.lock()
        let want = wanted.removeValue(forKey: id)
        var length = liveLengths[id]
        liveLock.unlock()
        var landed = false
        if let want {
            if let time = want.time {
                if length == nil {
                    let read = duration(of: id) ?? 0
                    liveLock.lock()
                    liveLengths[id] = read
                    liveLock.unlock()
                    length = read
                    landed = true
                }
                let at = stampedTime(time, duration: length ?? 0)
                if frame(id, at: at) != nil {
                    liveLock.lock()
                    latest[id] = at
                    liveLock.unlock()
                    landed = true
                }
            } else if poster(id) != nil {
                landed = true
            }
        }
        liveLock.lock()
        let more = wanted[id] != nil
        if !more { queued.remove(id) }
        liveLock.unlock()
        if more { worker.async { VideoStore.decodeNext(id) } }
        if landed { DispatchQueue.main.async { VideoStore.live.version &+= 1 } }
    }
}
