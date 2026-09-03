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

    static func delete(id: String) {
        try? FileManager.default.removeItem(at: designsDir.appendingPathComponent("\(id).json"))
        try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent("\(id).jpg"))
    }

    /// Delete uploaded photos no design references any more.
    ///
    /// Media files outlive the designs that used them: deleting a design
    /// removes its JSON and thumbnail but not the pictures it embedded, so
    /// Documents/media grows without bound. Only safe to run at launch, when
    /// no editor holds a design that has added media but not yet saved.
    static func pruneUnusedMedia() {
        var referenced = Set<String>()
        let mediaID: (String) -> String? = { src in
            src.hasPrefix("media:") ? String(src.dropFirst(6)) : nil
        }
        for design in allDesigns() {
            for page in design.pages {
                if case .image(let src) = page.background, let id = mediaID(src) {
                    referenced.insert(id)
                }
                for el in page.elements {
                    if let src = el.src, let id = mediaID(src) { referenced.insert(id) }
                }
            }
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: MediaStore.directory, includingPropertiesForKeys: nil) else { return }
        for url in files where MediaStore.extensions.contains(url.pathExtension) {
            let id = url.deletingPathExtension().lastPathComponent
            if !referenced.contains(id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func allDesigns() -> [Design] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: designsDir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Design.self, from: data)
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
                thumbnail: thumb))
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }
}
