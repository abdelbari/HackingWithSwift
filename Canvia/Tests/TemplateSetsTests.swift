// Template sets: built-in templates of several pages (decks, two-sided
// cards, folded cards, two-page resumes and tri-fold brochures), the design
// types added beside them, and "Apply all N pages" — which replaces an empty
// design and otherwise follows the page open, as one undo step. The rows are
// the Android twin's, so both phones ship and apply the same sets.

import XCTest
@testable import Canvia

final class TemplateSetsTests: XCTestCase {

    private var sets: [Template] { ContentLibrary.templates.filter { $0.pageCount > 1 } }

    private func sets(width: Double, height: Double) -> [Template] {
        sets.filter { $0.width == width && $0.height == height }
    }

    // MARK: what ships

    func testTheSetsTheSpecAsksFor() {
        let decks = sets(width: 1920, height: 1080)
        XCTAssertGreaterThanOrEqual(decks.count, 8, "eight decks")
        for deck in decks {
            XCTAssertTrue((8...12).contains(deck.pageCount), "\(deck.id) has \(deck.pageCount) slides")
        }
        let cards = sets(width: 1050, height: 600)
        XCTAssertGreaterThanOrEqual(cards.count, 6, "six two-sided business cards")
        XCTAssertTrue(cards.allSatisfy { $0.pageCount == 2 })
        let folded = sets(width: 1500, height: 2100)
        XCTAssertGreaterThanOrEqual(folded.count, 4, "four folded cards at 5 × 7 in")
        XCTAssertTrue(folded.allSatisfy { $0.pageCount == 2 })
        let resumes = sets(width: 2480, height: 3508) + sets(width: 2550, height: 3300)
        XCTAssertGreaterThanOrEqual(resumes.filter { $0.name.contains("Resume") }.count, 4, "four two-page resumes")
        let brochures = sets(width: 3300, height: 2550)
        XCTAssertGreaterThanOrEqual(brochures.count, 3, "three tri-fold brochures")
        XCTAssertTrue(brochures.allSatisfy { $0.pageCount == 2 })
    }

    /// The sets by id and page count, as the Android twin's TemplateSpecs
    /// lists them: the two generated outputs agree page for page.
    func testTheSetsPageForPage() {
        let rows: [(String, Int)] = [
            ("deck-seed-round-pitch", 12), ("deck-quarterly-business-review", 10), ("deck-marketing-plan", 10),
            ("deck-product-launch", 9), ("deck-science-lesson", 8), ("deck-project-kickoff", 9),
            ("deck-travel-guide", 8), ("deck-cooking-class", 8),
            ("card-set-harbour-architects", 2), ("card-set-fernwood-florist", 2), ("card-set-voltline-electric", 2),
            ("card-set-pixel-and-pine", 2), ("card-set-calm-practice", 2), ("card-set-golden-crumb", 2),
            ("folded-birthday-balloons", 2), ("folded-thank-you-botanical", 2), ("folded-congrats-confetti", 2),
            ("folded-season-greetings", 2),
            ("resume-two-page-slate", 2), ("resume-two-page-sage", 2), ("resume-two-page-ink", 2),
            ("resume-two-page-coral", 2),
            ("brochure-trifold-dental", 2), ("brochure-trifold-yoga", 2), ("brochure-trifold-museum", 2),
        ]
        for (id, count) in rows {
            let t = ContentLibrary.templates.first { $0.id == id }
            XCTAssertEqual(t?.pageCount, count, id)
        }
        XCTAssertEqual(sets.count, rows.count, "a set not in the table")
        let deck = ContentLibrary.templates.first { $0.id == "deck-seed-round-pitch" }
        XCTAssertEqual(deck?.pageSpecs.first?.title, "Title")
        XCTAssertEqual(deck?.pageSpecs.last?.title, "Thank you")
        let card = ContentLibrary.templates.first { $0.id == "card-set-harbour-architects" }
        XCTAssertEqual(card?.pageSpecs.map(\.title), ["Front", "Back"])
    }

    /// Every page of every set is one a design could start from: something
    /// on it, nothing lost off it, shapes and fonts the library has, and
    /// the top level is its first page.
    func testEveryPageOfEverySetIsUsable() {
        for t in sets {
            XCTAssertEqual(t.background, t.pageSpecs[0].background, t.id)
            XCTAssertEqual(t.elements.count, t.pageSpecs[0].elements.count, t.id)
            for (n, spec) in t.pageSpecs.enumerated() {
                let at = "\(t.id) page \(n + 1)"
                XCTAssertFalse(spec.elements.isEmpty, "\(at) is empty")
                XCTAssertLessThanOrEqual(spec.elements.count, 20, at)
                for el in spec.elements {
                    XCTAssertTrue(el.x + el.w > 0 && el.y + el.h > 0, "\(at): \(el.type) off the top-left")
                    XCTAssertTrue(el.x < t.width && el.y < t.height, "\(at): \(el.type) off the bottom-right")
                    if el.type == .shape {
                        XCTAssertEqual(ContentLibrary.shape(el.shapeId).id, el.shapeId, at)
                    }
                    if el.type == .text {
                        XCTAssertGreaterThanOrEqual(el.fontSize ?? 0, 14, "\(at): tiny type")
                        if let family = el.fontFamily {
                            XCTAssertTrue(FontLibrary.all.contains { $0.id == family } || FontLibrary.aliases[family] != nil,
                                          "\(at) names font \(family)")
                        }
                    }
                }
            }
            let design = t.instantiate()
            XCTAssertEqual(design.pages.count, t.pageCount, t.id)
            XCTAssertEqual(Set(design.pages.map(\.id)).count, t.pageCount, "\(t.id): fresh page ids")
        }
    }

