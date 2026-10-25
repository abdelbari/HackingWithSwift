// The font combinations in Add ▸ Text, as the Android twin's TextCombosTest
// has them: textcombos.json the same bytes on both phones, every combination
// decoded with every element it lists in a category the chips list, the six
// pairings first, a search over names, tags and categories, Recently used,
// From your brand, and the same numbers as one goes on a page — 72% of its
// width, centred, a fresh group — then measured and selected in one step.

import XCTest
import CryptoKit
@testable import Canvia

@MainActor
final class TextCombosTests: XCTestCase {

    func testTheCombinationsAreTheSameBytesOnBothPhones() throws {
        // The Android twin's TextCombosTest checks the same digest of its copy.
        let url = try XCTUnwrap(Bundle.main.url(forResource: "textcombos", withExtension: "json"))
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "6c482c4dfe46c2df78f87d1280db2e8f2216281ab9fee5b011647f84777289a6")
    }

    /// The rows of the Android twin's TextCombosTest: every combination, and
    /// how many elements it draws.
    func testEveryCombinationDecodesAndDrawsEveryElementItLists() {
        let expected: [(String, Int)] = [
            ("editorial", 2), ("poster", 2), ("technical", 2), ("playful", 2), ("luxury", 2), ("minimal", 2), ("mega-sale", 4),
            ("wedding-invitation", 5), ("quote", 4), ("grand-opening", 4), ("happy-birthday", 3), ("webinar", 4),
            ("summer-vibes", 4), ("breaking-news", 5), ("coffee-house", 4), ("thank-you", 3), ("neon-night", 3),
            ("creative-workshop", 3), ("new-collection", 3), ("podcast-episode", 4), ("open-house", 4), ("train-harder", 3),
            ("black-friday", 4), ("recipe-card", 3), ("merry-christmas", 5), ("explore-iceland", 3), ("baby-shower", 6),
            ("dont-stop", 3), ("product-launch", 4), ("halloween-party", 3), ("big-announcement", 3), ("magazine-cover", 4),
            ("chapter-one", 4), ("tech-keynote", 3), ("photo-essay", 2), ("city-guide", 3), ("flash-sale", 3), ("half-price", 4),
            ("clearance", 4), ("buy-one-get-one", 3), ("cyber-monday", 4), ("summer-sale", 3), ("new-arrivals", 3),
            ("free-shipping", 3), ("limited-offer", 4), ("price-drop", 2), ("wise-words", 3), ("bold-quote", 3),
            ("testimonial", 3), ("handwritten-note", 2), ("book-quote", 3), ("daily-mantra", 2), ("fun-fact", 2),
            ("tweet-quote", 3), ("poem-line", 3), ("team-motto", 2), ("live-music", 3), ("save-our-seat", 4),
            ("farmers-market", 3), ("charity-run", 4), ("movie-night", 4), ("new-year-party", 3), ("we-said-yes", 3),
            ("wedding-menu", 3), ("reception", 3), ("mr-and-mrs", 2), ("bridal-shower", 3), ("anniversary", 3), ("rsvp-card", 3),
            ("save-the-date-script", 3), ("love-story", 2), ("ceremony-order", 3), ("new-post", 3), ("giveaway", 4),
            ("swipe-up", 3), ("good-morning", 3), ("milestone", 2), ("weekend-plans", 3), ("behind-the-scenes", 3),
            ("retro-diner", 3), ("arcade", 4), ("groovy", 2), ("vintage-label", 4), ("synthwave", 2), ("typewriter", 2),
            ("roller-disco", 3), ("old-cinema", 3), ("retro-surf", 3), ("pop-art", 2), ("record-store", 3), ("just-words", 2),
            ("thin-caps", 3), ("mono-label", 2), ("serif-whisper", 2), ("numbered", 3), ("left-aligned", 3), ("lowercase", 2),
            ("big-number", 2), ("one-line", 3), ("contact-card", 3), ("best-seller", 5), ("new-badge", 4), ("handmade", 5),
            ("organic", 4), ("percent-off", 4), ("award-winner", 5), ("vegan", 4), ("limited-edition", 5), ("free-gift", 4),
            ("local", 5), ("guarantee", 5), ("first-birthday", 3), ("back-to-school", 3), ("story-time", 3), ("its-a-boy", 3),
            ("its-a-girl", 3), ("play-date", 3), ("dino-party", 3), ("star-pupil", 3), ("summer-camp", 3),
            // Round 34: twelve more bent by a warp or a curve, then the Animated category.
            ("arched-title", 2), ("perspective-news", 2), ("bulge-sale", 2), ("curved-quote", 2),
            ("flag-festival", 2), ("curved-concert", 2), ("arched-names", 2), ("rise-follow", 2),
            ("perspective-retro", 2), ("squeeze-minimal", 2), ("curved-badge", 2), ("bouncy-arch", 2),
            ("typed-hello", 2), ("word-by-word", 2), ("letter-pop-party", 2), ("line-by-line", 1),
            ("ascending-title", 2), ("shift-in", 1), ("merge-logo", 2), ("block-reveal", 2), ("burst-boom", 1),
            ("bouncy-hello", 2), ("roll-credits", 2), ("skate-in", 2), ("spread-wide", 1), ("clarify-focus", 2),
            ("tumble-fun", 2), ("signature-write", 2), ("neon-flicker", 2), ("glitch-title", 2), ("echo-drop", 2),
            ("neon-breathe", 1), ("curved-hello", 2), ("arch-rise", 2), ("flag-wave", 2), ("bulge-pop", 2),
            ("countdown", 2), ("breaking-wipe", 2), ("sale-ends", 2), ("swipe-up-bounce", 2),
            ("coming-soon-typed", 2), ("thank-you-written", 1), ("new-drop", 2), ("live-now", 2),
            ("drifting-dream", 2), ("big-reveal", 2), ("quote-reveal", 2), ("new-year-burst", 2),
        ]
        XCTAssertEqual(TextCombos.all.map(\.id), expected.map(\.0))
        XCTAssertEqual(TextCombos.all.map(\.elements.count), expected.map(\.1))
        let fonts = Set(FontLibrary.all.map(\.id)).union(FontLibrary.aliases.keys)
        for combo in TextCombos.all {
            let drawn = TextCombos.elements(combo, scale: 1)
            XCTAssertEqual(drawn.count, combo.elements.count, combo.id)
            // Text, shapes and rules only, each with a box, every text with
            // words in a font the library has.
            XCTAssertTrue(drawn.allSatisfy { [ElementType.text, .shape, .line].contains($0.type) && $0.w > 0 && $0.h > 0 }, combo.id)
            for el in drawn where el.type == .text {
                XCTAssertFalse((el.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty, combo.id)
                XCTAssertTrue(fonts.contains(el.fontFamily ?? ""), "\(combo.id) \(el.fontFamily ?? "")")
            }
            // Within its box.
            XCTAssertTrue(drawn.allSatisfy {
                $0.x >= 0 && $0.x + $0.w <= combo.w + 1e-9 && $0.y >= 0 && $0.y + $0.h <= combo.h + 1e-9
            }, combo.id)
            XCTAssertFalse(combo.name.isEmpty, combo.id)
            XCTAssertFalse(combo.tags.isEmpty, combo.id)
            // In a category the chips list.
            XCTAssertTrue(TextCombos.categories.contains(combo.category ?? ""), combo.id)
        }
        // About a hundred and seventy: twelve or more in each category,
        // thirty-six of them Animated.
        XCTAssertEqual(TextCombos.all.count, 168)
        XCTAssertEqual(TextCombos.categories.map { TextCombos.search("", in: $0).count },
                       [14, 13, 13, 14, 13, 13, 13, 13, 13, 13, 36])
        XCTAssertEqual(Set(TextCombos.all.map(\.id)).count, TextCombos.all.count)
    }

    func testTheSixPairingsComeFirstAsTheyWere() {
        XCTAssertEqual(Array(TextCombos.all.prefix(6)).map(\.name), ContentLibrary.pairings.map(\.name))
        for (combo, pairing) in zip(TextCombos.all, ContentLibrary.pairings) {
            let drawn = TextCombos.elements(combo, scale: 1)
            XCTAssertEqual(drawn.count, 2, combo.id)
            guard drawn.count == 2 else { continue }
            for (el, spec) in [(drawn[0], pairing.heading), (drawn[1], pairing.body)] {
                XCTAssertEqual(el.text, spec.text)
                XCTAssertEqual(el.fontFamily, spec.fontFamily)
                XCTAssertEqual(el.fontWeight, spec.fontWeight)
                XCTAssertEqual(el.fontSize, spec.fontSize)
                XCTAssertEqual(el.letterSpacing, spec.letterSpacing ?? 0)
            }
            // The body 14 under the heading.
            XCTAssertEqual(drawn[1].y, drawn[0].y + drawn[0].h + 14, accuracy: 1e-9)
        }
    }

    func testTheCombinationsUseWhatADesignCanHold() {
        let drawn = TextCombos.all.flatMap { TextCombos.elements($0, scale: 1) }
        let texts = drawn.filter { $0.type == .text }
        XCTAssertTrue(texts.contains { ($0.effect?.type ?? "none") != "none" })
        XCTAssertTrue(texts.contains { ($0.curve ?? 0) != 0 })
        XCTAssertTrue(texts.contains { $0.uppercase == true })
        XCTAssertTrue(texts.contains { !$0.liveSpans.isEmpty })
        XCTAssertTrue(texts.contains { $0.textFill?.kind == "gradient" && $0.textFill?.stops?.count == 2 })
        XCTAssertTrue(texts.contains { ($0.letterSpacing ?? 0) > 0 })
        XCTAssertTrue(texts.contains { $0.italic == true })
        XCTAssertTrue(drawn.contains { $0.type == .line })
        // This phone's shape ids, each one the library has.
        let shapes = drawn.filter { $0.type == .shape }
        XCTAssertEqual(Set(shapes.compactMap(\.shapeId)), ["rect", "circle", "heart", "star-4"])
        XCTAssertTrue(shapes.allSatisfy { ContentLibrary.shapeMap[$0.shapeId ?? ""] != nil })
        // Weights from Light to Black among them.
        XCTAssertEqual(Set(texts.compactMap(\.fontWeight)).sorted(), [300, 400, 500, 600, 700, 800, 900])
        // Words given their own colour where the file says.
        let sale = TextCombos.elements(TextCombos.combo("mega-sale")!, scale: 1)[0]
        XCTAssertEqual(sale.liveSpans, [TextSpan(start: 5, end: 9, color: "#111827")])
        XCTAssertEqual(sale.effect?.type, "lift")
        let coffee = TextCombos.elements(TextCombos.combo("coffee-house")!, scale: 1)[0]
        XCTAssertEqual(coffee.curve, 60)
    }

    /// The rows of the Android twin's TextCombosTest.
    func testASearchFindsNamesTagsAndCategoriesCaseAndAccentsAside() {
        XCTAssertEqual(TextCombos.search("Café").map(\.id), ["coffee-house"])
        XCTAssertEqual(TextCombos.search(" celebration ").map(\.id),
                       ["happy-birthday", "baby-shower", "new-year-party", "anniversary", "new-year-burst"])
        XCTAssertEqual(TextCombos.search("eleg").map(\.id),
                       ["luxury", "wedding-invitation", "save-the-date-script", "serif-whisper", "arched-names"])
        XCTAssertEqual(TextCombos.search("real estate").map(\.id), ["open-house"])
        // A category's name finds all of it, and a tag outside it too.
        XCTAssertEqual(TextCombos.search("SALE").map(\.id), [
            "mega-sale", "black-friday", "flash-sale", "half-price", "clearance", "buy-one-get-one", "cyber-monday",
            "summer-sale", "new-arrivals", "free-shipping", "limited-offer", "price-drop", "percent-off", "bulge-sale",
            "bulge-pop", "sale-ends",
        ])
        XCTAssertEqual(TextCombos.search("sale", in: "Badge").map(\.id), ["percent-off"])
        XCTAssertEqual(TextCombos.search("love", in: "Wedding").map(\.id),
                       ["wedding-invitation", "we-said-yes", "mr-and-mrs", "anniversary", "save-the-date-script", "love-story",
                        "arched-names"])
        XCTAssertEqual(TextCombos.search("").map(\.id), TextCombos.all.map(\.id))
        XCTAssertEqual(TextCombos.search("zzz").map(\.id), [])
        XCTAssertEqual(TextCombos.noneFound(" zzz "), "No font combinations match \u{201C}zzz\u{201D}.")
    }

    func testRecentlyUsedKeepsTheLastEightNewestFirstEachOnce() {
        var recent: [String] = []
        let eight = TextCombos.all.dropFirst(10).prefix(8).map(\.id)
        for id in ["quote", "poster", "quote"] + eight { recent = TextCombos.recent(recent, adding: id) }
        XCTAssertEqual(recent, Array(eight.reversed()))
        XCTAssertEqual(TextCombos.recent(["quote", "poster"], adding: "poster"), ["poster", "quote"])
        // Ids no longer in the file are passed over.
        XCTAssertEqual(TextCombos.named(["gone", "quote"]).map(\.id), ["quote"])
        // Kept per phone, one in the brand's faces by its own id.
        if let defaults = UserDefaults(suiteName: "combos-\(UUID().uuidString)") {
            RecentCombos.record("brand:quote", defaults: defaults)
            RecentCombos.record("poster", defaults: defaults)
            XCTAssertEqual(RecentCombos.all(defaults), ["poster", "quote"])
        }
    }

    /// Shared rows: a combination in the brand's faces by size rank.
    func testFromYourBrandSetsEachTextInTheKitsFaceForItsSize() throws {
        let sale = try XCTUnwrap(TextCombos.combo("mega-sale"))
        // Sizes 150, 44 and 26: title (else heading), subheading, body.
        var kit = BrandFonts()
        kit.title = BrandFont(family: "anton", weight: 400)
        kit.subheading = BrandFont(family: "lora", weight: 600)
        kit.body = BrandFont(family: "roboto", weight: 300)
        let branded = try XCTUnwrap(TextCombos.branded(sale, fonts: kit))
        XCTAssertEqual(branded.id, "brand:mega-sale")
        let texts = TextCombos.elements(branded, scale: 1).filter { $0.type == .text }
        XCTAssertEqual(texts.map(\.fontFamily), ["anton", "lora", "roboto"])
        XCTAssertEqual(texts.map(\.fontWeight), [400, 600, 300])
        XCTAssertEqual(texts.map(\.fontSize), [150, 44, 26])
        // The shapes as they were.
        XCTAssertEqual(branded.elements[1], sale.elements[1])
        // A heading alone sets the biggest and the next; the body falls back
        // on it.
        var heading = BrandFonts()
        heading.heading = BrandFont(family: "bebas-neue", weight: 400)
        let headed = try XCTUnwrap(TextCombos.branded(sale, fonts: heading))
        XCTAssertEqual(TextCombos.elements(headed, scale: 1).filter { $0.type == .text }.map(\.fontFamily),
                       ["bebas-neue", "bebas-neue", "bebas-neue"])
        // Only a body: the biggest falls back on it too.
        var body = BrandFonts()
        body.body = BrandFont(family: "karla", weight: 500)
        let bodied = try XCTUnwrap(TextCombos.branded(try XCTUnwrap(TextCombos.combo("editorial")), fonts: body))
        XCTAssertEqual(TextCombos.elements(bodied, scale: 1).map(\.fontFamily), ["karla", "karla"])
        // No title, heading or body face: no row.
        var quote = BrandFonts()
        quote.quote = BrandFont(family: "lora")
        XCTAssertNil(TextCombos.branded(sale, fonts: quote))
        XCTAssertNil(TextCombos.branded(sale, fonts: BrandFonts()))
    }

    private func assertRect(_ el: Element, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(el.x, x, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(el.y, y, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(el.w, w, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(el.h, h, accuracy: 1e-6, file: file, line: line)
    }

    /// The rows of the Android twin's TextCombosTest: 72% of the page wide,
    /// centred both ways, nothing rounded.
    func testACombinationGoesOnScaledToThePageAndCentredAsOneNewGroup() {
        let editorial = TextCombos.placed(TextCombos.combo("editorial")!, pageWidth: 1080, pageHeight: 1080)
        assertRect(editorial[0], 151.2, 460.7446153846154, 777.6, 109.66153846153846)
        assertRect(editorial[1], 151.2, 584.363076923077, 777.6, 34.89230769230769)
        XCTAssertEqual(editorial[0].fontSize ?? 0, 87.72923076923077, accuracy: 1e-6)
        XCTAssertEqual(editorial[0].letterSpacing ?? 0, -0.9969230769230769, accuracy: 1e-6)

        let sale = TextCombos.placed(TextCombos.combo("mega-sale")!, pageWidth: 1080, pageHeight: 1080)
        assertRect(sale[0], 151.2, 404.352, 777.6, 129.6)
        assertRect(sale[1], 280.8, 554.688, 518.4, 72.576)
        XCTAssertEqual(sale[1].radius ?? 0, 36.288, accuracy: 1e-6)
        assertRect(sale[2], 280.8, 568.08, 518.4, 45.792)
        XCTAssertEqual(sale[2].fontSize ?? 0, 38.016, accuracy: 1e-6)
        XCTAssertEqual(sale[2].letterSpacing ?? 0, 2.592, accuracy: 1e-6)
        assertRect(sale[3], 151.2, 648.0, 777.6, 27.648)

        // A wide page: still 72% of its width.
        let wedding = TextCombos.placed(TextCombos.combo("wedding-invitation")!, pageWidth: 1920, pageHeight: 1080)
        assertRect(wedding[0], 268.8, 281.2018604651163, 1382.4, 54.65302325581395)
        XCTAssertEqual(wedding[0].letterSpacing ?? 0, 19.289302325581396, accuracy: 1e-6)
        assertRect(wedding[2], 799.2558139534884, 615.5497674418605, 321.48837209302326, 12.85953488372093)
        XCTAssertEqual(wedding[2].thickness ?? 0, 3.2148837209302323, accuracy: 1e-6)
        assertRect(wedding[4], 268.8, 747.36, 1382.4, 51.43813953488372)

        // A tall one.
        let neon = TextCombos.placed(TextCombos.combo("neon-night")!, pageWidth: 1080, pageHeight: 1920)
        assertRect(neon[0], 151.2, 797.246511627907, 777.6, 325.50697674418603)
        assertRect(neon[1], 187.3674418604651, 869.5813953488373, 705.2651162790697, 119.35255813953489)
        XCTAssertEqual(neon[1].fontSize ?? 0, 99.46046511627907, accuracy: 1e-6)

        // One group, fresh ids every time it goes on.
        for placed in [editorial, sale, wedding, neon] {
            XCTAssertEqual(Set(placed.map(\.group)).count, 1)
            XCTAssertNotNil(placed[0].group)
            XCTAssertEqual(Set(placed.map(\.id)).count, placed.count)
        }
        let again = TextCombos.placed(TextCombos.combo("mega-sale")!, pageWidth: 1080, pageHeight: 1080)
        XCTAssertTrue(Set(again.map(\.id)).isDisjoint(with: sale.map(\.id)))
        XCTAssertNotEqual(again[0].group, sale[0].group)
    }

    func testACombinationWithoutWhatItNeedsIsPassedOver() {
        func combos(_ json: String) -> [TextCombos.Combo] {
            TextCombos.combos(from: Data(json.utf8))
        }
        let element = #"{"type":"text","text":"Hi","w":100,"h":40}"#
        XCTAssertEqual(combos(#"[{"id":"a","name":"A","w":100,"elements":[\#(element)]}]"#).first?.h, 40)
        XCTAssertEqual(combos(#"[{"name":"A","w":100,"elements":[\#(element)]}]"#).count, 0)
        XCTAssertEqual(combos(#"[{"id":"a","name":"A","w":"100","elements":[\#(element)]}]"#).count, 0)
        XCTAssertEqual(combos(#"[{"id":"a","name":"A","w":100}]"#).count, 0)
        // One passed over leaves the rest.
        XCTAssertEqual(combos(#"[{"id":"a","w":100,"elements":[\#(element)]},{"id":"b","name":"B","w":100,"elements":[\#(element)]}]"#).map(\.id), ["b"])
    }

    // MARK: on the page

    private func store(width: Double, height: Double) -> DesignStore {
        DesignStore(design: Design(title: "combos", width: width, height: height))
    }

    func testATapPutsItOnThePageMeasuredGroupedAndSelectedAsOneStep() {
        let s = store(width: 1080, height: 1080)
        let combo = TextCombos.combo("mega-sale")!
        let placed = TextCombos.placed(combo, pageWidth: 1080, pageHeight: 1080)
        s.addTextCombo(combo)
        let made = s.page.elements
        XCTAssertEqual(made.count, 4)
        XCTAssertEqual(Set(made.compactMap(\.group)).count, 1)
        XCTAssertEqual(s.selection, Set(made.map(\.id)))
        for (el, at) in zip(made, placed) {
            XCTAssertEqual(el.type, at.type)
            // Each text from its top, at the height its words take.
            XCTAssertEqual(el.x, at.x, accuracy: 1e-9)
            XCTAssertEqual(el.y, at.y, accuracy: 1e-9)
            XCTAssertEqual(el.w, at.w, accuracy: 1e-9)
            if el.type == .text {
                XCTAssertEqual(el.h, FontLibrary.layoutHeight(for: el), accuracy: 1e-9)
            } else {
                XCTAssertEqual(el.h, at.h, accuracy: 1e-9)
            }
        }
        s.undo()
        XCTAssertTrue(s.page.elements.isEmpty)
        XCTAssertFalse(s.canUndo, "one step")
    }

    func testAPageOfItsOwnSizeTakesItAtItsOwnWidth() {
        var design = Design(title: "combos", width: 1080, height: 1080)
        design.pages[0].width = 1920
        let s = DesignStore(design: design)
        s.addTextCombo(TextCombos.combo("editorial")!)
        let heading = s.page.elements[0]
        XCTAssertEqual(heading.x, 268.8, accuracy: 1e-6)
        XCTAssertEqual(heading.w, 1382.4, accuracy: 1e-6)
    }
}

extension TextCombosTests {

    /// Every animation in the file is one ElementAnimation knows — an
    /// entrance one of its kinds, an exit one of its exits or a unit kind,
    /// played backwards — and each combination of the Animated category
    /// moves — and only those in it, so the tiles that play are that
    /// category's.
    func testTheAnimatedCombinationsMoveByKindsTheAppKnows() {
        let known = Set(ElementAnimation.kinds)
        let exits = Set(ElementAnimation.exitKinds).union(ElementAnimation.unitKinds)
        for combo in TextCombos.all {
            for el in combo.elements {
                if let enter = el.animation { XCTAssertTrue(known.contains(enter.kind), "\(combo.id) \(enter.kind)") }
                if let exit = el.exitAnimation { XCTAssertTrue(exits.contains(exit.kind), "\(combo.id) exit \(exit.kind)") }
                for anim in [el.animation, el.exitAnimation].compactMap({ $0 }) {
                    XCTAssertTrue(anim.by == nil || ElementAnimation.unitChoices.contains(anim.by ?? ""), combo.id)
                }
            }
            XCTAssertEqual(TextCombos.isAnimated(combo), combo.category == TextCombos.animatedCategory, combo.id)
        }
        XCTAssertEqual(TextCombos.categories.last, "Animated")
        // Among them typewriter, letter pop and line rise, exits, and the
        // neon, glitch and echo effects, curves and warps.
        let animated = TextCombos.search("", in: TextCombos.animatedCategory).flatMap(\.elements)
        let kinds = Set(animated.compactMap { $0.animation?.kind })
        XCTAssertTrue(kinds.isSuperset(of: ["typewriter", "words", "letterPop", "lineRise", "fade"]))
        XCTAssertTrue(animated.contains { $0.exitAnimation != nil })
        let effects = Set(animated.compactMap { $0.effect?.type })
        XCTAssertTrue(effects.isSuperset(of: ["neon", "glitch", "echo"]))
        XCTAssertTrue(animated.contains { ($0.curve ?? 0) != 0 })
        XCTAssertTrue(animated.contains { $0.warp != nil })
        // Twelve more in the other categories, after the hundred and
        // twenty: eight bent by a warp, four by a curve.
        let others = TextCombos.all.dropFirst(120).filter { $0.category != TextCombos.animatedCategory }
        XCTAssertEqual(others.count, 12)
        XCTAssertEqual(others.filter { $0.elements.contains { $0.warp != nil } }.count, 8)
        XCTAssertEqual(others.filter { $0.elements.contains { ($0.curve ?? 0) != 0 } }.count, 4)
    }

    /// A tile's loop, the Android twin's rows of playLength: the latest
    /// entrance's end (a loop kind one loopPeriod), a second to read, then
    /// the longest exit — and the animation goes on the page with it.
    func testATilesLoopAndTheAnimationGoOnThePage() throws {
        let typed = try XCTUnwrap(TextCombos.combo("typed-hello"))
        XCTAssertEqual(TextCombos.loopHold(typed), 1.6 + 0.6 + 1.0, accuracy: 1e-9)
        XCTAssertEqual(TextCombos.loopHold(try XCTUnwrap(TextCombos.combo("countdown"))), 1.5 + 0.5 + 1.0 + 0.5,
                       accuracy: 1e-9)
        XCTAssertEqual(TextCombos.loopHold(try XCTUnwrap(TextCombos.combo("live-now"))),
                       ElementAnimation.loopPeriod + 1.0, accuracy: 1e-9)
        let placed = TextCombos.placed(typed, pageWidth: 1080, pageHeight: 1080)
        XCTAssertEqual(placed[0].animation?.kind, "typewriter")
        XCTAssertEqual(placed[0].animation?.by, "letter")
        XCTAssertEqual(placed[1].animation?.delay, 1.6)
    }
}
