// Drop shadows and glows.
//
// The one effect that separates a flat mockup from something that looks
// placed on a page. Presets first, because "Soft" is what most people want
// and a slider for blur is not how anyone thinks about it; dials after, for
// the person who does.

import SwiftUI

struct ShadowSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    private var current: Shadow? { store.singleSelection?.shadow }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    presets
                    if current != nil { dials }
                }
                .padding()
            }
            .navigationTitle("Shadow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onDisappear { if store.hasPendingChanges { store.commit() } }
    }

    private var presets: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
            tile(nil, name: "None")
            ForEach(Shadow.presets, id: \.name) { preset in
                tile(preset.shadow, name: preset.name)
            }
        }
    }

    private func tile(_ shadow: Shadow?, name: String) -> some View {
        let active = current == shadow
        return Button {
            store.updateSelected { $0.shadow = shadow }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.card)
                    .frame(width: 60, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                    .shadow(color: shadow.map { Color(hex: $0.color).opacity($0.opacity) } ?? .clear,
                            radius: (shadow?.blur ?? 0) / 2,
                            x: (shadow?.offsetX ?? 0) / 2, y: (shadow?.offsetY ?? 0) / 2)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                Text(name).font(.caption)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 14)
                .stroke(active ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var dials: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adjust").font(.headline)
            dial("Opacity", \.opacity, in: 0...1, format: { "\(Int(($0 * 100).rounded()))%" })
            dial("Blur", \.blur, in: 0...60, format: { "\(Int($0.rounded()))" })
            dial("Across", \.offsetX, in: -60...60, format: { String(format: "%+.0f", $0) })
            dial("Down", \.offsetY, in: -60...60, format: { String(format: "%+.0f", $0) })
            HStack {
                Text("Colour").font(.subheadline)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: current?.color ?? "#000000") },
                    set: { color in
                        let hex = UIColor(color).hexString
                        store.updateSelectedTransient { $0.shadow?.color = hex }
                    }), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    private func dial(_ label: String, _ key: WritableKeyPath<Shadow, Double>,
                      in range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        let value = current?[keyPath: key] ?? range.lowerBound
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(format(value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value },
                set: { v in store.updateSelectedTransient { $0.shadow?[keyPath: key] = v } }
            ), in: range, onEditingChanged: { editing in
                if !editing { store.commit() }
            })
        }
    }
}
