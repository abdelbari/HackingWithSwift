// Persistence: designs are JSON files in Documents/designs, thumbnails are
// JPEGs in Documents/thumbs. The recents list is derived from the files,
// through the summaries DesignShelf keeps of them.

import UIKit

struct RecentDesign: Identifiable, Sendable {
    var id: String
    var title: String
    var width: Double
    var height: Double
    var pages: Int
    var updatedAt: Double
    var folder: String? = nil
    /// When the card's picture was last written, in epoch milliseconds, or
    /// nil when there is none. The picture itself is read as its card
    /// shows, not with the list: building every one up front was most of
    /// what Home did each time it appeared.
    var thumbnailStamp: Double? = nil
    /// A design file that no longer reads as a design.
    var damaged = false
}

enum DesignLibrary {

    static var designsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("designs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var thumbsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes the design whole or not at all, and says which. Written in
    /// place, a save the phone ran out of room for, or was killed during,
    /// left half a file where the design had been — and the design with it
    /// gone. Atomic, the new file is written beside the old and swapped in
    /// only once it is complete, so a failed save leaves the last good one.
    @discardableResult
    static func save(_ design: Design) -> Bool {
        do {
            let data = try JSONEncoder().encode(design)
            try data.write(to: designsDir.appendingPathComponent("\(design.id).json"), options: .atomic)
            SpotlightIndexer.index(design)
            return true
        } catch {
            return false
        }
    }

    static func saveThumbnail(_ image: UIImage, for id: String) {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }
        try? data.write(to: thumbsDir.appendingPathComponent("\(id).jpg"), options: .atomic)
    }

