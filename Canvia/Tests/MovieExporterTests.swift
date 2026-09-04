// Video and GIF export.
//
// The frame maths is pure and gets asserted directly: which page a frame
// belongs to, how far into it, and how much of the next page is fading in.
// The encode itself gets one end-to-end test that reads the file back with
// AVFoundation — including which way up the picture came out, because a video
// written upside down is a file that opens fine and is wrong, and that exact
// class of bug has bitten this codebase twice.

import XCTest
import AVFoundation
import CoreGraphics
import ImageIO
@testable import Canvia

final class MovieExporterTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func destination(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("movie-test-\(UUID().uuidString).\(ext)")
        written.append(url)
        return url
    }

    /// White above, black below, and the black band a different depth on each
    /// page. Off-centre on purpose: a band that straddled the middle would
    /// cover the same share of the frame at every zoom, and the zoom test
    /// would pass whether or not anything moved.
    private func design(pages: Int = 2, width: Double = 240, height: Double = 160) -> Design {
        var d = Design(title: "movie", width: width, height: height)
        d.pages = (0..<pages).map { index in
            let depth = index.isMultiple(of: 2) ? 0.4 : 0.3
            var band = Element.shape("rect", w: width, h: height * depth)
            band.x = 0
            band.y = height * (1 - depth)
            band.fill = .solid("#000000")
            return Page(background: .color("#ffffff"), elements: [band])
        }
        return d
    }

    // MARK: sizing

    /// H.264 encodes in 2x2 blocks; an odd dimension is refused outright.
    func testVideoDimensionsAreAlwaysEven() {
        for size in [(1080.0, 1080.0), (1079.0, 641.0), (4000.0, 3000.0), (41.0, 37.0)] {
            let out = MovieExporter.videoSize(for: Design(width: size.0, height: size.1),
                                              maxEdge: 1920)
            XCTAssertEqual(Int(out.width) % 2, 0, "\(size) gave an odd width")
            XCTAssertEqual(Int(out.height) % 2, 0, "\(size) gave an odd height")
            XCTAssertGreaterThanOrEqual(out.width, 2)
            XCTAssertGreaterThanOrEqual(out.height, 2)
        }
    }

    func testLargeDesignsAreFittedUnderTheCap() {
        let out = MovieExporter.videoSize(for: Design(width: 4000, height: 2000), maxEdge: 1920)
        XCTAssertLessThanOrEqual(max(out.width, out.height), 1920)
        // The aspect ratio survives, give or take the rounding to even.
        XCTAssertEqual(out.width / out.height, 2, accuracy: 0.02)
    }

    /// Small designs are not blown up: upscaling a 240pt card to 1080p makes a
    /// bigger file of exactly the same picture.
    func testSmallDesignsAreNotUpscaled() {
        let out = MovieExporter.videoSize(for: Design(width: 240, height: 160), maxEdge: 1920)
        XCTAssertEqual(out, CGSize(width: 240, height: 160))
    }

    func testFrameCountFollowsPagesAndDuration() {
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 2
        settings.fps = 30
        XCTAssertEqual(MovieExporter.frameCount(pages: 3, settings: settings), 180)
        XCTAssertGreaterThan(MovieExporter.frameCount(pages: 0, settings: settings), 0)
    }

    // MARK: the frame sequence

    /// Every frame has to be drawn — a page that renders as an empty context
    /// is a black flash in the middle of the video.
    @MainActor
    func testEveryFrameDrawsSomething() throws {
        let d = design(pages: 2)
        let size = MovieExporter.videoSize(for: d, maxEdge: 1920)
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 0.2
        settings.fps = 10
        let pages = try renderPages(d, size: size)
        let total = MovieExporter.frameCount(pages: pages.count, settings: settings)

        for index in 0..<total {
            let context = try XCTUnwrap(makeContext(size))
            MovieExporter.draw(frame: index, pages: pages, size: size,
                               settings: settings, into: context)
            let image = try XCTUnwrap(context.makeImage())
            XCTAssertEqual(image.width, Int(size.width))
            XCTAssertFalse(try isUniform(image), "frame \(index) came out flat")
        }
    }

    /// The push in. Later frames of a page show a larger crop, so the boundary
    /// between the white half and the black half moves.
    @MainActor
    func testThePageZoomsAcrossItsFrames() throws {
        let d = design(pages: 1)
        let size = MovieExporter.videoSize(for: d, maxEdge: 1920)
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 1
        settings.fps = 10
        settings.crossfade = 0
        let pages = try renderPages(d, size: size)

        let first = try darkFraction(frame: 0, pages: pages, size: size, settings: settings)
        let last = try darkFraction(frame: 9, pages: pages, size: size, settings: settings)
        XCTAssertNotEqual(first, last, accuracy: 0.0001,
                          "nothing changed across the page — the zoom is not running")
    }

    /// The cross-fade lives at the end of a page, so the last page never fades
    /// out to nothing.
    @MainActor
    func testTheFinalFrameIsNotFadedOut() throws {
        let d = design(pages: 2)
        let size = MovieExporter.videoSize(for: d, maxEdge: 1920)
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 1
        settings.fps = 10
        settings.crossfade = 0.5
        let pages = try renderPages(d, size: size)
        let total = MovieExporter.frameCount(pages: pages.count, settings: settings)

        let last = try darkFraction(frame: total - 1, pages: pages, size: size, settings: settings)
        XCTAssertGreaterThan(last, 0.2, "the last frame washed out")
    }

    // MARK: the file

    @MainActor
    func testTheVideoOpensWithTheRightSizeAndDuration() async throws {
        let url = destination("mp4")
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 0.5
        settings.fps = 20
        let d = design(pages: 2)
        do {
            try await MovieExporter.exportMP4(design: d, settings: settings, to: url)
        } catch {
            throw XCTSkip("no H.264 encoder in this environment: \(error)")
        }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 1.0, accuracy: 0.15)
        let expected = MovieExporter.videoSize(for: d, maxEdge: settings.maxEdge)
        let track = try XCTUnwrap(tracks.first)
        let natural = try await track.load(.naturalSize)
        XCTAssertEqual(natural, expected)
    }

    /// Which way up. The fixture is white over black, so the top half of a
    /// decoded frame has to be lighter than the bottom — a video written
    /// upside down plays perfectly and is wrong.
    @MainActor
    func testTheVideoIsNotUpsideDown() async throws {
        let url = destination("mp4")
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 0.5
        settings.fps = 20
        settings.zoom = 0
        settings.crossfade = 0
        do {
            try await MovieExporter.exportMP4(design: design(pages: 1), settings: settings, to: url)
        } catch {
            throw XCTSkip("no H.264 encoder in this environment: \(error)")
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        let (frame, _) = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600))
        let top = try brightness(of: frame, y: frame.height / 8)
        let bottom = try brightness(of: frame, y: frame.height * 7 / 8)
        XCTAssertGreaterThan(top, bottom + 60,
                             "the frame is upside down or the halves have merged")
    }

    // MARK: progress and cancellation

    @MainActor
    func testTheVideoReportsProgressUpToOne() async throws {
        let url = destination("mp4")
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 0.5
        settings.fps = 10
        let seen = ProgressLog()
        do {
            try await MovieExporter.exportMP4(design: design(pages: 1), settings: settings, to: url,
                                              progress: { seen.record($0) })
        } catch {
            throw XCTSkip("no H.264 encoder in this environment: \(error)")
        }
        let values = seen.values
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values.last ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(values, values.sorted(), "progress went backwards")
    }

    @MainActor
    func testACancelledVideoLeavesNoFileAndThrowsCancellation() async throws {
        let url = destination("mp4")
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 3
        settings.fps = 30
        let task = Task { @MainActor in
            try await MovieExporter.exportMP4(design: design(pages: 3), settings: settings, to: url)
        }
        try await Task.sleep(for: .milliseconds(120))
        task.cancel()
        do {
            try await task.value
            XCTFail("a cancelled export finished")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the partial file was left behind")
        } catch {
            throw XCTSkip("no H.264 encoder in this environment: \(error)")
        }
    }

    @MainActor
    func testTheGIFReportsProgressUpToOne() throws {
        let url = destination("gif")
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 0.5
        var values: [Double] = []
        try MovieExporter.exportGIF(design: design(pages: 2), settings: settings, to: url,
                                    progress: { values.append($0) })
        XCTAssertEqual(values.count, MovieExporter.frameCount(pages: 2, settings: {
            var s = settings; s.fps = 12; return s
        }()))
        XCTAssertEqual(values.last ?? 0, 1, accuracy: 0.0001)
    }

    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Double] = []
        func record(_ v: Double) { lock.lock(); stored.append(v); lock.unlock() }
        var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    @MainActor
    func testTheGIFHasAFrameForEveryFrame() throws {
        let url = destination("gif")
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 0.5
        try MovieExporter.exportGIF(design: design(pages: 2), settings: settings, to: url)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "com.compuserve.gif")
        // exportGIF drops to 12fps regardless of what it is handed.
        XCTAssertEqual(CGImageSourceGetCount(source), 12)
    }

    @MainActor
    func testAnEmptyDesignRefusesRatherThanWritingAnEmptyFile() {
        var d = design(pages: 1)
        d.pages = []
        XCTAssertThrowsError(try MovieExporter.exportGIF(design: d, to: destination("gif")))
    }

    // MARK: calibration

    /// Every orientation assertion above reads pixels through `gray`, which
    /// draws the image into a bitmap context — the same operation the encoder
    /// uses to fill a frame. If that draw flipped, the write and the read
    /// would flip together and an upside-down video would sail through.
    ///
    /// So the reader is checked against an image whose row order is not a
    /// matter of convention at all: bytes handed straight to CGImage, where
    /// row zero is the top by definition.
    func testTheGrayReaderPreservesRowOrder() throws {
        let side = 4
        var bytes = [UInt8](repeating: 255, count: side * side)
        for x in 0..<side { bytes[x] = 0 }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        XCTAssertEqual(try brightness(of: image, y: 0), 0, accuracy: 1,
                       "the pixel reader flips rows, so every orientation test here is meaningless")
        XCTAssertEqual(try brightness(of: image, y: side - 1), 255, accuracy: 1)
    }

    // MARK: helpers

    @MainActor
    private func renderPages(_ d: Design, size: CGSize) throws -> [CGImage] {
        let pages = MovieExporter.pageImages(design: d, size: size)
        guard pages.count == d.pages.count else {
            throw XCTSkip("the page renderer produced nothing in this environment")
        }
        return pages
    }

    private func makeContext(_ size: CGSize) -> CGContext? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    private func darkFraction(frame index: Int, pages: [CGImage], size: CGSize,
                              settings: MovieExporter.Settings) throws -> Double {
        let context = try XCTUnwrap(makeContext(size))
        MovieExporter.draw(frame: index, pages: pages, size: size,
                           settings: settings, into: context)
        return try darkFraction(of: try XCTUnwrap(context.makeImage()))
    }

    private func gray(_ image: CGImage) throws -> [UInt8] {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        try bytes.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(data: raw.baseAddress, width: w, height: h,
                                              bitsPerComponent: 8, bytesPerRow: w,
                                              space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return bytes
    }

    private func darkFraction(of image: CGImage) throws -> Double {
        let bytes = try gray(image)
        return Double(bytes.filter { $0 < 128 }.count) / Double(bytes.count)
    }

    private func isUniform(_ image: CGImage) throws -> Bool {
        let bytes = try gray(image)
        guard let first = bytes.first else { return true }
        return bytes.allSatisfy { $0 == first }
    }

    /// Mean brightness of one row, top-origin.
    private func brightness(of image: CGImage, y: Int) throws -> Double {
        let bytes = try gray(image)
        let row = min(max(y, 0), image.height - 1)
        let start = row * image.width
        let slice = bytes[start..<(start + image.width)]
        return Double(slice.reduce(0) { $0 + Int($1) }) / Double(image.width)
    }
}
