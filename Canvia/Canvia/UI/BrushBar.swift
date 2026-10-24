// Brush mode's bar, in place of the insert button while a photo is brushed
// (BrushMode.swift): for the Erase and Restore brush, the two as chips with
// Clear a colour beside them, the brush's Size and Softness — or, clearing
// a colour, Tolerance and Everywhere; for a blur or pixelate brush, Size, Strength
// and Erase from effect. Then Show original, held to compare, Undo stroke,
// Cancel and Done — the whole session one Undo.

import SwiftUI

struct BrushBar: View {
    @Bindable var store: DesignStore
    let session: BrushSession

    var body: some View {
        VStack(spacing: 8) {
            modes
            sliders
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Erase or Restore; or, for a blur or pixelate, whether the brush takes
    /// the effect back off.
    @ViewBuilder
    private var modes: some View {
        if session.retouching {
            Toggle("Erase from effect", isOn: Binding(get: { session.reverse },
                                                      set: { store.brushing?.reverse = $0 }))
                .font(.subheadline)
        } else {
            HStack(spacing: 8) {
                chip(tr("Erase"), on: !session.reverse && !session.clearing) { pick(clearing: false, reverse: false) }
                chip(tr("Restore"), on: session.reverse && !session.clearing) { pick(clearing: false, reverse: true) }
                chip(tr("Clear a colour"), on: session.clearing) { pick(clearing: true, reverse: false) }
                Spacer(minLength: 0)
            }
        }
    }

    private func pick(clearing: Bool, reverse: Bool) {
        store.brushing?.clearing = clearing
        store.brushing?.reverse = reverse
    }

    @ViewBuilder
    private var sliders: some View {
        if session.clearing && !session.retouching {
            keySliders
        } else {
            brushSliders
        }
    }

    /// Clear a colour's Tolerance, 0 to 100, and Everywhere: each redoes the
    /// last tap, live.
    private var keySliders: some View {
        HStack(spacing: 14) {
            slider(tr("Tolerance"), value: session.tolerance * 100, in: 0...100,
                   readout: "\(Int((session.tolerance * 100).rounded()))") { store.setKeyTolerance($0 / 100) }
            Toggle("Everywhere", isOn: Binding(get: { session.everywhere }, set: { store.setKeyEverywhere($0) }))
                .font(.subheadline)
                .fixedSize()
        }
    }

    private var brushSliders: some View {
        HStack(spacing: 14) {
            slider(tr("Size"), value: session.size, in: BrushSession.sizeRange,
                   readout: Self.percent(session.size)) { store.brushing?.size = $0 }
            if session.retouching && session.kind != .adjust {
                slider(tr("Strength"), value: session.strength, in: 0...1,
                       readout: Self.percent(session.strength)) { store.setBrushStrength($0) }
            } else {
                slider(tr("Softness"), value: session.softness, in: 0...1,
                       readout: Self.percent(session.softness)) { store.brushing?.softness = ($0 * 100).rounded() / 100 }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            showOriginal
            Spacer(minLength: 0)
            Button {
                store.undoBrushStroke()
            } label: { Image(systemName: "arrow.uturn.backward").frame(width: 30, height: 30) }
                .disabled(session.painted == 0)
                .accessibilityLabel("Undo stroke")
            Button("Cancel") { store.cancelBrush() }
            Button("Done") { store.finishBrush() }
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
        }
    }

    /// Show original: while it is held the photo shows as it was before the
    /// brush's strokes — before a Cut out, too, for Erase and Restore — and
    /// VoiceOver says so.
    private var showOriginal: some View {
        let held = session.comparing
        return Label(held ? PhotoEdits.comparingNote : tr("Show original"), systemImage: "eye")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(held ? Theme.accent.opacity(0.18) : Color(.systemGray6)))
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 60, perform: {},
                                onPressingChanged: compare)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double-tap and hold to see the photo as it was")
    }

    private func compare(_ pressing: Bool) {
        guard store.brushing?.comparing != pressing else { return }
        store.brushing?.comparing = pressing
        if pressing { AccessibilityNotification.Announcement(PhotoEdits.comparingNote).post() }
    }

    private func chip(_ name: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            Text(name)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? Theme.accent.opacity(0.18) : Color(.systemGray6)))
                .overlay(Capsule().stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A slider of the brush's, its name and value under it.
    private func slider(_ label: String, value: Double, in range: ClosedRange<Double>, readout: String,
                        set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { value }, set: set), in: range)
                .accessibilityLabel(label)
                .accessibilityValue(readout)
            Text(verbatim: "\(label) \(readout)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// A share as whole per cent, at least 1 for any at all.
    static func percent(_ share: Double) -> String {
        let whole = Int((share * 100).rounded())
        return "\(share > 0 ? max(1, whole) : 0)%"
    }
}
