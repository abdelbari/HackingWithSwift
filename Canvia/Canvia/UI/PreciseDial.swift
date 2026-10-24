// A photo dial you can set exactly (DialPrecision): its readout a button
// that opens a number to type, held to the dial's range, and a Reset in its
// long-press menu; a double tap on the track resets it too. Within 2 of
// its rest it rests there, with a light tick as it arrives. VoiceOver
// moves it 5 at a time and offers "Reset <name>". A drag is one step, and
// so is a typed number or a reset.

import SwiftUI
import UIKit

struct PreciseDial: View {
    let label: String
    /// What VoiceOver calls it, when not its label: "Red Hue".
    var spoken: String?
    /// Its value in steps (-100…100 or 0…100).
    let value: Double
    let range: ClosedRange<Double>
    /// Where it rests: 0, or 100 for a strength.
    var rest: Double = 0
    /// A value while the finger moves, left open as one step.
    let live: (Double) -> Void
    /// The drag let go: the step closed.
    let done: () -> Void
    /// A value as one step: typed, reset or stepped by VoiceOver.
    let set: (Double) -> Void
    @State private var typing = false
    @State private var typed = ""

    private var name: String { spoken ?? label }
    private var readout: String { DialPrecision.readout(value, in: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.subheadline)
                    .accessibilityHidden(true)
                Spacer()
                readoutButton
            }
            slider
        }
        .alert(label, isPresented: $typing) {
            TextField(readout, text: $typed)
                .keyboardType(.numbersAndPunctuation)
            Button("Done") {
                if let v = DialPrecision.typed(typed, in: range), v != value { set(v) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "\(Int(range.lowerBound)) – \(Int(range.upperBound))")
        }
    }

    /// The number, a button that opens it for typing; held, Reset.
    private var readoutButton: some View {
        Button {
            typed = "\(Int(value.rounded()))"
            typing = true
        } label: {
            Text(readout)
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .contextMenu {
            Button("Reset") { reset() }
                .disabled(value == rest)
        }
        .accessibilityLabel(tr("Type a value for %@", name))
        .accessibilityValue(readout)
    }

    private var slider: some View {
        Slider(value: Binding(
            get: { value },
            set: { v in
                let landed = DialPrecision.snapped(v, rest: rest, in: range)
                guard landed != value else { return }
                if DialPrecision.reachedRest(from: value, to: landed, rest: rest) {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                live(landed)
            }
        ), in: range, onEditingChanged: { editing in
            if !editing { done() }
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        .accessibilityLabel(name)
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(DialPrecision.stepped(value, up: true, in: range))
            case .decrement: set(DialPrecision.stepped(value, up: false, in: range))
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text(tr("Reset %@", name))) { reset() }
    }

    private func reset() {
        guard value != rest else { return }
        set(rest)
    }
}
