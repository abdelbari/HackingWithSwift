// Failed exports: why, plainly, and what to try next — the Android twin's
// ExportFailureTest, row for row.

import AVFoundation
import XCTest
@testable import Canvia

@MainActor
final class ExportFailureTests: XCTestCase {

    private struct Said: LocalizedError {
        let why: String
        var errorDescription: String? { why }
    }

    func testEachErrorIsReadAsItsKind() {
        XCTAssertEqual(ExportFailure.classify(Said(why: "write failed: ENOSPC (No space left on device)")), .noSpace)
        XCTAssertEqual(ExportFailure.classify(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)), .noSpace)
        XCTAssertEqual(ExportFailure.classify(Said(why: "trying to draw too large(120000000bytes) bitmap.")), .tooLarge)
        XCTAssertEqual(ExportFailure.classify(Said(why: "this phone has no video encoder for a design this shape")), .codec)
        XCTAssertEqual(ExportFailure.classify(NSError(domain: AVFoundationErrorDomain, code: -11800)), .codec)
        XCTAssertEqual(ExportFailure.classify(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)), .missingMedia)
        XCTAssertEqual(ExportFailure.classify(CancellationError()), .cancelled)
        XCTAssertEqual(ExportFailure.classify(Said(why: "no page to show")), .other)
        XCTAssertEqual(ExportFailure.classify(nil), .other)
    }

    /// The error under one that says nothing decides; the outermost that
    /// says something wins.
    func testACauseDecidesWhenTheErrorItselfSaysNothing() {
        let under = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let wrapped = NSError(domain: "export", code: 1, userInfo: [NSUnderlyingErrorKey: under])
        XCTAssertEqual(ExportFailure.classify(wrapped), .noSpace)
        let gone = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError,
                           userInfo: [NSUnderlyingErrorKey: Said(why: "out of memory")])
        XCTAssertEqual(ExportFailure.classify(gone), .missingMedia)
    }

    func testAPictureTooLargeIsTriedAt1xAFilmOneStepDownNoneBelow720p() throws {
        let png = ExportFailure.Asked(format: "png", scale: 3)
        let s = try XCTUnwrap(ExportFailure.suggestion(.tooLarge, settings: png))
        XCTAssertEqual(s.label, "Try at 1×")
        XCTAssertEqual(s.settings.scale, 1)
        XCTAssertNil(s.settings.longEdge)
        // A long edge typed is let go too.
        let typed = ExportFailure.Asked(format: "png", scale: 1, longEdge: 4000)
        XCTAssertEqual(ExportFailure.suggestion(.tooLarge, settings: typed)?.settings.scale, 1)
        XCTAssertNil(ExportFailure.suggestion(.tooLarge, settings: typed)?.settings.longEdge)
        // Already at 1×: nothing smaller.
        XCTAssertNil(ExportFailure.suggestion(.tooLarge, settings: ExportFailure.Asked(format: "png", scale: 1)))

        XCTAssertEqual(ExportFailure.suggestion(.codec, settings: ExportFailure.Asked(format: "mp4", maxEdge: 3840))?.label,
                       "Try at 1080p")
        XCTAssertEqual(ExportFailure.suggestion(.tooLarge, settings: ExportFailure.Asked(format: "mp4", maxEdge: 1920))?
                        .settings.maxEdge, 1280)
        XCTAssertNil(ExportFailure.suggestion(.codec, settings: ExportFailure.Asked(format: "mp4", maxEdge: 1280)))

        // A GIF is sized by its own budget, and a PDF, print or PowerPoint
        // file never reads the scale: smaller would make the same file.
        XCTAssertNil(ExportFailure.suggestion(.tooLarge, settings: ExportFailure.Asked(format: "gif", maxEdge: 1920)))
        for format in ["pdf", "print", "pptx"] {
            XCTAssertNil(ExportFailure.suggestion(.tooLarge, settings: ExportFailure.Asked(format: format, scale: 3)))
        }

        // Only a size or an encoder problem suggests trying smaller.
        XCTAssertNil(ExportFailure.suggestion(.noSpace, settings: png))
        XCTAssertNil(ExportFailure.suggestion(.other, settings: png))
        XCTAssertNil(ExportFailure.suggestion(.tooLarge, settings: nil))
    }

    func testEachKindSaysWhyPlainlyAMissingPhotoNamingItsPage() {
        XCTAssertEqual(ExportFailure.reasonText(.noSpace, page: nil), "There isn't enough space on this phone.")
        XCTAssertEqual(ExportFailure.reasonText(.missingMedia, page: 1), "A photo or clip on page 2 is missing.")
        XCTAssertEqual(ExportFailure.reasonText(.missingMedia, page: nil), "A photo or clip is missing.")
        XCTAssertEqual(ExportFailure.failedText(.tooLarge), "Export failed. It's too large to make at this size.")
        var photo = Element.shape("rect", w: 10, h: 10)
        photo.type = .image
        photo.src = "media:gone"
        var design = Design(title: "T", width: 100, height: 100)
        design.pages = [Page(), Page(elements: [photo])]
        XCTAssertEqual(ExportFailure.missingPage(design, pages: [0, 1]) { $0 != "media:gone" }, 1)
        XCTAssertNil(ExportFailure.missingPage(design, pages: [0, 1]) { _ in true })
    }

    func testAFailureIsKeptAsItsKindAndDesignsAndAtMostThreeAreKept() throws {
        let f = ExportFailure.Failure(kind: .noSpace, designIds: ["d1", "d2"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(data: try encoder.encode(f), encoding: .utf8), #"{"designIds":["d1","d2"],"kind":"noSpace"}"#)
        let read = try JSONDecoder().decode(ExportFailure.Failure.self,
                                            from: Data(#"{"kind":"noSpace","designIds":["d1","d2"]}"#.utf8))
        XCTAssertEqual(read, f)
        let lost = try JSONDecoder().decode(ExportFailure.Failure.self, from: Data(#"{"kind":"lost"}"#.utf8))
        XCTAssertEqual(lost.kind, .other)
        XCTAssertEqual(ExportFailure.kept([3, 2, 1], 4), [4, 3, 2])
    }

    /// A failure is kept to try again; Try again runs it once more, and a
    /// suggestion runs its smaller work.
    func testAFailedExportIsKeptAndTriedAgain() async throws {
        let queue = ExportQueue(host: .none)
        var made: [String] = []
        var tries = 0
        let retry = ExportQueue.Retry(design: nil, settings: ExportFailure.Asked(format: "png", scale: 3)) { settings in
            { _ in
                made.append("at \(settings.scale)")
                return ExportQueue.Result(urls: [URL(fileURLWithPath: "/tmp/small.png")])
            }
        }
        queue.enqueue(ExportQueue.Job(label: "Rendering", designId: "d", retry: retry) { _ in
            tries += 1
            throw Said(why: "too large to draw")
        })
        await queue.waitUntilIdle()
        let failed = try XCTUnwrap(queue.failedExports.first)
        XCTAssertEqual(failed.message, "Export failed. It's too large to make at this size.")
        XCTAssertEqual(failed.suggestion?.label, "Try at 1×")
        XCTAssertEqual(failed.failure, ExportFailure.Failure(kind: .tooLarge, designIds: ["d"]))
        queue.retry(failed.id)
        await queue.waitUntilIdle()
        XCTAssertEqual(tries, 2)
        // Failing again puts it back, once.
        XCTAssertEqual(queue.failedExports.count, 1)
        queue.retry(try XCTUnwrap(queue.failedExports.first).id, smaller: true)
        await queue.waitUntilIdle()
        XCTAssertEqual(made, ["at 1.0"])
        XCTAssertTrue(queue.failedExports.isEmpty)
        queue.enqueue(ExportQueue.Job(label: "Rendering", designId: "d") { _ in throw Said(why: "boom") })
        await queue.waitUntilIdle()
        let other = try XCTUnwrap(queue.failedExports.first)
        queue.dismissFailed(other.id)
        XCTAssertTrue(queue.failedExports.isEmpty)
    }
}
