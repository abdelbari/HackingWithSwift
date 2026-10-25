// Diagrams in the editor (Diagrams): Add's Diagrams row — a tile for each
// kind, drawn by the page renderer as it will go on, in the page's colours,
// else the brand's — and Edit diagram, the diagram selected as a list: each
// item's words and a second line, moved up or down, an org chart's indented
// or not, taken away, or a new one added; its kind, its style and its
// colours, from the page or a brand palette. Each change makes it again
// where it stands, one undo step (DesignStore.updateDiagram). The Android
// twin's DiagramRow and DiagramPanel.

import SwiftUI

/// Add's Diagrams row: a tile for each kind of diagram; a tap adds it
/// across the middle of the page.
struct DiagramRow: View {
    @Bindable var store: DesignStore
    var onAdded: () -> Void

    var body: some View {
        let palette = store.newChartPalette
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DiagramKind.allCases) { kind in
                    Button {
                        if store.addDiagram(kind) { onAdded() }
                    } label: {
                        VStack(spacing: 4) {
                            DiagramTile(kind: kind, palette: palette)
                            Text(kind.label)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(width: DiagramTile.width)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tr("%@ diagram", kind.label))
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}

/// A kind's starting diagram (Diagrams.starter) as the page renderer draws
/// it, made at a page's scale — so its words are the size they will be —
/// and drawn small, on white.
struct DiagramTile: View {
    let kind: DiagramKind
    let palette: [String]

    static let width: CGFloat = 120
    /// The page it is drawn on, and how small it is drawn.
    private static let page = CGSize(width: 960, height: 600)
    private static var scale: CGFloat { width / page.width }

    var body: some View {
        let design = DiagramTiles.design(kind, palette: palette)
        PageRenderView(design: design, page: design.pages[0])
            .scaleEffect(Self.scale)
            .frame(width: Self.page.width * Self.scale, height: Self.page.height * Self.scale)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The design a tile shows: one white page with the kind's starting
    /// diagram on it, 40 in from every edge.
    static func made(_ kind: DiagramKind, palette: [String]) -> Design {
        var design = Design(title: kind.label, width: Double(page.width), height: Double(page.height))
        var sheet = Page()
        sheet.elements = Diagrams.make(Diagrams.starter(kind),
                                       in: CGRect(x: 40, y: 40, width: page.width - 80, height: page.height - 80),
                                       palette: palette)
        design.pages = [sheet]
        return design
    }
}

/// The tiles' designs, made once for each kind and palette, so a tile drawn
/// again is the same design — its elements' ids and all.
@MainActor
enum DiagramTiles {
    private static var made: [String: Design] = [:]

    static func design(_ kind: DiagramKind, palette: [String]) -> Design {
        let key = kind.rawValue + "#" + palette.joined()
        if let known = made[key] { return known }
        let design = DiagramTile.made(kind, palette: palette)
        made[key] = design
        return design
    }
}

/// Edit diagram: the diagram selected, as a list.
struct DiagramSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// The item whose words are being typed, and the words and note.
    @State private var wording: Int?
    @State private var words = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Group {
                if let spec = store.selectedDiagram, !store.diagramIsLocked(spec.id) {
                    editor(spec)
                } else {
                    Text(store.selectedDiagram == nil ? tr("Select a diagram on the page to edit it.")
                         : tr("This diagram is locked. Unlock it from More to edit it."))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Edit diagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func editor(_ spec: DiagramSpec) -> some View {
        Form {
            Section {
                kindChips(spec)
                styleChips(spec)
            }
            Section("Colours") { DiagramPalettes(store: store, spec: spec) }
            Section("Items") {
                ForEach(Array(spec.items.enumerated()), id: \.offset) { i, item in
                    DiagramItemRow(spec: spec, index: i, item: item, update: update) {
                        words = item.text
                        note = item.note ?? ""
                        wording = i
                    }
                }
                Button {
                    update(Diagrams.adding(spec, text: tr("Item %d", spec.items.count + 1)))
                } label: {
                    Label("Add item", systemImage: "plus")
                }
                .disabled(spec.items.count >= spec.kind.maxItems)
            }
        }
        .alert(wording.map { tr("Item %d of %d", $0 + 1, spec.items.count) } ?? "",
               isPresented: Binding(get: { wording != nil }, set: { if !$0 { wording = nil } })) {
            TextField("Words", text: $words)
            TextField("Note", text: $note)
            Button("Done") {
                if let i = wording { update(Diagrams.editing(spec, at: i, text: words, note: note)) }
                wording = nil
            }
            Button("Cancel", role: .cancel) { wording = nil }
        }
    }

    private func kindChips(_ spec: DiagramSpec) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiagramKind.allCases) { kind in
                    chip(kind.label, on: spec.kind == kind) { update(Diagrams.switching(spec, to: kind)) }
                }
            }
        }
    }

