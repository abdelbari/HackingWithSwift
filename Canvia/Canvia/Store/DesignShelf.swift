// What Home shows of each design — its title, size, pages, dates and
// folder — kept in designs/shelf.json, so Home no longer decodes every
// design each time it appears. An entry holds while its design file's
// modification time is the one it was read at; any other, or none, and that
// one design is read again. A file that has gone takes its entry with it.
// The Android twin keeps the same file, with the same keys, in its own
// designs folder.
//
// So rename, duplicate, move to a folder, trash and restore need do nothing
// here: each writes, moves or removes the design's file, and the next read
// of the shelf sees it. And a cache is all it is: missing or unreadable, it
// is rebuilt from the designs, so nothing in it is worth keeping for its
// own sake.

import Foundation

extension DesignLibrary {

    /// The cache's name in the designs folder, which every listing of that
    /// folder leaves out: it is not a design.
    static let shelfFileName = "shelf.json"

    /// What a design file that no longer reads as one is called on its card.
    static let damagedTitle = "Damaged design"

    /// One design's summary, as shelf.json keeps it.
    struct ShelfEntry: Codable, Equatable {
        var id: String
        var title: String
        var width: Double
        var height: Double
        var pages: Int
        var updatedAt: Double
        var createdAt: Double
        var folder: String?
        /// The design file's modification time when this was read from it,
        /// in epoch milliseconds.
        var modified: Double

        init(_ design: Design, id: String, modified: Double) {
            self.id = id
            title = design.title
            width = design.width
            height = design.height
            pages = design.pages.count
            updatedAt = design.updatedAt
            createdAt = design.createdAt
            folder = design.folder
            self.modified = modified
        }
    }

    /// Home's view of the designs folder: the designs, and the files that no
    /// longer read as one, each as a card.
    struct Shelf: Sendable {
        var designs: [RecentDesign] = []
        var damaged: [RecentDesign] = []
    }

    /// One read or rewrite of shelf.json at a time: Home reads it off the
    /// main thread while the app, Siri or a quick action may read it on it.
    private static let shelfLock = NSLock()

    private static var shelfURL: URL { designsDir.appendingPathComponent(shelfFileName) }

    /// Whether a file in the designs folder is a design's: its JSON, and not
    /// the shelf cache beside them.
    static func isDesignFile(_ url: URL) -> Bool {
        url.pathExtension == "json" && url.lastPathComponent != shelfFileName
    }

    /// The designs on the shelf, most recently edited first, and the files
    /// that no longer decode. Only a design whose file changed since the
    /// cache last saw it is read.
    static func shelf() -> Shelf {
        // Listed with their modification times before any is read, so the
        // time kept with an entry is never newer than what was read for it:
        // a design saved meanwhile is read again next time, never missed.
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: designsDir, includingPropertiesForKeys: keys)) ?? []
        let stamps = thumbnailStamps(trashed: false)

        shelfLock.lock()
        defer { shelfLock.unlock() }
        let cached = readShelf()
        var entries: [ShelfEntry] = []
        var shelf = Shelf()
        var rebuilt = false
        for url in files where isDesignFile(url) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile != false else { continue }
            let id = url.deletingPathExtension().lastPathComponent
            let modified = (values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000
            // Within a microsecond rather than to the bit, as the time is a
            // fraction of a millisecond that has been through JSON.
            if let hit = cached[id], abs(hit.modified - modified) < 0.001 {
                entries.append(hit)
                continue
            }
            rebuilt = true
            if let data = try? Data(contentsOf: url),
               let design = try? JSONDecoder().decode(Design.self, from: data) {
                entries.append(ShelfEntry(design, id: id, modified: modified))
            } else {
                shelf.damaged.append(RecentDesign(
                    id: id, title: damagedTitle, width: 0, height: 0, pages: 0,
                    updatedAt: modified, thumbnailStamp: stamps[id], damaged: true))
            }
        }
        // Rewritten when an entry was read again or a file has gone.
        if rebuilt || entries.count != cached.count {
            writeShelf(entries)
        }
        shelf.designs = entries.map { entry in
            RecentDesign(id: entry.id, title: entry.title, width: entry.width, height: entry.height,
                         pages: entry.pages, updatedAt: entry.updatedAt, folder: entry.folder,
                         thumbnailStamp: stamps[entry.id])
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        return shelf
    }

    /// The cache by design id; empty when there is none or it cannot be
    /// read, so every design is read afresh.
    private static func readShelf() -> [String: ShelfEntry] {
        guard let data = try? Data(contentsOf: shelfURL),
              let entries = try? JSONDecoder().decode([ShelfEntry].self, from: data) else { return [:] }
        return Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func writeShelf(_ entries: [ShelfEntry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(entries.sorted { $0.id < $1.id }) else { return }
        try? data.write(to: shelfURL, options: .atomic)
    }
}
