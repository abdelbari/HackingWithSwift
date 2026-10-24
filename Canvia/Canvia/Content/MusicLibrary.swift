// The music that comes with the app — a dozen seamless 8-bar loops, two for
// each mood — synthesised by tools/generate_music.py, which writes the WAVs
// (the bundle's music folder here, the Android twin's assets/music) and
// music.json, this list, the same on both phones.
//
// A loop goes under the film as an ordinary audio track whose source is
// "music:<id>" (AudioTrack.musicPrefix): from the film's start, looping
// to its end, fading out over its last second, and
// mixed, previewed and exported as any track is — AudioStore finds its file
// in the bundle. Beat Sync takes its beats from its tempo rather than
// listening for them. It is in every copy of the app, so a design file or a
// backup never carries it (AudioTrack.storedAudioId). The Android twin's
// MusicLibrary, with the same test rows.

import Foundation

/// One built-in loop: its id, what the Audio sheet calls it, its mood and
/// genre, its tempo, how long it plays once through, and words to find it by.
struct MusicTrack: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var mood: String
    var genre: String
    var bpm: Double
    var seconds: Double
    var tags: [String] = []

    private enum CodingKeys: String, CodingKey { case id, name, mood, genre, bpm, seconds, tags }

    init(id: String, name: String, mood: String, genre: String = "", bpm: Double, seconds: Double, tags: [String] = []) {
        self.id = id
        self.name = name
        self.mood = mood
        self.genre = genre
        self.bpm = bpm
        self.seconds = seconds
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mood = (try? c.decodeIfPresent(String.self, forKey: .mood)) ?? ""
        genre = (try? c.decodeIfPresent(String.self, forKey: .genre)) ?? ""
        bpm = (try? c.decodeIfPresent(Double.self, forKey: .bpm)) ?? 0
        seconds = (try? c.decodeIfPresent(Double.self, forKey: .seconds)) ?? 0
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
    }
}

enum MusicLibrary {

    /// The moods, in the order the sheet's chips show them.
    static let moods = ["upbeat", "calm", "dramatic", "happy", "chill", "corporate"]

    /// What a mood's chip says.
    static func moodName(_ mood: String) -> String {
        switch mood {
        case "upbeat": return tr("Upbeat")
        case "calm": return tr("Calm")
        case "dramatic": return tr("Dramatic")
        case "happy": return tr("Happy")
        case "chill": return tr("Chill")
        case "corporate": return tr("Corporate")
        default: return mood
        }
    }

    /// A new loop's fades: none in, a second out at the film's end.
    static let fadeIn = 0.0
    static let fadeOut = 1.0

    /// Read once, on first use.
    static let all: [MusicTrack] = {
        guard let url = Bundle.main.url(forResource: "music", withExtension: "json")
                ?? Bundle.main.url(forResource: "music", withExtension: "json", subdirectory: "music"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("music.json missing")
            return []
        }
        return parse(data)
    }()

    /// The list music.json holds; an entry without an id or a name, or with
    /// a mood not among `moods`, is left out, and the rest kept in order.
    static func parse(_ data: Data) -> [MusicTrack] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return raw.compactMap { entry in
            guard let object = try? JSONSerialization.data(withJSONObject: entry),
                  let track = try? JSONDecoder().decode(MusicTrack.self, from: object),
                  !track.id.isEmpty, !track.name.isEmpty, moods.contains(track.mood) else { return nil }
            return track
        }
    }

    /// The loop `id` names, when this build has it.
    static func byId(_ id: String?, in tracks: [MusicTrack] = all) -> MusicTrack? {
        guard let id else { return nil }
        return tracks.first { $0.id == id }
    }

    /// The loop a "music:" source names, when this build has it.
    static func of(_ src: String?) -> MusicTrack? {
        byId(AudioTrack.musicId(of: src))
    }

    /// The loops of `mood` (any, for nil) whose name or one of whose tags
    /// has `query` in it, case aside, in the list's order.
    static func filter(_ tracks: [MusicTrack] = all, mood: String?, query: String) -> [MusicTrack] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tracks.filter { track in
            (mood == nil || track.mood == mood)
                && (needle.isEmpty || track.name.lowercased().contains(needle)
                    || track.tags.contains { $0.lowercased().contains(needle) })
        }
    }

    /// The file a loop is played from, relative to the bundle (iOS) or the
    /// assets (Android): "music/<id>.wav".
    static func assetPath(_ id: String) -> String { "music/\(id).wav" }

    /// Loop `id`'s WAV in the app's bundle; nil for one this build does
    /// not have.
    static func url(_ id: String?) -> URL? {
        guard let id, byId(id) != nil else { return nil }
        return Bundle.main.url(forResource: id, withExtension: "wav")
            ?? Bundle.main.url(forResource: id, withExtension: "wav", subdirectory: "music")
    }

    /// The track `music` becomes: from the film's start, looping so it
    /// fills the film, no fade in and a second's fade out, called by its
    /// name.
    static func track(_ music: MusicTrack) -> AudioTrack {
        AudioTrack(src: AudioTrack.musicSrc(music.id), fadeIn: fadeIn, fadeOut: fadeOut, loop: true, name: music.name)
    }

    /// Where a loop's beats fall in its file, from its tempo: every beat
    /// from 0, the loops starting on their first beat, short of its end
    /// (by a hundredth of a beat, so a length rounded up to the thousandth
    /// does not add the next time round's first), each to the thousandth.
    static func beats(of music: MusicTrack) -> [Double] {
        guard music.bpm > 0, music.seconds > 0 else { return [] }
        let beat = 60 / music.bpm
        let count = Int((music.seconds / beat - 0.01).rounded(.up))
        return (0..<count).map { (Double($0) * beat * 1000).rounded() / 1000 }
    }
}
