// The room one design takes on this phone, as its Details sheet says it:
// its file — on the shelf or in Recently deleted — every version kept of
// it, and the photos, clips and songs it uses that no other design does,
// each counted once. Fonts of your own are left out: a font is the
// phone's, not a design's. Reads every design, so off the main thread. The
// Android twin's DesignStorage.

import Foundation

enum DesignStorage {

    /// `design`'s bytes here, measured from the files.
    static func bytes(of design: Design) -> Int64 {
        let id = design.id
        let live = DesignLibrary.designsDir.appendingPathComponent("\(id).json")
        let trashed = DesignLibrary.trashDir.appendingPathComponent("\(id).json")
        let file = FileManager.default.fileExists(atPath: live.path) ? live : trashed
        let own = StorageReport.bytes(of: file) + StorageReport.size(of: DesignLibrary.historyDir(for: id))
        let faces = FontStore.faces()
        let elsewhere = Set(Uploads.usageIndex(otherDesigns(than: id), faces: faces).keys)
        let used = Uploads.ids(usedBy: design, faces: faces)
        let alone = Uploads.all().filter { used.contains($0.id) && !elsewhere.contains($0.id) }
        return own + alone.reduce(0) { $0 + StorageReport.bytes(of: StorageReport.file(of: $1)) }
    }

    /// Every other design, on the shelf or in Recently deleted, that reads.
    private static func otherDesigns(than id: String) -> [Design] {
        [DesignLibrary.designsDir, DesignLibrary.trashDir].flatMap { dir -> [Design] in
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return files
                .filter { $0.pathExtension == "json" && $0.deletingPathExtension().lastPathComponent != id }
                .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Design.self, from: $0) } }
        }
    }
}
