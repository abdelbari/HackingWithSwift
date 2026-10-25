// Diagrams: their layouts from the fixture both phones read
// (Fixtures/diagrams.json), their JSON, the list editor, the store's one
// step an edit and what VoiceOver hears — the Android twin's DiagramsTest,
// case for case.

import CoreGraphics
import XCTest
@testable import Canvia

final class DiagramsTests: XCTestCase {

    private let palette = ["#1a6bff", "#ff7a00", "#16c79a", "#e94560"]

    private func spec(_ row: [String: Any]) throws -> DiagramSpec {
        let kind = try XCTUnwrap(DiagramKind(rawValue: try XCTUnwrap(row["kind"] as? String)))
        let items = try XCTUnwrap(row["items"] as? [[String: Any]]).map { o in
            DiagramItem(text: o["text"] as? String ?? "", level: o["level"] as? Int)
        }
        return DiagramSpec(id: "dia_t", kind: kind, items: items)
    }

    private func parts(_ made: [Element], _ prefix: String) -> [Element] {
        made.filter { ($0.diagramPart ?? "").hasPrefix(prefix) }
    }

    func testEveryKindLaysOutAsTheFixtureSays() throws {
        let cases = try XCTUnwrap(try SharedFixture.object("diagrams")["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for row in cases {
            let spec = try spec(row)
            let b = try XCTUnwrap(row["box"] as? [Double])
            let made = Diagrams.make(spec, in: CGRect(x: b[0], y: b[1], width: b[2], height: b[3]), palette: palette)
            let byPart = Dictionary(made.map { ($0.diagramPart ?? "", $0) }, uniquingKeysWith: { a, _ in a })
            let what = spec.kind.rawValue
            let expected = try XCTUnwrap(row["parts"] as? [[String: Any]])
            for part in expected {
                let name = try XCTUnwrap(part["part"] as? String)
                let el = try XCTUnwrap(byPart[name], "\(what) has no \(name)")
                let r = try XCTUnwrap(part["rect"] as? [Double])
                XCTAssertEqual(el.x, r[0], accuracy: 1e-6, "\(what) \(name) x")
                XCTAssertEqual(el.y, r[1], accuracy: 1e-6, "\(what) \(name) y")
                XCTAssertEqual(el.w, r[2], accuracy: 1e-6, "\(what) \(name) w")
                XCTAssertEqual(el.h, r[3], accuracy: 1e-6, "\(what) \(name) h")
            }
            // Every part is the diagram's, in one group; and the connectors
            // join the items the fixture says, in order.
            XCTAssertTrue(made.allSatisfy { $0.diagram == spec && $0.group == made.first?.group }, what)
            var itemOf: [String: Int] = [:]
            for el in parts(made, "item:") { itemOf[el.id] = Diagrams.index(el.diagramPart, "item:") }
            let joins = parts(made, "connector:").map { [$0.connectFrom.flatMap { itemOf[$0] } ?? -1,
                                                          $0.connectTo.flatMap { itemOf[$0] } ?? -1] }
            XCTAssertEqual(joins, try XCTUnwrap(row["connectors"] as? [[Int]]), what)
            XCTAssertEqual(made.count, expected.count + joins.count, what)
        }
    }

    func testMadeAgainInTheBoxItsPartsFillADiagramStaysWhereItIs() throws {
        for kind in DiagramKind.allCases {
            let spec = Diagrams.starter(kind)
            let made = Diagrams.make(spec, in: CGRect(x: 37, y: 51, width: 713, height: 389), palette: palette)
            var page = Page()
            page.elements = made
            let again = try XCTUnwrap(Diagrams.remade(on: page, spec, palette: palette), kind.rawValue)
            XCTAssertEqual(made.count, again.count, kind.rawValue)
            for (was, now) in zip(made, again) {
                XCTAssertEqual(was.x, now.x, accuracy: 1e-6, kind.rawValue)
                XCTAssertEqual(was.y, now.y, accuracy: 1e-6, kind.rawValue)
                XCTAssertEqual(was.w, now.w, accuracy: 1e-6, kind.rawValue)
                XCTAssertEqual(was.h, now.h, accuracy: 1e-6, kind.rawValue)
            }
            XCTAssertEqual(made.first?.group, again.first?.group, kind.rawValue)
        }
        XCTAssertNil(Diagrams.remade(on: Page(), Diagrams.starter(.cycle), palette: palette))
    }

    func testWordsTypedOnThePageAreWhatEditDiagramStartsFromAsTheFixtureSays() throws {
        let cases = try XCTUnwrap(try SharedFixture.object("diagrams")["synced"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for row in cases {
            let name = row["name"] as? String ?? ""
            let items = try XCTUnwrap(row["items"] as? [[String: Any]]).map { o in
                DiagramItem(text: o["text"] as? String ?? "", note: o["note"] as? String)
            }
            let kind = try XCTUnwrap(DiagramKind(rawValue: try XCTUnwrap(row["kind"] as? String)))
            let spec = DiagramSpec(id: "dia_t", kind: kind, items: items)
            var made = Diagrams.make(spec, in: CGRect(x: 0, y: 0, width: 600, height: 400), palette: palette)
            for edit in try XCTUnwrap(row["edits"] as? [[String: Any]]) {
                let part = edit["part"] as? String
                for i in made.indices where made[i].diagramPart == part {
                    made[i].text = edit["text"] as? String
                    if let font = edit["font"] as? String { made[i].fontFamily = font }
                }
            }
            let synced = Diagrams.synced(spec, members: made)
            let expect = try XCTUnwrap(row["expect"] as? [[String: Any]])
            XCTAssertEqual(synced.items.map(\.text), expect.map { $0["text"] as? String ?? "" }, name)
            XCTAssertEqual(synced.items.map(\.note), expect.map { $0["note"] as? String }, name)
            XCTAssertEqual(synced.font, row["font"] as? String, name)
        }
    }

    func testMadeAgainADiagramKeepsItsTurnGroupsFadeLinkAndHiding() throws {
        let spec = DiagramSpec(id: "dia_t", kind: .cycle, items: ["Plan", "Do", "Check", "Act"].map { DiagramItem(text: $0) })
        let made = Diagrams.make(spec, in: CGRect(x: 100, y: 100, width: 400, height: 400), palette: palette, group: "g")
        let box = made.dropFirst().reduce(made[0].frame) { $0.union($1.frame) }
        let turned = Geometry.rotate(made, around: CGPoint(x: box.midX, y: box.midY), by: 30).map { el -> Element in
            var out = Groups.withChain(el, ["outer", "g"])
            out.groupTurn = 30
            out.link = "https://example.com"
            out.opacity = 0.5
            return out
        }
        var page = Page()
        page.elements = turned
        let renamed = Diagrams.editing(spec, at: 0, text: "Research", note: nil)
        let again = try XCTUnwrap(Diagrams.remade(on: page, renamed, palette: palette))
        XCTAssertEqual(turned.count, again.count)
        for (was, now) in zip(turned, again) {
            XCTAssertEqual(was.x, now.x, accuracy: 1e-6)
            XCTAssertEqual(was.y, now.y, accuracy: 1e-6)
            XCTAssertEqual(was.w, now.w, accuracy: 1e-6)
            XCTAssertEqual(was.h, now.h, accuracy: 1e-6)
            XCTAssertEqual(was.rotation, now.rotation, accuracy: 1e-6)
            XCTAssertEqual(Groups.chain(now), ["outer", "g"])
            XCTAssertEqual(now.groupTurn, 30)
            XCTAssertEqual(now.opacity, 0.5)
            XCTAssertEqual(now.link, "https://example.com")
            XCTAssertFalse(now.isHidden)
        }
        let first = try XCTUnwrap(again.first { $0.diagramPart == "item:0" })
        XCTAssertEqual(RichText.strip(first.text ?? ""), "Research")
        // Hidden whole, it stays hidden.
        page.elements = made.map { el -> Element in
            var out = el
            out.hidden = true
            return out
        }
        let hidden = try XCTUnwrap(Diagrams.remade(on: page, spec, palette: palette))
        XCTAssertTrue(hidden.allSatisfy(\.isHidden))
    }

    func testThePagesColoursForAnEditDoNotCountTheDiagramsOwn() {
        let blank = Design(title: "Blank", width: 1080, height: 1080)
        let fresh = DataGraphics.palette(for: blank, page: blank.pages[0], brand: nil)
        let spec = DiagramSpec(id: "dia_t", kind: .process, items: ["A", "B", "C"].map { DiagramItem(text: $0) })
        var design = blank
        design.pages[0].elements = Diagrams.make(spec, in: CGRect(x: 0, y: 0, width: 600, height: 200), palette: palette)
        let page = design.pages[0]
        XCTAssertNotEqual(DataGraphics.palette(for: design, page: page, brand: nil), fresh)
        XCTAssertEqual(Diagrams.palette(updating: "dia_t", design: design, page: page, brand: nil), fresh)
    }

    func testVennCirclesAreSeeThroughAndMultipliedAndStylesPaintAsTheySay() throws {
        let venn = Diagrams.make(Diagrams.starter(.venn3), in: CGRect(x: 0, y: 0, width: 600, height: 600), palette: palette)
        let circles = parts(venn, "item:")
        XCTAssertEqual(circles.count, 3)
        XCTAssertTrue(circles.allSatisfy { $0.opacity == 0.7 && $0.blendMode == "multiply" && $0.text == nil })
        XCTAssertEqual(parts(venn, "label:").map(\.text), ["Fast", "Good", "Cheap"])

        let spec = Diagrams.starter(.process)
        let box = CGRect(x: 0, y: 0, width: 800, height: 200)
        let solid = try XCTUnwrap(Diagrams.make(spec, in: box, palette: palette).first)
        XCTAssertEqual(solid.fill?.color, "#1a6bff")
        XCTAssertEqual(solid.color, ShapeText.defaultInk(for: solid.fill))
        var outlined = spec
        outlined.style = .outline
        let outline = try XCTUnwrap(Diagrams.make(outlined, in: box, palette: palette).first)
        XCTAssertEqual(outline.fill?.kind, "none")
        XCTAssertEqual(outline.stroke, "#1a6bff")
        XCTAssertEqual(outline.color, "#1a6bff")
        var softened = spec
        softened.style = .soft
        let soft = try XCTUnwrap(Diagrams.make(softened, in: box, palette: palette).first)
        XCTAssertEqual(soft.fill?.color, Diagrams.tint("#1a6bff"))
        XCTAssertEqual(Diagrams.tint("#1a6bff"), "#c6daff")
        // Its own palette, then an item's own colour, before the page's.
        var own = spec
        own.palette = ["#000000", "#ffffff"]
        own.items[1].color = "#ff0000"
        let fills = parts(Diagrams.make(own, in: box, palette: palette), "item:").map { $0.fill?.color }
        XCTAssertEqual(fills, ["#000000", "#ff0000", "#000000", "#ffffff"])
        // A note is the item's second line; words are literal; a blank note is none.
        XCTAssertNil(Diagrams.editing(spec, at: 0, text: "**Idea**", note: "  ").items[0].note)
        let first = try XCTUnwrap(Diagrams.make(Diagrams.editing(spec, at: 0, text: "Idea", note: "Week 1"), in: box,
                                                palette: palette).first)
        XCTAssertEqual(RichText.strip(first.text ?? ""), "Idea\nWeek 1")
    }

    func testTheJSONWritesOnlyWhatIsSetAndReadsBack() throws {
        let spec = DiagramSpec(id: "dia_1", kind: .orgChart,
                               items: [DiagramItem(text: "Boss", level: 0),
                                       DiagramItem(text: "Me", note: "hi", color: "#ff0000", level: 1)],
                               style: .soft, palette: ["#123456", "#abcdef"], font: "serif")
        XCTAssertEqual(try JSONDecoder().decode(DiagramSpec.self, from: try JSONEncoder().encode(spec)), spec)
        let bare = DiagramSpec(id: "dia_2", kind: .cycle, items: [DiagramItem(text: "A"), DiagramItem(text: "B")])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(bare)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["id", "kind", "items", "style"])
        XCTAssertEqual(Set(try XCTUnwrap((json["items"] as? [[String: Any]])?.first).keys), ["text"])
        XCTAssertEqual(json["style"] as? String, "solid")
        // An unknown kind is no diagram this build draws; nor is one without an id.
        func read(_ o: [String: Any]) -> DiagramSpec? {
            (try? JSONSerialization.data(withJSONObject: o)).flatMap { try? JSONDecoder().decode(DiagramSpec.self, from: $0) }
        }
        var mindMap = json
        mindMap["kind"] = "mindMap"
        XCTAssertNil(read(mindMap))
        var noId = json
        noId.removeValue(forKey: "id")
        XCTAssertNil(read(noId))
        var noStyle = json
        noStyle["style"] = NSNull()
        XCTAssertEqual(read(noStyle)?.style, .solid)
        XCTAssertTrue(Diagrams.newId().hasPrefix("dia_"))
        // A part carries it, and its part, through a design file.
        var el = Element.shape("rect")
        el.diagram = bare
        el.diagramPart = "item:0"
        let back = try JSONDecoder().decode(Element.self, from: try JSONEncoder().encode(el))
        XCTAssertEqual(back.diagram, bare)
        XCTAssertEqual(back.diagramPart, "item:0")
    }

    func testTheListEditorKeepsEachKindBetweenItsFewestAndMostItems() {
        let venn = Diagrams.starter(.venn2)
        XCTAssertEqual(Diagrams.adding(venn, text: "More"), venn)
        XCTAssertEqual(Diagrams.removing(venn, at: 0), venn)
        var cycle = Diagrams.starter(.cycle)
        cycle = Diagrams.adding(cycle, text: "Learn", after: 0)
        XCTAssertEqual(cycle.items.map(\.text), ["Plan", "Learn", "Do", "Check", "Act"])
        cycle = Diagrams.moving(cycle, at: 1, by: 10)
        XCTAssertEqual(cycle.items.map(\.text), ["Plan", "Do", "Check", "Act", "Learn"])
        for _ in 0..<5 { cycle = Diagrams.adding(cycle, text: "x") }
        XCTAssertEqual(cycle.items.count, 8)
        for _ in 0..<9 { cycle = Diagrams.removing(cycle, at: 0) }
        XCTAssertEqual(cycle.items.count, 2)
        // Switching keeps what it can: a Venn of two from four, a cycle of two made up.
        XCTAssertEqual(Diagrams.switching(Diagrams.starter(.cycle), to: .venn2).items.map(\.text), ["Plan", "Do"])
        XCTAssertEqual(Diagrams.switching(Diagrams.starter(.venn2), to: .venn3).items.map(\.text), ["Ours", "Theirs", "Item 3"])
        XCTAssertEqual(Diagrams.levels(Diagrams.switching(Diagrams.starter(.cycle), to: .orgChart)), [0, 1, 1, 1])
    }

    func testAnOrgChartsLevelsStepOneAtATime() {
        let org = Diagrams.starter(.orgChart)
        XCTAssertEqual(Diagrams.levels(org), [0, 1, 1, 2, 2])
        // The first stays at the top; one goes at most one deeper than the item above.
        XCTAssertEqual(Diagrams.indenting(org, at: 0, by: 1), org)
        XCTAssertEqual(Diagrams.levels(Diagrams.indenting(org, at: 2, by: 1)), [0, 1, 2, 2, 2])
        let twice = Diagrams.indenting(Diagrams.indenting(org, at: 2, by: 1), at: 2, by: 1)
        XCTAssertEqual(Diagrams.levels(Diagrams.indenting(twice, at: 2, by: -1)), [0, 1, 1, 2, 2])
        XCTAssertEqual(Diagrams.levels(Diagrams.indenting(org, at: 3, by: -1)), [0, 1, 1, 1, 2])
        // Levels written past their room are read as far as they go.
        var odd = org
        for (i, level) in [2, 5, 0, 3, 1].enumerated() { odd.items[i].level = level }
        XCTAssertEqual(Diagrams.levels(odd), [0, 1, 0, 1, 1])
        // Added after an item, at its level.
        XCTAssertEqual(Diagrams.adding(org, text: "Intern", after: 3).items[4].level, 2)
        // Not an org chart: indenting does nothing.
        let cycle = Diagrams.starter(.cycle)
        XCTAssertEqual(Diagrams.indenting(cycle, at: 1, by: 1), cycle)
    }

    func testColoursArePinnedToTheirItemsAndANewPaletteLetsThemGo() throws {
        let spec = Diagrams.starter(.matrix2x2)
        let box = CGRect(x: 0, y: 0, width: 400, height: 400)
        let made = Diagrams.make(spec, in: box, palette: palette)
        let recoloured = made.map { el -> Element in
            var out = el
            if el.diagramPart == "item:2" { out.fill = .solid("#00ff00") }
            return out
        }
        let pinned = Diagrams.pinned(spec, members: recoloured)
        XCTAssertEqual(pinned.items.map(\.color), ["#1a6bff", "#ff7a00", "#00ff00", "#e94560"])
        // Taken away, the rest keep theirs.
        let fewer = Diagrams.removing(pinned, at: 0)
        XCTAssertEqual(parts(Diagrams.make(fewer, in: box, palette: palette), "item:").map { $0.fill?.color },
                       ["#ff7a00", "#00ff00", "#e94560"])
        let repainted = Diagrams.repainted(pinned, palette: ["#111111", "#222222"])
        XCTAssertTrue(repainted.items.allSatisfy { $0.color == nil })
        XCTAssertEqual(repainted.palette, ["#111111", "#222222"])
        XCTAssertNil(Diagrams.repainted(pinned, palette: []).palette)
    }

    func testAReaderHearsADiagramAsAList() {
        let org = Diagrams.starter(.orgChart)
        XCTAssertEqual(Diagrams.summary(org), "Org chart diagram, 5 items")
        XCTAssertEqual(Diagrams.stops(org)[1], "2 of 5: Design lead, level 2")
        let cycle = Diagrams.editing(Diagrams.starter(.cycle), at: 0, text: "Plan", note: "Monday")
        XCTAssertEqual(Diagrams.stops(cycle), ["1 of 4: Plan, Monday", "2 of 4: Do", "3 of 4: Check", "4 of 4: Act"])
        // Read from the parts on the page, as one stop with its items as values.
        let made = Diagrams.make(cycle, in: CGRect(x: 0, y: 0, width: 400, height: 400), palette: palette)
        XCTAssertNotNil(Diagrams.of(made))
        var other = Element.shape("rect")
        other.diagram = Diagrams.starter(.venn2)
        XCTAssertNil(Diagrams.of(made + [other]))
        XCTAssertEqual(CanvasAccessibility.label(for: made[0]), "Cycle diagram, 4 items")
        XCTAssertEqual(CanvasAccessibility.values(ofChart: cycle.id, in: made), Diagrams.stops(cycle))
        let order = made.map(\.id)
        let stops = CanvasAccessibility.chartStops(made, order: order)
        XCTAssertEqual(stops.heads, [made[0].id])
        XCTAssertEqual(stops.hidden.count, made.count - 1)
    }

    /// Add puts one across the middle of the page, selected, one step; an
    /// edit is one step more, the diagram made again where it stands; a
    /// locked page refuses the edit.
    @MainActor
    func testTheStoreAddsAndEditsADiagramAsOneStepEach() throws {
        let store = DesignStore(design: Design(title: "t", width: 1000, height: 1000))
        XCTAssertTrue(store.addDiagram(.cycle))
        let spec = try XCTUnwrap(store.selectedDiagram)
        XCTAssertEqual(store.selection.count, store.page.elements.count)
        let box = try XCTUnwrap(Diagrams.frame(of: spec.id, on: store.page))
        XCTAssertTrue(store.updateDiagram(Diagrams.adding(spec, text: "Learn")))
        let after = try XCTUnwrap(store.selectedDiagram)
        XCTAssertEqual(after.items.count, 5)
        XCTAssertEqual(Diagrams.members(store.page, id: spec.id).count, 10)
        let again = try XCTUnwrap(Diagrams.frame(of: spec.id, on: store.page))
        XCTAssertEqual(again.midX, box.midX, accuracy: 1e-6)
        XCTAssertEqual(again.midY, box.midY, accuracy: 1e-6)
        store.undo()
        XCTAssertEqual(store.page.elements.compactMap(\.diagram).first?.items.count, 4)
        store.undo()
        XCTAssertTrue(store.page.elements.isEmpty)
        // A copy is a diagram of its own.
        let copied = Copies.of(Diagrams.make(spec, in: box, palette: palette))
        XCTAssertNotEqual(copied.first?.diagram?.id, spec.id)
        XCTAssertEqual(Set(copied.compactMap(\.diagram?.id)).count, 1)
    }

    func testACopiedDiagramIsADiagramOfItsOwn() throws {
        let spec = Diagrams.starter(.cycle)
        let made = Diagrams.make(spec, in: CGRect(x: 0, y: 0, width: 400, height: 400), palette: palette)
        let copied = Copies.of(made, offset: 24)
        let ids = Array(Set(copied.compactMap(\.diagram?.id)))
        XCTAssertEqual(ids.count, 1)
        let id = try XCTUnwrap(ids.first)
        XCTAssertNotEqual(id, spec.id)
        XCTAssertTrue(id.hasPrefix("dia_"))
        // Each is whole, so Edit diagram on the copy leaves the original be.
        var page = Page()
        page.elements = made + copied
        XCTAssertEqual(Diagrams.members(page, id: spec.id).map(\.id), made.map(\.id))
        XCTAssertEqual(Diagrams.members(page, id: id).map(\.id), copied.map(\.id))
        // A component's diagram, put in twice, is two diagrams.
        let component = try XCTUnwrap(Components.make(named: "Cycle", from: made))
        let first = try XCTUnwrap(Diagrams.of(Components.instance(of: component, width: 200, at: .zero))).id
        let second = try XCTUnwrap(Diagrams.of(Components.instance(of: component, width: 200, at: CGPoint(x: 300, y: 0)))).id
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, spec.id)
    }
}
