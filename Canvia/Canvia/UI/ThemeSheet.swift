// A palette and a type pairing for the whole document, previewed on the
// first page before it touches anything.
//
// The shuffle button on the toolbar recolours one page at a time and
// leaves fonts alone. This is the deliberate version: pick the colours,
// pick the faces, see page one wearing them, apply to every page as one
// undo step.

import SwiftUI

struct ThemeSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var palette: Palette?
    @State private var pairing: FontPairing?

    private var preview: Design {
        DesignStore.themed(store.design, palette: palette?.colors, pairing: pairing)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewCard
                    Text("Colours").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    paletteGrid
                    Text("Type").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    pairingList
                }
                .padding()
            }
            .navigationTitle("Document theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        store.applyTheme(palette: palette?.colors, pairing: pairing)
                        dismiss()
                    }
                    .disabled(palette == nil && pairing == nil)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var previewCard: some View {
        let design = preview
        return VStack(alignment: .leading, spacing: 6) {
            PageRenderView(design: design, page: design.pages[0])
                .scaleEffect(previewScale(design), anchor: .topLeading)
                .frame(width: design.width * previewScale(design),
                       height: design.height * previewScale(design))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                .frame(maxWidth: .infinity)
            Text(design.pages.count == 1 ? "Preview" : "Preview of page 1 — applies to all \(design.pages.count) pages")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func previewScale(_ design: Design) -> Double {
        min(320 / max(design.width, 1), 220 / max(design.height, 1))
    }

    private var paletteGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(ContentLibrary.palettes) { p in
                Button {
                    palette = palette?.id == p.id ? nil : p
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 0) {
                            ForEach(Array(p.colors.enumerated()), id: \.offset) { _, hex in
                                Color(hex: hex)
                            }
                        }
                        .frame(height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(p.name).font(.caption).lineLimit(1)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(palette?.id == p.id ? Theme.accentSubtle : Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(palette?.id == p.id ? Theme.accent : Theme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.name)
                .accessibilityAddTraits(palette?.id == p.id ? [.isSelected] : [])
            }
        }
    }

    private var pairingList: some View {
        VStack(spacing: 8) {
            ForEach([BrandKit.load().pairing].compactMap { $0 } + ContentLibrary.pairings) { pr in
                Button {
                    pairing = pairing?.id == pr.id ? nil : pr
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.heading.text)
                                .font(FontLibrary.font(family: pr.heading.fontFamily, size: 18,
                                                       weight: pr.heading.fontWeight, italic: false))
                            Text(pr.body.text)
                                .font(FontLibrary.font(family: pr.body.fontFamily, size: 13,
                                                       weight: pr.body.fontWeight, italic: false))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        Spacer()
                        Text(pr.name).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(pairing?.id == pr.id ? Theme.accentSubtle : Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(pairing?.id == pr.id ? Theme.accent : Theme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pr.name)
                .accessibilityAddTraits(pairing?.id == pr.id ? [.isSelected] : [])
            }
        }
    }
}
