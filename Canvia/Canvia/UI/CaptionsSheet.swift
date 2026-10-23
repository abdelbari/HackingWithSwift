// Captions on a clip or a voice-over: Generate, from the phone's own speech
// recognition where it has it (CaptionSpeech), Import .srt, and Edit — a
// list of the cues with their times and words — then the three styles once
// there are captions. The cues go on this page's caption box for `source`
// ("video:<id>" or "audio:<trackId>"), or a new one across the lower part of
// the page (DesignStore.setCaptions), one undo step each time. The Android
// twin's CaptionsRows, the same words.
//
// `audio` is the file the words are in and `range` the part of it heard —
// a clip's trim, a track's — and `toPage` takes cues timed in the file's
// own seconds to the page's: through a clip's trim and speed, or along the
// film to the page a track plays under.

import SwiftUI
import UniformTypeIdentifiers

struct CaptionsSheet: View {
    @Bindable var store: DesignStore
    let source: String
    let audio: () -> URL?
    let range: ClosedRange<Double>?
    let toPage: ([CaptionCue]) -> [CaptionCue]
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var busy = false
    @State private var importing = false
    @State private var editing = false

    private var captions: Captions? { store.captionsFor(source)?.captions }

    var body: some View {
        NavigationStack {
            Form {
                actionSection
                if captions != nil { styleSection }
            }
            .navigationTitle("Captions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(isPresented: $editing) {
                CaptionsEditorView(cues: captions?.cues ?? []) { cues in
                    editing = false
                    put(cues)
                }
            }
        }
        .presentationDetents(sheetDetents)
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.captionTypes) { result in
            bringIn(result)
        }
    }

    /// The file kinds an import offers: .srt and .vtt, and any text.
    static var captionTypes: [UTType] {
        [UTType(filenameExtension: "srt"), UTType(filenameExtension: "vtt"), .plainText, .text].compactMap { $0 }
    }

    private var actionSection: some View {
        Section {
            Button("Generate") { generate() }
                .disabled(busy)
            Button("Import .srt") { importing = true }
                .disabled(busy)
            Button("Edit") { editing = true }
                .disabled(busy)
        } footer: {
            if let status {
                Text(status)
            }
        }
    }

    /// The three styles, as the text-effect pipeline draws them: plain
    /// words, a bar behind them, the word being said lit.
    private var styleSection: some View {
        Section {
            Picker("Style", selection: Binding(
                get: { captions?.style ?? Captions.plain },
                set: { store.setCaptionStyle(source, $0) })) {
                Text("Plain").tag(Captions.plain)
                Text("Box").tag(Captions.box)
                Text("Highlight word").tag(Captions.highlightWord)
            }
            .pickerStyle(.segmented)
        }
    }

    private func put(_ cues: [CaptionCue]) {
        store.setCaptions(source, cues: cues)
        status = nil
    }

    /// An .srt or .vtt, timed to the file, as a player would read it.
    private func bringIn(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let text = (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let cues = Captions.parse(text)
        if cues.isEmpty {
            status = tr("No captions were found in that file.")
        } else {
            put(toPage(Captions.split(cues)))
        }
    }

    private func generate() {
        let language = store.design.language
        guard CaptionSpeech.isAvailable(language: language) else {
            status = CaptionSpeech.unavailableNote
            return
        }
        guard let file = audio(), let heard = range else {
            status = CaptionSpeech.unreadableNote
            return
        }
        busy = true
        status = CaptionSpeech.workingNote
        Task { @MainActor in
            do {
                let cues = try await CaptionSpeech.transcribe(file, from: heard.lowerBound, to: heard.upperBound,
                                                              language: language)
                busy = false
                if cues.isEmpty {
                    status = CaptionSpeech.nothingHeardNote
                } else {
                    // Timed from the part heard; back into the file's own seconds.
                    put(toPage(cues.map { CaptionCue(start: $0.start + heard.lowerBound, end: $0.end + heard.lowerBound,
                                                     text: $0.text) }))
                }
            } catch {
                busy = false
                status = error.localizedDescription
            }
        }
    }
}

/// The cues, one a row: a start and an end stepped a tenth of a second at
/// a time, the words, and Delete; Add a cue puts one after the last. Done
/// writes them, as one step; Back leaves them as they were.
struct CaptionsEditorView: View {
    @State var cues: [CaptionCue]
    let onDone: ([CaptionCue]) -> Void

    var body: some View {
        List {
            ForEach(Array(cues.enumerated()), id: \.offset) { index, cue in
                row(index, cue)
            }
            Button {
                let start = cues.last?.end ?? 0
                cues.append(CaptionCue(start: start, end: start + 2, text: ""))
            } label: {
                Label("Add a cue", systemImage: "plus")
            }
        }
        .navigationTitle("Edit captions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDone(Self.tidied(cues)) }
            }
        }
    }

    /// The cues as Done writes them: those with words, each ending after
    /// it starts, sorted by start.
    static func tidied(_ cues: [CaptionCue]) -> [CaptionCue] {
        cues.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }

    private func row(_ index: Int, _ cue: CaptionCue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                timeStepper(tr("Start"), value: cue.start) { v in
                    set(index, CaptionCue(start: v, end: max(cue.end, v + 0.1), text: cue.text))
                }
                Spacer()
                timeStepper(tr("End"), value: cue.end) { v in
                    set(index, CaptionCue(start: cue.start, end: max(v, cue.start + 0.1), text: cue.text))
                }
                Button(role: .destructive) {
                    cues.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete")
            }
            TextField("", text: Binding(
                get: { cue.text },
                set: { set(index, CaptionCue(start: cue.start, end: cue.end, text: $0)) }), axis: .vertical)
                .lineLimit(1...3)
        }
        .padding(.vertical, 2)
    }

    /// A time in seconds with − and + a tenth either side, read as a clock.
    private func timeStepper(_ label: String, value: Double, _ onChange: @escaping (Double) -> Void) -> some View {
        Stepper {
            Text("\(label) \(VideoStore.timeLabel(value))")
                .font(.caption.monospacedDigit())
        } onIncrement: {
            onChange(Self.tenth(value + 0.1))
        } onDecrement: {
            onChange(Self.tenth(max(0, value - 0.1)))
        }
        .accessibilityLabel(label)
        .accessibilityValue(VideoStore.timeLabel(value))
    }

    private static func tenth(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    private func set(_ index: Int, _ cue: CaptionCue) {
        guard cues.indices.contains(index) else { return }
        cues[index] = cue
    }
}