    private func styleChips(_ spec: DiagramSpec) -> some View {
        HStack(spacing: 8) {
            ForEach(DiagramStyle.allCases) { style in
                chip(style.label, on: spec.style == style) {
                    var restyled = spec
                    restyled.style = style
                    update(restyled)
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(on ? Theme.accentSubtle : Color(.systemGray6)))
                .overlay(Capsule().stroke(on ? Theme.accent : Color.clear))
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func update(_ spec: DiagramSpec) {
        store.updateDiagram(spec)
    }
}

/// One item of the list: its words and note — a tap types them — and, as
/// labelled buttons, indent and outdent for an org chart, up, down and
/// remove.
private struct DiagramItemRow: View {
    let spec: DiagramSpec
    let index: Int
    let item: DiagramItem
    let update: (DiagramSpec) -> Void
    let edit: () -> Void

    var body: some View {
        let org = spec.kind == .orgChart
        let levels = Diagrams.levels(spec)
        HStack(spacing: 4) {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text.isEmpty ? tr("Item %d of %d", index + 1, spec.items.count) : item.text)
                        .lineLimit(1)
                    if let note = item.note {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, org ? CGFloat(levels[index] * 16) : 0)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.ink)
            .accessibilityLabel(Diagrams.stops(spec)[index])
            .accessibilityHint(tr("Edit words"))
            if org { indentButtons(levels) }
            moveButtons
        }
    }

    @ViewBuilder
    private func indentButtons(_ levels: [Int]) -> some View {
        iconButton("decrease.indent", tr("Outdent %@", item.text), enabled: levels[index] > 0) {
            update(Diagrams.indenting(spec, at: index, by: -1))
        }
        iconButton("increase.indent", tr("Indent %@", item.text),
                   enabled: index > 0 && levels[index] <= levels[index - 1]) {
            update(Diagrams.indenting(spec, at: index, by: 1))
        }
    }

    @ViewBuilder
    private var moveButtons: some View {
        iconButton("arrow.up", tr("Move %@ up", item.text), enabled: index > 0) {
            update(Diagrams.moving(spec, at: index, by: -1))
        }
        iconButton("arrow.down", tr("Move %@ down", item.text), enabled: index < spec.items.count - 1) {
            update(Diagrams.moving(spec, at: index, by: 1))
        }
        iconButton("trash", tr("Remove %@", item.text), enabled: spec.items.count > spec.kind.minItems) {
            update(Diagrams.removing(spec, at: index))
        }
    }

    private func iconButton(_ system: String, _ label: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).frame(width: 32, height: 32)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The colours a diagram takes: the page's — the colours a chart would take
/// there — or one of the brand kit's palettes of two or more, each shown as
/// swatches. Choosing one lets go of the items' own colours.
private struct DiagramPalettes: View {
    @Bindable var store: DesignStore
    let spec: DiagramSpec

    var body: some View {
        let brand = BrandKit.load().palettes.filter { $0.colors.count >= 2 }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                choice(tr("Page"), chosen: nil, shown: store.newChartPalette)
                ForEach(Array(brand.enumerated()), id: \.offset) { _, palette in
                    choice(palette.name, chosen: palette.colors, shown: palette.colors)
                }
            }
        }
    }

    private func choice(_ name: String, chosen: [String]?, shown: [String]) -> some View {
        let on = spec.palette == chosen
        return Button {
            store.updateDiagram(Diagrams.repainted(spec, palette: chosen), repaint: true)
        } label: {
            HStack(spacing: 2) {
                ForEach(Array(shown.prefix(5).enumerated()), id: \.offset) { _, hex in
                    Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
                }
                Text(name).font(.subheadline).padding(.leading, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(on ? Theme.accentSubtle : Color(.systemGray6)))
            .overlay(Capsule().stroke(on ? Theme.accent : Color.clear))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.ink)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
