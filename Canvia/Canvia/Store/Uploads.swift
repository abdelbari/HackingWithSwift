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
// and when it came in, in epoch milliseconds — and, filed in a folder of
// Home's, its "folder" (a path, as a design's: DesignLibrary.folderName) —
// a font never is, on either phone, so one is never filed or moved.
// The Android twin keeps the same file in its filesDir. Keys this version
// does not know are kept as they were.
//
// A font of your own is an entry too, of kind "font", kept apart from the
// photos, clips and music the Add sheet offers: its id is the twelve hex
// digits of "custom:<sha12>", and it also holds the font's "name" — its
// family's, read from the file — and its "file" in fonts/ ("<sha12>.ttf"),
// as the Android twin writes it, with its face: "family", "weight",
// "italic" and, for a variable font, "axes": {"wght": [min, max]} — and the
// "scripts" it covers (FontLibrary.scriptKeys). An entry an earlier build
// wrote without them is described from its file once (FontStore.installed).
// See CustomFonts and FontStore.
//
// Deleted from Home or Add, an entry is kept with "deleted": when, in epoch
// milliseconds, and its file stays: it waits in Recently deleted, hidden
// from Add, Home's Uploads and search, while a design that shows it goes on
// showing it. Restored, the key goes; after DesignLibrary.trashRetention
// the launch sweep takes the entry off the list (swept), and the file goes
// with the prune that follows unless a design, a version, a brand kit or a
// template still uses it. The Android twin's Uploads.trashing by the same
// rules, with the shared fixture uploads-trash.json.

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
        /// Its file's name, where the entry keeps one ("name"): what a
        /// Bulk create photo cell may name it by.
        var fileName: String? = nil
        /// The folder it is filed in, as a design's is; nil at the top.
        var folder: String? = nil
        /// For a clip converted as it came in (VideoImport), how many
        /// bytes it was before; nil for one kept as it came.
        var optimisedFrom: Int64? = nil
        /// When it went to Recently deleted, in epoch milliseconds; nil
        /// while it is not there.
        var deleted: Double? = nil
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
        /// The scripts it covers, when the entry says (FontLibrary.covers).
        var scripts: [String]?
        /// When it went to Recently deleted, in epoch milliseconds; nil
        /// while it is not there. Its file stays registered meanwhile, so
        /// a text set in it still draws.
        var deleted: Double? = nil

        init(id: String, name: String, file: String, added: Double, family: String? = nil, weight: Int = 400,
             italic: Bool = false, wght: ClosedRange<Double>? = nil, described: Bool = true,
             scripts: [String]? = nil) {
            self.id = id
            self.name = name
            self.file = file
            self.added = added
            self.family = family ?? name
            self.weight = weight
            self.italic = italic
            self.wght = wght
            self.described = described
            self.scripts = scripts
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

    /// Every upload whose file is still here, newest first — those in
    /// Recently deleted left out.
    static func all() -> [Entry] {
        withTrashed().filter { $0.deleted == nil }
    }

    /// The uploads in Recently deleted whose files are still here, the last
    /// deleted first.
    static func trashed() -> [Entry] {
        withTrashed().filter { $0.deleted != nil }.sorted { ($0.deleted ?? 0) > ($1.deleted ?? 0) }
    }

    /// The fonts of your own in Recently deleted, the last deleted first.
    static func trashedFonts() -> [FontEntry] {
        fonts().filter { $0.deleted != nil }.sorted { ($0.deleted ?? 0) > ($1.deleted ?? 0) }
    }

    /// Every upload whose file is still here, in Recently deleted or not,
    /// newest first: what a backup keeps, and Storage counts.
    static func withTrashed() -> [Entry] {
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
        record(id, kind: kind, name: nil, now: now)
    }

    /// As `record(_:kind:now:)`, with the `name` its file had, where it came
    /// with one, kept as "name": what a suggested description is drawn from
    /// (AltText.suggest), as on the Android twin.
    static func record(_ id: String, kind: Kind, name: String?, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var raw = list(now: now)
        guard !raw.contains(where: { $0["id"] as? String == id }) else { return }
        var item: [String: Any] = ["id": id, "kind": kind.rawValue, "added": milliseconds(now)]
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { item["name"] = name }
        raw.append(item)
        write(raw)
    }

    /// A photo or clip by the source that shows it: "media:<id>" or
    /// "video:<id>".
    static func record(source: String, now: Date = Date()) {
        record(source: source, name: nil, now: now)
    }

    /// As `record(source:now:)`, with the name its file had.
    static func record(source: String, name: String?, now: Date = Date()) {
        if source.hasPrefix("media:") {
            record(String(source.dropFirst("media:".count)), kind: .image, name: name, now: now)
        } else if let clip = VideoStore.split(source) {
            record(clip.id, kind: .video, name: name, now: now)
        }
    }

    /// Puts a font of your own on the list — its hash, family name and file
    /// — once, however often it is added. Its face goes in with
    /// describeFont.
    static func recordFont(_ sha: String, name: String, file: String, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        let raw = list(now: now)
        let out = addingFont(raw, sha: sha, name: name, file: file, added: milliseconds(now))
        if out.count != raw.count || restoredFont(raw, sha: sha) { write(out) }
    }

    /// `raw` with the font `sha` — called `name`, kept as `file` — as
    /// added at `added` (epoch ms); unchanged when it is there already, but
    /// for one in Recently deleted, which adding again brings back.
    static func addingFont(_ raw: [[String: Any]], sha: String, name: String, file: String,
                           added: Int64) -> [[String: Any]] {
        guard raw.contains(where: { isFont($0, sha) }) else {
            let entry: [String: Any] = ["id": sha, "kind": fontKind, "added": added, "name": name, "file": file]
            return raw + [entry]
        }
        return raw.map { item in
            guard isFont(item, sha), item[deletedKey] != nil else { return item }
            var out = item
            out[deletedKey] = nil
            return out
        }
    }

    /// Whether adding the font `sha` again takes it out of Recently deleted.
    private static func restoredFont(_ raw: [[String: Any]], sha: String) -> Bool {
        raw.contains { isFont($0, sha) && $0[deletedKey] != nil }
    }

    private static func isFont(_ item: [String: Any], _ sha: String) -> Bool {
        item["id"] as? String == sha && item["kind"] as? String == fontKind
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
        if let scripts = face.scripts { item["scripts"] = scripts }
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
            var entry = FontEntry(id: id, name: name,
                             file: (item["file"] as? String) ?? "\(id).ttf",
                             added: (item["added"] as? NSNumber)?.doubleValue ?? 0,
                             family: item["family"] as? String,
                             weight: weight ?? 400,
                             italic: (item["italic"] as? Bool) ?? false,
                             wght: wghtAxis(item),
                             described: weight != nil,
                             scripts: item["scripts"] as? [String])
            entry.deleted = deletedTime(item)
            return entry
        }
        .enumerated()
        .sorted { $0.element.added != $1.element.added ? $0.element.added > $1.element.added : $0.offset > $1.offset }
        .map { $0.element }
    }

    /// The key an upload's folder is kept under.
    static let folderKey = "folder"

    /// `raw` — the list as written — with upload `id` filed in `folder`: nil
    /// takes it out of one; anything else it holds as it was. A font is left
    /// as it was.
    static func filed(_ raw: [[String: Any]], id: String, folder: String?) -> [[String: Any]] {
        raw.map { item in
            guard item["id"] as? String == id, item["kind"] as? String != fontKind else { return item }
            var out = item
            out[folderKey] = DesignLibrary.folderName(folder)
            return out
        }
    }

    /// `raw` once folder `from` is `to` (DesignLibrary.movedFolder): every
    /// upload in it, or in a folder inside it, to the same place there.
    static func refiled(_ raw: [[String: Any]], from: String, to: String?) -> [[String: Any]] {
        raw.map { item in
            guard let folder = item[folderKey] as? String, DesignLibrary.isInside(folder, from),
                  item["kind"] as? String != fontKind else { return item }
            var out = item
            out[folderKey] = DesignLibrary.movedFolder(folder, from: from, to: to)
            return out
        }
    }

    /// `raw` with clip `id` marked converted as it came in, from
    /// `originalBytes` (VideoImport): {"optimised": true, "originalBytes"},
    /// and "toneMapped": "hlg" | "pq" for an HDR clip brought to SDR;
    /// anything else it holds as it was, and anything not a clip untouched.
    static func optimised(_ raw: [[String: Any]], id: String, originalBytes: Int64) -> [[String: Any]] {
        optimised(raw, id: id, originalBytes: originalBytes, toneMapped: nil)
    }

    static func optimised(_ raw: [[String: Any]], id: String, originalBytes: Int64, toneMapped: String?) -> [[String: Any]] {
        raw.map { item in
            guard item["id"] as? String == id, item["kind"] as? String == Kind.video.rawValue else { return item }
            var out = item
            out[VideoImport.optimisedKey] = true
            out[VideoImport.originalBytesKey] = originalBytes
            if let toneMapped { out[VideoImport.toneMappedKey] = toneMapped }
            return out
        }
    }

    /// Clip `id` marked converted as it came in, from `originalBytes`.
    static func markOptimised(_ id: String, originalBytes: Int64, toneMapped: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        write(optimised(list(), id: id, originalBytes: originalBytes, toneMapped: toneMapped))
    }

    /// The uploads filed in `path` — and, `recursive`, in the folders inside
    /// it.
    static func inFolder(_ entries: [Entry], path: String, recursive: Bool) -> [Entry] {
        entries.filter { recursive ? DesignLibrary.isInside($0.folder, path) : $0.folder == path }
    }

    /// Files upload `id` in `folder`, or out of any for nil.
    static func file(_ id: String, inFolder folder: String?) {
        lock.lock()
        defer { lock.unlock() }
        write(filed(list(), id: id, folder: folder))
    }

    /// Folder `from` renamed, moved or emptied up to `to`: its uploads go
    /// with it.
    static func refile(from: String, to: String?) {
        lock.lock()
        defer { lock.unlock() }
        let raw = list()
        let moved = refiled(raw, from: from, to: to)
        if !NSArray(array: moved).isEqual(to: raw) { write(moved) }
    }

    // MARK: Recently deleted

    /// The key an entry's time in Recently deleted is kept under.
    static let deletedKey = "deleted"

    /// When `item` went to Recently deleted: a number, in epoch
    /// milliseconds; nil for none, or anything else kept there.
    static func deletedTime(_ item: [String: Any]) -> Double? {
        // A JSON true or false is no time; `is Bool` would also pass over a
        // 0 or 1 read back as an NSNumber.
        guard let number = item[deletedKey] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    /// `raw` with `ids` in Recently deleted from `now` (epoch ms); one there
    /// already keeps its time. Anything else each holds as it was.
    static func trashing(_ raw: [[String: Any]], ids: Set<String>, now: Double) -> [[String: Any]] {
        raw.map { item in
            guard let id = item["id"] as? String, ids.contains(id), deletedTime(item) == nil else { return item }
            var out = item
            out[deletedKey] = Int64(now.rounded())
            return out
        }
    }

    /// `raw` with `ids` out of Recently deleted, where they were.
    static func restoring(_ raw: [[String: Any]], ids: Set<String>) -> [[String: Any]] {
        raw.map { item in
            guard let id = item["id"] as? String, ids.contains(id), item[deletedKey] != nil else { return item }
            var out = item
            out[deletedKey] = nil
            return out
        }
    }

    /// The ids in `raw` deleted longer ago than Recently deleted keeps
    /// them, at `now` (epoch ms): before now − 30 days, as a design's; one
    /// deleted exactly 30 days ago stays this launch.
    static func stale(_ raw: [[String: Any]], now: Double) -> [String] {
        let cutoff = now - DesignLibrary.trashRetention * 1000
        return raw.compactMap { item in
            guard let id = item["id"] as? String, let when = deletedTime(item), when < cutoff else { return nil }
            return id
        }
    }

    /// What the launch sweep leaves of `raw` at `now`: those `stale` off
    /// the list, the rest as they were.
    static func swept(_ raw: [[String: Any]], now: Double) -> [[String: Any]] {
        let gone = Set(stale(raw, now: now))
        return raw.filter { item in !gone.contains(item["id"] as? String ?? "") }
    }

    /// Uploads `ids` to Recently deleted now: hidden from Add, Home's
    /// Uploads and search, their files left where they are.
    static func trash(_ ids: [String]) {
        trash(ids, at: Date().timeIntervalSince1970 * 1000)
    }

    /// The same, deleted at `at`, in epoch milliseconds.
    static func trash(_ ids: [String], at: Double) {
        lock.lock()
        defer { lock.unlock() }
        write(trashing(list(), ids: Set(ids), now: at))
    }

    /// Uploads `ids` back out of Recently deleted.
    static func restore(_ ids: [String]) {
        lock.lock()
        defer { lock.unlock() }
        write(restoring(list(), ids: Set(ids)))
    }

    /// The launch sweep's part, before the prune: what has waited thirty
    /// days in Recently deleted off the list, so the prune takes each
    /// photo's, clip's or song's file unless something still uses it.
    /// Returns the fonts it took off, whose files no prune reads.
    @discardableResult
    static func sweepTrash(now: Date = Date()) -> [String] {
        lock.lock()
        let raw = list()
        let ms = now.timeIntervalSince1970 * 1000
        let gone = Set(stale(raw, now: ms))
        if !gone.isEmpty { write(swept(raw, now: ms)) }
        lock.unlock()
        let taken = raw.filter { gone.contains($0["id"] as? String ?? "") }
        // Unstarred too, as deleting for good does, or the star keeps the file.
        for item in taken where item["kind"] as? String != fontKind {
            guard let id = item["id"] as? String else { continue }
            if Favorites.isFavorite("upload", id) { Favorites.toggle("upload", id) }
        }
        let fonts = taken.filter { $0["kind"] as? String == fontKind }
        return fonts.compactMap { $0["id"] as? String }
    }

    /// An upload out of Recently deleted for good: off the list and
    /// unstarred — or the star would keep its file — its file left for the
    /// next launch sweep, which takes it once nothing uses it; a font's
    /// file goes now, as deleting one always did.
    static func deleteForever(_ id: String, font: Bool) {
        if font {
            FontStore.remove(id)
        } else {
            remove(id)
            if Favorites.isFavorite("upload", id) { Favorites.toggle("upload", id) }
        }
    }

    /// The entries `raw` lists, for a test: as all() reads them, whether
    /// or not their files are here.
    static func entries(of raw: [[String: Any]]) -> [Entry] { entries(in: raw) }

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
    /// would keep it for — with the other faces of a family it uses among
    /// `faces`, this phone's own as the sweep reads them.
    static func ids(usedBy design: Design, faces: [FontEntry]) -> Set<String> {
        DesignLibrary.photos(in: [design])
            .union(DesignLibrary.clips(in: [design]))
            .union(design.audioTracks.compactMap(\.audioId))
            .union(CustomFonts.used(in: design, faces: faces))
    }

    /// The designs among `designs` that use the upload `id`, in their
    /// order, whatever kind it is. A brand kit's use is asked apart
    /// (inBrandKit): it is no design to list. The Android twin's
    /// Uploads.usages.
    static func usages(_ designs: [Design], id: String, faces: [FontEntry] = FontStore.faces()) -> [Design] {
        designs.filter { ids(usedBy: $0, faces: faces).contains(id) }
    }

    /// Every upload id each of `designs` uses, by id: usages for every
    /// upload at once, each design read once — what the Uploads grid on
    /// Home counts with.
    static func usageIndex(_ designs: [Design], faces: [FontEntry] = FontStore.faces()) -> [String: [Design]] {
        var index: [String: [Design]] = [:]
        for design in designs {
            for id in ids(usedBy: design, faces: faces) { index[id, default: []].append(design) }
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

    /// Whether every upload the grid `shown` is picked — so the button
    /// says "Deselect all". Picks the grid does not show do not count.
    static func allPicked(_ shown: [String], picked: Set<String>) -> Bool {
        !shown.isEmpty && shown.allSatisfy { picked.contains($0) }
    }

    /// What "Select all" (or "Deselect all") leaves picked: only what the
    /// grid `shown`, or nothing.
    static func pickingAll(_ shown: [String], picked: Set<String>) -> Set<String> {
        allPicked(shown, picked: picked) ? [] : Set(shown)
    }

    /// "Used in 2 designs", or "Not used in any design": what the ⋯ menu
    /// says of an upload on Home — and "and your brand kit", or "Used in
    /// your brand kit" alone, when `brandKit` shows it too.
    static func usedIn(_ designs: Int, brandKit: Bool = false) -> String {
        if brandKit {
            return designs > 0
                ? trn("Used in %d design and your brand kit|Used in %d designs and your brand kit", designs)
                : tr("Used in your brand kit")
        }
        return designs <= 0 ? tr("Not used in any design") : trn("Used in %d design|Used in %d designs", designs)
    }

    /// What deleting uploads from Home asks: for `count` uploads of which
    /// `designs` designs use any — they stay in the designs' files, but
    /// show an empty frame once swept — and whether a brand kit shows any
    /// of them, said after the designs.
    static func deletingFromHome(_ count: Int, designs: Int, brandKit: Bool = false) -> (title: String, text: String?) {
        let title = count == 1 ? tr("Delete this upload?") : trn("Delete %d upload?|Delete %d uploads?", count)
        let inDesigns: String? = designs <= 0 ? nil
            : trn("Used in %d design. That design will show an empty frame.|Used in %d designs. Those designs will show an empty frame.", designs)
        let inKit: String? = brandKit ? tr("Used in your brand kit.") : nil
        let said = [inDesigns, inKit].compactMap { $0 }
        return (title, said.isEmpty ? nil : said.joined(separator: " "))
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
            let optimised = item[VideoImport.optimisedKey] as? Bool == true
            return Entry(id: id, kind: kind, added: added, fileName: item["name"] as? String,
                         folder: DesignLibrary.folderName(item[folderKey] as? String),
                         optimisedFrom: optimised ? (item[VideoImport.originalBytesKey] as? NSNumber)?.int64Value : nil,
                         deleted: deletedTime(item))
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
