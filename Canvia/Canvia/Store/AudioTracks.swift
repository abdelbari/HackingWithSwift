// The design's audio tracks as the Audio sheet edits them: added from your
// music, a voice-over or the built-in sound effects, each change to one —
// where it starts, its trim, volume, fades, loop, Beat Sync — one undo
// step, and taken out again; and what the sheet says of each. As the
// Android twin's Audio panel does.

import Foundation

enum AudioTracks {

    /// What a track is called: its own name, else its music's (on this
    /// phone), else that its music was chosen on another phone.
    static func name(of track: AudioTrack) -> String {
        let own = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        guard let id = track.audioId, AudioStore.url(for: id) != nil else { return tr("Music from another phone") }
        return AudioStore.label(for: id)
    }

    /// How long the track's trim is, in seconds, its music being `duration`
    /// long: what it plays once through.
    static func length(of track: AudioTrack, duration: Double) -> Double {
        let from = min(max(track.trimStart, 0), duration)
        let to = min(track.trimEnd ?? duration, duration)
        return max(0, to - from)
    }

    /// The line under a track's name: where it starts in the film, and how
    /// long it plays once through when that is known — "Starts at 0:02.0 ·
    /// 0:12.5 long" — "loops" when it does, and that its music is `missing`
    /// from this phone, chosen on another. As the Android twin's.
    static func summary(of track: AudioTrack, duration: Double?, missing: Bool = false) -> String {
        var line = tr("Starts at %@", VideoStore.timeLabel(track.start))
        if let duration { line += " · " + tr("%@ long", VideoStore.timeLabel(length(of: track, duration: duration))) }
        if track.loop { line += " · " + tr("loops") }
        if missing { line += " · " + tr("not on this phone") }
        return line
    }

    /// Whether the track's music is not on this phone: chosen on another.
    static func isMissing(_ track: AudioTrack) -> Bool {
        AudioStore.url(for: track.audioId) == nil
    }

    /// What a new voice-over is called first.
    static let firstVoiceOver = tr("Voice-over")

    /// Every name a recording can start with: "Voice-over" and the
    /// catalogue's seven translations of it — the same list as the Android
    /// twin's AudioTracks.VOICE_OVER_NAMES, whichever language named it.
    static let voiceOverNames = [
        "Voice-over", "التعليق الصوتي", "Sprachaufnahme", "Voz en off",
        "Voix off", "Voce fuori campo", "ナレーション", "Narração",
    ]

    /// Whether `name` is one Record gives, whatever the language the app
    /// runs in now: one of `voiceOverNames`, or one with " 2" and on after
    /// it — the one rule for a voice-over on both phones (the audio panel,
    /// the audio download's 'Include voice-over' and the captions check),
    /// so "Voice-over take", renamed by hand, is music.
    static func isVoiceOverName(_ name: String) -> Bool {
        var base = Substring(name)
        if let space = name.lastIndex(of: " "), space > name.startIndex {
            let number = name[name.index(after: space)...]
            if !number.isEmpty, number.allSatisfy({ ("0"..."9").contains($0) }) { base = name[..<space] }
        }
        return voiceOverNames.contains(String(base))
    }

    /// The name a new voice-over takes, as the Android twin names it:
    /// "Voice-over", then "Voice-over 2" and on — the first that none of
    /// the design's tracks has.
    static func voiceOverName(after tracks: [AudioTrack]) -> String {
        let names = Set(tracks.map(\.name))
        guard names.contains(firstVoiceOver) else { return firstVoiceOver }
        var n = 2
        while names.contains("\(firstVoiceOver) \(n)") { n += 1 }
        return "\(firstVoiceOver) \(n)"
    }

    /// What Export's motion note says of the music: nothing without tracks,
    /// that the video has music under it, or that some or all of it —
    /// `away` of the `tracks` — was chosen on another phone and is not on
    /// this one. Each sentence starts with a space. As the Android twin's.
    static func musicNote(tracks: Int, away: Int) -> String {
        if tracks <= 0 { return "" }
        if away <= 0 { return " " + tr("The video has music under it.") }
        if away >= tracks { return " " + tr("The music was chosen on another phone and isn't on this one.") }
        return " " + tr("Some of the music was chosen on another phone and isn't on this one.")
    }

    /// What a clip's detached sound is called.
    static var clipSoundName: String { tr("Clip sound") }