    static func load(id: String) -> Design? {
        let url = designsDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url),
              var design = try? JSONDecoder().decode(Design.self, from: data) else { return nil }
        design.normalizeTextHeights()
        return design
    }

    static func copyThumbnail(from oldId: String, to newId: String) {
        let src = thumbsDir.appendingPathComponent("\(oldId).jpg")
        let dst = thumbsDir.appendingPathComponent("\(newId).jpg")
        try? FileManager.default.copyItem(at: src, to: dst)
    }

    /// Gone for good: the document, its thumbnail and its versions.
    static func delete(id: String) {
        SpotlightIndexer.remove(id)
        try? FileManager.default.removeItem(at: designsDir.appendingPathComponent("\(id).json"))
        try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent("\(id).jpg"))
        try? FileManager.default.removeItem(at: trashDir.appendingPathComponent("\(id).json"))
        try? FileManager.default.removeItem(at: trashDir.appendingPathComponent("\(id).jpg"))
        try? FileManager.default.removeItem(at: historyDir(for: id))
    }

    /// Gone for good from the trash only. A live design with the same id —
    /// one imported again, or restored and deleted twice — keeps its
    /// document and versions; the versions go only when nothing lives on.
    static func deleteTrashed(id: String) {
        try? FileManager.default.removeItem(at: trashDir.appendingPathComponent("\(id).json"))
        try? FileManager.default.removeItem(at: trashDir.appendingPathComponent("\(id).jpg"))
        guard !FileManager.default.fileExists(atPath: designsDir.appendingPathComponent("\(id).json").path) else { return }
        try? FileManager.default.removeItem(at: historyDir(for: id))
        SpotlightIndexer.remove(id)
    }

    // MARK: trash

    /// Deleted designs wait here for thirty days. "Delete" on the home
    /// screen used to be the only irreversible action in the app, and it sat
    /// two taps from "Rename" in the same menu.
    static let trashRetention: TimeInterval = 30 * 24 * 3600

    static var trashDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Move a design to the trash. Its versions stay where they are, so a
    /// restore brings its history back too.
    static func trash(id: String, now: Date = Date()) {
        SpotlightIndexer.remove(id)
        let json = trashDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: json)
        try? FileManager.default.moveItem(at: designsDir.appendingPathComponent("\(id).json"), to: json)
        // The file's own modification date is the deletion date: no index
        // to keep in step, and a move preserves the old date otherwise.
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: json.path)
        let thumb = trashDir.appendingPathComponent("\(id).jpg")
        try? FileManager.default.removeItem(at: thumb)
        try? FileManager.default.moveItem(at: thumbsDir.appendingPathComponent("\(id).jpg"), to: thumb)
    }

    static func restore(id: String) {
        defer { if let design = load(id: id) { SpotlightIndexer.index(design) } }
        try? FileManager.default.moveItem(at: trashDir.appendingPathComponent("\(id).json"),
                                          to: designsDir.appendingPathComponent("\(id).json"))
        try? FileManager.default.moveItem(at: trashDir.appendingPathComponent("\(id).jpg"),
                                          to: thumbsDir.appendingPathComponent("\(id).jpg"))
    }

    /// What is in the trash, most recently deleted first. `updatedAt` on
    /// each entry is the deletion time, which is what the list shows.
    /// A design that no longer reads is listed too, as on the shelf, so it
    /// can be restored and mended from a version, or purged with the rest.
    static func trashed() -> [RecentDesign] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: trashDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        let stamps = thumbnailStamps(trashed: true)
        var result: [RecentDesign] = []
        for url in files where url.pathExtension == "json" {
            let deleted = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            guard let data = try? Data(contentsOf: url),
                  let design = try? JSONDecoder().decode(Design.self, from: data) else {
                let id = url.deletingPathExtension().lastPathComponent
                result.append(RecentDesign(
                    id: id, title: damagedTitle, width: 0, height: 0, pages: 0,
                    updatedAt: deleted.timeIntervalSince1970 * 1000,
                    thumbnailStamp: stamps[id], damaged: true))
                continue
            }
            result.append(RecentDesign(
                id: design.id, title: design.title,
                width: design.width, height: design.height,
                pages: design.pages.count, updatedAt: deleted.timeIntervalSince1970 * 1000,
                thumbnailStamp: stamps[design.id]))
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Delete for good whatever has sat in the trash past the retention.
    /// Returns the ids it removed.
    @discardableResult
    static func purgeTrash(now: Date = Date()) -> [String] {
        let cutoff = now.timeIntervalSince1970 * 1000 - trashRetention * 1000
        let stale = trashed().filter { $0.updatedAt < cutoff }.map(\.id)
        for id in stale { deleteTrashed(id: id) }
        return stale
    }

    static func emptyTrash() {
        for entry in trashed() { deleteTrashed(id: entry.id) }
    }

    /// What emptying Recently deleted asks first, as the Android twin asks
    /// it: "Delete 3 designs forever?", then `cannotBeUndone`.
    static func emptyTrashQuestion(count: Int) -> String {
        "Delete \(count) \(count == 1 ? "design" : "designs") forever?"
    }

    static let cannotBeUndone = "This can't be undone."

    // MARK: search and sort

    enum Sort: String, CaseIterable, Identifiable {
        case recent, name, largest
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recent: return "Last edited"
            case .name: return "Name"
            case .largest: return "Most pages"
            }
        }
    }

    /// The recents that match a query, in an order. Matching is on the
    /// title, case- and diacritic-insensitively, and on the size ("1080")
    /// because that is how people remember a design they never named.
    /// Every folder in use, alphabetically.
    static func folders(in designs: [RecentDesign]) -> [String] {
        Array(Set(designs.compactMap(\.folder))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Files a design under a folder — nil or blank takes it out of one.
    /// Filing is not an edit, so the design's edit time stays.
    @discardableResult
    static func move(id: String, toFolder folder: String?) -> Bool {
        guard var design = load(id: id) else { return false }
        design.folder = folderName(folder)
        return save(design)
    }

    /// The designs in a folder (nil is every folder), then the query and sort.
    static func filter(_ designs: [RecentDesign], query: String, sort: Sort, folder: String?) -> [RecentDesign] {
        let inFolder = folder == nil ? designs : designs.filter { $0.folder == folder }
        return filter(inFolder, query: query, sort: sort)
    }

    static func filter(_ designs: [RecentDesign], query: String, sort: Sort = .recent) -> [RecentDesign] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        var matched = designs
        if !needle.isEmpty {
            matched = designs.filter { d in
                d.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || "\(Int(d.width))×\(Int(d.height))".contains(needle)
                    || "\(Int(d.width))x\(Int(d.height))".contains(needle)
            }
        }
        switch sort {
        case .recent:
            return matched.sorted { $0.updatedAt > $1.updatedAt }
        case .name:
            return matched.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .largest:
            return matched.sorted { $0.pages != $1.pages ? $0.pages > $1.pages : $0.updatedAt > $1.updatedAt }
        }
    }

    // MARK: starters

    static let startersKey = "canvia.starters.seeded"

    /// On the very first launch, two sample designs, so the home screen
    /// shows what a finished design looks like and there is something to
    /// open, poke at and undo. Once, ever: deleting them must not bring
    /// them back.
    @discardableResult
    static func seedStartersIfNeeded(defaults: UserDefaults = .standard,
                                     templates: [Template] = ContentLibrary.templates,
                                     now: Date = Date()) -> [Design] {
        guard !defaults.bool(forKey: startersKey) else { return [] }
        defaults.set(true, forKey: startersKey)
        guard recents().isEmpty else { return [] }
        var seeded: [Design] = []
        for (n, template) in templates.prefix(2).enumerated() {
            var design = template.instantiate()
            design.title = "Sample: \(template.name)"
            // A moment apart, so the two sort predictably.
            design.updatedAt = now.timeIntervalSince1970 * 1000 - Double(n) * 1000
            save(design)
            seeded.append(design)
        }
        return seeded
    }

    // MARK: version history

    /// One saved state of a design, kept so an edit made an hour ago can be
    /// walked back after undo has long since been pushed off the stack.
    struct Version: Identifiable, Equatable {
        var id: String { url.lastPathComponent }
        var url: URL
        var savedAt: Date
        var pages: Int
        var elements: Int
    }

    /// How many versions a design keeps. Thirty at a few kilobytes each is
    /// nothing; a thousand is a directory listing that takes a second.
    static let versionLimit = 30

    /// The least time between two versions of the same design. Autosave runs
    /// 900ms after every edit, and a version per edit would be undo with a
    /// worse interface.
    static var versionInterval: TimeInterval = 120

    private static func historyDir(for id: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    /// Record the design as a version, if it has changed since the last one
    /// and enough time has passed. Returns whether a version was written.
    ///
    /// Content-deduplicated, so saving the same document twice records it
    /// once; and rate-limited, so a burst of edits records the state at the
    /// end of the burst rather than every keystroke of it.
    @discardableResult
    static func snapshot(_ design: Design, force: Bool = false, now: Date = Date()) -> Bool {
        // Sorted keys, so encoding the same document twice gives the same
        // bytes. JSONEncoder's default order is whatever the dictionary
        // hashes to that run, and the dedup below compares bytes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(design) else { return false }
        let dir = historyDir(for: design.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing = versions(for: design.id)
        if let latest = existing.first {
            if !force, now.timeIntervalSince(latest.savedAt) < versionInterval { return false }
            if let last = try? Data(contentsOf: latest.url), last == data { return false }
        }
        let name = String(format: "%.3f", now.timeIntervalSince1970)
        // Whole or not at all, as a save is: a version is what a damaged
        // design is restored from.
        guard (try? data.write(to: dir.appendingPathComponent("\(name).json"), options: .atomic)) != nil else {
            return false
        }
        // Oldest out once past the limit, by the time in each name, as the
        // Android twin does: a version that no longer reads ages out with
        // the rest rather than staying for good.
        for stale in versionFiles(in: dir).dropFirst(versionLimit) {
            try? FileManager.default.removeItem(at: stale)
        }
        return true
    }

    /// The version files in a history folder, newest first by the time in
    /// their names, whether or not they still read.
    private static func versionFiles(in dir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url -> (url: URL, stamp: Double)? in
            guard url.pathExtension == "json",
                  let stamp = Double(url.deletingPathExtension().lastPathComponent) else { return nil }
            return (url, stamp)
        }
        .sorted { $0.stamp > $1.stamp }
        .map { $0.url }
    }

    /// Newest first.
    static func versions(for id: String) -> [Version] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: historyDir(for: id), includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> Version? in
            guard let stamp = Double(url.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: url),
                  let design = try? JSONDecoder().decode(Design.self, from: data) else { return nil }
            return Version(url: url, savedAt: Date(timeIntervalSince1970: stamp),
                           pages: design.pages.count,
                           elements: design.pages.reduce(0) { $0 + $1.elements.count })
        }
        .sorted { $0.savedAt > $1.savedAt }
    }

    static func load(version: Version) -> Design? {
        guard let data = try? Data(contentsOf: version.url),
              var design = try? JSONDecoder().decode(Design.self, from: data) else { return nil }
        design.normalizeTextHeights()
        return design
    }

    static func clearVersions(for id: String) {
        try? FileManager.default.removeItem(at: historyDir(for: id))
    }

    /// The launch sweep: photos, soundtracks and clips nothing uses any
    /// more, with every design, trashed design and kept version read once
    /// for all three. Each sweep used to read the whole library again for
    /// itself — three full passes of decoding before the first frame, where
    /// the Android twin makes one.
    ///
    /// Every store's candidates are still listed before a single design is
    /// read, as each sweep always listed its own, so a file stored while the
    /// designs are being read is never among them and can never be taken
    /// for an orphan. Only safe at launch, for the reasons each sweep gives.
    ///
    /// On the main thread still. Designs are swapped in whole now, so none
    /// can be read as half a file; but a sweep on another thread could still
    /// read a design's old file while the editor saves a photo into its new
    /// one, and take that photo for an orphan.
    ///
    /// Not at all while any design, live or trashed, no longer reads: what a
    /// damaged design uses cannot be known, and its photos have to still be
    /// there when it is restored from a version. A version that no longer
    /// reads is passed over, as it can never be restored.
    static func pruneUnusedFiles(pasteboard: UIPasteboard = .general) {
        let photos = mediaCandidates()
        let tracks = AudioStore.all()
        let clips = VideoStore.all()
        guard photos?.isEmpty == false || !tracks.isEmpty || !clips.isEmpty else { return }
        guard let designs = everyDesign() else { return }
        if let photos { pruneUnusedMedia(photos, designs: designs, pasteboard: pasteboard) }
        pruneUnusedAudio(tracks, designs: designs)
        pruneUnusedVideos(clips, designs: designs, pasteboard: pasteboard)
    }

    /// The photo files there are, or nil when the folder cannot be read.
    private static func mediaCandidates() -> [URL]? {
        try? FileManager.default.contentsOfDirectory(at: MediaStore.directory, includingPropertiesForKeys: nil)
    }

    /// Delete uploaded photos no design references any more.
    ///
    /// Media files outlive the designs that used them: deleting a design
    /// removes its JSON and thumbnail but not the pictures it embedded, so
    /// Documents/media grows without bound. Only safe to run at launch, when
    /// no editor holds a design that has added media but not yet saved.
    static func pruneUnusedMedia(pasteboard: UIPasteboard = .general) {
        // The candidates are listed before a single reference is read, so a
        // photo stored while the references are being gathered is not among
        // them and can never be taken for an orphan.
        guard let files = mediaCandidates(), let designs = everyDesign() else { return }
        pruneUnusedMedia(files, designs: designs, pasteboard: pasteboard)
    }

    /// The photo sweep over `files`, listed before `designs` were read.
    /// Your uploads stay, used or not, and so does anything starred: they
    /// are in the Add sheet to use again.
    private static func pruneUnusedMedia(_ files: [URL], designs: [Design], pasteboard: UIPasteboard) {
        // The designs, every version kept of them — a photo taken out of a
        // design is still in its older versions, and restoring one must
        // bring the photo back — and what is kept outside them.
        let referenced = photos(in: designs).union(photosKeptOutsideDesigns(pasteboard: pasteboard))
        let kept = Uploads.kept()
        for url in files where MediaStore.extensions.contains(url.pathExtension) {
            let id = url.deletingPathExtension().lastPathComponent
            if !referenced.contains(id) && !kept.contains(id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// The MediaStore id a "media:" source shows.
    private static func photoID(_ src: String?) -> String? {
        guard let src, src.hasPrefix("media:") else { return nil }
        return String(src.dropFirst(6))
    }

    private static func collectPhotos(in elements: [Element], into found: inout Set<String>) {
        for el in elements {
            if let id = photoID(el.src) { found.insert(id) }
            // A shape filled with a photo uses it too.
            if let id = photoID(el.fill?.src) { found.insert(id) }
        }
    }

    private static func collectPhotos(on page: Page, into found: inout Set<String>) {
        if case .image(let src) = page.background, let id = photoID(src) { found.insert(id) }
        collectPhotos(in: page.elements, into: &found)
    }

    /// The photos these designs show — as a picture, filling a shape, or
    /// behind a page — by MediaStore id.
    static func photos(in designs: [Design]) -> Set<String> {
        var found = Set<String>()
        for design in designs {
            for page in design.pages { collectPhotos(on: page, into: &found) }
        }
        return found
    }

    /// The photos kept outside the designs: what the person keeps across
    /// them — the brand's logos and the components' pictures — and what was
    /// cut or copied but not yet pasted. The pasteboard outlives a launch,
    /// and a photo cut from a design is referenced nowhere else until it is
    /// pasted back; the Android twin keeps these too. Read only when our own
    /// types are there, so someone else's copied text never brings up the
    /// paste prompt.
    static func photosKeptOutsideDesigns(pasteboard: UIPasteboard) -> Set<String> {
        var found = Set<String>()
        for src in BrandKit.load().logos { if let id = photoID(src) { found.insert(id) } }
        for component in Components.load() { collectPhotos(in: component.elements, into: &found) }
        if ElementClipboard.hasElements(in: pasteboard), let elements = ElementClipboard.read(from: pasteboard) {
            collectPhotos(in: elements, into: &found)
        }
        if PageClipboard.hasPage(in: pasteboard), let payload = PageClipboard.paste(from: pasteboard) {
            collectPhotos(on: payload.page, into: &found)
        }
        return found
    }

    /// Delete soundtrack files no design plays any more.
    ///
    /// Removing or changing a design's soundtrack leaves its file behind: a
    /// duplicate of the design, one of its saved versions or the undo step
    /// may still name the same id, and deleting it there and then took the
    /// music out of their videos without a word. At launch there is no undo
    /// step left, so a file no saved, versioned or trashed design names can
    /// go. Only safe at launch, for the same reason as the media sweep.
    static func pruneUnusedAudio() {
        // Listed first, as with the photos: a file stored while the designs
        // are being read is not a candidate, so it is never taken for an
        // orphan.
        let stored = AudioStore.all()
        guard !stored.isEmpty, let designs = everyDesign() else { return }
        pruneUnusedAudio(stored, designs: designs)
    }

    /// The soundtrack sweep over `stored`, listed before `designs` were
    /// read. Music brought in stays, as the photos do.
    private static func pruneUnusedAudio(_ stored: [String], designs: [Design]) {
        guard !stored.isEmpty else { return }
        let playing = soundtracks(in: designs)
        let kept = Uploads.kept()
        for id in stored where !playing.contains(id) && !kept.contains(id) {
            AudioStore.delete(id)
        }
    }

    /// Delete clips no design shows any more.
    ///
    /// Deleting a clip's element, or its design, left the movie file behind
    /// for good: nothing ever swept the clips. At launch a clip no saved,
    /// versioned or trashed design shows — nor a component, nor a brand
    /// logo, nor what was cut or copied but not yet pasted — can go. Listed
    /// first, as the photos are, so a clip stored while the designs are
    /// being read is never taken for an orphan.
    static func pruneUnusedVideos(pasteboard: UIPasteboard = .general) {
        let stored = VideoStore.all()
        guard !stored.isEmpty, let designs = everyDesign() else { return }
        pruneUnusedVideos(stored, designs: designs, pasteboard: pasteboard)
    }

    /// The clip sweep over `stored`, listed before `designs` were read.
    /// Clips brought in stay, as the photos do.
    private static func pruneUnusedVideos(_ stored: [String], designs: [Design], pasteboard: UIPasteboard) {
        guard !stored.isEmpty else { return }
        let shown = clips(in: designs).union(clipsKeptOutsideDesigns(pasteboard: pasteboard))
        let kept = Uploads.kept()
        for id in stored where !shown.contains(id) && !kept.contains(id) {
            VideoStore.delete(id)
        }
    }

    /// The VideoStore id a "video:" source shows, at any moment.
    private static func clipID(_ src: String?) -> String? {
        src.flatMap { VideoStore.split($0)?.id }
    }

    /// A clip shows as a photo, and also wherever a photo can: filling a
    /// shape — the colour sheet offers every clip as a Photo fill — or, in a
    /// design from the Android twin, behind a page. A text fill never draws
    /// a picture, but keeping its clip costs nothing.
    private static func collectClips(in elements: [Element], into found: inout Set<String>) {
        for el in elements {
            for src in [el.src, el.fill?.src, el.textFill?.src] {
                if let id = clipID(src) { found.insert(id) }
            }
        }
    }

    private static func collectClips(on page: Page, into found: inout Set<String>) {
        if case .image(let src) = page.background, let id = clipID(src) { found.insert(id) }
        collectClips(in: page.elements, into: &found)
    }

    /// The clips these designs show, by VideoStore id.
    static func clips(in designs: [Design]) -> Set<String> {
        var found = Set<String>()
        for design in designs {
            for page in design.pages { collectClips(on: page, into: &found) }
        }
        return found
    }

    /// The clips kept outside the designs: in a component, as a brand logo —
    /// the Brand kit offers a design's clips as logos, as it does its
    /// photos, and a logo outlives every design it came from — or cut or
    /// copied but not yet pasted.
    static func clipsKeptOutsideDesigns(pasteboard: UIPasteboard) -> Set<String> {
        var found = Set<String>()
        for component in Components.load() { collectClips(in: component.elements, into: &found) }
        for src in BrandKit.load().logos { if let id = clipID(src) { found.insert(id) } }
        if ElementClipboard.hasElements(in: pasteboard), let elements = ElementClipboard.read(from: pasteboard) {
            collectClips(in: elements, into: &found)
        }
        if PageClipboard.hasPage(in: pasteboard), let payload = PageClipboard.paste(from: pasteboard) {
            collectClips(on: payload.page, into: &found)
        }
        return found
    }

    /// The AudioStore ids these designs play under their videos.
    static func soundtracks(in designs: [Design]) -> Set<String> {
        Set(designs.compactMap { $0.motion?.soundtrack })
    }

    // MARK: uploads in use

    /// What deleting an upload would mean: how many designs, on the shelf
    /// or in Recently deleted, use it, and whether any design, kept version
    /// or step Undo can go back to still holds its file.
    struct UploadUse: Equatable, Sendable {
        var designs: Int
        var held: Bool
    }

    /// Whether this design shows the upload, or plays it.
    static func uses(_ design: Design, upload id: String, kind: Uploads.Kind) -> Bool {
        switch kind {
        case .image: return photos(in: [design]).contains(id)
        case .video: return clips(in: [design]).contains(id)
        case .audio: return design.motion?.soundtrack == id
        }
    }

    /// Every design is read for this, and every version, so it belongs off
    /// the main thread. `editing` is the design open in the editor, as it
    /// stands and as undo and redo can bring it back: counted as it is on
    /// screen rather than as last saved, and holding what it held. A design
    /// that does not read may hold it too, so then it is held; a version
    /// that does not read can never come back, so holds nothing.
    static func use(ofUpload id: String, kind: Uploads.Kind, editing: [Design] = []) -> UploadUse {
        var byID: [String: Design] = [:]
        var unreadable = false
        for dir in [designsDir, trashDir] {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in files where isDesignFile(url) {
                guard let data = try? Data(contentsOf: url),
                      let design = try? JSONDecoder().decode(Design.self, from: data) else {
                    unreadable = true
                    continue
                }
                if byID[design.id] == nil || dir == designsDir { byID[design.id] = design }
            }
        }
        if let open = editing.first { byID[open.id] = open }
        let count = byID.values.filter { uses($0, upload: id, kind: kind) }.count
        guard count == 0, !unreadable else { return UploadUse(designs: count, held: true) }
        let held = (allVersions() + editing).contains { uses($0, upload: id, kind: kind) }
        return UploadUse(designs: 0, held: held)
    }

    /// Whether anything kept outside the designs holds an upload: a brand
    /// logo, a component, or what was cut or copied. On the main thread,
    /// where the pasteboard is read.
    static func uploadKeptOutsideDesigns(_ id: String, kind: Uploads.Kind,
                                         pasteboard: UIPasteboard = .general) -> Bool {
        switch kind {
        case .image: return photosKeptOutsideDesigns(pasteboard: pasteboard).contains(id)
        case .video: return clipsKeptOutsideDesigns(pasteboard: pasteboard).contains(id)
        case .audio: return false
        }
    }

    /// Every design, live and trashed, and every kept version of each — or
    /// nil when a design's file no longer reads, and so what it uses
    /// cannot be known. Each sweep keeps what these use.
    private static func everyDesign() -> [Design]? {
        guard let designs = allDesigns() else { return nil }
        return designs + allVersions()
    }

    /// Every kept version of every design that still reads. One that does
    /// not can never be restored, so what it used is not kept for it, and
    /// it ages out of its history as the others do.
    private static func allVersions() -> [Design] {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var versions: [Design] = []
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            versions += files.filter { $0.pathExtension == "json" }.compactMap { url -> Design? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Design.self, from: data)
            }
        }
        return versions
    }

    /// Live and trashed both: a design in the trash can come back, and its
    /// photos have to still be there when it does. Nil when one does not
    /// read.
    private static func allDesigns() -> [Design]? {
        var designs: [Design] = []
        for dir in [designsDir, trashDir] {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            guard let read = decodeAll(files.filter { isDesignFile($0) }) else { return nil }
            designs += read
        }
        return designs
    }

    /// The designs in these files, or nil at the first that does not read.
    private static func decodeAll(_ files: [URL]) -> [Design]? {
        var designs: [Design] = []
        for url in files {
            guard let data = try? Data(contentsOf: url),
                  let design = try? JSONDecoder().decode(Design.self, from: data) else { return nil }
            designs.append(design)
        }
        return designs
    }

    // MARK: damaged designs

    /// Brings a design whose file no longer reads back from the newest of
    /// its versions that does, under the same id, so its card is the
    /// design again. Its old picture goes with the damaged file, as it may
    /// show something the version does not. Edited now, as the Android twin
    /// stamps it, so it sorts first among the designs. Nil when no version
    /// reads, or the design could not be written.
    @discardableResult
    static func restoreLastVersion(of id: String, now: Date = Date()) -> Design? {
        // Newest first, and only those that read.
        for version in versions(for: id) {
            guard var design = load(version: version) else { continue }
            design.id = id
            design.updatedAt = now.timeIntervalSince1970 * 1000
            guard save(design) else { return nil }
            try? FileManager.default.removeItem(at: thumbnailURL(for: id))
            return design
        }
        return nil
    }

    /// The designs on the shelf, most recently edited first; see shelf().
    static func recents() -> [RecentDesign] {
        shelf().designs
    }
}
