// Audio files brought in for a soundtrack, kept in Documents/audio by id so
// a design can refer to one without holding the file.

import AVFoundation
import Foundation

enum AudioStore {

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies the file in under a fresh id and returns it.
    static func store(_ source: URL) -> String? {
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let id = UID.make("audio") + "." + ext
        do {
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(id))
            return id
        } catch {
            return nil
        }
    }

    static func url(for id: String?) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        let url = directory.appendingPathComponent(id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(_ id: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id))
    }

    static func all() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    /// The file's length in seconds, or nil when it is not audio.
    static func duration(of id: String) async -> Double? {
        guard let url = url(for: id) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return nil }
        return duration.seconds
    }

    /// The original name is not kept; the id's extension says what it is.
    static func label(for id: String) -> String {
        "Audio (\(URL(fileURLWithPath: id).pathExtension.uppercased()))"
    }
}
