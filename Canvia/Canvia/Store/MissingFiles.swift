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

    /// Whether `el`'s picture or clip is gone from this phone.
    static func isMissing(_ el: Element) -> Bool {
        guard el.type == .image, let file = stored(el.src) else { return false }
        return !exists(file)
    }

    /// Whether `track`'s sound is gone from this phone.
    static func isTrackMissing(_ track: AudioTrack) -> Bool {
        guard let file = trackFile(track) else { return false }
        return !exists(file)
    }
}
