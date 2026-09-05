// Video clips as elements: the source grammar, looping, and a real clip
// stored, read for its poster and frames, and recognised as animation.

import XCTest
import UIKit
@testable import Canvia

final class VideoElementTests: XCTestCase {

    func testSourceGrammarAndLooping() {
        XCTAssertTrue(VideoStore.isVideo("video:vid-1"))
        XCTAssertFalse(VideoStore.isVideo("media:img-1"))
        XCTAssertFalse(VideoStore.isVideo(nil))
        XCTAssertEqual(VideoStore.split("video:vid-1")?.id, "vid-1")
        XCTAssertNil(VideoStore.split("video:vid-1")?.time)
        let stamped = VideoStore.src("vid-1", at: 1.256)
        XCTAssertEqual(stamped, "video:vid-1@1.26")
        XCTAssertEqual(VideoStore.split(stamped)?.time ?? 0, 1.26, accuracy: 0.0001)
        XCTAssertNil(VideoStore.split("media:x"))
        XCTAssertEqual(VideoStore.loopedTime(7.5, duration: 3), 1.5, accuracy: 0.0001)
        XCTAssertEqual(VideoStore.loopedTime(2, duration: 3), 2, accuracy: 0.0001)
        XCTAssertEqual(VideoStore.loopedTime(5, duration: 0), 0)
    }

    @MainActor
    func testAStoredClipHasAPosterFramesAndALength() async throws {
        // Make a real clip: a one-page design as a short MP4.
        var d = Design(title: "clip", width: 320, height: 240)
        d.pages[0].background = .color("#2040ff")
        var m = MotionSettings(); m.secondsPerPage = 1; m.fps = 24; m.movement = false; m.crossfade = false
        d.motion = m
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID()).mp4")
        try await MovieExporter.exportMP4(design: d, settings: MovieExporter.Settings(d.motion), to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let id = try XCTUnwrap(VideoStore.store(data, ext: "mp4"))
        defer { VideoStore.delete(id) }
        XCTAssertNotNil(VideoStore.url(for: id))
        XCTAssertTrue(VideoStore.all().contains(id))
        XCTAssertEqual(try XCTUnwrap(VideoStore.duration(of: id)), 1, accuracy: 0.15)

        let poster = try XCTUnwrap(VideoStore.poster(id))
        XCTAssertEqual(poster.size.width / poster.size.height, 320.0 / 240.0, accuracy: 0.02)
        XCTAssertNotNil(VideoStore.frame(id, at: 0.5))
        XCTAssertNotNil(VideoStore.resolve(VideoStore.src(id, at: 2.4)), "past the end loops round")
        XCTAssertNotNil(PhotoLibrary.resolve(VideoStore.src(id, at: nil)), "an element source resolves to the poster")

        var page = Page()
        page.elements = [Element.image(VideoStore.src(id, at: nil), w: 160, h: 120)]
        XCTAssertTrue(MovieExporter.isAnimated(page), "a page with a clip renders frame by frame")
        XCTAssertFalse(MovieExporter.isAnimated(Page(elements: [Element.image("media:x", w: 10, h: 10)])))

        VideoStore.delete(id)
        XCTAssertNil(VideoStore.url(for: id))
    }
}
