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
//
// A font of your own is an entry too, of kind "font", kept apart from the
// photos, clips and music the Add sheet offers: its id is the twelve hex
// digits of "custom:<sha12>", and it also holds the font's "name" — its
// family's, read from the file — and its "file" in fonts/ ("<sha12>.ttf"),
// as the Android twin writes it, with its face: "family", "weight",
// "italic" and, for a variable font, "axes": {"wght": [min, max]}. An entry
// an earlier build wrote without them is described from its file once
// (FontStore.installed). See CustomFonts and FontStore.

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

    /// A font of your own, as uploads.json lists it.
    struct FontEntry: Equatable, Sendable {
        /// The font's hash, sha12.
        var id: String
        var name: String
        /// Its file in fonts/.
        var file: String
        var added: Double
        /// The family it is grouped in, its weight and whether it is an
        /// italic; an entry without them is the family `name`, 400, upright.
        var family: String
        var weight: Int
        var italic: Bool
        /// A variable font's wght axis, least to greatest.
        var wght: ClosedRange<Double>?
        /// Whether the entry says its face: false for one an earlier build
        /// wrote.
        var described: Bool

        init(id: String, name: String, file: String, added: Double, family: String? = nil, weight: Int = 400,
             italic: Bool = false, wght: ClosedRange<Double>? = nil, described: Bool = true) {
            self.id = id
            self.name = name
            self.file = file
            self.added = added
            self.family = family ?? name
            self.weight = weight
            self.italic = italic
            self.wght = wght
            self.described = described
        }

        /// The key a text set in it stores.
        var key: String { CustomFonts.key(id) }
    }

    static let fontKind = "font"

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

    /// Puts a font of your own on the list — its hash, family name and file
    /// — once, however often it is added. Its face goes in with
    /// describeFont.
    static func recordFont(_ sha: String, name: String, file: String, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var raw = list(now: now)
        guard !raw.contains(where: { $0["id"] as? String == sha && $0["kind"] as? String == fontKind }) else { return }
        raw.append(["id": sha, "kind": fontKind, "added": milliseconds(now), "name": name, "file": file])
        write(raw)
    }

    /// A font's face written into its entry: as it is added, and as an
    /// earlier build's entry is brought up to date.
    static func describeFont(_ sha: String, _ face: CustomFonts.Face) {
        lock.lock()
        defer { lock.unlock() }
        var raw = list()
        guard let i = raw.firstIndex(where: { $0["id"] as? String == sha && $0["kind"] as? String == fontKind }) else { return }
        describing(&raw[i], face)
        write(raw)
    }

    /// "family", "weight", "italic" and, for a variable font, "axes":
    /// {"wght": [min, max]}.
    private static func describing(_ item: inout [String: Any], _ face: CustomFonts.Face) {
        item["family"] = face.family
        item["weight"] = face.weight
        item["italic"] = face.italic
        if let axis = face.wght { item["axes"] = ["wght": [axis.min, axis.max]] }
    }

    /// A variable font's wght axis as an entry keeps it, when it does.
    private static func wghtAxis(_ item: [String: Any]) -> ClosedRange<Double>? {
        guard let axes = item["axes"] as? [String: Any], let range = axes["wght"] as? [NSNumber],
              range.count == 2, range[0].doubleValue <= range[1].doubleValue else { return nil }
        return range[0].doubleValue...range[1].doubleValue
    }

    /// The fonts of your own listed, newest first, whether or not their
    /// files are here (FontStore.installed asks that). One with no name is
    /// called by its hash; one with no file is taken to be a .ttf.
    static func fonts() -> [FontEntry] {
        lock.lock()
        let raw = list()
        lock.unlock()
        return raw.compactMap { item -> FontEntry? in
            guard item["kind"] as? String == fontKind,
                  let id = item["id"] as? String, CustomFonts.sha(CustomFonts.key(id)) != nil else { return nil }
            let name = (item["name"] as? String) ?? id
            let weight = (item["weight"] as? NSNumber)?.intValue
            return FontEntry(id: id, name: name,
                             file: (item["file"] as? String) ?? "\(id).ttf",
                             added: (item["added"] as? NSNumber)?.doubleValue ?? 0,
                             family: item["family"] as? String,
                             weight: weight ?? 400,
                             italic: (item["italic"] as? Bool) ?? false,
                             wght: wghtAxis(item),
                             described: weight != nil)
        }
        .enumerated()
        .sorted { $0.element.added != $1.element.added ? $0.element.added > $1.element.added : $0.offset > $1.offset }
        .map { $0.element }
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
    /// designs. It stays in them.", or "Used in 1 design. It stays in it." for
    /// one, as on Android.
    static func usedInNote(_ designs: Int) -> String {
        trn("Used in %d design. It stays in it.|Used in %d designs. It stays in them.", designs)
    }

    // MARK: Home's Uploads

    /// Every upload id `design` uses: a photo anywhere in it — a frame, a
    /// background, a shape's fill, the master's too — a clip, a song on an
    /// audio track, or a font of your own. The rule that keeps an upload
    /// from the launch sweep, so "Used in N designs" counts what the sweep
    /// would keep it for.
    static func ids(usedBy design: Design) -> Set<String> {
        DesignLibrary.photos(in: [design])
            .union(DesignLibrary.clips(in: [design]))
            .union(design.audioTracks.compactMap(\.audioId))
            .union(CustomFonts.used(in: design))
    }

    /// The designs among `designs` that use the upload `id`, in their
    /// order, whatever kind it is. A brand kit's use is asked apart
    /// (inBrandKit): it is no design to list. The Android twin's
    /// Uploads.usages.
    static func usages(_ designs: [Design], id: String) -> [Design] {
        designs.filter { ids(usedBy: $0).contains(id) }
    }

    /// Every upload id each of `designs` uses, by id: usages for every
    /// upload at once, each design read once — what the Uploads grid on
    /// Home counts with.
    static func usageIndex(_ designs: [Design]) -> [String: [Design]] {
        var index: [String: [Design]] = [:]
        for design in designs {
            for id in ids(usedBy: design) { index[id, default: []].append(design) }
        }
        return index
    }

    /// Whether a brand kit shows the photo `id` — as a logo, a brand photo
    /// or a graphic.
    static func inBrandKit(_ kits: BrandKits, id: String) -> Bool {
        kits.allAssets.contains("media:\(id)")
    }

    /// An upload as Home's grid lists it: a photo, clip or song of the
    /// list, or a font of your own — "image", "video", "audio" or "font".
    struct Listed: Equatable, Sendable {
        var id: String
        var kind: String
        /// When it came in, in epoch milliseconds.
        var added: Double
    }

    /// The Uploads grid's filters, after All: each a kind.
    static let filters = [Kind.image.rawValue, Kind.video.rawValue, Kind.audio.rawValue, fontKind]

    /// `entries` as the Uploads grid lists them: those of `kind` (every
    /// kind for nil), newest first, or largest first by `bytes` when
    /// `largest` — ties by newest.
    static func sorted(_ entries: [Listed], kind: String?, largest: Bool, bytes: (Listed) -> Int64) -> [Listed] {
        let kept = kind.map { k in entries.filter { $0.kind == k } } ?? entries
        // Stable: of two alike, the one listed first stays first.
        return kept.enumerated().sorted { a, b in
            if largest {
                let x = bytes(a.element), y = bytes(b.element)
                if x != y { return x > y }
            }
            if a.element.added != b.element.added { return a.element.added > b.element.added }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// "Used in 2 designs", or "Not used in any design": what the ⋯ menu
    /// says of an upload on Home.
    static func usedIn(_ designs: Int) -> String {
        designs <= 0 ? tr("Not used in any design") : trn("Used in %d design|Used in %d designs", designs)
    }

    /// What deleting uploads from Home asks: for `count` uploads of which
    /// `designs` designs use any — they stay in the designs' files, but
    /// show an empty frame once swept.
    static func deletingFromHome(_ count: Int, designs: Int) -> (title: String, text: String?) {
        let title = count == 1 ? tr("Delete this upload?") : trn("Delete %d upload?|Delete %d uploads?", count)
        let text = designs <= 0 ? nil
            : trn("Used in %d design. That design will show an empty frame.|Used in %d designs. Those designs will show an empty frame.", designs)
        return (title, text)
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
