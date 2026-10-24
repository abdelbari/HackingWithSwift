// The editor's motion as the store works it, at parity with the Android
// twin: Animate's Create — the selected element held and dragged round the
// page, recorded as the path it plays along, with Smooth, Orient to path and
// Speed after — a whole page's animation, and the timeline's lanes: an
// audio track dragged along the film or trimmed at either end, split at the
// playhead, duplicated; an element's timing bar dragged or trimmed. Each
// drag is one Undo, named for what it did.

import Foundation

/// Animate's Create under way: the element it records, and whether a path
/// has been recorded yet — before, a drag records; after, the bar offers
/// Smooth, Orient to path, Speed and Re-record.
struct MotionRecording: Equatable {
    var id: String
    var recorded = false
}

extension DesignStore {

    // MARK: Create an animation

    /// The element being recorded, as it is now.
    var motionElement: Element? {
        motionRecording.flatMap { element($0.id) }
    }

    /// Create: record mode for the one selected element. Refused, with a
    /// word, without one element selected, on a locked page or for a locked
    /// element, as the Android twin's is. One with a path
    /// already opens on its options, to change them or record again.
    func beginMotionRecord() {
        guard let el = singleSelection else {
            buzz(.reject)
            announce(tr("Select one thing to record its path"), undoable: false)
            return
        }
        guard !refusesLockedPage() else { return }
        if el.locked {
            buzz(.reject)
            announce(tr("This element is locked"), undoable: false)
            return
        }
        stopPreview()
        endTextEdit()
        finishCrop()
        finishBrush()
        drawing = nil
        if hasPendingChanges { commit() }
        let has = el.animation?.kind == ElementAnimation.pathKind && MotionPath.travels(el.animation?.path)
        motionRecording = MotionRecording(id: el.id, recorded: has)
    }

    /// Record again: the next drag replaces the path.
    func rerecordMotion() {
        stopPreview()
        motionRecording?.recorded = false
    }

    /// Record mode over, what was recorded kept.
    func finishMotionRecord() {
        stopPreview()
        motionRecording = nil
    }

    /// A drag let go: the element rests where the finger lifted, and plays
    /// `samples` — its centre on the page, and when — as its path, from the
    /// drag's start to there, as one step; then the page plays to show it.
    /// A drag that went nowhere changes nothing. A path recorded again keeps
    /// its Smooth, Orient to path, Speed and delay.
    func recordMotion(_ samples: [MotionPath.Sample]) {
        guard let recording = motionRecording, let el = element(recording.id), !el.locked,
              let end = samples.last, !refusesLockedPage() else { return }
        let points = MotionPath.recorded(samples)
        guard MotionPath.travels(points) else {
            buzz(.reject)
            announce(tr("Drag it farther to record a path."), undoable: false)
            return
        }
        var anim = ElementAnimation(kind: ElementAnimation.pathKind, delay: 0, duration: MotionPath.seconds(samples))
        if let was = el.animation, was.kind == ElementAnimation.pathKind {
            anim.delay = was.delay
            anim.smooth = was.smooth
            anim.orient = was.orient
            anim.speed = was.speed
        }
        anim.path = points
        namedStep = tr("Create an animation")
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == recording.id }) else { return }
            page.elements[i].x = end.x - el.w / 2
            page.elements[i].y = end.y - el.h / 2
            page.elements[i].animation = anim
        }
        motionRecording?.recorded = true
        buzz(.confirm)
        playPreview()
    }

    /// The recorded path's Smooth, Orient to path or Speed changed by
    /// `change`, as one step, and played.
    func updateMotionPath(_ change: (inout ElementAnimation) -> Void) {
        guard let recording = motionRecording, let el = element(recording.id),
              var anim = el.animation, anim.kind == ElementAnimation.pathKind else { return }
        change(&anim)
        guard anim != el.animation else { return }
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == recording.id }) else { return }
            page.elements[i].animation = anim
        }
        playPreview()
    }

    // MARK: page animation

    /// The page on screen animated by `animation` — every element on it
    /// arriving, leaving or both, one after another — or by none, as one
    /// step; refused on a locked page.
    func setPageAnimation(_ animation: PageAnimation?) {
        guard page.pageAnimation != animation else { return }
        applyToPage { $0.pageAnimation = animation }
    }

    // MARK: lanes

    /// Track `id` set to `track` while its lane is dragged: the step left
    /// open for `endLaneDrag`, so the whole drag is one Undo. Words being
    /// typed are a step of their own, closed first.
    func dragTrack(_ id: String, to track: AudioTrack) {
        guard let i = design.audioTracks.firstIndex(where: { $0.id == id }) else { return }
        endTextEdit()
        endDictation()
        beginGesture()
        var tracks = design.audioTracks
        tracks[i] = track
        design.audioTracks = tracks
    }

    /// Element `id`'s timing set to `timing` while its bar is dragged: the
    /// step left open for `endLaneDrag`. A locked page, or a locked element,
    /// keeps its timing.
    func dragTiming(_ id: String, to timing: ElementTiming?) {
        guard !isPageLocked, let i = page.elements.firstIndex(where: { $0.id == id }),
              !page.elements[i].locked else { return }
        endTextEdit()
        endDictation()
        beginGesture()
        design.pages[pageIndex].elements[i].timing = timing
    }

    /// A lane's drag let go: its one step, called `label` — "Move audio",
    /// "Trim audio" — or nothing when it changed nothing.
    func endLaneDrag(_ label: String) {
        guard hasPendingChanges else { return }
        namedStep = label
        commit()
    }

    /// Split at the playhead: track `id` cut in two where the playhead stands
    /// in the film (AudioTracks.split), its file `duration` long when known,
    /// as one step; refused where the cut would leave too little of either.
    func splitTrack(_ id: String, duration: Double?) {
        guard let t = filmPlayhead else {
            buzz(.reject)
            return
        }
        guard let split = AudioTracks.split(design, trackId: id, at: t, duration: duration) else {
            buzz(.reject)
            announce(tr("Move the playhead inside the track to split it"), undoable: false)
            return
        }
        namedStep = tr("Split audio")
        apply { $0 = split }
        buzz(.confirm)
    }

    /// Track `id` again, after it, as one step.
    func duplicateTrack(_ id: String) {
        guard let copy = AudioTracks.duplicating(design, trackId: id) else { return }
        apply { $0 = copy }
        buzz(.confirm)
    }

    /// Track `id` set to `track` at once, as one step: VoiceOver's adjust of
    /// a lane.
    func setTrack(_ id: String, to track: AudioTrack, label: String) {
        guard let i = design.audioTracks.firstIndex(where: { $0.id == id }), design.audioTracks[i] != track else { return }
        namedStep = label
        apply { design in
            var tracks = design.audioTracks
            tracks[i] = track
            design.audioTracks = tracks
        }
    }

    /// Element `id`'s timing set at once, as one step: VoiceOver's adjust of
    /// its bar.
    func setTiming(_ id: String, to timing: ElementTiming?) {
        guard let el = element(id), !el.locked, el.timing != timing else { return }
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == id }) else { return }
            page.elements[i].timing = timing
        }
    }
}
