// A page's own name — "Intro", "Agenda", "Thank you" — for finding it in a
// long deck. Never drawn on the page and never in an export: it shows where
// pages are listed — the organizer, the pages bar to VoiceOver, Present's
// counter, Find's results. Kept on the page as `title`, written only when
// there is one, under the key the Android twin keeps it by
// (core/content/PageExtras.kt), and to the same 60 characters.

import Foundation

enum PageTitles {

    /// The longest title a page takes, in characters.
    static let maxLength = 60

    /// A title as typed, made fit to keep: trimmed and cut to `maxLength`;
    /// nil when nothing is left, so an emptied title leaves no key behind.
    static func cleaned(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }

    /// A title read from a file or about to be written: as it is, so a design
    /// from the other phone comes back unchanged — or nil when there is
    /// nothing to it.
    static func kept(_ title: String) -> String? {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
    }

    /// "Page 2 · Intro", or "Page 2" untitled. `number` is one-based.
    static func named(_ number: Int, title: String?) -> String {
        guard let title = title.flatMap(kept) else { return "Page \(number)" }
        return "Page \(number) · \(title)"
    }

    /// Present's counter: "2 / 5 · Intro", or "2 / 5" untitled.
    static func counter(_ number: Int, of count: Int, title: String?) -> String {
        guard let title = title.flatMap(kept) else { return "\(number) / \(count)" }
        return "\(number) / \(count) · \(title)"
    }
}
