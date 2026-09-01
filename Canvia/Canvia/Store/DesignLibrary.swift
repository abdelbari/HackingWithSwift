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
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Design.self, from: data)
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
