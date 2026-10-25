// What VoiceOver finds on a slide in Present, from the fixture both phones
// read (Fixtures/present_speech.json, the Android twin's
// PresentSpeechTest): the page's header, what a page change announces, and
// the slide's stops in reading order.

import XCTest
@testable import Canvia

final class PresentSpeechTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("present_speech") }

    private func design() throws -> Design {
        try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(try fixture()["design"])))
    }

    func testTheSlideReadsAsTheFixturesStopsInReadingOrder() throws {
        let expected = try XCTUnwrap(try fixture()["items"] as? [[String: Any]]).map { o in
            PresentSpeech.Stop(id: o["id"] as? String ?? "", kind: o["kind"] as? String ?? "",
                               label: o["label"] as? String ?? "", url: o["url"] as? String)
        }
        let d = try design()
        XCTAssertEqual(PresentSpeech.items(d.pages[0], in: d), expected)
    }

    func testTheHeaderSaysThePageAndItsTitleAndAPageChangeItsFirstHeading() throws {
        let f = try fixture()
        let d = try design()
        XCTAssertEqual(PresentSpeech.header(d, index: 0), f["header"] as? String)
        XCTAssertEqual(PresentSpeech.announcement(d, index: 0), f["announcement"] as? String)
        // Untitled, the number alone; no heading, the header alone.
        var bare = d
        bare.pages[0].title = nil
        bare.pages[0].elements.removeAll { $0.id == "e1" }
        XCTAssertEqual(PresentSpeech.header(bare, index: 0), "Page 1 of 1")
        XCTAssertEqual(PresentSpeech.announcement(bare, index: 0), "Page 1 of 1")
    }

    func testADecorativePictureWithAltTextIsStillRead() throws {
        var d = try design()
        let at = try XCTUnwrap(d.pages[0].elements.firstIndex { $0.id == "e4" })
        d.pages[0].elements[at].altText = "Pattern"
        let read = PresentSpeech.items(d.pages[0], in: d)
            .filter { $0.kind == PresentSpeech.image || $0.kind == PresentSpeech.chart }
        XCTAssertEqual(read.map(\.id), ["e3", "chart_1", "e4"])
    }

    /// A heading is a header to VoiceOver, a picture and a chart images, a
    /// link a link.
    @MainActor
    func testEachKindHasItsTrait() {
        XCTAssertEqual(PresentSlideReader.traits(PresentSpeech.heading), .isHeader)
        XCTAssertEqual(PresentSlideReader.traits(PresentSpeech.image), .isImage)
        XCTAssertEqual(PresentSlideReader.traits(PresentSpeech.link), .isLink)
        XCTAssertEqual(PresentSlideReader.traits(PresentSpeech.text), [])
    }
}
