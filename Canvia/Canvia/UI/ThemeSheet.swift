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
    /// The active brand kit's text roles, by size rank, in place of a
    /// pairing.
    @State private var brandFonts = false
    /// Read once as the sheet opens, not on every tap.
    @State private var kit = BrandKit.load()

    /// The active brand kit's palettes first, each with two or more
    /// colours, then the library's.
    private var palettes: [Palette] {
        kit.themePalettes + ContentLibrary.palettes
    }

    /// The kit's roles when they are chosen; none set otherwise.
    private var chosenBrandFonts: BrandFonts { brandFonts ? kit.fonts : BrandFonts() }

    private var palette: Palette? {
        guard let paletteIndex, palettes.indices.contains(paletteIndex) else { return nil }
        return palettes[paletteIndex]
    }

    private var preview: Design {
        DesignStore.themed(store.design, palette: palette?.colors, pairing: pairing, brandFonts: chosenBrandFonts)
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
                        store.applyTheme(palette: palette?.colors, pairing: pairing, brandFonts: chosenBrandFonts)
                        dismiss()
                    }
                    .disabled(palette == nil && pairing == nil && !brandFonts)
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
                .accessibilityLabel(BrandKit.isBrandPalette(p) ? "\(kit.name), \(p.name)" : p.name)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
    }

    private var pairingList: some View {
        VStack(spacing: 8) {
            if !kit.fonts.rankedRoles.isEmpty { brandFontsRow }
            ForEach(ContentLibrary.pairings) { pr in
                Button {
                    pairing = pairing?.id == pr.id ? nil : pr
                    brandFonts = false
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

    /// The active kit's faces, set by size rank: its title and heading
    /// faces drawn as a pairing's are, with the kit's name.
    private var brandFontsRow: some View {
        let ranked = kit.fonts.rankedRoles.compactMap { kit.fonts[$0] }
        let top = ranked.first, last = ranked.last
        return Button {
            brandFonts.toggle()
            if brandFonts { pairing = nil }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Brand heading")
                        .font(FontLibrary.font(family: top?.family ?? "sans", size: 18,
                                               weight: top?.weight ?? 700, italic: false))
                    Text("Brand body text")
                        .font(FontLibrary.font(family: last?.family ?? "sans", size: 13,
                                               weight: last?.weight ?? 400, italic: false))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer()
                Text(kit.name).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(brandFonts ? Theme.accentSubtle : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(brandFonts ? Theme.accent : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kit.name) fonts, by size")
        .accessibilityAddTraits(brandFonts ? [.isSelected] : [])
    }
}
