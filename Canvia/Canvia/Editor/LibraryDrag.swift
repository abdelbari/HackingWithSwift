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
//
// A photo or clip held over a plain photo, clip or moving picture for
// replaceHoldSeconds outlines it with a Replace chip; let go then, the
// picture replaces its own in place (Crop.replaced: its crop back to
// filling, its look, effects, shadow, animation, link and alt text kept),
// one step named Replace. Moving away before the hold is up drops on the
// page as before.

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
        /// In place of this plain photo's, clip's or moving picture's
        /// picture, held over it long enough (replaceTarget).
        case replace(String)
        /// On the page, at the finger.
        case page
        /// Nowhere: off the page.
        case none
    }

    /// How long a tile is held before it lifts, in seconds, as on the
    /// Android twin; here the system's own drag decides.
    static let holdSeconds = 0.35

    /// How long a carried picture is held over a plain photo before it
    /// would replace it, in seconds, as on the Android twin.
    static let replaceHoldSeconds = 0.45

    /// The plain photo, clip or moving picture whose picture one let go at
    /// `point` would replace: the topmost thing under it (Geometry.hits, so
    /// never a hidden one, and one covered by something else is not
    /// reached), when that is an unlocked image with a picture — not a
    /// frame or a grid's cell, which take a picture as frames do
    /// (PhotoFrames.isFrameLike), and not a code. Never `excluding`, the
    /// photo being dragged.
    static func replaceTarget(at point: CGPoint, in elements: [Element], excluding id: String? = .none) -> Element? {
        guard let top = elements.last(where: { $0.id != id && Geometry.hits($0, point: point) }),
              top.type == .image, !top.locked, let src = top.src, !src.isEmpty, !CodeGenerator.isCode(src),
              !PhotoFrames.isFrameLike(top, among: elements) else { return nil }
        return top
    }

    /// Where an item of `kind` let go at `point`, in the units of a page of
    /// `page` size holding `elements`, lands: a picture over a frame or
    /// grid cell (PhotoFrames.target) goes into it, and over the plain
    /// photo `held` over long enough (replaceTarget) replaces its picture;
    /// anything else on the page goes on the page; off the page — edges
    /// included in it — nowhere.
    static func target(_ point: CGPoint, elements: [Element], kind: Tile, page: CGSize,
                       held: String? = .none) -> Landing {
        guard point.x >= 0, point.y >= 0, point.x <= page.width, point.y <= page.height else { return .none }
        if kind.fillsFrames, let frame = PhotoFrames.target(at: point, in: elements, excluding: nil) {
            return .frame(frame.id)
        }
        if kind.fillsFrames, let held, replaceTarget(at: point, in: elements)?.id == held {
            return .replace(held)
        }
        return .page
    }
}

/// The tile being dragged, held here in the app while the system carries
/// its drag: what it is, the picture it brings into a frame, and how it
/// goes on a page at a point. One at a time, let go as the drag lands.
final class LibraryDrag {

    static let shared = LibraryDrag()

    struct Carried {
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
    var item: Carried?
    /// Told as a tile lifts: the sheet goes down to its peek.
    var onLift: (() -> Void)?
    /// The plain photo a carried picture is over, and whether it has been
    /// held there long enough to replace it.
    private(set) var over: String?
    private(set) var armed = false
    /// Which hold is running, so one given up does not arm.
    private var holding = 0

    /// The plain photo a carried picture would replace if let go now: the
    /// one under it, held there long enough.
    var heldTarget: String? { armed ? over : nil }

    /// `id` now under the carried picture (nil, none): held there
    /// replaceHoldSeconds it arms, and `armed` is told; another, or none,
    /// starts again.
    func hold(_ id: String?, onArmed: @escaping () -> Void) {
        guard id != over else { return }
        over = id
        armed = false
        holding += 1
        guard id != nil else { return }
        let mine = holding
        DispatchQueue.main.asyncAfter(deadline: .now() + DropFromLibrary.replaceHoldSeconds) { [weak self] in
            guard let self, self.holding == mine else { return }
            self.armed = true
            onArmed()
        }
    }

    /// No hold any more: the drag left, or landed.
    func letGo() {
        hold(nil) {}
    }

    func begin(_ item: Carried) {
        self.item = item
        onLift?()
    }

