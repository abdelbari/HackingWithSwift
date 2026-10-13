// The design's audio tracks as the Audio sheet edits them: added from your
// music or a voice-over, each change to one — where it starts, its trim,
// volume, fades, loop — one undo step, and taken out again; and what the
// sheet says of each. As the Android twin's Audio panel does.

import Foundation

enum AudioTracks {

    /// What a track is called: its own name, else its music's (on this
    /// phone), else that its music was chosen on another phone.
    static func name(of track: AudioTrack) -> String {
        let own = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        guard let id = track.audioId, AudioStore.url(for: id) != nil else { return "Music from another phone" }
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
    /// 0:12.5 long".
    static func summary(of track: AudioTrack, duration: Double?) -> String {
        var line = "Starts at \(VideoStore.timeLabel(track.start))"
        if let duration { line += " · \(VideoStore.timeLabel(length(of: track, duration: duration))) long" }
        if track.loop { line += " · loops" }
        return line
    }

    /// The name a new voice-over takes: "Voice-over 1", then one more than
    /// the most the design's tracks have reached.
    static func voiceOverName(after tracks: [AudioTrack]) -> String {
        let prefix = "Voice-over "
        let used = tracks.compactMap { track -> Int? in
            guard track.name.hasPrefix(prefix) else { return nil }
            return Int(track.name.dropFirst(prefix.count))
        }
        return prefix + String((used.max() ?? 0) + 1)
    }

    /// A time as a fade shows it: "0.0s" to "5.0s".
    static func secondsLabel(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }

    /// Seconds kept to the tenth the sheet shows.
    static func tenths(_ seconds: Double) -> Double { (seconds * 10).rounded() / 10 }
}

extension DesignStore {

    /// Music `id` as a new track, last in the list, as one step: from
    /// `start` seconds into the film, played once from the file's start at
    /// full volume, called `name` — by the music's own name when that is
    /// empty.
    @discardableResult
    func addAudioTrack(_ id: String, start: Double = 0, name: String = "") -> AudioTrack {
        let track = AudioTrack(src: AudioTrack.src(id), start: AudioTracks.tenths(max(0, start)),
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
        apply { $0.audioTracks.removeAll { $0.id == id } }
    }

    /// Whether Play has anything to show or to hear on this page: its
    /// motion, or the design's tracks.
    var pagePlays: Bool { pageIsAnimated || !design.audioTracks.isEmpty }
}
