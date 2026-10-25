// Photos, clips, animated pictures and sounds whose files are gone — a
// design brought from another phone without them, or a file deleted — said
// as such rather than left a grey box: the canvas draws "Photo missing" or
// "Video missing" over the placeholder (on screen only; an export keeps its
// plain grey), the toolbar opens with "Photo missing · Replace", the design
// opens with "N items are missing from this design", Check accessibility
// and the export nudge have a missingMedia finding with Replace, the Audio
// sheet says "Sound missing · Replace", and VoiceOver hears ", missing"
// after the element's name.
//
// `missing` lists what is gone, in the order of the shared fixture
// missing-media.json (MissingMediaTests, the Android twin's
// MissingMediaTest): page by page, the page's background before its
// elements in layer order, back to front — an element by its picture or
// clip, else by the photo or clip its fill holds (a photo-filled shape is a
// photo) — then the design's audio tracks, in their order, each with no page
// index (null in the fixture) and its track's id. Only a file
// of the design's own counts — "media:", "video:", "anim:" and an "audio:"
// track or a clip's sound ("video:") — never a library picture ("asset:"),
// a loop ("motion:"), a code ("qr:") or a sound or song the app comes with.
// A background's item is named by its page's id.

import Foundation

enum MissingMedia {

    enum MediaKind: String {
        case photo, video, anim, audio, background
    }

    /// One thing whose file is gone.
    struct Absent: Equatable {
        var elementId: String
        /// The page it is on; nil for a sound track, which is no page's.
        var pageIndex: Int?
        var kind: MediaKind
    }

    /// The stored file a source names, unstamped — "media:<id>",
    /// "video:<id>", "anim:<id>" — or nil for a source that is no file of
    /// the design's own.
    static func stored(_ src: String?) -> String? {
        guard let src else { return nil }
        if src.hasPrefix("media:") { return src.count > 6 ? src : nil }
        if let parts = VideoStore.split(src) { return parts.id.isEmpty ? nil : VideoStore.src(parts.id, at: nil) }
        if let parts = AnimStore.split(src) { return parts.id.isEmpty ? nil : AnimStore.src(parts.id, at: nil) }
        return nil
    }

    /// The stored files `el` shows, in the order they are checked: its
    /// own picture or clip, then the photo or clip its fill holds.
    static func sources(of el: Element) -> [String] {
        let fill = el.fill?.kind == "image" ? el.fill?.src : nil
        return [el.src, fill].compactMap { stored($0) }
    }

    /// The first of `el`'s stored files that is in `gone`, or nil.
    static func missingFile(of el: Element, among gone: Set<String>) -> String? {
        sources(of: el).first { gone.contains($0) }
    }

    /// The kind of file a stored source is.
    static func fileKind(_ stored: String) -> MediaKind {
        if VideoStore.isVideo(stored) { return .video }
        if AnimStore.isAnim(stored) { return .anim }
        return .photo
    }

    /// What `design` has whose stored file `exists` says is gone — asked
    /// of each source once, as `stored` writes it, and of a song as
    /// "audio:<id>".
    static func missing(_ design: Design, exists: (String) -> Bool) -> [Absent] {
        var asked: [String: Bool] = [:]
        func gone(_ file: String) -> Bool {
            if let known = asked[file] { return !known }
            let here = exists(file)
            asked[file] = here
            return !here
        }
        var out: [Absent] = []
        for (p, page) in design.pages.enumerated() {
            if case .image(let src) = page.background, let file = stored(src), gone(file) {
                out.append(Absent(elementId: page.id, pageIndex: p, kind: .background))
            }
            for el in page.elements {
                guard let file = sources(of: el).first(where: { gone($0) }) else { continue }
                out.append(Absent(elementId: el.id, pageIndex: p, kind: fileKind(file)))
            }
        }
        for track in design.audioTracks {
            guard let file = trackFile(track), gone(file) else { continue }
            out.append(Absent(elementId: track.id, pageIndex: nil, kind: .audio))
        }
        return out
    }

    /// The file a track plays: "audio:<id>" for a song of the design's own,
    /// its clip's "video:<id>" for a clip's sound; nil for an effect or a
    /// loop the app comes with.
    static func trackFile(_ track: AudioTrack) -> String? {
        if let clip = AudioTrack.videoId(of: track.src) { return VideoStore.src(clip, at: nil) }
        return track.storedAudioId.map { AudioTrack.src($0) }
    }

    /// `el` with `src` in place of its picture that is gone — `gone` holds
    /// the stored sources (`stored`) missing. The picture its fill holds
    /// when that is gone and its own is not, the fill's other keys (its
    /// crop) kept; else its own picture. Everything else is kept — its
    /// crop, frame, filters and alt text — since the picture it was fitted
    /// to is not there to say otherwise. The alt text stays as typed words,
    /// no longer tied to the old picture. The Android twin's
    /// MissingMedia.replaced, held to missing-media.json.
    static func replaced(_ el: Element, src: String, gone: Set<String>) -> Element {
        var out = el
        if out.altTextSource != nil { out.altTextSource = nil }
        let ownGone = stored(el.src).map { gone.contains($0) } ?? false
        let fillFile = el.fill?.kind == "image" ? stored(el.fill?.src) : nil
        let fillGone = fillFile.map { gone.contains($0) } ?? false
        if !ownGone, fillGone {
            out.fill?.src = src
            return out
        }
        out.src = src
        return out
    }

    // MARK: words

    /// "Photo missing", "Video missing" or "Sound missing": an animated
    /// picture is a photo, and so is a background (`saying(background:)`
    /// says one by its file).
    static func saying(_ kind: MediaKind) -> String {
        switch kind {
        case .video: return tr("Video missing")
        case .audio: return tr("Sound missing")
        case .photo, .anim, .background: return tr("Photo missing")
        }
    }

    /// A background's words, by the file it showed: a clip's "Video
    /// missing", any other "Photo missing".
    static func saying(background file: String) -> String {
        saying(fileKind(file))
    }

    /// "Photo missing · Replace", the toolbar's and the Audio sheet's chip.
    static func chipText(_ kind: MediaKind) -> String {
        tr("%@ · Replace", saying(kind))
    }

    /// "3 items are missing from this design".
    static func banner(_ count: Int) -> String {
        trn("%d item is missing from this design|%d items are missing from this design", count)
    }

    /// An element's name as VoiceOver says it when its file is gone.
    static func spoken(_ name: String, missing: Bool) -> String {
        missing ? tr("%@, missing", name) : name
    }
}
