// Document model. Value types throughout: the whole design is a struct, so
// undo/redo snapshots are plain copies. JSON keys match the Canvia web
// schema so the validated template gallery decodes verbatim.

import SwiftUI
import UIKit

enum UID {
    static func make(_ prefix: String = "el") -> String {
        "\(prefix)_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    }
}

// MARK: - Paint (solid or linear gradient)

struct GradientStop: Codable, Equatable, Hashable {
    var offset: Double
    var color: String
}

struct Paint: Codable, Equatable, Hashable {
    var kind: String              // "solid" | "gradient" | "pattern" | "image"
    var color: String?            // solid; pattern foreground
    var angle: Double?            // gradient, CSS convention: 0° = up, 90° = right
    var stops: [GradientStop]?
    /// gradient: "linear" (nil) | "radial" | "angular".
    var gradientKind: String?
    /// pattern: which one (see Patterns.names), its background, and its
    /// tile size in page units.
    var pattern: String?
    var secondary: String?
    var scale: Double?
    /// image: a photo source, "asset:…" or "media:…", filling the shape.
    var src: String?

    static func solid(_ color: String) -> Paint {
        Paint(kind: "solid", color: color, angle: nil, stops: nil)
    }

    /// No fill at all: an outline, a drawn stroke. Not called `none`, which
    /// on an optional fill would read as nil.
    static let clear = Paint(kind: "none", color: nil, angle: nil, stops: nil)

    static func pattern(_ name: String, color: String, secondary: String, scale: Double = 24) -> Paint {
        Paint(kind: "pattern", color: color, angle: nil, stops: nil,
              pattern: name, secondary: secondary, scale: scale, src: nil)
    }

    static func image(_ src: String) -> Paint {
        Paint(kind: "image", color: nil, angle: nil, stops: nil, pattern: nil, secondary: nil, scale: nil, src: src)
    }

    var primaryColor: String {
        if kind == "gradient" { return stops?.first?.color ?? "#000000" }
        return color ?? "#000000"
    }

    /// SwiftUI gradient endpoints for the CSS angle convention, in unit space.
    var unitPoints: (start: UnitPoint, end: UnitPoint) {
        let rad = ((angle ?? 0) - 90) * .pi / 180
        let dx = cos(rad) / 2, dy = sin(rad) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    var swiftUIStops: [Gradient.Stop] {
        (stops ?? []).map { .init(color: Color(hex: $0.color), location: $0.offset) }
    }

    /// The gradient as a ShapeStyle: linear along the angle, radial from the
    /// centre out to the edges, or angular sweeping from the angle.
    func gradientStyle() -> AnyShapeStyle {
        switch gradientKind {
        case "radial":
            return AnyShapeStyle(EllipticalGradient(stops: swiftUIStops, center: .center,
                                                    startRadiusFraction: 0, endRadiusFraction: 0.5))
        case "angular":
            return AnyShapeStyle(AngularGradient(stops: swiftUIStops, center: .center,
                                                 angle: .degrees((angle ?? 0) - 90)))
        default:
            let pts = unitPoints
            return AnyShapeStyle(LinearGradient(stops: swiftUIStops, startPoint: pts.start, endPoint: pts.end))
        }
    }

    @ViewBuilder
    func fillView() -> some View {
        if kind == "gradient", stops != nil {
            Rectangle().fill(gradientStyle())
        } else if kind == "pattern" {
            PatternFill(paint: self)
        } else if kind == "image", let ui = PhotoLibrary.resolve(src) {
            Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
        } else {
            Color(hex: color ?? "#000000")
        }
    }
}

// MARK: - Background

enum Background: Codable, Equatable {
    case color(String)
    case gradient(Paint)
    case image(String)            // "asset:<photo id>" or user image key

    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "gradient": self = .gradient(try c.decode(Paint.self, forKey: .value))
        case "image": self = .image(try c.decode(String.self, forKey: .value))
        default: self = .color((try? c.decode(String.self, forKey: .value)) ?? "#ffffff")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .color(let v):
            try c.encode("color", forKey: .type)
            try c.encode(v, forKey: .value)
        case .gradient(let p):
            try c.encode("gradient", forKey: .type)
            try c.encode(p, forKey: .value)
        case .image(let v):
            try c.encode("image", forKey: .type)
            try c.encode(v, forKey: .value)
        }
    }
}

