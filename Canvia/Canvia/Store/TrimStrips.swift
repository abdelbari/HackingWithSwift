// What the trimmer bar shows under its handles (see Trimming): a track's
// waveform — the loudness of 120 equal parts of its music, read once to
// linear PCM and kept as JSON in Caches/peaks/<id>.json — and a clip's eight
// frames, kept while the app runs. Both are read off the main thread, as
// the Android twin reads them, and the audition each handle plays when let
// go.

import AVFoundation
import Foundation
import UIKit

enum Peaks {

    /// The loudness of `n` equal parts of `samples`, each the root mean
    /// square of its samples. Part i holds the samples from i × count / n
    /// up to (i + 1) × count / n, in whole numbers, so with fewer samples
    /// than parts some parts hold none, and are 0. The Android twin's
    /// Peaks.buckets, row for row (TrimmingTests).
    static func buckets(_ samples: [Float], _ n: Int) -> [Float] {
        guard n > 0 else { return [] }
        let count = samples.count
        return (0..<n).map { i in
            let from = i * count / n
            let to = (i + 1) * count / n
            guard to > from else { return 0 }
            var sum = 0.0
            for s in samples[from..<to] { sum += Double(s) * Double(s) }
            return Float((sum / Double(to - from)).squareRoot())
        }
    }

    /// Each part's share of the loudest, 0…1, for drawing; all 0 for
    /// silence.
    static func normalised(_ peaks: [Float]) -> [Float] {
        guard let top = peaks.max(), top > 0 else { return peaks.map { _ in 0 } }
        return peaks.map { $0 / top }
    }

    static var directory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("peaks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ id: String) -> URL { directory.appendingPathComponent("\(id).json") }

    /// Music `id`'s peaks as kept; nil before they are read, or for a file
    /// that is not a list of numbers.
    static func cached(_ id: String) -> [Float]? {
        guard let data = try? Data(contentsOf: file(id)),
              let values = try? JSONDecoder().decode([Float].self, from: data) else { return nil }
        return values
    }

    /// Music `id`'s `Trimming.peakCount` peaks: kept ones, else read from its
    /// file and kept; nil for music not on this phone or that cannot be read.
    /// Never on the main thread.
    static func of(_ id: String) async -> [Float]? {
        if let kept = cached(id) { return kept }
        guard let url = AudioStore.url(for: id), let samples = await samples(of: url) else { return nil }
        let peaks = buckets(samples, Trimming.peakCount)
        if let data = try? JSONEncoder().encode(peaks) { try? data.write(to: file(id), options: .atomic) }
        return peaks
    }

    /// The rate the music is read at for its peaks: plenty to tell loud
    /// from quiet in a 120th of a song.
    static let sampleRate = 8000

    /// The sound of the file at `url`, one channel of 32-bit floats at
    /// `sampleRate`; nil when it has none, or cannot be read.
    static func samples(of url: URL) async -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            let count = bytes / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            var chunk = [Float](repeating: 0, count: count)
            let status = chunk.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                           destination: raw.baseAddress!)
            }
            if status == kCMBlockBufferNoErr { samples += chunk }
        }
        guard reader.status == .completed, !samples.isEmpty else { return nil }
        return samples
    }
}

enum Filmstrip {

    /// Each clip's frames, by video id, once read.
    @MainActor private static var kept: [String: [UIImage]] = [:]

    /// The longest side a frame is read at: a bar is 56 points tall.
    static let side: CGFloat = 160

    /// Clip `id`'s `Trimming.thumbnailCount` frames, `length` seconds of it
    /// spread across (Trimming.thumbnailTimes), read once with
    /// AVAssetImageGenerator — the nearest frames that decode quickly, as
    /// the Android twin takes the nearest key frames — and kept for the
    /// clip. Empty when none can be read.
    @MainActor
    static func frames(of id: String, length: Double) async -> [UIImage] {
        if let known = kept[id] { return known }
        guard let url = VideoStore.url(for: id) else { return [] }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: side, height: side)
        var frames: [UIImage] = []
        for t in Trimming.thumbnailTimes(length: length) {
            let at = CMTime(seconds: t, preferredTimescale: 600)
            // A frame that will not read is left out; the rest share the bar.
            do {
                let frame = try await generator.image(at: at)
                frames.append(UIImage(cgImage: frame.image))
            } catch {
                continue
            }
        }
        if !frames.isEmpty { kept[id] = frames }
        return frames
    }
}

/// What a trimmer plays when a handle is let go: a stretch of a clip's or a
/// track's file, once, then nothing — one at a time, a new one in place of
/// any still playing.
@MainActor
final class Audition {
    static let shared = Audition()

    private let player = AVPlayer()
    private var stopper: Task<Void, Never>?

    /// `range` seconds of the file at `url`, from its start to its end.
    func play(_ url: URL, _ range: ClosedRange<Double>) {
        stop()
        guard range.upperBound - range.lowerBound > 0.01 else { return }
        let item = AVPlayerItem(url: url)
        item.forwardPlaybackEndTime = PageSound.time(range.upperBound)
        player.replaceCurrentItem(with: item)
        player.seek(to: PageSound.time(range.lowerBound), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        let seconds = range.upperBound - range.lowerBound
        stopper = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 0.25))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopper?.cancel()
        stopper = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
