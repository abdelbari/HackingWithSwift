// The menu a still hold on the empty page brings up, at the finger: Paste —
// put down where you pressed — Paste page, Select all, Add text here,
// Background and Animate (HoldMenu). A pill like the quick actions at the selection,
// placed as they are placed (Geometry.bubbleAnchor). A tap anywhere else on
// the canvas puts it away, as does the view moving; VoiceOver has the same
// items as actions on the page (CanvasView).
//
// In a view of its own, over the canvas, as SelectionBubble is, so that
// only it redraws as the canvas scrolls.

import SwiftUI

struct HoldMenuPill: View {
    @Bindable var store: DesignStore
    /// Opens the page background panel.
    var openBackground: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The pill's height, and one item's width, in points: six items fit
    /// across the narrowest phone.
    private static let height = 52.0
    private static let slot = 60.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let at = store.holdMenuAt, let place = anchor(at, in: proxy.size) {
                    pill(at)
                        .position(place)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: store.holdMenuAt)
    }

    /// What one of the menu's items does, pressed at `point` on the page —
    /// from the pill, or from VoiceOver's actions on the page. The menu goes
    /// either way.
    static func choose(_ item: HoldMenu.HoldItem, at point: CGPoint, store: DesignStore,
                       openBackground: () -> Void) {
        store.holdMenuAt = nil
        switch item {
        case .paste: store.paste(at: point)
        case .pastePage: store.pastePage()
        case .selectAll: store.selectAll()
        case .addText: store.addText(at: point)
        case .background: openBackground()
        case .animate: store.asksPageAnimation = true
        }
    }

    private var items: [HoldMenu.HoldItem] {
        HoldMenu.items(canPaste: store.canPasteAtFinger, canPastePage: store.hasPageOnClipboard)
    }

    /// The pill's middle on screen, or nil when the point pressed is out of
    /// sight.
    private func anchor(_ at: CGPoint, in size: CGSize) -> CGPoint? {
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
        return CGPoint(x: x, y: y)
    }

    private func pill(_ at: CGPoint) -> some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                button(item, at: at)
            }
        }
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
            Self.choose(item, at: point, store: store, openBackground: openBackground)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.callout.weight(.medium))
                Text(item == .pastePage ? store.pastePageTitle : item.title)
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
