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
    /// Which of `palettes` is chosen, by position: the library repeats a
    /// few palette ids, so an id cannot tell two tiles apart.
    @State private var paletteIndex: Int?
    @State private var pairing: FontPairing?
    /// Read once as the sheet opens, not on every tap.
    @State private var kit = BrandKit.load()

    /// The brand kit's colours first, when it has two or more, then the
    /// library's palettes.
    private var palettes: [Palette] {
        [kit.palette].compactMap { $0 } + ContentLibrary.palettes
    }

    private var palette: Palette? {
        guard let paletteIndex, palettes.indices.contains(paletteIndex) else { return nil }
        return palettes[paletteIndex]
    }

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
                .frame(width: Double(design.size(at: 0).width) * previewScale(design),
                       height: Double(design.size(at: 0).height) * previewScale(design))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                .frame(maxWidth: .infinity)
            Text(design.pages.count == 1 ? "Preview" : "Preview of page 1 — applies to all \(design.pages.count) pages")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func previewScale(_ design: Design) -> Double {
        let size = design.size(at: 0)
        return min(320 / max(Double(size.width), 1), 220 / max(Double(size.height), 1))
    }

    private var paletteGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(Array(palettes.enumerated()), id: \.offset) { index, p in
                let chosen = paletteIndex == index
                Button {
                    paletteIndex = chosen ? nil : index
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
                        .fill(chosen ? Theme.accentSubtle : Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(chosen ? Theme.accent : Theme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.id == "brand-kit" ? "Brand kit colours" : p.name)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
    }

    private var pairingList: some View {
        VStack(spacing: 8) {
            ForEach([kit.pairing].compactMap { $0 } + ContentLibrary.pairings) { pr in
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
