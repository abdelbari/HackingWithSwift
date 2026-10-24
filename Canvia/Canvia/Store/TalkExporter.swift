// A recorded talk as an MP4: the design's pages held as long as the talk
// held them (RecordingPlan.film), cut from one to the next, the voice over
// the design's music ducked to RecordingPlan.duck by the mix every video
// has (AudioMix), and the camera in its bubble at the corner chosen —
// composited frame by frame by a small video compositor, round or rounded.
// The Android twin's MovieExporter does the same with the same plan.

import AVFoundation
import CoreImage
import Foundation

extension MovieExporter {

    /// The frame rate a talk's film is made at (RecordingPlan.fps).
    static let talkFps = RecordingPlan.fps

    /// The talk `recording` of `design` as an MP4 at `url`. Without its
    /// camera on this phone, the pages and the voice alone.
    @MainActor
    @discardableResult
    static func exportTalk(design: Design, recording: Recording, to url: URL,
                           progress: (@Sendable (Double) -> Void)? = nil) async throws -> Outcome {
        let film = RecordingPlan.film(design, recording, fps: talkFps)
        var settings = Settings(film.motion)
        settings.fps = talkFps
        settings.zoom = 0
        settings.crossfade = 0
        guard let camera = recording.cameraId.flatMap(VideoStore.url(for:)) else {
            return try await exportMP4(design: film, settings: settings, to: url, progress: progress)
        }
        let base = url.deletingPathExtension().appendingPathExtension("film.mp4")
        defer { try? FileManager.default.removeItem(at: base) }
        let picture: @Sendable (Double) -> Void = { done in progress?(done * 0.8) }
        let outcome = try await exportMP4(design: film, settings: settings, to: base, progress: picture)
        try Task.checkCancellation()
        try await composite(film: base, camera: camera, bubble: recording.bubble, to: url)
        progress?(1)
        return outcome
    }

    /// `film` with the camera clip over it in its bubble, sound and all,
    /// written to `url`.
    static func composite(film: URL, camera: URL, bubble: RecordingBubble, to url: URL) async throws {
        let filmAsset = AVURLAsset(url: film)
        let cameraAsset = AVURLAsset(url: camera)
        let composition = AVMutableComposition()
        let pictures = try await filmAsset.loadTracks(withMediaType: .video)
        guard let picture = pictures.first,
              let pictureTrack = composition.addMutableTrack(withMediaType: .video,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MovieError.writerFailed("the film has no picture")
        }
        let duration = try await filmAsset.load(.duration)
        let whole = CMTimeRange(start: .zero, duration: duration)
        try pictureTrack.insertTimeRange(whole, of: picture, at: .zero)
        let sounds = try await filmAsset.loadTracks(withMediaType: .audio)
        for sound in sounds {
            let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try track?.insertTimeRange(whole, of: sound, at: .zero)
        }
        var cameraID = kCMPersistentTrackID_Invalid
        var cameraTurn = CGAffineTransform.identity
        let faces = try await cameraAsset.loadTracks(withMediaType: .video)
        if let face = faces.first,
           let faceTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let length = try await cameraAsset.load(.duration)
            try faceTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, duration)), of: face, at: .zero)
            cameraID = faceTrack.trackID
            // A clip from the Android twin keeps the sensor's pixels and
            // says how to turn them in the track; this phone's are upright.
            cameraTurn = try await face.load(.preferredTransform)
        }
        let size = try await picture.load(.naturalSize)
        let rect = RecordingPlan.bubbleRect(bubble, width: Double(size.width), height: Double(size.height))
        let radius = CGFloat(RecordingPlan.bubbleRadius(bubble, side: Double(rect.width)))
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = TalkBubbleCompositor.self
        video.renderSize = size
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(talkFps))
        video.instructions = [TalkBubbleInstruction(timeRange: whole, film: pictureTrack.trackID, camera: cameraID,
                                                    cameraTurn: cameraTurn, rect: rect, radius: radius)]
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw MovieError.writerFailed("the export could not start")
        }
        try? FileManager.default.removeItem(at: url)
        export.outputURL = url
        export.outputFileType = .mp4
        export.videoComposition = video
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { done.resume() }
        }
        guard export.status == .completed else {
            throw MovieError.writerFailed(export.error?.localizedDescription ?? "the export stopped")
        }
    }
}

