// Stickers found by their own words, and the ones that move.
//
// A glyph carries no words of its own, so Content.json's `stickerNames`
// gives each sticker a few — what it is and what it is for ("🎉" is party
// and celebrate) — the Android twin's Stickers.names, glyph for glyph. And
// Add's Animated row is a glyph from the groups with one of the looping
// moves already set: an ordinary sticker with a loop `animation`, so it
// needs nothing new in a file and moves on either phone.

import Foundation

/// A sticker that keeps moving: `glyph` with the loop `loop` ("pulse",
/// "wiggle", "bounce" or "spin").
struct AnimatedSticker: Identifiable, Equatable {
    var glyph: String
    var loop: String

    var id: String { "\(glyph):\(loop)" }

    /// What it is called aloud: "Party, wiggling" — its glyph's first word
    /// and its move.
    var name: String {
        let word = Stickers.words(for: glyph).first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? glyph
        return "\(word), \(Self.loopWord(loop))"
    }

    /// A loop as it is said: "wiggling".
    private static func loopWord(_ loop: String) -> String {
        switch loop {
        case "pulse": return "pulsing"
        case "wiggle": return "wiggling"
        case "bounce": return "bouncing"
        case "spin": return "spinning"
        default: return loop
        }
    }

    /// The sticker as it goes on a page, `size` square, its loop set.
    func element(size: Double) -> Element {
        var el = Element.sticker(glyph, size: size)
        el.animation = ElementAnimation(kind: loop, delay: 0, duration: 0.6)
        return el
    }
}

enum Stickers {

    /// Words to find each sticker by, lower case, by glyph, from
    /// Content.json's `stickerNames`.
    static var allWords: [String: [String]] { ContentLibrary.bundle.stickerNames ?? [:] }

    /// The words `glyph` goes by; none for a glyph the table lacks.
    static func words(for glyph: String) -> [String] {
        allWords[glyph] ?? []
    }

    /// Add's Animated row: four loops, six of each, as the Android twin
    /// lists them.
    static let animated: [AnimatedSticker] = {
        let rows: [(glyphs: [String], loop: String)] = [
            (["🎉", "🥳", "🦋", "☕", "🔔", "👉"], "wiggle"),
            (["🎂", "❤️", "💥", "😍", "💡", "🔥"], "pulse"),
            (["🎈", "🏆", "😂", "🍕", "🎵", "🚀"], "bounce"),
            (["✨", "⭐", "💫", "🌸", "☀️", "🌻"], "spin"),
        ]
        return rows.flatMap { row in row.glyphs.map { AnimatedSticker(glyph: $0, loop: row.loop) } }
    }()

    /// A search as it is matched: trimmed, lower case.
    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether `glyph` goes by `needle`: one of its words contains it.
    private static func matches(_ glyph: String, _ needle: String) -> Bool {
        words(for: glyph).contains { $0.contains(needle) }
    }

    /// The groups a search finds: a group whose name matches, whole; else,
    /// in each group, the stickers one of whose words matches, a group with
    /// none dropping out. A blank search is every group.
    static func search(_ query: String, in groups: [StickerGroup]) -> [StickerGroup] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group -> StickerGroup? in
            if group.name.lowercased().contains(needle) { return group }
            let found = group.emoji.filter { matches($0, needle) }
            return found.isEmpty ? nil : StickerGroup(name: group.name, emoji: found)
        }
    }

    /// The animated stickers a search finds, by their glyphs' words or
    /// their loop, or "animated" for all of them.
    static func searchAnimated(_ query: String) -> [AnimatedSticker] {
        let needle = normalized(query)
        if needle.isEmpty || "animated".contains(needle) { return animated }
        return animated.filter { matches($0.glyph, needle) || $0.loop.contains(needle) }
    }
}