// MARK: - Page / Design

struct Page: Codable, Equatable, Identifiable {
    var id: String = UID.make("page")
    var background: Background = .color("#ffffff")
    var elements: [Element] = []
    /// Speaker or production notes. Never drawn on the page — they are about
    /// the page, not on it — so nothing that renders reads this.
    var notes: String?
    /// How long this page holds in a video or presentation; nil is the
    /// document's setting.
    var holdSeconds: Double?
    /// How this page gives way to the next: "fade" | "cut" | "slide" |
    /// "push" | "wipe" | "circle" | "zoom"; nil is the document's setting.
    /// Kept as written, so a kind from a newer build survives a save here.
    var transition: String?
    /// How long that takes, in seconds, kept to PageTransitions.secondsRange
    /// where it is used; nil is the usual timing.
    var transitionSeconds: Double?
    /// Whether the master page shows behind this one; nil is yes.
    var usesMaster: Bool?
    /// This page's own size, when it differs from the document's — a story
    /// page after a square post. nil is the document's size.
    var width: Double?
    var height: Double?
    /// Left out of Present and of "All pages" in an export; nil is shown.
    /// The page is still edited, saved, numbered and drawn as a master like
    /// any other — only showing it is skipped. Never false: shown is nil, so
    /// the key is written only when true, as `usesMaster` only when false.
    var hidden: Bool?
    /// The page's own name — "Intro", "Agenda" — for finding it in a long
    /// deck; nil is untitled. Like the notes, never drawn on the page and
    /// never in an export. Kept trimmed and at most PageTitles.maxLength
    /// characters by the sheet that edits it.
    var title: String?
    /// Locked whole: nothing on it, its background included, can be
    /// selected, moved, added to or deleted until it is unlocked — a
    /// finished page in a long deck kept as it is (see PageLocks). Still
    /// shown, exported, copied and duplicated like any other page, a copy
    /// locked too. Never false: unlocked is nil, so the key is written only
    /// when true, as `hidden` is.
    var locked: Bool?

    init(id: String = UID.make("page"), background: Background = .color("#ffffff"),
         elements: [Element] = [], notes: String? = nil) {
        self.id = id
        self.background = background
        self.elements = elements
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UID.make("page")
        background = (try? c.decode(Background.self, forKey: .background)) ?? .color("#ffffff")
        elements = (try? c.decode([Element].self, forKey: .elements)) ?? []
        notes = try? c.decode(String.self, forKey: .notes)
        holdSeconds = try? c.decode(Double.self, forKey: .holdSeconds)
        transition = try? c.decode(String.self, forKey: .transition)
        transitionSeconds = try? c.decode(Double.self, forKey: .transitionSeconds)
        usesMaster = try? c.decode(Bool.self, forKey: .usesMaster)
        width = try? c.decode(Double.self, forKey: .width)
        height = try? c.decode(Double.self, forKey: .height)
        hidden = (try? c.decode(Bool.self, forKey: .hidden)) == true ? true : nil
        title = (try? c.decode(String.self, forKey: .title)).flatMap(PageTitles.kept)
        locked = (try? c.decode(Bool.self, forKey: .locked)) == true ? true : nil
    }

    /// As the synthesised encoder wrote it, except that `hidden` and
    /// `locked` are written only when true and `title` only when there is
    /// one — a page shown, unlocked and untitled reads exactly as it did
    /// before any of them existed, on this phone and the Android twin alike.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(background, forKey: .background)
        try c.encode(elements, forKey: .elements)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(holdSeconds, forKey: .holdSeconds)
        try c.encodeIfPresent(transition, forKey: .transition)
        try c.encodeIfPresent(transitionSeconds, forKey: .transitionSeconds)
        try c.encodeIfPresent(usesMaster, forKey: .usesMaster)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
        if hidden == true { try c.encode(true, forKey: .hidden) }
        if let title = title.flatMap(PageTitles.kept) { try c.encode(title, forKey: .title) }
        if locked == true { try c.encode(true, forKey: .locked) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, background, elements, notes, holdSeconds, transition, usesMaster, width, height
        case hidden, title, transitionSeconds, locked
    }
}

