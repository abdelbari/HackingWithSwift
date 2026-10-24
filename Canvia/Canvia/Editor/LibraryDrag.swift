// A photo, clip or graphic dragged from the Add sheet onto the page, as
// Canva lets a tile be held and carried out of its panel. A held tile lifts
// (the system's drag, its ghost and its tap) and the sheet drops to its
// peek height, so the canvas — the column of pages too — takes the drop.
// The page under the finger is outlined, and a frame or grid cell under it
// lit, while a photo or clip is carried. Let go over a frame, the picture
// goes into it (Crop.replaced), one step named Replace, the frame selected;
// anywhere else on a page, the item goes on as its tile would put it,
// centred at the finger and kept on the page (HoldMenu.placed), one step on
// that page; a locked page says so; off every page, nothing at all. The
// Android twin's DropFromLibrary, with the same rows.

import SwiftUI
import UniformTypeIdentifiers

enum DropFromLibrary {

    /// What a tile carries.
    enum Tile: String, CaseIterable {
        case photo, clip, svgGraphic, icon, sticker, graphic

        /// Whether it goes into a frame let go over one: a picture.
        var fillsFrames: Bool { self == .photo || self == .clip }
    }

    /// Where a drop lands.
    enum Landing: Equatable {
        /// Into this frame or grid cell, full or empty.
        case frame(String)
        /// On the page, at the finger.
        case page
        /// Nowhere: off the page.
        case none
    }

    /// How long a tile is held before it lifts, in seconds, as on the
    /// Android twin; here the system's own drag decides.
    static let holdSeconds = 0.35

    /// Where an item of `kind` let go at `point`, in the units of a page of
    /// `page` size holding `elements`, lands: a picture over a frame or
    /// grid cell (PhotoFrames.target) goes into it; anything else on the
    /// page goes on the page; off the page — edges included in it — nowhere.
    static func target(_ point: CGPoint, elements: [Element], kind: Tile, page: CGSize) -> Landing {
        guard point.x >= 0, point.y >= 0, point.x <= page.width, point.y <= page.height else { return .none }
        if kind.fillsFrames, let frame = PhotoFrames.target(at: point, in: elements, excluding: nil) {
            return .frame(frame.id)
        }
        return .page
    }
}

/// The tile being dragged, held here in the app while the system carries
/// its drag: what it is, the picture it brings into a frame, and how it
/// goes on a page at a point. One at a time, let go as the drag lands.
final class LibraryDrag {

    static let shared = LibraryDrag()

    struct Item {
        var kind: DropFromLibrary.Tile
        /// A photo's or clip's picture, for a frame.
        var src: String?
        /// The item put on the page worked, centred at a point of it.
        var place: (CGPoint) -> Void
    }

    /// What the drag carries, as text, for the system: the app's own mark,
    /// seen by this app alone.
    static let payload = "canvia-add"

    /// The item under way.
    var item: Item?
    /// Told as a tile lifts: the sheet goes down to its peek.
    var onLift: (() -> Void)?

    func begin(_ item: Item) {
        self.item = item
        onLift?()
    }

    /// The item, let go of.
    func take() -> Item? {
        defer { item = nil }
        return item
    }
}

extension View {
    /// A tile of the Add sheet that lifts as it is held and is carried onto
    /// the canvas (LibraryDrag).
    func libraryDrag(_ item: @escaping () -> LibraryDrag.Item) -> some View {
        onDrag {
            LibraryDrag.shared.begin(item())
            // Words for this app alone: let go in another, nothing lands.
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier,
                                                visibility: .ownProcess) { done in
                done(Data(LibraryDrag.payload.utf8), nil)
                return nil
            }
            return provider
        }
    }
}

/// A tile that lifts when there is something for it to carry, and is
/// only a tile when there is not.
struct LibraryDragTile: ViewModifier {
    let item: (() -> LibraryDrag.Item)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let item {
            content.libraryDrag(item)
        } else {
            content
        }
    }
}

extension DesignStore {

