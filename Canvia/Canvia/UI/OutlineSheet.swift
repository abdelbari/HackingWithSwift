// A sticker's or a graphic's outline or glow: the photo's edge, reused
// (PhotoEffects.takesDrawnEdge) — None, Outline or Glow as chips, then its
// size and colour. Everything selected takes it together, one step a tap and
// one a drag, as the Android twin's Outline panel.

import SwiftUI

struct OutlineSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    /// The edge shown: the first selected sticker's or graphic's.
    private var current: PhotoEdge? {
        store.selectedElements.first(where: PhotoEffects.takesDrawnEdge)?.edge
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    kinds
                    if let edge = current { dials(edge) }
                }
                .padding()
            }
            .navigationTitle("Outline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onDisappear { if store.hasPendingChanges { store.commit() } }
    }

    private var kinds: some View {
        HStack(spacing: 8) {
            chip(nil, tr("None"))
            chip("outline", tr("Outline"))
            chip("glow", tr("Glow"))
        }
    }

    /// None, or an outline or a glow; from one kind to the other keeps the
    /// size and colour, as a photo's edge chips do.
    private func chip(_ kind: String?, _ name: String) -> some View {
        let on = kind == nil ? current == nil : current.map { ($0.kind == "glow") == (kind == "glow") } ?? false
        return Button {
            store.updateSelected { el in
                guard PhotoEffects.takesDrawnEdge(el) else { return }
                guard let kind else { el.edge = nil; return }
                if var mine = el.edge {
                    mine.kind = kind
                    el.edge = mine
                } else {
                    el.edge = PhotoEdge(kind: kind, color: kind == "glow" ? PhotoEffects.glowColour : "#ffffff")
                }
            }
        } label: {
            Text(name)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(on ? Theme.accent.opacity(0.18) : Color(.systemGray6)))
                .overlay(Capsule().stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func dials(_ edge: PhotoEdge) -> some View {
        let glow = PhotoEffects.isGlow(edge)
        let size = glow ? tr("Glow size") : tr("Outline size")
        let colour = glow ? tr("Glow colour") : tr("Outline colour")
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(size).font(.subheadline)
                Spacer()
                Text("\(Int(edge.width.rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: Binding(
                get: { edge.width },
                set: { v in
                    store.updateSelectedTransient { el in
                        if PhotoEffects.takesDrawnEdge(el), el.edge != nil { el.edge?.width = v.rounded() }
                    }
                }
            ), in: 1...100, onEditingChanged: { editing in
                if !editing { store.commit() }
            })
            .accessibilityLabel(size)
            .accessibilityValue("\(Int(edge.width.rounded()))")
        }
        HStack {
            Text(colour).font(.subheadline)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(hex: edge.color) },
                set: { color in
                    let hex = UIColor(color).hexString
                    store.updateSelectedTransient { el in
                        if PhotoEffects.takesDrawnEdge(el), el.edge != nil { el.edge?.color = hex }
                    }
                }), supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel(colour)
        }
    }
}
