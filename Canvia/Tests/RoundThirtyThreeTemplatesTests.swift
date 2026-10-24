// Round 33's templates: the animated ones and the colourway variants, as
// the Android twin's templates/round33-animated.json and round33-variants.json
// are written into Content.json by its generator — the same JSON its
// Templates.json carries, so both phones load the same templates. The rows
// are the twin's RoundThirtyThreeTemplatesTest.

import XCTest
@testable import Canvia

final class RoundThirtyThreeTemplatesTests: XCTestCase {

    private var library: [Template] { ContentLibrary.templates }

    private func template(_ id: String) throws -> Template {
        try XCTUnwrap(library.first { $0.id == id }, id)
    }

    /// Content.json's templates as written, to read each key as it is.
    private func rawTemplates() throws -> [[String: Any]] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Content", withExtension: "json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(object["templates"] as? [[String: Any]])
    }

    private var animatedRaw: [[String: Any]] {
        get throws { try rawTemplates().filter { $0["topic"] as? String == "animated" } }
    }

    // MARK: animated

    /// Shared: every animated template is Animated in the Filters sheet.
    func testEveryAnimatedTemplateIsMarkedAnimatedAndTheFilterIsNoLongerEmpty() throws {
        let animated = try animatedRaw
        XCTAssertGreaterThanOrEqual(animated.count, 40)
        for raw in animated {
            let t = try template(try XCTUnwrap(raw["id"] as? String))
            XCTAssertTrue(t.shownFacets.animated, t.id)
            XCTAssertEqual(t.topic, "animated", t.id)
        }
        let filtered = ContentLibrary.filteredTemplates(in: nil, matching: "", facets: TemplateFilter(animated: true))
        XCTAssertGreaterThanOrEqual(filtered.count, 40)
        XCTAssertEqual(Templates.animated.map(\.id), filtered.map(\.id))
    }

    func testTheAnimatedKindsAreAllThereAndPresentationsOfFivePages() {
        func count(_ w: Double, _ h: Double) -> Int { Templates.animated.filter { $0.width == w && $0.height == h }.count }
        // Reels, Stories and TikToks share 1080 x 1920.
        XCTAssertGreaterThanOrEqual(count(1080, 1920), 21)
        XCTAssertGreaterThanOrEqual(count(1080, 1080), 7)
        // YouTube intros and the presentations share 1920 x 1080.
        XCTAssertGreaterThanOrEqual(count(1920, 1080), 9)
        XCTAssertGreaterThanOrEqual(count(1500, 2100), 5)
        let decks = Templates.animated.filter { $0.pageCount > 1 }
        XCTAssertEqual(decks.count, 3)
        XCTAssertTrue(decks.allSatisfy { $0.pageCount == 5 })
    }

    /// Shared: what an animated template carries decodes as a design's own
    /// keys — entrances and exits, a page's animation, transition and hold,
    /// a loop behind it and the sound it starts with — and a design made
    /// from it keeps them.
    func testAnAnimatedTemplatesKeysDecodeAsADesigns() throws {
        var exits = 0
        var units = 0
        var photos = 0
        var drawn = 0
        var loops = 0
        let animated = try animatedRaw
        for raw in animated {
            let t = try template(try XCTUnwrap(raw["id"] as? String))
            let design = t.instantiate()
            let pages = (raw["pages"] as? [[String: Any]]) ?? [raw]
            XCTAssertEqual(pages.count, design.pages.count, t.id)
            for (source, page) in zip(pages, design.pages) {
                XCTAssertEqual(source["transition"] as? String, page.transition, t.id)
                XCTAssertEqual(source["holdSeconds"] as? Double, page.holdSeconds, t.id)
                let pageAnimation = source["pageAnimation"] as? [String: Any]
                XCTAssertEqual(pageAnimation?["kind"] as? String, page.pageAnimation?.kind, t.id)
                let background = try XCTUnwrap(source["background"] as? [String: Any])
                if background["type"] as? String == "image" {
                    XCTAssertEqual(page.background, .image(try XCTUnwrap(background["value"] as? String)), t.id)
                    if MotionLibrary.isBackground(page) { loops += 1 }
                }
                let elements = try XCTUnwrap(source["elements"] as? [[String: Any]])
                XCTAssertEqual(elements.count, page.elements.count, t.id)
                for (el, made) in zip(elements, page.elements) {
                    if let anim = el["animation"] as? [String: Any] {
                        let read = try XCTUnwrap(made.animation, t.id)
                        XCTAssertEqual(anim["kind"] as? String, read.kind, t.id)
                        XCTAssertEqual(anim["by"] as? String, read.by, t.id)
                        if ElementAnimation.unitKinds.contains(read.kind) { units += 1 }
                        if read.kind == "photoZoom" || read.kind == "photoPan" { photos += 1 }
                        if read.kind == "draw" || read.kind == "twinkle" { drawn += 1 }
                    }
                    if el["exitAnimation"] != nil {
                        XCTAssertNotNil(made.exitAnimation, t.id)
                        exits += 1
                    }
                }
            }
            if let audio = raw["audio"] as? [[String: Any]] {
                let sound = try XCTUnwrap(audio.first?["src"] as? String)
                XCTAssertTrue(sound.hasPrefix(AudioTrack.sfxPrefix), t.id)
                // It goes with a design made from the template, at any size.
                XCTAssertEqual(design.audioTracks.map(\.src), [sound], t.id)
            }
        }
        XCTAssertGreaterThan(exits, 0)
        XCTAssertGreaterThan(units, 0)
        XCTAssertGreaterThan(photos, 0)
        XCTAssertGreaterThan(drawn, 0)
        XCTAssertGreaterThan(loops, 0)
    }

    func testTheSoundGoesWithADesignAtATypesSize() throws {
        let t = try XCTUnwrap(Templates.animated.first { !($0.audio ?? []).isEmpty })
        let preset = try XCTUnwrap(SizePreset.all.first { $0.w == t.width && $0.h == t.height })
        XCTAssertEqual(t.instantiate(for: preset).audioTracks.map(\.src), t.audio?.map(\.src))
    }

    // MARK: colourways

    /// Shared: 4 colourways x 2 font combinations of every base.
    func testEveryBaseComesInEightVariantsWithItsTopicAndStyle() throws {
        // Round 34's starts are topped by the type they were made for
        // ("report", "carousel", …), and come in no colourways.
        let round34 = Set(SizePreset.all.map(\.id)).union(["carousel", "report"])
        let variants = library.filter { $0.topic != nil && $0.topic != "animated" && !round34.contains($0.topic ?? "") }
        XCTAssertGreaterThanOrEqual(variants.count, 600)
        let bases = variants.filter { $0.variantOf == nil }
        XCTAssertFalse(bases.isEmpty)
        for base in bases {
            let family = Templates.colourways(base)
            XCTAssertEqual(family.count, 8, base.id)
            XCTAssertEqual(family.first?.id, base.id)
            XCTAssertTrue(family.dropFirst().allSatisfy { $0.variantOf == base.id && $0.topic == base.topic }, base.id)
            XCTAssertTrue(family.allSatisfy { TemplateFilter.styles.contains($0.shownFacets.style ?? "") }, base.id)
            XCTAssertEqual(base.pageCount, 1, base.id)
            // Photo variants and plain ones among them.
            XCTAssertTrue(family.contains { $0.shownFacets.photo } && family.contains { !$0.shownFacets.photo }, base.id)
            XCTAssertEqual(Templates.colourwaysBadge(base), trn("%d colourway|%d colourways", 8))
        }
        XCTAssertEqual(Set(variants.compactMap(\.topic)),
                       ["real-estate", "fitness", "restaurant", "beauty", "wedding", "education", "nonprofit",
                        "tech", "travel", "receipts", "coupons", "business-cards"])
    }

    func testTheStaplesAreFoundBySearch() {
        func found(_ query: String) -> Int { ContentLibrary.filteredTemplates(in: nil, matching: query).count }
        XCTAssertGreaterThanOrEqual(found("real estate"), 50)
        XCTAssertGreaterThanOrEqual(found("fitness"), 50)
        XCTAssertGreaterThan(found("receipt"), 0)
        XCTAssertGreaterThanOrEqual(found("coupon"), 50)
    }

    func testTheStyleFilterLetsThroughOnlyItsStyleAndSaysSoOnItsChip() {
        let elegant = ContentLibrary.filteredTemplates(in: nil, matching: "", facets: TemplateFilter(style: "elegant"))
        XCTAssertFalse(elegant.isEmpty)
        XCTAssertTrue(elegant.allSatisfy { $0.shownFacets.style == "elegant" })
        XCTAssertFalse(TemplateFilter(style: "bold").isEmpty)
        XCTAssertEqual(TemplateFilter(style: "elegant").chips.map(\.label), ["Elegant"])
        XCTAssertEqual(TemplateFilter(style: "elegant").chips.first?.without, TemplateFilter())
        XCTAssertEqual(TemplateFilter.styles.count, 5)
        XCTAssertEqual(TemplateFilter.styleName("bold"), tr("Bold", context: "style"))
    }

    func testAStartSheetShowsEachLayoutOnceItsColourwaysUnderIt() throws {
        let base = try template("fitness-insta-post-hero-1")
        let family = Templates.colourways(base)
        // All eight in: only the base shows.
        XCTAssertEqual(Templates.grouped(family).map(\.id), [base.id])
        // A variant whose base a filter left out stays.
        XCTAssertEqual(Templates.grouped(Array(family.dropFirst())).map(\.id), family.dropFirst().map(\.id))
        // More colourways is the rest of the family, from the base or a variant.
        XCTAssertEqual(Templates.moreColourways(base).map(\.id), family.dropFirst().map(\.id))
        XCTAssertEqual(Templates.moreColourways(family[1]).map(\.id), [base.id] + family.dropFirst(2).map(\.id))
        // A template with none has none.
        let plain = try template("mega-sale-post")
        XCTAssertEqual(Templates.colourways(plain).map(\.id), [plain.id])
        XCTAssertNil(Templates.colourwaysBadge(plain))
    }

    /// Shared: More like this leads with the rest of the family.
    func testSimilarRanksTheVariantsOfTheSameBaseFirst() throws {
        let variant = try template("travel-postcard-hero-3-v4")
        let similar = Templates.similar(variant)
        XCTAssertEqual(similar.count, Templates.similarCount)
        let kin = Templates.moreColourways(variant)
        XCTAssertEqual(Array(similar.prefix(kin.count)).map(\.id), kin.map(\.id))
        XCTAssertFalse(similar.contains { $0.id == variant.id })
        // A limit under the family's size is all family.
        XCTAssertEqual(Templates.similar(variant, limit: 3).map(\.id), kin.prefix(3).map(\.id))
    }

    func testAdaptedStartsAreNeverColourways() {
        for preset in SizePreset.all {
            XCTAssertTrue(Templates.nearbyTemplates(preset).allSatisfy { $0.variantOf == nil }, preset.id)
        }
    }

    /// Shared: the library's JSON stays within the content budget — the
    /// templates under the 3,000,000 bytes the generator holds them to
    /// (BUNDLE_LIMIT, as Content.json writes them, indent 1), and the whole
    /// file, round 34's design types and their templates with them, under
    /// 3,500,000.
    func testTheContentBundleStaysUnderItsBudget() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Content", withExtension: "json"))
        let bytes = try XCTUnwrap(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThan(bytes, 3_500_000)
        let templates = try XCTUnwrap(try rawTemplates())
        let compact = try JSONSerialization.data(withJSONObject: templates)
        XCTAssertLessThan(compact.count, 3_000_000)
    }

    /// A template's own keys read leniently: wrong kinds are none.
    func testTemplateKeysReadLeniently() throws {
        let json = #"""
        {"id": "t", "name": "T", "category": "Social", "width": 100, "height": 100,
         "background": {"type": "image", "value": "motion:x"}, "elements": [],
         "holdSeconds": "long", "transition": "fade", "topic": 3, "variantOf": "base",
         "pageAnimation": {"kind": "rise", "mode": "both"}}
        """#
        let t = try JSONDecoder().decode(Template.self, from: Data(json.utf8))
        XCTAssertNil(t.holdSeconds)
        XCTAssertNil(t.topic)
        XCTAssertEqual(t.variantOf, "base")
        XCTAssertEqual(t.family, "base")
        XCTAssertEqual(t.instantiate().pages[0].transition, "fade")
        XCTAssertEqual(t.instantiate().pages[0].pageAnimation, PageAnimation(kind: "rise", mode: "both"))
    }
}
