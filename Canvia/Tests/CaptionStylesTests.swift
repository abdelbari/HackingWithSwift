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

    private func fixtureRows(_ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(try SharedFixture.object("captions-styles")[key] as? [[String: Any]])
    }

    private func fixtureCue(_ raw: Any?) throws -> CaptionCue {
        let a = try XCTUnwrap(raw as? [Any])
        return CaptionCue(start: try XCTUnwrap(a[0] as? Double), end: try XCTUnwrap(a[1] as? Double),
                          text: try XCTUnwrap(a[2] as? String))
    }

    func testEachWordIsFramedAsTheSharedFixtureSays() throws {
        XCTAssertEqual(Captions.styles.count, 9)
        for row in try fixtureRows("frames") {
            let style = try XCTUnwrap(row["style"] as? String)
            let t = try XCTUnwrap(row["t"] as? Double)
            let frame = Captions.frameFor(style, t: t, span: try XCTUnwrap(row["span"] as? Double))
            XCTAssertEqual(frame.scale, try XCTUnwrap(row["scale"] as? Double), accuracy: 1e-9, "\(style) at \(t)")
            XCTAssertEqual(frame.alpha, try XCTUnwrap(row["alpha"] as? Double), accuracy: 1e-9, "\(style) at \(t)")
            XCTAssertEqual(frame.fill, try XCTUnwrap(row["fill"] as? Double), accuracy: 1e-9, "\(style) at \(t)")
        }
    }

    func testTheWordsShareTheCuesTimeEvenlyAndLettersRoundUp() throws {
        for row in try fixtureRows("progress") {
            let got = Captions.wordProgress(try fixtureCue(row["cue"]), try XCTUnwrap(row["t"] as? Double))
            let since = try XCTUnwrap(row["since"] as? [Double])
            XCTAssertEqual(got.count, since.count)
            for (timing, want) in zip(got, since) {
                XCTAssertEqual(timing.since, want, accuracy: 1e-9)
                XCTAssertEqual(timing.span, try XCTUnwrap(row["span"] as? Double), accuracy: 1e-9)
            }
        }
        for row in try fixtureRows("letters") {
            XCTAssertEqual(Captions.letters(try XCTUnwrap(row["fill"] as? Double), count: try XCTUnwrap(row["count"] as? Int)),
                           try XCTUnwrap(row["letters"] as? Int))
        }
        XCTAssertEqual(Captions.popScale(5), 1, accuracy: 1e-9)
        // Whole characters: half of "héllo" is three letters, three units.
        XCTAssertEqual(Captions.filledUnits("héllo", share: 0.5), 3)
    }

    func testPopKaraokeAndTypewriterDrawTheirWordsAsTheSharedFixtureSays() throws {
        for row in try fixtureRows("shown") {
            let style = try XCTUnwrap(row["style"] as? String)
            var white = Element.text("")
            white.color = "#ffffff"
            let box = Captions.on(white, Captions(cues: [try fixtureCue(row["cue"])], style: style))
            let t = try XCTUnwrap(row["t"] as? Double)
            let want = try XCTUnwrap(row["spans"] as? [[Any]]).map { a in
                TextSpan(start: a[0] as? Int ?? -1, end: a[1] as? Int ?? -1, color: a[2] as? String, scale: a[3] as? Double)
            }
            XCTAssertEqual(Captions.shown(box, at: t).liveSpans, want, "\(style) at \(t)")
        }
    }

    func testAStillShowsTheFinishedCue() {
        let hello = [CaptionCue(start: 1, end: 2, text: "Hello world")]
        var white = Element.text("")
        white.color = "#ffffff"
        for style in [Captions.pop, Captions.typewriter] {
            let box = Captions.on(white, Captions(cues: hello, style: style))
            XCTAssertEqual(Captions.shown(box, at: nil).liveSpans, [])
            // The playhead at rest before the first cue: that cue, finished.
            XCTAssertEqual(Captions.shown(box, at: 0.5, still: true).liveSpans, [])
            XCTAssertEqual(Captions.shown(box, at: 0.5, still: true).text, "Hello world")
        }
        let sung = Captions.on(white, Captions(cues: hello, style: Captions.karaoke, highlight: "#00ff00"))
        XCTAssertEqual(Captions.shown(sung, at: nil).liveSpans, [TextSpan(start: 0, end: 11, color: "#00ff00")])
    }

    func testOutlineGradientAndBar() {
        let hello = [CaptionCue(start: 0, end: 2, text: "Hi")]
        let outlined = Captions.shown(Captions.on(Element.text("x"), Captions(cues: hello, style: Captions.outline)), at: 1)
        XCTAssertEqual(outlined.color, "#ffffff")
        XCTAssertEqual(outlined.effect?.type, "outlined")
        XCTAssertEqual(outlined.effect?.thickness ?? 0, 75, accuracy: 1e-9)
        XCTAssertEqual(outlined.effect?.color, "#000000")
        XCTAssertEqual(TextEffect.outlinedStroke(fontSize: 100, thickness: outlined.effect?.thickness ?? 0), 6, accuracy: 1e-9)
        // Gradient: worked out from the page's palette as it is drawn, never stored.
        let graded = Captions.shown(Captions.on(Element.text("x"), Captions(cues: hello, style: Captions.gradient)), at: 1,
                                    palette: ["#1A1A2E", "#E63946", "#1D6FDC"])
        XCTAssertEqual(graded.textFill?.stops?.map(\.color), ["#1a1a2e", "#e63946"])
        XCTAssertEqual(graded.textFill?.angle, 90)
        XCTAssertEqual(Captions.gradientFill(["#123456"]).stops?.map(\.color), Captions.gradientFallback)
        XCTAssertEqual(Captions.gradientFallback, ["#ffd60a", "#ff375f"])
        var band = Element.text("x")
        band.y = 500
        band.h = 90
        let bar = Captions.on(band, Captions(cues: hello, style: Captions.bar))
        XCTAssertEqual(Captions.barRect(bar, pageWidth: 1080), CGRect(x: 0, y: 500, width: 1080, height: 90))
        XCTAssertNil(Captions.barRect(Captions.on(Element.text("x"), Captions(cues: hello)), pageWidth: 1080))
    }

    func testABoxIsPlacedAsTheSharedFixtureSaysItsPlaceRemembered() throws {
        for row in try fixtureRows("placed") {
            let box = try XCTUnwrap(row["box"] as? [Double])
            let safe = (row["safe"] as? [Double]).map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
            var el = Element.text("x")
            el.w = box[0]
            el.h = box[1]
            el = Captions.on(el, Captions(cues: [CaptionCue(start: 0, end: 1, text: "Hi")]))
            let place = try XCTUnwrap(row["place"] as? String)
            let placed = Captions.placed(el, place, size: CGSize(width: 1080, height: 1920), safe: safe)
            let frame = try XCTUnwrap(row["frame"] as? [Double])
            XCTAssertEqual(placed.x, frame[0], accuracy: 1e-6, place)
            XCTAssertEqual(placed.y, frame[1], accuracy: 1e-6, place)
            XCTAssertEqual(placed.captions?.place, place)
        }
    }

    func testABrandsAccentIsItsFirstPalettesSecondColourOrItsOnlyOne() {
        XCTAssertEqual(Captions.brandAccent([["#1A1A2E", "#E63946", "#ffffff"]]), "#e63946")
        XCTAssertEqual(Captions.brandAccent([[], ["#123456"]]), "#123456")
        XCTAssertNil(Captions.brandAccent([]))
        XCTAssertNil(Captions.brandAccent([["#000000", "gold"]]))
    }

    func testAHighlightThatIsNoColourIsLeftOut() throws {
        let text = ##"{"source":null,"cues":[],"style":"bar","highlight":"#12"}"##
        XCTAssertNil(try JSONDecoder().decode(Captions.self, from: Data(text.utf8)).highlight)
    }

    func testStyleAndPlaceAreOneStepEachAndKeepTheCues() {
        let s = store([])
        s.setCaptions("video:clip1", cues: [cue])
        s.setCaptionStyle("video:clip1", Captions.gradient)
        XCTAssertEqual(s.page.elements[0].captions?.style, Captions.gradient)
        XCTAssertEqual(s.page.elements[0].captions?.cues, [cue])
        // Gradient is drawn from the page's palette; nothing is stored.
        XCTAssertNil(s.page.elements[0].textFill)
        s.setCaptionPlace("video:clip1", Captions.top)
        XCTAssertEqual(s.page.elements[0].captions?.place, Captions.top)
        XCTAssertEqual(s.page.elements[0].y, 1920 * Captions.placeMargin, accuracy: 1e-9)
        XCTAssertEqual(s.page.elements[0].x, (1080 - s.page.elements[0].w) / 2, accuracy: 1e-9)
        s.undo()
        XCTAssertNil(s.page.elements[0].captions?.place)
        s.undo()
        XCTAssertEqual(s.page.elements[0].captions?.style, Captions.plain)
        XCTAssertEqual(s.page.elements[0].captions?.cues, [cue])
    }

    func testABoxLockedInPlaceStaysPut() {
        let s = store([])
        s.setCaptions("video:clip1", cues: [cue])
        let id = s.page.elements[0].id
        s.applyToPage { page in page.elements[0] = ElementLock.with(page.elements[0], .position) }
        let y = s.page.elements[0].y
        s.setCaptionPlace("video:clip1", Captions.top)
        XCTAssertEqual(s.page.elements.first { $0.id == id }?.y, y)
        XCTAssertNil(s.page.elements[0].captions?.place)
    }
}
