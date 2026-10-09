// A clip's trim, speed and loop.
//
// The part of the file a clip plays, how fast, and whether it goes round
// again — kept on the element, the file left as it is, so a trim can always
// be taken back out. Each change is one undo step: a slider's when it is let
// go, not one for every frame of the drag. The Android twin's PhotoPanel
// Clip section sets the same `clip` object.

import SwiftUI

struct ClipSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// The clip's length, read off the main thread when the sheet opens;
    /// nil until it is, 0 for one that cannot be read.
    @State private var length: Double?
    /// Where a trim slider is while it is dragged; written when let go.
    @State private var draftStart: Double?
    @State private var draftEnd: Double?

    private var element: Element? {
        guard let el = store.singleSelection, VideoStore.isVideo(el.src) else { return nil }
        return el
    }

    private var clipId: String? { element?.src.flatMap { VideoStore.split($0)?.id } }

    var body: some View {
        NavigationStack {
            Form {
                if let el = element {
                    let clip = el.clip ?? ClipPlayback()
                    trimSection(clip)
                    Section("Speed") {
                        Picker("Speed", selection: Binding(
                            get: { clip.speed },
                            set: { v in write { $0.speed = v } })) {
                            ForEach(ClipPlayback.speeds, id: \.self) { speed in
                                Text(Self.speedLabel(speed)).tag(speed)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    Section {
                        Toggle("Loop", isOn: Binding(
                            get: { clip.loop },
                            set: { on in write { $0.loop = on } }))
                        Button("Fit page to clip") { store.fitPageToClip() }
                            .disabled((length ?? 0) <= ClipPlayback.minLength)
                        Button { store.playPreview() } label: {
                            Label("Play", systemImage: "play.circle")
                        }
                    }
                }
            }
            .navigationTitle("Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .task(id: clipId) {
            guard let id = clipId else { return }
            length = await Task.detached(priority: .userInitiated) { VideoStore.duration(of: id) ?? 0 }.value
        }
    }

    /// Start and End, each its own slider over the whole file, kept
    /// `ClipPlayback.minLength` apart, with the trim read out above them.
    /// A clip whose length cannot be read, or is no longer than that, has
    /// none, as on the Android twin.
    @ViewBuilder
    private func trimSection(_ clip: ClipPlayback) -> some View {
        if let length, length > ClipPlayback.minLength {
            Section {
                let start = draftStart ?? min(max(0, clip.start), length)
                let end = draftEnd ?? min(clip.end ?? length, length)
                HStack {
                    Text("Trim")
                    Spacer()
                    Text(VideoStore.rangeLabel(start, end))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                trimSlider("Start", value: start, length: length,
                           set: { draftStart = max(0, min($0, end - ClipPlayback.minLength)) },
                           done: { commitTrim(clip, length: length) })
                trimSlider("End", value: end, length: length,
                           set: { draftEnd = min(length, max($0, start + ClipPlayback.minLength)) },
                           done: { commitTrim(clip, length: length) })
            }
        } else if length == nil {
            Section { ProgressView() }
        }
    }

    private func trimSlider(_ label: String, value: Double, length: Double,
                            set: @escaping (Double) -> Void, done: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
            Slider(value: Binding(get: { value }, set: set), in: 0...length,
                   onEditingChanged: { editing in if !editing { done() } })
            .accessibilityLabel(label)
            .accessibilityValue(VideoStore.timeLabel(value))
        }
    }

    /// The trim dragged to, written as one step: to a tenth of a second,
    /// and an end at the file's own end kept as none.
    private func commitTrim(_ clip: ClipPlayback, length: Double) {
        let start = draftStart
        let end = draftEnd
        draftStart = nil
        draftEnd = nil
        guard start != nil || end != nil else { return }
        write { next in
            if let start { next.start = Self.tenths(start) }
            if let end {
                let e = Self.tenths(end)
                next.end = e >= length - 0.05 ? nil : e
            }
        }
    }

    /// The selected clip's playback changed by `change`, as one undo step.
    private func write(_ change: (inout ClipPlayback) -> Void) {
        guard let el = element else { return }
        var clip = el.clip ?? ClipPlayback()
        change(&clip)
        store.setClip(clip)
    }

    private static func tenths(_ seconds: Double) -> Double { (seconds * 10).rounded() / 10 }

    /// "0.5×", "1×", "1.5×", "2×".
    static func speedLabel(_ speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))×" : String(format: "%.1f×", speed)
    }
}