    /// `design` with clip `clipElementId`'s sound lifted into a track of
    /// its own, last in the list, and the clip muted: the track plays the
    /// clip's file ("video:<id>") from where the clip starts in the film —
    /// its page's start (AudioMix.pageStart) and its own timing's start on
    /// the page — its trim, volume, fades and Enhance voice the clip's, once
    /// through. Its speed stays with the clip: a track plays at 1×. Nil
    /// when there is no such clip, it is a picture from a clip's moment,
    /// it is muted already, or its page is locked. As the Android twin's
    /// AudioTracks.detached.
    static func detached(_ design: Design, clipElementId: String) -> Design? {
        for (p, page) in design.pages.enumerated() {
            guard let i = page.elements.firstIndex(where: { $0.id == clipElementId }) else { continue }
            let el = page.elements[i]
            let playback = el.clip ?? ClipPlayback()
            guard el.type == .image, let src = el.src, let parts = VideoStore.split(src), parts.time == nil,
                  !playback.muted, !PageLocks.isLocked(page) else { return nil }
            let start = AudioMix.pageStart(design: design, index: p) + max(el.timing?.start ?? 0, 0)
            var track = AudioTrack(src: VideoStore.src(parts.id, at: nil), start: start,
                                   trimStart: max(0, playback.start), trimEnd: playback.end,
                                   volume: min(max(playback.volume, 0), 1),
                                   fadeIn: playback.fadeIn, fadeOut: playback.fadeOut, name: clipSoundName)
            track.enhance = playback.enhance
            var out = design
            var muted = playback
            muted.muted = true
            out.pages[p].elements[i].clip = muted
            out.audioTracks.append(track)
            return out
        }
        return nil
    }

    /// A time as a fade shows it: "0.0s" to "5.0s".
    static func secondsLabel(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }

    /// Seconds kept to the tenth the sheet shows.
    static func tenths(_ seconds: Double) -> Double { (seconds * 10).rounded() / 10 }

    /// `design` with the track `trackId` cut in two `t` seconds into the
    /// film (to a tenth), as Split at the playhead cuts it — both playing the
    /// same file, with no fade at the cut, so the cut itself is not heard:
    /// the first keeps its id, start and fade in and plays up to the cut
    /// (trimEnd = trimStart + (t − start)) with no fade out; the second, a
    /// new id, starts at t from the cut (trimStart), keeps the first's end
    /// and fade out, and has no fade in. Neither loops: a looping track
    /// becomes its first time through, cut in two, each piece played once. Nil when the cut is not at least
    /// AudioTrack.minLength inside the track's first time through — its
    /// trimmed length, when the file is `duration` long or the trim has an
    /// end, else anywhere after its start. The Android twin's split, row for
    /// row (motion.json).
    static func split(_ design: Design, trackId: String, at t: Double, duration: Double? = nil) -> Design? {
        var tracks = design.audioTracks
        guard let index = tracks.firstIndex(where: { $0.id == trackId }) else { return nil }
        let track = tracks[index]
        let at = Timeline.halfUp(t, 10)
        let into = at - track.start
        let cut = Timeline.halfUp(track.trimStart + into, 100)
        let end = track.trimEnd ?? duration
        guard into >= AudioTrack.minLength - 1e-9 else { return nil }
        if let end, cut > end - AudioTrack.minLength + 1e-9 { return nil }
        var first = track
        first.trimEnd = cut
        first.loop = false
        first.fadeOut = 0
        var second = track
        second.id = UID.make("track")
        second.start = at
        second.trimStart = cut
        second.fadeIn = 0
        second.loop = false
        tracks[index] = first
        tracks.insert(second, at: index + 1)
        var out = design
        out.audioTracks = tracks
        return out
    }

    /// `design` with a copy of the track `trackId` after it, a new id, laid
    /// the same; nil when there is no such track.
    static func duplicating(_ design: Design, trackId: String) -> Design? {
        var tracks = design.audioTracks
        guard let index = tracks.firstIndex(where: { $0.id == trackId }) else { return nil }
        var copy = tracks[index]
        copy.id = UID.make("track")
        tracks.insert(copy, at: index + 1)
        var out = design
        out.audioTracks = tracks
        return out
    }

    /// How a lane is read aloud: its name, and from when to when it plays in
    /// the film — "Song, 0:03 to 0:18".
    static func spoken(_ name: String, from: Double, to: Double) -> String {
        tr("%@, %@ to %@", name, wholeClock(from), wholeClock(to))
    }

