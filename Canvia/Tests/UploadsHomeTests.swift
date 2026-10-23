// Home's Uploads: the designs an upload is used in, the grid's filters
// and order, and what deleting asks — the same cases as the Android twin's
// UploadsTest.

import XCTest
@testable import Canvia

final class UploadsHomeTests: XCTestCase {

    private func design(_ id: String, _ pages: [Page] = [Page()]) -> Design {
        var d = Design(title: id, width: 100, height: 100)
        d.id = id
        d.pages = pages
        return d
    }

    func testTheDesignsUsingAnUploadAreListedByItsIdWhateverItsKind() {
        let framed = design("d1", [Page(elements: [Element.image("media:img-1", w: 10, h: 10)])])
        let behind = design("d2", [Page(background: .image("media:img-1"))])
        let playing = design("d3", [Page(elements: [Element.image(VideoStore.src("vid-1", at: nil), w: 10, h: 10)])])
        var scored = design("d4")
        scored.audio = [AudioTrack(src: "audio:audio-1.m4a")]
        var text = Element.text("Hi")
        text.fontFamily = CustomFonts.key("abcdef123456")
        let typed = design("d5", [Page(elements: [text])])
        let designs = [framed, behind, playing, scored, typed]
        XCTAssertEqual(Uploads.usages(designs, id: "img-1").map(\.id), ["d1", "d2"])
        XCTAssertEqual(Uploads.usages(designs, id: "vid-1").map(\.id), ["d3"])
        XCTAssertEqual(Uploads.usages(designs, id: "audio-1.m4a").map(\.id), ["d4"])
        XCTAssertEqual(Uploads.usages(designs, id: "abcdef123456").map(\.id), ["d5"])
        XCTAssertTrue(Uploads.usages(designs, id: "img-9").isEmpty)
        // A brand kit's logo or photo is a use too, asked apart.
        var kit = BrandKit()
        kit.photos = ["media:img-1"]
        let kits = BrandKits(activeId: kit.id, kits: [kit])
        XCTAssertTrue(Uploads.inBrandKit(kits, id: "img-1"))
        XCTAssertFalse(Uploads.inBrandKit(kits, id: "img-2"))
        XCTAssertEqual(Uploads.usedIn(0), "Not used in any design")
        XCTAssertEqual(Uploads.usedIn(1), "Used in 1 design")
        XCTAssertEqual(Uploads.usedIn(2), "Used in 2 designs")
    }

    func testTheUsageIndexSaysTheSameAndTheGridSortsByNewestOrLargest() {
        let framed = design("d1", [Page(elements: [Element.image("media:img-1", w: 10, h: 10),
                                                   Element.image(VideoStore.src("vid-1", at: nil), w: 10, h: 10)])])
        var scored = design("d2", [Page(background: .image("media:img-1"))])
        scored.audio = [AudioTrack(src: "audio:audio-1.m4a")]
        let index = Uploads.usageIndex([framed, scored])
        XCTAssertEqual(index["img-1"]?.map(\.id), ["d1", "d2"])
        XCTAssertEqual(index["vid-1"]?.map(\.id), ["d1"])
        XCTAssertEqual(index["audio-1.m4a"]?.map(\.id), ["d2"])
        XCTAssertNil(index["img-9"])
        let entries = [
            Uploads.Listed(id: "a", kind: "image", added: 1_000),
            Uploads.Listed(id: "b", kind: "video", added: 3_000),
            Uploads.Listed(id: "c", kind: "image", added: 2_000),
            Uploads.Listed(id: "d", kind: "font", added: 4_000),
        ]
        let bytes: [String: Int64] = ["a": 50, "b": 500, "c": 500, "d": 5]
        XCTAssertEqual(Uploads.sorted(entries, kind: nil, largest: false) { bytes[$0.id] ?? 0 }.map(\.id), ["d", "b", "c", "a"])
        // Largest first, the newer of two the same size first.
        XCTAssertEqual(Uploads.sorted(entries, kind: nil, largest: true) { bytes[$0.id] ?? 0 }.map(\.id), ["b", "c", "a", "d"])
        XCTAssertEqual(Uploads.sorted(entries, kind: "image", largest: false) { bytes[$0.id] ?? 0 }.map(\.id), ["c", "a"])
        XCTAssertEqual(Uploads.filters, ["image", "video", "audio", "font"])
    }

    func testDeletingFromHomeAsksForTheCountAndWarnsOfTheEmptyFrames() {
        XCTAssertEqual(Uploads.deletingFromHome(1, designs: 0).title, "Delete this upload?")
        XCTAssertNil(Uploads.deletingFromHome(1, designs: 0).text)
        XCTAssertEqual(Uploads.deletingFromHome(3, designs: 0).title, "Delete 3 uploads?")
        XCTAssertEqual(Uploads.deletingFromHome(1, designs: 2).text,
                       "Used in 2 designs. Those designs will show an empty frame.")
        XCTAssertEqual(Uploads.deletingFromHome(2, designs: 1).text,
                       "Used in 1 design. That design will show an empty frame.")
    }

    func testATileSaysItsSizeAndWhatItIs() {
        let listed = Uploads.Listed(id: "a", kind: "video", added: 0)
        var clip = UploadItem(listed: listed, file: URL(fileURLWithPath: "/tmp/a.mp4"), bytes: 0, seconds: 72)
        XCTAssertTrue(clip.caption.hasSuffix(" · 1:12"), clip.caption)
        clip.pixels = CGSize(width: 1920, height: 1080)
        XCTAssertTrue(clip.caption.hasSuffix(" · 1920 × 1080"), clip.caption)
        XCTAssertEqual(UploadItem.clock(3725), "1:02:05")
        XCTAssertTrue(clip.pictured)
    }
}
