// The trimmer bar's rules (Trimming), the waveform's loudness
// (Peaks.buckets, the Android twin's table row for row), and the canvas
// showing a clip's frame where its handle is dragged.

import XCTest
@testable import Canvia

final class TrimmingTests: XCTestCase {

    // MARK: peaks

    /// The Android twin's TrimmerTest has these rows, in this order, value
    /// for value: change a row here and there together.
    func testPeaksAreTheRootMeanSquareOfEachBucket() {
        let rows: [(name: String, samples: [Float], n: Int, peaks: [Float])] = [
            ("alternating full scale", [1, -1, 1, -1], 2, [1, 1]),
            ("silence then a rise", [0, 0, 3, 4], 2, [0, 3.5355339]),
            ("silence then full", [0, 0, 1, 1], 2, [0, 1]),
            ("a half then silence", [0.5, -0.5, 0.5, -0.5, 0, 0], 3, [0.5, 0.5, 0]),
            // More buckets than samples: ⌊i × 3 / 4⌋ leaves the first empty.
            ("more buckets than samples", [0.6, 0.8, 0], 4, [0, 0.6, 0.8, 0]),
            ("fewer samples than buckets", [0.5], 2, [0, 0.5]),
            ("one bucket", [0.3, 0.4], 1, [0.3535534]),
            // Five into two: two, then three.
            ("five into two", [0, 1, 1, 1, 1], 2, [0.7071068, 1]),
            ("uneven buckets", [1, 2, 3, 4, 5, 6, 7], 3, [1.5811388, 3.5355339, 6.0553007]),
            ("a quiet hum", [0.1, -0.1, 0.1, -0.1, 0.1, -0.1], 3, [0.1, 0.1, 0.1]),
            ("nothing", [], 3, [0, 0, 0]),
            ("no buckets", [2, 2], 0, []),
        ]
        for row in rows {
            let got = Peaks.buckets(row.samples, row.n)
            XCTAssertEqual(got.count, row.peaks.count, row.name)
            for (g, w) in zip(got, row.peaks) { XCTAssertEqual(g, w, accuracy: 1e-5, row.name) }
        }
    }

    func testAWaveformIsDrawnAsASharesOfTheLoudest() {
        XCTAssertEqual(Peaks.normalised([1, 2, 4]), [0.25, 0.5, 1])
        XCTAssertEqual(Peaks.normalised([0, 0]), [0, 0])
        XCTAssertEqual(Peaks.normalised([]), [])
        XCTAssertEqual(Trimming.peakCount, 120)
    }

    func testPeaksAreKeptAsJSONByMusicId() throws {
        let id = "audio_test_\(UUID().uuidString).m4a"
        XCTAssertNil(Peaks.cached(id))
        let file = Peaks.directory.appendingPathComponent("\(id).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode([Float]([0.25, 0.5])).write(to: file)
        XCTAssertEqual(Peaks.cached(id), [0.25, 0.5])
        XCTAssertEqual(file.deletingLastPathComponent().lastPathComponent, "peaks")
    }

    // MARK: the bar

    func testAHandleStaysWithinTheFileAndTheShortestTrim() {
        let rows: [(grip: Trimming.Grip, to: Double, start: Double, end: Double)] = [
            (.start, 2, 2, 8),
            (.start, -1, 0, 8),
            (.start, 7.95, 7.9, 8),
            (.end, 9, 1, 9),
            (.end, 12, 1, 10),
            (.end, 1.02, 1, 1.1),
        ]
        for row in rows {
            let moved = Trimming.moved(row.grip, to: row.to, start: row.grip == .start ? 0 : 1,
                                       end: row.grip == .start ? 8 : 6, length: 10, minLength: 0.1)
            XCTAssertEqual(moved.start, row.start, accuracy: 1e-9, "\(row)")
            XCTAssertEqual(moved.end, row.end, accuracy: 1e-9, "\(row)")
        }
    }

    func testEightFramesAreTakenFromTheMiddleOfEachEighth() {
        XCTAssertEqual(Trimming.thumbnailCount, 8)
        let times = Trimming.thumbnailTimes(length: 16)
        XCTAssertEqual(times, [1, 3, 5, 7, 9, 11, 13, 15])
        XCTAssertEqual(Trimming.thumbnailTimes(length: 4, count: 2), [1, 3])
        XCTAssertTrue(Trimming.thumbnailTimes(length: 0).isEmpty)
    }

    func testLettingGoPlaysASecondAndAHalfOrToTheEnd() {
        XCTAssertEqual(Trimming.auditioned(start: 2, end: 10), 2...3.5)
        XCTAssertEqual(Trimming.auditioned(start: 2, end: 2.6), 2...2.6)
        XCTAssertEqual(Trimming.auditioned(start: 2, end: 1), 2...2)
    }

    func testTheBarReadsOutTheTrimAndItsLength() {
        // The Android twin's TrimmerTest reads these the same.
        XCTAssertEqual(Trimming.readout(start: 1, end: 4.5), "0:01.0 – 0:04.5 · 0:03.5")
        XCTAssertEqual(Trimming.readout(start: 2, end: 6), "0:02.0 – 0:06.0 · 0:04.0")
        XCTAssertEqual(Trimming.readout(start: 0, end: 75.25), "0:00.0 – 1:15.3 · 1:15.3")
        XCTAssertEqual(Trimming.barHeight, 56)
        XCTAssertEqual(Trimming.step, 0.1)
    }

    func testAPlaceOnTheBarIsATimeInTheFile() {
        XCTAssertEqual(Trimming.x(of: 5, length: 10, width: 300), 150)
        XCTAssertEqual(Trimming.x(of: 12, length: 10, width: 300), 300)
        XCTAssertEqual(Trimming.time(at: 75, length: 10, width: 300), 2.5)
        XCTAssertEqual(Trimming.time(at: -5, length: 10, width: 300), 0)
    }

    // MARK: the canvas

    func testTheScrubbedClipShowsTheFrameAtItsHandle() {
        let clip = Element.image(VideoStore.src("vid_1", at: nil))
        let photo = Element.image("asset:sun")
        let page = Page(elements: [clip, photo])
        let shown = Trimming.scrubbed(page, Trimming.Scrub(elementId: clip.id, time: 2.5))
        XCTAssertEqual(shown.elements[0].src, "video:vid_1@2.50")
        XCTAssertEqual(shown.elements[1], photo)
        XCTAssertEqual(Trimming.scrubbed(page, nil), page)
        // A photo is no clip: nothing to scrub.
        XCTAssertEqual(Trimming.scrubbed(page, Trimming.Scrub(elementId: photo.id, time: 1)), page)
    }

    @MainActor
    func testATrimIsOneStepAndScrubbingWritesNothing() {
        var design = Design(title: "trim", width: 1000, height: 1000)
        let clip = Element.image(VideoStore.src("vid_1", at: nil), w: 320, h: 180)
        design.pages[0].elements = [clip]
        let s = DesignStore(design: design)
        s.select(clip.id)
        s.clipScrub = Trimming.Scrub(elementId: clip.id, time: 3)
        XCTAssertNil(s.element(clip.id)?.clip)
        XCTAssertEqual(s.element(clip.id)?.src, "video:vid_1")
        s.clipScrub = nil
        s.setClip(ClipPlayback(start: 1.5, end: 4))
        XCTAssertEqual(s.element(clip.id)?.clip, ClipPlayback(start: 1.5, end: 4))
        s.undo()
        XCTAssertNil(s.element(clip.id)?.clip, "start and end in one step")
    }
}
