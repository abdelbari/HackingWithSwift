// Whether a design's own files are on this phone, for MissingMedia: a
// photo by its file in Documents/media, a clip in video/, an animated
// picture in anim/ and a song in the audio store.

import Foundation

extension MissingMedia {

    /// Whether the stored file `file` names ("media:", "video:", "anim:",
    /// "audio:") is here; anything else is taken to be.
    static func exists(_ file: String) -> Bool {
        if file.hasPrefix("media:") {
            let id = String(file.dropFirst(6))
            return MediaStore.extensions.contains { ext in
                FileManager.default.fileExists(atPath: MediaStore.directory.appendingPathComponent("\(id).\(ext)").path)
            }
        }
        if let parts = VideoStore.split(file) { return VideoStore.url(for: parts.id) != nil }
        if let parts = AnimStore.split(file) { return AnimStore.url(for: parts.id) != nil }
        if file.hasPrefix(AudioTrack.prefix) { return AudioStore.url(for: String(file.dropFirst(AudioTrack.prefix.count))) != nil }
        return true
    }

    /// What is gone from `design` on this phone.
    static func onThisPhone(_ design: Design) -> [Absent] {
        missing(design, exists: exists)
    }

    /// Whether `el`'s picture or clip — or the photo its fill holds — is
    /// gone from this phone, read from the disk: for a step, never a view's
    /// body, which reads DesignStore.missingFiles.
    static func isMissing(_ el: Element) -> Bool {
        sources(of: el).contains { !exists($0) }
    }
}

extension DesignStore {

    /// What is missing looked for again, off the main thread, and kept in
    /// `missingMedia` and `missingFiles` — the Android twin's checkMissing.
    @MainActor
    func checkMissing() async {
        let design = self.design
        let found = await Task.detached(priority: .utility) { () -> ([MissingMedia.Absent], Set<String>) in
            var gone: Set<String> = []
            let items = MissingMedia.missing(design) { file in
                let here = MissingMedia.exists(file)
                if !here { gone.insert(file) }
                return here
            }
            return (items, gone)
        }.value
        if missingMedia != found.0 { missingMedia = found.0 }
        if missingFiles != found.1 { missingFiles = found.1 }
    }

    /// The kind of file `el` is missing — its own picture or clip's, else
    /// its fill's — or nil when it is missing none, as last looked for.
    func missingKind(_ el: Element) -> MissingMedia.MediaKind? {
        MissingMedia.missingFile(of: el, among: missingFiles).map(MissingMedia.fileKind)
    }

    /// Whether sound track `id`'s file is gone, as last looked for.
    func soundMissing(_ id: String) -> Bool {
        missingMedia.contains { $0.kind == .audio && $0.elementId == id }
    }
}
