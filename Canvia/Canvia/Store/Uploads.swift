// Your uploads: the photos, videos and music the person brought in —
// picked, dropped or pasted — listed in Documents/uploads.json, so the Add
// sheet can offer them again and the launch sweep never takes one. Before
// the list, an upload no design used any more was swept away at the next
// launch, and a clip or a song could never be found again at all.
//
// Pictures the app makes itself — cut-outs, erased copies, scans, baked
// looks, traced shapes, thumbnails — are not uploads: they live, and go,
// with the designs that use them.
//
// The file is a JSON array of {"id", "kind", "added"}: the id as the
// media:, video: and audio sources name it, "image", "video" or "audio",
// and when it came in, in epoch milliseconds. The Android twin keeps the
// same file in its filesDir. Keys this version does not know are kept as
// they were.

import Foundation

enum Uploads {

    enum Kind: String, CaseIterable, Sendable {
        case image, video, audio
    }

    struct Entry: Equatable, Sendable {
        var id: String
        var kind: Kind
        /// When it came in, in epoch milliseconds.
        var added: Double
    }

    static let fileName = "uploads.json"

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// One change to the list at a time: a dropped photo is stored, and
    /// recorded, off the main thread.
    private static let lock = NSLock()

    // MARK: reading

    /// Every upload whose file is still here, newest first.
    static func all() -> [Entry] {
        lock.lock()
        let raw = list()
        lock.unlock()
        // By name only: the Add sheet asks for this as it draws.
        let photos = ((try? FileManager.default.contentsOfDirectory(atPath: MediaStore.directory.path)) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { MediaStore.extensions.contains($0.pathExtension) }
            .map { $0.deletingPathExtension().lastPathComponent }
        let here: [Kind: Set<String>] = [
            .image: Set(photos),
            .video: Set(VideoStore.all()),
            .audio: Set(AudioStore.all()),
        ]
        return entries(in: raw)
            .filter { here[$0.kind]?.contains($0.id) == true }
            .enumerated()
            // Newest first; of two at the same moment, the later listed.
            .sorted { $0.element.added != $1.element.added ? $0.element.added > $1.element.added : $0.offset > $1.offset }
            .map { $0.element }
    }

    /// The uploads of one kind, newest first.
    static func all(_ kind: Kind) -> [Entry] {
        all().filter { $0.kind == kind }
    }

    /// What the launch sweep never takes: every upload on the list, and
    /// every one starred, on the list or not.
    static func kept(defaults: UserDefaults = .standard) -> Set<String> {
        lock.lock()
        let raw = list()
        lock.unlock()
        return Set(entries(in: raw).map(\.id)).union(Favorites.ids(of: "upload", defaults: defaults))
    }

    // MARK: changing

    /// Puts something the person brought in on the list; once, however
    /// often it is recorded.
    static func record(_ id: String, kind: Kind, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var raw = list(now: now)
        guard !raw.contains(where: { $0["id"] as? String == id }) else { return }
        raw.append(["id": id, "kind": kind.rawValue, "added": milliseconds(now)])
        write(raw)
    }

    /// A photo or clip by the source that shows it: "media:<id>" or
    /// "video:<id>".
    static func record(source: String, now: Date = Date()) {
        if source.hasPrefix("media:") {
            record(String(source.dropFirst("media:".count)), kind: .image, now: now)
        } else if let clip = VideoStore.split(source) {
            record(clip.id, kind: .video, now: now)
        }
    }

    /// Takes an upload off the list. Its file stays for whatever still uses
    /// it, and the launch sweep takes it once nothing does.
    static func remove(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        let raw = list()
        let kept = raw.filter { $0["id"] as? String != id }
        if kept.count != raw.count { write(kept) }
    }

    /// Makes the list if there is none yet; see list(). Called at launch,
    /// before the sweep.
    static func seedIfNeeded(now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        _ = list(now: now)
    }

    /// What deleting an upload says when designs use it: "Used in 3
    /// designs. It stays in them.", "1 design" for one, as on Android.
    static func usedInNote(_ designs: Int) -> String {
        "Used in \(designs) \(designs == 1 ? "design" : "designs"). It stays in them."
    }

    // MARK: the file

    /// The list as written, every key kept. None yet, or one that no
    /// longer reads, is made from every photo, clip and song stored, and
    /// written: on the first launch with the list, nothing brought in
    /// before is swept for want of being on it. Called with the lock held.
    private static func list(now: Date = Date()) -> [[String: Any]] {
        if let raw = read() { return raw }
        let seeded = seed(now: now)
        write(seeded)
        return seeded
    }

    /// The list as written; nil when there is none or it does not read.
    private static func read() -> [[String: Any]]? {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        return list.compactMap { $0 as? [String: Any] }
    }

    private static func write(_ raw: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The entries this version can use; one of a kind it does not know is
    /// left in the file but not offered.
    private static func entries(in raw: [[String: Any]]) -> [Entry] {
        raw.compactMap { item -> Entry? in
            guard let id = item["id"] as? String, !id.isEmpty,
                  let name = item["kind"] as? String, let kind = Kind(rawValue: name) else { return nil }
            let added = (item["added"] as? NSNumber)?.doubleValue ?? 0
            return Entry(id: id, kind: kind, added: added)
        }
    }

    /// Every photo, clip and song stored, dated by its file.
    private static func seed(now: Date) -> [[String: Any]] {
        var raw: [[String: Any]] = []
        func add(_ id: String, _ kind: Kind, _ url: URL) {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            raw.append(["id": id, "kind": kind.rawValue, "added": milliseconds(date ?? now)])
        }
        let photos = (try? FileManager.default.contentsOfDirectory(
            at: MediaStore.directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in photos where MediaStore.extensions.contains(url.pathExtension) {
            add(url.deletingPathExtension().lastPathComponent, .image, url)
        }
        for id in VideoStore.all() {
            if let url = VideoStore.url(for: id) { add(id, .video, url) }
        }
        for id in AudioStore.all() {
            add(id, .audio, AudioStore.directory.appendingPathComponent(id))
        }
        return raw
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
