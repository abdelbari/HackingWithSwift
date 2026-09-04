// Video and animated-GIF export.
//
// A multi-page design is already a sequence; this turns it into one people can
// post. Every frame is drawn from the same page bitmaps the raster exporter
// produces, so a video is the design rather than a second rendering of it.
//
// Two things make it read as designed rather than as a flipbook: a slow push
// in on each page, and a cross-fade between them. Both are cheap — they are
// affine draws of a bitmap that is already in memory — and their absence is
// exactly what makes an auto-generated slideshow look auto-generated.
//
// Nothing here needs a network, an account or a codec licence: AVAssetWriter
// is in the SDK and ImageIO writes GIFs.

import AVFoundation
import CoreGraphics
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum MovieExporter {

    struct Settings {
        var secondsPerPage: Double = 2.5
        var fps: Int = 30
        /// H.264 on a phone is comfortable to 1080p; beyond that the encode
        /// takes longer than anyone will wait for a social post.
        var maxEdge: Double = 1920
        var zoom: Double = 0.06
        var crossfade: Double = 0.5

        init() {}

        /// The design's own motion settings, or the defaults when it has none.
        init(_ motion: MotionSettings?) {
            let m = motion ?? MotionSettings()
            secondsPerPage = min(max(m.secondsPerPage, MotionSettings.secondsRange.lowerBound),
                                 MotionSettings.secondsRange.upperBound)
            fps = MotionSettings.fpsChoices.contains(m.fps) ? m.fps : 30
            zoom = m.movement ? 0.06 : 0
            // A fade cannot outlast the page it fades from.
            crossfade = m.crossfade ? min(0.5, secondsPerPage / 2) : 0
        }
    }

    enum MovieError: LocalizedError {
        case nothingToRender, writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .nothingToRender: return "there was nothing to render"
            case .writerFailed(let why): return "the video could not be written (\(why))"
            }
        }
    }

    // MARK: sizing

    /// The video's pixel size: the design, fitted under `maxEdge`, rounded to
    /// even numbers because H.264 encodes in 2x2 blocks and an odd dimension
    /// is rejected outright by most encoders.
    static func videoSize(for design: Design, maxEdge: Double) -> CGSize {
        let longest = max(design.width, design.height, 1)
        let scale = min(1, maxEdge / longest)
        func even(_ v: Double) -> Double { max(2, (v * scale / 2).rounded() * 2) }
        return CGSize(width: even(design.width), height: even(design.height))
    }

    static func frameCount(pages: Int, settings: Settings) -> Int {
        max(1, pages) * max(1, Int((settings.secondsPerPage * Double(settings.fps)).rounded()))
    }

    // MARK: frames

    /// One bitmap per page, at the output size. Rendered once and reused for
    /// every frame of that page — re-rendering the SwiftUI tree seventy-five
    /// times per page would take longer than the encode.
    @MainActor
    static func pageImages(design: Design, size: CGSize) -> [CGImage] {
        design.pages.compactMap { page in
            autoreleasepool { () -> CGImage? in
                let renderer = ImageRenderer(content: PageRenderView(design: design, page: page))
                renderer.scale = size.width / max(design.width, 1)
                renderer.isOpaque = true
                return renderer.cgImage
            }
        }
    }

    /// Draw one frame of the sequence into `context`.
    ///
    /// Split out and given no dependency on AVFoundation so the frame maths —
    /// which page, how far into it, how much zoom, how much of the next page
    /// is showing — can be exercised on its own.
    static func draw(frame index: Int, pages: [CGImage], size: CGSize,
                     settings: Settings, into context: CGContext) {
        guard !pages.isEmpty else { return }
        let perPage = max(1, Int((settings.secondsPerPage * Double(settings.fps)).rounded()))
        let page = min(index / perPage, pages.count - 1)
        let progress = Double(index % perPage) / Double(perPage)

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        context.interpolationQuality = .high

        drawPage(pages[page], progress: progress, alpha: 1,
                 size: size, settings: settings, into: context)

        // The fade lives at the end of a page rather than the start of the
        // next, so the last page never fades into nothing.
        let fadeFrames = Int((settings.crossfade * Double(settings.fps)).rounded())
        let remaining = perPage - (index % perPage)
        if page + 1 < pages.count, fadeFrames > 0, remaining <= fadeFrames {
            let alpha = 1 - Double(remaining) / Double(fadeFrames)
            drawPage(pages[page + 1], progress: 0, alpha: alpha,
                     size: size, settings: settings, into: context)
        }
    }

    private static func drawPage(_ image: CGImage, progress: Double, alpha: Double,
                                 size: CGSize, settings: Settings, into context: CGContext) {
        let scale = 1 + settings.zoom * progress
        let width = size.width * scale, height = size.height * scale
        let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                          width: width, height: height)
        context.saveGState()
        context.setAlpha(alpha)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    // MARK: mp4

    /// Progress is reported as a fraction of frames written, from the writer's
    /// own queue. Cancelling the surrounding task stops the writer at the next
    /// frame, discards the partial file and throws CancellationError.
    @MainActor
    static func exportMP4(design: Design, settings: Settings = Settings(), to url: URL,
                          progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try? FileManager.default.removeItem(at: url)
        let size = videoSize(for: design, maxEdge: settings.maxEdge)
        let pages = pageImages(design: design, size: size)
        guard !pages.isEmpty else { throw MovieError.nothingToRender }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ])
        guard writer.canAdd(input) else { throw MovieError.writerFailed("the encoder refused the input") }
        writer.add(input)
        guard writer.startWriting() else {
            throw MovieError.writerFailed(writer.error?.localizedDescription ?? "it would not start")
        }
        writer.startSession(atSourceTime: .zero)

        let total = frameCount(pages: pages.count, settings: settings)
        let state = WriteState()
        let queue = DispatchQueue(label: "canvia.movie.write")

        do {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard !state.finished else { return }
                    if state.cancelled {
                        state.finished = true
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if state.index >= total {
                        state.finished = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    guard let pool = adaptor.pixelBufferPool,
                          let buffer = makeBuffer(from: pool) else {
                        state.finished = true
                        continuation.resume(throwing: MovieError.writerFailed("no pixel buffer"))
                        return
                    }
                    fill(buffer, frame: state.index, pages: pages, size: size, settings: settings)
                    let time = CMTime(value: CMTimeValue(state.index),
                                      timescale: CMTimeScale(settings.fps))
                    guard adaptor.append(buffer, withPresentationTime: time) else {
                        state.finished = true
                        let why = writer.error?.localizedDescription ?? "a frame was rejected"
                        continuation.resume(throwing: MovieError.writerFailed(why))
                        return
                    }
                    state.index += 1
                    progress?(Double(state.index) / Double(total))
                }
            }
            }
        } onCancel: {
            // Seen by the writer callback on its next frame; the callback is
            // the one that resumes, so the continuation is never resumed
            // twice.
            state.cancelled = true
        }
        } catch {
            // Cancelled or failed: either way a partial MP4 is worse than
            // none, because it opens and plays and stops early.
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw MovieError.writerFailed(writer.error?.localizedDescription ?? "the writer stopped early")
        }
    }

    /// Mutable state shared with the writer's callback, which is invoked
    /// repeatedly and must resume its continuation exactly once.
    ///
    /// Unchecked because every access is on the writer's serial queue, except
    /// the cancel flag, which is a single Bool store that the next callback
    /// iteration reads — a stale read costs one more frame, never a crash.
    private final class WriteState: @unchecked Sendable {
        var index = 0
        var finished = false
        var cancelled = false
    }

    private static func makeBuffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess else {
            return nil
        }
        return buffer
    }

    private static func fill(_ buffer: CVPixelBuffer, frame index: Int, pages: [CGImage],
                             size: CGSize, settings: Settings) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        draw(frame: index, pages: pages, size: size, settings: settings, into: context)
    }

    // MARK: gif

    /// A GIF at the video's frame rate would be tens of megabytes, so it gets
    /// its own: fewer frames a second and a smaller frame.
    @MainActor
    static func exportGIF(design: Design, settings: Settings = Settings(), to url: URL,
                          progress: ((Double) -> Void)? = nil) throws {
        var gifSettings = settings
        gifSettings.fps = 12
        gifSettings.maxEdge = min(settings.maxEdge, 640)

        let size = videoSize(for: design, maxEdge: gifSettings.maxEdge)
        let pages = pageImages(design: design, size: size)
        guard !pages.isEmpty else { throw MovieError.nothingToRender }

        let total = frameCount(pages: pages.count, settings: gifSettings)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, total, nil) else {
            throw MovieError.writerFailed("no GIF destination")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1.0 / Double(gifSettings.fps),
            ],
        ] as CFDictionary

        for index in 0..<total {
            // Between frames, not mid-frame: a frame takes milliseconds and a
            // half-drawn one is never written.
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: url)
                throw CancellationError()
            }
            try autoreleasepool {
                guard let context = CGContext(
                    data: nil, width: Int(size.width), height: Int(size.height),
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue) else {
                    throw MovieError.writerFailed("a frame context would not open")
                }
                draw(frame: index, pages: pages, size: size, settings: gifSettings, into: context)
                guard let frame = context.makeImage() else {
                    throw MovieError.writerFailed("a frame would not render")
                }
                CGImageDestinationAddImage(destination, frame, frameProperties)
            }
            progress?(Double(index + 1) / Double(total))
        }
        guard CGImageDestinationFinalize(destination) else {
            throw MovieError.writerFailed("the GIF would not finalise")
        }
    }
}
