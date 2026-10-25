// Imported clips made light in the background (VideoImport's rules): a
// clip that needs it is converted by AVAssetExportSession at 1920×1080 at
// most, H.264 with AAC in an MP4 made for streaming, and swapped in under
// its own `video:<id>` when it is done (VideoStore.replace) — the element
// showed its poster all along, and its times are the same. One clip at a
// time, the rest waiting their turn; the export pill shows the one under
// way, with Keep original, which stops it and keeps the clip as it came.
// A failure keeps the original and says so in a line. The upload records
// {"optimised": true, "originalBytes"} (Uploads.markOptimised), and
// "toneMapped" for an HDR clip. An HDR clip is converted with the setting
// off too (VideoImport.converts), its colours brought to BT.709 on the way
// — the pill says "Converting HDR video…" — and one kept original is tone
// mapped as it is read (ClipReader.sdrSettings).

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ClipOptimiser {

    static let shared = ClipOptimiser()

    /// Settings ▸ Optimise imported videos, on until turned off.
    nonisolated static let key = "canvia.optimiseVideos"

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// The clip being converted, and how far along, 0…1.
    struct Running: Equatable {
        var id: String
        var progress: Double
        /// An HDR clip, brought to SDR as it is converted.
        var hdr = false
    }

    private(set) var running: Running?

    @ObservationIgnored private var waiting: [String] = []
    @ObservationIgnored private var session: AVAssetExportSession?
    @ObservationIgnored private var keptOriginal = Set<String>()

    // MARK: what a clip is

    /// What clip `url` is (VideoImport.Probe): its bytes, its picture's size
    /// as it is shown, and its codecs; nil when it does not read.
    nonisolated static func probe(_ url: URL) async -> VideoImport.Probe? {
        let asset = AVURLAsset(url: url)
        guard let video = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await video.load(.naturalSize),
              let turn = try? await video.load(.preferredTransform) else { return nil }
        let shown = natural.applying(turn)
        let videoCodec = await codec(of: video)
        let audio = try? await asset.loadTracks(withMediaType: .audio).first
        var audioCodec: String?
        if let audio { audioCodec = await codec(of: audio) }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        var probe = VideoImport.Probe(bytes: Int64(bytes), width: Int(abs(shown.width).rounded()),
                                      height: Int(abs(shown.height).rounded()),
                                      videoCodec: videoCodec, audioCodec: audioCodec, container: url.pathExtension)
        if let formats = try? await video.load(.formatDescriptions), let first = formats.first {
            readColour(of: first, into: &probe)
        }
        return probe
    }

    /// A picture's transfer, bit depth and primaries, as VideoImport names
    /// them, from its format's extensions.
    nonisolated private static func readColour(of format: CMFormatDescription, into probe: inout VideoImport.Probe) {
        func string(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(format, extensionKey: key) as? String
        }
        let transfer = string(kCMFormatDescriptionExtension_TransferFunction)
        if transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String {
            probe.transfer = HdrToneMap.hlg
        } else if transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String {
            probe.transfer = HdrToneMap.pq
        }
        if string(kCMFormatDescriptionExtension_ColorPrimaries) == kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String {
            probe.primaries = VideoImport.bt2020
        }
        if let bits = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent)
            as? NSNumber {
            probe.bitDepth = bits.intValue
        }
    }

    /// A track's codec as VideoImport names it, from its first format.
    nonisolated private static func codec(of track: AVAssetTrack) async -> String? {
        guard let formats = try? await track.load(.formatDescriptions), let first = formats.first else { return nil }
        let code = CMFormatDescriptionGetMediaSubType(first)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
        return VideoImport.codec(fourCC: String(decoding: bytes, as: UTF8.self))
    }

    // MARK: converting

    /// Clip `id`, just brought in, converted when it needs it and the
    /// setting is on, or when it is HDR (VideoImport.converts); nothing
    /// otherwise. Its turn waits for the one before.
    func imported(_ id: String) {
        guard running?.id != id, !waiting.contains(id) else { return }
        waiting.append(id)
        if running == nil { next() }
    }

    /// Keep original: the clip under way stops and stays as it came.
    func keepOriginal() {
        guard let id = running?.id else { return }
        keptOriginal.insert(id)
        session?.cancelExport()
    }

    private func next() {
        guard running == nil, !waiting.isEmpty else { return }
        let id = waiting.removeFirst()
        running = Running(id: id, progress: 0)
        Task { await convert(id) }
    }

    private func convert(_ id: String) async {
        defer {
            // An early return leaves no Keep original behind for a later turn.
            keptOriginal.remove(id)
            running = nil
            session = nil
            next()
        }
        guard let source = VideoStore.url(for: id), let clip = await Self.probe(source),
              VideoImport.converts(clip, settingOn: Self.isOn) else { return }
        running?.hdr = clip.hdr
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            failed(hdr: clip.hdr)
            return
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(id)-light.mp4")
        try? FileManager.default.removeItem(at: out)
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        // Faster than 30 frames a second, held to 30 (VideoImport.targetFps).
        let track = try? await asset.loadTracks(withMediaType: .video).first
        let fps = Double((try? await track?.load(.nominalFrameRate)) ?? 0)
        if fps > Double(VideoImport.maxFps) || clip.hdr {
            let composition = AVMutableVideoComposition(propertiesOf: asset)
            if fps > Double(VideoImport.maxFps) {
                composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(VideoImport.targetFps(fps)))
            }
            // An HDR clip's colours brought to SDR's, BT.709 throughout.
            if clip.hdr {
                composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
                composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
                composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
            }
            session.videoComposition = composition
        }
        self.session = session
        // Keep original tapped while the clip was still being read: there
        // was no session to cancel then, so stop before it starts.
        if keptOriginal.contains(id) {
            try? FileManager.default.removeItem(at: out)
            return
        }
        let ticking = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.running?.id == id else { return }
                self.running?.progress = Double(session.progress)
            }
        }
        await session.export()
        ticking.cancel()
        if keptOriginal.remove(id) != nil {
            try? FileManager.default.removeItem(at: out)
            return
        }
        guard session.status == .completed, VideoStore.replace(id, with: out) else {
            try? FileManager.default.removeItem(at: out)
            failed(hdr: clip.hdr)
            return
        }
        Uploads.markOptimised(id, originalBytes: clip.bytes, toneMapped: clip.toneMapped)
    }

    /// The original kept, said in a line in the pill — for an HDR clip,
    /// that it may look washed out.
    private func failed(hdr: Bool = false) {
        ExportQueue.shared.note = hdr ? VideoImport.hdrFailed
            : tr("The video couldn't be optimised, so the original is kept.")
    }
}

extension VideoImport {
    /// Clip `id`, just brought in, handed to ClipOptimiser from anywhere a
    /// clip comes in — a picker's worker, the inbox — on the main actor,
    /// soon.
    static func optimiseSoon(_ id: String) {
        Task { @MainActor in ClipOptimiser.shared.imported(id) }
    }
}
