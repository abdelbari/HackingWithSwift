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
    /// name — or `name`, for a voice-over recorded under a made-up one — is
    /// kept beside it, so the music list can say "Summer Song.mp3" rather
    /// than "Audio (MP3)" — on this phone only, as the Android twin keeps
    /// it; the design carries the id, and each track its own name.
    static func store(_ source: URL, name: String? = nil) -> String? {
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
        let id = UID.make("audio") + "." + ext
        do {
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(id))
            let label = (name ?? source.lastPathComponent).trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { try? Data(label.utf8).write(to: nameFile(for: id)) }
            return id
        } catch {
            return nil
        }
    }

    /// Writes music that arrived in a design file in under a fresh id, as
    /// a file of type `ext` — letters and digits only, m4a when it names
    /// none — and returns the id. The design carries no name for it.
    static func store(_ data: Data, ext: String) -> String? {
        let clean = String(ext.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(5))
        let id = UID.make("audio") + "." + (clean.isEmpty ? "m4a" : clean)
        do {
            try data.write(to: directory.appendingPathComponent(id))
            return id
        } catch {
            return nil
        }
    }

    /// Where a soundtrack's original file name is kept — a file a backup
    /// carries beside the music, as the Android twin's does.
    static func nameFile(for id: String) -> URL {
        directory.appendingPathComponent(id + nameSuffix)
    }

    private static let nameSuffix = ".name"

    /// Where track id `id` is played from: a song in the store, or — for
    /// an effect's "sfx:<id>" (AudioTrack.audioId) — the WAV bundled with
    /// the app (SoundEffects.url).
    static func url(for id: String?) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        if AudioTrack.isEffect(id) { return SoundEffects.url(AudioTrack.sfxId(of: id)) }
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
        if let effect = SoundEffects.effect(AudioTrack.sfxId(of: id)) { return effect.name }
        if let data = try? Data(contentsOf: nameFile(for: id)) {
            let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return tr("Audio (%@)", URL(fileURLWithPath: id).pathExtension.uppercased())
    }
}

extension AudioStore {

    /// Where song `id`'s beats fall, in seconds into the file (Beats.detect):
    /// read the first time — its first Beats.maxSeconds, one channel at
    /// Beats.rate — and kept beside its peaks, Caches/peaks/<id>.beats, as
    /// the Android twin keeps them. Nil for a song not on this phone, or one
    /// it cannot play. Never on the main thread.
    static func beats(of id: String) async -> [Double]? {
        let file = Peaks.directory.appendingPathComponent("\(id).beats")
        if let data = try? Data(contentsOf: file), let kept = Beats.decode(String(decoding: data, as: UTF8.self)) {
            return kept
        }
        guard let url = AudioStore.url(for: id),
              let samples = await Peaks.samples(of: url, rate: Beats.rate,
                                                limit: Int(Beats.maxSeconds) * Beats.rate) else { return nil }
        let found = Beats.detect(samples, rate: Beats.rate)
        try? Data(Beats.encode(found).utf8).write(to: file, options: .atomic)
        return found
    }
}
