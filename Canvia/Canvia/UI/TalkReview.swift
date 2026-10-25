// A design's recorded talks, newest first: each with Play — the pages as
// the talk turned them, the voice and the camera in its bubble — Export MP4
// (with its burnt-in captions as an .srt beside it),
// Re-record, Delete and where its camera bubble sits. Opened after a talk is
// recorded, and from the editor's Present menu. The Android twin's
// RecordingsSheet. TalkSheets hangs the studio and this sheet on the editor
// and on Home.

import AVFoundation
import AVKit
import SwiftUI

struct TalkReviewSheet: View {
    let design: Design
    /// The design with a talk taken away or its bubble moved.
    var onChange: (Design) -> Void
    /// Re-record: the studio again, the talk replaced by what it makes.
    var onRerecord: (Recording) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var playing: Recording?
    @State private var exporting: String?
    @State private var shared: URL?
    /// A talk's burnt-in captions as an .srt, shared beside its video.
    @State private var sharedCaptions: URL?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                if Recordings.of(design).isEmpty {
                    Text("No recordings yet.").foregroundStyle(.secondary)
                }
                ForEach(Recordings.of(design)) { talk in
                    row(talk)
                }
                if let problem { Text(problem).foregroundStyle(.red) }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .fullScreenCover(item: $playing) { talk in
            TalkPlayer(design: design, recording: talk)
        }
        .sheet(item: Binding(get: { shared.map(ShareURL.init) }, set: { if $0 == nil { shared = nil } })) { item in
            ShareSheet(urls: [item.url] + (sharedCaptions.map { [$0] } ?? []))
        }
    }

    private func row(_ talk: Recording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Recordings.label(talk)).font(.headline)
            Text(subtitle(talk)).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Play") { playing = talk }
                    .buttonStyle(.borderedProminent)
                Button(exporting == talk.id ? tr("Rendering the video") : tr("Export MP4")) { export(talk) }
                    .buttonStyle(.bordered)
                    .disabled(exporting != nil)
            }
            HStack(spacing: 8) {
                Button("Re-record") {
                    onRerecord(talk)
                    dismiss()
                }
                if talk.camera != nil { cornerMenu(talk) }
                Spacer()
                Button("Delete", role: .destructive) { onChange(Recordings.without(design, talk.id)) }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    /// "2 hours ago", and "Voice only" for a talk without its camera.
    private func subtitle(_ talk: Recording) -> String {
        let when = RelativeTime.text(ms: talk.createdAt)
        return talk.camera == nil ? when + " · " + tr("Voice only") : when
    }

    private func cornerMenu(_ talk: Recording) -> some View {
        Menu(tr("Camera bubble: %@", RecordingBubble.name(talk.bubble.corner))) {
            ForEach(RecordingBubble.corners, id: \.self) { corner in
                Button(RecordingBubble.name(corner)) {
                    var bubble = talk.bubble
                    bubble.corner = corner
                    onChange(Recordings.withBubble(design, talk.id, bubble))
                }
            }
        }
    }

    /// A talk's burnt-in captions (Recording.captions) as an .srt beside its
    /// video, timed from the talk's start; nil for none.
    static func captionsFile(_ design: Design, _ talk: Recording) -> URL? {
        guard !talk.captions.isEmpty else { return nil }
        let url = DesignExporter.fileURL(for: design, ext: "srt")
        do {
            try Data(Captions.srt(talk.captions).utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// The talk as an MP4, to share.
    private func export(_ talk: Recording) {
        exporting = talk.id
        problem = nil
        let url = DesignExporter.fileURL(for: design, ext: "mp4")
        Task { @MainActor in
            do {
                try await MovieExporter.exportTalk(design: design, recording: talk, to: url)
                sharedCaptions = Self.captionsFile(design, talk)
                shared = url
            } catch {
                problem = ExportChoices.failedText(error.localizedDescription)
            }
            exporting = nil
        }
    }
}

/// A talk played back: the voice, the page the talk had up at each moment
/// (RecordingPlan.pageAt), and the camera in its bubble.
struct TalkPlayer: View {
    let design: Design
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @State private var voice: AVPlayer?
    @State private var face: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                stage(at: voice?.currentTime().seconds ?? 0)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3).foregroundStyle(.white).padding(16)
            }
            .accessibilityLabel("Close")
        }
        .onAppear { start() }
        .onDisappear {
            voice?.pause()
            face?.pause()
        }
    }

    private func stage(at time: Double) -> some View {
        GeometryReader { geo in
            let span = RecordingPlan.pageAt(recording, time.isFinite ? time : 0)
            let page = design.pages.first { $0.id == span?.pageId } ?? design.pages.first ?? Page()
            let size = design.size(for: page)
            let scale = min(geo.size.width / max(size.width, 1), geo.size.height / max(size.height, 1))
            PageRenderView(design: design, page: page)
                .environment(\.onScreen, true)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .overlay { bubble(in: CGSize(width: size.width * scale, height: size.height * scale)) }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .designDirection()
    }

    @ViewBuilder
    private func bubble(in size: CGSize) -> some View {
        if let face {
            let rect = RecordingPlan.bubbleRect(recording.bubble, width: size.width, height: size.height)
            let radius = CGFloat(RecordingPlan.bubbleRadius(recording.bubble, side: Double(rect.width)))
            VideoPlayer(player: face)
                .disabled(true)
                .frame(width: rect.width, height: rect.height)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .position(x: rect.midX, y: rect.midY)
                .accessibilityHidden(true)
        }
    }

    private func start() {
        guard let url = AudioStore.url(for: recording.audio) else { return }
        let player = AVPlayer(url: url)
        voice = player
        if let id = recording.cameraId, let file = VideoStore.url(for: id) {
            let camera = AVPlayer(url: file)
            camera.isMuted = true
            face = camera
            camera.play()
        }
        player.play()
    }
}

/// Present and record over the editor or Home: the studio, then the
/// talks' sheet. `apply` puts a changed design where it belongs — the
/// editor's store, or the design's file.
struct TalkSheets: ViewModifier {
    @Binding var recording: Design?
    @Binding var reviewing: Design?
    var apply: (Design) -> Void
    /// The talk a Re-record takes the place of.
    @State private var replacing: String?
    /// What comes up once the cover or the sheet has gone: the talks after
    /// a recording, the studio after Re-record.
    @State private var reviewNext: Design?
    @State private var recordNext: Design?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $recording, onDismiss: afterStudio) { design in
                TalkStudio(design: design) { talk in
                    var next = replacing.map { Recordings.without(design, $0) } ?? design
                    next = Recordings.added(next, talk)
                    apply(next)
                    reviewNext = next
                }
            }
            .sheet(item: $reviewing, onDismiss: afterReview) { design in
                TalkReviewSheet(design: design, onChange: { next in
                    apply(next)
                    reviewing = next
                }, onRerecord: { talk in
                    replacing = talk.id
                    recordNext = design
                })
            }
    }

    private func afterStudio() {
        reviewing = reviewNext
        reviewNext = nil
        replacing = nil
    }

    private func afterReview() {
        guard let next = recordNext else { return }
        recordNext = nil
        recording = next
    }
}
