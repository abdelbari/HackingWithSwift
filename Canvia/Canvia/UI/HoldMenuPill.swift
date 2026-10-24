// The menu a still hold on the empty page brings up, at the finger: Paste —
// put down where you pressed — Paste page, Select all, Unlock all and Show
// hidden with how many, Add text here,
// Background and Animate (HoldMenu). A pill like the quick actions at the selection,
// placed as they are placed (Geometry.bubbleAnchor). A tap anywhere else on
// the canvas puts it away, as does the view moving; VoiceOver has the same
// items as actions on the page (CanvasView). Held where two or more things
// lie, Select behind opens a list of them beside the pill — a small picture
// of each and its Layers name, the top-most marked — and a row tapped
// selects what it stands for.
//
// In a view of its own, over the canvas, as SelectionBubble is, so that
// only it redraws as the canvas scrolls.

import SwiftUI
import UIKit

struct HoldMenuPill: View {
    @Bindable var store: DesignStore
    /// Opens the page background panel.
    var openBackground: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Select behind's list is open.
    @State private var listingBehind = false

    /// The pill's height, and one item's width, in points: six items fit
    /// across the narrowest phone.
    private static let height = 52.0
    private static let slot = 60.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let at = store.holdMenuAt, let place = anchor(at, in: proxy.size) {
                    pill(at, room: Double(proxy.size.width) - 28)
                        .position(place.point)
                        .transition(.opacity)
                    if listingBehind {
                        behindList(at, place: place, in: proxy.size)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: store.holdMenuAt)
        .onChange(of: store.holdMenuAt) { listingBehind = false }
    }

    /// What one of the menu's items does, pressed at `point` on the page —
    /// from the pill, or from VoiceOver's actions on the page. The menu goes
    /// either way.
    static func choose(_ item: HoldMenu.HoldItem, at point: CGPoint, store: DesignStore,
                       openBackground: () -> Void) {
        store.holdMenuAt = nil
        switch item {
        case .paste: store.paste(at: point)
        case .pastePlain: store.paste(at: point, plain: true)
        case .pastePage: store.pastePage()
        case .selectAll: store.selectAll()
        case .unlockAll: store.unlockAll(onPage: store.pageIndex)
        case .showHidden: store.showAllHidden(onPage: store.pageIndex)
        case .addText: store.addText(at: point)
        case .background: openBackground()
        case .animate: store.asksPageAnimation = true
        // Its list is the pill's own (listingBehind).
        case .selectBehind: break
        }
    }

    private var items: [HoldMenu.HoldItem] {
        let behind = store.holdMenuAt.map { store.hitStack(at: $0).count } ?? 0
        return HoldMenu.items(canPaste: store.canPasteAtFinger, canPastePlain: UIPasteboard.general.hasStrings,
                              canPastePage: store.hasPageOnClipboard, locked: store.lockedCount(onPage: store.pageIndex),
                              hidden: store.hiddenCount(onPage: store.pageIndex), pageLocked: store.isPageLocked,
                              behind: behind)
    }

    /// An item's words on the pill: Paste page's as the clipboard has it,
    /// and Unlock all and Show hidden with how many.
    private func title(_ item: HoldMenu.HoldItem) -> String {
        switch item {
        case .pastePage: return store.pastePageTitle
        case .unlockAll: return HoldMenu.unlockAllTitle(store.lockedCount(onPage: store.pageIndex))
        case .showHidden: return HoldMenu.showHiddenTitle(store.hiddenCount(onPage: store.pageIndex))
        default: return item.title
        }
    }

    /// The pill's middle on screen, and whether it stands above the point
    /// pressed — or nil when the point is out of sight.
    private func anchor(_ at: CGPoint, in size: CGSize) -> (point: CGPoint, above: Bool)? {
        guard size.width > 0, store.viewport.width > 0 else { return nil }
        let screen = Geometry.screenRect(CGRect(origin: at, size: .zero), visible: store.viewport, zoom: store.zoom)
        let canvas = CGRect(origin: .zero, size: size)
        guard canvas.contains(screen.origin) else { return nil }
        let place = Geometry.bubbleAnchor(screen, viewport: canvas, handleOutset: 8)
        let width = Self.slot * Double(items.count) + 12
        let half = CGFloat(width / 2 + 8)
        let x = size.width > half * 2 ? min(max(place.point.x, half), size.width - half) : size.width / 2
        let rise = CGFloat(Self.height / 2)
        let y = place.side == .above ? place.point.y - rise : place.point.y + rise
        return (CGPoint(x: x, y: y), place.side == .above)
    }

