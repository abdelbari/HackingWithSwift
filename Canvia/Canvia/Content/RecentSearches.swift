// Home's search history and the templates used lately, as both phones keep
// them: each a JSON array of strings, newest first — @AppStorage
// "recentSearches" and "recentTemplates" here, the Android twin's
// preferences "recent_searches" and "recent_templates", and a backup's
// settings.json under this phone's names. Kept on the phone, never in a
// design. The Android twin's RecentSearches.
//
// A search is remembered trimmed, once whatever its capitals (the newest
// spelling kept), at most searchLimit; a template by its id, at most
// templateLimit — pushed when a template is applied, its pages added or it
// is opened from its preview.

import Foundation

enum RecentSearches {

    static let searchesKey = "recentSearches"
    static let templatesKey = "recentTemplates"

    static let searchLimit = 10
    static let templateLimit = 12

    /// `searches` with `query` first: trimmed, any other spelling of it
    /// (capitals aside) taken out, at most searchLimit; a blank query
    /// changes nothing.
    static func remembered(_ searches: [String], _ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return searches }
        let key = q.lowercased()
        return Array(([q] + searches.filter { $0.lowercased() != key }).prefix(searchLimit))
    }

    /// `searches` without `query`, capitals aside — Remove on a Recent row.
    static func removed(_ searches: [String], _ query: String) -> [String] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return searches.filter { $0.lowercased() != key }
    }

    /// `ids` with template `id` first, once, at most templateLimit.
    static func usedTemplate(_ ids: [String], _ id: String) -> [String] {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty else { return ids }
        return Array(([id] + ids.filter { $0 != id }).prefix(templateLimit))
    }

    /// The templates `ids` name that are in the library, in their order —
    /// "Recently used"; one no longer there is passed over.
    static func templates(_ ids: [String], among library: [Template] = ContentLibrary.templates) -> [Template] {
        let byId = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    /// A list as it is stored: a JSON array of strings.
    static func encode(_ list: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: list, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    /// A stored list as it reads: the strings of a JSON array, blanks and
    /// repeats (capitals aside, for searches) dropped, cut to `limit`;
    /// nothing for anything else.
    static func decode(_ text: String?, limit: Int = searchLimit, searches: Bool = true) -> [String] {
        guard let text, let data = text.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [Any] else { return [] }
        return read(array, limit: limit, searches: searches)
    }

    /// The same, from an array already read — a backup's settings.
    static func read(_ array: [Any], limit: Int, searches: Bool) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for item in array {
            guard let raw = item as? String else { continue }
            let s = searches ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : raw
            guard !s.isEmpty, seen.insert(searches ? s.lowercased() : s).inserted else { continue }
            out.append(s)
            if out.count == limit { break }
        }
        return out
    }

    // MARK: kept on this phone

    static func searches(_ defaults: UserDefaults = .standard) -> [String] {
        decode(defaults.string(forKey: searchesKey))
    }

    static func setSearches(_ list: [String], _ defaults: UserDefaults = .standard) {
        defaults.set(encode(list), forKey: searchesKey)
    }

    static func usedTemplates(_ defaults: UserDefaults = .standard) -> [String] {
        decode(defaults.string(forKey: templatesKey), limit: templateLimit, searches: false)
    }

    static func setUsedTemplates(_ list: [String], _ defaults: UserDefaults = .standard) {
        defaults.set(encode(list), forKey: templatesKey)
    }

    /// Remembers a search as it is sent, or as the field is left with
    /// words in it.
    static func remember(_ query: String, _ defaults: UserDefaults = .standard) {
        let before = searches(defaults)
        let next = remembered(before, query)
        if next != before { setSearches(next, defaults) }
    }

    static func forget(_ query: String, _ defaults: UserDefaults = .standard) {
        setSearches(removed(searches(defaults), query), defaults)
    }

    /// A template applied, its pages added or opened from its preview.
    static func used(_ id: String, _ defaults: UserDefaults = .standard) {
        setUsedTemplates(usedTemplate(usedTemplates(defaults), id), defaults)
    }
}
