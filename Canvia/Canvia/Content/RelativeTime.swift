// "Just now", "12 minutes ago", "Yesterday", "3 days ago", "8 Sep".
//
// When a design was last touched, in the words the Android twin's cards use
// (home/RelativeTime.kt), so the same shelf reads the same on either phone.
// Worked out when the shelf is read rather than ticking: a card that counts
// seconds is a card that never stops moving.

import Foundation

enum RelativeTime {

    /// How long ago `ms` (milliseconds since 1970, as designs keep it) was,
    /// seen from `now`.
    static func text(ms: Double, now: Date, calendar: Calendar, locale: Locale) -> String {
        let then = Date(timeIntervalSince1970: ms / 1000)
        let delta = now.timeIntervalSince(then)
        // A clock put back, or a design from a phone whose clock runs ahead.
        if delta < 0 { return "Just now" }

        let minutes = Int(delta / 60)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }

        if calendar.isDate(then, inSameDayAs: now) {
            let hours = minutes / 60
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(then, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        // Whole days, and never "1 days ago": past yesterday is two
        // calendar days back even when it is under 48 hours.
        let days = max(2, Int(delta / 86_400))
        if days < 7 { return "\(days) days ago" }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: then) == calendar.component(.year, from: now)
        formatter.dateFormat = sameYear ? "d MMM" : "d MMM yyyy"
        return formatter.string(from: then)
    }

    static func text(ms: Double) -> String {
        text(ms: ms, now: Date(), calendar: .current, locale: .current)
    }

    /// "1 page" / "4 pages".
    static func pages(_ count: Int) -> String {
        count == 1 ? "1 page" : "\(count) pages"
    }

    /// The same, mid-sentence: "Deleted yesterday", "Deleted 5 minutes ago".
    static func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + String(text.dropFirst())
    }
}
