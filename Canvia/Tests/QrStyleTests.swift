// A QR code's colour, background and margin, as the Android twin's
// QrCodesTest has them, row for row: the keys written only when not the
// default, the scan risk, the placement of a code in its 512-pixel square,
// and the rectangles the canvas and the exports draw it with.

import XCTest
@testable import Canvia

final class QrStyleTests: XCTestCase {

    private let code = Element.image(CodeGenerator.source(for: "https://canvia.app"), w: 512, h: 512)

    private func object(_ el: Element) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any]
        return try XCTUnwrap(json)
    }

    func testTheStyleKeysAreWrittenOnlyWhenNotTheDefaultAndThePayloadKeepsThem() throws {
        XCTAssertEqual(CodeGenerator.style(of: code), CodeGenerator.Look())
        let plain = try object(CodeGenerator.styled(code, CodeGenerator.Look()))
        for key in ["qrColor", "qrBackground", "qrMargin"] { XCTAssertNil(plain[key], key) }
        let styled = CodeGenerator.styled(code, CodeGenerator.Look(color: "#1A237E", background: nil, margin: 2))
        let keys = try object(styled)
        XCTAssertEqual(keys["qrColor"] as? String, "#1a237e")
        XCTAssertEqual(keys["qrBackground"] as? String, "none")
        XCTAssertEqual(keys["qrMargin"] as? Int, 2)
        XCTAssertEqual(CodeGenerator.style(of: styled), CodeGenerator.Look(color: "#1a237e", background: nil, margin: 2))
        // A coloured background, and the defaults again taking the keys away.
        let paper = CodeGenerator.styled(styled, CodeGenerator.Look(background: "#ffeb3b"))
        XCTAssertEqual([paper.qrColor, paper.qrBackground], [nil, "#ffeb3b"])
        XCTAssertNil(paper.qrMargin)
        // A new payload is a new source; the look stays.
        var relinked = styled
        relinked.src = CodeGenerator.source(for: "new")
        XCTAssertEqual(CodeGenerator.style(of: relinked), CodeGenerator.style(of: styled))
        // Read back, and read tolerantly: a margin out of range is held to
        // 0…4, a colour that is none is the default.
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(styled))
        XCTAssertEqual([back.qrColor, back.qrBackground], ["#1a237e", "none"])
        XCTAssertEqual(back.qrMargin, 2)
        let odd = #"{"id":"el_q","type":"image","src":"qr:hi","qrMargin":9,"qrColor":"blue","qrBackground":3}"#
        let read = try JSONDecoder().decode(Element.self, from: Data(odd.utf8))
        XCTAssertEqual(CodeGenerator.style(of: read), CodeGenerator.Look())
        XCTAssertNil(read.qrMargin)
        let android = ##"{"id":"el_q","type":"image","src":"qr:hi","qrMargin":0,"qrColor":"#FF0000","qrBackground":"#FFFFFF"}"##
        let kept = try JSONDecoder().decode(Element.self, from: Data(android.utf8))
        XCTAssertEqual(CodeGenerator.style(of: kept), CodeGenerator.Look(color: "#ff0000", background: "#ffffff", margin: 0))
        XCTAssertNil(kept.qrBackground)
    }

    func testTheSharedScanRiskTable() {
        let risk = CodeGenerator.scanRiskWarning
        let rows: [(color: String, background: String?, behind: String, risk: String?)] = [
            ("#000000", "#ffffff", "#ffffff", nil),
            // Inverted: light on dark, however far apart.
            ("#ffffff", "#000000", "#ffffff", risk),
            // 4.48:1 scans; 2.85:1 may not.
            ("#777777", "#ffffff", "#ffffff", nil),
            ("#999999", "#ffffff", "#ffffff", risk),
            ("#1a237e", "#ffeb3b", "#000000", nil),
            ("#ff0000", "#ff0000", "#ffffff", risk),
            // With no background, what is behind it decides.
            ("#000000", nil, "#ffffff", nil),
            ("#000000", nil, "#222222", risk),
        ]
        for row in rows {
            XCTAssertEqual(CodeGenerator.scanRisk(color: row.color, background: row.background, pageBehind: row.behind),
                           row.risk, "\(row)")
        }
        XCTAssertEqual(risk, "This may be hard to scan")
    }

    func testTheSharedPlacementTable() {
        // A 21-module code in the 512-pixel square: whole pixels a module, centred.
        let rows: [(margin: Int, from: Double, to: Double)] = [
            (4, 77, 434), (2, 46, 466), (0, 4, 508),
        ]
        for row in rows {
            let place = CodeGenerator.placement(21, margin: row.margin)
            XCTAssertEqual(place.from, row.from / 512, "\(row)")
            XCTAssertEqual(place.to, row.to / 512, "\(row)")
        }
        XCTAssertEqual(CodeGenerator.placement(21).from, 77.0 / 512)
    }

    func testACodeGoesOutAsRectanglesARunAlongARowEach() throws {
        let grid = [[true, true, false, true], [false, false, false, false], [false, true, true, true]]
        XCTAssertEqual(CodeGenerator.runs(grid), [CGRect(x: 0, y: 0, width: 2, height: 1),
                                                  CGRect(x: 3, y: 0, width: 1, height: 1),
                                                  CGRect(x: 1, y: 2, width: 3, height: 1)])
        let v = try XCTUnwrap(CodeGenerator.vector(code))
        XCTAssertEqual(v.background, CGRect(x: 0, y: 0, width: 512, height: 512))
        // A 25-module code: the top left finder's top row is seven modules
        // of 15 at 68.
        XCTAssertEqual(CodeGenerator.modules(for: "https://canvia.app")?.count, 25)
        XCTAssertEqual(v.modules.first, CGRect(x: 68, y: 68, width: 105, height: 15))
        let bare = try XCTUnwrap(CodeGenerator.vector(CodeGenerator.styled(code, CodeGenerator.Look(background: nil, margin: 0))))
        XCTAssertNil(bare.background)
        XCTAssertEqual(bare.modules.first, CGRect(x: 6, y: 6, width: 140, height: 20))
        // A look past its colours goes out as the picture.
        var filtered = code
        filtered.filter = "noir"
        XCTAssertNil(CodeGenerator.vector(filtered))
        var bordered = code
        bordered.stroke = "#000000"
        bordered.strokeWidth = 2
        XCTAssertNil(CodeGenerator.vector(bordered))
        XCTAssertNil(CodeGenerator.vector(Element.image("media:x")))
    }

    func testACodesPictureIsInItsOwnColours() throws {
        let styled = CodeGenerator.styled(code, CodeGenerator.Look(color: "#1a237e", background: nil, margin: 4))
        let picture = try XCTUnwrap(CodeGenerator.picture(of: styled))
        XCTAssertNotEqual(picture.key, code.src)
        XCTAssertEqual(CodeGenerator.picture(of: code)?.key, code.src)
        let cg = try XCTUnwrap(picture.image.cgImage)
        XCTAssertEqual(cg.width, 512)
        XCTAssertNotEqual(cg.alphaInfo, .none, "a clear background keeps its alpha")
        XCTAssertNil(CodeGenerator.picture(of: Element.image("media:x")))
    }

    @MainActor
    func testSVGAndPowerPointDrawACodesModulesAsVectorsInItsColour() {
        var placed = code
        placed.x = 10
        placed.y = 20
        let styled = CodeGenerator.styled(placed, CodeGenerator.Look(color: "#1a237e", background: "#ffeb3b"))
        var d = Design(title: "Code", width: 800, height: 600)
        d.pages = [Page(elements: [styled])]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("<path d=\"M10 20H522V532H10Z\" fill=\"#ffeb3b\"/>"), svg)
        XCTAssertTrue(svg.contains("<path d=\"M78 88H183V103H78Z"), svg)
        XCTAssertTrue(svg.contains("fill=\"#1a237e\" shape-rendering=\"crispEdges\"/>"), svg)
        XCTAssertFalse(svg.contains("<image"), svg)
        let slide = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 1).xml
        // The background, then the modules with the element's name, both free-form.
        XCTAssertTrue(slide.contains("name=\"\(styled.id) background\""), slide)
        XCTAssertEqual(slide.components(separatedBy: "<a:custGeom>").count - 1, 2)
        XCTAssertTrue(slide.contains("<a:srgbClr val=\"FFEB3B\"/>"), slide)
        XCTAssertTrue(slide.contains("<a:srgbClr val=\"1A237E\"/>"), slide)
        XCTAssertFalse(slide.contains("<p:pic>"), slide)
        XCTAssertEqual(PptxExporter.form(of: styled), .code)
        var flipped = styled
        flipped.flipH = true
        XCTAssertEqual(PptxExporter.form(of: flipped), .picture)
    }
}
