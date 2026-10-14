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
            case .nothingToRender: return tr("there was nothing to render")
            case .writerFailed(let why): return tr("the video could not be written (%@)", why)
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

    // MARK: timeline

    static let transitions = ["fade", "cut", "slide", "push", "wipe", "circle", "zoom"]

    /// One page's stretch of the sequence: where it starts, how many frames
    /// it holds, and how it hands over to the next — and how long that
    /// takes, when the page says.
    struct Timing: Equatable {
        var start: Int
        var frames: Int
        var transition: String
        var transitionSeconds: Double? = nil
        var end: Int { start + frames }
    }

    /// Each page's own hold and transition, falling back to the document's,
    /// for the pages in `pages` — the design's indices, in the order they
    /// play. Taken by index rather than from a filtered copy of the design,
    /// so a hidden master page still draws behind the pages that show it.
    static func timeline(design: Design, pages: [Int], settings: Settings) -> [Timing] {
        var start = 0
        return pages.map { index in
            let page = design.pages[index]
            let seconds = min(max(page.holdSeconds ?? settings.secondsPerPage, 0.1), 60)
            let frames = max(1, Int((seconds * Double(settings.fps)).rounded()))
            let transition = page.transition ?? (settings.crossfade > 0 ? "fade" : "cut")
            defer { start += frames }
            return Timing(start: start, frames: frames, transition: transition,
                          transitionSeconds: PageTransitions.seconds(page.transitionSeconds))
        }
    }

    /// The pages not hidden, which are what a video plays, as Present
    /// shows them.
    static func timeline(design: Design, settings: Settings) -> [Timing] {
        timeline(design: design, pages: design.visiblePageIndices, settings: settings)
    }

    /// Uniform timings for a page count, which is what the settings alone
    /// describe.
    static func uniformTimeline(pages: Int, settings: Settings) -> [Timing] {
        let perPage = max(1, Int((settings.secondsPerPage * Double(settings.fps)).rounded()))
        return (0..<max(1, pages)).map {
            Timing(start: $0 * perPage, frames: perPage, transition: settings.crossfade > 0 ? "fade" : "cut")
        }
    }

    static func frameCount(design: Design, settings: Settings) -> Int {
        timeline(design: design, settings: settings).last?.end ?? 1
    }

    /// How long the film runs, in seconds: every page shown at its own hold.
    static func seconds(design: Design, settings: Settings) -> Double {
        Double(frameCount(design: design, settings: settings)) / Double(max(settings.fps, 1))
    }

    /// The same for the pages Export plays: all shown, the page on screen
    /// (`current`), or those chosen.
    static func seconds(design: Design, settings: Settings, range: DesignExporter.PageRange,
                        current: Int) -> Double {
        let pages = playedPages(design: design, range: range, current: current)
        let frames = timeline(design: design, pages: pages, settings: settings).last?.end ?? 1
        return Double(frames) / Double(max(settings.fps, 1))
    }

    /// The pages a video plays, by index, in the design's order: every page
    /// shown, as Present shows them, for `.all`; the page on screen; or the
    /// pages chosen in Export — a hidden one too, since it was ticked.
    static func playedPages(design: Design, range: DesignExporter.PageRange, current: Int) -> [Int] {
        range.indices(in: design, current: current)
    }

    // MARK: resolution

    /// The video's size as Export offers it: 720p, 1080p or 4K, each a
    /// longest side the design is fitted under — never enlarged past its
    /// own pixels — with the same frame maths as on Android.
    enum Resolution: String, CaseIterable, Identifiable {
        case hd = "720p", fullHD = "1080p", uhd = "4K"

        var id: String { rawValue }

        var maxEdge: Double {
            switch self {
            case .hd: return 1280
            case .fullHD: return 1920
            case .uhd: return 3840
            }
        }

        static let standard = Resolution.fullHD
    }

    /// Whether this phone's encoder takes `design` as a 4K H.264 video —
    /// its own size fitted under 3840, a tall print page as well as a wide
    /// one — as the Android twin asks its encoder of each design. 4K is
    /// offered only then.
    static func supports4K(for design: Design) -> Bool {
        encoderTakes(videoSize(for: design, maxEdge: Resolution.uhd.maxEdge))
    }

    /// The resolutions this phone can make of `design`.
    static func resolutions(for design: Design) -> [Resolution] {
        Resolution.allCases.filter { $0 != .uhd || supports4K(for: design) }
    }

    private static let probeLock = NSLock()
    private static var probed: [String: Bool] = [:]

    /// Whether the H.264 encoder takes a video of `size`: the settings and
    /// an input for them, asked of a writer that never starts. Asked once
    /// per size.
    static func encoderTakes(_ size: CGSize) -> Bool {
        let key = "\(Int(size.width))x\(Int(size.height))"
        probeLock.lock()
        defer { probeLock.unlock() }
        if let known = probed[key] { return known }
        let probe = FileManager.default.temporaryDirectory
            .appendingPathComponent("canvia-size-probe-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: probe) }
        var takes = false
        if let writer = try? AVAssetWriter(outputURL: probe, fileType: .mp4) {
            let settings = videoSettings(size)
            if writer.canApply(outputSettings: settings, forMediaType: .video) {
                takes = writer.canAdd(AVAssetWriterInput(mediaType: .video, outputSettings: settings))
            }
        }
        probed[key] = takes
        return takes
    }

    /// The H.264 settings for a video of `size`.
    static func videoSettings(_ size: CGSize) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
    }

    /// The page a frame belongs to, and how far through it.
    static func locate(frame index: Int, in timings: [Timing]) -> (page: Int, progress: Double, remaining: Int) {
        guard !timings.isEmpty else { return (0, 0, 1) }
        let page = timings.lastIndex { $0.start <= index } ?? 0
        let t = timings[page]
        let into = min(max(index - t.start, 0), t.frames - 1)
        return (page, Double(into) / Double(t.frames), t.frames - into)
    }

    // MARK: gif budget

    /// A GIF stores every frame in full; a size that is fine as H.264 is
    /// tens of megabytes as GIF. Given a byte budget, pick the largest frame
    /// and the higher of two honest frame rates that fit.
    ///
    /// Honest because GIF delays are whole hundredths of a second: 12fps is
    /// stored as 0.08s and plays at 12.5, 30fps as 0.03 and plays at 33.
    /// 20fps (0.05) and 10fps (0.10) play at exactly what they say.
    struct GIFPlan: Equatable {
        var maxEdge: Double
        var fps: Int
        var delay: Double { 1 / Double(fps) }
    }

    static let gifBudget = 8_000_000

    static func gifPlan(design: Design, settings: Settings, budget: Int = gifBudget,
                        range: DesignExporter.PageRange = .all, current: Int = 0) -> GIFPlan {
        let played = playedPages(design: design, range: range, current: current)
        let seconds = timeline(design: design, pages: played, settings: settings)
            .reduce(0.0) { $0 + Double($1.frames) / Double(max(settings.fps, 1)) }
        let aspect = max(design.width, 1) / max(design.height, 1)
        var last = GIFPlan(maxEdge: 240, fps: 10)
        for fps in [20, 10] {
            for edge in [640.0, 480, 360, 240] {
                let w = aspect >= 1 ? edge : edge * aspect
                let h = aspect >= 1 ? edge / aspect : edge
                // About 0.35 bytes a pixel a frame for LZW on flat design
                // content; photos run higher, and the budget has slack.
                let bytes = w * h * seconds * Double(fps) * 0.35
                last = GIFPlan(maxEdge: edge, fps: fps)
                if bytes <= Double(budget) { return last }
            }
        }
        return last
    }

    // MARK: frames

    /// Whether a page has to be rendered frame by frame: anything on it
    /// moves — arriving, leaving, looping, drifting, playing, an animated
    /// picture going round, showing for part of the page — or anything
    /// the master page draws behind it does. A master's
    /// looping clip or pulsing logo plays through every page that shows it,
    /// in Present and on the Android twin's video alike, so it has to here
    /// too rather than sit on its first frame.
    static func isAnimated(_ page: Page, in design: Design) -> Bool {
        design.drawnElements(on: page).contains {
            $0.animation != nil || $0.exitAnimation != nil || $0.kenBurns != nil || VideoStore.isVideo($0.src)
                || AnimStore.isAnim($0.src) || $0.timing != nil
        }
    }

    /// A page at a moment, for animated pages: the same render as the page
    /// bitmap, with the clock set. Its clips are asked for frame after
    /// frame, and read in order (ClipReader).
    @MainActor
    static func animatedFrame(design: Design, page: Int, time: Double, hold: Double, size: CGSize) -> CGImage? {
        guard design.pages.indices.contains(page), isAnimated(design.pages[page], in: design) else { return nil }
        return autoreleasepool { () -> CGImage? in
            let renderer = ImageRenderer(content: PageRenderView(design: design, page: design.pages[page])
                .environment(\.animationTime, (time, hold))
                .environment(\.clipsInOrder, true))
            renderer.scale = renderScale(for: design.size(for: design.pages[page]), in: size)
            renderer.isOpaque = true
            return renderer.cgImage
        }
    }

    /// The scale that fits a page of `page` size inside the video frame.
    static func renderScale(for page: CGSize, in size: CGSize) -> CGFloat {
        min(size.width / max(page.width, 1), size.height / max(page.height, 1))
    }

    /// Where a page bitmap sits in the frame: filling it when the shapes
    /// agree, letterboxed and centred when a page has a size of its own.
    static func fitRect(image: CGSize, in size: CGSize) -> CGRect {
        let s = min(size.width / max(image.width, 1), size.height / max(image.height, 1))
        let w = image.width * s, h = image.height * s
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// One bitmap per page shown, at the output size, in the order they
    /// play. Rendered once and reused for every frame of that page —
    /// re-rendering the SwiftUI tree seventy-five times per page would take
    /// longer than the encode.
    @MainActor
    static func pageImages(design: Design, size: CGSize) -> [CGImage] {
        design.visiblePageIndices.compactMap { index -> CGImage? in
            let page = design.pages[index]
            return autoreleasepool { () -> CGImage? in
                let renderer = ImageRenderer(content: PageRenderView(design: design, page: page))
                renderer.scale = renderScale(for: design.size(for: page), in: size)
                renderer.isOpaque = true
                return renderer.cgImage
            }
        }
    }

    /// The same, a page at a time with a pause between pages, so the sheet
    /// stays live and a Cancel lands before the frames are written.
    @MainActor
    private static func pageImages(design: Design, pages indices: [Int], size: CGSize,
                                   pacer: inout DesignExporter.Pacer) async throws -> [CGImage] {
        var images: [CGImage] = []
        for index in indices {
            try await pacer.breathe()
            let page = design.pages[index]
            let image = autoreleasepool { () -> CGImage? in
                let renderer = ImageRenderer(content: PageRenderView(design: design, page: page))
                renderer.scale = renderScale(for: design.size(for: page), in: size)
                renderer.isOpaque = true
                return renderer.cgImage
            }
            if let image { images.append(image) }
        }
        return images
    }

    /// Draw one frame of the sequence into `context`.
    ///
    /// Split out and given no dependency on AVFoundation so the frame maths —
    /// which page, how far into it, how much zoom, how much of the next page
    /// is showing — can be exercised on its own.
    static func draw(frame index: Int, pages: [CGImage], size: CGSize,
                     settings: Settings, into context: CGContext) {
        draw(frame: index, pages: pages, size: size, settings: settings, timings: nil, into: context)
    }

    static func draw(frame index: Int, pages: [CGImage], size: CGSize,
                     settings: Settings, timings: [Timing]?, into context: CGContext) {
        draw(frame: index, pages: pages, size: size, settings: settings, timings: timings,
             animated: nil, into: context)
    }

    /// A page whose elements animate is rendered per frame by `animated`
    /// (page index, seconds into the page, the page's hold in seconds);
    /// pages that do not use the one bitmap in `pages`.
    static func draw(frame index: Int, pages: [CGImage], size: CGSize,
                     settings: Settings, timings: [Timing]?,
                     animated: ((Int, Double, Double) -> CGImage?)?, into context: CGContext) {
        guard !pages.isEmpty else { return }
        let timeline = timings ?? uniformTimeline(pages: pages.count, settings: settings)
        let where_ = locate(frame: index, in: timeline)
        let page = min(where_.page, pages.count - 1)
        let progress = where_.progress
        let timing = timeline[min(page, timeline.count - 1)]
        let hold = Double(timing.frames) / Double(max(settings.fps, 1))
        let seconds = Double(index - timing.start) / Double(max(settings.fps, 1))

        // White behind a page that fills the frame; black bars behind one
        // shaped unlike the video.
        let fitted = fitRect(image: CGSize(width: pages[page].width, height: pages[page].height), in: size)
        let letterboxed = fitted.width < size.width - 0.5 || fitted.height < size.height - 0.5
        context.setFillColor(gray: letterboxed ? 0 : 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        context.interpolationQuality = .high

        // The transition lives at the end of a page rather than the start of
        // the next, so the last page never fades into nothing.
        let transition = timing.transition
        let overlap = Int((overlapSeconds(timing, settings: settings) * Double(settings.fps)).rounded())
        let remaining = where_.remaining
        let leaving = animated?(page, seconds, hold) ?? pages[page]
        guard page + 1 < pages.count, transition != "cut", overlap > 0, remaining <= overlap else {
            drawPage(leaving, progress: progress, alpha: 1, size: size, settings: settings, into: context)
            return
        }
        let t = 1 - Double(remaining) / Double(overlap)
        // A page that moves comes in as it opens, its entrances still to
        // play, not as it ends — as the Android twin draws it.
        let coming = animated?(page + 1, 0, 0) ?? pages[page + 1]
        // Both pages as PageTransitions lays them out, the next one on top;
        // a kind this build does not know is drawn as a fade.
        let layers = PageTransitions.layers(transition, t: t, forward: true)
        drawLayer(layers.outgoing, leaving, progress: progress, size: size, settings: settings, into: context)
        drawLayer(layers.incoming, coming, progress: 0, size: size, settings: settings, into: context)
    }

    /// How long a page hands over to the next, in seconds: its own length,
    /// else the cross-fade, but never under half a second; none for a cut.
    static func overlapSeconds(_ timing: Timing, settings: Settings) -> Double {
        guard timing.transition != "cut" else { return 0 }
        return timing.transitionSeconds ?? max(settings.crossfade, 0.5)
    }

    /// One page of a transition: clipped to a strip from the left or a
    /// circle from the centre, then shifted and scaled about the centre.
    private static func drawLayer(_ layer: PageTransitions.Layer, _ image: CGImage, progress: Double,
                                  size: CGSize, settings: Settings, into context: CGContext) {
        guard layer.alpha > 0 else { return }
        context.saveGState()
        switch layer.clip {
        case .none:
            break
        case .rect(let fraction):
            context.clip(to: CGRect(x: 0, y: 0, width: size.width * fraction, height: size.height))
        case .circle(let fraction):
            let radius = fraction * hypot(size.width, size.height) / 2
            context.addEllipse(in: CGRect(x: size.width / 2 - radius, y: size.height / 2 - radius,
                                          width: radius * 2, height: radius * 2))
            context.clip()
        }
        context.translateBy(x: size.width / 2 + size.width * layer.dx, y: size.height / 2)
        context.scaleBy(x: layer.scale, y: layer.scale)
        context.translateBy(x: -size.width / 2, y: -size.height / 2)
        drawPage(image, progress: progress, alpha: layer.alpha, size: size, settings: settings, into: context)
        context.restoreGState()
    }

    private static func drawPage(_ image: CGImage, progress: Double, alpha: Double,
                                 size: CGSize, settings: Settings, into context: CGContext) {
        let fitted = fitRect(image: CGSize(width: image.width, height: image.height), in: size)
        let scale = 1 + settings.zoom * progress
        let width = fitted.width * scale, height = fitted.height * scale
        let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                          width: width, height: height)
        context.saveGState()
        context.setAlpha(alpha)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    // MARK: mp4

    /// What came of a video export besides the file.
    struct Outcome: Equatable {
        /// The design has music or clip sound, but some of it could not be
        /// put under the picture, so the video is without it — said, rather
        /// than failing the export.
        var musicLost = false
    }

    /// Progress is reported as a fraction of frames written. Frames are drawn
    /// and handed to the writer here on the main actor, one at a time;
    /// cancelling the surrounding task stops at the next frame, discards
    /// the partial file and throws CancellationError.
    ///
    /// Returns whether sound — the soundtrack, or a clip's own — was meant
    /// to go under the picture and could not be mixed in: the picture is
    /// kept without it, rather than nothing, as the Android twin keeps it,
    /// and the caller says so.
    @MainActor
    @discardableResult
    static func exportMP4(design: Design, settings: Settings = Settings(),
                          range: DesignExporter.PageRange = .all, current: Int = 0, to url: URL,
                          progress: (@Sendable (Double) -> Void)? = nil) async throws -> Outcome {
        // The clips' readers let go once the frames are written, or not.
        defer { ClipReaders.closeAll() }
        try? FileManager.default.removeItem(at: url)
        var size = videoSize(for: design, maxEdge: settings.maxEdge)
        var pacer = DesignExporter.Pacer()
        // The pages Present shows: hidden ones are left out of the video,
        // and so of the length its music is fitted to, and their clips out
        // of its sound. Or the pages chosen in Export, in order.
        let shown = playedPages(design: design, range: range, current: current)
        var pages = try await pageImages(design: design, pages: shown, size: size, pacer: &pacer)
        guard !pages.isEmpty else { throw MovieError.nothingToRender }

        let timings = timeline(design: design, pages: shown, settings: settings)
        let total = timings.last?.end ?? 1

        // Opened once the page bitmaps are drawn, so a Cancel meanwhile
        // leaves no file to clean up. An encoder that will not take the
        // design at 4K after all makes it at 1080p rather than nothing, as
        // the Android twin steps down.
        let opened: OpenWriter
        do {
            opened = try openWriter(url: url, size: size)
        } catch where settings.maxEdge > Resolution.fullHD.maxEdge {
            size = videoSize(for: design, maxEdge: Resolution.fullHD.maxEdge)
            pages = try await pageImages(design: design, pages: shown, size: size, pacer: &pacer)
            opened = try openWriter(url: url, size: size)
        }
        let writer = opened.writer
        let input = opened.input
        let adaptor = opened.adaptor
        let frameSize = size
        let stills = pages

        // An animated page is drawn as each of its frames is written, here
        // on the main actor where SwiftUI draws, so only one frame of it is
        // held at a time: rendered all ahead, a 4K A4 page ran to gigabytes.
        // Each place keeps its last frame, so a page coming in under a
        // transition is drawn once rather than for every frame of it.
        let fps = Double(max(settings.fps, 1))
        let moving = Set(timings.indices.filter { $0 < shown.count && isAnimated(design.pages[shown[$0]], in: design) })
        var recent: [Int: (frame: Int, image: CGImage)] = [:]
        var animated: ((Int, Double, Double) -> CGImage?)?
        if !moving.isEmpty {
            animated = { (place: Int, seconds: Double, _: Double) -> CGImage? in
                guard moving.contains(place) else { return nil }
                let timing = timings[place]
                let f = min(max(Int((seconds * fps).rounded()), 0), max(timing.frames - 1, 0))
                if let kept = recent[place], kept.frame == f { return kept.image }
                guard let image = animatedFrame(design: design, page: shown[place], time: Double(f) / fps,
                                                hold: Double(timing.frames) / fps, size: frameSize) else { return nil }
                recent = recent.filter { abs($0.key - place) <= 1 }
                recent[place] = (frame: f, image: image)
                return image
            }
        }
        let drawsMoving = animated

        do {
            for index in 0..<total {
                // Between frames, not mid-frame, so the sheet stays live and
                // a Cancel lands before the next one.
                try await pacer.breathe()
                while !input.isReadyForMoreMediaData {
                    // A writer that has failed is never ready again.
                    guard writer.status == .writing else {
                        throw MovieError.writerFailed(writer.error?.localizedDescription ?? "the writer stopped early")
                    }
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                guard let pool = adaptor.pixelBufferPool,
                      let buffer = makeBuffer(from: pool) else {
                    throw MovieError.writerFailed("no pixel buffer")
                }
                autoreleasepool {
                    fill(buffer, frame: index, pages: stills, size: frameSize, settings: settings,
                         timings: timings, animated: drawsMoving)
                }
                let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(settings.fps))
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw MovieError.writerFailed(writer.error?.localizedDescription ?? "a frame was rejected")
                }
                progress?(Double(index + 1) / Double(total))
            }
            input.markAsFinished()
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

        // The sound goes under the finished picture — each clip's own on its
        // page, and the music (AudioMix.plan) — muxed into a sibling file,
        // which then takes the video's place. Sound that will not go in
        // costs the sound, not the video: the picture is kept, with what
        // would go in or silent, and the outcome says so — as on the
        // Android twin.
        let mix = await soundMix(design: design, pages: shown, timings: timings, settings: settings)
        guard !mix.segments.isEmpty else { return Outcome(musicLost: mix.lost) }
        let withSound = url.deletingPathExtension().appendingPathExtension("sound.mp4")
        do {
            let whole = try await Soundtrack.mux(video: url, segments: mix.segments, sources: mix.sources, to: withSound)
            try Task.checkCancellation()
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: withSound, to: url)
            return Outcome(musicLost: mix.lost || !whole)
        } catch {
            try? FileManager.default.removeItem(at: withSound)
            if error is CancellationError || Task.isCancelled {
                try? FileManager.default.removeItem(at: url)
                throw CancellationError()
            }
            // The silent picture is only there if the swap never started.
            guard FileManager.default.fileExists(atPath: url.path) else { throw error }
            return Outcome(musicLost: true)
        }
    }

    /// What is heard under the video of `pages` (the design's indices, as
    /// they play, timed by `timings`): the plan, the file each of its
    /// sources is read from, and whether music there was could not be read.
    /// A clip filmed without sound, or not on this phone, is silent, and a
    /// track whose music this phone does not have — chosen on another — is
    /// no music.
    @MainActor
    static func soundMix(design: Design, pages: [Int], timings: [Timing],
                         settings: Settings) async -> (segments: [AudioMix.Segment], sources: [String: URL], lost: Bool) {
        let clipsByPage = pages.map { AudioMix.clips(design: design, page: design.pages[$0]) }
        var sources: [String: URL] = [:]
        var durations: [String: Double] = [:]
        var lost = false
        var seen = Set<String>()
        for clip in clipsByPage.joined() where seen.insert(clip.source).inserted {
            guard let file = VideoStore.url(for: clip.source),
                  let seconds = await VideoStore.soundLength(of: clip.source) else { continue }
            durations[clip.source] = seconds
            sources[clip.source] = file
        }
        // Each track's music once, however many tracks play it.
        var trackDurations: [String: Double] = [:]
        var heard = Set<String>()
        for track in design.audioTracks where track.volume > 0 {
            guard let id = track.audioId, heard.insert(id).inserted, let file = AudioStore.url(for: id) else { continue }
            if let seconds = await AudioStore.duration(of: id), seconds > 0 {
                trackDurations[id] = seconds
                sources[id] = file
            } else {
                lost = true
            }
        }
        let segments = AudioMix.plan(timeline: timings, fps: settings.fps, clipsByPage: clipsByPage,
                                     clipDurations: durations, tracks: design.audioTracks,
                                     trackDurations: trackDurations)
        return (segments, sources, lost)
    }

    /// A writer started on a video of one size, its input and the adaptor
    /// frames are handed to.
    private struct OpenWriter {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
    }

    /// An H.264 writer at `url` for a video of `size`, started; throws when
    /// the encoder will not take that size, leaving no file.
    private static func openWriter(url: URL, size: CGSize) throws -> OpenWriter {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings = videoSettings(size)
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw MovieError.writerFailed("the encoder refused the size")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
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
            let why = writer.error?.localizedDescription ?? "it would not start"
            try? FileManager.default.removeItem(at: url)
            throw MovieError.writerFailed(why)
        }
        writer.startSession(atSourceTime: .zero)
        return OpenWriter(writer: writer, input: input, adaptor: adaptor)
    }

    private static func makeBuffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess else {
            return nil
        }
        return buffer
    }

    /// How many frames `animatedFrames` renders ahead: every frame of every
    /// animated page among `pages`, whose timings are `timings`.
    static func animatedFrameCount(design: Design, pages: [Int], timings: [Timing]) -> Int {
        timings.indices
            .filter { $0 < pages.count && isAnimated(design.pages[pages[$0]], in: design) }
            .reduce(0) { $0 + timings[$1].frames }
    }

    /// Every frame of every animated page, pre-rendered, keyed by its place
    /// in the sequence (`pages` holds the design's index for each place) then
    /// frame within the page. Static pages have no entry.
    ///
    /// Rendered with a pause every so often, so the sheet stays live while a
    /// page full of motion is drawn frame by frame.
    @MainActor
    private static func animatedFrames(design: Design, pages: [Int], size: CGSize, settings: Settings,
                                       timings: [Timing],
                                       pacer: inout DesignExporter.Pacer,
                                       progress: ((Double) -> Void)? = nil) async throws -> ((Int, Double, Double) -> CGImage?)? {
        let animatedPlaces = timings.indices.filter {
            $0 < pages.count && isAnimated(design.pages[pages[$0]], in: design)
        }
        guard !animatedPlaces.isEmpty else { return nil }
        let count = max(1, animatedFrameCount(design: design, pages: pages, timings: timings))
        var done = 0
        var cache: [Int: [CGImage]] = [:]
        for p in animatedPlaces {
            let t = timings[p]
            let hold = Double(t.frames) / Double(max(settings.fps, 1))
            var frames: [CGImage] = []
            for f in 0..<t.frames {
                try await pacer.breathe()
                if let frame = animatedFrame(design: design, page: pages[p], time: Double(f) / Double(max(settings.fps, 1)),
                                             hold: hold, size: size) {
                    frames.append(frame)
                }
                done += 1
                progress?(Double(done) / Double(count))
            }
            cache[p] = frames
        }
        return { page, seconds, _ in
            guard let frames = cache[page], !frames.isEmpty else { return nil }
            let f = min(max(Int((seconds * Double(settings.fps)).rounded()), 0), frames.count - 1)
            return frames[f]
        }
    }

    private static func fill(_ buffer: CVPixelBuffer, frame index: Int, pages: [CGImage],
                             size: CGSize, settings: Settings, timings: [Timing],
                             animated: ((Int, Double, Double) -> CGImage?)?) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        draw(frame: index, pages: pages, size: size, settings: settings, timings: timings,
             animated: animated, into: context)
    }

    // MARK: gif

    /// A GIF at the video's frame rate would be tens of megabytes, so it gets
    /// its own: fewer frames a second and a smaller frame. Drawn on the main
    /// actor with a pause every so often, so the progress bar moves and a
    /// Cancel stops it between frames, leaving no file behind.
    @MainActor
    static func exportGIF(design: Design, settings: Settings = Settings(),
                          range: DesignExporter.PageRange = .all, current: Int = 0, to url: URL,
                          progress: ((Double) -> Void)? = nil) async throws {
        // The clips' readers let go once the frames are drawn, or not.
        defer { ClipReaders.closeAll() }
        // Sized to a budget and paced at a rate the format can state
        // exactly; see gifPlan.
        let plan = gifPlan(design: design, settings: settings, range: range, current: current)
        var gifSettings = settings
        gifSettings.fps = plan.fps
        gifSettings.maxEdge = min(settings.maxEdge, plan.maxEdge)

        let size = videoSize(for: design, maxEdge: gifSettings.maxEdge)
        var pacer = DesignExporter.Pacer()
        // The pages shown, as the video plays them, or those chosen.
        let shown = playedPages(design: design, range: range, current: current)
        let pages = try await pageImages(design: design, pages: shown, size: size, pacer: &pacer)
        guard !pages.isEmpty else { throw MovieError.nothingToRender }

        let timings = timeline(design: design, pages: shown, settings: gifSettings)
        let total = timings.last?.end ?? 1
        // The frames rendered ahead count in the progress, as the MP4's do.
        let ahead = Double(animatedFrameCount(design: design, pages: shown, timings: timings))
        let share = ahead / (ahead + Double(total))
        let frames = try await animatedFrames(design: design, pages: shown, size: size, settings: gifSettings,
                                              timings: timings, pacer: &pacer,
                                              progress: { progress?(share * $0) })
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, total, nil) else {
            throw MovieError.writerFailed("no GIF destination")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: plan.delay,
            ],
        ] as CFDictionary

        for index in 0..<total {
            // Between frames, not mid-frame: a frame takes milliseconds and a
            // half-drawn one is never written.
            do { try await pacer.breathe() } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
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
                draw(frame: index, pages: pages, size: size, settings: gifSettings,
                     timings: timings, animated: frames, into: context)
                guard let frame = context.makeImage() else {
                    throw MovieError.writerFailed("a frame would not render")
                }
                CGImageDestinationAddImage(destination, frame, frameProperties)
            }
            progress?(share + (1 - share) * Double(index + 1) / Double(total))
        }
        // A Cancel tapped while the last frame drew is seen before the file
        // is finished and handed on.
        do { try await pacer.finish() } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        guard CGImageDestinationFinalize(destination) else {
            throw MovieError.writerFailed("the GIF would not finalise")
        }
    }
}
