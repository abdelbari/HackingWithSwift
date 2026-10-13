// Your own templates: saved with every page and fresh ids, listed in
// usertemplates.json, renamed, updated and deleted; a new design made from
// a fresh copy; several pages applied in the editor as one step; and a
// built-in template of several pages instantiated whole.

import XCTest
@testable import Canvia

final class UserTemplatesTests: XCTestCase {

    /// Three pages, a master, a group, and a story-sized third page.
    private func deck() -> Design {
        var d = Design(title: "Pitch", width: 1080, height: 1080)
        var a = Element.text("Hello", fontSize: 96, w: 800)
        a.group = "grp_1"
        var b = Element.shape("rect", w: 200, h: 200)
        b.group = "grp_1"
        b.x = 100; b.y = 100
        var story = Page(background: .color("#000000"), elements: [Element.text("Tall", fontSize: 48)])
        story.width = 1080
        story.height = 1920
        d.pages = [Page(elements: [a, b]), Page(background: .color("#ffeedd")), story]
        d.masterPageId = d.pages[1].id
        d.folder = "Work"
        return d
    }

    private func ids(_ d: Design) -> Set<String> {
        var out: Set<String> = [d.id]
        for page in d.pages {
            out.insert(page.id)
            for el in page.elements { out.insert(el.id) }
        }
        return out
    }

    func testATemplateKeepsEveryPageUnderFreshIds() {
        let source = deck()
        let now = Date(timeIntervalSince1970: 1_727_000_000)
        let t = UserTemplates.templateDesign(source, id: "tpl_1", name: "Pitch deck", now: now)
        XCTAssertEqual(t.id, "tpl_1")
        XCTAssertEqual(t.title, "Pitch deck")
        XCTAssertFalse(t.titleAuto)
        XCTAssertNil(t.folder)
        XCTAssertEqual(t.updatedAt, 1_727_000_000_000)
        // Whole milliseconds, however finely the clock reads.
        let fine = UserTemplates.templateDesign(source, id: "tpl_2", name: "Fine",
                                                now: Date(timeIntervalSince1970: 1_727_000_000.1236))
        XCTAssertEqual(fine.updatedAt, 1_727_000_000_124)
        XCTAssertEqual(fine.createdAt, fine.updatedAt)
        XCTAssertEqual(t.pages.count, 3)
        XCTAssertTrue(ids(t).isDisjoint(with: ids(source)), "no id shared with the design")
        XCTAssertEqual(t.masterPageId, t.pages[1].id, "the master follows its page")
        let groups = Set(t.pages[0].elements.compactMap(\.group))
        XCTAssertEqual(groups.count, 1)
        XCTAssertNotEqual(groups.first, "grp_1")
        XCTAssertEqual(t.pages[2].height, 1920)

        let entry = UserTemplates.entry(for: t, category: "Decks")
        XCTAssertEqual(entry, UserTemplate(id: "tpl_1", name: "Pitch deck", category: "Decks", width: 1080,
                                           height: 1080, pageCount: 3, updatedAt: 1_727_000_000_000))
        XCTAssertEqual(entry.caption, "Decks · 1080 × 1080 · 3 pages")

        // A new design from it: every id fresh again.
        let made = UserTemplates.newDesign(from: t, now: now)
        XCTAssertTrue(ids(made).isDisjoint(with: ids(t)))
        XCTAssertEqual(made.title, "Pitch deck")
        XCTAssertEqual(made.pages.count, 3)
        XCTAssertEqual(made.masterPageId, made.pages[1].id)
    }

    func testTheNameAndCategoryTypedFallBack() {
        let d = deck()
        XCTAssertEqual(UserTemplates.name("  ", design: d), "Pitch")
        XCTAssertEqual(UserTemplates.name(" Launch ", design: d), "Launch")
        XCTAssertEqual(UserTemplates.category(""), "Personal", "as the Android twin files it")
        XCTAssertEqual(UserTemplates.category(" Decks "), "Decks")
    }

