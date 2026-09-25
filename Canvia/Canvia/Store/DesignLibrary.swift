// Persistence: designs are JSON files in Documents/designs, thumbnails are
// JPEGs in Documents/thumbs. The recents list is derived from the files.

import UIKit

struct RecentDesign: Identifiable {
    var id: String
    var title: String
    var width: Double
    var height: Double
    var pages: Int
    var updatedAt: Double
    var thumbnail: UIImage?
    var folder: String? = nil
}

enum DesignLibrary {

    private static var designsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("designs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var thumbsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func save(_ design: Design) -> Bool {
        do {
            let data = try JSONEncoder().encode(design)
            try data.write(to: designsDir.appendingPathComponent("\(design.id).json"))
            SpotlightIndexer.index(design)
            return true
        } catch {
            return false
        }
    }

    static func saveThumbnail(_ image: UIImage, for id: String) {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }
        try? data.write(to: thumbsDir.appendingPathComponent("\(id).jpg"))
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

    private static var trashDir: URL {
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
    static func trashed() -> [RecentDesign] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: trashDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var result: [RecentDesign] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let design = try? JSONDecoder().decode(Design.self, from: data) else { continue }
            let deleted = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            let thumb = (try? Data(contentsOf: trashDir.appendingPathComponent("\(design.id).jpg")))
                .flatMap(UIImage.init(data:))
            result.append(RecentDesign(
                id: design.id, title: design.title,
                width: design.width, height: design.height,
                pages: design.pages.count, updatedAt: deleted.timeIntervalSince1970 * 1000,
                thumbnail: thumb))
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
        let name = folder?.trimmingCharacters(in: .whitespaces)
        design.folder = (name?.isEmpty ?? true) ? nil : name
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
        guard (try? data.write(to: dir.appendingPathComponent("\(name).json"))) != nil else {
            return false
        }
        // Oldest out once past the limit.
        let all = versions(for: design.id)
        for stale in all.dropFirst(versionLimit) {
            try? FileManager.default.removeItem(at: stale.url)
        }
        return true
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
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: MediaStore.directory, includingPropertiesForKeys: nil) else { return }
        var referenced = Set<String>()
        let mediaID: (String) -> String? = { src in
            src.hasPrefix("media:") ? String(src.dropFirst(6)) : nil
        }
        func keep(_ elements: [Element]) {
            for el in elements {
                if let src = el.src, let id = mediaID(src) { referenced.insert(id) }
                // A shape filled with a photo uses it too.
                if let src = el.fill?.src, let id = mediaID(src) { referenced.insert(id) }
            }
        }
        func keepPage(_ page: Page) {
            if case .image(let src) = page.background, let id = mediaID(src) {
                referenced.insert(id)
            }
            keep(page.elements)
        }
        // The designs, every version kept of them — a photo taken out of a
        // design is still in its older versions, and restoring one must
        // bring the photo back — and what the person keeps across designs:
        // the brand's logos and the components' pictures.
        for design in allDesigns() + allVersions() {
            for page in design.pages { keepPage(page) }
        }
        for src in BrandKit.load().logos { if let id = mediaID(src) { referenced.insert(id) } }
        for component in Components.load() { keep(component.elements) }
        // And what was cut or copied but not yet pasted. The pasteboard
        // outlives a launch, and a photo cut from a design is referenced
        // nowhere else until it is pasted back; the Android twin keeps these
        // too. Read only when our own types are there, so someone else's
        // copied text never brings up the paste prompt.
        if ElementClipboard.hasElements(in: pasteboard), let elements = ElementClipboard.read(from: pasteboard) {
            keep(elements)
        }
        if PageClipboard.hasPage(in: pasteboard), let payload = PageClipboard.paste(from: pasteboard) {
            keepPage(payload.page)
        }
        for url in files where MediaStore.extensions.contains(url.pathExtension) {
            let id = url.deletingPathExtension().lastPathComponent
            if !referenced.contains(id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
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
        guard !stored.isEmpty else { return }
        let playing = soundtracks(in: allDesigns() + allVersions())
        for id in stored where !playing.contains(id) {
            AudioStore.delete(id)
        }
    }

    /// Delete clips no design shows any more.
    ///
    /// Deleting a clip's element, or its design, left the movie file behind
    /// for good: nothing ever swept the clips. At launch a clip no saved,
    /// versioned or trashed design shows — nor a component, nor what was cut
    /// or copied but not yet pasted — can go. Listed first, as the photos
    /// are, so a clip stored while the designs are being read is never taken
    /// for an orphan.
    static func pruneUnusedVideos(pasteboard: UIPasteboard = .general) {
        let stored = VideoStore.all()
        guard !stored.isEmpty else { return }
        var shown = Set<String>()
        func keep(_ elements: [Element]) {
            for el in elements {
                if let src = el.src, let parts = VideoStore.split(src) { shown.insert(parts.id) }
            }
        }
        for design in allDesigns() + allVersions() {
            for page in design.pages { keep(page.elements) }
        }
        for component in Components.load() { keep(component.elements) }
        if ElementClipboard.hasElements(in: pasteboard), let elements = ElementClipboard.read(from: pasteboard) {
            keep(elements)
        }
        if PageClipboard.hasPage(in: pasteboard), let payload = PageClipboard.paste(from: pasteboard) {
            keep(payload.page.elements)
        }
        for id in stored where !shown.contains(id) {
            VideoStore.delete(id)
        }
    }

    /// The AudioStore ids these designs play under their videos.
    static func soundtracks(in designs: [Design]) -> Set<String> {
        Set(designs.compactMap { $0.motion?.soundtrack })
    }

    /// Every kept version of every design.
    private static func allVersions() -> [Design] {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history", isDirectory: true)
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return dirs.flatMap { dir -> [Design] in
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
            return files.filter { $0.pathExtension == "json" }.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Design.self, from: data)
            }
        }
    }

    /// Live and trashed both: a design in the trash can come back, and its
    /// photos have to still be there when it does.
    private static func allDesigns() -> [Design] {
        [designsDir, trashDir].flatMap { dir -> [Design] in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return [] }
            return files.filter { $0.pathExtension == "json" }.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Design.self, from: data)
            }
        }
    }

    static func recents() -> [RecentDesign] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: designsDir, includingPropertiesForKeys: nil) else { return [] }
        var result: [RecentDesign] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let design = try? JSONDecoder().decode(Design.self, from: data) else { continue }
            let thumbURL = thumbsDir.appendingPathComponent("\(design.id).jpg")
            let thumb = (try? Data(contentsOf: thumbURL)).flatMap(UIImage.init(data:))
            result.append(RecentDesign(
                id: design.id, title: design.title,
                width: design.width, height: design.height,
                pages: design.pages.count, updatedAt: design.updatedAt,
                thumbnail: thumb, folder: design.folder))
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }
}