/// A vertical or horizontal line to line things up against, in page units.
struct Guide: Codable, Equatable, Identifiable {
    var id: String = UID.make("guide")
    var vertical: Bool
    var position: Double
}

/// How a design plays as a video or GIF. Saved with the design, because a
/// deck timed for a trade-show loop should still be timed that way next
/// week.
struct MotionSettings: Codable, Equatable {
    var secondsPerPage: Double = 2.5
    var fps: Int = 30
    /// The slow push-in on each page.
    var movement: Bool = true
    /// Cross-fade between pages; off is a hard cut.
    var crossfade: Bool = true
    // The one soundtrack a design used to have, `soundtrack` and
    // `soundVolume`, is read by Design as its first audio track and never
    // written here again (see AudioTrack.migrated).

    static let fpsChoices = [24, 30, 60]
    static let secondsRange = 0.5...10.0
    /// A page's own hold can be longer than the document's, to play a clip
    /// on it through.
    static let pageHoldRange = 0.5...60.0
}

/// How Present plays the design, kept with it so a kiosk keeps it: written
/// as {"loop": true} only while looping is on, and left out otherwise, so
/// every other design reads and writes as before on both phones.
struct PresentSettings: Codable, Equatable {
    /// At the end of the last page shown, go round to the first.
    var loop = false

    init(loop: Bool = false) {
        self.loop = loop
    }

    private enum CodingKeys: String, CodingKey { case loop }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        loop = (try? c.decode(Bool.self, forKey: .loop)) ?? false
    }
}

/// One sound under the design's film — a song, a voice-over — as the Audio
/// sheet sets it. `src` names its file, "audio:<AudioStore id>"; `start` is
/// where it comes in, in seconds into the film; `trimStart` and `trimEnd`
/// the part of the file it plays, nil being to the file's end; `volume`
/// 0...1; `fadeIn` and `fadeOut` in seconds; `loop` goes round again until
/// the film ends; `name` is what the sheet calls it. Written as one of the
/// design's `audio` array, with the Android twin's keys; each read
/// leniently, as a clip's are, and a track with no "audio:" source is none.
struct AudioTrack: Codable, Equatable, Identifiable {
    var id: String = UID.make("track")
    var src: String
    var start: Double = 0
    var trimStart: Double = 0
    var trimEnd: Double?
    var volume: Double = 1
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var loop: Bool = false
    var name: String = ""

    static let prefix = "audio:"
    /// What the sheet offers a fade, and what the mix plays one within.
    static let fadeRange = 0.0...5.0
    /// The shortest a trim leaves a track, in seconds, as a clip's.
    static let minLength = 0.1
    /// How long the old soundtrack faded out over at the film's end, which
    /// its track keeps (Soundtrack.fadeSeconds).
    static let migratedFadeOut = 1.0
    /// The old soundtrack's track's id and name — fixed, so the same old
    /// design reads as the same track on either phone, and on every read.
    static let migratedId = "soundtrack"
    static let migratedName = "Soundtrack"

    /// The AudioStore id the track plays, or nil for a source that is not
    /// one.
    var audioId: String? {
        guard src.hasPrefix(Self.prefix) else { return nil }
        let id = String(src.dropFirst(Self.prefix.count))
        return id.isEmpty ? nil : id
    }

    static func src(_ id: String) -> String { prefix + id }

    init(id: String = UID.make("track"), src: String, start: Double = 0, trimStart: Double = 0,
         trimEnd: Double? = nil, volume: Double = 1, fadeIn: Double = 0, fadeOut: Double = 0,
         loop: Bool = false, name: String = "") {
        self.id = id
        self.src = src
        self.start = start
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.volume = volume
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.loop = loop
        self.name = name
    }

    /// The old single soundtrack as a track: from the film's start, looping
    /// to its end at its volume, fading out over the last second as it did —
    /// so its sound is what it was — with the Android twin's fixed id and
    /// name, "Soundtrack".
    static func migrated(soundtrack id: String, volume: Double?) -> AudioTrack {
        AudioTrack(id: migratedId, src: src(id), volume: min(max(volume ?? 1, 0), 1), fadeOut: migratedFadeOut,
                   loop: true, name: migratedName)
    }

