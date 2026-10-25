// The page heard as it plays: each clip's own sound while its page is up
// and its element shows (AudioMix.clips), and the design's audio tracks,
// in Play in the editor and in Present. One player a clip and one a track,
// each kept to its clock: a looping clip goes round its trimmed window
// (AVPlayerLooper), one that does not falls silent at its end, and one at
// another speed plays its window stretched or squeezed in a composition,
// its pitch kept (.spectral), rising and falling over its fades; a track
// waits for its place in the film (AudioMix.span), plays its window once
// or round and round, and its level follows its fades every tenth of a
// second. Once a second a player more than 150 ms off the clock is put
// right — as the Android twin's PageSound keeps its players. A clip or a
// track with Enhance voice on plays its enhanced sound (AudioStore
// .enhancedURL), made before it starts the first time.
//
// Play shares the phone's sound, and the silent switch mutes it; a
// presentation takes the sound, switch or not. The session is let go, and
// other apps told, when the sound stops. While a voice-over records, the
// recorder has the session, and nothing here touches it.

import AVFoundation
import Foundation

final class PageSound {

    /// How far a player may stray from the clock before it is put right.
    static let drift = 0.15

    private let presenting: Bool

    init(presenting: Bool) {
        self.presenting = presenting
    }

    /// One player, playing `start`...`end` seconds of its file from `since`,
    /// round and round or once, at `level` — for `lasts` seconds when that
    /// is set, rising and falling over `fadeIn` and `fadeOut`, in seconds
    /// on its own clock, and heard only within `timing` on that clock when
    /// it has one: a clip whose element shows for part of its page.
    private final class Voice {
        let player = AVQueuePlayer()
        /// What keeps a looping voice going round; none for one played once.
        private var looper: AVPlayerLooper?
        let level: Float
        let since: Date
        let start: Double
        let end: Double
        let loop: Bool
        let lasts: Double?
        let fadeIn: ClosedRange<Double>?
        let fadeOut: ClosedRange<Double>?
        let timing: ElementTiming?
        /// Whether it has started: one still waiting for its moment is
        /// looked at every tick, not once a second, so it starts on time.
        private(set) var begun = false

        init(item: AVPlayerItem, start: Double, end: Double, loop: Bool, level: Float, since: Date,
             lasts: Double? = nil, fadeIn: ClosedRange<Double>? = nil, fadeOut: ClosedRange<Double>? = nil,
             timing: ElementTiming? = nil) {
            self.start = start
            self.end = end
            self.loop = loop
            self.level = level
            self.since = since
            self.lasts = lasts
            self.fadeIn = fadeIn
            self.fadeOut = fadeOut
            self.timing = timing
            if loop {
                looper = AVPlayerLooper(player: player, templateItem: item,
                                        timeRange: CMTimeRange(start: PageSound.time(start), end: PageSound.time(end)))
            } else {
                item.forwardPlaybackEndTime = PageSound.time(end)
                player.insert(item, after: nil)
            }
            player.volume = fadeIn == nil ? level : 0
        }

        /// Where in the file it should be at `now`; nil before its moment,
        /// outside its timing, once it has played out, or for a window too
        /// short to play.
        func position(at now: Date) -> Double? {
            let t = now.timeIntervalSince(since)
            let span = end - start
            guard span > 0.01, t >= 0, ElementTiming.shows(timing, at: t) else { return nil }
            // Within a twentieth of its end it has ended: the player may
            // already have stopped there.
            if let lasts, t >= lasts - 0.05 { return nil }
            if loop { return start + t.truncatingRemainder(dividingBy: span) }
            return t < span - 0.05 ? start + t : nil
        }

        /// How loud it is at `now`, under its fades.
        func volume(at now: Date) -> Float {
            Float(AudioMix.envelope(now.timeIntervalSince(since), gain: Double(level), fadeIn: fadeIn, fadeOut: fadeOut))
        }

