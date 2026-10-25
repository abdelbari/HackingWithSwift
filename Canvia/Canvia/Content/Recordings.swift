// Present and record's talks, kept with the design under "recordings",
// newest first and at most `limit` — the same JSON on both phones (the
// Android twin keeps them among its design's extras, written out as this
// same top-level key):
//
//     {"id": "rec_x", "createdAt": ms, "audio": "rec_x.m4a",
//      "camera": "rec_x.mp4" | null,
//      "bubble": {"corner": "bottomLeft", "size": 0.22, "shape": "circle"},
//      "pages": [{"pageId": "p1", "start": 0.0, "end": 12.4}],
//      "captions": [{"start": 0.4, "end": 2.1, "text": "Hello"}]}
//
// `captions` — Burn in captions, only when ticked and heard — are the words
// said, timed from the talk's start, burnt into the talk's film
// (RecordingPlan.film) and written beside it as an .srt.
// The voice is music of the design's (AudioStore's "rec_x.m4a"), the camera
// a clip of its own (VideoStore's "rec_x", an .mp4), so both travel in a
// design file, a backup and a version as its music and clips do. A
// recording whose camera did not come with it plays without its bubble.

import Foundation

/// The camera bubble: its corner, its diameter as a share of the video's
/// shorter side, and its shape.
struct RecordingBubble: Codable, Equatable {
    var corner = "bottomLeft"
    var size = 0.22
    var shape = "circle"

    static let corners = ["topLeft", "topRight", "bottomLeft", "bottomRight"]
    static let shapes = ["circle", "rounded"]

    init(corner: String = "bottomLeft", size: Double = 0.22, shape: String = "circle") {
        self.corner = corner
        self.size = size
        self.shape = shape
    }

    /// A corner or shape this build does not know reads as the default; a
    /// size is kept to 0.1…0.5.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let corner = (try? c.decode(String.self, forKey: .corner)) ?? ""
        self.corner = Self.corners.contains(corner) ? corner : "bottomLeft"
        let size = (try? c.decode(Double.self, forKey: .size)).flatMap { $0.isFinite ? $0 : nil } ?? 0.22
        self.size = min(max(size, 0.1), 0.5)
        let shape = (try? c.decode(String.self, forKey: .shape)) ?? ""
        self.shape = Self.shapes.contains(shape) ? shape : "circle"
    }

    private enum CodingKeys: String, CodingKey { case corner, size, shape }

    /// "Bottom left": what the review sheet says of a corner.
    static func name(_ corner: String) -> String {
        switch corner {
        case "topLeft": return tr("Top left")
        case "topRight": return tr("Top right")
        case "bottomRight": return tr("Bottom right")
        default: return tr("Bottom left")
        }
    }
}

/// A page up from `start` to `end` seconds into the talk.
struct RecordingSpan: Codable, Equatable {
    var pageId: String
    var start: Double
    var end: Double
}

struct Recording: Codable, Equatable, Identifiable {
    var id: String
    /// When it was made, in epoch milliseconds, written whole.
    var createdAt: Double
    var audio: String
    var camera: String?
    var bubble = RecordingBubble()
    var pages: [RecordingSpan] = []
    /// The words said, burnt into its film; none unless asked for.
    var captions: [CaptionCue] = []

    init(id: String, createdAt: Double, audio: String, camera: String?,
         bubble: RecordingBubble = RecordingBubble(), pages: [RecordingSpan] = [], captions: [CaptionCue] = []) {
        self.id = id
        self.createdAt = createdAt
        self.audio = audio
        self.camera = camera
        self.bubble = bubble
        self.pages = pages
        self.captions = captions
    }

    /// One without an id or a voice does not read; a span that does not,
    /// or ends before it starts, is passed over.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        audio = try c.decode(String.self, forKey: .audio)
        createdAt = ((try? c.decode(Double.self, forKey: .createdAt)) ?? 0).rounded()
        camera = (try? c.decodeIfPresent(String.self, forKey: .camera)).flatMap { $0 }
        bubble = (try? c.decode(RecordingBubble.self, forKey: .bubble)) ?? RecordingBubble()
        let spans = (try? c.decode([Lossy<RecordingSpan>].self, forKey: .pages))?.compactMap(\.value) ?? []
        pages = spans.filter { $0.end > $0.start && $0.start.isFinite && $0.end.isFinite }
        let cues = (try? c.decode([Lossy<CaptionCue>].self, forKey: .captions))?.compactMap(\.value) ?? []
        captions = cues.filter { $0.end > $0.start && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Keys in the twin's order, the camera written as null when there is
    /// none, the time whole, and captions only when it has some.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(Int64(createdAt.rounded()), forKey: .createdAt)
        try c.encode(audio, forKey: .audio)
        if let camera { try c.encode(camera, forKey: .camera) } else { try c.encodeNil(forKey: .camera) }
        try c.encode(bubble, forKey: .bubble)
        try c.encode(pages, forKey: .pages)
        if !captions.isEmpty { try c.encode(captions, forKey: .captions) }
    }

