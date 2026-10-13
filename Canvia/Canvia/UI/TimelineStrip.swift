// The editor's timeline: a strip above the pages, off unless turned on in
// More, under a "Timeline" header that folds it away. Each shown page is a
// block as wide as it holds, whose right edge drags its hold longer or
// shorter; a playhead scrubs the film, the canvas showing each moment it
// passes, in silence; under the blocks, when each selected element shows,
// and the design's audio tracks as thin bars. As the Android twin's
// timeline.

import SwiftUI

struct TimelineStrip: View {
    @Bindable var store: DesignStore
    /// The edge being dragged: its page, its hold and the scale when the
    /// drag began, which the blocks keep until it ends so the edge stays
    /// under the finger.
    @State private var drag: HoldDrag?
    @State private var scrubbing = false
    /// Unfolded, or folded down to its header.
    @State private var open = true
    /// Each track's music length, by AudioStore id, once read.
    @State private var trackLengths: [String: Double] = [:]

    /// The per-phone switch in More, off unless turned on.
    static let key = "timeline"
    /// Points a second at the least: a long film scrolls rather than
    /// shrinking its blocks past use.
    static let minScale = 12.0
    static let rulerHeight: CGFloat = 16
    static let blockHeight: CGFloat = 34
    static let barHeight: CGFloat = 4
    /// The most bars of each kind drawn under the blocks.
    static let maxBars = 4

    private struct HoldDrag: Equatable {
        var id: String
        var from: Double
        var scale: Double
    }