    /// What was just added — the selection — moved so its box is centred
    /// at `point`, kept on the page (HoldMenu.placed): part of the add's own
    /// step, so one Undo takes both, as a cascade's nudge is.
    func moveAdded(to point: CGPoint) {
        let members = selectedElements
        guard !members.isEmpty else { return }
        let box = Geometry.union(members.map(Geometry.aabb))
        let at = HoldMenu.placed(box.size, at: point, page: pageSize)
        let dx = Double(at.x - box.minX), dy = Double(at.y - box.minY)
        let ids = selection
        for i in design.pages[pageIndex].elements.indices where ids.contains(design.pages[pageIndex].elements[i].id) {
            design.pages[pageIndex].elements[i].x += dx
            design.pages[pageIndex].elements[i].y += dy
        }
        Connectors.resolve(&design.pages[pageIndex])
    }

    /// The picture `src` into the frame `id` on the page worked, as one
    /// step named Replace, the frame then selected. False when it could not
    /// go — the frame locked, said.
    @discardableResult
    func dropPicture(_ src: String, intoFrame id: String) -> Bool {
        namedStep = tr("Replace")
        guard replacePicture(id, with: src) else {
            namedStep = nil
            return false
        }
        selection = [id]
        buzz(.confirm)
        return true
    }

    /// The one frame or grid cell selected, which a picture tile's "Add to
    /// the selected frame" fills.
    var selectedFrame: String? {
        guard let el = singleSelection, PhotoFrames.isFrameLike(el, among: page.elements) else { return nil }
        return el.id
    }

    /// A dragged tile let go at `point` on page `index` (the one worked, or
    /// another in the column): into the frame there, on the page there, or
    /// — a locked page — refused and said. True when anything happened.
    @discardableResult
    func dropLibraryItem(_ item: LibraryDrag.Item, at point: CGPoint, onPage index: Int) -> Bool {
        guard design.pages.indices.contains(index), !refusesLockedPage(at: index) else { return false }
        let page = design.pages[index]
        let target = DropFromLibrary.target(point, elements: page.elements, kind: item.kind, page: design.size(for: page))
        if target == .none { return false }
        if index != pageIndex { setPage(index) }
        if case .frame(let id) = target, let src = item.src { return dropPicture(src, intoFrame: id) }
        item.place(point)
        return true
    }
}

/// The canvas as a drop target: a tile carried from the Add sheet
/// (LibraryDrag) lands as dropLibraryItem places it, the page and the frame
/// under the finger lit as it goes and the view scrolling at the edge;
/// anything else from another app goes to `fallback` (CanvasDrop.handle),
/// where there is one. `locate` turns a point of the view it is on into
/// the page under it and the point on that page, nil off every page;
/// `toContent` into the canvas's content, for the edge scroll.
struct CanvasDropDelegate: DropDelegate {
    let store: DesignStore
    let edges: EdgeScroller
    let locate: (CGPoint) -> (index: Int, point: CGPoint)?
    let toContent: (CGPoint) -> CGPoint
    /// Told what a carried tile is over: the page, and the frame there.
    let hover: (Int?, String?) -> Void
    @Binding var targeted: Bool
    var fallback: (([NSItemProvider], CGPoint) -> Bool)?

    /// The tile under way, when this drag is one: a drag that also carries
    /// a picture or a link is another app's, and a tile left from a drag
    /// let go elsewhere is forgotten.
    private func carried(_ info: DropInfo) -> LibraryDrag.Item? {
        if info.hasItemsConforming(to: [.image, .url]) {
            LibraryDrag.shared.item = nil
            return nil
        }
        return LibraryDrag.shared.item
    }

    func dropEntered(info: DropInfo) {
        targeted = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let item = carried(info) else { return DropProposal(operation: .copy) }
        let spot = locate(info.location)
        var frame: String?
        if let spot, store.design.pages.indices.contains(spot.index) {
            let page = store.design.pages[spot.index]
            if case .frame(let id) = DropFromLibrary.target(spot.point, elements: page.elements, kind: item.kind,
                                                             page: store.design.size(for: page)) {
                frame = id
            }
        }
        hover(spot?.index, frame)
        edges.track(toContent(info.location)) { _ in }
        return DropProposal(operation: spot == nil ? .cancel : .copy)
    }

    func dropExited(info: DropInfo) {
        targeted = false
        hover(nil, nil)
        edges.stop()
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        hover(nil, nil)
        edges.stop()
        if let item = carried(info) {
            LibraryDrag.shared.item = nil
            guard let spot = locate(info.location) else { return false }
            return store.dropLibraryItem(item, at: spot.point, onPage: spot.index)
        }
        guard let fallback else { return false }
        return fallback(info.itemProviders(for: CanvasDrop.types), info.location)
    }
}
