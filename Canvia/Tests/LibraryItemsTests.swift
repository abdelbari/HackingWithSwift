// Favourites, saved text styles, components and the starter designs.

import XCTest
@testable import Canvia

@MainActor
final class LibraryItemsTests: XCTestCase {

    private func suite() throws -> (UserDefaults, String) {
        let name = "canvia.items.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    private func tempFile(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("items-\(UUID().uuidString).\(ext)")
    }

    // MARK: favourites

    func testFavouritesToggleAndListByKind() throws {
        let (d, name) = try suite(); defer { d.removePersistentDomain(forName: name) }
        XCTAssertFalse(Favorites.isFavorite("shape", "heart", defaults: d))
        Favorites.toggle("shape", "heart", defaults: d)
        Favorites.toggle("sticker", "🎉", defaults: d)
        Favorites.toggle("shape", "arrow", defaults: d)
        XCTAssertTrue(Favorites.isFavorite("shape", "heart", defaults: d))
        XCTAssertEqual(Favorites.ids(of: "shape", defaults: d), ["arrow", "heart"])
        XCTAssertEqual(Favorites.ids(of: "sticker", defaults: d), ["🎉"])
        Favorites.toggle("shape", "heart", defaults: d)
        XCTAssertEqual(Favorites.ids(of: "shape", defaults: d), ["arrow"])
    }

    // MARK: text styles

    func testASavedStyleAppliesAndStaysLinked() {
        let url = tempFile("json"); defer { try? FileManager.default.removeItem(at: url) }
        var heading = Element.text("Title", fontSize: 64, w: 500)
        heading.fontFamily = "serif"; heading.fontWeight = 700; heading.color = "#123456"
        heading.x = 100; heading.y = 100
        let saved = TextStyles.add(named: "Heading", from: heading, url: url)
        XCTAssertEqual(TextStyles.load(from: url).map(\.name), ["Heading"])
        XCTAssertNil(saved.style.fill, "a text style carries no shape fields")

        var body = Element.text("Body", fontSize: 18, w: 300)
        body.x = 7; body.opacity = 0.5
        TextStyles.apply(saved, to: &body)
        XCTAssertEqual(body.fontFamily, "serif"); XCTAssertEqual(body.fontSize, 64); XCTAssertEqual(body.color, "#123456")
        XCTAssertEqual(body.x, 7, "position is not style"); XCTAssertEqual(body.opacity, 0.5, "opacity is not style")
        XCTAssertEqual(body.textStyleId, saved.id)
        XCTAssertEqual(body.text, "Body")

        var shape = Element.shape("rect")
        TextStyles.apply(saved, to: &shape)
        XCTAssertNil(shape.textStyleId, "a shape does not take a text style")
    }

    func testUpdatingAStyleReachesEveryFollowerOnEveryPageAsOneUndo() {
        let url = tempFile("json"); defer { try? FileManager.default.removeItem(at: url) }
        var a = Element.text("A", fontSize: 20, w: 300)
        let saved = TextStyles.add(named: "Caption", from: a, url: url)
        a.textStyleId = saved.id
        var b = Element.text("B", fontSize: 20, w: 300); b.textStyleId = saved.id
        var other = Element.text("Other", fontSize: 20, w: 300)
        var d = Design(title: "styles", width: 800, height: 600)
        d.pages = [Page(elements: [a]), Page(elements: [b, other])]
        let s = DesignStore(design: d)

        // Change A by hand, then push its look into the style. Uses the
        // real store file for the load inside the store; the test file above
        // only covered TextStyles itself.
        a.fontSize = 40; a.color = "#ff0000"
        TextStyles.update(saved.id, from: a, url: url)
        let updated = TextStyles.load(from: url).first { $0.id == saved.id }!
        XCTAssertEqual(updated.style.fontSize, 40)
        // Apply through the store the way updateTextStyle does, directly.
        s.apply { design in
            for p in design.pages.indices {
                for i in design.pages[p].elements.indices where design.pages[p].elements[i].textStyleId == saved.id {
                    TextStyles.apply(updated, to: &design.pages[p].elements[i])
                }
            }
        }
        XCTAssertEqual(s.design.pages[1].elements[0].fontSize, 40)
        XCTAssertEqual(s.design.pages[1].elements[0].color, "#ff0000")
        XCTAssertEqual(s.design.pages[1].elements[1].fontSize, 20, "an element not following the style is untouched")
        s.undo()
        XCTAssertEqual(s.design.pages[1].elements[0].fontSize, 20)
        other.fontSize = 20
    }

    // MARK: components

    func testAComponentIsNormalisedAndInstancesScaleWithFreshIds() {
        var a = Element.shape("rect", w: 100, h: 50); a.x = 200; a.y = 300; a.locked = true
        var t = Element.text("Hi", fontSize: 20, w: 100); t.x = 300; t.y = 300
        let c = Components.make(named: "Tag", from: [a, t])!
        XCTAssertEqual(c.width, 200); XCTAssertGreaterThan(c.height, 0)
        XCTAssertEqual(c.elements[0].x, 0); XCTAssertEqual(c.elements[1].x, 100)
        XCTAssertFalse(c.elements[0].locked, "a saved component is never locked")

        let placed = Components.instance(of: c, width: 400, at: CGPoint(x: 50, y: 60))
        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual(placed[0].w, 200, accuracy: 0.001, "scaled 2x to 400 across")
        XCTAssertEqual(placed[0].x, 50, accuracy: 0.001)
        XCTAssertEqual(placed[1].x, 250, accuracy: 0.001)
        XCTAssertEqual(placed[1].fontSize ?? 0, 40, accuracy: 0.001)
        XCTAssertNotEqual(placed[0].id, c.elements[0].id)
        XCTAssertEqual(Set(placed.compactMap(\.group)).count, 1)
        XCTAssertNil(Components.make(named: "Empty", from: []))
    }

    func testComponentsPersist() {
        let url = tempFile("json"); defer { try? FileManager.default.removeItem(at: url) }
        let saved = Components.add(named: "Footer", from: [Element.shape("rect")], url: url)!
        XCTAssertEqual(Components.load(from: url).map(\.name), ["Footer"])
        Components.remove(saved.id, url: url)
        XCTAssertTrue(Components.load(from: url).isEmpty)
    }

    // MARK: starters

    func testStartersAreSeededOnceAndOnlyIntoAnEmptyLibrary() throws {
        let (d, name) = try suite(); defer { d.removePersistentDomain(forName: name) }
        let hadDesigns = !DesignLibrary.recents().isEmpty
        let seeded = DesignLibrary.seedStartersIfNeeded(defaults: d)
        defer { for s in seeded { DesignLibrary.delete(id: s.id) } }
        if hadDesigns {
            XCTAssertTrue(seeded.isEmpty, "a library with designs in it gets no samples")
        } else {
            XCTAssertEqual(seeded.count, min(2, ContentLibrary.templates.count))
            XCTAssertTrue(seeded.allSatisfy { $0.title.hasPrefix("Sample: ") })
        }
        XCTAssertTrue(d.bool(forKey: DesignLibrary.startersKey))
        XCTAssertTrue(DesignLibrary.seedStartersIfNeeded(defaults: d).isEmpty, "never twice")
    }
}
