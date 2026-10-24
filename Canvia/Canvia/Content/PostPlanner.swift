// Plan a post: a reminder at a time, with the caption and the file ready —
// Canva's Content Planner without the accounts. Nothing is exported in
// advance: the file is made when the reminder's Share now is tapped, so
// edits made meanwhile go with it. The Android twin's PostPlanner.
//
// Kept in the design as both phones write it, and so carried by a backup
// with the design: "plannedPosts": [{"id", "at", "caption", "format",
// "pages", "done"}] — `at` an ISO 8601 instant in UTC to the second
// ("2026-11-02T09:30:00Z"), `format` an export format (ExportLast.formats),
// `pages` the page ids to post (empty for every shown page), `done` whether
// it was marked done. A design with none has no key. An entry that does not
// read is left out.

import Foundation

/// One planned post (PostPlanner).
struct PlannedPost: Codable, Equatable, Identifiable {
    var id: String
    /// ISO 8601, UTC, to the second.
    var at: String
    var caption = ""
    var format = "png"
    var pages: [String] = []
    var done = false

    init(id: String, at: String, caption: String = "", format: String = "png", pages: [String] = [],
         done: Bool = false) {
        self.id = id
        self.at = at
        self.caption = caption
        self.format = format
        self.pages = pages
        self.done = done
    }

    private enum CodingKeys: String, CodingKey { case id, at, caption, format, pages, done }

    /// Lenient, as the twin reads it: no id, or a time that does not read,
    /// is no post; a format it cannot make is "png"; a page that is not a
    /// string, or a done that is not true or false, is passed over.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let at = try c.decode(String.self, forKey: .at)
        guard !id.isEmpty, PostPlanner.date(at) != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Not a planned post"))
        }
        self.id = id
        self.at = at
        caption = (try? c.decode(String.self, forKey: .caption)) ?? ""
        format = (try? c.decode(String.self, forKey: .format)).flatMap { ExportLast.formats.contains($0) ? $0 : nil } ?? "png"
        pages = ((try? c.decode([Lossy<String>].self, forKey: .pages)) ?? []).compactMap(\.value)
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
    }

    /// Every key, in the twin's order.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(at, forKey: .at)
        try c.encode(caption, forKey: .caption)
        try c.encode(format, forKey: .format)
        try c.encode(pages, forKey: .pages)
        try c.encode(done, forKey: .done)
    }
}

enum PostPlanner {

    static let key = "plannedPosts"

    /// The caption counter's limit: X's 280 for a design of an X type, else
    /// Instagram's 2,200.
    static let longCaption = 2200
    static let shortCaption = 280

    /// The formats a post can be made in, in the sheet's order.
    static let formats = ["png", "jpg", "pdf", "mp4", "gif"]

    /// A post with the design it belongs to, for Home's Planned list.
    struct Planned: Identifiable, Equatable {
        var designId: String
        var title: String
        var post: PlannedPost

        var id: String { designId + "|" + post.id }
    }

    static func newId() -> String {
        "post_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
    }

