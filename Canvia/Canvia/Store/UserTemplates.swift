// Your own templates: a design saved as a template from the editor's More
// menu ("Save as template…"), every page of it, to start new designs from.
//
// Each is kept whole in Documents/templates_user/<id>.json — a design as
// the shelf keeps one, with fresh ids throughout, its id the template's —
// beside a picture of its first page (<id>.jpg), and listed, newest saved
// first, in Documents/usertemplates.json:
//
//   [{"id", "name", "category", "width", "height", "pageCount", "updatedAt"}]
//
// as the Android twin keeps them. The photos and clips a template shows
// are kept by the launch sweep as a design's are. Using one makes a new
// design from a fresh copy of it, every id new again.

import UIKit

/// A template of your own, as usertemplates.json lists it.
struct UserTemplate: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var category: String
    var width: Double
    var height: Double
    var pageCount: Int
    /// When it was saved or last updated, in epoch milliseconds.
    var updatedAt: Double

    /// "Poster · 1080 × 1920 · 3 pages".
    var caption: String {
        let size = "\(Int(width)) × \(Int(height))"
        return pageCount == 1 ? "\(category) · \(size)" : "\(category) · \(size) · \(pageCount) pages"
    }
}

extension UserTemplate {
    /// Lenient, as an index from another build may be: an entry without an
    /// id cannot be found and does not read; the rest take defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Template"
        category = (try? c.decode(String.self, forKey: .category)) ?? UserTemplates.defaultCategory
        width = (try? c.decode(Double.self, forKey: .width)) ?? 1080
        height = (try? c.decode(Double.self, forKey: .height)) ?? 1080
        pageCount = (try? c.decode(Int.self, forKey: .pageCount)) ?? 1
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
    }
}

enum UserTemplates {

