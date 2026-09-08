// A soundtrack under the video: the chosen audio looped or trimmed to the
// video's length, at a volume, fading out over the last second so the file
// does not end mid-note. The plan is pure; the mux runs it through
// AVFoundation on the finished MP4.

import AVFoundation
import Foundation

enum Soundtrack {

    struct Segment: Equatable {
        /// Where in the audio file the piece starts.
        var sourceStart: Double
        /// Where in the video it is placed.
        var at: Double
        var duration: Double
    }

    struct Plan: Equatable {
        var segments: [Segment]
        /// The seconds over which the volume ramps to zero, if any.
        var fadeOut: ClosedRange<Double>?
    }

    static let fadeSeconds = 1.0

    /// Loops audio shorter than the video and trims audio longer than it;
    /// the fade covers the last second when the video is long enough to
    /// have one.
    static func plan(audioDuration: Double, videoDuration: Double, fade: Double = fadeSeconds) -> Plan {
        guard audioDuration > 0.01, videoDuration > 0.01 else { return Plan(segments: [], fadeOut: nil) }
        var segments: [Segment] = []
        var at = 0.0
        while at < videoDuration - 0.001 {
            let duration = min(audioDuration, videoDuration - at)
            segments.append(Segment(sourceStart: 0, at: at, duration: duration))
            at += duration
        }
        let fadeOut: ClosedRange<Double>? = videoDuration > fade * 2 ? (videoDuration - fade)...videoDuration : nil
        return Plan(segments: segments, fadeOut: fadeOut)
    }

    enum SoundtrackError: LocalizedError {
        case noAudio, noVideo, exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .noAudio: return "the soundtrack file has no audio"
            case .noVideo: return "the video has no picture track"
            case .exportFailed(let why): return "the soundtrack could not be added (\(why))"
            }
        }
    }

    /// Writes `video` with `audio` under it to `output`.
    static func mux(video: URL, audio: URL, volume: Double, to output: URL) async throws {
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else { throw SoundtrackError.noVideo }
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else { throw SoundtrackError.noAudio }
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw SoundtrackError.exportFailed("no composition tracks")
        }
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        compVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        let plan = plan(audioDuration: audioDuration.seconds, videoDuration: videoDuration.seconds)
        let scale: CMTimeScale = 600
        for s in plan.segments {
            try compAudio.insertTimeRange(
                CMTimeRange(start: CMTime(seconds: s.sourceStart, preferredTimescale: scale),
                            duration: CMTime(seconds: s.duration, preferredTimescale: scale)),
                of: audioTrack, at: CMTime(seconds: s.at, preferredTimescale: scale))
        }

        let mix = AVMutableAudioMix()
        let params = AVMutableAudioMixInputParameters(track: compAudio)
        let level = Float(min(max(volume, 0), 1))
        params.setVolume(level, at: .zero)
        if let fade = plan.fadeOut {
            params.setVolumeRamp(fromStartVolume: level, toEndVolume: 0,
                                 timeRange: CMTimeRange(start: CMTime(seconds: fade.lowerBound, preferredTimescale: scale),
                                                        end: CMTime(seconds: fade.upperBound, preferredTimescale: scale)))
        }
        mix.inputParameters = [params]

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw SoundtrackError.exportFailed("no export session")
        }
        try? FileManager.default.removeItem(at: output)
        session.outputURL = output
        session.outputFileType = .mp4
        session.audioMix = mix
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else {
            throw SoundtrackError.exportFailed(session.error?.localizedDescription ?? "the export stopped early")
        }
    }
}
