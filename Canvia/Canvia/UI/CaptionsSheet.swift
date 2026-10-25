// Captions on a clip or a voice-over: Generate, from the phone's own speech
// recognition where it has it (CaptionSpeech), Import .srt, and Edit — a
// list of the cues with their times and words — then, once there are
// captions, a row of the nine styles, each tile playing its sample words in
// its style, where the box sits (top, middle, bottom or inside the page's
// safe zone) and the colour the said words are lit in. The cues go on this page's caption box for `source`
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

    /// The nine styles as tiles, each drawn live; then the place and the
    /// highlight colour. Each a step of its own, the cues kept.
    private var styleSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Captions.styles, id: \.self) { style in
                        CaptionStyleTile(style: style, ink: captions?.highlightInk ?? Captions.highlightColour,
                                         chosen: (captions?.style ?? Captions.plain) == style) {
                            store.setCaptionStyle(source, style)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            placePicker
            highlightRow
        } header: {
            Text("Style")
        }
    }

    /// Top, Middle, Bottom or Safe — inside the page's safe zone.
    private var placePicker: some View {
        Picker("Position", selection: Binding(
            get: { captions?.place ?? "" },
            set: { store.setCaptionPlace(source, $0) })) {
            ForEach(Captions.places, id: \.self) { place in
                Text(CaptionStyleTile.placeName(place)).tag(place)
            }
        }
        .pickerStyle(.segmented)
    }

    /// The colour the said words are lit in: the default yellow, then the
    /// brand's colours.
    private var highlightRow: some View {
        let chosen = captions?.highlightInk ?? Captions.highlightColour
        return HStack(spacing: 10) {
            Text("Highlight")
            Spacer()
            ForEach(Self.highlightInks(BrandKit.load().colors), id: \.self) { ink in
                Button { store.setCaptionHighlight(source, ink) } label: {
                    Circle()
                        .fill(Color(hex: ink))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Theme.accent, lineWidth: ink == chosen.lowercased() ? 3 : 0))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(ElementNames.spokenColour(ink))
                .accessibilityAddTraits(ink == chosen.lowercased() ? [.isSelected] : [])
            }
        }
    }

    /// The highlight colours offered: the default, then up to five of the
    /// brand's, each once.
    static func highlightInks(_ brand: [String]) -> [String] {
        var out = [Captions.highlightColour]
        for hex in brand.map({ $0.lowercased() }) where !out.contains(hex) && out.count < 6 {
            out.append(hex)
        }
        return out
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

/// One caption style as a tile: sample words drawn in it on a dark card,
/// playing through on a loop, and its name; chosen, outlined.
struct CaptionStyleTile: View {
    let style: String
    let ink: String
    let chosen: Bool
    let choose: () -> Void

    /// The sample's cue and how long a turn of it lasts.
    private static let sample = CaptionCue(start: 0, end: 1.2, text: "Say it loud")
    private static let turn = 1.8

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 6) {
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                    TextElementView(element: frame(at: context.date))
                        .frame(width: 96, height: 44)
                }
                .frame(width: 104, height: 56)
                .background(Color(hex: "#1f2430"), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: chosen ? 3 : 0))
                Text(Self.name(style))
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(style))
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    /// The sample box drawn as `style` draws it at `date`, round its turn.
    private func frame(at date: Date) -> Element {
        var box = Element.text("", fontSize: 16, w: 96)
        box.h = 44
        box.fontWeight = 700
        box.align = "center"
        box.vAlign = "middle"
        box.color = "#ffffff"
        box = Captions.on(box, Captions(cues: [Self.sample], style: style, highlight: ink))
        if style == Captions.gradient {
            box.textFill = Captions.gradientFill([ink, "#5a31f4"])
        }
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.turn)
        return Captions.shown(box, at: min(t, Self.sample.end - 0.001))
    }

    /// A style's name in the sheet.
    static func name(_ style: String) -> String {
        switch style {
        case Captions.box: return tr("Box")
        case Captions.highlightWord: return tr("Highlight word")
        case Captions.outline: return tr("Outline")
        case Captions.pop: return tr("Pop")
        case Captions.karaoke: return tr("Karaoke")
        case Captions.typewriter: return tr("Typewriter")
        case Captions.bar: return tr("Bar")
        case Captions.gradient: return tr("Gradient")
        default: return tr("Plain")
        }
    }

    /// A place's name in the sheet.
    static func placeName(_ place: String) -> String {
        switch place {
        case Captions.top: return tr("Top")
        case Captions.middle: return tr("Middle")
        case Captions.safe: return tr("Safe")
        default: return tr("Bottom")
        }
    }
}
