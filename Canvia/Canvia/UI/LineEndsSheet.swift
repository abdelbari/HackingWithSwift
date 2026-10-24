// A line's ends: Start and End as rows of icon chips, each drawn from the
// head it puts on (LineEnds), and a Size slider for both heads. As the
// Android twin's line panel offers them. One step a tap, one a drag, and
// nothing recorded when a line already is what was picked.

import SwiftUI

struct LineEndsSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    private var line: Element? { store.selectedElements.first { $0.type == .line } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    row(tr("Start"), start: true)
                    row(tr("End"), start: false)
                    sizeSlider
                }
                .padding()
            }
            .navigationTitle("Line ends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onDisappear { if store.hasPendingChanges { store.commit() } }
    }

    private func row(_ title: String, start: Bool) -> some View {
        let current = LineEnds.kind(start ? line?.startCap : line?.endCap)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LineEnds.Kind.allCases) { kind in
                        chip(kind, start: start, active: kind == current)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }

    private func chip(_ kind: LineEnds.Kind, start: Bool, active: Bool) -> some View {
        Button {
            pick(kind, start: start)
        } label: {
            LineEndIcon(kind: kind, atStart: start)
                .frame(width: 56, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// One end of every unlocked line selected, as one step.
    private func pick(_ kind: LineEnds.Kind, start: Bool) {
        let key = kind.rawValue
        let lines = store.selectedElements.filter { $0.type == .line && !$0.locked }
        guard lines.contains(where: { LineEnds.kind(start ? $0.startCap : $0.endCap) != kind }) else { return }
        store.updateSelected { e in
            guard e.type == .line else { return }
            if start { e.startCap = key } else { e.endCap = key }
        }
        store.buzz(.tick)
    }

    private var sizeSlider: some View {
        let value = LineEnds.scale(line?.capScale)
        let readout = "\(Int((value * 100).rounded()))%"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Size").font(.headline)
                Spacer()
                Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: Binding(
                get: { value },
                set: { v in
                    // To the tenth, as both phones write it (LineEnds.written).
                    store.updateSelectedTransient { e in
                        if e.type == .line { e.capScale = LineEnds.written(v) }
                    }
                }
            ), in: LineEnds.scaleRange, onEditingChanged: { editing in
                if !editing { store.commit() }
            })
            .accessibilityLabel(tr("End size"))
            .accessibilityValue(readout)
        }
    }
}

/// A short line with one head, as the chip for that head: drawn with the
/// same shapes the canvas and the exports use.
struct LineEndIcon: View {
    let kind: LineEnds.Kind
    var atStart = false

    var body: some View {
        SwiftUI.Canvas { context, size in
            let t = 2.5
            let y = Double(size.height) / 2
            let tip = CGPoint(x: atStart ? 8 : Double(size.width) - 8, y: y)
            let tail = CGPoint(x: atStart ? Double(size.width) - 8 : 8, y: y)
            let angle = atStart ? Double.pi : 0
            // A head 10 long for a 2.5 weight at the usual size.
            let back = LineEnds.back(kind, thickness: t)
            var stroke = Path()
            stroke.move(to: tail)
            stroke.addLine(to: CGPoint(x: Double(tip.x) - cos(angle) * back, y: y))
            let ink = Color.primary
            context.stroke(stroke, with: .color(ink), style: StrokeStyle(lineWidth: t, lineCap: .round))
            if let head = LineEnds.head(kind, tip: tip, angle: angle, thickness: t) {
                LineElementView.drawHead(head, color: ink, in: context)
            }
        }
        .designDirection()
        .accessibilityHidden(true)
    }
}
