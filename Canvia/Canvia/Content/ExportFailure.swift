// Why an export failed, said plainly, and what to try next — the Android
// twin's ExportFailure, kind for kind. `classify` reads the error a failed
// export threw; each Reason has its message (`reasonText`) and, where there is
// one, a suggestion (`suggestion`): free up space, or try again smaller —
// the same settings with the picture at 1× or the video one quality step
// down.

import AVFoundation
import Foundation

enum ExportFailure {

    /// The kinds of failure, by the key a failure is kept under in JSON.
    enum Reason: String, CaseIterable, Codable {
        /// The phone ran out of space writing the file.
        case noSpace
        /// A pixel or memory cap was hit: the picture or film is too big.
        case tooLarge
        /// The video encoder refused the film.
        case codec
        /// A photo or clip's file is gone.
        case missingMedia
        /// Stopped, by the pill's X.
        case cancelled
        case other

        /// The kind a stored key names; other for one unknown.
        static func of(_ key: String?) -> Reason { Reason.allCases.first { $0.rawValue == key } ?? .other }
    }

    /// The kind of `error`, by the simplest rule both phones can follow:
    /// the error and then each error under it in turn (NSUnderlyingError),
    /// the first that says anything deciding — a cancellation is
    /// cancelled; a message of a size too large ("too large", "exceeds",
    /// "out of memory") is tooLarge; out of space (ENOSPC, "No space left",
    /// Cocoa's out-of-space write) is noSpace; a file not found is
    /// missingMedia; an AVFoundation error, or a message naming an encoder
    /// or codec, is codec. Anything else is other.
    static func classify(_ error: Error?) -> Reason {
        var next: Error? = error
        var depth = 0
        while let e = next, depth < 8 {
            if let kind = kindOf(e) { return kind }
            next = (e as NSError).userInfo[NSUnderlyingErrorKey] as? Error
            depth += 1
        }
        return .other
    }

    private static func kindOf(_ e: Error) -> Reason? {
        if e is CancellationError { return .cancelled }
        let ns = e as NSError
        let said = ns.localizedDescription.lowercased()
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return .cancelled }
        if said.contains("too large") || said.contains("exceeds") || said.contains("out of memory") { return .tooLarge }
        if (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC))
            || (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError)
            || said.contains("enospc") || said.contains("no space left") {
            return .noSpace
        }
        if (ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError))
            || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT)) {
            return .missingMedia
        }
        if ns.domain == AVFoundationErrorDomain || said.contains("encoder") || said.contains("codec") { return .codec }
        if said.contains("not enough space") { return .noSpace }
        return nil
    }

    /// What a failed export says after "Export failed": why, plainly. A
    /// missing photo or clip names the page it is on, `page` counted from
    /// 0, when that is known.
    static func reasonText(_ kind: Reason, page: Int? = nil) -> String {
        switch kind {
        case .noSpace: return tr("There isn't enough space on this phone.")
        case .tooLarge: return tr("It's too large to make at this size.")
        case .codec: return tr("This phone's video encoder couldn't make it.")
        case .missingMedia:
            return page.map { tr("A photo or clip on page %d is missing.", $0 + 1) } ?? tr("A photo or clip is missing.")
        case .cancelled: return tr("Stopped")
        case .other: return tr("Something went wrong.")
        }
    }

    /// The whole line a failed export says: "Export failed. It's too large
    /// to make at this size."
    static func failedText(_ kind: Reason, page: Int? = nil) -> String {
        ExportChoices.failedTitle + ". " + reasonText(kind, page: page)
    }

    /// What a failure without space suggests, above its button to
    /// Settings' Storage.
    static var freeUpSpace: String { tr("Free up space, or clear caches in Settings") }

    /// The buttons every failed export's row and notification offer.
    static var tryAgain: String { tr("Try again") }
    static var retryThese: String { tr("Retry these") }
    static var openSettings: String { tr("Open Settings") }

    /// What an export was asked for with, as far as trying it smaller goes:
    /// its format ("png", "mp4", …, as ExportLast keeps it), the picture's
    /// scale and typed long edge, and a film's long edge.
    struct Asked: Equatable {
        var format: String
        var scale: Double = 1
        var longEdge: Int? = nil
        var maxEdge: Double? = nil
    }

    /// Trying again smaller: what the button says, and the settings the
    /// export is made with instead.
    struct Suggestion: Equatable {
        var label: String
        var settings: Asked
    }

    /// The video formats, whose suggestion is a lower quality.
    static let videoFormats: Set<String> = ["mp4", "gif"]

    /// The formats a picture is drawn for at a scale.
    static let scaledFormats: Set<String> = ["png", "jpg", "pdf", "print", "pptx"]

    /// What a failure of `kind` suggests trying, made with `settings`: only
    /// a picture or film too large, or one the encoder refused — a film one
    /// quality step down ("Try at 1080p"), none below 720p; a picture at 1×
    /// ("Try at 1×") when it was asked for larger, its typed long edge let
    /// go. Nil when there is nothing smaller to try.
    static func suggestion(_ kind: Reason, settings: Asked?) -> Suggestion? {
        guard kind == .tooLarge || kind == .codec, let settings else { return nil }
        if videoFormats.contains(settings.format) {
            let edge = settings.maxEdge ?? MovieExporter.Resolution.standard.maxEdge
            guard let lower = MovieExporter.Resolution.allCases.last(where: { $0.maxEdge < edge }) else { return nil }
            var smaller = settings
            smaller.maxEdge = lower.maxEdge
            return Suggestion(label: tr("Try at %@", lower.rawValue), settings: smaller)
        }
        guard scaledFormats.contains(settings.format), settings.scale > 1 || settings.longEdge != nil else { return nil }
        var smaller = settings
        smaller.scale = 1
        smaller.longEdge = nil
        return Suggestion(label: tr("Try at 1×"), settings: smaller)
    }

    /// A failure as Home keeps a finished export's: its kind and the
    /// designs it was of — one, or a batch's that failed — as
    /// {"kind":"noSpace","designIds":["…"]}.
    struct Failure: Codable, Equatable {
        var kind: Reason
        var designIds: [String] = []

        init(kind: Reason, designIds: [String] = []) {
            self.kind = kind
            self.designIds = designIds
        }

        /// Read leniently: a kind unknown is other, ids not strings are
        /// left out.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = Reason.of(try c.decode(String.self, forKey: .kind))
            let listed: [LenientString]? = try? c.decodeIfPresent([LenientString].self, forKey: .designIds)
            designIds = listed?.compactMap(\.value) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind.rawValue, forKey: .kind)
            try c.encode(designIds, forKey: .designIds)
        }

        private enum CodingKeys: String, CodingKey { case kind, designIds }

        /// One id, or nothing for a value that is not a string.
        private struct LenientString: Decodable {
            var value: String?
            init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(String.self) }
        }
    }

    /// How many failed exports are kept to try again, newest first.
    static let keptCount = 3

    /// `list` with `entry` put first, at most `keptCount` kept.
    static func kept<T>(_ list: [T], _ entry: T) -> [T] {
        Array(([entry] + list).prefix(keptCount))
    }

    /// The first of `pages` (indices of `design`'s pages, in order) with a
    /// photo or clip whose file `exists` says is gone — the page a
    /// missing-media failure names — or nil.
    static func missingPage(_ design: Design, pages: [Int], exists: (String) -> Bool) -> Int? {
        pages.first { i in
            guard design.pages.indices.contains(i) else { return false }
            return design.pages[i].elements.contains { el in el.src.map { !exists($0) } ?? false }
        }
    }
}