/// One instruction for the whole talk: the film's track, the camera's, and
/// where the bubble goes in the picture, top-left origin.
final class TalkBubbleInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let film: CMPersistentTrackID
    let camera: CMPersistentTrackID
    /// The camera track's preferred transform: how its frames are turned
    /// upright.
    let cameraTurn: CGAffineTransform
    let rect: CGRect
    let radius: CGFloat

    init(timeRange: CMTimeRange, film: CMPersistentTrackID, camera: CMPersistentTrackID,
         cameraTurn: CGAffineTransform, rect: CGRect, radius: CGFloat) {
        self.timeRange = timeRange
        self.film = film
        self.camera = camera
        self.cameraTurn = cameraTurn
        self.rect = rect
        self.radius = radius
        let tracks = camera == kCMPersistentTrackID_Invalid ? [film] : [film, camera]
        requiredSourceTrackIDs = tracks.map { NSNumber(value: $0) }
        super.init()
    }
}

/// Lays the camera's frame, filled into the bubble and cut to its shape,
/// over the film's.
final class TalkBubbleCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    let sourcePixelBufferAttributes: [String: Any]? = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    let requiredPixelBufferAttributesForRenderContext: [String: Any] =
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    private let context = CIContext()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? TalkBubbleInstruction,
              let base = request.sourceFrame(byTrackID: instruction.film),
              let out = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "Canvia.talk", code: 1))
            return
        }
        var image = CIImage(cvPixelBuffer: base)
        if instruction.camera != kCMPersistentTrackID_Invalid,
           let face = request.sourceFrame(byTrackID: instruction.camera) {
            let upright = CIImage(cvPixelBuffer: face).oriented(Self.orientation(of: instruction.cameraTurn))
            image = Self.bubbled(upright, over: image, rect: instruction.rect, radius: instruction.radius)
        }
        context.render(image, to: out)
        request.finish(withComposedVideoFrame: out)
    }

    /// The quarter turn a track's preferred transform makes, as the
    /// orientation that turns its frames upright: 90° as an upright phone's
    /// camera is written (.right), 270° (.left), 180° (.down), else none.
    static func orientation(of turn: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (turn.a.rounded(), turn.b.rounded(), turn.c.rounded(), turn.d.rounded()) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }

    /// `camera` filling `rect` (top-left origin) of `base`, cut to a
    /// rounded square of `radius` — a circle at half its side.
    static func bubbled(_ camera: CIImage, over base: CIImage, rect: CGRect, radius: CGFloat) -> CIImage {
        let target = CGRect(x: rect.minX, y: base.extent.height - rect.maxY, width: rect.width, height: rect.height)
        let source = camera.extent
        guard source.width > 0, source.height > 0 else { return base }
        let scale = max(target.width / source.width, target.height / source.height)
        let scaled = camera.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let moved = scaled.transformed(by: CGAffineTransform(translationX: target.midX - scaled.extent.midX,
                                                             y: target.midY - scaled.extent.midY))
            .cropped(to: target)
        guard let shape = CIFilter(name: "CIRoundedRectangleGenerator"), let blend = CIFilter(name: "CIBlendWithMask") else {
            return moved.composited(over: base)
        }
        shape.setValue(CIVector(cgRect: target), forKey: "inputExtent")
        shape.setValue(radius, forKey: "inputRadius")
        shape.setValue(CIColor.white, forKey: "inputColor")
        blend.setValue(moved, forKey: kCIInputImageKey)
        blend.setValue(base, forKey: kCIInputBackgroundImageKey)
        blend.setValue(shape.outputImage, forKey: kCIInputMaskImageKey)
        return blend.outputImage?.cropped(to: base.extent) ?? base
    }
}
