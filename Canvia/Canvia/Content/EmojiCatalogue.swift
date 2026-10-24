// Every emoji the Stickers tab offers — some sixteen hundred, in eight
// groups — from tools/generate_emoji.py's emoji.json, the file the Android
// twin bundles, byte for byte, so both phones list the same glyphs under the
// same names. Each phone leaves out a glyph its own font cannot draw (here
// CTFont, there Paint.hasGlyph) before showing it (EmojiGlyphs); what goes
// on the page is the sticker it has always been, `glyph` and all.
//
// A search reads an emoji's name and keywords and the curated words the
// stickers it always had carry (Stickers.words), so "party" still finds 🎉.
// Recently used (`remembered`) and the last skin tone chosen are kept on
// the phone — UserDefaults here, Prefs on the Android twin — under
// `recentKey` and `toneKey`, never in a design. The Android twin's
// EmojiCatalogue, rule for rule, with the same test rows.

import Foundation

/// One emoji: the glyph `g`, fully qualified; its Unicode name; words to
/// find it by; and whether it takes a skin tone.
struct Emoji: Codable, Equatable, Hashable {
    var g: String
    var name: String
    var keywords: [String] = []
    var tone: Bool = false

    private enum CodingKeys: String, CodingKey { case g, name, keywords, tone }

    init(g: String, name: String, keywords: [String] = [], tone: Bool = false) {
        self.g = g
        self.name = name
        self.keywords = keywords
        self.tone = tone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        g = try c.decode(String.self, forKey: .g)
        name = try c.decode(String.self, forKey: .name)
        keywords = (try? c.decodeIfPresent([String].self, forKey: .keywords)) ?? []
        tone = (try? c.decodeIfPresent(Bool.self, forKey: .tone)) ?? false
    }
}

extension Emoji {

    private static let zwj: UInt32 = 0x200D
    private static let vs15: UInt32 = 0xFE0E
    private static let keycap: UInt32 = 0x20E3

    /// Whether `scalar` is Extended_Pictographic, by the generator's table.
    static func isPictographic(_ scalar: UInt32) -> Bool {
        let table = EmojiCatalogue.pictographic
        var lo = 0, hi = table.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if scalar < table[mid].lowerBound {
                hi = mid - 1
            } else if scalar > table[mid].upperBound {
                lo = mid + 1
            } else {
                return true
            }
        }
        return false
    }

    private static func isRegional(_ scalar: UInt32) -> Bool { (0x1F1E6...0x1F1FF).contains(scalar) }

    /// Whether `cluster` — one character as a reader sees it — is an emoji,
    /// drawn in colour by the phone's emoji font rather than traced as an
    /// outline: a keycap (a digit, # or * with U+20E3), a flag (two regional
    /// indicators), or anything with an Extended_Pictographic code point in
    /// it — ZWJ, skin tone and U+FE0F sequences included — unless U+FE0E
    /// asks for it as text (and no ZWJ joins it). The rule both phones
    /// share, over Fixtures/emoji_clusters.json.
    static func isEmojiCluster(_ cluster: String) -> Bool {
        let scalars = cluster.unicodeScalars.map(\.value)
        guard let first = scalars.first else { return false }
        if scalars.contains(keycap), (0x30...0x39).contains(first) || first == 0x23 || first == 0x2A { return true }
        if scalars.count >= 2, isRegional(scalars[0]), isRegional(scalars[1]) { return true }
        if scalars.contains(vs15), !scalars.contains(zwj) { return false }
        return scalars.contains(where: isPictographic)
    }

    /// `text`'s characters as a reader sees them, each with its UTF-16
    /// range and whether it is an emoji (isEmojiCluster) — what the
    /// outliners place one by one.
    static func clusters(_ text: String) -> [(range: NSRange, emoji: Bool)] {
        var out: [(range: NSRange, emoji: Bool)] = []
        var offset = 0
        for character in text {
            let cluster = String(character)
            let length = cluster.utf16.count
            out.append((range: NSRange(location: offset, length: length), emoji: isEmojiCluster(cluster)))
            offset += length
        }
        return out
    }
}

/// A tab of the catalogue: Smileys & People, Animals & Nature, … Flags.
struct EmojiGroup: Codable, Equatable, Identifiable {
    var name: String
    var emoji: [Emoji]

    var id: String { name }
}

enum EmojiCatalogue {

    /// Where Recently used is kept on the phone: the glyphs, newest first.
    static let recentKey = "recentEmoji"

    /// Where the last skin tone chosen is kept: the modifier, or "" for none.
    static let toneKey = "emojiTone"

    /// How many emoji Recently used keeps.
    static let recentLimit = 24

    /// The five skin tones, light to dark: U+1F3FB to U+1F3FF.
    static let tones: [String] = (UInt32(0x1F3FB)...UInt32(0x1F3FF)).compactMap { Unicode.Scalar($0) }.map { String($0) }

    /// The variation selector that asks for a glyph drawn as an emoji.
    private static let vs16 = Unicode.Scalar(UInt32(0xFE0F))!

    private struct Catalogue: Codable {
        var groups: [EmojiGroup]
        /// The Extended_Pictographic code points as [first, last] pairs.
        var pictographic: [[UInt32]]?
    }

