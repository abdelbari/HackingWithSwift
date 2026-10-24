// Where Present starts from the editor: "From the beginning" or "From page
// N" — the page being edited — offered when the design has more than one
// page and that page is not the first (offersChoice); else Present starts
// where it always has. The last choice is kept per design on this phone,
// as the Android twin keeps it, under the preference "presentFrom":
// {"<designId>": "start" | "current"} — the menu ticks it, and ⇧⌘P starts
// there; F5 is always the beginning and ⇧F5 always this page. Hidden pages
// are skipped either way: a hidden start goes on to the next shown page
// (PageVisibility.start). The Android twin's PresentFrom, row for row.

import Foundation

enum PresentFrom {

    static let key = "presentFrom"

    static let start = "start"
    static let current = "current"

    /// Whether the editor's Present asks where to start: more than one
    /// page, and the one being edited (`pageIndex`) is not the first.
    static func offersChoice(_ design: Design, pageIndex: Int) -> Bool {
        design.pages.count > 1 && pageIndex > 0
    }

    /// The page Present opens on for `choice`: the first shown page, or the
    /// page being edited — the next shown one when it is hidden; nil when
    /// every page is hidden. Anything but `current` is the beginning.
    static func startPage(_ design: Design, choice: String, pageIndex: Int) -> Int? {
        PageVisibility.start(at: choice == current ? pageIndex : 0, in: design.visiblePageIndices)
    }

    /// The choices kept, by design id: those that are `start` or `current`,
    /// from the preference's JSON; none for anything else.
    static func decode(_ text: String?) -> [String: String] {
        guard let data = text?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (id, value) in object {
            if let choice = value as? String, choice == start || choice == current { out[id] = choice }
        }
        return out
    }

    /// The choices as the preference keeps them, ids in order.
    static func encode(_ choices: [String: String]) -> String {
        let entries = choices.keys.sorted().map { id in "\(quoted(id)):\(quoted(choices[id] ?? start))" }
        return "{" + entries.joined(separator: ",") + "}"
    }

    /// `text` as a JSON string.
    private static func quoted(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    /// `designId`'s kept choice, `start` when it has none.
    static func chosen(_ choices: [String: String], designId: String) -> String {
        choices[designId] ?? start
    }

    /// `choices` with `choice` kept for `designId`.
    static func remembered(_ choices: [String: String], designId: String, choice: String) -> [String: String] {
        guard choice == start || choice == current else { return choices }
        var out = choices
        out[designId] = choice
        return out
    }

    /// "From page 7": the menu's row for the page being edited.
    static func fromPage(_ pageIndex: Int) -> String {
        tr("From page %d", pageIndex + 1)
    }

    /// "Presenting from page 3 of 9", said as Present opens on `index`: its
    /// place among the shown pages, as Present's counter numbers them.
    static func announcement(_ design: Design, index: Int) -> String {
        let shown = design.visiblePageIndices
        return tr("Presenting from page %d of %d", (shown.firstIndex(of: index) ?? -1) + 1, shown.count)
    }

    // MARK: keys

    /// A slideshow's keys, as the Android twin's EditorKeys has them: F5
    /// from the beginning, ⇧F5 from this page — each named as the
    /// keyboard's list of shortcuts says it.
    struct Shortcut: Equatable {
        var shift: Bool
        var choice: String
        var name: String
    }

    static let keys: [Shortcut] = [
        Shortcut(shift: false, choice: start, name: "Present from the beginning"),
        Shortcut(shift: true, choice: current, name: "Present from this page"),
    ]

    /// What F5 asks for, with Shift or without.
    static func choice(shift: Bool) -> String {
        keys.first { $0.shift == shift }?.choice ?? start
    }

    // MARK: kept on this phone

    static func choices(_ defaults: UserDefaults = .standard) -> [String: String] {
        decode(defaults.string(forKey: key))
    }

    static func remember(_ designId: String, choice: String, _ defaults: UserDefaults = .standard) {
        let before = choices(defaults)
        let next = remembered(before, designId: designId, choice: choice)
        if next != before { defaults.set(encode(next), forKey: key) }
    }
}