    /// Select behind's list, hung from the pill's far side from the point
    /// pressed — above a pill above it, below one below — and kept across
    /// on the canvas.
    private func behindList(_ at: CGPoint, place: (point: CGPoint, above: Bool), in size: CGSize) -> some View {
        let width = min(280, max(Double(size.width) - 32, 120))
        let reach = Self.height / 2 + 6
        let half = width / 2 + 16
        let x = Double(size.width) > half * 2 ? min(max(Double(place.point.x), half), Double(size.width) - half)
            : Double(size.width) / 2
        let edge = place.above ? Double(size.height) - Double(place.point.y) + reach : Double(place.point.y) + reach
        return behindRows(at)
            .frame(width: CGFloat(width))
            .offset(x: CGFloat(x - Double(size.width) / 2))
            .padding(place.above ? .bottom : .top, CGFloat(edge))
            .frame(width: size.width, height: size.height, alignment: place.above ? .bottom : .top)
    }

    private func pill(_ at: CGPoint, room: Double) -> some View {
        // Wider than the screen with every item, it scrolls across.
        let width = Self.slot * Double(items.count)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    button(item, at: at)
                }
            }
        }
        .frame(width: CGFloat(min(width, max(room, Self.slot))))
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page menu")
    }

    private func button(_ item: HoldMenu.HoldItem, at point: CGPoint) -> some View {
        Button {
            // Select behind opens its list, and the menu stays.
            if item == .selectBehind { return listingBehind.toggle() }
            Self.choose(item, at: point, store: store, openBackground: openBackground)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.callout.weight(.medium))
                Text(title(item))
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.primary)
            .frame(width: Self.slot, height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: select behind

extension HoldMenuPill {

    /// Select behind's list: what lies under the point pressed, top-most
    /// first, at most Layers.behindRows of it.
    fileprivate func behindRows(_ at: CGPoint) -> some View {
        let rows = Array(store.hitStack(at: at).prefix(Layers.behindRows))
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { n, row in
                behindRow(row, top: n == 0)
            }
        }
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Select behind"))
    }

    /// One row: its picture, its Layers name, On top for the top-most, and
    /// a padlock or a struck eye for what is locked or hidden.
    private func behindRow(_ row: LayerRows.Row, top: Bool) -> some View {
        let lock = Self.sharedLock(row.elements)
        let hidden = row.elements.allSatisfy(\.isHidden)
        let chosen = row.elements.allSatisfy { store.selection.contains($0.id) }
        return Button { store.selectStackRow(row) } label: {
            HStack(spacing: 10) {
                StackThumb(elements: row.elements, page: store.pageSize)
                Text(Layers.rowName(row)).lineLimit(1)
                Spacer(minLength: 4)
                if top {
                    Text("On top").font(.caption).foregroundStyle(.secondary)
                }
                behindMarks(lock: lock, hidden: hidden)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    @ViewBuilder
    private func behindMarks(lock: ElementLock.Mode, hidden: Bool) -> some View {
        if lock != .unlocked {
            Image(systemName: ElementLock.symbol(lock))
                .foregroundStyle(.secondary)
                .accessibilityLabel(lock == .position ? tr("Position locked") : tr("Locked"))
        }
        if hidden {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
                .accessibilityLabel(tr("Hidden"))
        }
    }

    /// A row's lock: its members' one lock when they share it, else none.
    private static func sharedLock(_ members: [Element]) -> ElementLock.Mode {
        let modes = Set(members.map { ElementLock.mode(of: $0) })
        return modes.count == 1 ? modes.first ?? .unlocked : .unlocked
    }
}

/// What a Select behind row stands for, drawn small: the elements as the
/// page draws them, cut to the box round them and fitted in 32 points.
private struct StackThumb: View {
    let elements: [Element]
    let page: CGSize
    private static let side = 32.0

    var body: some View {
        let box = Geometry.union(elements.map(Geometry.aabb))
        let w = Double(box.width), h = Double(box.height)
        let scale = w > 0 && h > 0 ? min(Self.side / w, Self.side / h) : 1
        return ZStack(alignment: .topLeading) {
            // Back to front, as the page draws them.
            ForEach(Array(elements.reversed())) { el in
                ElementView(element: el)
            }
        }
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .offset(x: -box.minX, y: -box.minY)
        .scaleEffect(CGFloat(scale), anchor: .topLeading)
        .frame(width: CGFloat(w * scale), height: CGFloat(h * scale), alignment: .topLeading)
        .frame(width: CGFloat(Self.side), height: CGFloat(Self.side))
        .clipped()
        .designDirection()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
