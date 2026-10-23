// What the font picker lists, and the fonts last chosen on this phone. The
// sheet itself is FontSheet; the words and the order are the Android
// twin's.
//
// Browsing — nothing searched, "All" — the brand kit's fonts come first,
// then Recently used (the last eight chosen on this phone, newest first),
// Popular (the eight ranked so in the catalogue), the fonts In this design,
// Your fonts with "Add a font…", and then every font. A search or a
// category lists only the fonts it finds — by name, category or style tag
// (FontLibrary.matches) — the library's in catalogue order, then — under
// "All" only — fonts of your own whose names match. Fonts of your own are
// listed a family a row, by the key of its Regular face
// (CustomFonts.families). A search that finds nothing offers tags to try
// (FontLibrary.suggestedTags) as chips that fill the search.

import Foundation

enum FontChoices {

    static let brandTitle = tr("Brand fonts")
    static let recentTitle = tr("Recently used")
    static let popularTitle = tr("Popular")
    /// Over the tag chips when a search finds nothing.
    static let tryTitle = tr("Try:")
    static let inDesignTitle = tr("In this design")
    static let yoursTitle = tr("Your fonts")
    static let allTitle = tr("All fonts")

    /// One run of fonts under a heading, by key.
    struct Section: Equatable, Identifiable {
        var title: String
        var keys: [String]

        var id: String { title }
    }

    /// The brand kit's faces, by role from title to caption, resolved,
    /// once each.
    static func brandFonts(_ kit: BrandKit) -> [String] {
        var out: [String] = []
        for family in BrandFonts.Role.allCases.compactMap({ kit.fonts[$0]?.family }) {
            let id = FontLibrary.resolve(family)
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    /// The runs above Your fonts while browsing, each left out when it has
    /// nothing in it.
    static func browsing(kit: BrandKit, recent: [String], design: Design) -> [Section] {
        [Section(title: brandTitle, keys: brandFonts(kit)),
         Section(title: recentTitle, keys: recent),
         Section(title: popularTitle, keys: FontLibrary.popular.map(\.id)),
         Section(title: inDesignTitle, keys: families(FontLibrary.usedIn(design), design: design))]
            .filter { !$0.keys.isEmpty }
    }

    /// Keys with each font of your own as its family's Regular face, once
    /// (FontStore.familyKey).
    static func families(_ keys: [String], design: Design) -> [String] {
        var seen = Set<String>()
        return keys.map { FontStore.familyKey($0, in: design) }.filter { seen.insert($0).inserted }
    }

    /// Whether the picker is browsing rather than finding.
    static func isBrowsing(query: String, category: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && category == FontLibrary.allCategories
    }

    /// What a search or a category finds, by key: the library's fonts — by
    /// name, category or tag — then the fonts of your own whose names
    /// match, under "All" only.
    static func found(query: String, category: String, own: [Uploads.FontEntry]) -> [String] {
        let library = FontLibrary.search(query, category: category).map(\.id)
        guard category == FontLibrary.allCategories else { return library }
        return library + CustomFonts.families(own).filter { FontLibrary.matches($0.name, query) }.map(\.key)
    }

    /// What the picker says when nothing is found.
    static func noneFound(_ query: String) -> String {
        tr("No fonts match \u{201C}%@\u{201D}.", query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// The fonts last chosen on this phone, newest first, eight of them
/// (FontLibrary.recent): the font picker's Recently used. Per phone, as
/// the Android twin keeps its own.
enum RecentFonts {
    private static let key = "canvia.recentFonts"

    static func all(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func record(_ font: String, defaults: UserDefaults = .standard) {
        defaults.set(FontLibrary.recent(all(defaults), adding: font), forKey: key)
    }
}
