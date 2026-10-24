// Enhance voice, in a track's sheet and a clip's sound: a switch that
// cleans the background noise from a recording and levels the voice
// (VoiceEnhance), and, while it is on, Hold to compare — the part it plays
// heard as recorded while held, and enhanced when let go — as the Android
// twin's EnhanceVoiceRow. The enhanced sound is made off the main thread
// the first time, as the switch goes on.

import SwiftUI

struct EnhanceVoiceRow: View {
    /// Whether Enhance voice is on.
    let on: Bool
    /// The sound's AudioStore id: a song's, an effect's "sfx:<id>", or a
    /// clip's "video:<id>"; nil when it is not on this phone.
    let source: String?
    /// The part of the file it plays, for the comparison; nil while its
    /// length is not known.
    let range: ClosedRange<Double>?
    let volume: Double
    let set: (Bool) -> Void

    /// The enhanced sound being made.
    @State private var making = false
    /// The enhanced sound could not be made.
    @State private var failed = false
    @State private var holding = false

    var body: some View {
        Section {
            Toggle("Enhance voice", isOn: Binding(get: { on }, set: { turn($0) }))
            if on, source != nil, range != nil {
                compare
            }
        } footer: {
            Text(failed ? Self.failedNote : Self.note)
        }
        .task(id: on ? source : nil) {
            guard on, let source else { return }
            await prepare(source)
        }
    }

    static var note: String { tr("Cleans background noise and levels the voice.") }
    static var failedNote: String { tr("This sound can't be enhanced, so it plays as it is.") }

    /// Held, the original; let go, the enhanced sound.
    private var compare: some View {
        HStack {
            Label(holding ? tr("Original") : tr("Hold to compare"), systemImage: "waveform.badge.magnifyingglass")
            Spacer()
            if making { ProgressView() }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0, perform: {}, onPressingChanged: { pressing in
            holding = pressing
            Task { await play(enhanced: !pressing) }
        })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Play original")) { Task { await play(enhanced: false) } }
        .accessibilityAction(named: Text("Play enhanced")) { Task { await play(enhanced: true) } }
    }

    private func turn(_ value: Bool) {
        failed = false
        set(value)
    }

    @MainActor
    private func prepare(_ source: String) async {
        making = true
        let made = await AudioStore.enhancedURL(for: source)
        making = false
        failed = made == nil
    }

    /// The part it plays, once, as recorded or enhanced.
    @MainActor
    private func play(enhanced: Bool) async {
        guard let source, let range else { return }
        let found: URL?
        if enhanced {
            found = await AudioStore.enhancedURL(for: source)
        } else {
            found = AudioStore.url(for: source)
        }
        guard let url = found else { return }
        // Its first ten seconds at most: enough to hear the difference.
        Audition.shared.play(url, range.lowerBound...min(range.upperBound, range.lowerBound + 10), volume: volume)
    }
}