    /// The item, let go of.
    func take() -> Carried? {
        defer {
            item = nil
            letGo()
        }
        return item
    }
}

extension View {
    /// A tile of the Add sheet that lifts as it is held and is carried onto
    /// the canvas (LibraryDrag).
    func libraryDrag(_ item: @escaping () -> LibraryDrag.Carried) -> some View {
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
    let item: (() -> LibraryDrag.Carried)?

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

    /// The picture `src` into the frame `id` on the page worked — or in
    /// place of the plain photo `id`'s — as one step named Replace, the
    /// frame then selected. False when it could not go — the frame locked,
    /// said.
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
    func dropLibraryItem(_ item: LibraryDrag.Carried, at point: CGPoint, onPage index: Int,
                         held: String? = .none) -> Bool {
        guard design.pages.indices.contains(index), !refusesLockedPage(at: index) else { return false }
        let page = design.pages[index]
        let target = DropFromLibrary.target(point, elements: page.elements, kind: item.kind,
                                            page: design.size(for: page), held: held)
        if target == .none { return false }
        if index != pageIndex { setPage(index) }
        if case .frame(let id) = target, let src = item.src { return dropPicture(src, intoFrame: id) }
        if case .replace(let id) = target, let src = item.src { return dropPicture(src, intoFrame: id) }
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
    /// Told what a carried tile is over: the page, the frame there, and
    /// the plain photo it would replace, held over long enough.
    let hover: (Int?, String?, String?) -> Void
    @Binding var targeted: Bool
    var fallback: (([NSItemProvider], CGPoint) -> Bool)?

    /// The tile under way, when this drag is one: a drag that also carries
    /// a clip, a picture or a link is another app's, and a tile left from a drag
    /// let go elsewhere is forgotten.
    private func carried(_ info: DropInfo) -> LibraryDrag.Carried? {
        if info.hasItemsConforming(to: [.movie, .image, .url]) {
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
        var replacing: String?
        var under: String?
        if let spot, store.design.pages.indices.contains(spot.index) {
            let page = store.design.pages[spot.index]
            switch DropFromLibrary.target(spot.point, elements: page.elements, kind: item.kind,
                                          page: store.design.size(for: page), held: LibraryDrag.shared.heldTarget) {
            case .frame(let id): frame = id
            case .replace(let id): replacing = id
            default: break
            }
            if item.kind.fillsFrames && frame == nil {
                under = DropFromLibrary.replaceTarget(at: spot.point, in: page.elements)?.id
            }
        }
        // Held over a plain photo, it lights up once the hold is up.
        let hover = self.hover
        let index = spot?.index
        LibraryDrag.shared.hold(under) { hover(index, nil, under) }
        hover(index, frame, replacing)
        edges.track(toContent(info.location)) { _ in }
        return DropProposal(operation: spot == nil ? .cancel : .copy)
    }

    func dropExited(info: DropInfo) {
        targeted = false
        LibraryDrag.shared.letGo()
        hover(nil, nil, nil)
        edges.stop()
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        hover(nil, nil, nil)
        edges.stop()
        if let item = carried(info) {
            let held = LibraryDrag.shared.heldTarget
            LibraryDrag.shared.item = nil
            LibraryDrag.shared.letGo()
            guard let spot = locate(info.location) else { return false }
            return store.dropLibraryItem(item, at: spot.point, onPage: spot.index, held: held)
        }
        guard let fallback else { return false }
        return fallback(info.itemProviders(for: CanvasDrop.types), info.location)
    }
}

/// The plain photo a carried or dragged picture would replace, held over
/// it long enough: its outline in the accent colour, and a Replace chip
/// over its top edge, at the screen's size whatever the zoom (`iz`).
struct ReplaceMark: View {
    let outline: Path
    /// The middle of its top edge, in page units.
    let at: CGPoint
    let iz: Double

    var body: some View {
        ZStack {
            outline
                .stroke(Theme.accent, lineWidth: 3 * iz)
                .background(outline.fill(Theme.accent.opacity(0.14)))
            Text("Replace")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.accent, in: Capsule())
                .scaleEffect(iz)
                .position(x: at.x, y: at.y - 18 * iz)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension DesignStore {

    /// Photo `dragged`, let go over the plain photo `target` it was held
    /// over, swaps pictures with it: each takes the other's picture in
    /// place (Crop.replaced), the dragged one back at `home` where its move
    /// began — the move and the swap one step, named Replace — and the
    /// target ends selected. False when either cannot change.
    @discardableResult
    func swapPictures(_ dragged: String, with target: String, home: CGPoint) -> Bool {
        guard let a = element(dragged), let b = element(target), a.type == .image, b.type == .image,
              !a.locked, !b.locked, let srcA = a.src, let srcB = b.src, !isPageLocked else { return false }
        beginGesture()
        for i in page.elements.indices {
            if page.elements[i].id == dragged {
                var moved = Crop.replaced(page.elements[i], src: srcB)
                moved.x = Double(home.x)
                moved.y = Double(home.y)
                page.elements[i] = moved
            } else if page.elements[i].id == target {
                page.elements[i] = Crop.replaced(page.elements[i], src: srcA)
            }
        }
        namedStep = tr("Replace")
        commit()
        selection = [target]
        buzz(.confirm)
        return true
    }

    /// The one plain photo, clip or moving picture selected, which a
    /// picture tile's "Replace … with this" replaces for VoiceOver.
    var replaceablePhoto: Element? {
        guard let el = singleSelection, !isPageLocked, el.type == .image, !el.locked, let src = el.src, !src.isEmpty,
              !CodeGenerator.isCode(src), !PhotoFrames.isFrameLike(el, among: page.elements) else { return nil }
        return el
    }
}