    /// Read once, on first use.
    private static let catalogue: Catalogue = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Catalogue.self, from: data) else {
            assertionFailure("emoji.json missing or invalid")
            return Catalogue(groups: [], pictographic: nil)
        }
        return decoded
    }()

    static var groups: [EmojiGroup] { catalogue.groups }

    /// The Extended_Pictographic code points, as ranges in order
    /// (Emoji.isPictographic): the generator's table, emoji.json's
    /// "pictographic", both phones read.
    static let pictographic: [ClosedRange<UInt32>] = (catalogue.pictographic ?? []).compactMap { pair in
        pair.count == 2 && pair[0] <= pair[1] ? pair[0]...pair[1] : nil
    }

    static let all: [Emoji] = groups.flatMap(\.emoji)

    private static let byGlyph: [String: Emoji] = Dictionary(
        all.map { ($0.g, $0) }, uniquingKeysWith: { first, _ in first })

    /// The emoji `glyph` is, its skin tone aside; nil for one not listed.
    static func of(_ glyph: String) -> Emoji? {
        let plain = untoned(glyph)
        return byGlyph[glyph] ?? byGlyph[plain] ?? byGlyph[plain + String(vs16)]
    }

    /// The group `glyph` is in, by name.
    static func groupOf(_ glyph: String) -> String? {
        guard let emoji = of(glyph) else { return nil }
        return groups.first { group in group.emoji.contains { $0.g == emoji.g } }?.name
    }

    /// What an emoji is found by: its keywords, then the curated words the
    /// same glyph had among the stickers, lower case, each once.
    static func words(_ emoji: Emoji) -> [String] {
        let listed = emoji.keywords + Stickers.words(for: emoji.g) + Stickers.words(for: withoutSelector(emoji.g))
        var seen = Set<String>()
        var out: [String] = []
        for word in listed.map({ $0.lowercased() }) where seen.insert(word).inserted { out.append(word) }
        return out
    }

    /// The emoji a search finds, in catalogue order, within `group` when
    /// one is chosen: those whose name or one of whose words has the query
    /// in it, case aside — every one there for a blank query. An emoji one
    /// of whose words starts with the query comes before one that only has
    /// it inside a word or its name, each part in catalogue order.
    static func search(_ query: String, in group: String? = nil) -> [Emoji] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let from = group.map { name in groups.first { $0.name == name }?.emoji ?? [] } ?? all
        guard !needle.isEmpty else { return from }
        var starts: [Emoji] = []
        var inside: [Emoji] = []
        for e in from {
            let found = words(e)
            if found.contains(where: { $0.hasPrefix(needle) }) {
                starts.append(e)
            } else if found.contains(where: { $0.contains(needle) }) || e.name.lowercased().contains(needle) {
                inside.append(e)
            }
        }
        return starts + inside
    }

    /// `glyph` in skin `tone` (one of `tones`), or without one for nil: the
    /// modifier straight after the emoji, which loses its U+FE0F, as
    /// Unicode's fully-qualified toned sequences are written. A glyph that
    /// takes no tone is returned as it is.
    static func toned(_ glyph: String, _ tone: String?) -> String {
        guard let emoji = of(untoned(glyph)), emoji.tone else { return glyph }
        guard let tone, tones.contains(tone) else { return emoji.g }
        return withoutSelector(emoji.g) + tone
    }

    /// `glyph` without any skin tone in it.
    static func untoned(_ glyph: String) -> String {
        scalars(glyph.unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains($0.value) })
    }

    /// `glyph` without a U+FE0F at its end — compared scalar by scalar, as
    /// a String's own suffix test takes the whole emoji as one character.
    private static func withoutSelector(_ glyph: String) -> String {
        var list = Array(glyph.unicodeScalars)
        if list.last == vs16 { list.removeLast() }
        return scalars(list)
    }

    private static func scalars<S: Sequence>(_ list: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: list)
        return String(view)
    }

    // MARK: Recently used

    /// Recently used with `glyph` first, once, and no more than
    /// recentLimit. A toned glyph is kept as chosen.
    static func remembered(_ recent: [String], _ glyph: String) -> [String] {
        Array(([glyph] + recent.filter { $0 != glyph }).prefix(recentLimit))
    }

    /// Recently used as the phone keeps it: the glyphs, one per line.
    static func encode(_ recent: [String]) -> String {
        recent.joined(separator: "\n")
    }

    /// Recently used read back: blank lines and repeats left out.
    static func decode(_ text: String?) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in (text ?? "").components(separatedBy: "\n")
        where !line.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert(line).inserted {
            out.append(line)
        }
        return Array(out.prefix(recentLimit))
    }

    /// Recently used, as this phone keeps it.
    static func recent(in defaults: UserDefaults = .standard) -> [String] {
        decode(defaults.string(forKey: recentKey))
    }

    /// `glyph` put on a page from the Stickers tab: first in Recently used.
    static func remember(_ glyph: String, in defaults: UserDefaults = .standard) {
        defaults.set(encode(remembered(recent(in: defaults), glyph)), forKey: recentKey)
    }

    /// The skin tone last chosen; nil for none.
    static func lastTone(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: toneKey).flatMap { tones.contains($0) ? $0 : nil }
    }

    /// The skin tone chosen, kept for next time; nil keeps none.
    static func keepTone(_ tone: String?, in defaults: UserDefaults = .standard) {
        defaults.set(tone.flatMap { tones.contains($0) ? $0 : nil } ?? "", forKey: toneKey)
    }
}