        /// Puts the player where the clock says — once it has strayed, or
        /// when `force`d — and keeps it playing until it has played out.
        func sync(_ now: Date, force: Bool = false) {
            guard let want = position(at: now) else {
                player.pause()
                return
            }
            player.volume = volume(at: now)
            let at = player.currentTime().seconds
            var off = abs(at - want)
            // Just past the window's end and just past its start are the
            // same moment, for a voice going round.
            if loop { off = min(off, (end - start) - off) }
            if force || !begun || !at.isFinite || off > PageSound.drift {
                player.seek(to: PageSound.time(want), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            if player.rate == 0 { player.play() }
            begun = true
        }

        /// Between the checks on its clock: its level kept to its fades,
        /// and silent once its time is up.
        func follow(_ now: Date) {
            guard position(at: now) != nil else {
                player.pause()
                return
            }
            player.volume = volume(at: now)
        }

        func stop() {
            looper?.disableLooping()
            looper = nil
            player.pause()
            player.removeAllItems()
        }
    }

    private var clips: [Voice] = []
    private var tracks: [Voice] = []
    /// Move on as the sound does, so a file still being read for a page
    /// already gone, or tracks already stopped, never starts.
    private var clipTurn = 0
    private var trackTurn = 0
    private var tracksLoading = false
    private var ticker: Task<Void, Never>?
    private var holdsSession = false
    /// The phone has one session for every PageSound: how many hold it, and
    /// how many of those are presentations, so one letting go never stops
    /// another still playing — as each Android twin keeps its own focus.
    /// Main actor use only.
    private static var holders = 0
    private static var presenters = 0
    /// Whether a presentation holds the phone's sound: what live captions
    /// hand the sound back to as they stop (LiveCaptioner).
    static var presentationHolds: Bool { presenters > 0 }

    /// How often each track's level follows its fades, in seconds; every
    /// tenth tick every player is checked against its clock.
    static let tick = 0.1

    static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    /// How long `duration` of sound lasts played at `speed`: itself at 1×.
    static func scaled(_ duration: CMTime, speed: Double) -> CMTime {
        guard speed > 0, speed != 1 else { return duration }
        return time(duration.seconds / speed)
    }

    /// The sound of the file at `url` from `start` to `end` seconds, played
    /// at `speed` with its pitch kept: a composition of that window alone,
    /// stretched or squeezed to last its length over the speed, as the
    /// video's mix lays it (Soundtrack.mux). Nil when its sound cannot be
    /// read.
    @MainActor
    static func stretched(_ url: URL, start: Double, end: Double, speed: Double) async -> AVPlayerItem? {
        let asset = AVURLAsset(url: url)
        guard let audio = try? await asset.loadTracks(withMediaType: .audio).first,
              let range = try? await audio.load(.timeRange) else { return nil }
        let window = CMTimeRange(start: time(start), end: CMTimeMinimum(time(end), range.end))
        let composition = AVMutableComposition()
        guard CMTimeCompare(window.duration, .zero) > 0,
              let track = composition.addMutableTrack(withMediaType: .audio,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? track.insertTimeRange(window, of: audio, at: .zero)) != nil else { return nil }
        track.scaleTimeRange(CMTimeRange(start: .zero, duration: window.duration),
                             toDuration: scaled(window.duration, speed: speed))
        let item = AVPlayerItem(asset: composition)
        item.audioTimePitchAlgorithm = .spectral
        return item
    }

    /// The clips of a page that came up at `since`, in place of any page's
    /// before: each clip this phone has with sound in it, in its window, at
    /// its speed and volume, with its fades, while its element shows — as
    /// AudioMix lays it in the video. A page `length` seconds long fades a
    /// looping clip out at its end; one with no end known — a talk in
    /// Present — does not.
    func page(_ sounding: [AudioMix.Clip], since: Date, length pageLength: Double? = nil) {
        clips.forEach { $0.stop() }
        clips = []
        clipTurn += 1
        let turn = clipTurn
        let wanted = sounding.compactMap { clip in VideoStore.url(for: clip.source).map { (clip, $0) } }
        guard !wanted.isEmpty else { return }
        Task { @MainActor in
            for (clip, own) in wanted {
                var url = own
                if clip.playback.enhance {
                    url = await AudioStore.enhancedURL(for: VideoStore.prefix + clip.source) ?? own
                    guard turn == self.clipTurn else { return }
                }
                // Its length, and whether it has sound at all, read without
                // holding up the page.
                let length = await VideoStore.soundLength(of: clip.source)
                guard turn == self.clipTurn else { return }
                guard let length else { continue }
                let p = clip.playback
                let start = max(0, p.start)
                let end = min(p.end ?? length, length)
                guard end - start > 0.01,
                      let heard = AudioMix.clipHeard(p, window: end - start, timing: clip.timing, page: pageLength)
                else { continue }
                let fades = AudioMix.clipFades(p, heard: heard)
                let rate = p.playbackSpeed
                let voice: Voice
                if rate == 1 {
                    voice = Voice(item: AVPlayerItem(url: url), start: start, end: end, loop: p.loop,
                                  level: Float(min(max(p.volume, 0), 1)), since: since,
                                  fadeIn: fades.fadeIn, fadeOut: fades.fadeOut, timing: clip.timing)
                } else {
                    // The window alone, at its speed: played from its own
                    // start, over its length at that speed.
                    let item = await PageSound.stretched(url, start: start, end: end, speed: rate)
                    guard turn == self.clipTurn else { return }
                    guard let item else { continue }
                    voice = Voice(item: item, start: 0, end: (end - start) / rate, loop: p.loop,
                                  level: Float(min(max(p.volume, 0), 1)), since: since,
                                  fadeIn: fades.fadeIn, fadeOut: fades.fadeOut, timing: clip.timing)
                }
                self.clips.append(voice)
                self.play(voice)
            }
        }
    }

    /// The design's tracks this phone has the music of, on a film clock
    /// that read `offset` seconds at `since`: each from its place in a film
    /// `film` seconds long, in its trim, at its volume, with its fades — as
    /// AudioMix.span lays it for the video. A talk in Present passes no end
    /// (`.infinity`), so a looping track goes on for as long as it runs, as
    /// the soundtrack always did. Left playing when they already are.
    func tracks(design: Design, offset: Double, since: Date, film: Double) {
        guard tracks.isEmpty, !tracksLoading else { return }
        let wanted = design.audioTracks.compactMap { track in AudioStore.url(for: track.audioId).map { (track, $0) } }
        guard !wanted.isEmpty else { return }
        tracksLoading = true
        let turn = trackTurn
        // The moment the film's clock reads 0.
        let zero = since.addingTimeInterval(-offset)
        Task { @MainActor in
            var lengths: [String: Double] = [:]
            for (track, _) in wanted {
                guard let id = track.audioId, lengths[id] == nil else { continue }
                if let length = await AudioStore.duration(of: id) { lengths[id] = length }
            }
            // Each enhanced sound made, the first time, before any starts.
            var enhanced: [String: URL] = [:]
            for (track, _) in wanted where track.enhance {
                guard let id = track.audioId, enhanced[id] == nil else { continue }
                if let file = await AudioStore.enhancedURL(for: id) { enhanced[id] = file }
            }
            guard turn == self.trackTurn else { return }
            self.tracksLoading = false
            for (track, own) in wanted {
                let url = track.enhance ? (track.audioId.flatMap { enhanced[$0] } ?? own) : own
                let length = track.audioId.flatMap { lengths[$0] }
                guard let span = AudioMix.span(of: track, duration: length, film: film) else { continue }
                let lasts: Double? = span.until.isFinite ? span.until - span.at : nil
                let begins = zero.addingTimeInterval(span.at)
                // Over already, where the film is now.
                if let lasts, begins.addingTimeInterval(lasts) <= Date() { continue }
                func local(_ fade: ClosedRange<Double>?) -> ClosedRange<Double>? {
                    fade.map { ($0.lowerBound - span.at)...($0.upperBound - span.at) }
                }
                let voice = Voice(item: AVPlayerItem(url: url), start: span.from, end: span.to, loop: span.loop,
                                  level: Float(span.gain),
                                  since: begins, lasts: lasts, fadeIn: local(span.fadeIn), fadeOut: local(span.fadeOut))
                self.tracks.append(voice)
                self.play(voice)
            }
        }
    }

    private func play(_ voice: Voice) {
        takeSession()
        voice.sync(Date(), force: true)
        keepTime()
    }

    /// Everything silent and let go — the tracks falling away over a second
    /// first, when `fade`d, as a presentation closes.
    func stop(fade: Bool = false) {
        clipTurn += 1
        trackTurn += 1
        tracksLoading = false
        clips.forEach { $0.stop() }
        clips = []
        ticker?.cancel()
        ticker = nil
        let last = tracks
        tracks = []
        guard fade, !last.isEmpty else {
            last.forEach { $0.stop() }
            letGo()
            return
        }
        let levels = last.map { $0.player.volume }
        Task { @MainActor in
            let steps = 20
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(Soundtrack.fadeSeconds / Double(steps)))
                for (voice, level) in zip(last, levels) {
                    voice.player.volume = level * Float(steps - step) / Float(steps)
                }
            }
            last.forEach { $0.stop() }
            self.letGo()
        }
    }