    private enum CodingKeys: String, CodingKey {
        case id, src, start, trimStart, trimEnd, volume, fadeIn, fadeOut, loop, name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        src = try c.decode(String.self, forKey: .src)
        guard src.hasPrefix(Self.prefix), src.count > Self.prefix.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Not an audio track"))
        }
        // One with no id of its own goes by its source, as on Android: the
        // same file reads as the same track each time.
        let own = try? c.decodeIfPresent(String.self, forKey: .id)
        id = own.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? src
        start = (try? c.decodeIfPresent(Double.self, forKey: .start)) ?? 0
        trimStart = (try? c.decodeIfPresent(Double.self, forKey: .trimStart)) ?? 0
        trimEnd = try? c.decodeIfPresent(Double.self, forKey: .trimEnd)
        volume = (try? c.decodeIfPresent(Double.self, forKey: .volume)) ?? 1
        fadeIn = (try? c.decodeIfPresent(Double.self, forKey: .fadeIn)) ?? 0
        fadeOut = (try? c.decodeIfPresent(Double.self, forKey: .fadeOut)) ?? 0
        loop = (try? c.decodeIfPresent(Bool.self, forKey: .loop)) ?? false
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }

    /// Every key but `trimEnd`, which is written only when the track stops
    /// short of its file's end.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(src, forKey: .src)
        try c.encode(start, forKey: .start)
        try c.encode(trimStart, forKey: .trimStart)
        try c.encodeIfPresent(trimEnd, forKey: .trimEnd)
        try c.encode(volume, forKey: .volume)
        try c.encode(fadeIn, forKey: .fadeIn)
        try c.encode(fadeOut, forKey: .fadeOut)
        try c.encode(loop, forKey: .loop)
        try c.encode(name, forKey: .name)
    }

    /// One track of an `audio` array: none, rather than the whole array,
    /// for one that does not read.
    struct IfReadable: Decodable {
        var track: AudioTrack?

        init(from decoder: Decoder) throws {
            track = try? AudioTrack(from: decoder)
        }
    }
}

struct Design: Codable, Equatable, Identifiable {
    var version: Int = 1
    var id: String = UID.make("doc")
    var title: String = "Untitled design"
    var width: Double = 1080
    var height: Double = 1080
    var createdAt: Double = Date().timeIntervalSince1970 * 1000
    var updatedAt: Double = Date().timeIntervalSince1970 * 1000
    var pages: [Page] = [Page()]
    var motion: MotionSettings?
    /// The page whose elements show behind every other page that uses the
    /// master — a header, a footer, a logo in the corner, drawn once.
    var masterPageId: String?
    /// Draggable alignment guides, in page units, kept with the design.
    var guides: [Guide] = []
    /// The folder on the home screen this design is filed under, if any.
    var folder: String?
    /// True while the title is still one an app chose, so the Android twin
    /// may keep improving it — from "Poster" to the design's own headline.
    /// Cleared for good the first time a person renames the design, on either
    /// platform.
    ///
    /// Carried here even though this app never renames anything itself:
    /// without it, a save on iOS silently dropped the field, and a design
    /// renamed on Android came back from the iPhone renaming itself again.
    var titleAuto: Bool = true
    /// The fonts of your own the texts are set in — {"id": "custom:<sha12>",
    /// "name", "file"} each — so a phone without one can still name it (see
    /// CustomFonts). Nil, and not written, when there are none; brought up
    /// to date by every save.
    var fonts: [CustomFonts.Record]?
    /// The unit the design is measured in: "mm", "cm" or "in"; nil is
    /// pixels, and a design in pixels never writes the key. Only how its
    /// size is read and printed — pages and elements stay in pixels.
    var unit: String?
    /// Its pixels per inch; nil is 96, what every design was drawn at before
    /// units. Written with a physical unit, at 300 for a size typed in one.
    var dpi: Double?
    /// The print bleed round every page, in page units — "Show print
    /// bleed", the Android twin's `bleed`. Nil, and not written, is no
    /// bleed: a design written before it, or with it turned off, prints as
    /// it always did (see Bleed). Never 0 or less.
    var bleed: Double?
    /// The sound under the film, in the order the Audio sheet lists it. Nil,
    /// and not written, when there is none. A design from before tracks
    /// reads its soundtrack in as the one track (AudioTrack.migrated).
    var audio: [AudioTrack]?
    /// Starred on Home: true, or nil and not written — so a file from
    /// before stars, or from a build that has none, reads as it did.
    var starred: Bool?
    /// The words the spelling check's Ignore has passed over in this
    /// design, lower-cased and sorted; nil, and not written, when there
    /// are none (see Proofreader.ignoring).
    var spellIgnore: [String]?
    /// The design's language, BCP-47 ("en-GB"), which the spelling check,
    /// Read aloud and dictation follow; nil, and not written, is the
    /// phone's own.
    var language: String?

