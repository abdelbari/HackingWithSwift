// Text to speech's rules (Narration), the rows the Android twin's
// NarrationTest holds: the track a voice makes and what it keeps, speed and
// pitch, Edit speech, the words the sheet starts with, the pieces a long
// text is read in, and the voices offered.

import XCTest
@testable import Canvia

final class NarrationTests: XCTestCase {

    func testASpokenTrackIsNamedForItsFirstFourWordsAndKeepsWhatItWasMadeFrom() throws {
        let spec = Narration.Spec(text: "  Welcome to   our summer sale, everyone!", voice: "en-us-x-voice", rate: 1.25, pitch: 0.9)
        let track = Narration.track(audioId: "audio_1.m4a", spec: spec, start: 12.5)
        XCTAssertEqual(track.src, "audio:audio_1.m4a")
        XCTAssertEqual(track.name, "Voice: Welcome to our summer")
        XCTAssertEqual(track.start, 12.5)
        let written = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        let tts = try XCTUnwrap(written["tts"] as? [String: Any])
        XCTAssertEqual(Set(tts.keys), ["text", "voice", "rate", "pitch"])
        XCTAssertEqual((tts["rate"] as? NSNumber)?.doubleValue, 1.25)
        XCTAssertEqual(Narration.of(track), spec)
        XCTAssertEqual(Narration.name("Hi"), "Voice: Hi")
        // Read back, the same track.
        XCTAssertEqual(try JSONDecoder().decode(AudioTrack.self, from: JSONEncoder().encode(track)), track)
        // A track that was not spoken writes no key.
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(AudioTrack(src: "audio:a"))) as? [String: Any])
        XCTAssertNil(plain["tts"])
    }

    func testSpeedAndPitchAreHeldToAHalfAndTwiceInTwentieths() throws {
        XCTAssertEqual(Narration.clamped(0.1), 0.5)
        XCTAssertEqual(Narration.clamped(3.0), 2.0)
        XCTAssertEqual(Narration.clamped(1.04), 1.05)
        XCTAssertEqual(Narration.clamped(.nan), 1.0)
        let odd = try JSONDecoder().decode(AudioTrack.self, from: Data(#"{"src":"audio:a","tts":{"text":"Hi","rate":"fast"}}"#.utf8))
        XCTAssertEqual(Narration.of(odd), Narration.Spec(text: "Hi", voice: "", rate: 1, pitch: 1))
        // No text, or no tts at all: not spoken.
        let blank = try JSONDecoder().decode(AudioTrack.self, from: Data(#"{"src":"audio:a","tts":{"text":" "}}"#.utf8))
        XCTAssertNil(Narration.of(blank))
        XCTAssertNil(Narration.of(AudioTrack(src: "audio:a")))
    }

    func testSpeakingAgainKeepsTheTracksPlaceTrimVolumeAndFades() throws {
        var first = Narration.track(audioId: "a.m4a", spec: Narration.Spec(text: "One two"), start: 3)
        first.trimStart = 0.5
        first.trimEnd = 4
        first.volume = 0.6
        first.fadeIn = 1
        first.fadeOut = 2
        first.enhance = true
        let again = Narration.regenerated(first, audioId: "b.m4a",
                                          spec: Narration.Spec(text: "Three four five six seven", voice: "v", rate: 1.5))
        var expected = first
        expected.src = "audio:b.m4a"
        expected.name = "Voice: Three four five six"
        expected.tts = again.tts
        XCTAssertEqual(again, expected)
        XCTAssertEqual(Narration.of(again)?.voice, "v")
        // Written into a design and read back, the same.
        var design = Design(title: "Spoken", width: 1080, height: 1080)
        design.audioTracks = [again]
        let back = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(back.audioTracks, [again])
    }

    func testTheSheetStartsFromTheSelectedTextElseTheNotesElseThePagesScript() {
        var box = Element.text("**Big** news")
        box.id = "t"
        var page = Page(background: .color("#ffffff"), elements: [box])
        page.notes = "  Say this  "
        var design = Design(title: "Spoken", width: 1080, height: 1080)
        design.pages = [page]
        XCTAssertEqual(Narration.prefill(design: design, page: page, selected: box), "Big news")
        XCTAssertEqual(Narration.prefill(design: design, page: page, selected: nil), "Say this")
        var bare = page
        bare.notes = " "
        design.pages = [bare]
        XCTAssertEqual(Narration.prefill(design: design, page: bare, selected: .sticker("🎉")),
                       ReadAloud.script(for: bare, in: design).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testLongTextGoesToTheVoiceASentenceAtATimeAtMostFourThousandCharacters() {
        let sentence = "This is a sentence of words. "
        let text = String(repeating: sentence, count: 300).trimmingCharacters(in: .whitespaces)
        let parts = Narration.utterances(text)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.joined().replacingOccurrences(of: " ", with: ""), text.replacingOccurrences(of: " ", with: ""))
        XCTAssertTrue(parts.allSatisfy { $0.count <= Narration.maxUtterance && $0.hasSuffix(".") })
        XCTAssertEqual(Narration.utterances("Short."), ["Short."])
        // No sentence end that fits: the last space; no space: the limit.
        XCTAssertEqual(Narration.chunks("aaa bbb ccc", max: 8), ["aaa bbb", "ccc"])
        XCTAssertEqual(Narration.chunks("abcdefghij", max: 4), ["abcd", "efgh", "ij"])
    }

    func testVoicesAreOfferedInTheAppsLanguageByName() {
        let voices = [
            Narration.Voice(id: "b", name: "b-voice", language: "en-GB"),
            Narration.Voice(id: "a", name: "a-voice", language: "en-US"),
            Narration.Voice(id: "pt", name: "pt-voice", language: "pt-PT"),
            Narration.Voice(id: "ja", name: "ja-voice", language: "ja_JP"),
        ]
        XCTAssertEqual(Narration.voicesFor(voices, language: "en").map(\.name), ["a-voice", "b-voice"])
        XCTAssertEqual(Narration.voicesFor(voices, language: "pt-BR").map(\.name), ["pt-voice"])
        XCTAssertEqual(Narration.voicesFor(voices, language: "ja").map(\.name), ["ja-voice"])
        XCTAssertEqual(Narration.voicesFor(voices, language: "ar"), [])
    }
}
