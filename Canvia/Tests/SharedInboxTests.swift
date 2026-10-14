// Edit in Canvia: the inbox manifest both phones write, the sizes offered
// for what was shared, and bringing it in.

import XCTest
import UniformTypeIdentifiers
@testable import Canvia

final class SharedInboxTests: XCTestCase {

    // MARK: manifest

    func testTheManifestIsWrittenAsTheAndroidTwinWritesIt() throws {
        let manifest = SharedInbox.ShareManifest(items: [SharedInbox.Item(kind: .image, file: "0.jpg", mime: "image/jpeg")],
                                            createdAt: 1_700_000_000_123)
        let text = String(decoding: try XCTUnwrap(manifest.data), as: UTF8.self)
        XCTAssertEqual(text, #"{"createdAt":1700000000123,"items":[{"file":"0.jpg","kind":"image","mime":"image\/jpeg"}],"version":1}"#)
        XCTAssertEqual(SharedInbox.ShareManifest.read(Data(text.utf8)), manifest)
    }

    /// An item of a kind this build does not know, or with no safe file
    /// name, is skipped; the rest still read.
    func testTheManifestReadsLeniently() throws {
        let json = #"""
        {"version":1,"createdAt":1700000000000.0,"extra":true,"items":[
          {"kind":"image","file":"0.jpg","mime":"image/jpeg"},
          {"kind":"hologram","file":"1.holo","mime":"x/holo"},
          {"kind":"video","file":"../2.mp4","mime":"video/mp4"},
          {"kind":"pdf","mime":"application/pdf"},
          {"kind":"anim","file":"3.gif","mime":"image/gif"},
          {"kind":"svg","file":"4.svg","mime":"image/svg+xml"}
        ]}
        """#
        let manifest = try XCTUnwrap(SharedInbox.ShareManifest.read(Data(json.utf8)))
        XCTAssertEqual(manifest.items.map(\.file), ["0.jpg", "3.gif", "4.svg"])
        XCTAssertEqual(manifest.items.map(\.kind), [.image, .anim, .svg])
        XCTAssertEqual(manifest.createdAt, 1_700_000_000_000)
        XCTAssertEqual(SharedInbox.ShareManifest.read(Data("{}".utf8))?.items, [])
    }

    func testWhatEachTypeComesInAs() {
        XCTAssertEqual(SharedInbox.kind(for: .jpeg), .image)
        XCTAssertEqual(SharedInbox.kind(for: .heic), .image)
        XCTAssertEqual(SharedInbox.kind(for: .gif), .anim)
        XCTAssertEqual(SharedInbox.kind(for: .webP), .anim)
        XCTAssertEqual(SharedInbox.kind(for: .svg), .svg)
        XCTAssertEqual(SharedInbox.kind(for: .mpeg4Movie), .video)
        XCTAssertEqual(SharedInbox.kind(for: .quickTimeMovie), .video)
        XCTAssertEqual(SharedInbox.kind(for: .pdf), .pdf)
        XCTAssertNil(SharedInbox.kind(for: .json))
        XCTAssertEqual(SharedInbox.kind(of: URL(fileURLWithPath: "/tmp/Holiday.JPG")), .image)
        XCTAssertNil(SharedInbox.kind(of: URL(fileURLWithPath: "/tmp/poster.canvia.json")))
    }

    // MARK: sizes

    /// The photo's own size, its long edge 4000 at most.
    func testFitToThePhoto() {
        XCTAssertEqual(SharedInbox.fitSize(CGSize(width: 6000, height: 4000)), CGSize(width: 4000, height: 2667))
        XCTAssertEqual(SharedInbox.fitSize(CGSize(width: 3024, height: 4032)), CGSize(width: 3000, height: 4000))
        XCTAssertEqual(SharedInbox.fitSize(CGSize(width: 800, height: 600)), CGSize(width: 800, height: 600))
        XCTAssertEqual(SharedInbox.fitSize(.zero), CGSize(width: 1, height: 1))
    }

    /// Nearest shape first, by the distance between aspect ratios on a log
    /// scale; a tie keeps the catalogue's order.
    func testSuggestionsRankByAspectDistance() {
        let presets = [
            SizePreset(id: "square", name: "Square", category: "Social", width: 1080, height: 1080),
            SizePreset(id: "story", name: "Story", category: "Social", width: 1080, height: 1920),
            SizePreset(id: "wide", name: "Wide", category: "Video", width: 1920, height: 1080),
            SizePreset(id: "portrait", name: "Portrait", category: "Social", width: 1080, height: 1350),
            SizePreset(id: "landscape", name: "Landscape", category: "Social", width: 1350, height: 1080),
            SizePreset(id: "a4", name: "A4", category: "Print", width: 210, height: 297, unit: "mm"),
        ]
        // A 4:5 photo: 4:5 itself, then A4, the square and 9:16.
        let photo = CGSize(width: 2160, height: 2700)
        XCTAssertEqual(SharedInbox.suggestions(for: photo, among: presets).map(\.id),
                       ["portrait", "a4", "square", "story"])
        XCTAssertEqual(SharedInbox.suggestions(for: CGSize(width: 1920, height: 1080), among: presets, count: 2).map(\.id),
                       ["wide", "landscape"])
        // Twice as wide and twice as tall are equally far from a square, so
        // the catalogue's order decides.
        let halves = [
            SizePreset(id: "wide2", name: "Wide", category: "Video", width: 2000, height: 1000),
            SizePreset(id: "square", name: "Square", category: "Social", width: 1000, height: 1000),
            SizePreset(id: "tall2", name: "Tall", category: "Social", width: 1000, height: 2000),
        ]
        XCTAssertEqual(SharedInbox.suggestions(for: CGSize(width: 500, height: 500), among: halves).map(\.id),
                       ["square", "wide2", "tall2"])
        XCTAssertEqual(SharedInbox.suggestions(for: CGSize(width: 500, height: 500), among: halves.reversed()).map(\.id),
                       ["square", "tall2", "wide2"])
        XCTAssertEqual(SharedInbox.suggestions(for: photo).count, 4)
        // Its size unknown, the first four in the catalogue, as on Android.
        XCTAssertEqual(SharedInbox.suggestions(for: nil, among: presets).map(\.id),
                       ["square", "story", "wide", "portrait"])
        XCTAssertEqual(SharedInbox.suggestions(for: .zero, among: presets).map(\.id),
                       ["square", "story", "wide", "portrait"])
    }

    func testWhatIsSaidOfItemsThatWouldNotOpen() {
        XCTAssertEqual(SharedInbox.failureText(failed: 1, total: 3), "Couldn't open 1 of 3 items")
        XCTAssertEqual(SharedInbox.failureText(failed: 1, total: 1), "Couldn't open that item")
        XCTAssertNil(SharedInbox.failureText(failed: 0, total: 3))
    }

    // MARK: bringing in

    /// Landed with a manifest, read back, brought in a page an item —
    /// what does not open counted — and the folder gone after.
    func testLandBringInAndRemove() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let svg = source.appendingPathComponent("star.svg")
        try Data(#"<svg viewBox="0 0 10 10"><path d="M0 0 L10 0 L10 10 Z"/></svg>"#.utf8).write(to: svg)
        let broken = source.appendingPathComponent("broken.jpg")
        try Data("not a picture".utf8).write(to: broken)
        let design = source.appendingPathComponent("design.json")
        try Data("{}".utf8).write(to: design)

        let box = try XCTUnwrap(SharedInbox.land([svg, design, broken], now: Date(timeIntervalSince1970: 1_700_000_000)))
        defer { SharedInbox.remove(box.id) }
        XCTAssertEqual(box.manifest.items, [SharedInbox.Item(kind: .svg, file: "0.svg", mime: "image/svg+xml"),
                                            SharedInbox.Item(kind: .image, file: "1.jpg", mime: "image/jpeg")])
        XCTAssertEqual(box.manifest.createdAt, 1_700_000_000_000)
        XCTAssertEqual(SharedInbox.open(box.id), box)

        let brought = SharedInbox.bringIn(box, pageSize: CGSize(width: 1000, height: 500))
        XCTAssertEqual(brought.pages.count, 1)
        XCTAssertEqual(brought.failed, 1)
        XCTAssertEqual(SharedInbox.failureText(failed: brought.failed, total: brought.total), "Couldn't open 1 of 2 items")
        let shape = try XCTUnwrap(brought.pages.first?.elements.first)
        XCTAssertNotNil(shape.pathData)
        XCTAssertEqual(shape.w, 200)
        XCTAssertEqual(shape.x, 400)
        XCTAssertEqual(shape.y, 150)

        SharedInbox.remove(box.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: box.directory.path))
        XCTAssertNil(SharedInbox.open(box.id))
        XCTAssertNil(SharedInbox.land([design]), "nothing Canvia takes, nothing landed")
    }
}
