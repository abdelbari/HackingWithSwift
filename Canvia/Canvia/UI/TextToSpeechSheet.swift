// Text to speech: the words — the selected text box's, else the page's
// notes, else what the page says (Narration.prefill) — a voice of the app's
// language, speed and pitch from half to twice, Preview, and Generate, which
// reads them into a voice track from this page's start (SpeechFile). Given
// `editing`, a spoken track, its words and settings come back and Generate
// makes its file again in place (Edit speech). With no voice for the
// language, Install voices opens Settings, where Accessibility ▸ Spoken
// Content ▸ Voices adds one. As the Android twin's sheet.

import SwiftUI
import UIKit

struct TextToSpeechSheet: View {
    @Bindable var store: DesignStore
    /// The spoken track being read again, by id; nil for a new one.
    var editing: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var text = ""
    @State private var voice = ""
    @State private var rate = 1.0
    @State private var pitch = 1.0
    @State private var voices: [Narration.Voice] = []
    @State private var making = false
    @State private var failure: String?
    @State private var started = false

    private var track: AudioTrack? {
        editing.flatMap { id in store.design.audioTracks.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Words to speak") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Words to speak")
                }
                voiceSection
                settingsSection
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle(editing == nil ? Text("Text to speech") : Text("Edit speech"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .disabled(making)
            .overlay { if making { ProgressView() } }
        }
        .presentationDetents(sheetDetents)
        .interactiveDismissDisabled(making)
        .onAppear(perform: start)
        .onDisappear { SpeechFile.shared.stopPreview() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Generate") { generate() }
                .disabled(!canSpeak)
        }
    }

    private var canSpeak: Bool {
        !voices.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !making
    }

    @ViewBuilder
    private var voiceSection: some View {
        Section("Voice") {
            if voices.isEmpty {
                Text("No voice for this language is installed on this phone.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Install voices") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else {
                Picker("Voice", selection: $voice) {
                    ForEach(voices) { v in
                        Text(Self.label(v)).tag(v.id)
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        Section {
            dial(tr("Speed"), value: $rate)
            dial(tr("Pitch"), value: $pitch)
            Button {
                preview()
            } label: {
                Label("Preview", systemImage: "play.circle")
            }
            .disabled(!canSpeak)
        }
    }

    /// Half to twice the voice's own, in twentieths.
    private func dial(_ label: String, value: Binding<Double>) -> some View {
        let readout = String(format: "%.2f×", Narration.clamped(value.wrappedValue))
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: value, in: Narration.minRate...Narration.maxRate, step: 0.05)
                .accessibilityLabel(label)
                .accessibilityValue(readout)
        }
    }

    /// A voice by its name and its language's.
    static func label(_ voice: Narration.Voice) -> String {
        let language = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        return voice.name + " · " + language
    }

    private func spec() -> Narration.Spec {
        Narration.Spec(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                       voice: voice.isEmpty ? voices.first?.id ?? "" : voice,
                       rate: Narration.clamped(rate), pitch: Narration.clamped(pitch))
    }

    /// The words and settings the sheet opens with: a spoken track's own,
    /// or the first words there are, and the first voice offered.
    private func start() {
        guard !started else { return }
        started = true
        voices = SpeechFile.voicesForApp()
        if let was = track?.tts {
            text = was.text
            voice = was.voice
            rate = was.rate
            pitch = was.pitch
        } else {
            text = Narration.prefill(design: store.design, page: store.page, selected: store.singleSelection)
        }
        if !voices.contains(where: { $0.id == voice }) { voice = voices.first?.id ?? "" }
    }

    private func preview() {
        failure = nil
        do {
            try SpeechFile.shared.preview(spec())
        } catch {
            failure = tr("No voice for this language is installed on this phone.")
        }
    }

    /// The words read into a file and kept: a new track from this page's
    /// start, or the spoken track's file made again in place — one step.
    private func generate() {
        let spec = spec()
        SpeechFile.shared.stopPreview()
        failure = nil
        making = true
        Task { @MainActor in
            defer { making = false }
            do {
                let name = Narration.name(spec.text)
                let id = try await SpeechFile.shared.make(spec, name: name)
                Uploads.record(id, kind: .audio)
                if let editing {
                    store.respeakTrack(editing, audioId: id, spec: spec)
                } else {
                    store.addSpokenTrack(id, spec: spec)
                }
                store.buzz(.confirm)
                store.announce(tr("Added %@", name))
                dismiss()
            } catch SpeechFile.Failure.noVoice {
                failure = tr("No voice for this language is installed on this phone.")
            } catch SpeechFile.Failure.unread {
                failure = tr("The voice could not read that.")
            } catch {
                failure = tr("The speech could not be kept.")
            }
        }
    }
}
