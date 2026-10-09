// The page heard as it plays: each clip's own sound while its page is up
// (AudioMix.clips) and the design's music, in Play in the editor and in
// Present. One player a clip and one for the music, each kept to the page's
// clock: a looping clip goes round its trimmed window (AVPlayerLooper), one
// that does not falls silent at its end, and once a second a player more
// than 150 ms off the clock is put right — as the Android twin's PageSound
// keeps its players.
//
// Play shares the phone's sound, and the silent switch mutes it; a
// presentation takes the sound, switch or not. The session is let go, and
// other apps told, when the sound stops.

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
    /// round and round or once, at `level`.
    private final class Voice {
        let player = AVQueuePlayer()
        /// What keeps a looping voice going round; none for one played once.
        private var looper: AVPlayerLooper?
        let level: Float
        let since: Date
        let start: Double
        let end: Double
        let loop: Bool

        init(url: URL, start: Double, end: Double, loop: Bool, level: Float, since: Date) {
            self.start = start
            self.end = end
            self.loop = loop
            self.level = level
            self.since = since
            let item = AVPlayerItem(url: url)
            if loop {
                looper = AVPlayerLooper(player: player, templateItem: item,
                                        timeRange: CMTimeRange(start: PageSound.time(start), end: PageSound.time(end)))
            } else {
                item.forwardPlaybackEndTime = PageSound.time(end)
                player.insert(item, after: nil)
            }
            player.volume = level
        }

        /// Where in the file it should be at `now`; nil once it has played
        /// out, or for a window too short to play.
        func position(at now: Date) -> Double? {
            let t = max(0, now.timeIntervalSince(since))
            let span = end - start
            guard span > 0.01 else { return nil }
            if loop { return start + t.truncatingRemainder(dividingBy: span) }
            // Within a twentieth of its end it has ended: the player may
            // already have stopped there.
            return t < span - 0.05 ? start + t : nil
        }

        /// Puts the player where the clock says — once it has strayed, or
        /// when `force`d — and keeps it playing until it has played out.
        func sync(_ now: Date, force: Bool = false) {
            guard let want = position(at: now) else {
                player.pause()
                return
            }
            let at = player.currentTime().seconds
            var off = abs(at - want)
            // Just past the window's end and just past its start are the
            // same moment, for a voice going round.
            if loop { off = min(off, (end - start) - off) }
            if force || !at.isFinite || off > PageSound.drift {
                player.seek(to: PageSound.time(want), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            if player.rate == 0 { player.play() }
        }

        func stop() {
            looper?.disableLooping()
            looper = nil
            player.pause()
            player.removeAllItems()
        }
    }

    private var clips: [Voice] = []
    private var music: Voice?
    /// Move on as the sound does, so a file still being read for a page
    /// already gone, or music already stopped, never starts.
    private var clipTurn = 0
    private var musicTurn = 0
    private var musicLoading = false
    private var ticker: Task<Void, Never>?
    private var holdsSession = false

    static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    /// The clips of a page that came up at `since`, in place of any page's
    /// before: each clip this phone has with sound in it, in its window, at
    /// its volume.
    func page(_ sounding: [AudioMix.Clip], since: Date) {
        clips.forEach { $0.stop() }
        clips = []
        clipTurn += 1
        let turn = clipTurn
        let wanted = sounding.compactMap { clip in VideoStore.url(for: clip.source).map { (clip, $0) } }
        guard !wanted.isEmpty else { return }
        Task { @MainActor in
            for (clip, url) in wanted {
                // Its length, and whether it has sound at all, read without
                // holding up the page.
                let length = await VideoStore.soundLength(of: clip.source)
                guard turn == self.clipTurn else { return }
                guard let length else { continue }
                let p = clip.playback
                let start = max(0, p.start)
                let end = min(p.end ?? length, length)
                guard end - start > 0.01 else { continue }
                self.play(Voice(url: url, start: start, end: end, loop: p.loop,
                                level: Float(min(max(p.volume, 0), 1)), since: since))
            }
        }
    }

    /// The design's music, if this phone has it, as from `offset` seconds
    /// in at `since`, looping; left playing when it already is.
    func music(design: Design, offset: Double, since: Date) {
        guard music == nil, !musicLoading, let id = design.motion?.soundtrack,
              let url = AudioStore.url(for: id) else { return }
        let level = min(max(design.motion?.soundVolume ?? 1, 0), 1)
        guard level > 0 else { return }
        musicLoading = true
        let turn = musicTurn
        Task { @MainActor in
            let length = await AudioStore.duration(of: id)
            guard turn == self.musicTurn else { return }
            self.musicLoading = false
            guard let length, length > 0.01 else { return }
            // Started `offset` seconds before `since`, so the clock finds it
            // there.
            let voice = Voice(url: url, start: 0, end: length, loop: true, level: Float(level),
                              since: since.addingTimeInterval(-offset))
            self.music = voice
            self.play(voice)
        }
    }

    private func play(_ voice: Voice) {
        takeSession()
        if voice !== music { clips.append(voice) }
        voice.sync(Date(), force: true)
        keepTime()
    }

    /// Everything silent and let go — the music falling away over a second
    /// first, when `fade`d, as a presentation closes.
    func stop(fade: Bool = false) {
        clipTurn += 1
        musicTurn += 1
        musicLoading = false
        clips.forEach { $0.stop() }
        clips = []
        ticker?.cancel()
        ticker = nil
        let last = music
        music = nil
        guard fade, let last else {
            last?.stop()
            letGo()
            return
        }
        Task { @MainActor in
            let steps = 20
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(Soundtrack.fadeSeconds / Double(steps)))
                last.player.volume = last.level * Float(steps - step) / Float(steps)
            }
            last.stop()
            self.letGo()
        }
    }

    /// Once a second, every player put back on the clock if it has strayed.
    private func keepTime() {
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let now = Date()
                for voice in self.clips { voice.sync(now) }
                self.music?.sync(now)
            }
        }
    }

    /// The phone's sound: shared and silenced by the switch for Play, taken
    /// for a presentation. Left alone while dictation has the microphone.
    private func takeSession() {
        guard !holdsSession, !Dictation.shared.isListening else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(presenting ? .playback : .ambient)
        try? session.setActive(true)
        holdsSession = true
    }

    private func letGo() {
        // Taken again in the meantime — the sound turned back on mid-fade —
        // it is kept.
        guard holdsSession, music == nil, clips.isEmpty, !musicLoading else { return }
        holdsSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Whether anything in `design` is heard on this phone: its music, or a
    /// clip with sound on a page Present shows.
    static func heard(in design: Design) async -> Bool {
        if AudioStore.url(for: design.motion?.soundtrack) != nil, (design.motion?.soundVolume ?? 1) > 0 { return true }
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
