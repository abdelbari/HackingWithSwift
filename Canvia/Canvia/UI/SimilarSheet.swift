// More like this, for a selected icon, sticker, graphic from the pack or
// library shape: a strip of things like it (ElementSearch.similar), as
// Canva's "See more like this". A tap swaps the selection for one in place,
// keeping its box, turn, opacity, motion, link and main colour (LikeThis) —
// one Undo; a press and hold puts one on the page beside it instead, as Add
// would. Opened from the selection's tool row and from the quick actions at
// the selection, as the Android twin opens it from its selection bar and
// hold menu.

import SwiftUI

struct SimilarSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// What was like the selection as the sheet opened: kept while it is
    /// up, so each swap leaves the rest to try.
    @State private var hits: [ElementSearch.Hit] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                if hits.isEmpty {
                    Text("Nothing else like this")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    strip
                    Text("Tap one to swap it in. Touch and hold to add it as well.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("More like this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.height(210), .medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(210)))
        .onAppear { hits = store.similarToSelection }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(hits, id: \.key) { hit in
                    HitTile(hit: hit, onHold: { store.addSimilar(hit) }) { store.replaceWithSimilar(hit) }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
        }
    }
}

extension DesignStore {

    /// Several things selected that are one graphic from the pack: its
    /// parts, all in one group, all naming it.
    private var selectionIsOneGraphic: Bool {
        let chosen = selectedElements
        guard chosen.count > 1, let first = chosen.first, first.group != nil,
              let graphic = GraphicsLibrary.graphic(of: first) else { return false }
        return chosen.allSatisfy { $0.group == first.group && GraphicsLibrary.graphic(of: $0) == graphic }
    }

    /// Whether the selection has More like this: one icon, sticker or
    /// library shape that swaps, or one graphic from the pack, none of it
    /// locked. Cheap, for the tool row; the sheet finds the things.
    var offersSimilar: Bool {
        let chosen = selectedElements
        guard let first = chosen.first, !chosen.contains(where: { $0.locked }) else { return false }
        if chosen.count > 1 { return selectionIsOneGraphic }
        return IconLibrary.icon(of: first) != nil || GraphicsLibrary.graphic(of: first) != nil
            || first.type == .sticker || Self.swapsShape(first)
    }

    /// Things like the selection, best first (ElementSearch.similar); none
    /// for anything else, or for several things that are not one graphic.
    var similarToSelection: [ElementSearch.Hit] {
        let chosen = selectedElements
        guard let first = chosen.first, chosen.count == 1 || selectionIsOneGraphic else { return [] }
        return ElementSearch.similar(first)
    }

    /// What `hit` puts on a page of this one's size, as Add puts it.
    func similarElements(for hit: ElementSearch.Hit) -> [Element] {
        let side = min(pageWidth, pageHeight)
        switch hit.kind {
        case .icon:
            guard let icon = IconLibrary.icon(hit.id) else { return [] }
            let fill = IconLibrary.fill(for: page, brandColours: BrandKit.load().colors)
            return [IconLibrary.element(icon, pageWidth: pageWidth, pageHeight: pageHeight, fill: fill)]
        case .graphic:
            guard let graphic = GraphicsLibrary.graphic(hit.id) else { return [] }
            return GraphicsLibrary.elements(graphic, pageWidth: pageWidth, pageHeight: pageHeight)
        case .sticker:
            return [.sticker(hit.id, size: side * 0.18)]
        case .shape:
            return [.shape(hit.id, w: side * 0.28, h: side * 0.28)]
        default:
            return []
        }
    }

    /// The selection replaced in place by `fresh` — More like this — as one
    /// step, keeping its box, turn, opacity, motion, link and main colour
    /// (LikeThis.replaced); the new thing goes where the old one's first
    /// part was among the layers, and is selected. False, and said, on a
    /// locked page or when any of the selection is locked, as on the
    /// Android twin.
    @discardableResult
    func replaceSelected(with fresh: [Element]) -> Bool {
        let old = selectedElements
        guard !old.isEmpty, !fresh.isEmpty, !refusesLockedPage() else { return false }
        guard !old.contains(where: { $0.locked }) else {
            buzz(.reject)
            announce(tr("Unlock it to change it"), undoable: false)
            return false
        }
        let placed = LikeThis.replaced(old, with: fresh)
        let ids = Set(old.map(\.id))
        applyToPage { page in
            let at = page.elements.firstIndex { ids.contains($0.id) } ?? page.elements.count
            var rest = page.elements.filter { !ids.contains($0.id) }
            rest.insert(contentsOf: placed, at: min(max(at, 0), rest.count))
            page.elements = rest
        }
        selection = Set(placed.map(\.id))
        return true
    }

    /// The selection swapped for `hit`, remembered in Add's Recently used.
    func replaceWithSimilar(_ hit: ElementSearch.Hit) {
        guard replaceSelected(with: similarElements(for: hit)) else { return }
        ElementSearch.remember(hit.kind, hit.id)
        buzz(.confirm)
    }

    /// `hit` put on the page as a new thing — More like this's press and
    /// hold — as Add would put it: onto the next unlocked page when this
    /// one is locked.
    func addSimilar(_ hit: ElementSearch.Hit) {
        var added = false
        if hit.kind == .graphic, let graphic = GraphicsLibrary.graphic(hit.id) {
            added = addPackGraphic(graphic)
        } else if let one = similarElements(for: hit).first {
            added = add(one)
            if added { buzz(.confirm) }
        }
        if added { ElementSearch.remember(hit.kind, hit.id) }
    }
}