    /// Every tick, each track's level kept to its fades and any player
    /// still waiting for its moment started; once a second, every player put
    /// back on the clock if it has strayed.
    private func keepTime() {
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(PageSound.tick))
                guard let self, !Task.isCancelled else { return }
                ticks += 1
                let now = Date()
                let check = ticks % 10 == 0
                for voice in self.clips + self.tracks {
                    if check || !voice.begun { voice.sync(now) } else { voice.follow(now) }
                }
            }
        }
    }

    /// The phone's sound: shared and silenced by the switch for Play, taken
    /// for a presentation. Left alone while dictation, a voice-over or live
    /// captions have the microphone — live captions playing the sound beside
    /// it, so the presentation still counts as holding it.
    private func takeSession() {
        guard !holdsSession, !Dictation.shared.isListening, !VoiceRecorder.shared.isRecording,
              !LiveCaptionFeed.listening else {
            if !holdsSession, LiveCaptionFeed.listening {
                holdsSession = true
                PageSound.holders += 1
                if presenting { PageSound.presenters += 1 }
            }
            return
        }
        holdsSession = true
        PageSound.holders += 1
        if presenting { PageSound.presenters += 1 }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(PageSound.presenters > 0 ? .playback : .ambient)
        try? session.setActive(true)
    }

    private func letGo() {
        // Taken again in the meantime — the sound turned back on mid-fade —
        // it is kept.
        guard holdsSession, tracks.isEmpty, clips.isEmpty, !tracksLoading else { return }
        holdsSession = false
        PageSound.holders -= 1
        if presenting { PageSound.presenters -= 1 }
        // Dictation or a voice-over took the session while this held it: it
        // is theirs now, and they let it go when they stop.
        guard !Dictation.shared.isListening, !VoiceRecorder.shared.isRecording, !LiveCaptionFeed.listening else { return }
        let session = AVAudioSession.sharedInstance()
        // Another still plays — Play started while Present faded out — so the
        // session stays, shared again once no presentation holds it.
        guard PageSound.holders == 0 else {
            if PageSound.presenters == 0 { try? session.setCategory(.ambient) }
            return
        }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Whether anything in `design` is heard on this phone: a track whose
    /// music is here, or a clip with sound on a page Present shows.
    static func heard(in design: Design) async -> Bool {
        if design.audioTracks.contains(where: { $0.volume > 0 && AudioStore.url(for: $0.audioId) != nil }) { return true }
        var ids: [String] = []
        for index in design.visiblePageIndices {
            for clip in AudioMix.clips(design: design, page: design.pages[index]) where !ids.contains(clip.source) {
                ids.append(clip.source)
            }
        }
        for id in ids {
            if await VideoStore.soundLength(of: id) != nil { return true }
        }
        return false
    }
}