    /// A thin bar under the blocks: when an element shows, or a track plays.
    private struct Bar: Identifiable {
        var id: String
        var x: Double
        var width: Double
        var color: Color
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if open {
                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: false) {
                        lanes(scale: scale(width: geo.size.width - 24))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                }
                .frame(height: height)
            }
        }
        .background(Theme.chrome)
        .overlay(alignment: .top) { Divider() }
        .task(id: trackSources) { await readTrackLengths() }
    }

    // MARK: header

    /// The fold, the title, where the playhead is in the film and how long
    /// it runs, and Split page — as the Android twin's header.
    private var header: some View {
        HStack(spacing: 8) {
            Button { open.toggle() } label: {
                Image(systemName: open ? "chevron.down" : "chevron.up")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(open ? "Fold the timeline" : "Unfold the timeline")
            Text("Timeline")
                .font(.subheadline.weight(.semibold))
            Text(clockLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Split page") { store.splitPage() }
                .font(.subheadline)
                .disabled(!store.canSplitPage)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
    }

    /// "0:03.5 / 0:12.0": the playhead in the film, m:ss.s, and the film's
    /// length; on a hidden page, which has no playhead, that it is hidden.
    private var clockLabel: String {
        guard let at = shownPlayhead else { return "This page is hidden" }
        let total = store.timelinePages.reduce(0.0) { $0 + $1.hold }
        return VideoStore.timeLabel(at) + " / " + VideoStore.timeLabel(total)
    }

    // MARK: layout

    /// Points a second: the film fitted to `width`, at least `minScale` —
    /// held where it was while an edge is dragged.
    private func scale(width: Double) -> Double {
        if let drag { return drag.scale }
        let total = store.timelinePages.reduce(0.0) { $0 + $1.hold }
        return max(width / max(total, 0.1), Self.minScale)
    }

    private var height: CGFloat {
        let bars = min(selectedOnTimeline.count, Self.maxBars) + min(store.design.audioTracks.count, Self.maxBars)
        return 12 + Self.rulerHeight + 3 + Self.blockHeight + CGFloat(bars) * (Self.barHeight + 3)
    }

    private func lanes(scale: Double) -> some View {
        let pages = store.timelinePages
        let blocks = Timeline.blocks(holds: pages.map { $0.hold }, scale: scale)
        let width = blocks.last.map { $0.x + $0.width } ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            ruler(width: width, scale: scale)
            ZStack(alignment: .topLeading) {
                ForEach(0..<pages.count, id: \.self) { pos in
                    block(index: pages[pos].index, hold: pages[pos].hold, frame: blocks[pos], scale: scale)
                }
            }
            .frame(width: max(width, 1), height: Self.blockHeight, alignment: .topLeading)
            ForEach(elementBars(blocks: blocks, pages: pages, scale: scale)) { barView($0) }
            ForEach(trackBars(film: width / scale, scale: scale)) { barView($0) }
        }
        .frame(width: max(width, 1), alignment: .leading)
        .overlay(alignment: .topLeading) { playheadLine(width: width, scale: scale) }
    }

    // MARK: the playhead

    /// Second ticks — every fifth when they would crowd — over a strip that
    /// scrubs the film where it is touched and dragged.
    private func ruler(width: Double, scale: Double) -> some View {
        Canvas { context, size in
            let step = scale >= 24 ? 1.0 : 5.0
            var s = 0.0
            while s * scale <= Double(size.width) + 0.5 {
                var tick = Path()
                tick.move(to: CGPoint(x: s * scale, y: Double(size.height) * 0.45))
                tick.addLine(to: CGPoint(x: s * scale, y: Double(size.height)))
                context.stroke(tick, with: .color(Color.secondary.opacity(0.6)), lineWidth: 1)
                s += step
            }
        }
        .frame(width: max(width, 1), height: Self.rulerHeight)
        .contentShape(Rectangle())
        .gesture(scrubGesture(scale: scale))
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityValue(String(format: "%.1f seconds", store.filmPlayhead ?? 0))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.5 : -0.5
            store.scrub(to: (store.filmPlayhead ?? 0) + step)
            store.endScrub()
        }
    }

    private func scrubGesture(scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !scrubbing {
                    scrubbing = true
                    store.beginScrub()
                }
                store.scrub(to: value.location.x / scale)
            }
            .onEnded { _ in
                scrubbing = false
                store.endScrub()
            }
    }

    /// Where the playhead is drawn, in the film: where it stands, or while
    /// the page plays, where the play has got to; nowhere on a hidden page.
    private var shownPlayhead: Double? {
        guard let start = store.timelinePageStart else { return nil }
        if !scrubbing, let t = store.previewTime { return start + t }
        return store.filmPlayhead
    }

    @ViewBuilder
    private func playheadLine(width: Double, scale: Double) -> some View {
        if let at = shownPlayhead {
            Rectangle()
                .fill(Theme.guide)
                .frame(width: 2)
                .overlay(alignment: .top) {
                    Circle().fill(Theme.guide).frame(width: 10, height: 10)
                }
                .offset(x: min(max(at * scale, 0), width) - 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: blocks

    private func block(index: Int, hold: Double, frame: Timeline.Block, scale: Double) -> some View {
        blockFace(index: index, hold: hold, scale: scale)
            .frame(width: max(frame.width - 2, 4), height: Self.blockHeight)
            .contentShape(Rectangle())
            .onTapGesture { store.selectTimelinePage(index) }
            .offset(x: frame.x + 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spokenBlock(number: index + 1, hold: hold, current: index == store.pageIndex))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { store.selectTimelinePage(index) }
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.5 : -0.5
                store.setHold(of: store.design.pages[index].id, to: Timeline.draggedHold(hold, by: step, scale: 1))
            }
    }

    /// The block as drawn: its page's number and hold, the page on screen
    /// in the accent, and the edge to drag.
    private func blockFace(index: Int, hold: Double, scale: Double) -> some View {
        let current = index == store.pageIndex
        let shape = RoundedRectangle(cornerRadius: 6)
        return shape
            .fill(current ? Theme.accentSubtle : Color(.systemGray5))
            .overlay(alignment: .leading) {
                Text("\(index + 1)  " + Self.holdLabel(hold))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .padding(.leading, 6)
            }
            .clipShape(shape)
            .overlay(shape.stroke(current ? Theme.accent : Color(.systemGray3), lineWidth: current ? 2 : 1))
            .overlay(alignment: .trailing) { edgeHandle(index: index, hold: hold, scale: scale) }
    }

    private func edgeHandle(index: Int, hold: Double, scale: Double) -> some View {
        Capsule()
            .fill(index == store.pageIndex ? Theme.accent : Color(.systemGray2))
            .frame(width: 4, height: 18)
            .frame(width: 16, height: Self.blockHeight)
            .contentShape(Rectangle())
            .gesture(holdGesture(id: store.design.pages[index].id, hold: hold, scale: scale))
    }

    /// The edge dragged: the hold follows it to the tenth, within the half
    /// second to the minute, and the drag is one Undo once it ends.
    private func holdGesture(id: String, hold: Double, scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if drag?.id != id { drag = HoldDrag(id: id, from: hold, scale: scale) }
                guard let current = drag else { return }
                let seconds = Timeline.draggedHold(current.from, by: value.translation.width, scale: current.scale)
                store.dragHold(of: id, to: seconds)
            }
            .onEnded { _ in
                drag = nil
                store.commit()
            }
    }

    /// A hold as a block shows it: "2.5s".
    static func holdLabel(_ hold: Double) -> String {
        String(format: "%.1fs", hold)
    }

    /// What VoiceOver says for a block: which page, how long it holds, and
    /// whether it is the one on screen.
    static func spokenBlock(number: Int, hold: Double, current: Bool) -> String {
        "Page \(number), " + String(format: "%.1f seconds", hold) + (current ? ", current" : "")
    }

    // MARK: bars

    /// The selected elements, when the page on screen is on the timeline.
    private var selectedOnTimeline: [Element] {
        store.timelinePageStart == nil ? [] : store.selectedElements
    }

    /// When each selected element shows, under its page's block: its timing,
    /// or the whole page.
    private func elementBars(blocks: [Timeline.Block], pages: [(index: Int, hold: Double)],
                             scale: Double) -> [Bar] {
        guard let pos = pages.firstIndex(where: { $0.index == store.pageIndex }), pos < blocks.count else { return [] }
        let hold = pages[pos].hold, x0 = blocks[pos].x
        return selectedOnTimeline.prefix(Self.maxBars).map { el -> Bar in
            let start = min(el.timing?.start ?? 0, hold)
            let end = min(el.timing?.end ?? hold, hold)
            return Bar(id: el.id, x: x0 + start * scale, width: max(end - start, 0) * scale, color: Theme.accent)
        }
    }

    /// Where each of the design's tracks plays in the film, once its
    /// music's length is read; none for one not heard.
    private func trackBars(film: Double, scale: Double) -> [Bar] {
        store.design.audioTracks.prefix(Self.maxBars).compactMap { track -> Bar? in
            let length = track.audioId.flatMap { trackLengths[$0] }
            guard let span = AudioMix.span(of: track, duration: length, film: film) else { return nil }
            return Bar(id: track.id, x: span.at * scale, width: (span.until - span.at) * scale, color: Theme.userGuide)
        }
    }

    private func barView(_ bar: Bar) -> some View {
        Capsule()
            .fill(bar.color)
            .frame(width: max(bar.width, 2), height: Self.barHeight)
            .offset(x: bar.x)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    // MARK: track lengths

    private var trackSources: [String] {
        store.design.audioTracks.compactMap(\.audioId)
    }

    @MainActor
    private func readTrackLengths() async {
        for id in trackSources where trackLengths[id] == nil {
            if let seconds = await AudioStore.duration(of: id) { trackLengths[id] = seconds }
        }
    }
}
