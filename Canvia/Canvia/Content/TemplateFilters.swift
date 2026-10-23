// What a built-in template is filtered by on Home's and the Start sheet's
// Filters sheet — the Android twin's TemplateFilters.kt, by the same rules.

import Foundation

/// A template's facets, as its JSON has them under "facets":
/// {"colors": ["blue", "white"], "animated": false, "photo": false, "pages": 1}.
/// Worked out once, by the templates generator (facets_of), so both phones
/// agree: `colors` are up to three of TemplateFilter.colors, most first,
/// each covering more than 12% of the template, weighing every page's
/// background by its area and every shape's fill by its box times its
/// opacity.
struct TemplateFacets: Codable, Equatable {
    var colors: [String] = []
    var animated = false
    var photo = false
    var pages = 1

    init(colors: [String] = [], animated: Bool = false, photo: Bool = false, pages: Int = 1) {
        self.colors = colors
        self.animated = animated
        self.photo = photo
        self.pages = pages
    }

    /// Anything missing, or not of its kind, reads as a template with none.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colors = (try? c.decode([String].self, forKey: .colors)) ?? []
        animated = (try? c.decode(Bool.self, forKey: .animated)) ?? false
        photo = (try? c.decode(Bool.self, forKey: .photo)) ?? false
        pages = (try? c.decode(Int.self, forKey: .pages)) ?? 1
    }

    private enum CodingKeys: String, CodingKey { case colors, animated, photo, pages }
}

/// The Filters sheet's choices. Each that is set narrows the templates; an
/// empty filter lets every one through. `colors` lets through a template
/// with ANY of them (the simplest rule: each dot picked adds its
/// templates); `animated` and `photo` a template that is, or is not; and
/// `multiPage` a set of several pages (true) or a single page (false).
struct TemplateFilter: Equatable {
    var colors: Set<String> = []
    var animated: Bool?
    var photo: Bool?
    var multiPage: Bool?

    var isEmpty: Bool { colors.isEmpty && animated == nil && photo == nil && multiPage == nil }

    func admits(_ facets: TemplateFacets) -> Bool {
        (colors.isEmpty || facets.colors.contains { colors.contains($0) })
            && (animated == nil || facets.animated == animated)
            && (photo == nil || facets.photo == photo)
            && (multiPage == nil || (facets.pages > 1) == multiPage)
    }

    /// One of the dismissible chips under the search: what it says, and
    /// the filter without it.
    struct Chip: Identifiable {
        let label: String
        let without: TemplateFilter
        var id: String { label }
    }

    /// The chips for what is set, in the sheet's order: each colour, then
    /// Animated, With photos, Single page or Set.
    var chips: [Chip] {
        var out: [Chip] = []
        for c in Self.allColors where colors.contains(c) {
            var rest = self
            rest.colors.remove(c)
            out.append(Chip(label: Self.colorName(c), without: rest))
        }
        if let animated {
            var rest = self
            rest.animated = nil
            out.append(Chip(label: animated ? tr("Animated") : tr("Not animated"), without: rest))
        }
        if let photo {
            var rest = self
            rest.photo = nil
            out.append(Chip(label: photo ? tr("With photos") : tr("Without photos"), without: rest))
        }
        if let multiPage {
            var rest = self
            rest.multiPage = nil
            out.append(Chip(label: multiPage ? tr("Set", context: "pages") : tr("Single page"), without: rest))
        }
        return out
    }

    /// The twelve colours, in the sheet's order — the generator's
    /// COLOR_BUCKETS.
    static let allColors = ["red", "orange", "yellow", "green", "teal", "blue",
                         "purple", "pink", "brown", "black", "white", "grey"]

    /// The dot each is drawn as.
    static let swatches: [String: String] = [
        "red": "#e53935", "orange": "#fb8c00", "yellow": "#fdd835", "green": "#43a047",
        "teal": "#00897b", "blue": "#1e88e5", "purple": "#8e24aa", "pink": "#ec407a",
        "brown": "#6d4c41", "black": "#000000", "white": "#ffffff", "grey": "#9e9e9e",
    ]

    /// A colour's name, as VoiceOver says its dot and its chip.
    static func colorName(_ id: String) -> String {
        switch id {
        case "red": return tr("Red")
        case "orange": return tr("Orange")
        case "yellow": return tr("Yellow")
        case "green": return tr("Green")
        case "teal": return tr("Teal")
        case "blue": return tr("Blue")
        case "purple": return tr("Purple")
        case "pink": return tr("Pink")
        case "brown": return tr("Brown")
        case "black": return tr("Black")
        case "white": return tr("White")
        default: return tr("Grey")
        }
    }

    /// What an empty result says, above Clear filters.
    static var noMatch: String { tr("No templates match those filters") }

    /// The filter last used, this session only: both Home and the Start
    /// sheet start from it, and it is gone when the app is.
    static var session = TemplateFilter()
}