    // MARK: reading

    /// "pages" replaces the top-level background and elements, which may be
    /// left out; titles and notes go to the pages made; an old single-page
    /// entry reads as it did.
    func testPagesReadAndOldEntriesStillRead() throws {
        let json = ##"""
        {"id":"d","name":"Deck","category":"Business","width":100,"height":50,
         "pages":[{"background":{"type":"color","value":"#111111"},"elements":[{"type":"text","x":0,"y":0,"w":80,"text":"One","fontSize":20,"color":"#ffffff"}],"title":"Intro","notes":"Say hello"},
                  {"background":{"type":"color","value":"#222222"},"elements":[]}]}
        """##
        let t = try JSONDecoder().decode(Template.self, from: Data(json.utf8))
        XCTAssertEqual(t.pageCount, 2)
        XCTAssertEqual(t.background, .color("#111111"), "the first page is the top level")
        XCTAssertEqual(t.elements.first?.text, "One")
        let design = t.instantiate()
        XCTAssertEqual(design.pages[0].title, "Intro")
        XCTAssertEqual(design.pages[0].notes, "Say hello")
        XCTAssertNil(design.pages[1].title)
        XCTAssertNil(design.pages[1].notes)
        XCTAssertEqual(t.instantiate(onlyPage: 1).pages.map(\.background), [.color("#222222")])

        let old = ##"{"id":"p","name":"Post","category":"Social","width":10,"height":10,"background":{"type":"color","value":"#ffffff"},"elements":[]}"##
        let single = try JSONDecoder().decode(Template.self, from: Data(old.utf8))
        XCTAssertEqual(single.pageCount, 1)
        XCTAssertNil(single.pages)
        let fitted = t.makePages(width: 200, height: 100)
        XCTAssertEqual(fitted.count, 2)
        XCTAssertEqual(fitted[0].elements.first?.w, 160, "fitted to the page")
    }

    // MARK: applying

    private func fitted(_ count: Int) -> [Page] {
        (0..<count).map { Page(background: .color("#00000\($0)"), elements: [Element.text("Slide \($0 + 1)")]) }
    }

    /// Nothing on any page — a background alone is nothing — and the set
    /// replaces it, every page, the master going with the old pages.
    func testAllPagesReplaceAnEmptyDesign() {
        var d = Design(title: "Blank", width: 1920, height: 1080)
        d.pages = [Page(background: .color("#ff0000")), Page()]
        d.masterPageId = d.pages[1].id
        XCTAssertTrue(DesignStore.isEmptyForTemplates(d))
        let applied = DesignStore.appliedTemplateSet(d, pages: fitted(3), at: 1)
        XCTAssertEqual(applied.design.pages.count, 3)
        XCTAssertEqual(applied.design.pages.map { $0.elements.first?.text }, ["Slide 1", "Slide 2", "Slide 3"])
        XCTAssertEqual(applied.first, 0)
        XCTAssertNil(applied.design.masterPageId)
    }

    /// Nothing on any page, but one is locked: it is kept, and the set
    /// follows the page open. The Android twin's UserTemplatesTest row.
    func testAllPagesFollowThePageOpenWhenAPageIsLocked() {
        var d = Design(title: "Blank", width: 1080, height: 1080)
        var locked = Page(background: .color("#ff0000"))
        locked.locked = true
        d.pages = [Page(), locked]
        XCTAssertFalse(DesignStore.isEmptyForTemplates(d))
        let applied = DesignStore.appliedTemplateSet(d, pages: fitted(3), at: 0)
        XCTAssertEqual(applied.design.pages.count, 5)
        XCTAssertEqual(applied.design.pages[0].id, d.pages[0].id)
        XCTAssertEqual(applied.design.pages[4], locked)
        XCTAssertEqual(applied.first, 1)
    }

    /// Anything on any page, and the set follows the page open, in order,
    /// at its size, everything there kept.
    func testAllPagesFollowThePageOpenOtherwise() {
        var d = Design(title: "Mine", width: 1920, height: 1080)
        var tall = Page(elements: [Element.text("Keep me")])
        tall.width = 1080
        tall.height = 1920
        d.pages = [Page(), tall, Page()]
        XCTAssertFalse(DesignStore.isEmptyForTemplates(d))
        let applied = DesignStore.appliedTemplateSet(d, pages: fitted(2), at: 1)
        XCTAssertEqual(applied.design.pages.count, 5)
        XCTAssertEqual(applied.first, 2)
        XCTAssertEqual(applied.design.pages[1].elements.first?.text, "Keep me")
        XCTAssertEqual(applied.design.pages[2].elements.first?.text, "Slide 1")
        XCTAssertEqual(applied.design.pages[3].elements.first?.text, "Slide 2")
        XCTAssertEqual(applied.design.pages[3].width, 1080, "at the page open's size")
        XCTAssertEqual(applied.design.pages[3].height, 1920)
        XCTAssertEqual(applied.design.pages[4].id, d.pages[2].id)
        XCTAssertEqual(DesignStore.appliedTemplateSet(d, pages: [], at: 1).design, d)
        XCTAssertEqual(DesignStore.appliedTemplateSet(d, pages: fitted(2), at: 9).design, d)
    }

    func testApplyingAllIsOneUndoStepOnTheFirstOfThem() {
        var d = Design(title: "Mine", width: 1920, height: 1080)
        d.pages = [Page(elements: [Element.text("Keep me")])]
        let store = DesignStore(design: d)
        let deck = ContentLibrary.templates.first { $0.pageCount > 1 && $0.width == 1920 }
        guard let deck else { return XCTFail("no deck") }
        store.applyTemplateSet(deck.makePages(width: store.pageWidth, height: store.pageHeight), name: deck.name)
        XCTAssertEqual(store.design.pages.count, 1 + deck.pageCount)
        XCTAssertEqual(store.pageIndex, 1)
        store.undo()
        XCTAssertEqual(store.design.pages.count, 1)
        XCTAssertEqual(store.design.pages[0].elements.first?.text, "Keep me")
    }

    // MARK: design types

    /// The types added this round, after the forty there were, each with
    /// at least one template of its own size.
    func testEveryNewTypeHasATemplate() throws {
        let added = ["card", "calendar-a4", "calendar-letter", "planner", "worksheet-a4", "worksheet-letter",
                     "book-cover", "album-cover", "label", "sticker", "bookmark", "ticket", "gift-certificate",
                     "letterhead-a4", "letterhead-letter", "newsletter", "magazine", "banner",
                     "facebook-event-cover", "instagram-ad", "twitch-banner", "etsy-banner", "mobile-video",
                     "logo-animated", "gmail-header", "snapchat-geofilter", "podcast-cover", "zoom-background",
                     "etsy-shop-icon"]
        // Before the Whiteboard type, which came later and is drawn on
        // rather than started from a template.
        XCTAssertEqual(Array(SizePreset.all.map(\.id).dropLast().suffix(added.count)), added)
        for id in added {
            let preset = try XCTUnwrap(SizePreset.byId(id), id)
            XCTAssertFalse(preset.keywords.isEmpty, id)
            XCTAssertGreaterThanOrEqual(ContentLibrary.sizedTemplates(for: preset).count, 1, "\(id) has no template")
        }
        let card = try XCTUnwrap(SizePreset.byId("card"))
        XCTAssertEqual(card.dimensions, "5 × 7 in")
        XCTAssertEqual(try XCTUnwrap(SizePreset.byId("banner")).dimensions, "72 × 36 in")
        XCTAssertEqual(try XCTUnwrap(SizePreset.byId("facebook-event-cover")).w, 1920)
        XCTAssertEqual(try XCTUnwrap(SizePreset.byId("facebook-event-cover")).h, 1005)
        XCTAssertEqual(try XCTUnwrap(SizePreset.byId("snapchat-geofilter")).h, 2340)
        // The shared sizes.json, as the Android twin's TemplateSetsTest has them.
        XCTAssertEqual(try XCTUnwrap(SizePreset.byId("gift-certificate")).dimensions, "8 × 3.5 in")
        XCTAssertEqual(try XCTUnwrap(SizePreset.byId("gmail-header")).w, 1000)
        XCTAssertEqual(try XCTUnwrap(SizePreset.byId("gmail-header")).h, 250)
    }

    /// Every type's pixels give back the size it is written in, and keep its
    /// shape: within half a pixel either way, in its own unit.
    func testThePresetsAspectRatiosRoundTrip() {
        for preset in SizePreset.all {
            let unit = preset.unit ?? "px"
            let dpi = preset.dpi ?? Units.screenDPI
            let halfPixel = Units.value(ofPixels: 0.5, unit: unit, dpi: dpi)
            XCTAssertEqual(Units.value(ofPixels: preset.w, unit: unit, dpi: dpi), preset.width,
                           accuracy: halfPixel + 1e-9, preset.id)
            XCTAssertEqual(Units.value(ofPixels: preset.h, unit: unit, dpi: dpi), preset.height,
                           accuracy: halfPixel + 1e-9, preset.id)
            let written = preset.width / preset.height
            let made = preset.w / preset.h
            XCTAssertEqual(made, written, accuracy: written / min(preset.w, preset.h), preset.id)
        }
    }
}
