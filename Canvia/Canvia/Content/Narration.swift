// Text to speech: words typed, or a text box's, or a page's notes or what
// the page says, read by one of the phone's own voices into a file — an
// ordinary voice track ({src: "audio:<id>", name: "Voice: <first words>",
// start: the page's start}) whose `tts` keeps what it was made from:
// {text, voice, rate, pitch}. Keeping it lets Edit speech make the file
// again in place, the track's start, trim, volume and fades kept; a build
// that does not know `tts` just plays the file. The rules are pure and the
// same on both phones (NarrationTests, the Android twin's NarrationTest);
// the reading itself is SpeechFile's.

import Foundation

enum Narration {

    /// The track's key for what it was spoken from.
    static let key = "tts"

    /// What a spoken track's name starts with, before its first words;
    /// stored as written, in English, on both phones.
    static let namePrefix = "Voice: "

    /// How many of its words a spoken track is named by.
    static let nameWords = 4

    /// Speed and pitch, each 0.5 to 2 times the voice's own, in twentieths.
    static let minRate = 0.5
    static let maxRate = 2.0

    /// The most a voice is handed at once, in characters: about Android's
    /// own limit for one utterance, cut at sentence ends (`chunks`) and the
    /// pieces joined — the same pieces on both phones.
    static let maxUtterance = 4000

    /// What a spoken track was made from: `text`, read by `voice` — the
    /// voice's identifier on the phone that made it, empty for that phone's
    /// default — at `rate` and `pitch` times the voice's own. Read
    /// leniently: no words is no spec, and a speed or pitch that is no
    /// number is the voice's own.
    struct Spec: Codable, Equatable {
        var text: String
        var voice: String = ""
        var rate: Double = 1
        var pitch: Double = 1

        private enum CodingKeys: String, CodingKey { case text, voice, rate, pitch }

        init(text: String, voice: String = "", rate: Double = 1, pitch: Double = 1) {
            self.text = text
            self.voice = voice
            self.rate = rate
            self.pitch = pitch
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let words = (try? c.decode(String.self, forKey: .text)) ?? ""
            guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "No words"))
            }
            text = words
            voice = (try? c.decode(String.self, forKey: .voice)) ?? ""
            rate = Narration.clamped((try? c.decode(Double.self, forKey: .rate)) ?? 1)
            pitch = Narration.clamped((try? c.decode(Double.self, forKey: .pitch)) ?? 1)
        }

        /// Text, voice, rate and pitch, the speed and pitch held as kept.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(text, forKey: .text)
            try c.encode(voice, forKey: .voice)
            try c.encode(Narration.clamped(rate), forKey: .rate)
            try c.encode(Narration.clamped(pitch), forKey: .pitch)
        }
    }

    /// A speed or a pitch held to minRate…maxRate, to a twentieth; anything
    /// unreadable is the voice's own, 1.
    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return (min(max(value, minRate), maxRate) * 20).rounded() / 20
    }

    /// What `track` was spoken from, or nil for a track that was not.
    static func of(_ track: AudioTrack) -> Spec? {
        track.tts
    }

    /// "Voice: " and `text`'s first `nameWords` words, one space apart.
    static func name(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace }).prefix(nameWords).map(String.init)
        return namePrefix + words.joined(separator: " ")
    }

    /// A new track of the audio `audioId` spoken from `spec`, from `start`
    /// seconds into the film.
    static func track(audioId: String, spec: Spec, start: Double) -> AudioTrack {
        var track = AudioTrack(src: AudioTrack.src(audioId), start: max(0, start), name: name(spec.text))
        track.tts = spec
        return track
    }

    /// `track` spoken again from `spec` into `audioId`: the new file and
    /// name, its start, trim, volume, fades and loop kept.
    static func regenerated(_ track: AudioTrack, audioId: String, spec: Spec) -> AudioTrack {
        var out = track
        out.src = AudioTrack.src(audioId)
        out.name = name(spec.text)
        out.tts = spec
        return out
    }

    /// The words the sheet starts with, the first there is of: the selected
    /// text box's words (`selected`, style marks left out), the page's
    /// notes, and what the page says as Read aloud reads it.
    static func prefill(design: Design, page: Page, selected: Element?) -> String {
        if let box = selected, box.type == .text {
            let words = RichText.strip(box.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty { return words }
        }
        if let notes = page.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty { return notes }
        return ReadAloud.script(for: page, in: design).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `text` in the pieces a voice is handed one at a time, in order.
    static func utterances(_ text: String, max: Int = maxUtterance) -> [String] {
        chunks(text, max: max)
    }

    /// `text` cut into pieces no longer than `max` characters, at the last
    /// sentence end or space that fits, so no word is split — the Android
    /// twin's Proofing.chunks, step for step.
    static func chunks(_ text: String, max: Int) -> [String] {
        guard max > 0 else { return [text] }
        var out: [String] = []
        var rest = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        func trimmed(_ part: ArraySlice<Character>) -> String {
            String(part).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while rest.count > max {
            let window = rest[0...max]
            var stop = -1
            for i in stride(from: window.count - 2, through: 0, by: -1)
            where ".!?…".contains(window[i]) && window[i + 1] == " " {
                stop = i
                break
            }
            let space = window.lastIndex(of: " ") ?? -1
            let cut = stop > 0 ? stop + 1 : space > 0 ? space : max
            out.append(trimmed(rest[0..<cut]))
            rest = Array(trimmed(rest[cut...]))
        }
        if !rest.isEmpty { out.append(String(rest)) }
        return out
    }

    /// One of the phone's voices: its identifier, what it is called, and
    /// its language (BCP-47).
    struct Voice: Equatable, Identifiable {
        var id: String
        var name: String
        var language: String
    }

    /// The voices offered for the app's `language` (AppLanguage): those
    /// whose language is the same language, its region aside — any
    /// Portuguese for pt-BR — by name; the rest are not offered.
    static func voicesFor(_ voices: [Voice], language: String) -> [Voice] {
        let wanted = primary(language)
        return voices.filter { primary($0.language) == wanted }.sorted { $0.name < $1.name }
    }

    private static func primary(_ tag: String) -> String {
        String(tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "").lowercased()
    }
}
