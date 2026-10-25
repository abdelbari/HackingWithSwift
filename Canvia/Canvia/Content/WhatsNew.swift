// What's new: the notes whatsnew.json carries (Tools/generate_help.py),
// the same on both phones, newest version first. Home shows a card of them
// once for each version newer than the one last seen — the setting `pref`,
// kept in backups — and Settings ▸ Help lists them all. The Android twin's
// WhatsNew.kt by the same rules.
//
// The version is the notes' own, the newest in the file, not the build's:
// the two phones number their builds apart, and the notes change exactly
// when an update brings new ones.

import Foundation

enum WhatsNew {

    /// The setting that holds the newest version seen, the same key on both
    /// phones.
    static let pref = "whatsNewSeen"

    /// The places on Home an item's "opens" names.
    static let tools = "tools"
    static let trash = "trash"
    static let templates = "templates"

    struct Note: Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        var body: String
        var opens: String?
    }

    struct Version: Equatable, Sendable {
        var version: String
        var items: [Note]
    }

    /// whatsnew.json, read once, in English.
    private static let english: [Version] = {
        guard let url = Bundle.main.url(forResource: "whatsnew", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("whatsnew.json missing")
            return []
        }
        return decode(data)
    }()

    /// The versions in `data`: each with a version and its items that have
    /// an id; anything else passed over, and a file that does not read is
    /// none.
    static func decode(_ data: Data) -> [Version] {
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return raw.compactMap { entry -> Version? in
            guard let o = entry as? [String: Any], let version = o["version"] as? String else { return nil }
            let items = (o["items"] as? [Any] ?? []).compactMap { e -> Note? in
                guard let i = e as? [String: Any], let id = i["id"] as? String else { return nil }
                return Note(id: id, title: i["title"] as? String ?? "", body: i["body"] as? String ?? "",
                            opens: i["opens"] as? String)
            }
            return Version(version: version, items: items)
        }
    }

    /// Every version's notes, newest first, in the app's language.
    static var all: [Version] {
        english.map { v in
            Version(version: v.version, items: v.items.map { item in
                Note(id: item.id, title: tr(item.title), body: tr(item.body), opens: item.opens)
            })
        }
    }

    /// The newest version the notes have.
    static var current: String { newest(english) }

    static func newest(_ versions: [Version]) -> String {
        versions.map(\.version).max { compare($0, $1) < 0 } ?? ""
    }

    /// `a` against `b` as dotted whole numbers, part by part, a missing
    /// part read as 0 ("1.36" after "1.4", "1.36" the same as "1.36.0");
    /// nothing, or a part that is no number, reads as 0 too, so a blank
    /// setting is older than any version. Below zero when `a` is older.
    static func compare(_ a: String?, _ b: String?) -> Int {
        let x = parts(a)
        let y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p < q ? -1 : 1 }
        }
        return 0
    }

    private static func parts(_ v: String?) -> [Int] {
        let trimmed = v?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: ".", omittingEmptySubsequences: false).map {
            Int($0.trimmingCharacters(in: .whitespaces)) ?? 0
        }
    }

    /// Whether Home shows the card: the notes are newer than `seen`.
    static func shows(_ seen: String?) -> Bool { shows(seen, versions: english) }

    static func shows(_ seen: String?, versions: [Version]) -> Bool {
        compare(newest(versions), seen) > 0
    }

    /// What the card lists: the items of every version newer than `seen`,
    /// newest first, in the app's language.
    static func since(_ seen: String?) -> [Note] { since(seen, versions: all) }

    static func since(_ seen: String?, versions: [Version]) -> [Note] {
        versions.filter { compare($0.version, seen) > 0 }
            .sorted { compare($0.version, $1.version) > 0 }
            .flatMap(\.items)
    }

    /// The version last seen on this phone; "" for none.
    static func seen(_ defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: pref) ?? ""
    }

    /// The notes there are now marked seen.
    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(current, forKey: pref)
    }

    /// A backup's version seen counts as seen here too; never older.
    static func restore(_ version: String?, defaults: UserDefaults = .standard) {
        guard let version, compare(version, seen(defaults)) > 0 else { return }
        defaults.set(version, forKey: pref)
    }
}
