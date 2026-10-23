// How much room Canvia takes, as Settings shows it, and the caches it can
// let go of. Measured from the folders themselves, away from the main
// thread.

import Foundation

struct StorageReport: Equatable, Sendable {
    /// The designs on the shelf and their pictures.
    var designs: Int64 = 0
    /// Every photo, clip and song the designs and uploads use.
    var photosAndClips: Int64 = 0
    /// Of those, the ones you brought in.
    var uploads: Int64 = 0
    /// Fonts of your own.
    var fonts: Int64 = 0
    /// Version history.
    var versions: Int64 = 0
    /// Your templates.
    var templates: Int64 = 0
    /// Recently deleted.
    var recentlyDeleted: Int64 = 0
    /// Exported files waiting to be shared, and other caches.
    var caches: Int64 = 0

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Every folder that counts as a cache: the exports written for the
    /// share sheet, in the temporary folder, and the system's caches.
    static var cacheFolders: [URL] {
        [FileManager.default.temporaryDirectory] + FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    }

    /// Everything in a folder and the folders in it, in bytes.
    static func size(of folder: URL) -> Int64 {
        guard let walk = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    private static func size(ofFile url: URL?) -> Int64 {
        guard let url else { return 0 }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// The room taken now. Reads every folder, so off the main thread.
    static func measure() -> StorageReport {
        var report = StorageReport()
        report.designs = size(of: DesignLibrary.designsDir) + size(of: DesignLibrary.thumbsDir)
        report.photosAndClips = size(of: MediaStore.directory) + size(of: VideoStore.directory)
            + size(of: AudioStore.directory)
        report.uploads = uploadsBytes()
        report.fonts = size(of: FontStore.directory)
        report.versions = size(of: documents.appendingPathComponent("history", isDirectory: true))
        report.templates = size(of: UserTemplates.directory) + size(ofFile: UserTemplates.indexURL)
        report.recentlyDeleted = size(of: DesignLibrary.trashDir)
        report.caches = cacheFolders.reduce(0) { $0 + size(of: $1) }
        return report
    }

    /// The file an upload on the list is kept in, when it is still here.
    static func file(of entry: Uploads.Entry) -> URL? {
        switch entry.kind {
        case .image:
            return MediaStore.extensions.map { MediaStore.directory.appendingPathComponent("\(entry.id).\($0)") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        case .video: return VideoStore.url(for: entry.id)
        case .audio: return AudioStore.url(for: entry.id)
        }
    }

    /// The bytes of a file, 0 for none.
    static func bytes(of url: URL?) -> Int64 { size(ofFile: url) }

    /// The photos, clips and songs you brought in, in bytes: Settings'
    /// "Your uploads", and the figure on Home's Uploads.
    static func uploadsBytes() -> Int64 {
        Uploads.all().reduce(0) { $0 + size(ofFile: file(of: $1)) }
    }

    /// "12.4 MB", as the Files app says a size.
    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Everything in the caches gone: exports already shared, or never
    /// shared, are made again on the next export.
    static func clearCaches() {
        let fm = FileManager.default
        for folder in cacheFolders {
            for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: url)
            }
        }
    }
}
