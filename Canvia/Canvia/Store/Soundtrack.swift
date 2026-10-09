// A soundtrack under the video: the chosen audio looped or trimmed to the
// video's length, at a volume, fading out over the last second so the file
// does not end mid-note. The plan is pure; the mux runs it, and each clip's
// own sound (AudioMix), through AVFoundation on the finished MP4.

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

    /// The longest music a design file carries, in bytes; longer music
    /// stays on the phone it was chosen on.
    static let maxPackedBytes = 20 * 1024 * 1024

    /// The music types a design file carries — ones both phones play.
    static let packable: Set<String> = ["m4a", "mp3", "aac", "wav"]

    /// Whether music `bytes` long, of file type `ext`, travels in a design
    /// file — the Android twin's rule too, so either phone packs the same.
    static func packs(bytes: Int, ext: String) -> Bool {
        bytes > 0 && bytes <= maxPackedBytes && packable.contains(ext.lowercased())
    }

    /// One stretch's level on its track, from `start` to `end` in the
    /// video: its gain from where it begins, falling across whatever part of
    /// the fade it is under.
    private static func level(_ s: AudioMix.Segment, from start: CMTime, to end: CMTime,
                              in levels: AVMutableAudioMixInputParameters) {
        let from = start.seconds, to = end.seconds
        guard let fade = s.fadeOut, fade.upperBound > from, fade.lowerBound < to else {
            levels.setVolume(Float(s.gain), at: start)
            return
        }
        let rampStart = max(fade.lowerBound, from), rampEnd = min(fade.upperBound, to)
        // A stretch that begins inside the fade begins on the ramp.
        if rampStart > from { levels.setVolume(Float(s.gain), at: start) }
        levels.setVolumeRamp(fromStartVolume: Float(s.gainAt(rampStart)), toEndVolume: Float(s.gainAt(rampEnd)),
                             timeRange: CMTimeRange(start: CMTime(seconds: rampStart, preferredTimescale: start.timescale),
                                                    end: CMTime(seconds: rampEnd, preferredTimescale: start.timescale)))
    }

    enum SoundtrackError: LocalizedError {
        case noAudio, noVideo, exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .noAudio: return "none of the sound could be read"
            case .noVideo: return "the video has no picture track"
            case .exportFailed(let why): return "the soundtrack could not be added (\(why))"
            }
        }
    }

    /// Writes `video` with the sound `segments` lay under it (see
    /// AudioMix.plan) to `output`, each source read from its file in
    /// `sources`: one composition track a source — another beside it where
    /// two of its stretches sound at once, the same clip twice on a page —
    /// each with its own levels, the music fading out. A source that will
    /// not decode is left out and the rest kept; returns whether every one
    /// went in, and throws when none did, so the picture is kept as it is.
    static func mux(video: URL, segments: [AudioMix.Segment], sources: [String: URL],
                    to output: URL) async throws -> Bool {
        let videoAsset = AVURLAsset(url: video)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else { throw SoundtrackError.noVideo }
        let videoDuration = try await videoAsset.load(.duration)

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw SoundtrackError.exportFailed("no composition tracks")
        }
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        compVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        let scale: CMTimeScale = 600
        func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: scale) }
        /// A tick or two of rounding between one stretch and the next is
        /// the same moment, not a gap or an overlap.
        let slack = CMTime(value: 2, timescale: scale)
        var inputs: [AVMutableAudioMixInputParameters] = []
        // Held until the export is done, as the tracks taken from them are.
        var assets: [AVURLAsset] = []
        var lost = false
        // Each source once, in the order it is first heard.
        var order: [String] = []
        for s in segments where !order.contains(s.source) { order.append(s.source) }
        for source in order {
            guard let url = sources[source] else {
                lost = true
                continue
            }
            let asset = AVURLAsset(url: url)
            guard let audio = try? await asset.loadTracks(withMediaType: .audio).first,
                  let range = try? await audio.load(.timeRange) else {
                lost = true
                continue
            }
            assets.append(asset)
            var lanes: [(track: AVMutableCompositionTrack, end: CMTime, levels: AVMutableAudioMixInputParameters)] = []
            do {
                for s in segments where s.source == source {
                    let start = time(s.sourceStart)
                    // Never past the end of the file's own sound.
                    let duration = CMTimeMinimum(time(s.duration), CMTimeSubtract(range.end, start))
                    guard CMTimeCompare(duration, .zero) > 0 else { continue }
                    var at = time(s.at)
                    let lane: Int
                    if let free = lanes.firstIndex(where: { CMTimeCompare($0.end, CMTimeAdd(at, slack)) <= 0 }) {
                        lane = free
                    } else {
                        guard let track = composition.addMutableTrack(withMediaType: .audio,
                                                                      preferredTrackID: kCMPersistentTrackID_Invalid) else {
                            throw SoundtrackError.exportFailed("no composition tracks")
                        }
                        lanes.append((track: track, end: CMTime.zero, levels: AVMutableAudioMixInputParameters(track: track)))
                        lane = lanes.count - 1
                    }
                    let track = lanes[lane].track
                    // Silence up to it, or straight on from the one before.
                    if CMTimeCompare(at, lanes[lane].end) > 0 {
                        track.insertEmptyTimeRange(CMTimeRange(start: lanes[lane].end, end: at))
                    } else {
                        at = lanes[lane].end
                    }
                    try track.insertTimeRange(CMTimeRange(start: start, duration: duration), of: audio, at: at)
                    lanes[lane].end = CMTimeAdd(at, duration)
                    level(s, from: at, to: lanes[lane].end, in: lanes[lane].levels)
                }
            } catch {
                // What went in of a source that would not go in whole comes
                // back out: it is left out, not cut short.
                for lane in lanes { composition.removeTrack(lane.track) }
                lost = true
                continue
            }
            inputs += lanes.map { $0.levels }
        }
        guard !inputs.isEmpty else { throw SoundtrackError.noAudio }

        let mix = AVMutableAudioMix()
        mix.inputParameters = inputs

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw SoundtrackError.exportFailed("no export session")
        }
        try? FileManager.default.removeItem(at: output)
        session.outputURL = output
        session.outputFileType = .mp4
        session.audioMix = mix
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        withExtendedLifetime(assets) {}
        guard session.status == .completed else {
            throw SoundtrackError.exportFailed(session.error?.localizedDescription ?? "the export stopped early")
        }
        return !lost
    }
}
