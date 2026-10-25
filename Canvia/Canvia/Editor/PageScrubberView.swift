// The page scrubber (PageScrubber): a slim thumb on the column's trailing
// edge — the leading one when the screen reads right to left — shown for a
// moment after any scroll. Dragged, the view follows it down the column at
// once, a bubble beside it naming the page under it and a tick felt as each
// page passes; let go, the view settles on that page's top. VoiceOver has
// it as an adjustable "Page, 37 of 60", a page a swipe.
//
// A view of its own over the canvas, as the hold menu is, so only it
// redraws as the view scrolls.

import SwiftUI

struct PageScrubberView: View {
    @Bindable var store: DesignStore
    let seen: CanvasView.ColumnSeen
    let slots: [PageColumn.Slot]
    /// The column's height, in column units.
    let column: Double
    @Binding var scrubbing: Bool
    /// The view's top asked for, down the column, as the thumb is dragged.
    var onScrub: (Double) -> Void
    /// Let go over this page.
    var onRelease: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shown, after a scroll or while held.
    @State private var shown = false
    /// The thumb's top where the drag took it, and where it is now.
    @State private var grabStart: Double?
    @State private var grabbedAt: Double?
    /// The page the bubble last named, for the tick as each one passes.
    @State private var passing: Int?
    @State private var hiding: Task<Void, Never>?

    /// The thumb's width on screen; it is taken across minThumb.
    private static let width = 6.0
    private static let inset = 8.0

    var body: some View {
        GeometryReader { proxy in
            let track = max(Double(proxy.size.height) - 2 * Self.inset, 0)
            let length = PageScrubber.thumbLength(visible: seen.height, column: column, track: track)
            let top = grabbedAt ?? PageScrubber.thumbTop(top: seen.top, visible: seen.height,
                                                         column: column, track: track)
            HStack(alignment: .top, spacing: 6) {
                Spacer(minLength: 0)
                if scrubbing { bubble.padding(.top, CGFloat(max(top + length / 2 - 14, 0))) }
                thumb(track: track, length: length, top: top)
            }
            .padding(.vertical, CGFloat(Self.inset))
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .opacity(shown || scrubbing ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: shown)
        .onChange(of: seen.top) { show() }
        .onDisappear { hiding?.cancel() }
    }

    /// The page under the thumb: the one across the middle of the view.
    private var page: Int {
        PageColumn.currentPage(CGRect(x: 0, y: seen.top, width: 1, height: seen.height), in: slots)
    }

    private var bubble: some View {
        let index = page
        let title = store.design.pages.indices.contains(index) ? store.design.pages[index].title : nil
        return Text(PageScrubber.bubble(index, title: title))
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline))
            .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func thumb(track: Double, length: Double, top: Double) -> some View {
        Capsule()
            .fill(scrubbing ? Theme.accent : Color.secondary.opacity(0.7))
            .frame(width: CGFloat(Self.width), height: CGFloat(length))
            .frame(width: CGFloat(PageScrubber.minThumb), height: CGFloat(length))
            .contentShape(Rectangle())
            .padding(.top, CGFloat(top))
            .gesture(drag(track: track, top: top))
            .allowsHitTesting(shown || scrubbing)
            .accessibilityElement()
            .accessibilityLabel(Text("Page"))
            .accessibilityValue(PageScrubber.spoken(page, count: slots.count))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(1)
                case .decrement: step(-1)
                @unknown default: break
                }
            }
    }

    /// The thumb dragged down the track: the view's top the same share
    /// down the column, a tick as each page passes.
    private func drag(track: Double, top: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if grabStart == nil {
                    grabStart = top
                    scrubbing = true
                    passing = page
                    hiding?.cancel()
                }
                let start = grabStart ?? top
                let length = PageScrubber.thumbLength(visible: seen.height, column: column, track: track)
                let moved = min(max(start + Double(value.translation.height), 0), max(track - length, 0))
                grabbedAt = moved
                onScrub(PageScrubber.columnTop(thumbTop: moved, visible: seen.height, column: column, track: track))
                let now = page
                if now != passing {
                    passing = now
                    store.buzz(.tick)
                }
            }
            .onEnded { _ in
                grabStart = nil
                grabbedAt = nil
                passing = nil
                scrubbing = false
                onRelease(page)
                show()
            }
    }

    /// VoiceOver's swipe up or down: the next page or the one before, its
    /// top brought into view.
    private func step(_ by: Int) {
        onRelease(PageScrubber.stepped(store.pageIndex, by: by, count: slots.count))
    }

    /// Shown now, and gone shownSeconds after the view stops moving.
    private func show() {
        if !shown { shown = true }
        hiding?.cancel()
        hiding = Task { @MainActor in
            try? await Task.sleep(for: .seconds(PageScrubber.shownSeconds))
            guard !Task.isCancelled, !scrubbing else { return }
            shown = false
        }
    }
}