    /// How Present plays it; nil, and not written, is as it always played.
    var present: PresentSettings?

    /// Whether Present goes round from the last page shown to the first;
    /// turning it off takes the key away.
    var presentLoops: Bool {
        get { present?.loop == true }
        set { present = newValue ? PresentSettings(loop: true) : nil }
    }

    /// Whether the design is starred; unstarring takes the key away.
    var isStarred: Bool {
        get { starred == true }
        set { starred = newValue ? true : nil }
    }

    /// The tracks, none as an empty list; setting none takes the key away.
    var audioTracks: [AudioTrack] {
        get { audio ?? [] }
        set { audio = newValue.isEmpty ? nil : newValue }
    }

    var size: CGSize { CGSize(width: width, height: height) }

    /// A page's size: its own when it has one, else the document's.
    func size(for page: Page) -> CGSize {
        CGSize(width: page.width ?? width, height: page.height ?? height)
    }

    func size(at index: Int) -> CGSize {
        pages.indices.contains(index) ? size(for: pages[index]) : size
    }

    /// Whether any page has a size of its own.
    var hasMixedPageSizes: Bool { pages.contains { $0.width != nil || $0.height != nil } }

    /// The pages Present shows and "All pages" exports, by index, in order:
    /// every page not hidden. By index rather than as a filtered copy, so a
    /// hidden master page still draws behind the pages that use it.
    var visiblePageIndices: [Int] { pages.indices.filter { pages[$0].hidden != true } }

    init(title: String = "Untitled design", width: Double = 1080, height: Double = 1080) {
        self.title = title
        self.width = width
        self.height = height
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        id = (try? c.decode(String.self, forKey: .id)) ?? UID.make("doc")
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled design"
        width = (try? c.decode(Double.self, forKey: .width)) ?? 1080
        height = (try? c.decode(Double.self, forKey: .height)) ?? 1080
        createdAt = (try? c.decode(Double.self, forKey: .createdAt)) ?? Date().timeIntervalSince1970 * 1000
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? createdAt
        let pages = (try? c.decode([Page].self, forKey: .pages)) ?? []
        self.pages = pages.isEmpty ? [Page()] : pages
        motion = try? c.decode(MotionSettings.self, forKey: .motion)
        masterPageId = try? c.decode(String.self, forKey: .masterPageId)
        guides = (try? c.decode([Guide].self, forKey: .guides)) ?? []
        folder = try? c.decode(String.self, forKey: .folder)
        titleAuto = (try? c.decode(Bool.self, forKey: .titleAuto)) ?? true
        let records = (try? c.decode([CustomFonts.Lenient].self, forKey: .fonts))?.compactMap(\.record) ?? []
        fonts = records.isEmpty ? nil : records
        // "px" is pixels, as no key is: kept as none, so the file reads as
        // it would have.
        unit = (try? c.decode(String.self, forKey: .unit)).flatMap { $0 == "px" ? nil : $0 }
        dpi = (try? c.decode(Double.self, forKey: .dpi)).flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        bleed = (try? c.decode(Double.self, forKey: .bleed)).flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        starred = (try? c.decode(Bool.self, forKey: .starred)) == true ? true : nil
        // Each word on its own: one that is not a string is passed over.
        let words = (try? c.decode([Proofreader.LenientWord].self, forKey: .spellIgnore))?.compactMap(\.word) ?? []
        let ignored = Proofreader.tidied(words)
        spellIgnore = ignored.isEmpty ? nil : ignored
        language = Proofreader.languageTag(try? c.decode(String.self, forKey: .language))
        present = (try? c.decode(PresentSettings.self, forKey: .present)).flatMap { $0.loop ? $0 : nil }
        let tracks = (try? c.decode([AudioTrack.IfReadable].self, forKey: .audio))?.compactMap(\.track) ?? []
        audio = tracks.isEmpty ? nil : tracks
        // The old soundtrack, read forever: the one track of a file with no
        // `audio` key, and passed over beside one that has it. Never written
        // back, as `motion` no longer has it.
        if audio == nil, let old = try? c.decode(LegacySound.self, forKey: .motion),
           let id = old.soundtrack, !id.isEmpty {
            audio = [AudioTrack.migrated(soundtrack: id, volume: old.soundVolume)]
        }
    }

