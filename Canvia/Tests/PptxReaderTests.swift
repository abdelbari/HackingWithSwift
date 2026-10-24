// The PowerPoint reader. The fixture test and the rows marked shared hold
// the same file and the same expected design as the Android twin's
// PptxReaderTest: the same deck is the same design on either phone.
// Fixtures/deck.pptx and Fixtures/deck.json are the twin's
// tools/generate_pptx_fixture.py's copies of its fixtures, byte for byte:
// the expected design is one file, in the JSON the two apps exchange (this
// phone's), which the twin's test reaches through its Interchange.toIos.

import XCTest
@testable import Canvia

final class PptxReaderTests: XCTestCase {

    /// Ids as both phones' tests make them: the prefix and a count.
    private func counter() -> (String) -> String {
        var n = 0
        return { prefix in
            n += 1
            return "\(prefix)-\(n)"
        }
    }

    private func read(_ data: Data, title: String = "Deck") throws -> PptxReader.Imported {
        try XCTUnwrap(PptxReader.read(data, title: title, now: 0, ids: counter()), "not read as a deck")
    }

    /// A ZIP of `files`, stored, as the PowerPoint export writes one.
    private func archive(_ files: [(String, Data)]) throws -> Data {
        var out = Data()
        let writer = ZipWriter { out.append($0) }
        for (name, data) in files { try writer.add(name, data) }
        try writer.finish()
        return out
    }

    private let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
        + "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""

    private func rels(_ rows: [(String, String)]) -> String {
        let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        let entries = rows.enumerated().map { k, row in
            "<Relationship Id=\"rId\(k + 1)\" Type=\"\(base)\(row.0)\" Target=\"\(row.1)\"/>"
        }
        return "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + entries.joined() + "</Relationships>"
    }

    /// A deck of `slides` — each its spTree's insides — 1280 × 720, with no
    /// master, layout or theme, and `extra` parts.
    private func deck(_ slides: [String], extra: [(String, String)] = [], slideRels: [Int: String] = [:],
                      media: [(String, Data)] = []) throws -> Data {
        var files: [(String, Data)] = []
        files.append(("_rels/.rels", Data(rels([("officeDocument", "ppt/presentation.xml")]).utf8)))
        let ids = slides.indices.map { "<p:sldId id=\"\(256 + $0)\" r:id=\"rId\($0 + 1)\"/>" }.joined()
        let presentation = "<p:presentation \(ns)><p:sldIdLst>\(ids)</p:sldIdLst>"
            + "<p:sldSz cx=\"12192000\" cy=\"6858000\"/></p:presentation>"
        files.append(("ppt/presentation.xml", Data(presentation.utf8)))
        let listed = slides.indices.map { ("slide", "slides/slide\($0 + 1).xml") }
        var parts: [String: String] = ["ppt/_rels/presentation.xml.rels": rels(listed)]
        for (k, tree) in slides.enumerated() {
            parts["ppt/slides/slide\(k + 1).xml"] = "<p:sld \(ns)><p:cSld><p:spTree>\(tree)</p:spTree></p:cSld></p:sld>"
            if let own = slideRels[k] { parts["ppt/slides/_rels/slide\(k + 1).xml.rels"] = own }
        }
        for (name, text) in extra { parts[name] = text }
        for (name, text) in parts.sorted(by: { $0.key < $1.key }) { files.append((name, Data(text.utf8))) }
        return try archive(files + media)
    }

    private func textBox(_ xfrm: String, _ body: String,
                         bodyPr: String = "<a:bodyPr lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"/>") -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"t\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr>\(xfrm)</p:spPr>"
            + "<p:txBody>\(bodyPr)<a:lstStyle/>\(body)</p:txBody></p:sp>"
    }

    private let box = "<a:xfrm><a:off x=\"952500\" y=\"952500\"/><a:ext cx=\"3810000\" cy=\"952500\"/></a:xfrm>"

    private func only(_ data: Data) throws -> Element {
        let elements = try read(data).design.pages[0].elements
        XCTAssertEqual(elements.count, 1)
        return try XCTUnwrap(elements.first)
    }

    // MARK: the file

    func testAZipOfDeflatedPartsIsReadWhenAsked() throws {
        let fixture = try loadFixture("deck", "pptx")
        // A backup is never read deflated…
        XCTAssertThrowsError(try ZipStore.Reader(data: fixture))
        // …a deck is, each part inflated to its own size.
        let reader = try ZipStore.Reader(data: fixture, inflating: true)
        let presentation = try XCTUnwrap(reader.file("ppt/presentation.xml"))
        XCTAssertEqual(reader.size(of: "ppt/presentation.xml"), presentation.count)
        XCTAssertTrue(String(decoding: presentation, as: UTF8.self).contains("<p:sldSz cx=\"12192000\" cy=\"6858000\"/>"))
        XCTAssertNil(reader.file("ppt/missing.xml"))
        XCTAssertNil(ZipStore.inflate(Data([1, 2, 3]), size: 10), "not deflate")
    }

    // MARK: numbers (shared rows)

    /// Shared: EMU ÷ 9525 page pixels, hundredths of a point ÷ 75 pixels,
    /// 60000ths of a degree, none of them rounded.
    func testLengthsTypeAndTurnsAreReadAsTheWriterWritesThem() throws {
        let t = try only(deck([textBox(
            "<a:xfrm rot=\"2700000\"><a:off x=\"100000\" y=\"9525\"/><a:ext cx=\"914400\" cy=\"476250\"/></a:xfrm>",
            "<a:p><a:r><a:rPr sz=\"2400\"/><a:t>Hi</a:t></a:r></a:p>")]))
        XCTAssertEqual(t.x, 100000 / 9525.0)
        XCTAssertEqual(t.y, 1)
        XCTAssertEqual(t.w, 96)
        XCTAssertEqual(t.h, 50)
        XCTAssertEqual(t.rotation, 45)
        XCTAssertEqual(t.fontSize, 32)
        let design = try read(deck([textBox(box, "<a:p><a:r><a:t>x</a:t></a:r></a:p>")])).design
        XCTAssertEqual(design.width, 1280)
        XCTAssertEqual(design.height, 720)
    }

    /// Shared: what the sheet says after an import.
    func testTheSummarySaysTheSlidesAndWhatWasLeftOutKindByKind() {
        let rows: [(Int, [String: Int], String)] = [
            (12, [PptxReader.chart: 2, PptxReader.smartArt: 1],
             "Imported 12 slides. 3 items couldn't be brought in (2 charts, 1 SmartArt)."),
            (1, [:], "Imported 1 slide."),
            (3, [PptxReader.font: 1], "Imported 3 slides. 1 item couldn't be brought in (1 font)."),
            (2, [PptxReader.other: 2, PptxReader.video: 1, PptxReader.sound: 2, PptxReader.picture: 1,
                 PptxReader.shape: 3, PptxReader.smartArt: 2],
             "Imported 2 slides. 11 items couldn't be brought in (2 SmartArt, 1 video, 2 sounds, 1 picture, 3 shapes, 2 other items)."),
            (5, [PptxReader.chart: 0], "Imported 5 slides."),
            (4, [PptxReader.other: 1], "Imported 4 slides. 1 item couldn't be brought in (1 other item)."),
        ]
        for (slides, skipped, said) in rows {
            XCTAssertEqual(PptxReader.summary(slides: slides, skipped: skipped), said)
        }
    }

