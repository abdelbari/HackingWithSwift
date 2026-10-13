// The editor's timeline as the store works it: the playhead scrubbed
// through the film with the canvas showing that moment, a page's hold set by
// dragging its block's edge as one undo step, Split page at the playhead,
// and the selection shown or hidden from the playhead. As the Android
// twin's timeline does.

import Foundation

extension DesignStore {

    /// The pages on the timeline — the shown ones, as the video plays them —
    /// by index, and how long each holds.
    var timelinePages: [(index: Int, hold: Double)] { Timeline.pages(of: design) }

    /// Where the page on screen starts in the film, in seconds; nil for a
    /// hidden page, which is in no film.
    var timelinePageStart: Double? {
        var start = 0.0
        for entry in timelinePages {
            if entry.index == pageIndex { return start }
            start += entry.hold
        }
        return nil
    }

    /// The playhead as seconds into the page on screen, within its hold —
    /// its start when the playhead stood on a page since gone; nil while
    /// the page is hidden, which is on no timeline.
    var playheadInPage: Double? {
        guard timelinePageStart != nil else { return nil }
        guard playheadPage == nil || playheadPage == page.id else { return 0 }
        return min(max(playhead, 0), pageHold)
    }

    /// The playhead in the film: where the page on screen starts, and as far
    /// into it as the playhead stands; nil while the page is hidden.
    var filmPlayhead: Double? {
        guard let start = timelinePageStart, let t = playheadInPage else { return nil }
        return start + t
    }

    /// Whether Split page can cut the page on screen at the playhead: it
    /// stands on the page, at least Timeline.splitMargin from either end.
    var canSplitPage: Bool {
        guard let t = playheadInPage else { return false }
        return Timeline.splitHolds(hold: pageHold, at: t) != nil
    }

    /// A scrub begins: a play under way stops, and with it its sound.
    func beginScrub() {
        stopPreview()
    }

    /// The playhead at `t` seconds into the film, kept to the film, and the
    /// canvas showing the page there at that moment — brought on screen
    /// when it is another — in silence, until endScrub. The playhead is kept
    /// as that page and how far into it.
    func scrub(to t: Double) {
        let pages = timelinePages
        guard !pages.isEmpty else { return }
        let holds = pages.map { $0.hold }
        let spot = Timeline.locate(min(max(t, 0), holds.reduce(0, +)), holds: holds)
        let index = pages[spot.page].index
        if index != pageIndex { setPage(index) }
        playheadPage = design.pages[index].id
        playhead = spot.time
        previewTime = spot.time
    }

    /// The scrub over: the canvas at rest again, the playhead left where it
    /// stands.
    func endScrub() {
        previewTime = nil
    }

    /// A block tapped: its page on screen, and the playhead brought to the
    /// page's start when it stood on another.
    func selectTimelinePage(_ index: Int) {
        setPage(index)
    }

    /// Page `id`'s hold while its block's edge is dragged: set as it goes,
    /// with the step left open for commit() on release, so the whole drag is
    /// one Undo. Words being typed or dictated are a step of their own,
    /// closed first, so one Undo never takes back both — as apply() closes
    /// them, and the Android twin's drag commits what is open.
    func dragHold(of id: String, to seconds: Double) {
        guard let i = design.pages.firstIndex(where: { $0.id == id }) else { return }
        endTextEdit()
        endDictation()
        beginGesture()
        design.pages[i].holdSeconds = seconds
    }

    /// Page `id`'s hold set, as one step: VoiceOver's adjust of a block.
    func setHold(of id: String, to seconds: Double) {
        guard let i = design.pages.firstIndex(where: { $0.id == id }) else { return }
        apply { $0.pages[i].holdSeconds = seconds }
    }

    /// Split page: the page on screen cut in two at the playhead, as one
    /// step (Timeline.split), with the second part on screen and the
    /// playhead at its start. Nothing when the page is hidden or the
    /// playhead too near either end of it. Its clips' lengths are read
    /// first, off the main thread, so a clip that loops over its whole file
    /// plays on from the right moment; the split waits for them, and is
    /// let go if the page or the playhead moved meanwhile, as on Android.
    func splitPage() {
        guard let t = playheadInPage, canSplitPage else {
            buzz(.reject)
            return
        }
        let clips = Set(page.elements.compactMap { el in el.src.flatMap { VideoStore.split($0)?.id } })
        guard !clips.isEmpty else {
            split(at: t, lengths: [:])
            return
        }
        let id = page.id
        Task { @MainActor in
            var lengths: [String: Double] = [:]
            for clip in clips {
                if let seconds = await VideoStore.loadedDuration(of: clip) { lengths[clip] = seconds }
            }
            guard page.id == id, playheadInPage == t else { return }
            split(at: t, lengths: lengths)
        }
    }

    /// The page on screen split at `t`, its clips `lengths` long by
    /// VideoStore id.
    private func split(at t: Double, lengths: [String: Double]) {
        guard let parts = Timeline.split(page, at: t, hold: pageHold, duration: { lengths[$0] }) else {
            buzz(.reject)
            return
        }
        stopPreview()
        let index = pageIndex
        apply { design in
            design.pages[index] = parts.first
            design.pages.insert(parts.second, at: index + 1)
        }
        pageIndex = index + 1
        selection.removeAll()
        playheadPage = parts.second.id
        playhead = 0
        announce("Split page \(index + 1)")
    }

    /// "Show from playhead": the selection shown from the playhead on, as
    /// one step.
    func showSelectedFromPlayhead() {
        guard let t = playheadInPage else { return }
        updateSelected { $0.timing = ElementTiming.showing($0.timing, from: t) }
    }

    /// "Hide from playhead": the selection gone from the playhead on, as
    /// one step.
    func hideSelectedFromPlayhead() {
        guard let t = playheadInPage else { return }
        updateSelected { $0.timing = ElementTiming.hiding($0.timing, from: t) }
    }

    /// The selection shown for the whole page again, as one step.
    func clearSelectedTiming() {
        updateSelected { $0.timing = nil }
    }
}
