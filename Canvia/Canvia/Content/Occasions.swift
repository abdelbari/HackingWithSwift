// The occasions Home's Coming up row leads with — Halloween, Diwali, Black
// Friday, Christmas — from the calendar both phones share,
// templates/occasions.json (Content.json's "occasions", written by the
// Android twin's tools/generate_templates.py): the Android twin's
// Occasions, rule for rule.
//
// Each occasion falls on a fixed "date" ("10-31"), on a "rule" — "easter"
// (the Gregorian computus) or "weekday" (the `nth` `weekday`, ISO 1 =
// Monday to 7 = Sunday, of `month`; a negative nth counts from the month's
// end) — moved by "offset" days, or on the day a table of "dates" by year
// gives (moving feasts up to 2035; a year not in it has none). A region may
// fall on a rule of its own ("regions", by the locale's country):
// Mothering Sunday in the UK, Thanksgiving in Canada. It is coming up for
// its "lead" days before it, and on the day itself.

import Foundation

enum Occasions {

    /// A day of the Gregorian calendar, whatever the time zone: what the
    /// calendar's rules are worked in.
    struct CivilDay: Comparable, Hashable {
        var year: Int
        var month: Int
        var day: Int

        /// Days since 1 January 1970 (Howard Hinnant's days_from_civil).
        var ordinal: Int {
            let y = month <= 2 ? year - 1 : year
            let era = (y >= 0 ? y : y - 399) / 400
            let yoe = y - era * 400
            let mp = (month + 9) % 12
            let doy = (153 * mp + 2) / 5 + day - 1
            let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            return era * 146_097 + doe - 719_468
        }

        /// The day `ordinal` days from 1 January 1970.
        init(ordinal: Int) {
            let z = ordinal + 719_468
            let era = (z >= 0 ? z : z - 146_096) / 146_097
            let doe = z - era * 146_097
            let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
            let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
            let mp = (5 * doy + 2) / 153
            day = doy - (153 * mp + 2) / 5 + 1
            month = mp < 10 ? mp + 3 : mp - 9
            year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        }

        /// The day, when there is such a day: never 31 April.
        init?(year: Int, month: Int, day: Int) {
            guard (1...12).contains(month), day >= 1, day <= Self.length(of: month, in: year) else { return nil }
            self.year = year
            self.month = month
            self.day = day
        }

        /// ISO weekday: 1 Monday to 7 Sunday.
        var weekday: Int { ((ordinal % 7 + 7 + 3) % 7) + 1 }

        func adding(days: Int) -> CivilDay { CivilDay(ordinal: ordinal + days) }

        static func < (a: CivilDay, b: CivilDay) -> Bool { a.ordinal < b.ordinal }

        static func length(of month: Int, in year: Int) -> Int {
            switch month {
            case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
            case 4, 6, 9, 11: return 30
            default: return 31
            }
        }

        /// The day `date` falls on in `calendar`'s time zone.
        static func of(_ date: Date, calendar: Calendar = .current) -> CivilDay {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return CivilDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
                ?? CivilDay(ordinal: 0)
        }

        /// "2026-10-25", as the shared cases write a day; nil for anything
        /// else.
        static func parse(_ text: String) -> CivilDay? {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return CivilDay(year: parts[0], month: parts[1], day: parts[2])
        }
    }

    /// When an occasion falls in a year.
    struct Rule: Equatable {
        var date: String?
        var rule: String?
        var month = 1
        var weekday = 7
        var nth = 1
        var offset = 0
        var dates: [String: String] = [:]

        /// Its day in `year`, or nil when it has none that year.
        func day(in year: Int) -> CivilDay? {
            let base: CivilDay?
            if let date {
                base = Occasions.monthDay(year, date)
            } else if rule == "easter" {
                base = Occasions.easter(year)
            } else if rule == "weekday" {
                base = Occasions.weekdayIn(year, month: month, weekday: weekday, nth: nth)
            } else {
                base = dates[String(year)].flatMap { Occasions.monthDay(year, $0) }
            }
            return base?.adding(days: offset)
        }
    }

    struct Occasion: Identifiable, Equatable {
        var id: String
        var name: String
        var lead: Int
        var rule: Rule
        var regions: [String: Rule] = [:]

        /// Its rule in `region` (a country code, "GB"): the region's own,
        /// else its own.
        func rule(for region: String?) -> Rule {
            region.flatMap { regions[$0.uppercased()] } ?? rule
        }
    }

    /// An occasion coming up: on `date`, `days` from today (0 is today).
    struct Upcoming: Equatable {
        var occasion: Occasion
        var date: CivilDay
        var days: Int
    }

    /// The calendar, as the app ships it.
    static let all: [Occasion] = ContentLibrary.bundle.occasions?.compactMap(\.occasion) ?? []

    static func byId(_ id: String?) -> Occasion? { all.first { $0.id == id } }