    /// The index as both phones write it, and read leniently.
    func testTheIndexReadsAsTheAndroidTwinWritesIt() throws {
        let json = #"[{"category":"Decks","height":1080,"id":"tpl_a","name":"Pitch","pageCount":3,"updatedAt":1727000000000,"width":1920},{"name":"No id"},{"id":"tpl_b","extra":true},7]"#
        let entries = UserTemplates.read(Data(json.utf8))
        XCTAssertEqual(entries.map(\.id), ["tpl_a", "tpl_b"])
        XCTAssertEqual(entries[0], UserTemplate(id: "tpl_a", name: "Pitch", category: "Decks", width: 1920,
                                                height: 1080, pageCount: 3, updatedAt: 1_727_000_000_000))
        XCTAssertEqual(entries[1].category, "Personal")
        XCTAssertEqual(entries[1].pageCount, 1)
        // A fraction of a millisecond, as an earlier build wrote it, reads;
        // the Android twin rounds it to 1727000000001.
        let fraction = #"[{"category":"Decks","height":1080,"id":"tpl_a","name":"Pitch","pageCount":3,"updatedAt":1727000000000.5,"width":1920}]"#
        XCTAssertEqual(UserTemplates.read(Data(fraction.utf8)).first?.updatedAt.rounded(), 1_727_000_000_001)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode([entries[0]]), as: UTF8.self),
                       #"[{"category":"Decks","height":1080,"id":"tpl_a","name":"Pitch","pageCount":3,"updatedAt":1727000000000,"width":1920}]"#)
    }

    func testSavedRenamedUpdatedAndDeleted() throws {
        let source = deck()
        let saved = try XCTUnwrap(UserTemplates.save(source, name: "Pitch deck", category: "Decks"))
        defer { UserTemplates.delete(saved.id) }
        XCTAssertEqual(UserTemplates.all().first?.id, saved.id, "newest first")
        XCTAssertEqual(UserTemplates.load(id: saved.id)?.pages.count, 3)
        XCTAssertTrue(UserTemplates.designs().contains { $0.id == saved.id }, "kept by the launch sweep")

        UserTemplates.rename(saved.id, to: "  ")
        XCTAssertEqual(UserTemplates.all().first { $0.id == saved.id }?.name, "Pitch deck", "an empty name changes nothing")
        UserTemplates.rename(saved.id, to: "Launch", now: Date(timeIntervalSince1970: 1_800_000_000.0004))
        XCTAssertEqual(UserTemplates.all().first { $0.id == saved.id }?.name, "Launch")
        XCTAssertEqual(UserTemplates.load(id: saved.id)?.title, "Launch")
        // Changed then, in whole milliseconds, in the list and the design
        // alike, so a backup carries the rename as the newer template.
        XCTAssertEqual(UserTemplates.all().first { $0.id == saved.id }?.updatedAt, 1_800_000_000_000)
        XCTAssertEqual(UserTemplates.load(id: saved.id)?.updatedAt, 1_800_000_000_000)

        var shorter = source
        shorter.pages.removeLast()
        let updated = try XCTUnwrap(UserTemplates.update(saved.id, from: shorter))
        XCTAssertEqual(updated.pageCount, 2)
        XCTAssertEqual(updated.name, "Launch", "the name and category stay")
        XCTAssertEqual(updated.category, "Decks")
        XCTAssertEqual(UserTemplates.load(id: saved.id)?.pages.count, 2)

        UserTemplates.delete(saved.id)
        XCTAssertFalse(UserTemplates.all().contains { $0.id == saved.id })
        XCTAssertNil(UserTemplates.load(id: saved.id))
        XCTAssertNil(UserTemplates.update(saved.id, from: source))
    }

    func testFilteredBySizeAndByWords() {
        let a = UserTemplate(id: "a", name: "Pitch", category: "Decks", width: 1920, height: 1080, pageCount: 3, updatedAt: 1)
        let b = UserTemplate(id: "b", name: "Sale", category: "Posts", width: 1080, height: 1080, pageCount: 1, updatedAt: 2)
        XCTAssertEqual(UserTemplates.sized([a, b], width: 1080, height: 1080).map(\.id), ["b"])
        XCTAssertEqual(UserTemplates.matching([a, b], query: "deck").map(\.id), ["a"])
        XCTAssertEqual(UserTemplates.matching([a, b], query: " sale ").map(\.id), ["b"])
        XCTAssertEqual(UserTemplates.matching([a, b], query: "").map(\.id), ["a", "b"])
    }

    // MARK: applying in the editor

    func testEveryPageLandsFittedToThePageOnScreen() {
        let template = deck()
        let pages = UserTemplates.pages(of: template, width: 540, height: 540)
        XCTAssertEqual(pages.count, 3)
        XCTAssertTrue(Set(pages.map(\.id)).isDisjoint(with: Set(template.pages.map(\.id))))
        XCTAssertEqual(pages[0].elements[1].w, 100, "halved to fit")
        XCTAssertNil(pages[2].height, "at the size of the page it lands on")
        XCTAssertEqual(pages[2].elements[0].fontSize, 48 * 540 / 1920, "a tall page fitted by its height")
    }

    /// The row the Android twin's "a template of your own is fitted as a
    /// built-in one is" checks: a stroke keeps its width, the rounding
    /// scales with the box.
    func testATemplateOfYourOwnIsFittedAsABuiltInOneIs() {
        var card = Element.shape("rect", w: 400, h: 200)
        card.strokeWidth = 10
        card.radius = 24
        var d = Design(title: "Card", width: 1080, height: 1080)
        d.pages = [Page(elements: [card])]
        let fitted = UserTemplates.pages(of: d, width: 540, height: 540)[0].elements[0]
        XCTAssertEqual(fitted.w, 200, accuracy: 0.001)
        XCTAssertEqual(fitted.strokeWidth, 10)
        XCTAssertEqual(fitted.radius ?? 0, 12, accuracy: 0.001)
    }

    /// The rows the Android twin's "a template back from a backup takes its
    /// listed name and time" checks: renamed in the list, it comes back
    /// under that name, at the later time; unlisted, as it was, in Personal.
    func testATemplateBackFromABackupTakesItsListedNameAndTime() {
        var d = Design(title: "Sale", width: 1080, height: 1080)
        d.id = "tpl_a"
        d.updatedAt = 1000
        let listed = UserTemplate(id: "tpl_a", name: "Spring sale", category: "Events", width: 1080,
                                  height: 1080, pageCount: 1, updatedAt: 2000)
        let back = UserTemplates.restored(d, listed: listed)
        XCTAssertEqual(back.design.title, "Spring sale")
        XCTAssertEqual(back.design.updatedAt, 2000)
        XCTAssertEqual(UserTemplates.entry(for: back.design, category: back.category), listed)
        let alone = UserTemplates.restored(d, listed: nil)
        XCTAssertEqual(alone.design.title, "Sale")
        XCTAssertEqual(alone.design.updatedAt, 1000)
        XCTAssertEqual(alone.category, "Personal")
        var newer = d
        newer.updatedAt = 3000
        XCTAssertEqual(UserTemplates.restored(newer, listed: listed).design.updatedAt, 3000)
    }

    /// The row the Android twin's "a template keeps its arrows joined and
    /// its groups apart" checks: laid on, a template is copied as any copy
    /// is — its arrow follows the copies of its boxes, and its group is a
    /// new one each time.
    func testATemplateKeepsItsArrowsJoinedAndItsGroupsApart() {
        var box = Element.shape("rect")
        box.id = "box"
        box.group = "g1"
        var other = Element.shape("oval")
        other.id = "other"
        other.group = "g1"
        var arrow = Element.shape("rect")
        arrow.id = "arrow"
        arrow.connectFrom = "box"
        arrow.connectTo = "other"
        var d = Design(title: "Joined", width: 1080, height: 1080)
        d.pages = [Page(elements: [box, other, arrow])]
        let first = UserTemplates.pages(of: d, width: 540, height: 540)[0].elements
        let second = UserTemplates.pages(of: d, width: 540, height: 540)[0].elements
        XCTAssertEqual(first[2].connectFrom, first[0].id)
        XCTAssertEqual(first[2].connectTo, first[1].id)
        XCTAssertEqual(first[0].group, first[1].group)
        XCTAssertNotEqual(first[0].group, "g1")
        XCTAssertNotEqual(first[0].group, second[0].group)
        let made = UserTemplates.newDesign(from: d).pages[0].elements
        XCTAssertEqual(made[2].connectFrom, made[0].id)
        XCTAssertNotEqual(made[0].group, "g1")
    }

    func testApplyingSeveralPagesReplacesThisOneAndAddsTheRestAfterIt() {
        var d = Design(title: "Mine", width: 1080, height: 1080)
        var tall = Page(background: .color("#111111"), elements: [Element.text("Mine")])
        tall.width = 1080
        tall.height = 1920
        d.pages = [Page(), tall, Page()]
        let incoming = [Page(background: .color("#aa0000"), elements: [Element.text("One")]),
                        Page(background: .color("#00aa00")),
                        Page(background: .color("#0000aa"))]
        let out = DesignStore.appliedTemplate(d, pages: incoming, at: 1)
        XCTAssertEqual(out.pages.count, 5)
        XCTAssertEqual(out.pages[1].id, tall.id, "the page stays itself")
        XCTAssertEqual(out.pages[1].background, .color("#aa0000"))
        XCTAssertEqual(out.pages[1].elements.map(\.text), ["One"])
        XCTAssertEqual(out.pages[1].height, 1920)
        XCTAssertEqual(out.pages[2].background, .color("#00aa00"))
        XCTAssertEqual(out.pages[2].height, 1920, "added at the size of the page applied to")
        XCTAssertEqual(out.pages[3].background, .color("#0000aa"))
        XCTAssertEqual(out.pages[4].id, d.pages[2].id)

        // One page: this page only.
        let one = DesignStore.appliedTemplate(d, pages: [incoming[2]], at: 0)
        XCTAssertEqual(one.pages.count, 3)
        XCTAssertEqual(one.pages[0].background, .color("#0000aa"))
        XCTAssertEqual(DesignStore.appliedTemplate(d, pages: [], at: 0), d)
        XCTAssertEqual(DesignStore.appliedTemplate(d, pages: incoming, at: 9), d)
    }

    func testApplyingIsOneUndoStep() {
        var d = Design(title: "Mine", width: 1080, height: 1080)
        d.pages = [Page(elements: [Element.text("Keep me")])]
        let store = DesignStore(design: d)
        let pages = UserTemplates.pages(of: deck(), width: 1080, height: 1080)
        store.applyTemplatePages(pages, name: "Pitch")
        XCTAssertEqual(store.design.pages.count, 3)
        store.undo()
        XCTAssertEqual(store.design.pages.count, 1)
        XCTAssertEqual(store.design.pages[0].elements.first?.text, "Keep me")
    }

    // MARK: built-in templates of several pages

    func testABuiltInTemplateWithPagesInstantiatesEveryPage() {
        let first = TemplatePage(background: .color("#ffffff"), elements: [Element.text("Cover", fontSize: 80, w: 600)])
        let second = TemplatePage(background: .color("#000000"), elements: [Element.text("Inside", fontSize: 40, w: 600)])
        var t = Template(id: "t", name: "Deck", category: "Decks", width: 1080, height: 1080,
                         background: first.background, elements: first.elements)
        XCTAssertEqual(t.pageCount, 1, "no pages: the one page it describes")
        XCTAssertEqual(t.instantiate().pages.count, 1)
        t.pages = [first, second]
        XCTAssertEqual(t.pageCount, 2)
        let design = t.instantiate()
        XCTAssertEqual(design.pages.count, 2)
        XCTAssertEqual(design.pages[1].background, .color("#000000"))
        XCTAssertEqual(design.pages[1].elements.first?.text, "Inside")
        XCTAssertNotEqual(design.pages[0].elements.first?.id, first.elements[0].id, "fresh ids")
        let fitted = t.makePage(at: 1, width: 540, height: 540)
        XCTAssertEqual(fitted.background, .color("#000000"))
        XCTAssertEqual(fitted.elements.first?.w, 300)
        XCTAssertEqual(t.makePage(at: 7, width: 1080, height: 1080).background, .color("#ffffff"), "no such page: the first")

        let json = ##"{"id":"d","name":"Deck","category":"Decks","width":100,"height":100,"background":{"type":"color","value":"#ffffff"},"elements":[],"pages":[{"background":{"type":"color","value":"#ffffff"},"elements":[]},{"background":{"type":"color","value":"#222222"},"elements":[]}]}"##
        let decoded = try? JSONDecoder().decode(Template.self, from: Data(json.utf8))
        XCTAssertEqual(decoded?.pageCount, 2)
    }
}
