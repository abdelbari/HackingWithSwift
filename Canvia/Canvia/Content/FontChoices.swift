// What the font picker lists, and the fonts last chosen on this phone. The
// sheet itself is FontSheet; the words and the order are the Android
// twin's.
//
// Browsing — nothing searched, "All" — the brand kit's fonts come first,
// then Recently used (the last eight chosen on this phone, newest first),
// the fonts In this design, Your fonts with "Add a font…", and then every
// font. A search or a category lists only the fonts it finds: the library's
// in catalogue order, then — under "All" only — fonts of your own whose
// names match.

import Foundation

enum FontChoices {

    static let brandTitle = "Brand fonts"
    static let recentTitle = "Recently used"
    static let inDesignTitle = "In this design"
    static let yoursTitle = "Your fonts"
    static let allTitle = "All fonts"

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
         Section(title: inDesignTitle, keys: FontLibrary.usedIn(design))]
            .filter { !$0.keys.isEmpty }
    }

    /// Whether the picker is browsing rather than finding.
    static func isBrowsing(query: String, category: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && category == FontLibrary.allCategories
    }

    /// What a search or a category finds, by key: the library's fonts, then
    /// the fonts of your own whose names match, under "All" only.
    static func found(query: String, category: String, own: [Uploads.FontEntry]) -> [String] {
        let library = FontLibrary.search(query, category: category).map(\.id)
        guard category == FontLibrary.allCategories else { return library }
        return library + own.filter { FontLibrary.matches($0.name, query) }.map(\.key)
    }

    /// What the picker says when nothing is found.
    static func noneFound(_ query: String) -> String {
        "No fonts match \u{201C}\(query.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}."
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