    static let folderName = "templates_user"
    static let indexName = "usertemplates.json"
    /// Where a template goes when no category is typed, as on the Android
    /// twin.
    static let defaultCategory = "Personal"
    /// What Home's chip and section, and the Templates panel, call them.
    static let sectionTitle = "Your templates"

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var indexURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(indexName)
    }

    static func fileURL(for id: String) -> URL { directory.appendingPathComponent("\(id).json") }
    static func thumbnailURL(for id: String) -> URL { directory.appendingPathComponent("\(id).jpg") }

    // MARK: reading

    /// Every template listed whose file is here, in the index's order.
    static func all() -> [UserTemplate] {
        let folder = directory
        return index().filter {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("\($0.id).json").path)
        }
    }

    /// The index as written: an entry that does not read is passed over.
    static func index() -> [UserTemplate] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return read(data)
    }

    /// An index's entries, leniently.
    static func read(_ data: Data) -> [UserTemplate] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return raw.compactMap { item in
            guard let fields = item as? [String: Any],
                  let one = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
            return try? JSONDecoder().decode(UserTemplate.self, from: one)
        }
    }

    static func write(_ entries: [UserTemplate]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(entries) { try? data.write(to: indexURL, options: .atomic) }
    }

    /// A template's design, as saved.
    static func load(id: String) -> Design? {
        guard let data = try? Data(contentsOf: fileURL(for: id)),
              var design = try? JSONDecoder().decode(Design.self, from: data) else { return nil }
        design.normalizeTextHeights()
        return design
    }

    /// Every template's design that reads, for the launch sweep. One that
    /// does not read can never be used, so what it showed is not kept.
    static func designs() -> [Design] {
        all().compactMap { entry in
            guard let data = try? Data(contentsOf: fileURL(for: entry.id)) else { return nil }
            return try? JSONDecoder().decode(Design.self, from: data)
        }
    }

    /// Those made at exactly this size, for a size's starts.
    static func sized(_ entries: [UserTemplate], width: Double, height: Double) -> [UserTemplate] {
        entries.filter { $0.width == width && $0.height == height }
    }

    /// Those whose name or category holds the query; all for an empty one.
    static func matching(_ entries: [UserTemplate], query: String) -> [UserTemplate] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(needle) || $0.category.localizedCaseInsensitiveContains(needle)
        }
    }

    // MARK: making

    /// The name typed, trimmed; the design's own title when it is empty.
    static func name(_ typed: String, design: Design) -> String {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? design.title : name
    }

    /// The category typed, trimmed; "Personal" when it is empty.
    static func category(_ typed: String) -> String {
        let category = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return category.isEmpty ? defaultCategory : category
    }

    /// `design` as the template `id` keeps it: every page, fresh ids
    /// throughout (CopyResize.freshCopy, by Copies' rules), its id the
    /// template's, its title the template's name, in no folder, made `now`
    /// — in whole milliseconds, as the Android twin reads the index.
    static func templateDesign(_ design: Design, id: String, name: String, now: Date = Date()) -> Design {
        var out = CopyResize.freshCopy(of: design)
        out.id = id
        out.title = name
        out.titleAuto = false
        out.folder = nil
        out.createdAt = (now.timeIntervalSince1970 * 1000).rounded()
        out.updatedAt = out.createdAt
        return out
    }

    /// The index entry for a template's design.
    static func entry(for design: Design, category: String) -> UserTemplate {
        UserTemplate(id: design.id, name: design.title, category: category, width: design.width,
                     height: design.height, pageCount: design.pages.count, updatedAt: design.updatedAt)
    }

    /// `design` saved as a new template, listed first. Nil when it could
    /// not be written.
    @discardableResult
    static func save(_ design: Design, name: String, category: String, now: Date = Date()) -> UserTemplate? {
        let saved = templateDesign(design, id: UID.make("tpl"), name: name, now: now)
        guard write(design: saved) else { return nil }
        let listed = entry(for: saved, category: category)
        write([listed] + index().filter { $0.id != listed.id })
        return listed
    }

    /// The template `id` made again from `design`, every page, keeping its
    /// name, category and place in the list.
    @discardableResult
    static func update(_ id: String, from design: Design, now: Date = Date()) -> UserTemplate? {
        var entries = index()
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let saved = templateDesign(design, id: id, name: entries[i].name, now: now)
        guard write(design: saved) else { return nil }
        entries[i] = entry(for: saved, category: entries[i].category)
        write(entries)
        return entries[i]
    }

    /// A new name for a template, in the list and in its design; an empty
    /// one changes nothing.
    static func rename(_ id: String, to typed: String) {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var entries = index()
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].name = name
        write(entries)
        if var design = load(id: id) {
            design.title = name
            write(design: design)
        }
    }

    /// A template gone for good, its file, picture and entry. What it
    /// showed is swept at the next launch when nothing else uses it.
    static func delete(_ id: String) {
        write(index().filter { $0.id != id })
        try? FileManager.default.removeItem(at: fileURL(for: id))
        try? FileManager.default.removeItem(at: thumbnailURL(for: id))
    }

    /// A template stored as it is, keeping its id and dates — as a backup
    /// brings one back — listed first, or in its place when it is here.
    @discardableResult
    static func store(_ design: Design, category: String) -> Bool {
        guard write(design: design) else { return false }
        let listed = entry(for: design, category: category)
        var entries = index()
        if let i = entries.firstIndex(where: { $0.id == listed.id }) {
            entries[i] = listed
        } else {
            entries.insert(listed, at: 0)
        }
        write(entries)
        return true
    }

    @discardableResult
    private static func write(design: Design) -> Bool {
        do {
            let data = try JSONEncoder().encode(CustomFonts.synced(design, installed: FontStore.record))
            try data.write(to: fileURL(for: design.id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// A picture of the template's first page, as a design's card has.
    @MainActor
    static func writeThumbnail(for design: Design) {
        guard let image = DesignLibrary.thumbnailImage(for: design),
              let data = image.jpegData(compressionQuality: 0.7) else { return }
        try? data.write(to: thumbnailURL(for: design.id), options: .atomic)
    }

    /// The picture, when there is one.
    static func thumbnail(for id: String) -> UIImage? {
        UIImage(contentsOfFile: thumbnailURL(for: id).path)
    }

    // MARK: using

    /// A new design from the template: a fresh copy of every page, titled
    /// as the template is, in no folder, made `now`.
    static func newDesign(from template: Design, now: Date = Date()) -> Design {
        var design = CopyResize.freshCopy(of: template)
        design.folder = nil
        design.titleAuto = false
        design.createdAt = (now.timeIntervalSince1970 * 1000).rounded()
        design.updatedAt = design.createdAt
        return design
    }

    /// The template's pages as they land on a page `width` × `height` in
    /// the editor: fresh ids, each scaled to fit and centred by the rules a
    /// built-in template is fitted by (Template.fitted) — strokes keep
    /// their width, as on the Android twin — in the size of the page they
    /// land on rather than one of their own.
    static func pages(of template: Design, width: Double, height: Double) -> [Page] {
        template.pages.indices.map { index in
            var page = Copies.of(template.pages[index])
            let size = template.size(at: index)
            let ownWidth = Double(size.width), ownHeight = Double(size.height)
            if ownWidth > 0, ownHeight > 0 {
                let scale = min(width / ownWidth, height / ownHeight)
                let dx = (width - ownWidth * scale) / 2
                let dy = (height - ownHeight * scale) / 2
                page.elements = page.elements.map { Template.fitted($0, scale: scale, dx: dx, dy: dy) }
            }
            page.width = nil
            page.height = nil
            return page
        }
    }
}
