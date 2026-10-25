// Template search that forgives: separate words, plurals, synonyms,
// colours, typos — the Android twin's TemplateSearch, step for step, so a
// query finds the same templates in the same order on both phones
// (templates/search-cases.json).
//
// 1. The query is normalised — lower case, accents stripped, apostrophes
//    dropped ("valentine's" is "valentines"), '-' made a space — and split
//    at anything not a letter or a digit; the stop words (`stopWords`) go.
// 2. Each word is stemmed (`stem`): an irregular plural from `irregular`,
//    else a trailing "ies" made "y", "es" after s, x, z, ch or sh dropped,
//    or a trailing "s" (not "ss") dropped — on the template's words alike.
// 3. A word matches a template through itself or a synonym
//    (templates/search-synonyms.json, either way round): in its name (3),
//    its design type's name (2), its topic, category, occasion or style
//    (2) or its own words (1). A colour word (TemplateFilter.allColors)
//    matches only a template with that colour in its facets, and scores
//    nothing — unless the template's name has the word ("Black Friday"),
//    which scores as a name does. Every word must match (AND); a template
//    scores each word's best, added up, and 1 more when recently used. The
//    best first, a tie in the library's order.
// 4. When nothing matches, each word not in the vocabulary is replaced by
//    the vocabulary's word nearest it — a Damerau-Levenshtein distance of
//    at most 1, or 2 for a word of 7 letters or more; the nearer, then the
//    one more templates have, then the first alphabetically — and the
//    search is tried again, "Showing results for “birthday”".

import Foundation

enum TemplateSearch {

    /// The words a query leaves out.
    static let stopWords: Set<String> = ["a", "the", "for", "my", "template"]

    /// Plurals no rule makes.
    static let irregular: [String: String] = [
        "children": "child", "people": "person", "men": "man", "women": "woman",
        "mice": "mouse", "geese": "goose", "teeth": "tooth", "feet": "foot", "leaves": "leaf",
    ]

    private static let nameScore = 3
    private static let typeScore = 2
    private static let topicScore = 2
    private static let textScore = 1