    private static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    /// `date` as `at` writes it: UTC, to the second.
    static func iso(_ date: Date) -> String {
        formatter().string(from: Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)))
    }

    /// The moment an `at` says, or nil when it does not read — with
    /// fractions of a second or without, as Java's Instant reads them.
    static func date(_ at: String) -> Date? {
        if let plain = formatter().date(from: at) { return plain }
        let fractional = formatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: at)
    }

    /// `design`'s planned posts, as written.
    static func of(_ design: Design) -> [PlannedPost] { design.plannedPosts ?? [] }

    /// `design` with `posts` as its planned posts, soonest first; the key
    /// gone for none.
    static func with(_ design: Design, _ posts: [PlannedPost]) -> Design {
        var out = design
        let sorted = posts.sorted { a, b in
            let da = date(a.at) ?? .distantFuture, db = date(b.at) ?? .distantFuture
            return da != db ? da < db : a.id < b.id
        }
        out.plannedPosts = sorted.isEmpty ? nil : sorted
        return out
    }

    /// `post` added to `design`, or put in place of the one with its id.
    static func saved(_ design: Design, _ post: PlannedPost) -> Design {
        with(design, of(design).filter { $0.id != post.id } + [post])
    }

    /// `design` without post `id`.
    static func removed(_ design: Design, id: String) -> Design {
        with(design, of(design).filter { $0.id != id })
    }

    /// `design` with post `id` marked done.
    static func markedDone(_ design: Design, id: String) -> Design {
        with(design, of(design).map { post in
            var p = post
            if p.id == id { p.done = true }
            return p
        })
    }

    /// The caption limit for `design`: `shortCaption` when the first type of
    /// exactly its size is one of X's ("x-…"), else `longCaption`.
    static func captionLimit(_ design: Design, presets: [SizePreset] = ContentLibrary.sizes) -> Int {
        let type = presets.first { $0.w == design.width && $0.h == design.height }
        return type?.id.hasPrefix("x-") == true ? shortCaption : longCaption
    }

    /// The format a new post starts in: the export suggestion when a post
    /// can be made in it, else "png".
    static func defaultFormat(_ design: Design) -> String {
        let suggested = ExportSuggestion.suggest(design)
        return formats.contains(suggested) ? suggested : "png"
    }

    /// The page indices `post` is made of: its pages that are still in the
    /// design, in the design's order — every shown page when it names none
    /// or none of them is left.
    static func pageIndices(_ design: Design, _ post: PlannedPost) -> [Int] {
        let chosen = design.pages.indices.filter { post.pages.contains(design.pages[$0].id) }
        return chosen.isEmpty ? design.visiblePageIndices : chosen
    }

    /// Every post not done, across `designs`, soonest first — Home's
    /// Planned list.
    static func upcoming(_ designs: [Design]) -> [Planned] {
        designs.flatMap { d in of(d).filter { !$0.done }.map { Planned(designId: d.id, title: d.title, post: $0) } }
            .sorted { a, b in
                let da = date(a.post.at) ?? .distantFuture, db = date(b.post.at) ?? .distantFuture
                return da != db ? da < db : a.post.id < b.post.id
            }
    }

    // MARK: the calendar

    /// Every post, done or not, across `designs`, soonest first — what the
    /// Planned calendar and list show.
    static func all(_ designs: [Design]) -> [Planned] {
        designs.flatMap { d in of(d).map { Planned(designId: d.id, title: d.title, post: $0) } }
            .sorted(by: soonerFirst)
    }

    /// Sooner first, a post with no time that reads last, then by id.
    private static func soonerFirst(_ a: Planned, _ b: Planned) -> Bool {
        let da = date(a.post.at) ?? .distantFuture, db = date(b.post.at) ?? .distantFuture
        return da != db ? da < db : a.post.id < b.post.id
    }

    /// One day of a month in the calendar: its number and its posts.
    struct Day: Equatable {
        var day: Int
        var posts: [Planned]
    }

    /// A Gregorian calendar in `zone`, the one every day is reckoned by.
    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// The calendar's `month` (1–12) of `year`: a bucket for every one of
    /// its days, from 1 to its last, each holding the posts of `planned`
    /// that fall on it in `zone`, soonest first (then by id); a post of
    /// another month, or with no time that reads, is in none. The Android
    /// twin's PostPlanner.month.
    static func month(_ planned: [Planned], year: Int, month: Int, zone: TimeZone) -> [Day] {
        let cal = calendar(zone)
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = cal.range(of: .day, in: .month, for: first) else { return [] }
        var byDay: [Int: [Planned]] = [:]
        for p in planned {
            guard let at = date(p.post.at) else { continue }
            let parts = cal.dateComponents([.year, .month, .day], from: at)
            guard parts.year == year, parts.month == month, let day = parts.day else { continue }
            byDay[day, default: []].append(p)
        }
        return days.map { Day(day: $0, posts: (byDay[$0] ?? []).sorted(by: soonerFirst)) }
    }

    /// How many empty cells come before the 1st of `month` in a grid whose
    /// weeks start on `firstWeekday` (the locale's, Calendar's numbering:
    /// 1 is Sunday), 0–6.
    static func leadingBlanks(year: Int, month: Int, firstWeekday: Int) -> Int {
        let cal = calendar(TimeZone(identifier: "UTC") ?? .current)
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        return (cal.component(.weekday, from: first) - firstWeekday + 7) % 7
    }

    /// The hour a post planned from a day of the calendar starts at.
    static let planHour = 9

    /// planHour:00 on `day` of `month` of `year` in `zone`, as `at` writes it.
    static func morningOf(year: Int, month: Int, day: Int, zone: TimeZone) -> String {
        let parts = DateComponents(year: year, month: month, day: day, hour: planHour, minute: 0)
        return calendar(zone).date(from: parts).map(iso) ?? ""
    }

    /// `post` moved to `day` of `month` of `year`, keeping its time of day in
    /// `zone` — a drag to another day, or Move to date…; one with no time
    /// that reads is as it was.
    static func movedTo(_ post: PlannedPost, year: Int, month: Int, day: Int, zone: TimeZone) -> PlannedPost {
        let cal = calendar(zone)
        guard let at = date(post.at) else { return post }
        let time = cal.dateComponents([.hour, .minute, .second], from: at)
        let parts = DateComponents(year: year, month: month, day: day, hour: time.hour, minute: time.minute,
                                   second: time.second)
        guard let moved = cal.date(from: parts) else { return post }
        var out = post
        out.at = iso(moved)
        return out
    }

    /// Whether `post` is overdue: not done, and its time gone by at `now`.
    static func overdue(_ post: PlannedPost, now: Date) -> Bool {
        guard !post.done, let at = date(post.at) else { return false }
        return at < now
    }

    /// The caption counter: "12 / 2,200" as the sheet shows it, the
    /// caption counted in characters as the twin counts code points.
    static func counter(_ caption: String, limit: Int) -> String {
        tr("%d / %d", caption.unicodeScalars.count, limit)
    }

    /// Whether the caption runs past `limit`.
    static func isTooLong(_ caption: String, limit: Int) -> Bool { caption.unicodeScalars.count > limit }
}
