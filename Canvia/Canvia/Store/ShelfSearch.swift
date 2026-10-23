// Home's search finds designs by the words on their pages as well as by
// their titles, and the Type and Edited chips under it narrow the shelf —
// the Android twin's Shelf.searchText, typeOf, snippet, TypeFilter and
// Edited, by the same rules. The words and the type are kept in shelf.json
// ("text", "type"), read as each design's entry is, off the main thread.

import Foundation

extension DesignLibrary {

    // MARK: searching designs' words

    /// How much of a design's words the shelf keeps to search.
    static let searchTextLimit = 4000

    /// `s` lower-cased with its accents taken off, as the twin's Shelf.fold:
    /// decomposed, its combining marks dropped.
    static func fold(_ s: String) -> String {
        let marks = s.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            $0.properties.generalCategory != .nonspacingMark
        }
        return String(String.UnicodeScalarView(marks)).lowercased()
    }

    /// A design's words as the shelf keeps them, to search from Home: the
    /// words of every text box and every shape with words in it, on every
    /// page, in order — neither a hidden element's nor a caption box's, and
    /// no page title or note — markers left out, joined by a space, runs of
    /// spaces and line breaks made one space, lower-cased and accents
    /// stripped, and cut at searchTextLimit UTF-16 units.
    static func searchText(_ design: Design) -> String {
        let words = design.pages.flatMap { page in
            page.elements.filter { el in
                (el.type == .text || ShapeText.words(of: el) != nil) && !el.isHidden && el.captions == nil
            }.map { RichText.strip($0.text ?? "") }
        }
        let folded = fold(words.joined(separator: " "))
        // Java's \s: space, tab, line feed, vertical tab, form feed, return.
        let spaces: Set<Character> = [" ", "\t", "\n", "\u{0B}", "\u{0C}", "\r", "\r\n"]
        var joined = ""
        var lastWasSpace = false
        for ch in folded {
            if spaces.contains(ch) {
                if !lastWasSpace { joined.append(" ") }
                lastWasSpace = true
            } else {
                joined.append(ch)
                lastWasSpace = false
            }
        }
        return utf16Prefix(joined.trimmingCharacters(in: .whitespacesAndNewlines), limit: searchTextLimit)
    }

    /// The first `limit` UTF-16 units of `s`, never splitting a character.
    static func utf16Prefix(_ s: String, limit: Int) -> String {
        guard s.utf16.count > limit else { return s }
        var count = 0
        var out = ""
        for ch in s {
            let n = ch.utf16.count
            if count + n > limit { break }
            out.append(ch)
            count += n
        }
        return out
    }

    /// A design's type, as the shelf keeps it: "whiteboard" for one with an
    /// expanded page; for one measured on paper, the first type defined on
    /// paper of its pixels; else the first type in pixels of exactly its
    /// size; else none.
    static func typeOf(_ design: Design, presets: [SizePreset] = SizePreset.all) -> String? {
        if design.pages.contains(where: Whiteboards.isExpanded) { return Whiteboards.presetId }
        if design.unit != nil,
           let paper = presets.first(where: { $0.unit != nil && $0.w == design.width && $0.h == design.height }) {
            return paper.id
        }
        return presets.first { $0.unit == nil && $0.w == design.width && $0.h == design.height }?.id
    }

    /// Whether a design's words hold `query`, capitals and accents aside —
    /// found after those whose title matches.
    static func matchesText(_ design: RecentDesign, query: String) -> Bool {
        let needle = fold(query.trimmingCharacters(in: .whitespaces))
        return !needle.isEmpty && design.text.contains(needle)
    }

    /// Whether the title or the size matches `query`, as the shelf's
    /// search always has.
    static func matchesTitle(_ d: RecentDesign, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return d.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || "\(Int(d.width))×\(Int(d.height))".contains(needle)
            || "\(Int(d.width))x\(Int(d.height))".contains(needle)
    }

    /// A line of a result found by its words: `start` until `end`, in
    /// UTF-16 units, is the match, to bold.
    struct Snippet: Equatable {
        var text: String
        var start: Int
        var end: Int
    }

    static let snippetReach = 30

    /// Where `query` first is in `text` (a design's shelf words), shown as
    /// "…bake sale on Saturday…": from snippetReach UTF-16 units before the
    /// match, moved on past the first space when that is not the start, to
    /// as many after it, moved back to the last space when that is not the
    /// end. Nil when `query` is not there.
    static func snippet(_ text: String, query: String) -> Snippet? {
        let needle = Array(fold(query.trimmingCharacters(in: .whitespaces)).utf16)
        guard !needle.isEmpty else { return nil }
        let units = Array(text.utf16)
        guard let at = firstIndex(of: needle, in: units) else { return nil }
        let end = at + needle.count
        let space = UInt16(32)
        var from = max(0, at - snippetReach)
        if from > 0, let found = units[from...].firstIndex(of: space), found < at {
            from = found + 1
        }
        var to = min(units.count, end + snippetReach)
        if to < units.count, let found = units[...to].lastIndex(of: space), found >= end {
            to = found
        }
        let lead = from > 0 ? "…" : ""
        let tail = to < units.count ? "…" : ""
        let middle = String(decoding: units[from..<to], as: UTF16.self)
        let leadCount = lead.utf16.count
        return Snippet(text: lead + middle + tail, start: leadCount + at - from, end: leadCount + end - from)
    }

    private static func firstIndex(of needle: [UInt16], in units: [UInt16]) -> Int? {
        guard needle.count <= units.count else { return nil }
        for i in 0...(units.count - needle.count) where units[i] == needle[0] {
            if Array(units[i..<(i + needle.count)]) == needle { return i }
        }
        return nil
    }

    /// The snippet as Text draws it: the match in bold.
    static func attributed(_ snippet: Snippet) -> AttributedString {
        let ns = snippet.text as NSString
        let start = min(max(0, snippet.start), ns.length)
        let end = min(max(start, snippet.end), ns.length)
        var before = AttributedString(ns.substring(to: start))
        var match = AttributedString(ns.substring(with: NSRange(location: start, length: end - start)))
        match.inlinePresentationIntent = .stronglyEmphasized
        before.append(match)
        before.append(AttributedString(ns.substring(from: end)))
        return before
    }

    // MARK: Type and Edited

    /// The Type chips under the search: each the category of the design
    /// types it takes, or the whiteboard. A design of no known type, or of
    /// a Marketing type, shows under All alone.
    enum TypeFilter: String, CaseIterable, Identifiable {
        case all, presentations, social, video, print, documents, whiteboards
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return tr("All")
            case .presentations: return tr("Presentations")
            case .social: return tr("Social")
            case .video: return tr("Video")
            case .print: return tr("Print")
            case .documents: return tr("Documents")
            case .whiteboards: return tr("Whiteboards")
            }
        }

        /// The design types' category it takes; nil for All and Whiteboards.
        var category: String? {
            switch self {
            case .all, .whiteboards: return nil
            case .presentations: return "Presentations"
            case .social: return "Social"
            case .video: return "Video"
            case .print: return "Print"
            case .documents: return "Documents"
            }
        }

        /// Whether `design` shows under it: everything under All, a damaged
        /// design under each; a whiteboard under Whiteboards alone; else a
        /// design whose type is of its category.
        func admits(_ design: RecentDesign) -> Bool {
            if self == .all || design.damaged { return true }
            if design.type == Whiteboards.presetId { return self == .whiteboards }
            if self == .whiteboards { return false }
            guard let type = design.type, let preset = SizePreset.byId(type) else { return false }
            return preset.category == category
        }
    }

    /// The Edited chips under the search.
    enum Edited: String, CaseIterable, Identifiable {
        case any, today, week, month, older
        var id: String { rawValue }

        var label: String {
            switch self {
            case .any: return tr("Any time")
            case .today: return tr("Today")
            case .week: return tr("Past 7 days")
            case .month: return tr("Past 30 days")
            case .older: return tr("Older")
            }
        }

        /// Whether `design`, last edited at its updatedAt, shows under it:
        /// Today from `startOfToday` (local midnight); Past 7 and Past 30
        /// days from that many whole days before `now`; Older before 30
        /// days; a damaged design under each. Times in epoch milliseconds.
        func admits(_ design: RecentDesign, now: Double, startOfToday: Double) -> Bool {
            if design.damaged { return true }
            let t = design.updatedAt
            switch self {
            case .any: return true
            case .today: return t >= startOfToday
            case .week: return t >= now - 7 * DesignLibrary.dayMillis
            case .month: return t >= now - 30 * DesignLibrary.dayMillis
            case .older: return t < now - 30 * DesignLibrary.dayMillis
            }
        }
    }

    static let dayMillis = 24.0 * 3600 * 1000

    /// The designs in a folder (nil is every folder) of `type` and edited
    /// `edited` that match `query`, in `sort` order: those whose title or
    /// size matches first, then those found by their words alone, each in
    /// `sort` order.
    static func filter(_ designs: [RecentDesign], query: String, sort: Sort, folder: String?,
                       type: TypeFilter, edited: Edited, now: Double, startOfToday: Double) -> [RecentDesign] {
        let inView = designs.filter { d in
            (folder == nil || d.folder == folder) && type.admits(d)
                && edited.admits(d, now: now, startOfToday: startOfToday)
        }
        let byTitle = inView.filter { matchesTitle($0, query: query) }
        let blank = query.trimmingCharacters(in: .whitespaces).isEmpty
        let byText = blank ? [] : inView.filter { !matchesTitle($0, query: query) && matchesText($0, query: query) }
        return filter(byTitle, query: "", sort: sort) + filter(byText, query: "", sort: sort)
    }

    /// Local midnight before `now`, in epoch milliseconds.
    static func startOfDay(_ now: Date = Date(), calendar: Calendar = .current) -> Double {
        calendar.startOfDay(for: now).timeIntervalSince1970 * 1000
    }
}
