// What Add's one search finds, and Recently used.
//
// The hits of ElementSearch in their sections, in their fixed order —
// Shapes, Icons, Graphics, Stickers, Frames, Grids, Lines, Charts and
// tables, Artwork
// — each its first eight, best first, with See all for the rest; and each
// hit drawn as its own tab draws it. A tap is the sheet's to carry out, as
// its own tab would. As the Android twin's ElementResults.

import SwiftUI

struct ElementResults: View {
    let query: String
    let onInsert: (ElementSearch.Hit) -> Void
    /// The section shown whole, after See all.
    @State private var all: ElementSearch.Shelf?

    var body: some View {
        let hits = ElementSearch.results(query)
        let sections = ElementSearch.sections(hits)
        VStack(alignment: .leading, spacing: 8) {
            if hits.isEmpty {
                Text(ElementSearch.nothingFound(query))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else if let open = all, let found = sections.first(where: { $0.section == open }) {
                heading(open.title) {
                    Button("All results") { all = nil }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                    ForEach(found.hits, id: \.key) { hit in
                        HitTile(hit: hit) { onInsert(hit) }
                    }
                }
            } else {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, entry in
                    section(entry.section, entry.hits)
                }
            }
        }
        .padding()
        .onChange(of: query) { all = nil }
    }

    /// A section's first eight, and See all when it has more.
    @ViewBuilder
    private func section(_ section: ElementSearch.Shelf, _ found: [ElementSearch.Hit]) -> some View {
        heading(section.title) {
            if found.count > ElementSearch.sectionLimit {
                Button("See all") { all = section }
                    .accessibilityLabel("See all \(section.title.lowercased()), \(found.count)")
            }
        }
        HitRow(hits: Array(found.prefix(ElementSearch.sectionLimit)), onInsert: onInsert)
    }

    private func heading<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            InsertSheet.header(title)
            Spacer()
            trailing()
                .font(.footnote.weight(.semibold))
                .tint(Theme.accent)
        }
    }
}

/// A row of hits to scroll across: Recently used — the last things put on
/// a page from Add, of every kind, newest first — or a section's first few.
struct HitRow: View {
    let hits: [ElementSearch.Hit]
    let onInsert: (ElementSearch.Hit) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(hits, id: \.key) { hit in
                    HitTile(hit: hit) { onInsert(hit) }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// A hit drawn as its own tab draws it, its name under it; a chart, the
/// table and the QR code, which are made from what you type, by a symbol.
/// With `onHold`, a press and hold does that instead of the tap (More like
/// this adds one rather than swapping it in), and VoiceOver offers it as an
/// action.
struct HitTile: View {
    let hit: ElementSearch.Hit
    var onHold: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if let onHold {
                tile
                    .contentShape(Rectangle())
                    .onTapGesture(perform: action)
                    .onLongPressGesture(perform: onHold)
                    .accessibilityAction(named: Text("Add to this page"), onHold)
            } else {
                Button(action: action) { tile }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var tile: some View {
        VStack(spacing: 4) {
            face
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(hit.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 72)
    }

    /// What VoiceOver says: the name, and what it is where the name alone
    /// would not say.
    private var spoken: String {
        switch hit.kind {
        case .sticker: return tr("%@ sticker", hit.name)
        case .photoFrame: return tr("%@ photo frame", hit.name)
        case .grid: return tr("%@ photo grid", hit.name)
        case .icon: return tr("%@ icon", hit.name)
        case .graphic: return tr("%@ graphic", hit.name)
        default: return hit.name
        }
    }

    @ViewBuilder
    private var face: some View {
        switch hit.kind {
        case .shape:
            if let shape = ContentLibrary.shapeMap[hit.id] {
                LibraryShape(definition: shape, cornerRadius: 0)
                    .fill(Color(hex: "#545d6b"))
                    .padding(8)
            }
        case .icon:
            if let icon = IconLibrary.icon(hit.id) {
                LibraryShape(definition: icon.shape, cornerRadius: 0)
                    .fill(Color(hex: "#545d6b"))
                    .padding(14)
            }
        case .graphic:
            if let graphic = GraphicsLibrary.graphic(hit.id) { GraphicThumb(graphic: graphic).padding(6) }
        case .sticker:
            Text(hit.id).font(.largeTitle)
        case .photoFrame:
            if let preset = DecorativeFrames.preset(hit.id) { InsertSheet.decorativeFrameThumb(preset) }
        case .grid:
            if let layout = PhotoGrids.layout(hit.id) { InsertSheet.layoutThumb(layout) }
        case .line:
            symbol(ElementSearch.linePresets.first { $0.name == hit.id }?.symbol ?? "line.diagonal")
        case .chart:
            symbol(hit.id == "pie" || hit.id == "donut" ? "chart.pie" : "chart.bar.xaxis")
        case .table:
            symbol("tablecells")
        case .qr:
            symbol("qrcode")
        case .stockArt:
            photoThumb(hit.id)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title2)
            .foregroundStyle(.primary)
    }
}
