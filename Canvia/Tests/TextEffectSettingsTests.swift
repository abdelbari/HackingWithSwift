// Text effect settings, and Echo: each effect's offset, direction, blur and
// the rest worked out into what is drawn — the same table as the Android
// twin's, at a 100 pt type size in black — and written into the design only
// where a setting differs from its effect's default, so a design from before
// the settings draws and saves as it did.

import XCTest
@testable import Canvia

@MainActor
final class TextEffectSettingsTests: XCTestCase {

    private func resolve(_ json: String, fontSize: Double = 100) throws -> ResolvedEffect {
        let spec = try JSONDecoder().decode(TextEffectSpec.self, from: Data(json.utf8))
        return TextEffect.resolve(spec, fontSize: fontSize, ink: "#000000")
    }

    private func keys(_ spec: TextEffectSpec) throws -> [String: Any] {
        let data = try JSONEncoder().encode(spec)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: the table

    func testShadow() throws {
        let plain = try resolve(#"{"type":"shadow"}"#)
        XCTAssertEqual(plain.dx, 6, accuracy: 0.001)
        XCTAssertEqual(plain.dy, 6, accuracy: 0.001)
        XCTAssertEqual(plain.blur, 12, accuracy: 0.001)
        XCTAssertEqual(plain.alpha, 0.55, accuracy: 0.001)
        XCTAssertEqual(plain.color, "#000000")
        XCTAssertTrue(plain.casts)

        let down = try resolve(#"{"type":"shadow","offset":100,"direction":90}"#)
        XCTAssertEqual(down.dx, 0, accuracy: 0.01)
        XCTAssertEqual(down.dy, 16.97, accuracy: 0.01)
        XCTAssertEqual(down.blur, 12, accuracy: 0.001)

        let clear = try resolve(#"{"type":"shadow","blur":0,"transparency":100}"#)
        XCTAssertEqual(clear.blur, 0, accuracy: 0.001)
        XCTAssertEqual(clear.alpha, 0, accuracy: 0.001)
    }

    func testLift() throws {
        let plain = try resolve(#"{"type":"lift"}"#)
        XCTAssertEqual(plain.dx, 0, accuracy: 0.001)
        XCTAssertEqual(plain.dy, 18, accuracy: 0.001)
        XCTAssertEqual(plain.blur, 50, accuracy: 0.001)
        XCTAssertEqual(plain.alpha, 0.35, accuracy: 0.001)

        let strong = try resolve(#"{"type":"lift","intensity":100}"#)
        XCTAssertEqual(strong.dy, 36, accuracy: 0.001)
        XCTAssertEqual(strong.blur, 100, accuracy: 0.001)
        XCTAssertEqual(strong.alpha, 0.7, accuracy: 0.001)
    }

    func testHollow() throws {
        XCTAssertEqual(try resolve(#"{"type":"outline"}"#).stroke, 3.5, accuracy: 0.001)
        // max(2.5, 0.35) · 2
        XCTAssertEqual(try resolve(#"{"type":"outline","thickness":100}"#, fontSize: 10).stroke, 5, accuracy: 0.001)
    }

    /// Outline's stroke round its filled letters, max(1.5, 0.04 · fs) · t / 50:
    /// the effect as a file has it, the type size, and the stroke's width —
    /// the Android twin's TextEffectsTest, row for row.
    private let outlineRows: [(json: String, fontSize: Double, width: Double)] = [
        (#"{"type":"outlined"}"#, 100, 4.0),
        (#"{"type":"outlined","thickness":100}"#, 100, 8.0),
        (#"{"type":"outlined"}"#, 10, 1.5),
        (#"{"type":"outlined","thickness":100}"#, 10, 3.0),
        (#"{"type":"outlined","thickness":25}"#, 200, 4.0),
        (#"{"type":"outlined","thickness":25}"#, 50, 1.0),
        (#"{"type":"outlined","thickness":25}"#, 20, 0.75),
        (#"{"type":"outlined","thickness":0}"#, 100, 0.0),
    ]

    func testOutline() throws {
        XCTAssertEqual(outlineRows.count, 8)
        for row in outlineRows {
            XCTAssertEqual(try resolve(row.json, fontSize: row.fontSize).stroke, row.width, accuracy: 0.001,
                           "\(row.json) at \(row.fontSize)")
        }
        let plain = try resolve(#"{"type":"outlined"}"#)
        XCTAssertEqual(plain.color, "#000000")
        XCTAssertTrue(plain.copies.isEmpty)
        XCTAssertFalse(plain.casts)
        XCTAssertEqual(try resolve(##"{"type":"outlined","color":"#ff0000"}"##).color, "#ff0000")
        // Hollow is unchanged, under its own key.
        XCTAssertEqual(try resolve(#"{"type":"outline"}"#).stroke, 3.5, accuracy: 0.001)
    }

    func testOutlineHasAThicknessAndAColourOfItsOwn() throws {
        XCTAssertEqual(TextEffect.outlined.rawValue, "outlined")
        XCTAssertEqual(TextEffect.outlined.params, [.thickness])
        XCTAssertEqual(TextEffect.outlined.defaultValue(.thickness), 50)
        XCTAssertTrue(TextEffect.outlined.takesColor)
        XCTAssertEqual(TextEffect.outlined.defaultColor, "#000000", "not optional: no Auto")
        var spec = TextEffectSpec(type: "outlined")
        spec.adjust(.thickness, to: 50)
        spec.setColor("#000000")
        XCTAssertTrue(spec.isAtDefaults)
        XCTAssertEqual(Array(try keys(spec).keys), ["type"], "defaults are left out")
        spec.adjust(.thickness, to: 80)
        spec.setColor("#ff0000")
        let written = try keys(spec)
        XCTAssertEqual(written["thickness"] as? Double, 80)
        XCTAssertEqual(written["color"] as? String, "#ff0000")
    }

    func testSplice() throws {
        let plain = try resolve(#"{"type":"splice"}"#)
        XCTAssertEqual(plain.stroke, 3, accuracy: 0.001)
        XCTAssertEqual(plain.copies.count, 1)
        let copy = try XCTUnwrap(plain.copies.first)
        XCTAssertEqual(copy.dx, 8, accuracy: 0.001)
        XCTAssertEqual(copy.dy, 8, accuracy: 0.001)
        XCTAssertEqual(copy.alpha, 0.45, accuracy: 0.001)
        XCTAssertEqual(copy.color, "#000000", "the text's own colour")

        let red = try XCTUnwrap(try resolve(##"{"type":"splice","color":"#ff0000"}"##).copies.first)
        XCTAssertEqual(red.color, "#ff0000")
        XCTAssertEqual(red.alpha, 1, accuracy: 0.001)
    }

    func testNeon() throws {
        let neon = try resolve(#"{"type":"neon"}"#)
        XCTAssertEqual(neon.blur, 35, accuracy: 0.001)
        XCTAssertEqual(neon.alpha, 0.85, accuracy: 0.001)
        XCTAssertEqual(neon.dx, 0); XCTAssertEqual(neon.dy, 0)
    }

    func testGlitch() throws {
        let plain = try resolve(#"{"type":"glitch"}"#)
        XCTAssertEqual(plain.copies.count, 2)
        XCTAssertEqual(plain.copies[0].dx, 6, accuracy: 0.001)
        XCTAssertEqual(plain.copies[0].dy, 0, accuracy: 0.001)
        XCTAssertEqual(plain.copies[0].color, "#00e5ff")
        XCTAssertEqual(plain.copies[1].dx, -6, accuracy: 0.001)
        XCTAssertEqual(plain.copies[1].dy, 0, accuracy: 0.001)
        XCTAssertEqual(plain.copies[1].color, "#ff2d78")
        XCTAssertEqual(plain.copies.map(\.alpha), [0.85, 0.85])

        let down = try resolve(#"{"type":"glitch","direction":90,"offset":100}"#)
        XCTAssertEqual(down.copies[0].dx, 0, accuracy: 0.001)
        XCTAssertEqual(down.copies[0].dy, 12, accuracy: 0.001)
        XCTAssertEqual(down.copies[1].dx, 0, accuracy: 0.001)
        XCTAssertEqual(down.copies[1].dy, -12, accuracy: 0.001)
    }

    func testEcho() throws {
        let echo = try resolve(#"{"type":"echo"}"#)
        XCTAssertEqual(TextEffect.from(TextEffectSpec(type: "echo")), .echo)
        XCTAssertEqual(echo.copies.count, 2)
        // The farther, fainter copy is drawn first.
        XCTAssertEqual(echo.copies[0].dx, 12, accuracy: 0.001)
        XCTAssertEqual(echo.copies[0].dy, 12, accuracy: 0.001)
        XCTAssertEqual(echo.copies[0].alpha, 0.25, accuracy: 0.001)
        XCTAssertEqual(echo.copies[1].dx, 6, accuracy: 0.001)
        XCTAssertEqual(echo.copies[1].dy, 6, accuracy: 0.001)
        XCTAssertEqual(echo.copies[1].alpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(echo.copies.map(\.color), ["#000000", "#000000"], "the text's own colour")
    }

    func testHighlight() throws {
        let plain = try resolve(#"{"type":"highlight"}"#)
        XCTAssertEqual(plain.pad, 18, accuracy: 0.001)
        XCTAssertEqual(plain.radius(barHeight: 40), 0, accuracy: 0.001)
        XCTAssertEqual(plain.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(plain.color, "#ffe066", "yellow under dark letters, as before")

        let round = try resolve(#"{"type":"highlight","roundness":100}"#)
        XCTAssertEqual(round.radius(barHeight: 40), 20, accuracy: 0.001)
    }

    /// Shared rows (Fixtures/extrude.json): 3D's layers, back to front.
    func testExtrudeLayersAreTheSharedRows() throws {
        let fixture = try SharedFixture.object("extrude")
        let rows = try XCTUnwrap(fixture["rows"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let spec = try JSONDecoder().decode(TextEffectSpec.self, from: SharedFixture.encoded(XCTUnwrap(row["spec"])))
            let size = try XCTUnwrap(row["fontSize"] as? Double)
            let ink = try XCTUnwrap(row["ink"] as? String)
            let fx = TextEffect.resolve(spec, fontSize: size, ink: ink)
            XCTAssertEqual(fx.copies.count, row["count"] as? Int, "\(spec)")
            for (key, layer) in [("farthest", fx.copies.first), ("nearest", fx.copies.last)] {
                guard let expected = row[key] as? [String: Any] else { continue }
                let got = try XCTUnwrap(layer)
                XCTAssertEqual(got.dx, try XCTUnwrap(expected["dx"] as? Double), accuracy: 0.001, "\(spec) \(key)")
                XCTAssertEqual(got.dy, try XCTUnwrap(expected["dy"] as? Double), accuracy: 0.001, "\(spec) \(key)")
                XCTAssertEqual(got.color, expected["color"] as? String, "\(spec) \(key)")
                XCTAssertEqual(got.alpha, 1)
            }
        }
    }

    func testExtrudeSettingsAndColour() throws {
        let effect = TextEffect.extrude
        XCTAssertEqual(effect.params, [.depth, .direction, .shading])
        XCTAssertEqual(effect.defaultValue(.depth), 40)
        XCTAssertEqual(effect.defaultValue(.direction), 135)
        XCTAssertEqual(effect.defaultValue(.shading), 40)
        XCTAssertTrue(effect.takesColor)
        XCTAssertNil(effect.defaultColor, "Auto: the ink, darkened")
        XCTAssertTrue(effect.takesGradient)
        // Settings at their defaults are left out; others are written.
        var spec = TextEffectSpec(type: "extrude")
        spec.adjust(.depth, to: 40)
        spec.adjust(.shading, to: 70)
        let written = try keys(spec)
        XCTAssertNil(written["depth"])
        XCTAssertEqual(written["shading"] as? Double, 70)
        let back = try JSONDecoder().decode(TextEffectSpec.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(back, spec)
    }

    /// The contrast check reads the front face, not the block behind it:
    /// white letters on a white page fall short however dark their 3D.
    func testContrastIsCheckedAgainstTheFrontFace() {
        var el = Element.text("Sale", fontSize: 20, w: 200)
        el.color = "#ffffff"
        el.effect = TextEffectSpec(type: "extrude", color: "#000000")
        var design = Design(title: "Poster", width: 400, height: 400)
        design.pages = [Page(background: .color("#ffffff"), elements: [el])]
        let findings = ContrastAudit.audit(design)
        XCTAssertEqual(findings.map(\.elementId), [el.id])
        XCTAssertEqual(findings.first?.ratio ?? 0, 1, accuracy: 0.01)
    }

    // MARK: names and order

    func testTilesAreInTheTwinsOrderAndGlitchIsCalledGlitch() {
        XCTAssertEqual(TextEffect.allCases.map(\.displayName),
                       ["None", "Shadow", "Lift", "Hollow", "Outline", "Splice", "Echo", "3D", "Glitch", "Neon", "Highlight"])
        XCTAssertEqual(TextEffect.allCases.map(\.rawValue),
                       ["none", "shadow", "lift", "outline", "outlined", "splice", "echo", "extrude", "glitch", "neon",
                        "highlight"])
        XCTAssertEqual(TextEffect.glitch.rawValue, "glitch")
        XCTAssertEqual(TextEffect.echo.rawValue, "echo")
    }

    // MARK: JSON

    func testAPlainEffectIsWrittenAsItsTypeAlone() throws {
        let shadow = try JSONDecoder().decode(TextEffectSpec.self, from: Data(#"{"type":"shadow"}"#.utf8))
        XCTAssertEqual(Array(try keys(shadow).keys), ["type"])
    }

    func testASettingAtItsDefaultIsLeftOut() throws {
        let atDefault = TextEffectSpec(type: "shadow", offset: 50, blur: 20)
        let written = try keys(atDefault)
        XCTAssertNil(written["offset"])
        XCTAssertEqual(written["blur"] as? Double, 20)

        var spec = TextEffectSpec(type: "glitch")
        spec.adjust(.offset, to: 50)
        spec.setColor("#00E5FF")
        XCTAssertTrue(spec.isAtDefaults, "glitch's own colour is its default")
        spec.adjust(.offset, to: 72.4)
        XCTAssertEqual(spec.offset, 72, "sliders move in whole steps")
    }

    func testABadSettingLosesOnlyItself() throws {
        let spec = try JSONDecoder().decode(TextEffectSpec.self,
                                            from: Data(#"{"type":"shadow","blur":"x","offset":80}"#.utf8))
        XCTAssertEqual(TextEffect.from(spec), .shadow)
        XCTAssertNil(spec.blur)
        XCTAssertEqual(spec.offset, 80)
        XCTAssertEqual(TextEffect.resolve(spec, fontSize: 100, ink: "#000000").blur, 12, accuracy: 0.001)
    }

    func testASettingPastTheSliderIsDrawnAsItIs() throws {
        // As on the Android twin, which keeps no setting in range.
        let lift = try resolve(#"{"type":"lift","intensity":150}"#, fontSize: 50)
        XCTAssertEqual(lift.dy, 27, accuracy: 0.001)
        XCTAssertEqual(lift.blur, 75, accuracy: 0.001)
        XCTAssertEqual(lift.alpha, 1, accuracy: 0.001)

        let up = try resolve(#"{"type":"shadow","direction":270}"#)
        XCTAssertEqual(up.dx, 0, accuracy: 0.01)
        XCTAssertEqual(up.dy, -8.49, accuracy: 0.01)
    }

    func testAnUnknownTypeDrawsAsNoneAndKeepsItsName() throws {
        let spec = try JSONDecoder().decode(TextEffectSpec.self,
                                            from: Data(#"{"type":"sparkle","offset":20}"#.utf8))
        XCTAssertEqual(TextEffect.from(spec), .none)
        let written = try keys(spec)
        XCTAssertEqual(written["type"] as? String, "sparkle")
        XCTAssertEqual(written["offset"] as? Double, 20, "nothing to compare with, so it is kept")
    }

    func testSettingsSurviveTheDesignFile() throws {
        var el = Element.text("Hello")
        el.effect = TextEffectSpec(type: "echo", offset: 80, direction: -30, color: "#336699")
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.effect, el.effect)
    }

    // MARK: in the editor

    private func store(_ el: Element) -> DesignStore {
        var design = Design(title: "effects", width: 1000, height: 1000)
        design.pages[0].elements = [el]
        let s = DesignStore(design: design)
        s.selection = [el.id]
        return s
    }

    func testADragIsOneStepAndAnotherEffectStartsFromItsDefaults() {
        var el = Element.text("Hello")
        el.effect = TextEffectSpec(type: "shadow")
        let s = store(el)
        for v in [60.0, 70, 80] {
            s.updateSelectedTransient { $0.effect?.adjust(.offset, to: v) }
        }
        s.commit()
        XCTAssertEqual(s.element(el.id)?.effect?.offset, 80)
        s.undo()
        XCTAssertNil(s.element(el.id)?.effect?.offset, "one drag, one Undo")
        s.redo()

        s.updateSelected { $0.effect = TextEffectSpec(type: "lift") }
        XCTAssertEqual(s.element(el.id)?.effect, TextEffectSpec(type: "lift"))
    }

    func testASavedStyleCarriesTheSettings() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("effects-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var source = Element.text("Loud")
        source.effect = TextEffectSpec(type: "highlight", roundness: 60, color: "#ff00aa")
        let saved = TextStyles.add(named: "Loud", from: source, url: url)
        XCTAssertEqual(TextStyles.load(from: url).first?.style.effect, source.effect)
        var target = Element.text("Quiet")
        TextStyles.apply(saved, to: &target)
        XCTAssertEqual(target.effect, source.effect)
    }
}