    /// The soundtrack keys `motion` had before audio tracks.
    private struct LegacySound: Decodable {
        var soundtrack: String?
        var soundVolume: Double?

        private enum CodingKeys: String, CodingKey { case soundtrack, soundVolume }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            soundtrack = try? c.decodeIfPresent(String.self, forKey: .soundtrack)
            soundVolume = try? c.decodeIfPresent(Double.self, forKey: .soundVolume)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, title, width, height, createdAt, updatedAt, pages, motion, masterPageId, guides, folder
        case titleAuto, fonts, unit, dpi, bleed, audio, starred, spellIgnore, language, present
    }

    /// The master page, if one is set and still exists.
    var masterPage: Page? {
        guard let id = masterPageId else { return nil }
        return pages.first { $0.id == id }
    }

    /// The elements drawn behind `page` from the master: none on the master
    /// itself, none on a page that opted out, and none hidden.
    func masterElements(behind page: Page) -> [Element] {
        guard let master = masterPage, master.id != page.id, page.usesMaster != false else { return [] }
        return master.elements.filter { !$0.isHidden }
    }

    /// Everything drawn on `page`, back to front: the master's behind, then
    /// the page's own — hidden elements left out. What every renderer,
    /// exporter, link, voice and sound reads.
    func drawnElements(on page: Page) -> [Element] {
        masterElements(behind: page) + page.elements.filter { !$0.isHidden }
    }

    /// Grow any text box that is shorter than the text actually needs.
    ///
    /// Template specs carry no height (the decoder estimates one from the
    /// line count), and large display faces have leading beyond
    /// fontSize x lineHeight — so without this the last line clips. Only
    /// grows, never shrinks, so hand-sized boxes are left alone.
    mutating func normalizeTextHeights() {
        for p in pages.indices {
            for i in pages[p].elements.indices where pages[p].elements[i].type == .text {
                let measured = FontLibrary.layoutHeight(for: pages[p].elements[i])
                if measured > pages[p].elements[i].h {
                    pages[p].elements[i].h = measured
                }
            }
        }
    }
}

// MARK: - Color hex helpers

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        if s.count == 8 {
            self.init(
                red: CGFloat((value >> 24) & 0xff) / 255,
                green: CGFloat((value >> 16) & 0xff) / 255,
                blue: CGFloat((value >> 8) & 0xff) / 255,
                alpha: CGFloat(value & 0xff) / 255)
        } else {
            self.init(
                red: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: 1)
        }
    }

    /// sRGB components clamped to 0...1 (ColorPicker often yields extended
    /// sRGB / Display-P3 values outside the unit range).
    var srgbComponents: (r: CGFloat, g: CGFloat, b: CGFloat) {
        var color = self
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil) {
            color = UIColor(cgColor: converted)
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (min(1, max(0, r)), min(1, max(0, g)), min(1, max(0, b)))
    }

    var hexString: String {
        let c = srgbComponents
        return String(format: "#%02x%02x%02x",
                      Int(round(c.r * 255)), Int(round(c.g * 255)), Int(round(c.b * 255)))
    }

    var isLight: Bool {
        let c = srgbComponents
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.62
    }
}