    /// Shared: the file's name, without its extension, is the design's.
    func testTheDesignIsNamedByItsFile() {
        let rows: [(String?, String)] = [
            ("Quarterly review.pptx", "Quarterly review"),
            ("Deck.PPTX", "Deck"),
            ("notes.pptx.pptx", "notes.pptx"),
            ("Pitch", "Pitch"),
            ("  .pptx", "Untitled design"),
            (nil, "Untitled design"),
            ("folder/Plan.pptx", "Plan"),
        ]
        for (name, title) in rows {
            XCTAssertEqual(PptxReader.title(fromFile: name), title, "\(name ?? "nil")")
        }
    }

    /// Shared: a typeface is a bundled family only by its name or id.
    func testATypefaceIsTheBundledFamilyOfItsNameElseNone() {
        let rows: [(String?, String?)] = [
            ("Lora", "lora"),
            ("Playfair Display", "playfair-display"),
            ("playfair-display", "playfair-display"),
            ("PlayfairDisplay", "playfair-display"),
            ("  OPEN SANS ", "open-sans"),
            ("Modern Sans", "sans"),
            ("Typewriter", "mono"),
            ("Calibri", nil),
            ("Comic Sans MS", nil),
            ("", nil),
            (nil, nil),
        ]
        for (face, family) in rows {
            XCTAssertEqual(PptxReader.family(of: face), family, "\(face ?? "nil")")
        }
    }

    // MARK: words

    func testRunsBecomeOneBoxTheFirstRunsLookMarkersForStylesSpansForTheirOwn() throws {
        let body = "<a:p><a:pPr algn=\"r\"/><a:r><a:rPr sz=\"3000\"><a:solidFill><a:srgbClr val=\"112233\"/></a:solidFill>"
            + "<a:latin typeface=\"Lora\"/></a:rPr><a:t>Big </a:t></a:r>"
            + "<a:r><a:rPr sz=\"3000\" b=\"1\"><a:solidFill><a:srgbClr val=\"112233\"/></a:solidFill>"
            + "<a:latin typeface=\"Lora\"/></a:rPr><a:t>sale</a:t></a:r></a:p>"
            + "<a:p><a:r><a:rPr sz=\"1500\" i=\"1\"><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill>"
            + "<a:latin typeface=\"Anton\"/></a:rPr><a:t>today only</a:t></a:r></a:p>"
        let t = try only(deck([textBox(box, body)]))
        XCTAssertEqual(t.text, "Big **sale**\n*today only*")
        XCTAssertEqual(t.fontSize, 40)
        XCTAssertEqual(t.color, "#112233")
        XCTAssertEqual(t.fontFamily, "lora")
        XCTAssertEqual(t.align, "right")
        XCTAssertEqual(t.fontWeight, 400)
        XCTAssertNil(t.italic)
        XCTAssertNil(t.effect, "no effect key, as on the Android twin")
        XCTAssertEqual(t.spans, [TextSpan(start: 9, end: 19, color: "#ff0000", scale: 0.5, font: "anton")])
        XCTAssertEqual(t.spansText, "Big sale\ntoday only")
    }

    /// Shared: a run's cut ("Montserrat Light") is its words' own weight,
    /// and a bold or italic run the markers cannot keep apart from the
    /// words' own stars is their own weight and slant instead.
    func testARunsCutAndTheStylesTheMarkersCannotKeepGoToTheSpans() throws {
        let body = "<a:p><a:r><a:rPr><a:latin typeface=\"Montserrat\"/></a:rPr><a:t>Big </a:t></a:r>"
            + "<a:r><a:rPr b=\"1\" i=\"1\"><a:latin typeface=\"Montserrat Semibold\"/></a:rPr><a:t>sale</a:t></a:r>"
            + "<a:r><a:rPr><a:latin typeface=\"Montserrat Light\"/></a:rPr><a:t> now</a:t></a:r></a:p>"
        let t = try only(deck([textBox(box, body)]))
        // The cut's b="1" is its weight, not a ** that would draw it bolder.
        XCTAssertEqual(t.text, "Big *sale* now")
        XCTAssertEqual(t.fontFamily, "montserrat")
        XCTAssertEqual(t.spans, [TextSpan(start: 4, end: 8, weight: 600), TextSpan(start: 8, end: 12, weight: 300)])
        XCTAssertEqual(PptxReader.cut("Montserrat Light").map { "\($0.family) \($0.weight)" }, "montserrat 300")
        XCTAssertEqual(PptxReader.cut("Lora Bold").map { "\($0.family) \($0.weight)" }, "lora 700")
        XCTAssertEqual(PptxReader.cut("Lora 350").map { "\($0.family) \($0.weight)" }, "lora 350")
        XCTAssertEqual(PptxReader.cut("Montserrat Extra bold").map { "\($0.family) \($0.weight)" }, "montserrat 800")
        XCTAssertNil(PptxReader.cut("Lora"))
        XCTAssertNil(PptxReader.cut("Comic Sans MS Bold"))
        let stars = try only(deck([textBox(box, "<a:p><a:r><a:rPr/><a:t>2*3 is </a:t></a:r><a:r><a:rPr b=\"1\" i=\"1\"/><a:t>6*</a:t></a:r></a:p>")]))
        // The deck's own stars escaped, the markers keep the bold italic.
        XCTAssertEqual(stars.text, "2\\*3 is ***6\\****")
        XCTAssertEqual(RichText.strip(stars.text ?? ""), "2*3 is 6*")
        XCTAssertEqual(RichText.parse(stars.text ?? "").runs.map(\.style), [RichText.Style(bold: true, italic: true)])
        XCTAssertNil(stars.spans)
    }

