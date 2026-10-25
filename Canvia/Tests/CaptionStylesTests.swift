// The nine caption styles, where a caption box is put and the colour its
// said words take (Captions): each word's frame held to the shared fixture
// captions-styles.json, the spans that draw it, the `captions` keys, and
// the store's steps — the rows the Android twin's CaptionStylesTest holds.

import XCTest
import CoreGraphics
@testable import Canvia

final class CaptionStylesTests: XCTestCase {

    private let cue = CaptionCue(start: 1, end: 2.2, text: "Say it loud")

    private func store(_ elements: [Element], width: Double = 1080, height: Double = 1920) -> DesignStore {
        var design = Design(title: "captions", width: width, height: height)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    func testNineStylesAndFourPlacesAnUnknownStyleReadsPlain() throws {
        XCTAssertEqual(Captions.styles, ["plain", "box", "highlightWord", "outline", "pop", "karaoke", "typewriter",
                                         "bar", "gradient"])
        XCTAssertEqual(Captions.places, ["top", "middle", "bottom", "safe"])
        let text = ##"{"source":null,"cues":[],"style":"wobble","place":"left","highlight":"#ff0066"}"##
        let read = try JSONDecoder().decode(Captions.self, from: Data(text.utf8))
        XCTAssertEqual(read.style, Captions.plain)
        XCTAssertNil(read.place)
        XCTAssertEqual(read.highlight, "#ff0066")
        XCTAssertEqual(read.highlightInk, "#ff0066")
    }

    func testPlaceAndHighlightAreWrittenOnlyWhenSet() throws {
        func object(_ c: Captions) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any])
        }
        let bare = try object(Captions(cues: [cue], style: Captions.karaoke))
        XCTAssertEqual(bare["style"] as? String, "karaoke")
        XCTAssertNil(bare["place"])
        XCTAssertNil(bare["highlight"])
        let set = Captions(cues: [cue], style: Captions.pop, place: Captions.safe, highlight: "#22c55e")
        let written = try object(set)
        XCTAssertEqual(written["place"] as? String, "safe")
        XCTAssertEqual(written["highlight"] as? String, "#22c55e")
        XCTAssertEqual(try JSONDecoder().decode(Captions.self, from: JSONEncoder().encode(set)), set)
        // A box keeps them as its cues change.
        let box = Captions.on(Element.text(""), set)
        XCTAssertEqual(box.captions?.place, Captions.safe)
        XCTAssertEqual(box.captions?.highlight, "#22c55e")
    }

    func testEachWordsFrameMatchesTheSharedFixture() throws {
        let fixture = try SharedFixture.object("captions-styles")
        let tolerance = try XCTUnwrap(fixture["tolerance"] as? Double)
        let raw = try XCTUnwrap(fixture["cue"] as? [String: Any])
        let shared = CaptionCue(start: try XCTUnwrap(raw["start"] as? Double), end: try XCTUnwrap(raw["end"] as? Double),
                                text: try XCTUnwrap(raw["text"] as? String))
        let rows = try XCTUnwrap(fixture["rows"] as? [[String: Any]])
        XCTAssertEqual(Set(rows.compactMap { $0["style"] as? String }), Set(Captions.styles))
        for row in rows {
            let style = try XCTUnwrap(row["style"] as? String)
            let t = row["t"] as? Double
            let expected = try XCTUnwrap(row["frames"] as? [[Double]])
            let frames = Captions.frameFor(style, cue: shared, t: t)
            XCTAssertEqual(frames.count, expected.count, "\(style) at \(String(describing: t))")
            for (frame, want) in zip(frames, expected) {
                XCTAssertEqual(frame.scale, want[0], accuracy: tolerance, "\(style) at \(String(describing: t))")
                XCTAssertEqual(frame.alpha, want[1], accuracy: tolerance, "\(style) at \(String(describing: t))")
                XCTAssertEqual(frame.fill, want[2], accuracy: tolerance, "\(style) at \(String(describing: t))")
            }
        }
    }

    func testWordProgressAndPop() {
        let early = Captions.wordProgress(cue, 1.2)
        XCTAssertEqual(early.count, 3)
        XCTAssertEqual(early[0], 0.5, accuracy: 1e-9)
        XCTAssertEqual(Array(early.dropFirst()), [0, 0])
        XCTAssertEqual(Captions.wordProgress(cue, 3), [1, 1, 1])
        XCTAssertEqual(Captions.popScale(0), 0.6, accuracy: 1e-9)
        XCTAssertEqual(Captions.popScale(0.09), 1.08, accuracy: 1e-9)
        XCTAssertEqual(Captions.popScale(0.18), 1, accuracy: 1e-9)
        XCTAssertEqual(Captions.popScale(5), 1, accuracy: 1e-9)
    }

    func testTheSpansThatDrawEachStyle() {
        let box = Element.text("")
        func shown(_ style: String, _ t: Double?) -> [TextSpan] {
            Captions.shown(Captions.on(box, Captions(cues: [cue], style: style)), at: t).liveSpans
        }
        // Karaoke: the first word whole, the second half filled ("i").
        XCTAssertEqual(shown(Captions.karaoke, 1.6), [TextSpan(start: 0, end: 3, color: Captions.highlightColour),
                                                       TextSpan(start: 4, end: 5, color: Captions.highlightColour)])
        // Typewriter: the rest of "it" clear, "loud" not yet there.
        XCTAssertEqual(shown(Captions.typewriter, 1.6), [TextSpan(start: 5, end: 6, color: Captions.clearInk),
                                                          TextSpan(start: 7, end: 11, color: Captions.clearInk)])
        // Pop: the first word settling, the rest clear and small.
        let pop = shown(Captions.pop, 1.05)
        XCTAssertEqual(pop.count, 3)
        XCTAssertNil(pop[0].color)
        XCTAssertEqual(pop[1].color, Captions.clearInk)
        // Finished, nothing is left clear or small.
        XCTAssertEqual(shown(Captions.typewriter, nil), [])
        XCTAssertEqual(shown(Captions.pop, nil), [])
        // Outline: white letters in a black stroke 6% of the type.
        let outlined = Captions.shown(Captions.on(box, Captions(cues: [cue], style: Captions.outline)), at: 1.5)
        XCTAssertEqual(outlined.color, "#ffffff")
        XCTAssertEqual(outlined.effect?.type, "outlined")
        XCTAssertEqual(outlined.effect?.color, "#000000")
        XCTAssertEqual(TextEffect.outlinedStroke(fontSize: 100, thickness: outlined.effect?.thickness ?? 0), 6, accuracy: 1e-9)
        // A colour of its own lights the words.
        let lit = Captions.shown(Captions.on(box, Captions(cues: [cue], style: Captions.highlightWord, highlight: "#22c55e")),
                                 at: 1.1)
        XCTAssertEqual(lit.liveSpans, [TextSpan(start: 0, end: 3, color: "#22c55e")])
        XCTAssertEqual(Captions.filledUnits("héllo", share: 0.5), 2)
    }

    func testPlacesMoveTheBoxOnly() {
        let size = CGSize(width: 1000, height: 800)
        let box = Captions.element(width: 1000, height: 800, captions: Captions(cues: [cue]))
        XCTAssertEqual(Captions.placed(box, Captions.top, size: size, zone: nil).y, 48, accuracy: 1e-9)
        XCTAssertEqual(Captions.placed(box, Captions.middle, size: size, zone: nil).y, (800 - box.h) / 2, accuracy: 1e-9)
        XCTAssertEqual(Captions.placed(box, Captions.bottom, size: size, zone: nil).y, box.y, accuracy: 1e-9)
        // Safe with no zone for the size is the bottom.
        XCTAssertEqual(Captions.placed(box, Captions.safe, size: size, zone: nil).y, box.y, accuracy: 1e-9)
        let zone = SafeZones.Zone(id: "z", label: "Z", sizes: [[1000, 800]],
                                  insets: .init(top: 0.1, bottom: 0.25, left: 0.05, right: 0.15), rails: [])
        let safe = Captions.placed(box, Captions.safe, size: size, zone: zone)
        XCTAssertEqual(safe.y + safe.h, 800 * 0.75 - 16, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(safe.x, 50)
        XCTAssertLessThanOrEqual(safe.x + safe.w, 850 + 1e-9)
        XCTAssertEqual(safe.text, box.text)
    }

    func testStyleAndPlaceAreOneStepEachAndKeepTheCues() {
        let s = store([])
        s.setCaptions("video:clip1", cues: [cue])
        s.setCaptionStyle("video:clip1", Captions.gradient)
        XCTAssertEqual(s.page.elements[0].captions?.style, Captions.gradient)
        XCTAssertEqual(s.page.elements[0].captions?.cues, [cue])
        XCTAssertEqual(s.page.elements[0].textFill?.kind, "gradient")
        s.setCaptionStyle("video:clip1", Captions.karaoke)
        XCTAssertNil(s.page.elements[0].textFill)
        s.setCaptionPlace("video:clip1", Captions.top)
        XCTAssertEqual(s.page.elements[0].captions?.place, Captions.top)
        XCTAssertEqual(s.page.elements[0].y, 1920 * Captions.placeMargin, accuracy: 1e-9)
        s.setCaptionHighlight("video:clip1", "#22C55E")
        XCTAssertEqual(s.page.elements[0].captions?.highlight, "#22c55e")
        s.setCaptionHighlight("video:clip1", Captions.highlightColour)
        XCTAssertNil(s.page.elements[0].captions?.highlight)
        s.undo()
        XCTAssertEqual(s.page.elements[0].captions?.highlight, "#22c55e")
        s.undo()
        s.undo()
        XCTAssertNil(s.page.elements[0].captions?.place)
        s.undo()
        XCTAssertEqual(s.page.elements[0].captions?.style, Captions.gradient)
        XCTAssertEqual(s.page.elements[0].captions?.cues, [cue])
    }

    func testGradientTakesThePagesFirstTwoColours() {
        let two = Captions.gradientFill(["#112233", "#445566", "#778899"])
        XCTAssertEqual(two.stops?.map(\.color), ["#112233", "#445566"])
        XCTAssertEqual(two.angle, 90)
        XCTAssertEqual(Captions.gradientFill(["#112233"]).stops?.map(\.color), ["#112233", "#ffffff"])
    }
}
