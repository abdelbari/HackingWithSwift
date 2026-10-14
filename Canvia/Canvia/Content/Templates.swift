// What a template is shown beside: "More like this" under its preview, and,
// for a design type with few templates of its own, those of other sizes
// "Adapted from other sizes" — each ranked by one rule, the Android twin's
// Templates.similar and Templates.nearby, so both phones list them in the
// same order (Tests/Fixtures/similar.json and nearby.json, the twin's
// templates/similar.json and nearby.json).

import Foundation

enum Templates {

    // MARK: more like this

    /// How many "More like this" shows.
    static let similarCount = 8

    /// The words of a template's name, once each: lowercased and split at
    /// anything that is not a letter or a digit — "We’ve Moved Postcard" is
    /// we, ve, moved and postcard.
    static func nameTokens(_ name: String) -> Set<String> {
        Set(name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    /// How alike `other` is to `template`: 3 for the same category, 2 for
    /// the same size — exactly, in pixels, which is the design type it was
    /// made for — and 1 for each word their names share.
    static func likeness(_ other: Template, to template: Template) -> Int {
        var score = other.category == template.category ? 3 : 0
        if other.width == template.width && other.height == template.height { score += 2 }
        return score + nameTokens(other.name).intersection(nameTokens(template.name)).count
    }

    /// The `limit` templates most like `template`, itself left out: the
    /// highest likeness first, a tie in the library's order.
    static func similar(_ template: Template, limit: Int = similarCount,
                        among library: [Template] = ContentLibrary.templates) -> [Template] {
        let scored: [(offset: Int, template: Template, score: Int)] = library.enumerated()
            .filter { $0.element.id != template.id }
            .map { (offset: $0.offset, template: $0.element, score: likeness($0.element, to: template)) }
        let ranked = scored.sorted { a, b in a.score != b.score ? a.score > b.score : a.offset < b.offset }
        return ranked.prefix(max(0, limit)).map { $0.template }
    }

    // MARK: adapted from other sizes

    /// How many a design type borrows at most.
    static let nearbyCount = 12

    /// How far apart two shapes may be and still be borrowed: |ln| of the
    /// ratio of their aspect ratios under a quarter — a square lends to 4:5,
    /// 16:9 to 4:3 not at all.
    static let nearbyReach = 0.25

    /// |ln(aspect of the template ÷ aspect of the type)|: twice as wide and
    /// twice as tall are as far.
    static func aspectDistance(_ template: Template, _ preset: SizePreset) -> Double {
        guard template.width > 0, template.height > 0, preset.w > 0, preset.h > 0 else { return .infinity }
        return abs(log((template.width / template.height) / (preset.w / preset.h)))
    }

    /// The category family a template belongs to — Social, Video, Print,
    /// Documents, Presentations or Marketing — as the first design type
    /// made at its size has it: its own size, or the one its templates had
    /// before (SizePreset.formerPixels, the A5 flyer's). Nil when no type is
    /// its size.
    static func family(of template: Template, in presets: [SizePreset] = SizePreset.all) -> String? {
        presets.first { isOwn(template, of: $0) }?.category
    }

    /// Whether a template is one of the type's own: made at its size, or at
    /// the size it had before (SizePreset.formerPixels).
    static func isOwn(_ template: Template, of preset: SizePreset) -> Bool {
        if template.width == preset.w && template.height == preset.h { return true }
        guard let former = SizePreset.formerPixels[preset.id] else { return false }
        return template.width == former.width && template.height == former.height
    }

    /// The templates of other sizes a type borrows, at most `limit`: those
    /// within nearbyReach of its shape, nearest first; at the same distance
    /// those of the type's own family first; then the library's order.
    static func nearbyTemplates(_ preset: SizePreset, limit: Int = nearbyCount,
                                among library: [Template] = ContentLibrary.templates,
                                presets: [SizePreset] = SizePreset.all) -> [Template] {
        let ranked = library.enumerated().compactMap { entry -> (Double, Int, Int, Template)? in
            let template = entry.element
            guard !isOwn(template, of: preset) else { return nil }
            let distance = aspectDistance(template, preset)
            guard distance < nearbyReach else { return nil }
            let kin = family(of: template, in: presets) == preset.category ? 0 : 1
            return (distance, kin, entry.offset, template)
        }
        let sorted = ranked.sorted { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            if a.1 != b.1 { return a.1 < b.1 }
            return a.2 < b.2
        }
        return sorted.prefix(max(0, limit)).map { $0.3 }
    }

    /// A template of another size, as a design of the type would start
    /// from it: every page reflowed to the type's size by Copy & resize's
    /// rule, in the type's unit, under the template's name.
    struct Adapted: Identifiable {
        let template: Template
        let design: Design
        var id: String { template.id }
    }

    static func adapted(_ template: Template, to preset: SizePreset) -> Design {
        CopyResize.copy(of: template.instantiate(), to: .preset(preset), title: template.name)
    }

    /// nearbyTemplates, each made at the type's size.
    static func nearby(_ preset: SizePreset, limit: Int = nearbyCount,
                       among library: [Template] = ContentLibrary.templates) -> [Adapted] {
        nearbyTemplates(preset, limit: limit, among: library).map {
            Adapted(template: $0, design: adapted($0, to: preset))
        }
    }

    /// How many each type borrows, by preset id, for its tile.
    static let nearbyCounts: [String: Int] = Dictionary(
        SizePreset.all.map { ($0.id, nearbyTemplates($0).count) },
        uniquingKeysWith: { first, _ in first })

    /// A type's tile: "4 ready-made", or with templates borrowed, "0 + 12
    /// adapted".
    static func countText(own: Int, adapted: Int) -> String {
        adapted > 0 ? tr("%d + %d adapted", own, adapted) : trn("%d ready-made|%d ready-made", own)
    }

    /// The same, as VoiceOver says it.
    static func spokenCount(own: Int, adapted: Int) -> String {
        adapted > 0 ? tr("%d + %d adapted", own, adapted)
            : trn("%d ready-made designs|%d ready-made designs", own)
    }

    /// The tile's line for a type, from the counts.
    static func countText(for preset: SizePreset) -> String {
        countText(own: ContentLibrary.templateCounts[preset.id] ?? 0, adapted: nearbyCounts[preset.id] ?? 0)
    }

    static func spokenCount(for preset: SizePreset) -> String {
        spokenCount(own: ContentLibrary.templateCounts[preset.id] ?? 0, adapted: nearbyCounts[preset.id] ?? 0)
    }

    /// The preview's header, and what VoiceOver says of a "More like this"
    /// card: "Business · 1920 × 1080 · 10 pages". A template drawn on paper
    /// is measured in the unit it opens in (instantiate), "210 × 297 mm";
    /// the pages are left off for one.
    static func caption(_ template: Template) -> String {
        let paper = SizePreset.all.first { $0.unit != nil && $0.w == template.width && $0.h == template.height }
        var parts = [UserTemplates.shownCategory(template.category),
                     Units.dimensions(width: template.width, height: template.height, unit: paper?.unit, dpi: paper?.dpi)]
        if template.pageCount > 1 { parts.append(trn("%d page|%d pages", template.pageCount)) }
        return parts.joined(separator: " · ")
    }
}