    private enum CodingKeys: String, CodingKey { case id, createdAt, audio, camera, bubble, pages, captions }

    /// How long the talk is: the last page's end.
    var duration: Double { pages.map(\.end).max() ?? 0 }

    /// The camera clip's id in VideoStore: its file's name without the
    /// extension.
    var cameraId: String? {
        guard let camera else { return nil }
        let id = (camera as NSString).deletingPathExtension
        return id.trimmingCharacters(in: .whitespaces).isEmpty ? nil : id
    }
}

enum Recordings {

    /// The most a design keeps; a new one past it lets the oldest go.
    static let limit = 5

    /// A new recording's id, "rec_<…>", and its files' names.
    static func newId() -> String { UID.make("rec") }

    static func audioFile(_ id: String) -> String { "\(id).m4a" }

    static func cameraFile(_ id: String) -> String { "\(id).mp4" }

    static func of(_ design: Design) -> [Recording] { design.recordings ?? [] }

    /// `design` with these recordings — no key at all for none.
    static func with(_ design: Design, _ recordings: [Recording]) -> Design {
        var out = design
        out.recordings = recordings.isEmpty ? nil : recordings
        return out
    }

    /// `design` with `recording` first — in place of one with its id, as a
    /// Re-record keeps its place first — and only the newest `limit` kept.
    static func added(_ design: Design, _ recording: Recording) -> Design {
        with(design, Array(([recording] + of(design).filter { $0.id != recording.id }).prefix(limit)))
    }

    /// `design` without recording `id`.
    static func without(_ design: Design, _ id: String) -> Design {
        with(design, of(design).filter { $0.id != id })
    }

    /// The bubble of recording `id` changed.
    static func withBubble(_ design: Design, _ id: String, _ bubble: RecordingBubble) -> Design {
        with(design, of(design).map { r in
            guard r.id == id else { return r }
            var changed = r
            changed.bubble = bubble
            return changed
        })
    }

    /// The AudioStore ids the design's talks use.
    static func audioIds(_ design: Design) -> Set<String> { Set(of(design).map(\.audio)) }

    /// The VideoStore ids of their camera clips.
    static func cameraIds(_ design: Design) -> Set<String> { Set(of(design).compactMap(\.cameraId)) }

    /// Each talk pointed at where its files were stored as a design file
    /// was read: its voice by `audio` (old music id to new), its camera by
    /// `video` (old clip id to new) — the camera written as the new id's
    /// .mp4.
    static func remapped(_ design: Design, audio: [String: String], video: [String: String]) -> Design {
        let all = of(design)
        guard all.contains(where: { audio[$0.audio] != nil || ($0.cameraId.map { video[$0] != nil } ?? false) }) else {
            return design
        }
        return with(design, all.map { r in
            var moved = r
            moved.audio = audio[r.audio] ?? r.audio
            if let old = r.cameraId, let new = video[old] { moved.camera = cameraFile(new) }
            return moved
        })
    }

    /// Each talk's pages renamed by `pageIds` (old page id to new), as a
    /// design's pages are when it is copied or read from a file, so a talk
    /// still plays over the pages it was given on; a span whose page is not
    /// among them goes. The Android twin's Recordings.withPageIds.
    static func withPageIds(_ design: Design, _ pageIds: [String: String]) -> Design {
        let all = of(design)
        guard !all.isEmpty else { return design }
        return with(design, all.map { r -> Recording in
            var moved = r
            moved.pages = r.pages.compactMap { span -> RecordingSpan? in
                guard let new = pageIds[span.pageId] else { return nil }
                var renamed = span
                renamed.pageId = new
                return renamed
            }
            return moved
        })
    }

    /// "Talk, 1:05": what the review sheet calls a recording.
    static func label(_ r: Recording) -> String { tr("Talk, %@", Presenter.clockText(r.duration)) }
}
