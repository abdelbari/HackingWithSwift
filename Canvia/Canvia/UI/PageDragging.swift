// Pages dragged into a new order, in the organiser's grid and along the
// pages bar: a press and hold lifts a page — in the organiser, every ticked
// page when it is one of them — the gap they would go into is marked as the
// finger moves, the view scrolls on at its ends, and letting go moves them
// as one undo step (PageOrder.moved). VoiceOver has Move page earlier,
// later, to start and to end instead.
//
// The press and the taps are the whole grid's or strip's, finding the
// thumbnail under the finger from where each was last laid out, not each
// thumbnail's own: a lazy grid lets go of a thumbnail scrolled far enough
// away, and a drag held by it would end with it.

import SwiftUI

/// The pages lifted, the gap they would go into and where the finger is, in
/// the scrolling view's own space; nothing lifted while nothing is dragged.
struct PageLift: Equatable {
    var ids: Set<String> = []
    var gap: Int?
    var finger: CGPoint?

    var isActive: Bool { !ids.isEmpty }
}

/// Where each thumbnail is in the scrolling view's own space, by page id,
/// and how big that view is: written as they move, read by a drag. A plain
/// class, so scrolling redraws nothing.
final class PageFrames {
    var rects: [String: CGRect] = [:]
    var viewport: CGSize = .zero

    /// The frames known, by the page's index in `pages`.
    func indexed(_ pages: [Page]) -> [Int: CGRect] {
        var out: [Int: CGRect] = [:]
        for (i, page) in pages.enumerated() {
            if let rect = rects[page.id] { out[i] = rect }
        }
        return out
    }

    /// The index of the page whose thumbnail is at `point`; nil between
    /// them.
    func page(at point: CGPoint, in pages: [Page]) -> Int? {
        pages.indices.first { rects[pages[$0].id]?.contains(point) == true }
    }

    /// The indices of the pages at least partly in view, along the view's
    /// length — down it when `vertical`, else across.
    func shown(_ pages: [Page], vertical: Bool) -> [Int] {
        let length = vertical ? viewport.height : viewport.width
        return indexed(pages).filter { _, r in
            vertical ? (r.maxY > 0 && r.minY < length) : (r.maxX > 0 && r.minX < length)
        }.map(\.key).sorted()
    }
}

/// Scrolls a strip or a grid on while a dragged page is held at one of its
/// ends: a step at a time, `step` called with the way to go until it says
/// there is no further to go, or the finger moves away.
final class PageEdgeScroll {
    private var task: Task<Void, Never>?
    private var direction = 0

    /// The finger is `direction` — -1 the start, 1 the end, 0 neither.
    func hold(_ direction: Int, step: @escaping (Int) -> Bool) {
        guard direction != self.direction else { return }
        stop()
        self.direction = direction
        guard direction != 0 else { return }
        task = Task { @MainActor in
            while !Task.isCancelled, step(direction) {
                try? await Task.sleep(for: .milliseconds(260))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        direction = 0
    }
}

/// The accent bar in the gap the lifted pages would go into: before the
/// thumbnail of page `gap`, or after the last.
struct PageGapMarker: View {
    let lift: PageLift
    let pages: [Page]
    let frames: PageFrames
    /// The room between two thumbnails, which the bar stands in the middle of.
    let spacing: Double

    var body: some View {
        if lift.isActive, let gap = lift.gap, let mark = mark(gap) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: 4, height: mark.height)
                .position(x: mark.midX, y: mark.midY)
                .allowsHitTesting(false)
        }
    }

    private func mark(_ gap: Int) -> CGRect? {
        if pages.indices.contains(gap), let r = frames.rects[pages[gap].id] {
            return CGRect(x: r.minX - spacing / 2 - 2, y: r.minY, width: 4, height: r.height)
        }
        if pages.indices.contains(gap - 1), let r = frames.rects[pages[gap - 1].id] {
            return CGRect(x: r.maxX + spacing / 2 - 2, y: r.minY, width: 4, height: r.height)
        }
        return nil
    }
}

extension View {
    /// This thumbnail's frame in the named `space`, kept in `frames` under
    /// page `id` while it is laid out.
    func reportsPageFrame(_ id: String, in space: String, to frames: PageFrames) -> some View {
        background(GeometryReader { g in
            Color.clear
                .onAppear { frames.rects[id] = g.frame(in: .named(space)) }
                .onChange(of: g.frame(in: .named(space))) { _, rect in frames.rects[id] = rect }
                .onDisappear { frames.rects[id] = nil }
        })
    }

    /// The scrolling view's size kept in `frames`, for its ends.
    func reportsViewport(to frames: PageFrames) -> some View {
        background(GeometryReader { g in
            Color.clear
                .onAppear { frames.viewport = g.size }
                .onChange(of: g.size) { _, size in frames.viewport = size }
        })
    }

    /// VoiceOver's Move page earlier, Move page later, Move to start and
    /// Move to end for page `index`, each one undo step; those that would
    /// not move it are left out.
    func pageMoveActions(_ store: DesignStore, index: Int, id: String) -> some View {
        accessibilityActions {
            ForEach(PageOrder.Step.allCases, id: \.self) { step in
                if let gap = PageOrder.gap(step, from: index, count: store.design.pages.count) {
                    Button(tr(step.rawValue)) { store.movePages([id], to: gap) }
                }
            }
        }
    }
}
