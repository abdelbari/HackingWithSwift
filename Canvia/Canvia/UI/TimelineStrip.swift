// The editor's timeline: a strip above the pages, off unless turned on in
// More, under a "Timeline" header that folds it away. Each shown page is a
// block as wide as it holds, whose right edge drags its hold longer or
// shorter; a playhead scrubs the film, the canvas showing each moment it
// passes, in silence; under the blocks, when each selected element shows,
// and the design's audio tracks as lanes, a song's beats ticked across its
// lane where they fall in the film. While a track has Beat Sync on, a
// dragged edge snaps to a beat within Beats.snapped's reach. As the Android
// twin's timeline.
//
// The lanes answer the hand: a track's lane dragged moves it along the film
// (Timeline.movedTrack), its ends pulled trim it (trimmedTrack), each drag
// one Undo — "Move audio", "Trim audio"; tapped, it is chosen, with Edit,
// Split at the playhead, Duplicate and Delete over the strip. An element's
// bar is dragged and trimmed the same way (movedTiming, trimmedTiming).
// Lanes are 28 points tall, touched 44 points tall. A pinch zooms the strip
// from the film fitted to its width up to Timeline.maxScale points a second,
// the playhead held where it is on screen.

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
    /// Each song's beats, in seconds into its file, by AudioStore id, once
    /// read (AudioStore.beats).
    @State private var trackBeats: [String: [Double]] = [:]
    /// The scale a pinch left, in points a second; nil is the film fitted.
    @State private var zoom: Double?
    /// The scale when a pinch began, and where the playhead was across the
    /// strip then, 0 its left edge and 1 its right.
    @State private var pinchFrom: Double?
    @State private var pinchAnchor: Double = 0.5
    /// Where the playhead is across the strip's width, in points, as last
    /// laid out.
    @State private var playheadX: Double = 0
    @State private var stripWidth: Double = 1
    /// A lane being dragged: what it was when the finger came down, and the
    /// scale then.
    @State private var laneDrag: LaneDrag?
    /// The track lane tapped, whose actions show over the strip.
    @State private var chosenTrack: String?
    /// The track whose Edit is open.
    @State private var editing: TrackRef?

    /// The per-phone switch in More, off unless turned on.
    static let key = "timeline"
    /// Points a second at the least: a long film scrolls rather than
    /// shrinking its blocks past use.
    static let minScale = 12.0
    static let rulerHeight: CGFloat = 16
    static let blockHeight: CGFloat = 34
    /// A lane's height, and how much taller a finger finds it.
    static let laneHeight: CGFloat = 28
    static let laneReach: CGFloat = 8
    /// The most bars of each kind drawn under the blocks.
    static let maxBars = 4

    private struct HoldDrag: Equatable {
        var id: String
        var from: Double
        var scale: Double
    }

    /// A track lane's or an element bar's drag: which, what was pulled, as
    /// it stood when the finger came down, and the scale then.
    private struct LaneDrag {
        var id: String
        var edge: Timeline.Edge?
        var track: AudioTrack?
        var timing: ElementTiming?
        var scale: Double
    }

    private struct TrackRef: Identifiable {
        var id: String
    }

    /// A lane under the blocks: when an element shows, or a track plays.
    private struct Lane: Identifiable {
        var id: String
        var x: Double
        var width: Double
        var color: Color
        var title: String
        /// What VoiceOver says of it: "Song, 0:03 to 0:18".
        var spoken: String
        /// Where a song's beats fall, in points from the film's start.
        var ticks: [Double] = []
        /// A track's lane, its file's length known; else an element's bar.
        var track: AudioTrack?
        var length: Double?
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if open, let id = chosenTrack, let track = store.design.audioTracks.first(where: { $0.id == id }) {
                laneActions(track)
            }
            if open {
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            lanes(scale: scale(width: geo.size.width - 24))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .simultaneousGesture(pinchGesture(width: geo.size.width - 24, proxy: proxy))
                    }
                    .onAppear { stripWidth = max(geo.size.width, 1) }
                    .onChange(of: geo.size.width) { _, width in stripWidth = max(width, 1) }
                }
                .coordinateSpace(name: Self.space)
                .frame(height: height)
                // The film runs left to right in any language, as the
                // design's pages do; the header reads as the language does.
                .designDirection()
            }
        }
        .background(Theme.chrome)
        .overlay(alignment: .top) { Divider() }
        .task(id: trackSources) { await readTrackLengths() }
        .sheet(item: $editing) { ref in
            NavigationStack { AudioTrackView(store: store, trackId: ref.id) }
                .presentationDetents([.medium, .large])
        }
    }

    /// The strip's own space, where the playhead's place is read.
    private static let space = "timelineStrip"

    // MARK: header

    /// The fold, the title, where the playhead is in the film and how long
    /// it runs, and Split page — as the Android twin's header.
    private var header: some View {
        HStack(spacing: 8) {
            Button { open.toggle() } label: {
                Image(systemName: open ? "chevron.down" : "chevron.up")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(open ? tr("Fold the timeline") : tr("Unfold the timeline"))
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
        guard let at = shownPlayhead else { return tr("This page is hidden") }
        let total = store.timelinePages.reduce(0.0) { $0 + $1.hold }
        return VideoStore.timeLabel(at) + " / " + VideoStore.timeLabel(total)
    }

    // MARK: layout

    /// Points a second: the film fitted to `width`, at least `minScale`, or
    /// as a pinch left it, no wider than Timeline.maxScale — held where it
    /// was while an edge or a lane is dragged.
    private func scale(width: Double) -> Double {
        if let drag { return drag.scale }
        if let laneDrag { return laneDrag.scale }
        let fit = fitScale(width: width)
        guard let zoom else { return fit }
        return min(max(zoom, fit), max(fit, Timeline.maxScale))
    }

    /// The film fitted to `width`, at least `minScale`.
    private func fitScale(width: Double) -> Double {
        let total = store.timelinePages.reduce(0.0) { $0 + $1.hold }
        return max(width / max(total, 0.1), Self.minScale)
    }

    private var height: CGFloat {
        let bars = min(selectedOnTimeline.count, Self.maxBars) + min(store.design.audioTracks.count, Self.maxBars)
        return 12 + Self.rulerHeight + 3 + Self.blockHeight + CGFloat(bars) * (Self.laneHeight + 3)
    }

    /// A pinch zooms the strip, the playhead held where it was across it.
    private func pinchGesture(width: Double, proxy: ScrollViewProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchFrom == nil {
                    pinchFrom = scale(width: width)
                    pinchAnchor = min(max(playheadX / stripWidth, 0), 1)
                }
                guard let from = pinchFrom else { return }
                zoom = Timeline.pinched(from, factor: Double(value.magnification), minScale: fitScale(width: width))
                proxy.scrollTo(Self.playheadMark, anchor: UnitPoint(x: pinchAnchor, y: 0.5))
            }
            .onEnded { _ in pinchFrom = nil }
    }

    private static let playheadMark = "playheadMark"

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
            ForEach(elementBars(blocks: blocks, pages: pages, scale: scale)) { lane in
                elementLane(lane, hold: currentHold(pages), scale: scale)
            }
            ForEach(trackBars(film: width / scale, scale: scale)) { lane in
                trackLane(lane, film: width / scale, scale: scale)
            }
        }
        .frame(width: max(width, 1), alignment: .leading)
        .overlay(alignment: .topLeading) { playheadLine(width: width, scale: scale) }
        .overlay(alignment: .topLeading) { playheadAnchor(scale: scale) }
    }

    /// How long the page on screen holds, on the timeline.
    private func currentHold(_ pages: [(index: Int, hold: Double)]) -> Double {
        pages.first { $0.index == store.pageIndex }?.hold ?? store.pageHold
    }

    /// A point where the playhead stands, for a pinch to keep in place.
    @ViewBuilder
    private func playheadAnchor(scale: Double) -> some View {
        if let at = shownPlayhead {
            Color.clear
                .frame(width: 1, height: 1)
                .id(Self.playheadMark)
                .padding(.leading, max(0, at * scale))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
        .accessibilityValue(tr("%@ seconds", String(format: "%.1f", store.filmPlayhead ?? 0)))
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
                .background {
                    GeometryReader { g in
                        let x = Double(g.frame(in: .named(Self.space)).midX)
                        Color.clear
                            .onAppear { playheadX = x }
                            .onChange(of: x) { _, now in playheadX = now }
                    }
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
                    .font(.caption2.weight(.semibold))
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
                store.dragHold(of: id, to: onBeat(seconds, page: id))
            }
            .onEnded { _ in
                drag = nil
                store.commit()
            }
    }

    /// A page's hold with its end on a beat, while a track has Beat Sync
    /// on and a beat is within reach of it (Beats.snapped); as it is
    /// otherwise. Kept within the holds a page may have.
    private func onBeat(_ hold: Double, page id: String) -> Double {
        guard BeatSync.active(store.design) else { return hold }
        var start = 0.0
        for entry in store.timelinePages {
            if store.design.pages[entry.index].id == id { break }
            start += entry.hold
        }
        let end = Beats.snapped(start + hold, beats: syncedBeats)
        let range = MotionSettings.pageHoldRange
        return min(max(Beats.thousandth(end - start), range.lowerBound), range.upperBound)
    }

    /// The beats of the tracks with Beat Sync on, where they fall in the
    /// film and a hold's worth past its end.
    private var syncedBeats: [Double] {
        let film = store.timelinePages.reduce(0.0) { $0 + $1.hold } + BeatSync.maxHold
        return store.design.audioTracks.filter(\.beatSync).flatMap { track -> [Double] in
            guard let id = track.audioId, let beats = trackBeats[id] else { return [] }
            return Beats.inFilm(beats, track: track, length: trackLengths[id], film: film)
        }
    }

    /// A hold as a block shows it: "2.5s".
    static func holdLabel(_ hold: Double) -> String {
        String(format: "%.1fs", hold)
    }

    /// What VoiceOver says for a block: which page, how long it holds, and
    /// whether it is the one on screen.
    static func spokenBlock(number: Int, hold: Double, current: Bool) -> String {
        tr("Page %d", number) + ", " + tr("%@ seconds", String(format: "%.1f", hold))
            + (current ? ", " + tr("current") : "")
    }

    // MARK: bars

    /// The selected elements, when the page on screen is on the timeline.
    private var selectedOnTimeline: [Element] {
        store.timelinePageStart == nil ? [] : store.selectedElements
    }

    /// When each selected element shows, under its page's block: its timing,
    /// or the whole page.
    private func elementBars(blocks: [Timeline.Block], pages: [(index: Int, hold: Double)],
                             scale: Double) -> [Lane] {
        guard let pos = pages.firstIndex(where: { $0.index == store.pageIndex }), pos < blocks.count else { return [] }
        let hold = pages[pos].hold, x0 = blocks[pos].x
        return selectedOnTimeline.prefix(Self.maxBars).map { el -> Lane in
            let start = min(el.timing?.start ?? 0, hold)
            let end = min(el.timing?.end ?? hold, hold)
            let name = ElementNames.name(of: el)
            return Lane(id: el.id, x: x0 + start * scale, width: max(end - start, 0) * scale, color: Theme.accent,
                        title: name, spoken: AudioTracks.spoken(name, from: start, to: end))
        }
    }

    /// Where each of the design's tracks plays in the film, once its music's
    /// length is read: from its start, once through or, looping, to the
    /// film's end.
    private func trackBars(film: Double, scale: Double) -> [Lane] {
        store.design.audioTracks.prefix(Self.maxBars).compactMap { track -> Lane? in
            guard let length = track.audioId.flatMap({ trackLengths[$0] }), length > 0.01 else { return nil }
            let at = max(track.start, 0)
            let until = track.loop ? max(film, at) : at + AudioTracks.length(of: track, duration: length)
            let beats = track.audioId.flatMap { trackBeats[$0] } ?? []
            let ticks = Beats.inFilm(beats, track: track, length: length, film: until).map { $0 * scale }
            let name = AudioTracks.name(of: track)
            return Lane(id: track.id, x: at * scale, width: (until - at) * scale, color: Theme.userGuide,
                        title: name, spoken: AudioTracks.spoken(name, from: at, to: until), ticks: ticks,
                        track: track, length: length)
        }
    }

    /// A lane as drawn: its name over its colour, a grip at each end, and
    /// the one chosen ringed.
    private func laneFace(_ lane: Lane, chosen: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return shape
            .fill(lane.color.opacity(0.35))
            .overlay(alignment: .leading) {
                Text(lane.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
            }
            .overlay { if !lane.ticks.isEmpty { tickMarks(lane.ticks.map { $0 - lane.x }) } }
            .clipShape(shape)
            .overlay(shape.stroke(chosen ? Theme.accent : lane.color, lineWidth: chosen ? 2 : 1))
    }

    /// A grip at one end of a lane, to pull.
    private func grip(_ lane: Lane) -> some View {
        Capsule()
            .fill(lane.color)
            .frame(width: 4, height: 16)
            .frame(width: 14, height: Self.laneHeight)
            .contentShape(Rectangle().inset(by: -Self.laneReach))
    }

    /// A track's lane: dragged along the film, its ends pulled to trim it,
    /// tapped to choose it — each drag one Undo.
    private func trackLane(_ lane: Lane, film: Double, scale: Double) -> some View {
        let chosen = chosenTrack == lane.id
        return laneFace(lane, chosen: chosen)
            .overlay(alignment: .leading) { grip(lane).gesture(trackGesture(lane, edge: .start, film: film, scale: scale)) }
            .overlay(alignment: .trailing) { grip(lane).gesture(trackGesture(lane, edge: .end, film: film, scale: scale)) }
            .frame(width: max(lane.width, 30), height: Self.laneHeight)
            .contentShape(Rectangle().inset(by: -Self.laneReach))
            .onTapGesture { chosenTrack = chosen ? nil : lane.id }
            .gesture(trackGesture(lane, edge: nil, film: film, scale: scale))
            .offset(x: lane.x)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lane.spoken)
            .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { chosenTrack = chosen ? nil : lane.id }
            .accessibilityAdjustableAction { direction in nudgeTrack(lane, by: direction == .increment ? 0.1 : -0.1, film: film) }
            .accessibilityAction(named: Text("Trim longer")) { trimTrack(lane, by: 0.1) }
            .accessibilityAction(named: Text("Trim shorter")) { trimTrack(lane, by: -0.1) }
    }

    /// A track's lane dragged — whole, or by one end — the step kept open
    /// until the finger lifts.
    private func trackGesture(_ lane: Lane, edge: Timeline.Edge?, film: Double, scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if laneDrag?.id != lane.id { laneDrag = LaneDrag(id: lane.id, edge: edge, track: lane.track, scale: scale) }
                guard let current = laneDrag, let track = current.track else { return }
                let dx = Double(value.translation.width)
                let next: AudioTrack
                if let edge = current.edge {
                    guard let length = lane.length else { return }
                    next = Timeline.trimmedTrack(track, edge: edge, dx: dx, scale: current.scale, duration: length)
                } else {
                    next = Timeline.movedTrack(track, dx: dx, scale: current.scale, film: film, beats: beatsInFilm(track))
                }
                store.dragTrack(lane.id, to: next)
            }
            .onEnded { _ in
                let trims = laneDrag?.edge != nil
                laneDrag = nil
                store.endLaneDrag(trims ? tr("Trim audio") : tr("Move audio"))
            }
    }

    /// VoiceOver's adjust of a track's lane: its start a tenth later or
    /// earlier.
    private func nudgeTrack(_ lane: Lane, by seconds: Double, film: Double) {
        guard let track = lane.track else { return }
        store.setTrack(lane.id, to: Timeline.movedTrack(track, dx: seconds, scale: 1, film: film, beats: beatsInFilm(track)),
                       label: tr("Move audio"))
    }

    /// VoiceOver's Trim longer and Trim shorter: its end a tenth on or back.
    private func trimTrack(_ lane: Lane, by seconds: Double) {
        guard let track = lane.track, let length = lane.length else { return }
        store.setTrack(lane.id, to: Timeline.trimmedTrack(track, edge: .end, dx: seconds, scale: 1, duration: length),
                       label: tr("Trim audio"))
    }

    /// A track's song's beats where they fall in the film, for a lane with
    /// Beat Sync on to snap to.
    private func beatsInFilm(_ track: AudioTrack) -> [Double] {
        guard track.beatSync, let id = track.audioId, let beats = trackBeats[id] else { return [] }
        let film = store.timelinePages.reduce(0.0) { $0 + $1.hold }
        return Beats.inFilm(beats, track: track, length: trackLengths[id], film: film)
    }

    /// An element's bar: dragged within its page, its ends pulled to when
    /// it comes and goes — each drag one Undo.
    private func elementLane(_ lane: Lane, hold: Double, scale: Double) -> some View {
        laneFace(lane, chosen: false)
            .overlay(alignment: .leading) { grip(lane).gesture(timingGesture(lane, edge: .start, hold: hold, scale: scale)) }
            .overlay(alignment: .trailing) { grip(lane).gesture(timingGesture(lane, edge: .end, hold: hold, scale: scale)) }
            .frame(width: max(lane.width, 30), height: Self.laneHeight)
            .contentShape(Rectangle().inset(by: -Self.laneReach))
            .gesture(timingGesture(lane, edge: nil, hold: hold, scale: scale))
            .offset(x: lane.x)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lane.spoken)
            .accessibilityAdjustableAction { direction in
                let timing = store.element(lane.id)?.timing
                store.setTiming(lane.id, to: Timeline.movedTiming(timing, dx: direction == .increment ? 0.1 : -0.1,
                                                                  scale: 1, hold: hold))
            }
            .accessibilityAction(named: Text("Trim longer")) { trimTiming(lane, by: 0.1, hold: hold) }
            .accessibilityAction(named: Text("Trim shorter")) { trimTiming(lane, by: -0.1, hold: hold) }
    }

    private func trimTiming(_ lane: Lane, by seconds: Double, hold: Double) {
        let timing = store.element(lane.id)?.timing
        store.setTiming(lane.id, to: Timeline.trimmedTiming(timing, edge: .end, dx: seconds, scale: 1, hold: hold))
    }

    private func timingGesture(_ lane: Lane, edge: Timeline.Edge?, hold: Double, scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if laneDrag?.id != lane.id {
                    laneDrag = LaneDrag(id: lane.id, edge: edge, timing: store.element(lane.id)?.timing, scale: scale)
                }
                guard let current = laneDrag else { return }
                let dx = Double(value.translation.width)
                let next = current.edge.map {
                    Timeline.trimmedTiming(current.timing, edge: $0, dx: dx, scale: current.scale, hold: hold)
                } ?? Timeline.movedTiming(current.timing, dx: dx, scale: current.scale, hold: hold)
                store.dragTiming(lane.id, to: next)
            }
            .onEnded { _ in
                laneDrag = nil
                store.endLaneDrag(tr("Edit"))
            }
    }

    /// The chosen track's actions: Edit — its volume, fades and Beat Sync —
    /// Split at the playhead, Duplicate and Delete.
    private func laneActions(_ track: AudioTrack) -> some View {
        HStack(spacing: 16) {
            Text(AudioTracks.name(of: track))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Edit") { editing = TrackRef(id: track.id) }
            Button("Split") {
                store.splitTrack(track.id, duration: track.audioId.flatMap { trackLengths[$0] })
            }
            .disabled(store.filmPlayhead == nil)
            Button("Duplicate") { store.duplicateTrack(track.id) }
            Button("Delete", role: .destructive) {
                chosenTrack = nil
                store.removeAudioTrack(track.id)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    /// A song's beats across its bar, `ticks` points from the film's start.
    private func tickMarks(_ ticks: [Double]) -> some View {
        Canvas { context, size in
            var marks = Path()
            for x in ticks {
                marks.move(to: CGPoint(x: x, y: 0))
                marks.addLine(to: CGPoint(x: x, y: Double(size.height)))
            }
            context.stroke(marks, with: .color(Theme.ink.opacity(0.6)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    // MARK: track lengths

    private var trackSources: [String] {
        store.design.audioTracks.compactMap(\.audioId)
    }

    /// Each track's length, then each song's beats — an effect has none
    /// worth ticking.
    @MainActor
    private func readTrackLengths() async {
        for id in trackSources where trackLengths[id] == nil {
            if let seconds = await AudioStore.duration(of: id) { trackLengths[id] = seconds }
        }
        for id in trackSources where trackBeats[id] == nil && !AudioTrack.isEffect(id) {
            if let beats = await AudioStore.beats(of: id) { trackBeats[id] = beats }
        }
    }
}
