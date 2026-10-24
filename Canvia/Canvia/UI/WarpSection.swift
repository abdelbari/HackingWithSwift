// The Effects sheet's Shape row: Warp tiles that bend the letters in their
// box (TextWarp), None first, an Amount slider for a preset, and Edit shape,
// which puts the warp's handles — or a path's points — on the canvas to
// drag (ShapeHandles). As the Android twin's Effects ▸ Shape row.

import SwiftUI

struct WarpSection: View {
    @Bindable var store: DesignStore
    var onEditShape: () -> Void = {}

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    private var warp: TextWarpSpec? {
        store.singleSelection.flatMap { TextWarp.isWarped($0) ? $0.warp : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shape").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                tile(nil)
                ForEach(TextWarp.kinds, id: \.self) { kind in tile(kind) }
                if warp?.kind == TextWarp.custom { tile(TextWarp.custom) }
            }
            if let warp, warp.kind != TextWarp.custom { amountRow(warp) }
            Button {
                store.toggleShapeEditing()
                onEditShape()
            } label: {
                Label("Edit shape", systemImage: "skew")
            }
            .disabled(!store.canEditShape)
        }
    }

    private func tile(_ kind: String?) -> some View {
        let active = warp?.kind == kind
        let name = kind.map(TextWarp.name) ?? tr("None")
        return Button {
            if store.hasPendingChanges { store.commit() }
            // The custom tile is the shape as it is: nothing to pick.
            guard kind != TextWarp.custom else { return }
            store.warpSelected(kind)
        } label: {
            VStack(spacing: 6) {
                preview(kind)
                    .frame(width: 64, height: 44)
                Text(name).font(.caption2)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? Theme.accent : .clear, lineWidth: 2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("%@ warp", name))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func preview(_ kind: String?) -> some View {
        var el = Element.text("Ag", fontSize: 30, w: 64)
        el.color = "#6d28d9"
        el.align = "center"
        el.h = 44
        if let kind { el.warp = kind == TextWarp.custom ? warp : TextWarpSpec(kind: kind, amount: 60) }
        return TextElementView(element: el)
    }

    private func amountRow(_ warp: TextWarpSpec) -> some View {
        let readout = "\(Int(warp.amount.rounded()))"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Amount").font(.subheadline)
                Spacer()
                Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: Binding(get: { warp.amount }, set: { store.warpAmountTransient($0) }),
                   in: -100...100, step: 1, onEditingChanged: { editing in
                       if !editing { store.commit() }
                   })
                .accessibilityLabel("Warp amount")
                .accessibilityValue(readout)
        }
    }
}
