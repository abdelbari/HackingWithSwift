// "What will you use Canvia for?" — asked once, on the first launch, before
// the welcome tour — and how Home follows the answer. The answer is kept
// under "canvia.use", the same key as the Android twin's, and in a backup's
// settings.json. The choices and what each puts first are Content.json's
// "uses", which the twin's generator writes from its templates/uses.json.
// Skipped, or never asked, Home is as it always was. The twin's UseProfile.

import Foundation

/// One answer: its design types for Home's hero row and its template
/// categories, each in its order.
struct UseCase: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var sizes: [String]
    var categories: [String]

    /// Its name in the app's language: a chip, the Settings row.
    var label: String { tr(name) }
}

enum UseProfile {

    /// The preference both phones keep the answer under.
    static let key = "canvia.use"
    /// Whether the first launch has asked: once, answered or skipped.
    static let askedKey = "canvia.use.asked"
    /// A backup's settings file: {"canvia.use": "teacher"}.
    static let settingsFile = "settings.json"

    static var all: [UseCase] { ContentLibrary.uses }

    static func byId(_ id: String?) -> UseCase? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// The answer kept here; nil when skipped, not asked, or not one this
    /// build knows.
    static func current(_ defaults: UserDefaults = .standard) -> String? {
        byId(defaults.string(forKey: key))?.id
    }

    /// Keeps `id` as the answer — nil takes it away — and marks it asked.
    static func set(_ id: String?, _ defaults: UserDefaults = .standard) {
        if let id, byId(id) != nil { defaults.set(id, forKey: key) } else { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: askedKey)
    }

    /// Asked on the first launch, before the tour, when the tour itself is
    /// to show: never again once answered or skipped.
    static func needsAsking(defaults: UserDefaults, arguments: [String]) -> Bool {
        !defaults.bool(forKey: askedKey) && Onboarding.needsTour(defaults: defaults, arguments: arguments)
    }

    static var needsAsking: Bool {
        needsAsking(defaults: .standard, arguments: ProcessInfo.processInfo.arguments)
    }

    /// `presets` in the order Home shows them for `use`: the use's design
    /// types that are among them, in the use's order, then every other in
    /// its own order. No use, or one not known, leaves them as they are.
    static func order(_ use: String?, _ presets: [SizePreset]) -> [SizePreset] {
        guard let chosen = byId(use) else { return presets }
        let first = chosen.sizes.compactMap { id in presets.first { $0.id == id } }
        let ids = Set(first.map(\.id))
        return first + presets.filter { !ids.contains($0.id) }
    }

    /// Home's hero row for `use`: `order` of every design type, as many as
    /// the row has without one — so the use's types, then the usual ones.
    static func hero(_ use: String?) -> [SizePreset] {
        guard byId(use) != nil else { return SizePreset.hero }
        return Array(order(use, SizePreset.all).prefix(SizePreset.hero.count))
    }

    /// Template `categories` with `use`'s first, in its order, then the
    /// rest in theirs.
    static func categories(_ use: String?, _ categories: [String]) -> [String] {
        guard let chosen = byId(use) else { return categories }
        let first = chosen.categories.filter { categories.contains($0) }
        return first + categories.filter { !first.contains($0) }
    }

    /// `templates` with those of `use`'s categories first, in the use's
    /// order of them, each keeping its place among its own (a stable sort).
    static func templatesFirst<T>(_ use: String?, _ templates: [T], category: (T) -> String) -> [T] {
        guard let chosen = byId(use) else { return templates }
        let ranks = templates.map { chosen.categories.firstIndex(of: category($0)) ?? chosen.categories.count }
        let order = templates.indices.sorted { a, b in ranks[a] != ranks[b] ? ranks[a] < ranks[b] : a < b }
        return order.map { templates[$0] }
    }

    /// A backup's settings file holding `use`.
    static func encodeSettings(_ use: String?) -> Data {
        let object: [String: String] = use.map { [key: $0] } ?? [:]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// The use kept in a backup's settings file; nil when it has none that
    /// this phone knows.
    static func decodeSettings(_ data: Data?) -> String? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object[key] as? String else { return nil }
        return byId(id)?.id
    }
}
