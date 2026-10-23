// The sound effects that come with the app — whoosh, pop, ding, riser, drum
// hits and the rest, two dozen, each under two seconds — synthesised by
// tools/generate_sounds.py, which writes the WAVs (the bundle's sfx folder
// here, the Android twin's assets/sfx) and sfx.json, this list, the same on
// both phones.
//
// An effect goes under the film as an ordinary audio track whose source is
// "sfx:<id>" (AudioTrack.sfxPrefix): from the start of the page on screen,
// once, and mixed, previewed and exported as any track is — AudioStore
// finds its file in the bundle. It is in every copy of the app, so a design
// file or a backup never carries it (AudioTrack.storedAudioId). The Android
// twin's SoundEffects, with the same test rows.

import Foundation

/// One built-in sound effect: its id, what the Audio sheet calls it, words
/// to find it by, and how long it plays.
struct SoundEffect: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var tags: [String] = []
    var seconds: Double

    private enum CodingKeys: String, CodingKey { case id, name, tags, seconds }

    init(id: String, name: String, tags: [String] = [], seconds: Double) {
        self.id = id
        self.name = name
        self.tags = tags
        self.seconds = seconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        seconds = (try? c.decodeIfPresent(Double.self, forKey: .seconds)) ?? 0
    }
}

enum SoundEffects {

    /// Read once, on first use.
    static let all: [SoundEffect] = {
        guard let url = Bundle.main.url(forResource: "sfx", withExtension: "json")
                ?? Bundle.main.url(forResource: "sfx", withExtension: "json", subdirectory: "sfx"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SoundEffect].self, from: data) else {
            assertionFailure("sfx.json missing or invalid")
            return []
        }
        return decoded
    }()

    private static let byId: [String: SoundEffect] = Dictionary(
        all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func effect(_ id: String?) -> SoundEffect? {
        id.flatMap { byId[$0] }
    }

    /// The effect an "sfx:" source names, when this build has it.
    static func of(_ src: String?) -> SoundEffect? {
        effect(AudioTrack.sfxId(of: src))
    }

    /// The effects whose name, id or one of whose tags has `query` in it,
    /// case aside, in the sheet's order; all of them for a blank one.
    static func search(_ query: String) -> [SoundEffect] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { e in
            e.name.lowercased().contains(needle) || e.id.contains(needle) || e.tags.contains { $0.contains(needle) }
        }
    }

    /// The file an effect is played from, relative to the bundle (iOS) or
    /// the assets (Android): "sfx/<id>.wav".
    static func assetPath(_ id: String) -> String { "sfx/\(id).wav" }

    /// Effect `id`'s WAV in the app's bundle — at its top, where Xcode
    /// copies a folder's files, or in its sfx folder; nil for one this
    /// build does not have.
    static func url(_ id: String?) -> URL? {
        guard let id, effect(id) != nil else { return nil }
        return Bundle.main.url(forResource: id, withExtension: "wav")
            ?? Bundle.main.url(forResource: id, withExtension: "wav", subdirectory: "sfx")
    }

    /// The track `effect` becomes: from `start` seconds into the film — the
    /// page on screen's start — once, called by its name.
    static func track(_ effect: SoundEffect, start: Double) -> AudioTrack {
        AudioTrack(src: AudioTrack.sfxSrc(effect.id), start: max(0, start), loop: false, name: effect.name)
    }
}
