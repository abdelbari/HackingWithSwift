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
    /// the app (SoundEffects.url), a loop's "music:<id>" its WAV
    /// (MusicLibrary.url), or — for a clip's sound, "video:<id>" —
    /// the clip's own file.
    static func url(for id: String?) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        if AudioTrack.isEffect(id) { return SoundEffects.url(AudioTrack.sfxId(of: id)) }
        if AudioTrack.isMusic(id) { return MusicLibrary.url(AudioTrack.musicId(of: id)) }
        if let clip = AudioTrack.videoId(of: id) { return VideoStore.url(for: clip) }
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

    /// The file's length in seconds, or nil when it is not audio — a
    /// clip's, nil when it has no sound.
    static func duration(of id: String) async -> Double? {
        if let clip = AudioTrack.videoId(of: id) { return await VideoStore.soundLength(of: clip) }
        guard let url = url(for: id) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return nil }
        return duration.seconds
    }

    /// The music's own file name, where it was kept; otherwise what the
    /// id's extension says it is.
    static func label(for id: String) -> String {
        if let effect = SoundEffects.effect(AudioTrack.sfxId(of: id)) { return effect.name }
        if let music = MusicLibrary.of(id) { return music.name }
        if AudioTrack.isClipSound(id) { return AudioTracks.clipSoundName }
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
        // A built-in loop's beats come from its tempo, not from listening.
        if let music = MusicLibrary.of(id) { return MusicLibrary.beats(of: music) }
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

extension AudioStore {

    /// Where source `id`'s enhanced sound is kept (VoiceEnhance): by its id
    /// and ".enh", Caches/peaks/<id>.enh.wav — a clip's "video:<id>" with
    /// its colon as an underscore — as the Android twin keeps it.
    static func enhancedFile(for id: String) -> URL {
        Peaks.directory.appendingPathComponent(id.replacingOccurrences(of: ":", with: "_") + ".enh.wav")
    }

    /// Source `id` — a song, an effect, or a clip's "video:<id>" — cleaned
    /// and levelled by Enhance voice: made the first time, once however
    /// many ask at once, and kept. Nil for a source not on this phone, with
    /// no sound, or longer than VoiceEnhance.maxSeconds, which plays as it
    /// is. Never on the main thread.
    static func enhancedURL(for id: String) async -> URL? {
        await EnhancedSounds.shared.url(for: id)
    }
}

/// The enhanced sounds being made, so two asking for the same source at once
/// wait for the one making it.
actor EnhancedSounds {
    static let shared = EnhancedSounds()

    private var making: [String: Task<URL?, Never>] = [:]

    func url(for id: String) async -> URL? {
        let file = AudioStore.enhancedFile(for: id)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        if let running = making[id] { return await running.value }
        let task = Task.detached(priority: .utility) { () -> URL? in
            let rate = VoiceEnhance.rate
            let most = Int(VoiceEnhance.maxSeconds) * rate
            guard let source = AudioStore.url(for: id),
                  let samples = await Peaks.samples(of: source, rate: rate, limit: most + 1),
                  samples.count <= most else { return nil }
            let data = VoiceEnhance.wav(VoiceEnhance.enhanced(samples, rate: rate), rate: rate)
            return (try? data.write(to: file, options: .atomic)) != nil ? file : nil
        }
        making[id] = task
        let made = await task.value
        making[id] = nil
        return made
    }
}