    /// Shared: what the writer's styled text reads back as — a round trip
    /// keeps the styling.
    func testStyledRunsComeBackAsEffectsACurveAndAColumn() async throws {
        func styledBox(_ rPr: String, bodyPr: String = "<a:bodyPr/>") throws -> Element {
            try only(deck([textBox(box, "<a:p><a:r>\(rPr)<a:t>Hi</a:t></a:r></a:p>", bodyPr: bodyPr)]))
        }
        let ink = "<a:solidFill><a:srgbClr val=\"1F2430\"/></a:solidFill>"
        let shadow = try styledBox("<a:rPr sz=\"3150\">\(ink)<a:effectLst><a:outerShdw blurRad=\"48006\" dist=\"33945\" dir=\"2700000\" algn=\"ctr\">"
                                   + "<a:srgbClr val=\"000000\"><a:alpha val=\"55000\"/></a:srgbClr></a:outerShdw></a:effectLst></a:rPr>")
        XCTAssertEqual(shadow.effect?.type, "shadow")
        XCTAssertEqual(TextEffect.value(shadow.effect, .offset, for: .shadow), 50, accuracy: 0.5)
        XCTAssertEqual(TextEffect.value(shadow.effect, .direction, for: .shadow), 45, accuracy: 0.01)
        XCTAssertEqual(TextEffect.value(shadow.effect, .blur, for: .shadow), 50, accuracy: 0.5)
        XCTAssertEqual(TextEffect.value(shadow.effect, .transparency, for: .shadow), 45, accuracy: 0.01)
        // Its colour comes without the alpha, so a default shadow reads back as the default.
        XCTAssertNil(shadow.effect?.color)
        XCTAssertEqual(shadow.effect, TextEffectSpec(type: "shadow"))
        let glow = try styledBox("<a:rPr sz=\"3150\">\(ink)<a:effectLst><a:glow rad=\"140018\"><a:srgbClr val=\"1F2430\"><a:alpha val=\"85000\"/></a:srgbClr></a:glow></a:effectLst></a:rPr>")
        XCTAssertEqual(glow.effect?.type, "neon")
        XCTAssertEqual(TextEffect.value(glow.effect, .intensity, for: .neon), 50, accuracy: 0.5)
        let hollow = try styledBox("<a:rPr sz=\"3150\"><a:ln w=\"23813\">\(ink)</a:ln><a:noFill/></a:rPr>")
        XCTAssertEqual(hollow.effect?.type, "outline")
        XCTAssertEqual(TextEffect.value(hollow.effect, .thickness, for: .outline), 50, accuracy: 0.5)
        let outlined = try styledBox("<a:rPr sz=\"3150\"><a:ln w=\"16002\"><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></a:ln>\(ink)</a:rPr>")
        XCTAssertEqual(outlined.effect, TextEffectSpec(type: "outlined", color: "#ff0000"))
        let lit = try styledBox("<a:rPr sz=\"3150\">\(ink)<a:highlight><a:srgbClr val=\"FFE066\"><a:alpha val=\"60000\"/></a:srgbClr></a:highlight></a:rPr>")
        XCTAssertEqual(lit.effect, TextEffectSpec(type: "highlight", color: "#ffe066"))
        let arched = try styledBox("<a:rPr/>", bodyPr: "<a:bodyPr><a:prstTxWarp prst=\"textArchUp\"><a:avLst><a:gd name=\"adj\" fmla=\"val 5400000\"/></a:avLst></a:prstTxWarp></a:bodyPr>")
        XCTAssertEqual(arched.curve, 90)
        let valley = try styledBox("<a:rPr/>", bodyPr: "<a:bodyPr><a:prstTxWarp prst=\"textArchDown\"><a:avLst><a:gd name=\"adj\" fmla=\"val 3600000\"/></a:avLst></a:prstTxWarp></a:bodyPr>")
        XCTAssertEqual(valley.curve, -60)
        XCTAssertEqual(try styledBox("<a:rPr/>", bodyPr: "<a:bodyPr vert=\"eaVert\"/>").vertical, true)
        XCTAssertNil(try styledBox("<a:rPr/>").effect)
        let poured = try styledBox("<a:rPr sz=\"3150\"><a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"000000\"/></a:gs>"
                                   + "<a:gs pos=\"100000\"><a:srgbClr val=\"FFFFFF\"/></a:gs></a:gsLst><a:lin ang=\"0\"/></a:gradFill></a:rPr>")
        XCTAssertEqual(poured.textFill?.kind, "gradient")
        XCTAssertEqual(poured.textFill?.angle, 90)
        XCTAssertEqual(poured.textFill?.stops?.map(\.color), ["#000000", "#ffffff"])
        // A round trip through the writer keeps the styling.
        var styled = Element.text("Glow", fontSize: 42, w: 300)
        styled.id = "t"
        styled.x = 10; styled.y = 10; styled.h = 60
        styled.effect = TextEffectSpec(type: "neon")
        styled.curve = 40
        var design = Design(title: "Deck", width: 800, height: 600)
        design.pages = [Page(id: "p", elements: [styled])]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("styled-\(UUID().uuidString).pptx")
        defer { try? FileManager.default.removeItem(at: url) }
        try await PptxExporter.export(design: design, range: .all, to: url)
        let back = try read(try Data(contentsOf: url)).design.pages[0].elements
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back.first?.effect, TextEffectSpec(type: "neon"))
        XCTAssertEqual(back.first?.curve, 40)
    }

    func testAStyleEveryRunHasIsTheBoxsOwn() throws {
        let body = "<a:p><a:r><a:rPr b=\"1\" u=\"sng\"/><a:t>All </a:t></a:r><a:r><a:rPr b=\"1\" i=\"1\" u=\"sng\"/>"
            + "<a:t>bold</a:t></a:r><a:r><a:rPr/><a:t> </a:t></a:r></a:p>"
        let t = try only(deck([textBox(box, body)]))
        XCTAssertEqual(t.text, "All *bold* ")
        XCTAssertEqual(t.fontWeight, 700)
        XCTAssertEqual(t.underline, true)
        XCTAssertNil(t.italic)
        // 18 pt, black, Modern Sans and left when nothing says otherwise.
        XCTAssertEqual(t.fontSize, 24)
        XCTAssertEqual(t.color, "#000000")
        XCTAssertEqual(t.fontFamily, "sans")
        XCTAssertEqual(t.align, "left")
    }

    func testWordsWhoseStarsTheMarkersCannotKeepApartGoInPlain() throws {
        let t = try only(deck([textBox(box, "<a:p><a:r><a:rPr/><a:t>2*3 is </a:t></a:r><a:r><a:rPr b=\"1\"/><a:t>6*</a:t></a:r></a:p>")]))
        XCTAssertEqual(RichText.strip(t.text ?? ""), "2*3 is 6*")
    }

    /// Shared: a deck's own stars, lines, tildes and backslashes are
    /// escaped, so the box reads exactly as the deck does.
    func testADecksOwnStarsLinesAndTildesStayAsTheyRead() throws {
        let rows: [(String, String)] = [
            ("Press *Enter* to continue", "Press \\*Enter\\* to continue"),
            ("call __init__ first", "call \\_\\_init\\_\\_ first"),
            ("~~old~~ price", "\\~\\~old\\~\\~ price"),
            ("C:\\temp", "C:\\\\temp"),
        ]
        for (plain, kept) in rows {
            let t = try only(deck([textBox(box, "<a:p><a:r><a:rPr/><a:t>\(plain)</a:t></a:r></a:p>")]))
            XCTAssertEqual(t.text, kept, plain)
            XCTAssertEqual(RichText.strip(t.text ?? ""), plain, plain)
        }
    }

    /// Shared: a box with a deck's own stars keeps its runs' spans.
    func testABoxWithItsOwnStarsKeepsItsSpansAndStyles() throws {
        let body = "<a:p><a:r><a:rPr/><a:t>Press *Enter* </a:t></a:r><a:r><a:rPr b=\"1\"><a:solidFill>"
            + "<a:srgbClr val=\"FF0000\"/></a:solidFill></a:rPr><a:t>now</a:t></a:r></a:p>"
        let t = try only(deck([textBox(box, body)]))
        XCTAssertEqual(t.text, "Press \\*Enter\\* **now**")
        XCTAssertEqual(t.spans, [TextSpan(start: 14, end: 17, color: "#ff0000")])
    }

    func testTheBoxSitsInsideItsInsetsAndHoldsItsWordsWhereItIsAnchored() throws {
        let t = try only(deck(["<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"t\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>\(box)</p:spPr>"
            + "<p:txBody><a:bodyPr anchor=\"ctr\"/><a:p><a:r><a:t>Hi</a:t></a:r></a:p></p:txBody></p:sp>"]))
        // The default insets: 0.1 inch either side, 0.05 above and below.
        XCTAssertEqual(t.x, 109.6, accuracy: 1e-9)
        XCTAssertEqual(t.y, 104.8, accuracy: 1e-9)
        XCTAssertEqual(t.w, 400 - 19.2, accuracy: 1e-9)
        XCTAssertEqual(t.h, 100 - 9.6, accuracy: 1e-9)
        XCTAssertEqual(t.vAlign, "middle")
    }

    func testABoxWithNoWordsIsNone() throws {
        let first = textBox(box, "<a:p><a:endParaRPr/></a:p>") + textBox(box, "<a:p><a:r><a:t>  </a:t></a:r></a:p>")
        let design = try read(deck([first, textBox(box, "<a:p><a:r><a:t>x</a:t></a:r></a:p>")])).design
        XCTAssertTrue(design.pages[0].elements.isEmpty)
    }

    // MARK: shapes

    private func shape(_ geometry: String, _ fill: String, extra: String = "", xfrm: String? = nil) -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"s\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>\(xfrm ?? box)\(geometry)\(fill)\(extra)</p:spPr></p:sp>"
    }

    private func solid(_ hex: String) -> String { "<a:solidFill><a:srgbClr val=\"\(hex)\"/></a:solidFill>" }

    func testPresetRectanglesRoundedRectanglesOvalsAndTrianglesAreShapes() throws {
        let gradient = "<a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FFFFFF\"/></a:gs>"
            + "<a:gs pos=\"100000\"><a:srgbClr val=\"000000\"/></a:gs></a:gsLst><a:lin ang=\"5400000\"/></a:gradFill>"
        let tree = [
            shape("<a:prstGeom prst=\"rect\"/>",
                  "<a:solidFill><a:srgbClr val=\"ABCDEF\"><a:alpha val=\"50000\"/></a:srgbClr></a:solidFill>",
                  extra: "<a:ln w=\"19050\">\(solid("000000"))</a:ln>"),
            shape("<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val 25000\"/></a:avLst></a:prstGeom>", solid("00FF00")),
            shape("<a:prstGeom prst=\"ellipse\"/>", gradient),
            shape("<a:prstGeom prst=\"triangle\"/>", "<a:noFill/>", extra: "<a:ln>\(solid("FF0000"))</a:ln>"),
            shape("<a:prstGeom prst=\"roundRect\"/>", solid("00FF00")),
        ].joined()
        let els = try read(deck([tree])).design.pages[0].elements
        XCTAssertEqual(els.map(\.shapeId), ["rect", "rect", "circle", "triangle", "rect"])
        XCTAssertEqual(els[0].fill, .solid("#abcdef80"))
        XCTAssertEqual(els[0].stroke, "#000000")
        XCTAssertEqual(els[0].strokeWidth, 2)
        XCTAssertEqual(els[0].radius, 0)
        // The corner a quarter of the shorter side; PowerPoint's own when it
        // gives none.
        XCTAssertEqual(els[1].radius ?? 0, 25, accuracy: 1e-9)
        XCTAssertNil(els[1].stroke)
        XCTAssertEqual(els[4].radius ?? 0, 16.667, accuracy: 1e-9)
        // DrawingML's 90 degrees points down; the model's 180.
        XCTAssertEqual(els[2].fill?.kind, "gradient")
        XCTAssertEqual(els[2].fill?.angle, 180)
        XCTAssertEqual(els[2].fill?.stops?.map(\.color), ["#ffffff", "#000000"])
        XCTAssertEqual(els[3].fill, .clear)
        XCTAssertEqual(els[3].stroke, "#ff0000")
        XCTAssertEqual(els[3].strokeWidth, 1)
    }

    func testOtherOutlinesThatWouldShowAreLeftOutAndTheirWordsKept() throws {
        let star = "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"s\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>\(box)"
            + "<a:prstGeom prst=\"star5\"/>\(solid("FFC000"))</p:spPr>"
            + "<p:txBody><a:bodyPr/><a:p><a:r><a:t>Star</a:t></a:r></a:p></p:txBody></p:sp>"
        let imported = try read(deck([star + shape("<a:custGeom/>", "<a:noFill/>")]))
        XCTAssertEqual(imported.design.pages[0].elements.map(\.type), [.text])
        XCTAssertEqual(imported.skipped, [PptxReader.shape: 1])
    }

    /// Shared: a picture fill of an outline left out is not brought in — no
    /// file is kept for it — and the outline is counted once.
    func testAnOutlineLeftOutKeepsNoneOfItsPicture() throws {
        let tree = [
            shape("<a:prstGeom prst=\"star5\"/>", "<a:blipFill><a:blip r:embed=\"rId1\"/></a:blipFill>"),
            shape("<a:custGeom/>", "<a:blipFill><a:blip r:embed=\"rId9\"/></a:blipFill>"),
            shape("<a:prstGeom prst=\"rect\"/>", "<a:blipFill><a:blip r:embed=\"rId2\"/></a:blipFill>"),
        ].joined()
        let imported = try read(deck([tree],
                                     slideRels: [0: rels([("image", "../media/star.png"), ("image", "../media/kept.png")])],
                                     media: [("ppt/media/star.png", png), ("ppt/media/kept.png", png)]))
        XCTAssertEqual(imported.design.pages[0].elements.map(\.fill), [.image("media:kept.png")])
        XCTAssertEqual(imported.media, ["kept.png": "ppt/media/kept.png"])
        XCTAssertEqual(imported.skipped, [PptxReader.shape: 2])
    }

    /// Shared: words are never mirrored — a flipped box's words read as they
    /// are, turned over by flipV.
    func testFlippedWordsReadAsTheyAreTurnedOverWhenFlippedTopToBottom() throws {
        func arrow(_ flips: String, rot: String = "") -> String {
            "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"s\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>"
                + "<a:xfrm\(rot)\(flips)><a:off x=\"952500\" y=\"952500\"/><a:ext cx=\"3810000\" cy=\"952500\"/></a:xfrm>"
                + "<a:prstGeom prst=\"rightArrow\"/>\(solid("4472C4"))</p:spPr>"
                + "<p:txBody><a:bodyPr/><a:p><a:r><a:t>Back</a:t></a:r></a:p></p:txBody></p:sp>"
        }
        let tree = [arrow(" flipH=\"1\""), arrow(" flipV=\"1\""), arrow(" flipH=\"1\" flipV=\"1\"", rot: " rot=\"5400000\""), arrow("")]
        let els = try read(deck([tree.joined()])).design.pages[0].elements
        XCTAssertEqual(els.map(\.text), ["Back", "Back", "Back", "Back"])
        XCTAssertEqual(els.map(\.flipH), [false, false, false, false])
        XCTAssertEqual(els.map(\.flipV), [false, false, false, false])
        XCTAssertEqual(els.map(\.rotation), [0, 180, 270, 0])
    }

    func testALineRunsCornerToCornerOfItsBoxFlippedAsTheBoxIs() throws {
        let line = try only(deck(["<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"4\" name=\"l\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr>"
            + "<a:xfrm flipV=\"1\"><a:off x=\"0\" y=\"0\"/><a:ext cx=\"2857500\" cy=\"3810000\"/></a:xfrm>"
            + "<a:prstGeom prst=\"straightConnector1\"/><a:ln w=\"28575\">\(solid("3366FF"))<a:prstDash val=\"lgDash\"/></a:ln>"
            + "</p:spPr></p:cxnSp>"]))
        XCTAssertEqual(line.type, .line)
        // 300 across and 400 up from the bottom left: 500 long, at -53.13°.
        XCTAssertEqual(line.w, 500, accuracy: 1e-9)
        XCTAssertEqual(line.h, 8)
        XCTAssertEqual(line.x, 150 - 250, accuracy: 1e-9)
        XCTAssertEqual(line.y, 200 - 4, accuracy: 1e-9)
        XCTAssertEqual(line.rotation, 360 - atan2(400.0, 300.0) * 180 / .pi, accuracy: 1e-9)
        XCTAssertEqual(line.color, "#3366ff")
        XCTAssertEqual(line.thickness, 3)
        XCTAssertEqual(line.dash, "dashed")
        XCTAssertNil(line.startCap)
        XCTAssertNil(line.endCap)
    }

    func testTurnsAndFlipsAreTheShapesOwn() throws {
        let xfrm = "<a:xfrm rot=\"-5400000\" flipH=\"1\" flipV=\"true\"><a:off x=\"0\" y=\"0\"/><a:ext cx=\"9525\" cy=\"9525\"/></a:xfrm>"
        let s = try only(deck([shape("<a:prstGeom prst=\"rect\"/>", solid("000000"), xfrm: xfrm)]))
        XCTAssertEqual(s.rotation, 270)
        XCTAssertTrue(s.flipH)
        XCTAssertTrue(s.flipV)
    }

    func testAGroupsChildrenArePlacedByItsOwnBox() throws {
        let group = "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"5\" name=\"g\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr>"
            + "<a:xfrm><a:off x=\"952500\" y=\"952500\"/><a:ext cx=\"1905000\" cy=\"952500\"/>"
            + "<a:chOff x=\"9525000\" y=\"0\"/><a:chExt cx=\"952500\" cy=\"952500\"/></a:xfrm></p:grpSpPr>"
            + shape("<a:prstGeom prst=\"rect\"/>", solid("000000"),
                    xfrm: "<a:xfrm><a:off x=\"9620250\" y=\"95250\"/><a:ext cx=\"476250\" cy=\"476250\"/></a:xfrm>")
            + shape("<a:prstGeom prst=\"ellipse\"/>", solid("000000"),
                    xfrm: "<a:xfrm><a:off x=\"9525000\" y=\"0\"/><a:ext cx=\"952500\" cy=\"952500\"/></a:xfrm>")
            + "</p:grpSp>"
        let els = try read(deck([group])).design.pages[0].elements
        // Twice as wide as its children's box, as tall.
        XCTAssertEqual([els[0].x, els[0].y, els[0].w, els[0].h], [120, 110, 100, 50])
        XCTAssertEqual([els[1].x, els[1].y, els[1].w, els[1].h], [100, 100, 200, 100])
        XCTAssertEqual(els[0].group, "grp-3")
        XCTAssertEqual(els[0].group, els[1].group)
    }

    /// Shared: a group inside a group is a subgroup of the outer one's
    /// members (Groups), its id made as it is met.
    func testAGroupInsideAGroupIsASubgroup() throws {
        let plain = "<p:grpSpPr/>"
        let square = shape("<a:prstGeom prst=\"rect\"/>", solid("000000"),
                           xfrm: "<a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"952500\" cy=\"952500\"/></a:xfrm>")
        let tree = "<p:grpSp>" + plain + "<p:grpSp>" + plain + square + square + "</p:grpSp>" + square + "</p:grpSp>" + square
        let els = try read(deck([tree])).design.pages[0].elements
        XCTAssertEqual(els.count, 4)
        XCTAssertEqual(els.map(\.group), ["grp-3", "grp-3", "grp-3", nil])
        XCTAssertEqual(els.map(\.subgroups), [["grp-4"], ["grp-4"], nil, nil])
    }

    // MARK: pictures and backgrounds

    private let png = Data([0x89, 0x50, 0x4e, 0x47])

    private func pic(_ embed: String, nvPr: String = "<p:nvPr/>") -> String {
        "<p:pic><p:nvPicPr><p:cNvPr id=\"6\" name=\"p\"/><p:cNvPicPr/>\(nvPr)</p:nvPicPr><p:blipFill><a:blip r:embed=\"\(embed)\"/></p:blipFill>"
            + "<p:spPr><a:xfrm rot=\"1800000\" flipH=\"1\"><a:off x=\"952500\" y=\"0\"/><a:ext cx=\"952500\" cy=\"476250\"/></a:xfrm></p:spPr></p:pic>"
    }

    func testAPictureIsAPhotoOfItsMediaEachFileOnce() throws {
        let own = rels([("slideLayout", "../slideLayouts/none.xml"), ("image", "../media/image1.png"),
                        ("image", "../media/image2.emf"), ("image", "/ppt/media/IMAGE1.PNG")])
        let imported = try read(deck([pic("rId2") + pic("rId3") + pic("rId2") + pic("rId4") + pic("rId9")],
                                     slideRels: [0: own],
                                     media: [("ppt/media/image1.png", png), ("ppt/media/image2.emf", png)]))
        let els = imported.design.pages[0].elements
        XCTAssertEqual(els.map(\.src), ["media:image1.png", "media:image1.png", "media:image1.png"])
        XCTAssertEqual(imported.media, ["image1.png": "ppt/media/image1.png"])
        XCTAssertEqual([els[0].x, els[0].y, els[0].w, els[0].h, els[0].rotation], [100, 0, 100, 50, 30])
        XCTAssertTrue(els[0].flipH)
        XCTAssertNil(els[0].filter, "no filter key, as on the Android twin")
        // An EMF, and a picture with no file.
        XCTAssertEqual(imported.skipped, [PptxReader.picture: 2])
    }

    func testVideosAndSoundsAreLeftOut() throws {
        let imported = try read(deck([pic("rId1", nvPr: "<p:nvPr><a:videoFile r:link=\"rId2\"/></p:nvPr>")
                                      + pic("rId1", nvPr: "<p:nvPr><a:audioFile r:link=\"rId2\"/></p:nvPr>")],
                                     slideRels: [0: rels([("image", "../media/image1.png")])],
                                     media: [("ppt/media/image1.png", png)]))
        XCTAssertTrue(imported.design.pages[0].elements.isEmpty)
        XCTAssertTrue(imported.media.isEmpty)
        XCTAssertEqual(imported.skipped, [PptxReader.video: 1, PptxReader.sound: 1])
    }

    func testPlacedPicturesPointWhereTheyWereStoredAndThoseThatWereNotAreLeftOut() throws {
        let imported = try read(deck([pic("rId1") + pic("rId2")],
                                     slideRels: [0: rels([("image", "../media/a.png"), ("image", "../media/b.jpeg")])],
                                     media: [("ppt/media/a.png", png), ("ppt/media/b.jpeg", png)]))
        let placed = PptxReader.placed(imported, stored: ["a.png": "media:img-1"])
        XCTAssertEqual(placed.design.pages[0].elements.map(\.src), ["media:img-1"])
        XCTAssertEqual(placed.skipped, [PptxReader.picture: 1])
        var behind = Design()
        behind.pages = [Page(background: .image("media:a.png"))]
        let gone = PptxReader.placed(PptxReader.Imported(design: behind, media: ["a.png": "ppt/media/a.png"], skipped: [:]),
                                     stored: [:])
        XCTAssertEqual(gone.design.pages[0].background, .color("#ffffff"))
        XCTAssertEqual(gone.skipped, [PptxReader.picture: 1])
    }

    func testABackgroundIsTheSlidesElseItsLayoutsElseItsMasters() throws {
        func bytes(_ slideBg: String, _ layoutBg: String, _ masterBg: String) throws -> Data {
            try deck([""], extra: [
                ("ppt/slides/slide1.xml", "<p:sld \(ns)><p:cSld>\(slideBg)<p:spTree/></p:cSld></p:sld>"),
                ("ppt/slideLayouts/slideLayout1.xml", "<p:sldLayout \(ns)><p:cSld>\(layoutBg)<p:spTree/></p:cSld></p:sldLayout>"),
                ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels([("slideMaster", "../slideMasters/slideMaster1.xml")])),
                ("ppt/slideMasters/slideMaster1.xml", "<p:sldMaster \(ns)><p:cSld>\(masterBg)<p:spTree/></p:cSld></p:sldMaster>"),
            ], slideRels: [0: rels([("slideLayout", "../slideLayouts/slideLayout1.xml")])])
        }
        func bg(_ hex: String) -> String { "<p:bg><p:bgPr>\(solid(hex))</p:bgPr></p:bg>" }
        func background(_ data: Data) throws -> Background { try read(data).design.pages[0].background }
        XCTAssertEqual(try background(bytes(bg("111111"), bg("222222"), bg("333333"))), .color("#111111"))
        XCTAssertEqual(try background(bytes("", bg("222222"), bg("333333"))), .color("#222222"))
        XCTAssertEqual(try background(bytes("", "", bg("333333"))), .color("#333333"))
        XCTAssertEqual(try background(bytes("", "", "")), .color("#ffffff"))
        XCTAssertEqual(try background(bytes("<p:bg><p:bgPr><a:noFill/></p:bgPr></p:bg>", "", bg("333333"))), .color("#ffffff"))
    }

    // MARK: frames

    private func frame(_ uri: String, _ inner: String = "") -> String {
        "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"7\" name=\"f\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>"
            + "<p:xfrm><a:off x=\"952500\" y=\"952500\"/><a:ext cx=\"2857500\" cy=\"952500\"/></p:xfrm>"
            + "<a:graphic><a:graphicData uri=\"\(uri)\">\(inner)</a:graphicData></a:graphic></p:graphicFrame>"
    }

    func testChartsSmartArtAndOtherFramesAreLeftOutAndCounted() throws {
        let tree = frame("http://schemas.openxmlformats.org/drawingml/2006/chart")
            + frame("http://schemas.microsoft.com/office/drawing/2014/chartex")
            + frame("http://schemas.openxmlformats.org/drawingml/2006/diagram")
            + frame("http://schemas.openxmlformats.org/presentationml/2006/ole")
            + "<p:contentPart r:id=\"rId1\"/>"
        let imported = try read(deck([tree]))
        XCTAssertTrue(imported.design.pages[0].elements.isEmpty)
        XCTAssertEqual(imported.skipped, [PptxReader.chart: 2, PptxReader.smartArt: 1, PptxReader.other: 2])
        XCTAssertEqual(imported.summary,
                       "Imported 1 slide. 5 items couldn't be brought in (2 charts, 1 SmartArt, 2 other items).")
    }

    func testATableIsARectangleAndATextACellItsMergesSpans() throws {
        func tc(_ words: String, _ attrs: String = "") -> String {
            let run = words.isEmpty ? "" : "<a:r><a:rPr sz=\"1500\"/><a:t>\(words)</a:t></a:r>"
            return "<a:tc\(attrs)><a:txBody><a:bodyPr/><a:p>\(run)</a:p></a:txBody><a:tcPr/></a:tc>"
        }
        let tbl = "<a:tbl><a:tblGrid><a:gridCol w=\"952500\"/><a:gridCol w=\"952500\"/><a:gridCol w=\"952500\"/></a:tblGrid>"
            + "<a:tr h=\"476250\">\(tc("A", " gridSpan=\"2\""))\(tc("", " hMerge=\"1\""))\(tc("C", " rowSpan=\"2\""))</a:tr>"
            + "<a:tr h=\"476250\">\(tc("D"))\(tc("E"))\(tc("", " vMerge=\"1\""))</a:tr></a:tbl>"
        let els = try read(deck([frame("http://schemas.openxmlformats.org/drawingml/2006/table", tbl)])).design.pages[0].elements
        let cells = els.compactMap(\.table)
        XCTAssertEqual(cells.count, els.count)
        XCTAssertEqual(els.map(\.type), [.shape, .shape, .text, .text, .shape, .shape, .text, .text])
        XCTAssertEqual(cells.map { [$0.row, $0.col] }, [[0, 0], [0, 2], [0, 0], [0, 2], [1, 0], [1, 1], [1, 0], [1, 1]])
        XCTAssertEqual(cells[0], TableCell(id: "tbl-4", row: 0, col: 0, rowSpan: 1, colSpan: 2))
        XCTAssertEqual(cells[1], TableCell(id: "tbl-4", row: 0, col: 2, rowSpan: 2, colSpan: 1))
        XCTAssertEqual([els[0].x, els[0].y, els[0].w, els[0].h], [100, 100, 200, 50])
        XCTAssertEqual([els[1].x, els[1].y, els[1].w, els[1].h], [300, 100, 100, 100])
        XCTAssertEqual(els.filter { $0.type == .text }.map(\.text), ["A", "C", "D", "E"])
        // Inside the cell's margins, in its own size.
        XCTAssertEqual(els[2].x, 109.6, accuracy: 1e-9)
        XCTAssertEqual(els[2].y, 104.8, accuracy: 1e-9)
        XCTAssertEqual(els[2].fontSize, 20)
        XCTAssertEqual(Set(els.map(\.group)), ["grp-3"])
        XCTAssertEqual(els[0].fill, .solid("#ffffff"))
        XCTAssertEqual(els[0].stroke, PptxReader.tableBorder)
        XCTAssertEqual(els[0].shapeId, "rect")
    }

    /// Shared: a cell's picture fill is not brought in — no file is kept for
    /// it — and is a picture left out, the cell white.
    func testATableCellsPictureIsLeftOutAndKeepsNoFile() throws {
        let tbl = "<a:tbl><a:tblGrid><a:gridCol w=\"952500\"/></a:tblGrid><a:tr h=\"476250\"><a:tc><a:txBody><a:bodyPr/>"
            + "<a:p><a:r><a:t>A</a:t></a:r></a:p></a:txBody>"
            + "<a:tcPr><a:blipFill><a:blip r:embed=\"rId1\"/></a:blipFill></a:tcPr></a:tc></a:tr></a:tbl>"
        let imported = try read(deck([frame("http://schemas.openxmlformats.org/drawingml/2006/table", tbl)],
                                     slideRels: [0: rels([("image", "../media/cell.png")])],
                                     media: [("ppt/media/cell.png", png)]))
        XCTAssertEqual(imported.design.pages[0].elements.first?.fill, .solid("#ffffff"))
        XCTAssertTrue(imported.media.isEmpty)
        XCTAssertEqual(imported.skipped, [PptxReader.picture: 1])
    }

    // MARK: notes, titles and order

    func testSlidesComeInTheListsOrderWithTheirNotesAndTitles() throws {
        let title = "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"t\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"title\"/></p:nvPr></p:nvSpPr>"
            + "<p:spPr>\(box)</p:spPr><p:txBody><a:bodyPr/><a:p><a:r><a:t>Second</a:t></a:r><a:br/>"
            + "<a:r><a:t> slide </a:t></a:r></a:p></p:txBody></p:sp>"
        let notes = "<p:notes \(ns)><p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"n\"/><p:cNvSpPr/>"
            + "<p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/>"
            + "<a:p><a:r><a:t>Line one</a:t></a:r></a:p><a:p/><a:p><a:r><a:t>Line </a:t></a:r><a:r><a:t>three</a:t></a:r></a:p>"
            + "</p:txBody></p:sp></p:spTree></p:cSld></p:notes>"
        let bytes = try deck([textBox(box, "<a:p><a:r><a:t>First</a:t></a:r></a:p>"), title], extra: [
            // The second slide listed first.
            ("ppt/_rels/presentation.xml.rels", rels([("slide", "slides/slide2.xml"), ("slide", "slides/slide1.xml")])),
            ("ppt/notesSlides/notesSlide1.xml", notes),
        ], slideRels: [1: rels([("notesSlide", "../notesSlides/notesSlide1.xml")])])
        let design = try read(bytes, title: "Plan").design
        XCTAssertEqual(design.title, "Plan")
        XCTAssertFalse(design.titleAuto)
        XCTAssertEqual(design.pages.map(\.id), ["page-2", "page-4"])
        XCTAssertEqual(design.pages[0].title, "Second slide")
        XCTAssertEqual(design.pages[0].elements.first?.text, "Second\n slide ")
        XCTAssertEqual(design.pages[0].notes, "Line one\n\nLine three")
        XCTAssertNil(design.pages[1].title)
        XCTAssertNil(design.pages[1].notes)
    }

    /// Shared: a title is split on ASCII white space only and joined with
    /// one space; a no-break space, as French puts before "!", stays.
    func testATitleKeepsItsNoBreakSpaces() throws {
        func titled(_ words: String) -> String {
            "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"t\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"title\"/></p:nvPr></p:nvSpPr>"
                + "<p:spPr>\(box)</p:spPr><p:txBody><a:bodyPr/><a:p><a:r><a:t>\(words)</a:t></a:r></a:p></p:txBody></p:sp>"
        }
        let rows: [(String, String)] = [
            ("Merci\u{00A0}!", "Merci\u{00A0}!"),
            (" Merci \t\u{00A0}! \u{2028} encore ", "Merci \u{00A0}! \u{2028} encore"),
        ]
        for (words, title) in rows {
            XCTAssertEqual(try read(deck([titled(words)])).design.pages[0].title, title, words)
        }
    }

    /// Shared: groups within groups are read 64 deep; a deck one deeper is
    /// none, as on the Android twin.
    func testGroupsPastTheDeepestReadAreNotADeck() throws {
        func nested(_ depth: Int) throws -> Data {
            let inner = textBox(box, "<a:p><a:r><a:t>Deep</a:t></a:r></a:p>")
            return try deck([String(repeating: "<p:grpSp><p:grpSpPr/>", count: depth) + inner
                + String(repeating: "</p:grpSp>", count: depth)])
        }
        XCTAssertEqual(PptxReader.maxDepth, 64)
        XCTAssertEqual(try only(nested(PptxReader.maxDepth)).text, "Deep")
        XCTAssertNil(PptxReader.read(try nested(PptxReader.maxDepth + 1), title: "x", now: 0, ids: counter()))
    }

    func testAFileThatIsNotADeckOrHasNoSlidesIsNone() throws {
        XCTAssertNil(PptxReader.read(Data("not a zip".utf8), title: "x"))
        XCTAssertNil(PptxReader.read(try archive([("hello.txt", Data("hi".utf8))]), title: "x"))
        XCTAssertNil(PptxReader.read(try deck([]), title: "x"))
        XCTAssertTrue(PptxReader.isZip(try deck([""])))
        XCTAssertFalse(PptxReader.isZip(Data("{\"format\"".utf8)))
    }

    /// Shared: what Home and the import say, as on the Android twin.
    func testTheWordsAreTheAndroidTwins() {
        XCTAssertEqual(ImportChoice.powerPoint.title, "PowerPoint…")
        XCTAssertEqual(PptxReader.notADeck, "That file isn't a PowerPoint presentation.")
        XCTAssertEqual(PptxReader.tooBig, "That PowerPoint is too big to open.")
        XCTAssertEqual(PptxReader.mimeType, "application/vnd.openxmlformats-officedocument.presentationml.presentation")
        XCTAssertEqual(PptxReader.typeIdentifier, "org.openxmlformats.presentationml.presentation")
    }

    /// A deck is known by its name, or by its first bytes when it came with
    /// none: a design file is never a ZIP.
    func testADeckIsKnownByItsNameOrItsBytes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bare = folder.appendingPathComponent("shared.bin")
        try deck([""]).write(to: bare)
        let design = folder.appendingPathComponent("Poster.canvia.json")
        try Data("{\"format\":\"canvia\"}".utf8).write(to: design)
        XCTAssertTrue(PowerPoints.isDeck(bare))
        XCTAssertTrue(PowerPoints.isDeck(folder.appendingPathComponent("Missing.PPTX")))
        XCTAssertFalse(PowerPoints.isDeck(design))
    }

    // MARK: the exporter's decks

    /// A deck as PptxExporter writes it, every picture three bytes.
    private func exported(_ design: Design) throws -> Data {
        let indices = Array(design.pages.indices)
        let slides = PptxExporter.deck(design: design, indices: indices)
        var files = PptxExporter.packageParts(design: design, noted: slides.map { $0.notes != nil })
            .map { ($0.name, Data($0.xml.utf8)) }
        for (n, slide) in slides.enumerated() {
            files += slide.media.map { ("ppt/media/\($0.name)", Data([1, 2, 3])) }
            files.append(("ppt/slides/slide\(n + 1).xml", Data(slide.xml.utf8)))
            files.append(("ppt/slides/_rels/slide\(n + 1).xml.rels", Data(slide.rels.utf8)))
            if let notes = slide.notes {
                files.append(("ppt/notesSlides/notesSlide\(n + 1).xml", Data(notes.utf8)))
                files.append(("ppt/notesSlides/_rels/notesSlide\(n + 1).xml.rels",
                              Data(PptxExporter.notesRels(slide: n + 1).utf8)))
            }
        }
        return try archive(files)
    }

    func testADeckTheExporterMadeReadsBackWithItsWordsPlacesAndNotes() throws {
        var hello = Element.text("Hello **world**", fontSize: 32, w: 400)
        hello.id = "t1"
        hello.x = 40.3; hello.y = 41.7; hello.h = 60
        hello.fontFamily = "lora"
        hello.align = "left"
        var rect = Element.shape("rect", w: 200, h: 100)
        rect.id = "r1"
        rect.x = 100; rect.y = 200
        rect.rotation = 45
        rect.fill = .solid("#ff0000")
        rect.stroke = "#000000"
        rect.strokeWidth = 2
        var oval = Element.shape("circle", w: 120, h: 80)
        oval.id = "o1"
        oval.x = 500; oval.y = 60
        var line = Element.line(w: 300)
        line.id = "l1"
        line.x = 50; line.y = 500
        line.rotation = 30
        var photo = Element.image("media:photo", w: 240, h: 180)
        photo.id = "i1"
        photo.x = 400; photo.y = 200
        var second = Element.text("Second\nslide", fontSize: 48)
        second.id = "t2"
        second.x = 10; second.y = 20
        second.color = "#2563eb"
        var design = Design(title: "Deck", width: 800, height: 600)
        design.pages = [
            Page(id: "p1", background: .color("#f4f4f6"), elements: [hello, rect, oval, line, photo],
                 notes: "  Say hello\n\nThen <go> & wave\n"),
            Page(id: "p2", elements: [second]),
        ]
        let imported = try read(exported(design))
        let back = imported.design
        XCTAssertEqual(back.width, 800)
        XCTAssertEqual(back.height, 600)
        XCTAssertEqual(back.pages.map(\.notes), design.pages.map(\.notes))
        XCTAssertEqual(back.pages[0].background, .color("#f4f4f6"))
        for (page, got) in zip(design.pages, back.pages) {
            XCTAssertEqual(got.elements.map(\.type), page.elements.map(\.type))
            for (a, b) in zip(page.elements, got.elements) {
                XCTAssertEqual(b.x, a.x, accuracy: 1, "\(a.id) x")
                XCTAssertEqual(b.y, a.y, accuracy: 1, "\(a.id) y")
                XCTAssertEqual(b.w, a.w, accuracy: 1, "\(a.id) w")
                XCTAssertEqual(b.h, a.h, accuracy: 1, "\(a.id) h")
                XCTAssertEqual(b.rotation, a.rotation, accuracy: 1e-3, "\(a.id) turn")
                XCTAssertEqual(b.text, a.text)
                if a.type == .text {
                    XCTAssertEqual(b.fontSize ?? 0, a.fontSize ?? 0, accuracy: 0.01)
                    XCTAssertEqual(b.color, a.color)
                    XCTAssertEqual(b.fontFamily, FontLibrary.resolve(a.fontFamily))
                }
            }
        }
        XCTAssertEqual(back.pages[0].elements[2].shapeId, "circle")
        XCTAssertEqual(back.pages[0].elements[4].src, "media:image1.png")
        XCTAssertEqual(imported.skipped.filter { $0.key != PptxReader.font }, [:])
    }

    func testNestedGroupsTheExporterWroteReadBackNested() throws {
        func square(_ id: String, x: Double, group: String?, subgroups: [String]? = nil) -> Element {
            var el = Element.shape("rect", w: 100, h: 100)
            el.id = id
            el.x = x
            el.y = 100
            el.group = group
            el.subgroups = subgroups
            return el
        }
        var design = Design(title: "Deck", width: 800, height: 600)
        design.pages = [Page(id: "p1", elements: [
            square("a", x: 0, group: "card", subgroups: ["logo"]), square("b", x: 120, group: "card", subgroups: ["logo"]),
            square("c", x: 240, group: "card"), square("d", x: 400, group: nil),
        ])]
        let back = try read(exported(design)).design.pages[0].elements
        XCTAssertEqual(back.count, 4)
        let chains = back.map(Groups.chain)
        XCTAssertEqual(chains[0].count, 2)
        XCTAssertEqual(chains[0], chains[1])
        XCTAssertEqual(chains[2], [chains[0][0]])
        XCTAssertEqual(chains[3], [])
        for (a, b) in zip(design.pages[0].elements, back) {
            XCTAssertEqual(b.x, a.x, accuracy: 1, "\(a.id) keeps its place")
            XCTAssertEqual(b.w, a.w, accuracy: 1)
        }
    }

    // MARK: the shared fixture

    /// A fixture's bytes: from the test bundle, or beside this file.
    private func loadFixture(_ name: String, _ ext: String, file: StaticString = #filePath) throws -> Data {
        if let url = Bundle(for: PptxReaderTests.self).url(forResource: name, withExtension: ext) {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).\(ext)"))
    }

    /// Where two JSON values differ, numbers within a billionth.
    private func differences(_ a: Any, _ b: Any, at path: String = "") -> [String] {
        if let x = a as? [String: Any], let y = b as? [String: Any] {
            let keys = Set(x.keys).union(y.keys).sorted()
            return keys.flatMap { key -> [String] in
                guard let left = x[key], let right = y[key] else { return ["\(path).\(key): only one has it"] }
                return differences(left, right, at: "\(path).\(key)")
            }
        }
        if let x = a as? [Any], let y = b as? [Any] {
            guard x.count == y.count else { return ["\(path): \(x.count) against \(y.count) items"] }
            return zip(x, y).enumerated().flatMap { differences($1.0, $1.1, at: "\(path)[\($0)]") }
        }
        if let x = a as? String, let y = b as? String {
            return x == y ? [] : ["\(path): \(x) against \(y)"]
        }
        if let x = a as? NSNumber, let y = b as? NSNumber {
            let p = x.doubleValue, q = y.doubleValue
            return abs(p - q) <= 1e-9 * max(1, abs(q)) ? [] : ["\(path): \(p) against \(q)"]
        }
        return ["\(path): \(a) against \(b)"]
    }

    /// Shared: Fixtures/deck.pptx is the design in Fixtures/deck.json on
    /// both phones.
    func testTheSharedDeckIsTheSharedDesign() throws {
        let imported = try read(loadFixture("deck", "pptx"))
        let actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(imported.design))
        let expected = try JSONSerialization.jsonObject(with: loadFixture("deck", "json"))
        let found = differences(actual, expected)
        XCTAssertTrue(found.isEmpty, found.joined(separator: "\n"))
        XCTAssertEqual(imported.summary,
                       "Imported 4 slides. 8 items couldn't be brought in (1 chart, 1 SmartArt, 1 video, 1 picture, 1 shape, 3 fonts).")
        XCTAssertEqual(imported.media, ["image1.png": "ppt/media/image1.png", "image2.png": "ppt/media/image2.png"])
    }
}