    /// `text` lower-cased, its accents and apostrophes gone, '-' a space.
    static func normalise(_ text: String) -> String {
        let marks = text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            $0.properties.generalCategory != .nonspacingMark && $0 != "'" && $0 != "\u{2019}"
        }
        return String(String.UnicodeScalarView(marks)).replacingOccurrences(of: "-", with: " ")
    }

    /// Whether a character is part of a word: a letter or a decimal digit.
    private static func isWordScalar(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
            return true
        default:
            return false
        }
    }

    /// `text` normalised and split at anything not a letter or a digit.
    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        for s in normalise(text).unicodeScalars {
            if isWordScalar(s) {
                current.append(s)
            } else if !current.isEmpty {
                out.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { out.append(String(current)) }
        return out
    }

    /// `text`'s words, normalised, in order, stop words left out.
    static func tokens(_ text: String) -> [String] {
        words(text).filter { !stopWords.contains($0) && !stopWords.contains(stem($0)) }
    }

    /// A word's stem: see the file's comment.
    static func stem(_ word: String) -> String {
        if let plain = irregular[word] { return plain }
        let n = word.count
        if n > 4 && word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if n > 3 && word.hasSuffix("es") {
            let base = word.dropLast(2)
            if ["s", "x", "z", "ch", "sh"].contains(where: { base.hasSuffix($0) }) { return String(base) }
        }
        if n > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    // MARK: synonyms

    /// The synonyms, as templates/search-synonyms.json has them.
    static var synonyms: [String: [String]] { ContentLibrary.bundle.searchSynonyms ?? [:] }

    /// The synonyms as stems, each word to every word it means, either way
    /// round.
    static func stemTable(_ table: [String: [String]]) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        // In key order, so the table is the same whatever order the
        // dictionary hashes to.
        for key in table.keys.sorted() {
            let k = tokens(key).map(stem).joined(separator: " ")
            for word in table[key] ?? [] {
                let w = tokens(word).map(stem).joined(separator: " ")
                guard !k.isEmpty, !w.isEmpty else { continue }
                out[k, default: []].insert(w)
                out[w, default: []].insert(k)
            }
        }
        return out
    }

    private static let stemmedSynonyms: [String: Set<String>] = stemTable(synonyms)

    /// The stems a query word `stemmed` stands for: itself and each synonym.
    private static func expansions(_ stemmed: String, table: [String: Set<String>]) -> Set<String> {
        Set([stemmed]).union(table[stemmed] ?? [])
    }

    // MARK: the index

    /// What one template is found by, as stems.
    struct Indexed {
        let template: Template
        let name: Set<String>
        let type: Set<String>
        let topic: Set<String>
        let colors: Set<String>
        let text: Set<String>
    }

    /// The words a template is found by, outside its own: its type's name,
    /// and its topic, category, occasion and style, as they read.
    private static func labels(_ t: Template) -> (type: String?, topics: [String]) {
        let type = SizePreset.all.first { p in
            (p.w == t.width && p.h == t.height)
                || SizePreset.formerPixels[p.id].map { $0.width == t.width && $0.height == t.height } == true
        }?.name
        let occasion = t.occasion.map { id in Occasions.byId(id)?.name ?? id }
        let topics = [t.topic, t.category, t.occasion, occasion, t.shownFacets.style].compactMap { $0 }
        return (type, topics)
    }

    private static func stems(_ text: String?) -> Set<String> {
        Set(tokens(text ?? "").map(stem))
    }

    /// A template's own words, as the shelf would keep them of a design
    /// made from it: every page's text boxes and shapes with words.
    static func ownWords(_ t: Template) -> String {
        var design = Design(title: t.name, width: t.width, height: t.height)
        design.pages = t.pageSpecs.map { Page(background: $0.background, elements: $0.elements) }
        return DesignLibrary.searchText(design)
    }

    static func entry(_ t: Template) -> Indexed {
        let (type, topics) = labels(t)
        return Indexed(template: t, name: stems(t.name), type: stems(type),
                     topic: topics.reduce(into: Set<String>()) { $0.formUnion(stems($1)) },
                     colors: Set(t.shownFacets.colors), text: stems(ownWords(t)))
    }

    /// The index and the vocabulary made, so the first search does not
    /// make them; off the main thread.
    static func warm() {
        _ = index.count
        _ = vocabulary.count
    }

    /// Every built-in template's entry, made once.
    static let index: [Indexed] = ContentLibrary.templates.map(entry)

    /// The words a typo is corrected to and a completion is drawn from:
    /// every built-in template's name, type, topic, category, occasion and
    /// style words, colours and the synonyms' words — normalised, not
    /// stemmed — each with how many templates have it.
    static let vocabulary: [String: Int] = vocabularyOf(ContentLibrary.templates, synonyms: synonyms)

    static func vocabularyOf(_ templates: [Template], synonyms: [String: [String]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for t in templates {
            let (type, topics) = labels(t)
            let texts = [t.name, type ?? ""] + topics + t.shownFacets.colors
            for w in Set(texts.flatMap(tokens)) { counts[w, default: 0] += 1 }
        }
        for (key, list) in synonyms {
            for w in tokens(key) + list.flatMap(tokens) where counts[w] == nil { counts[w] = 0 }
        }
        return counts
    }

    // MARK: searching

    /// What a search found, and the query it was corrected to, when its own
    /// words found nothing ("birthday" for "brithday").
    struct Result {
        var templates: [Template]
        var correctedTo: String? = nil
    }

    /// The templates of `entries` that `query` finds and `filter` lets
    /// through, best first (see the file's comment), `recent` ids scoring
    /// 1 more; corrected for typos when `correct` and its own words find
    /// nothing. A blank query finds nothing.
    static func search(_ query: String, filter: TemplateFilter = TemplateFilter(), recent: Set<String> = [],
                       correct: Bool = true) -> Result {
        search(query, filter: filter, recent: recent, correct: correct,
               entries: index, table: stemmedSynonyms, words: vocabulary)
    }

    /// `search`, remembered: Home and the editor read what a search found
    /// several times a pass, so the last few searches are kept and each
    /// runs once per query, filter and recent templates — as Android's
    /// remember(query, …).
    static func remembered(_ query: String, filter: TemplateFilter = TemplateFilter(), recent: Set<String> = [],
                           correct: Bool = true) -> Result {
        let key = RememberedSearch(query: query, filter: filter, recent: recent, correct: correct)
        memoLock.lock()
        let hit = memo.first { $0.key == key }?.result
        memoLock.unlock()
        if let hit { return hit }
        let result = search(query, filter: filter, recent: recent, correct: correct)
        memoLock.lock()
        memo = [(key: key, result: result)] + Array(memo.prefix(3))
        memoLock.unlock()
        return result
    }

    /// What a remembered search was asked with.
    private struct RememberedSearch: Equatable {
        var query: String
        var filter: TemplateFilter
        var recent: Set<String>
        var correct: Bool
    }

    private static var memo: [(key: RememberedSearch, result: Result)] = []
    private static let memoLock = NSLock()

    static func search(_ query: String, filter: TemplateFilter, recent: Set<String>, correct: Bool,
                       entries: [Indexed], table: [String: Set<String>], words: [String: Int]) -> Result {
        let toks = tokens(query)
        guard !toks.isEmpty else { return Result(templates: []) }
        let found = ranked(toks, filter: filter, recent: recent, entries: entries, table: table)
        if !found.isEmpty || !correct { return Result(templates: found) }
        let fixed = toks.map { tok in
            words[tok] != nil || table[stem(tok)] != nil ? tok : (nearest(tok, in: words) ?? tok)
        }
        guard fixed != toks else { return Result(templates: []) }
        let again = ranked(fixed, filter: filter, recent: recent, entries: entries, table: table)
        return again.isEmpty ? Result(templates: []) : Result(templates: again, correctedTo: fixed.joined(separator: " "))
    }

    private static func ranked(_ toks: [String], filter: TemplateFilter, recent: Set<String>,
                               entries: [Indexed], table: [String: Set<String>]) -> [Template] {
        let wanted = toks.map { tok in (tok, expansions(stem(tok), table: table)) }
        var scored: [(template: Template, score: Int, index: Int)] = []
        for (i, e) in entries.enumerated() where filter.admits(template: e.template) {
            var total = 0
            var matched = true
            for (tok, stems) in wanted {
                guard let s = score(tok, stems: stems, entry: e) else {
                    matched = false
                    break
                }
                total += s
            }
            guard matched else { continue }
            if recent.contains(e.template.id) { total += 1 }
            scored.append((e.template, total, i))
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.map(\.template)
    }

    /// What word `tok` (as `stems`) scores on `entry`, or nil when it does
    /// not match. A stem of several words — a synonym "real estate" —
    /// matches where every one of its words does.
    private static func score(_ tok: String, stems: Set<String>, entry e: Indexed) -> Int? {
        func hit(_ field: Set<String>) -> Bool {
            stems.contains { s in s.components(separatedBy: " ").allSatisfy { field.contains($0) } }
        }
        if TemplateFilter.allColors.contains(tok) {
            // A colour is a filter — unless the name says it: "Black Friday".
            if hit(e.name) { return nameScore }
            return e.colors.contains(tok) ? 0 : nil
        }
        if hit(e.name) { return nameScore }
        if hit(e.type) { return typeScore }
        if hit(e.topic) { return topicScore }
        if hit(e.text) { return textScore }
        return nil
    }

    /// The word of `words` nearest `tok`, within reach (see the file's
    /// comment), or nil.
    static func nearest(_ tok: String, in words: [String: Int]) -> String? {
        let reach = tok.count >= 7 ? 2 : 1
        var best: (word: String, distance: Int, count: Int)?
        for (w, n) in words {
            let d = distance(tok, w)
            guard d >= 1, d <= reach else { continue }
            if let b = best {
                let better = d != b.distance ? d < b.distance : (n != b.count ? n > b.count : w < b.word)
                if !better { continue }
            }
            best = (w, d, n)
        }
        return best?.word
    }

    /// The Damerau-Levenshtein distance (optimal string alignment): how
    /// many letters put in, taken out, changed or swapped with the next
    /// make `a` into `b`.
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > 2 { return 3 }
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        guard !x.isEmpty, !y.isEmpty else { return d[x.count][y.count] }
        for i in 1...x.count {
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1 && j > 1 && x[i - 1] == y[j - 2] && x[i - 2] == y[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[x.count][y.count]
    }

    // MARK: completions

    /// How many completions show under the field.
    static let completionLimit = 5

    /// Up to `limit` completions of `query` as it is typed: its last word
    /// finished as each vocabulary word it begins (never the word itself),
    /// those more templates have first, then alphabetically, the words
    /// before it kept — "blue birt" gives "blue birthday". None for a query
    /// ending in a space, or a last word of fewer than 2 letters.
    static func completions(_ query: String, limit: Int = completionLimit) -> [String] {
        completions(query, limit: limit, words: vocabulary)
    }

    static func completions(_ query: String, limit: Int, words: [String: Int]) -> [String] {
        guard let lastCharacter = query.last, !lastCharacter.isWhitespace else { return [] }
        let all = Self.words(query)
        guard let last = all.last, last.count >= 2 else { return [] }
        let head = all.dropLast().joined(separator: " ")
        return words
            .filter { w, n in w.count > last.count && w.hasPrefix(last) && n > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { head.isEmpty ? $0.key : head + " " + $0.key }
    }

    /// "Showing results for “birthday”", over a corrected search.
    static func showingFor(_ corrected: String) -> String { tr("Showing results for “%@”", corrected) }

    /// "Search instead for “brithday”", under it.
    static func searchInstead(_ query: String) -> String {
        tr("Search instead for “%@”", query.trimmingCharacters(in: .whitespaces))
    }
}