    /// The occasions of `calendar` whose window — `lead` days before the
    /// day, to the day itself — holds `today`, in `region` (a country
    /// code), nearest first; a tie keeps the calendar's order. An occasion
    /// whose day this year is past looks to next year's.
    static func upcoming(_ today: CivilDay, region: String?, calendar: [Occasion] = all) -> [Upcoming] {
        let found = calendar.enumerated().compactMap { i, occasion -> (Upcoming, Int)? in
            let rule = occasion.rule(for: region)
            guard let day = [today.year, today.year + 1].lazy.compactMap({ rule.day(in: $0) }).first(where: { $0 >= today })
            else { return nil }
            let days = day.ordinal - today.ordinal
            guard days <= occasion.lead else { return nil }
            return (Upcoming(occasion: occasion, date: day, days: days), i)
        }
        return found.sorted { a, b in a.0.days != b.0.days ? a.0.days < b.0.days : a.1 < b.1 }.map(\.0)
    }

    /// What is coming up now, where the phone is.
    static func upcoming(at date: Date = Date(), locale: Locale = .current, calendar: Calendar = .current) -> [Upcoming] {
        upcoming(CivilDay.of(date, calendar: calendar), region: locale.region?.identifier)
    }

    /// Easter Sunday in `year`: the anonymous Gregorian computus.
    static func easter(_ year: Int) -> CivilDay {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return CivilDay(year: year, month: month, day: day) ?? CivilDay(ordinal: 0)
    }

    /// "10-31" in `year`.
    static func monthDay(_ year: Int, _ md: String) -> CivilDay? {
        let parts = md.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return CivilDay(year: year, month: parts[0], day: parts[1])
    }

    /// The `nth` `weekday` (ISO) of `month`; a negative nth counts from the
    /// month's end, -1 its last.
    static func weekdayIn(_ year: Int, month: Int, weekday: Int, nth: Int) -> CivilDay? {
        guard let first = CivilDay(year: year, month: month, day: 1) else { return nil }
        let want = min(max(weekday, 1), 7)
        if nth < 0 {
            guard let last = CivilDay(year: year, month: month, day: CivilDay.length(of: month, in: year)) else { return nil }
            let back = (last.weekday - want + 7) % 7
            return last.adding(days: -back + (nth + 1) * 7)
        }
        let ahead = (want - first.weekday + 7) % 7
        let day = first.adding(days: ahead + (max(nth, 1) - 1) * 7)
        // Past the month's end, as Java's dayOfWeekInMonth runs on into the
        // next.
        return day
    }

    /// Home's Coming up row for `occasion`: its templates, each layout once
    /// (its colourways in its preview), those of a type `use` leads with
    /// (UseProfile.hero) first, each group in the library's order.
    static func templates(_ occasion: String, use: String?, library: [Template] = ContentLibrary.templates) -> [Template] {
        let sizes = Set(UseProfile.hero(use).map { SizeKey(width: $0.w, height: $0.h) })
        let own = Templates.grouped(library.filter { $0.occasion == occasion })
        return own.filter { sizes.contains(SizeKey(width: $0.width, height: $0.height)) }
            + own.filter { !sizes.contains(SizeKey(width: $0.width, height: $0.height)) }
    }

    /// A size, to look up.
    private struct SizeKey: Hashable {
        var width: Double
        var height: Double
    }

    /// The occasion's name as the app says it.
    static func name(_ occasion: Occasion) -> String { tr(occasion.name) }

    /// Home's row title: "Coming up: Halloween · 6 days", or "· Today".
    static func comingUp(_ up: Upcoming) -> String {
        tr("Coming up: %@ · %@", name(up.occasion), up.days == 0 ? tr("Today") : trn("%d day|%d days", up.days))
    }

    /// The preference that shows the row: Settings ▸ Home's "Show seasonal
    /// ideas", on until turned off.
    static let seasonalKey = "homeSeasonal"
}

/// One entry of the shared calendar as Content.json has it, read leniently:
/// an entry without an id or a lead is none.
struct OccasionSpec: Decodable {
    var occasion: Occasions.Occasion?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard let id = try? c.decode(String.self, forKey: Key("id")),
              let lead = try? c.decode(Int.self, forKey: Key("lead")) else {
            occasion = nil
            return
        }
        var regions: [String: Occasions.Rule] = [:]
        if let nested = try? c.nestedContainer(keyedBy: Key.self, forKey: Key("regions")) {
            for key in nested.allKeys {
                if let inner = try? nested.nestedContainer(keyedBy: Key.self, forKey: key) {
                    regions[key.stringValue] = Self.rule(inner)
                }
            }
        }
        let name = (try? c.decode(String.self, forKey: Key("name"))) ?? id
        occasion = Occasions.Occasion(id: id, name: name, lead: lead, rule: Self.rule(c), regions: regions)
    }

    private static func rule(_ c: KeyedDecodingContainer<Key>) -> Occasions.Rule {
        func int(_ key: String, _ fallback: Int) -> Int { (try? c.decode(Int.self, forKey: Key(key))) ?? fallback }
        var rule = Occasions.Rule()
        rule.date = try? c.decode(String.self, forKey: Key("date"))
        rule.rule = try? c.decode(String.self, forKey: Key("rule"))
        rule.month = int("month", 1)
        rule.weekday = int("weekday", 7)
        rule.nth = int("nth", 1)
        rule.offset = int("offset", 0)
        rule.dates = (try? c.decode([String: String].self, forKey: Key("dates"))) ?? [:]
        return rule
    }

    /// Any key.
    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
