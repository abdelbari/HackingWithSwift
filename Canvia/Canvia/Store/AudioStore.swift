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

    /// Copies the file in under a fresh id and returns it. The file's own
    /// name is kept beside it, so the soundtrack row can say "Summer Song.mp3"
    /// rather than "Audio (MP3)" — on this phone only, as the Android twin
    /// keeps it; the design carries the id alone.
    static func store(_ source: URL) -> String? {
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let id = UID.make("audio") + "." + ext
        do {
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(id))
            let name = source.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { try? Data(name.utf8).write(to: nameFile(for: id)) }
            return id
        } catch {
            return nil
        }
    }

    /// Where a soundtrack's original file name is kept.
    private static func nameFile(for id: String) -> URL {
        directory.appendingPathComponent(id + nameSuffix)
    }

    private static let nameSuffix = ".name"

    static func url(for id: String?) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        let url = directory.appendingPathComponent(id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(_ id: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id))
        try? FileManager.default.removeItem(at: nameFile(for: id))
    }

    /// Every soundtrack stored, by id — not the name files beside them,
    /// which no design names and the launch sweep would otherwise take.
    static func all() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { !$0.hasSuffix(nameSuffix) }
            .sorted()
    }

    /// The file's length in seconds, or nil when it is not audio.
    static func duration(of id: String) async -> Double? {
        guard let url = url(for: id) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return nil }
        return duration.seconds
    }

    /// The music's own file name, where it was kept; otherwise what the
    /// id's extension says it is.
    static func label(for id: String) -> String {
        if let data = try? Data(contentsOf: nameFile(for: id)) {
            let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return "Audio (\(URL(fileURLWithPath: id).pathExtension.uppercased()))"
    }
}