    /// Whole seconds as "m:ss", halves up.
    static func wholeClock(_ seconds: Double) -> String {
        let s = Int((max(0, seconds) + 0.5).rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension DesignStore {

    /// Music `id` as a new track, last in the list, as one step: from
    /// `start` seconds into the film — exactly, as a page's start is, the
    /// way the Android twin lays a voice-over — played once from the file's
    /// start at full volume, called `name` — by the music's own name when
    /// that is empty.
    @discardableResult
    func addAudioTrack(_ id: String, start: Double = 0, name: String = "") -> AudioTrack {
        let track = AudioTrack(src: AudioTrack.src(id), start: max(0, start),
                               name: name.isEmpty ? AudioStore.label(for: id) : name)
        apply { $0.audioTracks.append(track) }
        return track
    }

    /// Track `id` changed by `change`, as one step; none when it is gone or
    /// the change changes nothing.
    func updateAudioTrack(_ id: String, _ change: (inout AudioTrack) -> Void) {
        guard let index = design.audioTracks.firstIndex(where: { $0.id == id }) else { return }
        apply { design in
            var tracks = design.audioTracks
            change(&tracks[index])
            design.audioTracks = tracks
        }
    }

    /// Track `id` out of the design, as one step. Its music stays among
    /// your uploads, and the launch sweep takes a file nothing plays.
    func removeAudioTrack(_ id: String) {
        guard design.audioTracks.contains(where: { $0.id == id }) else { return }
        // The last track with Beat Sync on gone, the kept holds come back.
        apply { design in
            design.audioTracks.removeAll { $0.id == id }
            design = BeatSync.settled(design)
        }
    }

    /// One of the built-in sound effects as a new track, last in the list,
    /// as one step: from where the page on screen starts in the film, once,
    /// called by its name (SoundEffects.track), as on the Android twin.
    @discardableResult
    func addSoundEffect(_ effect: SoundEffect) -> AudioTrack {
        let track = SoundEffects.track(effect, start: pageStartSeconds)
        apply { $0.audioTracks.append(track) }
        return track
    }

    /// One of the built-in loops as a new track, last in the list, as one
    /// step: from the film's start, looping to fill it (MusicLibrary.track),
    /// as on the Android twin.
    @discardableResult
    func addMusic(_ music: MusicTrack) -> AudioTrack {
        let track = MusicLibrary.track(music)
        apply { $0.audioTracks.append(track) }
        return track
    }

    /// Beat Sync turned on for track `id`, its song's `beats` (seconds into
    /// the file, AudioStore.beats) and `length` known, as one step: the
    /// track says so, and each shown page's hold moves to the nearest beat
    /// where the track plays in the film (BeatSync.on), the holds as they
    /// were kept to come back to. A locked page keeps its hold, as on the
    /// Android twin; the next page starts from its end.
    func turnBeatSyncOn(_ id: String, beats: [Double], length: Double?) {
        guard let index = design.audioTracks.firstIndex(where: { $0.id == id }) else { return }
        apply { design in
            var tracks = design.audioTracks
            tracks[index].beatSync = true
            design.audioTracks = tracks
            let film = Timeline.pages(of: design).reduce(0.0) { $0 + $1.hold }
            // Beats a page's end could move to: the film's, and a hold's
            // worth on.
            let heard = Beats.inFilm(beats, track: tracks[index], length: length, film: film + BeatSync.maxHold)
            design = BeatSync.on(design, beats: heard)
        }
    }

    /// Beat Sync turned off for track `id`, as one step: the holds kept
    /// when it was turned on come back (BeatSync.off) — once no other track
    /// still has it on (BeatSync.settled).
    func turnBeatSyncOff(_ id: String) {
        guard let index = design.audioTracks.firstIndex(where: { $0.id == id }) else { return }
        apply { design in
            var tracks = design.audioTracks
            tracks[index].beatSync = false
            design.audioTracks = tracks
            // While another track still has it on, its holds and the kept
            // ones stay (BeatSync.settled).
            design = BeatSync.settled(design)
        }
    }

    /// Clip `elementId`'s sound as a track of its own and the clip muted
    /// (AudioTracks.detached), as one step named "Detach audio". A locked
    /// page says so, and nothing changes.
    func detachAudio(_ elementId: String) {
        if let p = design.pages.firstIndex(where: { $0.elements.contains { $0.id == elementId } }),
           refusesLockedPage(at: p) { return }
        guard let next = AudioTracks.detached(design, clipElementId: elementId) else { return }
        if hasPendingChanges && (editingTextId != nil || dictationTarget != nil) { commit() }
        namedStep = tr("Detach audio")
        apply { $0 = next }
        buzz(.confirm)
        announce(tr("The clip's sound is now a track in Audio"))
    }

    /// Whether Play has anything to show or to hear on this page: its
    /// motion, or the design's tracks.
    var pagePlays: Bool { pageIsAnimated || !design.audioTracks.isEmpty }
}
