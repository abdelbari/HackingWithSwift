// PowerPoint export: the units, what each element becomes, the slide XML
// for the shared fixture — character for character, the same vectors and
// rows the Android twin's PptxWriterTest holds — and the file itself: a ZIP
// whose entries come in the shared order, every one of them intact.

import XCTest
import CoreGraphics
@testable import Canvia

final class PptxExporterTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func destination() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(UUID().uuidString).pptx")
        written.append(url)
        return url
    }

    // MARK: fixtures

    /// The shared fixture: one text box, one rectangle, one photo, on a
    /// page with a colour behind it.
    private func fixture() -> Design {
        var text = Element.text("Hello **world**", fontSize: 32, w: 400)
        text.id = "text1"
        text.x = 40; text.y = 40; text.h = 60
        text.fontFamily = "lora"
        var rect = Element.shape("rect", w: 200, h: 100)
        rect.id = "rect1"
        rect.x = 100; rect.y = 200
        rect.rotation = 45
        rect.fill = .solid("#ff0000")
        rect.stroke = "#000000"
        rect.strokeWidth = 2
        var photo = Element.image("asset:photo", w: 240, h: 180)
        photo.id = "photo1"
        photo.x = 400; photo.y = 200
        var d = Design(title: "Deck", width: 800, height: 600)
        d.pages = [Page(id: "p1", background: .color("#f4f4f6"), elements: [text, rect, photo])]
        return d
    }

    private func slide(_ d: Design, page: Int = 0, previous: Page? = nil) -> PptxExporter.SlideParts {
        PptxExporter.slide(design: d, page: d.pages[page], number: page + 1, previous: previous, firstImage: 1)
    }

    private func onePage(_ elements: [Element], background: Background = .color("#ffffff"),
                         width: Double = 800, height: Double = 600) -> Design {
        var d = Design(title: "Deck", width: width, height: height)
        d.pages = [Page(background: background, elements: elements)]
        return d
    }

    private func slideXML(_ elements: [Element]) -> String {
        slide(onePage(elements)).xml
    }

    private func isWellFormed(_ xml: String) -> Bool {
        XMLParser(data: Data(xml.utf8)).parse()
    }

    private func twoStops() -> [GradientStop] {
        [GradientStop(offset: 0, color: "#000000"), GradientStop(offset: 1, color: "#ffffff")]
    }

    // MARK: units (shared rows)

    func testEMUConversionRows() {
        let rows: [(px: Double, emu: Int)] = [
            (0, 0), (1, 9525), (0.5, 4763), (-0.5, -4763), (96, 914_400), (1080, 10_287_000),
            (1920, 18_288_000), (12.25, 116_681), (-10, -95_250), (33.3, 317_183),
        ]
        for row in rows { XCTAssertEqual(PptxExporter.emu(row.px), row.emu, "\(row.px) px") }
        XCTAssertEqual(PptxExporter.emu(.nan), 0)
    }

    /// Hundredths of a point: px × 0.75 pt.
    func testTypeSizeRows() {
        let rows: [(px: Double, size: Int)] = [(42, 3150), (32, 2400), (12, 900), (10.5, 788), (13.5, 1013), (0, 0)]
        for row in rows { XCTAssertEqual(PptxExporter.fontSize(row.px), row.size, "\(row.px) px") }
    }

    /// 60000ths of a degree, clockwise, turned into 0..<360 first.
    func testAngleRows() {
        let rows: [(degrees: Double, angle: Int)] = [
            (0, 0), (45, 2_700_000), (-90, 16_200_000), (360, 0), (450, 5_400_000), (720.5, 30_000),
        ]
        for row in rows { XCTAssertEqual(PptxExporter.angle(row.degrees), row.angle, "\(row.degrees)°") }
    }

    /// A side outside 96–5376 px scales the whole deck by one factor.
    func testADesignPowerPointCannotOpenAtItsSizeIsScaledIntoIt() {
        let rows: [(w: Double, h: Double, scale: Double, cx: Int, cy: Int)] = [
            (800, 600, 1, 7_620_000, 5_715_000),
            (8000, 4000, 0.672, 51_206_400, 25_603_200),
            (1000, 60, 1.6, 15_240_000, 914_400),
            (8000, 40, 0.672, 51_206_400, 914_400),
            (0, 600, 1, 914_400, 5_715_000),
        ]
        for row in rows {
            let scale = PptxExporter.slideScale(width: row.w, height: row.h)
            XCTAssertEqual(scale, row.scale, accuracy: 1e-12, "\(row.w) x \(row.h)")
            XCTAssertEqual(PptxExporter.slideEdge(row.w, scale: scale), row.cx, "\(row.w) x \(row.h)")
            XCTAssertEqual(PptxExporter.slideEdge(row.h, scale: scale), row.cy, "\(row.w) x \(row.h)")
        }
        var rect = Element.shape("rect", w: 100, h: 200)
        rect.x = 1000; rect.y = 500
        rect.stroke = "#000000"
        rect.strokeWidth = 2
        let text = Element.text("Hi", fontSize: 32)
        let d = onePage([rect, text], width: 8000, height: 4000)
        XCTAssertTrue(PptxExporter.presentationXML(width: 8000, height: 4000, slides: 1, notes: false)
            .contains("<p:sldSz cx=\"51206400\" cy=\"25603200\"/>"))
        let xml = slide(d).xml
        XCTAssertTrue(xml.contains("<a:off x=\"6400800\" y=\"3200400\"/><a:ext cx=\"640080\" cy=\"1280160\"/>"), xml)
        XCTAssertTrue(xml.contains("<a:ln w=\"12802\">"))
        XCTAssertTrue(xml.contains("<a:rPr sz=\"1613\">"))
    }

    // MARK: the shared vectors

    func testTheFixtureSlideXMLIsTheSharedVector() {
        let expected = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
            "<p:sld xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" ",
            "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" ",
            "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">",
            "<p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"F4F4F6\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>",
            "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>",
            "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"text1\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>",
            "<p:spPr><a:xfrm><a:off x=\"381000\" y=\"381000\"/><a:ext cx=\"3810000\" cy=\"571500\"/></a:xfrm>",
            "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>",
            "<p:txBody><a:bodyPr lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"/><a:lstStyle/><a:p><a:pPr algn=\"ctr\"/>",
            "<a:r><a:rPr sz=\"2400\"><a:solidFill><a:srgbClr val=\"1F2430\"/></a:solidFill>",
            "<a:latin typeface=\"Lora\"/></a:rPr><a:t>Hello </a:t></a:r>",
            "<a:r><a:rPr sz=\"2400\" b=\"1\"><a:solidFill><a:srgbClr val=\"1F2430\"/></a:solidFill>",
            "<a:latin typeface=\"Lora\"/></a:rPr><a:t>world</a:t></a:r></a:p></p:txBody></p:sp>",
            "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"rect1\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>",
            "<p:spPr><a:xfrm rot=\"2700000\"><a:off x=\"952500\" y=\"1905000\"/><a:ext cx=\"1905000\" cy=\"952500\"/></a:xfrm>",
            "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill>",
            "<a:ln w=\"19050\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:ln></p:spPr></p:sp>",
            "<p:pic><p:nvPicPr><p:cNvPr id=\"4\" name=\"photo1\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>",
            "<p:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>",
            "<p:spPr><a:xfrm><a:off x=\"3810000\" y=\"1905000\"/><a:ext cx=\"2286000\" cy=\"1714500\"/></a:xfrm>",
            "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>",
            "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>",
        ].joined()
        let parts = slide(fixture())
        XCTAssertEqual(parts.xml, expected)
        XCTAssertTrue(isWellFormed(parts.xml))
    }

    func testTheFixtureSlideRelationshipsAreTheSharedVector() {
        let expected = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" ",
            "Target=\"../slideLayouts/slideLayout1.xml\"/>",
            "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" ",
            "Target=\"../media/image1.png\"/>",
            "</Relationships>",
        ].joined()
        let parts = slide(fixture())
        XCTAssertEqual(parts.rels, expected)
        XCTAssertEqual(parts.media.map(\.name), ["image1.png"])
        XCTAssertNil(parts.notes)
    }

    func testTheFixturePresentationXMLIsTheSharedVector() {
        let expected = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
            "<p:presentation xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" ",
            "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" ",
            "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">",
            "<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst>",
            "<p:sldIdLst><p:sldId id=\"256\" r:id=\"rId2\"/></p:sldIdLst>",
            "<p:sldSz cx=\"7620000\" cy=\"5715000\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/>",
            "</p:presentation>",
        ].joined()
        let parts = PptxExporter.packageParts(design: fixture(), noted: [false])
        XCTAssertEqual(parts.first { $0.name == "ppt/presentation.xml" }?.xml, expected)
    }

    func testThePresentationsRelationshipsAreTheSharedVector() {
        let expected = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" ",
            "Target=\"slideMasters/slideMaster1.xml\"/>",
            "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" ",
            "Target=\"slides/slide1.xml\"/>",
            "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" ",
            "Target=\"slides/slide2.xml\"/>",
            "<Relationship Id=\"rId4\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\" ",
            "Target=\"notesMasters/notesMaster1.xml\"/>",
            "<Relationship Id=\"rId5\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps\" ",
            "Target=\"presProps.xml\"/>",
            "<Relationship Id=\"rId6\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps\" ",
            "Target=\"viewProps.xml\"/>",
            "<Relationship Id=\"rId7\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" ",
            "Target=\"theme/theme1.xml\"/>",
            "<Relationship Id=\"rId8\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles\" ",
            "Target=\"tableStyles.xml\"/>",
            "</Relationships>",
        ].joined()
        XCTAssertEqual(PptxExporter.presentationRels(slides: 2, notes: true), expected)
        XCTAssertTrue(PptxExporter.presentationXML(width: 800, height: 600, slides: 2, notes: true)
            .contains("<p:notesMasterIdLst><p:notesMasterId r:id=\"rId4\"/></p:notesMasterIdLst>"))
    }

    /// The notes as typed, a paragraph a line.
    func testTheNotesSlideIsTheSharedVector() {
        let expected = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
            "<p:notes xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" ",
            "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" ",
            "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">",
            "<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>",
            "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Notes\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>",
            "<p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>",
            "<a:p><a:r><a:t>  Say hello</a:t></a:r></a:p><a:p/><a:p><a:r><a:t>Then &lt;go&gt; &amp; wave</a:t></a:r></a:p><a:p/>",
            "</p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>",
        ].joined()
        var d = onePage([])
        d.pages[0].notes = "  Say hello\n\nThen <go> & wave\n"
        let parts = slide(d)
        XCTAssertEqual(parts.notes, expected)
        XCTAssertTrue(parts.rels.hasSuffix("Target=\"../notesSlides/notesSlide1.xml\"/></Relationships>"))
        XCTAssertTrue(PptxExporter.contentTypes(noted: [true]).contains("<Override PartName=\"/ppt/notesSlides/notesSlide1.xml\""))
        XCTAssertTrue(isWellFormed(PptxExporter.notesRels(slide: 1)))

        // Notes of only spaces are none.
        d.pages[0].notes = "  \n "
        XCTAssertNil(slide(d).notes)
    }

    /// The fixed parts first, then each slide's pictures, the slide, and
    /// its notes — a hidden page left out of All pages, as the PDF leaves
    /// it — every entry intact.
    func testTheZipListsItsEntriesInTheSharedOrder() async throws {
        var d = fixture()
        var second = Page(id: "p2", background: .color("#000000"), elements: [Element.sticker("🎉")])
        second.notes = "Thanks"
        var hidden = Page(id: "p3")
        hidden.hidden = true
        d.pages += [hidden, second]
        let url = destination()
        try await PptxExporter.export(design: d, range: .all, to: url)
        let entries = try readZip(Data(contentsOf: url))
        let expected = [
            "[Content_Types].xml", "_rels/.rels", "ppt/presentation.xml", "ppt/_rels/presentation.xml.rels",
            "ppt/presProps.xml", "ppt/viewProps.xml", "ppt/tableStyles.xml", "ppt/theme/theme1.xml",
            "ppt/slideMasters/slideMaster1.xml", "ppt/slideMasters/_rels/slideMaster1.xml.rels",
            "ppt/slideLayouts/slideLayout1.xml", "ppt/slideLayouts/_rels/slideLayout1.xml.rels",
            "ppt/notesMasters/notesMaster1.xml", "ppt/notesMasters/_rels/notesMaster1.xml.rels",
            "ppt/theme/theme2.xml",
            "ppt/media/image1.png", "ppt/slides/slide1.xml", "ppt/slides/_rels/slide1.xml.rels",
            "ppt/media/image2.png", "ppt/slides/slide2.xml", "ppt/slides/_rels/slide2.xml.rels",
            "ppt/notesSlides/notesSlide2.xml", "ppt/notesSlides/_rels/notesSlide2.xml.rels",
        ]
        XCTAssertEqual(entries.map(\.name), expected)
        XCTAssertEqual(PptxExporter.entryNames(design: d, indices: [0, 2]), expected)
        for entry in entries where entry.name.hasSuffix(".xml") || entry.name.hasSuffix(".rels") {
            XCTAssertTrue(isWellFormed(String(decoding: entry.data, as: UTF8.self)), entry.name)
        }
        // The pictures are PNGs.
        for entry in entries where entry.name.hasPrefix("ppt/media/") {
            XCTAssertEqual(Array(entry.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], entry.name)
        }
        let slide1 = entries.first { $0.name == "ppt/slides/slide1.xml" }.map { String(decoding: $0.data, as: UTF8.self) }
        XCTAssertEqual(slide1, PptxExporter.deck(design: d, indices: [0, 2])[0].xml)
    }

    /// Current page, or the pages chosen, as the PDF takes them.
    func testThePageChoiceIsThePDFs() async throws {
        var d = fixture()
        d.pages += [Page(id: "p2"), Page(id: "p3")]
        let url = destination()
        try await PptxExporter.export(design: d, range: .chosen(["p3", "p1"]), to: url)
        let names = try readZip(Data(contentsOf: url)).map(\.name)
        XCTAssertTrue(names.contains("ppt/slides/slide2.xml"))
        XCTAssertFalse(names.contains("ppt/slides/slide3.xml"))
        XCTAssertEqual(DesignExporter.fileURL(for: d, ext: PptxExporter.fileExtension).lastPathComponent, "Deck.pptx")
        XCTAssertEqual(PptxExporter.mimeType,
                       "application/vnd.openxmlformats-officedocument.presentationml.presentation")
    }

    /// Fade, push and cut come in as PowerPoint's; any other kind none.
    func testTransitionsFadePushAndCut() {
        var d = Design(title: "Deck", width: 800, height: 600)
        d.pages = [Page(), Page(), Page(), Page(), Page()]
        d.pages[0].transition = "push"
        d.pages[2].transition = "cut"
        d.pages[3].transition = "zoom"
        let slides = PptxExporter.deck(design: d, indices: [0, 1, 2, 3, 4])
        XCTAssertFalse(slides[0].xml.contains("<p:transition>"))
        XCTAssertTrue(slides[1].xml.hasSuffix("<p:transition><p:push/></p:transition></p:sld>"))
        XCTAssertTrue(slides[2].xml.hasSuffix("<p:transition><p:fade/></p:transition></p:sld>"))
        XCTAssertTrue(slides[3].xml.hasSuffix("<p:transition><p:cut/></p:transition></p:sld>"))
        XCTAssertFalse(slides[4].xml.contains("<p:transition>"))
    }

    // MARK: what each element becomes (shared rows)

    private func word(_ form: PptxExporter.Form) -> String {
        switch form {
        case .text: return "text"
        case .shape: return "shape"
        case .line: return "line"
        case .picture: return "picture"
        }
    }

    func testWhatGoesOutAsWhat() {
        let text = Element.text("Hi")
        let rect = Element.shape("rect")
        func with(_ el: Element, _ change: (inout Element) -> Void) -> Element {
            var copy = el
            change(&copy)
            return copy
        }
        let gradient = Paint(kind: "gradient", color: nil, angle: 90, stops: twoStops())
        let rows: [(Element, String)] = [
            (text, "text"),
            (with(text) { $0.text = "**Bold** and ~~gone~~" }, "text"),
            (with(text) { $0.listStyle = "bullet" }, "text"),
            (with(text) { $0.effect = TextEffectSpec(type: "neon") }, "picture"),
            (with(text) { $0.curve = 90 }, "picture"),
            (with(text) { $0.textFill = gradient }, "picture"),
            (with(text) { $0.textFill = .solid("#ff0000") }, "text"),
            (with(text) { $0.setSpans([TextSpan(start: 0, end: 1, color: "#ff0000")]) }, "text"),
            (with(text) { $0.uppercase = true }, "text"),
            (with(text) { $0.flipH = true }, "picture"),
            (with(text) { $0.dropCap = true }, "picture"),
            (rect, "shape"),
            (with(rect) { $0.radius = 12 }, "shape"),
            (Element.shape("circle"), "shape"),
            (with(rect) { $0.fill = .clear; $0.stroke = "#000000"; $0.strokeWidth = 2 }, "shape"),
            (with(rect) { $0.fill = Paint(kind: "gradient", color: nil, angle: 90,
                                          stops: [GradientStop(offset: 0, color: "#000000")]) }, "picture"),
            (with(rect) { $0.fill = gradient }, "shape"),
            (with(rect) { $0.fill = gradient; $0.fill?.gradientKind = "radial" }, "picture"),
            (with(rect) { $0.fill = .image("asset:x") }, "picture"),
            (with(rect) { $0.corners = [8, 0, 0, 8] }, "picture"),
            (Element.shape("star-5"), "picture"),
            (with(rect) { $0.text = "Buy" }, "picture"),
            (with(rect) { $0.pathData = "M0,0L100,100" }, "picture"),
            (with(rect) { $0.chartPart = "series:0" }, "picture"),
            (with(rect) { $0.shadow = Shadow() }, "picture"),
            (with(rect) { $0.flipH = true }, "picture"),
            (with(rect) { $0.blendMode = "multiply" }, "picture"),
            (Element.line(), "line"),
            (with(Element.line()) { $0.flipH = true }, "line"),
            (with(Element.line()) { $0.shadow = Shadow() }, "picture"),
            (Element.image("asset:x"), "picture"),
            (Element.sticker("🎉"), "picture"),
        ]
        for (n, row) in rows.enumerated() {
            XCTAssertEqual(word(PptxExporter.form(of: row.0)), row.1, "row \(n)")
        }
        XCTAssertEqual(PptxExporter.form(of: Element.shape("circle")), .shape("ellipse"))
        XCTAssertEqual(PptxExporter.form(of: with(rect) { $0.radius = 12 }), .shape("roundRect"))
    }

    // MARK: text (shared)

    func testATextBoxKeepsItsWordsStylesColourSpacingAndPlaceInTheBox() {
        var el = Element.text("**Big** *news*\n\n__u__ ~~s~~", fontSize: 40)
        el.id = "t"
        el.x = 0; el.y = 0; el.w = 100; el.h = 100
        el.fontFamily = "didone"
        el.align = "right"
        el.letterSpacing = 2
        el.color = "#11223380"
        el.opacity = 0.5
        el.rotation = -90
        el.vAlign = "bottom"
        let xml = slideXML([el])
        let ink = "<a:solidFill><a:srgbClr val=\"112233\"><a:alpha val=\"25098\"/></a:srgbClr></a:solidFill><a:latin typeface=\"Playfair Display\"/>"
        let expected = [
            "<a:bodyPr lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"b\"/><a:lstStyle/>",
            "<a:p><a:pPr algn=\"r\"/>",
            "<a:r><a:rPr sz=\"3000\" b=\"1\" spc=\"150\">INK</a:rPr><a:t>Big</a:t></a:r>",
            "<a:r><a:rPr sz=\"3000\" spc=\"150\">INK</a:rPr><a:t> </a:t></a:r>",
            "<a:r><a:rPr sz=\"3000\" i=\"1\" spc=\"150\">INK</a:rPr><a:t>news</a:t></a:r></a:p>",
            "<a:p><a:pPr algn=\"r\"/><a:endParaRPr sz=\"3000\"/></a:p>",
            "<a:p><a:pPr algn=\"r\"/>",
            "<a:r><a:rPr sz=\"3000\" u=\"sng\" spc=\"150\">INK</a:rPr><a:t>u</a:t></a:r>",
            "<a:r><a:rPr sz=\"3000\" spc=\"150\">INK</a:rPr><a:t> </a:t></a:r>",
            "<a:r><a:rPr sz=\"3000\" strike=\"sngStrike\" spc=\"150\">INK</a:rPr><a:t>s</a:t></a:r></a:p>",
        ].joined().replacingOccurrences(of: "INK", with: ink)
        XCTAssertTrue(xml.contains(expected), xml)
        XCTAssertTrue(xml.contains("<a:xfrm rot=\"16200000\">"))
        XCTAssertTrue(isWellFormed(xml))
    }

    func testTheBoxsOwnTypeCarriesOverBoldFrom700() {
        var el = Element.text("Tom & Jerry <3")
        el.fontWeight = 700
        el.italic = true
        el.underline = true
        el.uppercase = true
        el.letterSpacing = 2
        let xml = slideXML([el])
        XCTAssertTrue(xml.contains("<a:rPr sz=\"3150\" b=\"1\" i=\"1\" u=\"sng\" cap=\"all\" spc=\"150\">"), xml)
        XCTAssertTrue(xml.contains("<a:t>Tom &amp; Jerry &lt;3</a:t>"))
        // SemiBold is not bold, as the canvas sets it.
        var semibold = Element.text("Hi")
        semibold.fontWeight = 600
        XCTAssertTrue(slideXML([semibold]).contains("<a:rPr sz=\"3150\"><a:solidFill>"))
        // Bold words in a bold box come out the same as the rest: one run.
        var bold = Element.text("a **b**")
        bold.fontWeight = 700
        let run = "<a:rPr sz=\"3150\" b=\"1\"><a:solidFill><a:srgbClr val=\"1F2430\"/></a:solidFill>"
            + "<a:latin typeface=\"Modern Sans\"/></a:rPr><a:t>a b</a:t></a:r></a:p>"
        XCTAssertTrue(slideXML([bold]).contains(run))
    }

    /// A colour or a size of its own on some words is a run of its own.
    func testColouredAndSizedWordsAreRunsOfTheirOwn() {
        var el = Element.text("one two")
        el.setSpans([TextSpan(start: 4, end: 7, color: "#ff0000", scale: 2)])
        let expected = [
            "<a:r><a:rPr sz=\"3150\"><a:solidFill><a:srgbClr val=\"1F2430\"/></a:solidFill>",
            "<a:latin typeface=\"Modern Sans\"/></a:rPr><a:t>one </a:t></a:r>",
            "<a:r><a:rPr sz=\"6300\"><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill>",
            "<a:latin typeface=\"Modern Sans\"/></a:rPr><a:t>two</a:t></a:r>",
        ].joined()
        let xml = slideXML([el])
        XCTAssertTrue(xml.contains(expected), xml)
    }

    /// Fitted type goes out at the size the canvas draws it, with no
    /// autofit for PowerPoint to redo.
    func testFittedTypeGoesOutAtTheSizeTheCanvasDrawsIt() {
        var el = Element.text("Headline", fontSize: 120)
        el.fitText = true
        let xml = slideXML([el])
        let size = PptxExporter.fontSize(FontLibrary.effectiveFontSize(for: el))
        XCTAssertTrue(xml.contains("<a:rPr sz=\"\(size)\">"), xml)
        XCTAssertFalse(xml.contains("Autofit"))
    }

    /// "{page}" is the page's number, a list's markers are words.
    func testPageNumbersAndListMarkersAreWords() {
        let el = Element.text("Page {page} of {pages}")
        var list = Element.text("Milk\nEggs")
        list.listStyle = "bullet"
        var d = Design(title: "Deck", width: 800, height: 600)
        d.pages = [Page(), Page(elements: [el, list])]
        let xml = PptxExporter.slide(design: d, page: d.pages[1], number: 1, previous: nil, firstImage: 1).xml
        XCTAssertTrue(xml.contains("<a:t>Page 2 of 2</a:t>"), xml)
        XCTAssertTrue(xml.contains("<a:t>•  Milk</a:t>"))
        XCTAssertTrue(xml.contains("<a:t>•  Eggs</a:t>"))
    }

    /// Shared: a word's font is its run's face, and a word's link a click
    /// on its run, in the link colour when it has none of its own.
    func testWordsKeepTheirOwnFontAndLink() {
        var el = Element.text("one two three")
        el.setSpans([TextSpan(start: 4, end: 7, font: "lora"), TextSpan(start: 8, end: 13, link: "https://x.com")])
        let parts = slide(onePage([el]))
        let ink = "<a:solidFill><a:srgbClr val=\"1F2430\"/></a:solidFill>"
        let expected = [
            "<a:r><a:rPr sz=\"3150\">\(ink)<a:latin typeface=\"Modern Sans\"/></a:rPr><a:t>one </a:t></a:r>",
            "<a:r><a:rPr sz=\"3150\">\(ink)<a:latin typeface=\"Lora\"/></a:rPr><a:t>two</a:t></a:r>",
            "<a:r><a:rPr sz=\"3150\">\(ink)<a:latin typeface=\"Modern Sans\"/></a:rPr><a:t> </a:t></a:r>",
            "<a:r><a:rPr sz=\"3150\"><a:solidFill><a:srgbClr val=\"2563EB\"/></a:solidFill>",
            "<a:latin typeface=\"Modern Sans\"/><a:hlinkClick r:id=\"rId2\"/></a:rPr><a:t>three</a:t></a:r>",
        ].joined()
        XCTAssertTrue(parts.xml.contains(expected), parts.xml)
        let rel = "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" "
            + "Target=\"https://x.com\" TargetMode=\"External\"/>"
        XCTAssertTrue(parts.rels.contains(rel), parts.rels)
        XCTAssertTrue(isWellFormed(parts.xml))
    }

    /// Shared: sz is held to 100 to 400000, as a deck must have it.
    func testATypeSizeIsHeldToWhatADeckMayHold() {
        let rows: [(px: Double, size: Int)] = [
            (1.2, 100), (0, 100), (-5, 100), (.nan, 100), (42, 3150), (5000, 375_000), (6000, 400_000),
        ]
        for row in rows { XCTAssertEqual(PptxExporter.typeSize(row.px), row.size, "\(row.px) px") }
        // A 4 px box with a word at 0.3 of it.
        var tiny = Element.text("ab", fontSize: 4)
        tiny.setSpans([TextSpan(start: 0, end: 1, scale: 0.3)])
        XCTAssertTrue(slideXML([tiny]).contains("<a:rPr sz=\"100\">"))
    }

    /// Shared: a page of its own size is fitted whole and centred.
    func testAPageOfItsOwnSizeIsFittedOntoTheSlide() {
        let d = Design(title: "Deck", width: 1920, height: 1080)
        let rows: [(w: Double?, h: Double?, factor: Double, dx: Double, dy: Double, fills: Bool)] = [
            (nil, nil, 1, 0, 0, true),
            (1080, 1920, 0.5625, 656.25, 0, false),
            (960, 540, 2, 0, 0, true),
            (1920, 1920, 0.5625, 420, 0, false),
            (3840, 1080, 0.5, 0, 270, false),
        ]
        for row in rows {
            var page = Page()
            page.width = row.w
            page.height = row.h
            let fit = PptxExporter.fit(design: d, page: page)
            let label = "\(String(describing: row.w)) x \(String(describing: row.h))"
            XCTAssertEqual(fit.factor, row.factor, accuracy: 1e-12, label)
            XCTAssertEqual(fit.dx, row.dx, accuracy: 1e-12, label)
            XCTAssertEqual(fit.dy, row.dy, accuracy: 1e-12, label)
            XCTAssertEqual(fit.fills, row.fills, label)
        }
    }

    /// Shared: the slide of a tall page in a wide deck.
    func testATallPageInAWideDeckKeepsItsElementsOnTheSlide() {
        var rect = Element.shape("rect", w: 100, h: 100)
        rect.id = "r"
        rect.x = 0; rect.y = 1800
        rect.stroke = "#000000"
        rect.strokeWidth = 2
        var text = Element.text("Hi", fontSize: 40, w: 1080)
        text.x = 0; text.y = 0; text.h = 100
        text.letterSpacing = 2
        var page = Page(background: .image("asset:bg"), elements: [rect, text])
        page.width = 1080
        page.height = 1920
        var d = Design(title: "Deck", width: 1920, height: 1080)
        d.pages = [page]
        let parts = slide(d)
        let expected = [
            "<p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>",
            "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>",
            "<p:pic><p:nvPicPr><p:cNvPr id=\"2\" name=\"Background\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>",
            "<p:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>",
            "<p:spPr><a:xfrm><a:off x=\"6250781\" y=\"0\"/><a:ext cx=\"5786438\" cy=\"10287000\"/></a:xfrm>",
            "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>",
            "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"r\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>",
            "<p:spPr><a:xfrm><a:off x=\"6250781\" y=\"9644063\"/><a:ext cx=\"535781\" cy=\"535781\"/></a:xfrm>",
        ].joined()
        XCTAssertTrue(parts.xml.contains(expected), parts.xml)
        XCTAssertTrue(parts.xml.contains("<a:ln w=\"10716\">"))
        XCTAssertTrue(parts.xml.contains("<a:rPr sz=\"1688\" spc=\"84\">"))
        XCTAssertTrue(parts.rels.contains("Target=\"../media/image1.jpeg\""))
        XCTAssertTrue(isWellFormed(parts.xml))
        // A page of the deck's shape at another size still fills the slide.
        d.pages[0].width = 960
        d.pages[0].height = 540
        let fills = slide(d).xml
        XCTAssertTrue(fills.contains("<p:bg><p:bgPr><a:blipFill><a:blip r:embed=\"rId2\"/>"), fills)
        XCTAssertTrue(fills.contains("<a:off x=\"0\" y=\"34290000\"/><a:ext cx=\"1905000\" cy=\"1905000\"/>"))
    }

    // MARK: shapes and lines (shared)

    func testShapesAndLinesArePresetGeometry() {
        var round = Element.shape("rect", w: 200, h: 100)
        round.id = "a"
        round.radius = 80
        round.opacity = 0.5
        var oval = Element.shape("circle")
        oval.id = "b"
        oval.fill = Paint(kind: "gradient", color: nil, angle: 180, stops: twoStops())
        var line = Element.line(w: 300)
        line.id = "c"
        line.x = 10; line.y = 20
        line.dash = "dashed"
        line.startCap = "dot"
        line.endCap = "arrow"
        let xml = slideXML([round, oval, line])
        // A radius past half the shorter side is clamped to it.
        let rounded = "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val 50000\"/></a:avLst></a:prstGeom>"
            + "<a:solidFill><a:srgbClr val=\"8B5CF6\"><a:alpha val=\"50000\"/></a:srgbClr></a:solidFill>"
        XCTAssertTrue(xml.contains(rounded), xml)
        let ellipse = "<a:prstGeom prst=\"ellipse\"><a:avLst/></a:prstGeom><a:gradFill><a:gsLst>"
            + "<a:gs pos=\"0\"><a:srgbClr val=\"000000\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"FFFFFF\"/></a:gs>"
            + "</a:gsLst><a:lin ang=\"5400000\"/></a:gradFill>"
        XCTAssertTrue(xml.contains(ellipse))
        let straight = "<a:xfrm><a:off x=\"95250\" y=\"228600\"/><a:ext cx=\"2857500\" cy=\"0\"/></a:xfrm>"
            + "<a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom><a:ln w=\"38100\" cap=\"rnd\">"
            + "<a:solidFill><a:srgbClr val=\"1F2430\"/></a:solidFill><a:prstDash val=\"dash\"/>"
            + "<a:headEnd type=\"oval\"/><a:tailEnd type=\"triangle\"/></a:ln>"
        XCTAssertTrue(xml.contains(straight))
        // Flipped across, its ends swap.
        line.flipH = true
        XCTAssertTrue(slideXML([line]).contains("<a:headEnd type=\"triangle\"/><a:tailEnd type=\"oval\"/>"))
        // A colour that does not read is black.
        var unread = Element.shape("rect")
        unread.fill = .solid("nope")
        XCTAssertTrue(slideXML([unread]).contains("<a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill>"))
        XCTAssertTrue(isWellFormed(xml))
    }

    func testAShapesFillBorderAndOpacity() {
        var el = Element.shape("circle", w: 100, h: 50)
        el.id = "c"
        el.fill = .solid("#ff000080")
        el.stroke = "#000000"
        el.strokeWidth = 4
        el.opacity = 0.5
        let xml = slideXML([el])
        XCTAssertTrue(xml.contains("<a:solidFill><a:srgbClr val=\"FF0000\"><a:alpha val=\"25098\"/></a:srgbClr></a:solidFill>"), xml)
        XCTAssertTrue(xml.contains("<a:ln w=\"38100\"><a:solidFill><a:srgbClr val=\"000000\"><a:alpha val=\"50000\"/>"))

        el.fill = .clear
        el.stroke = nil
        el.opacity = 1
        XCTAssertTrue(slideXML([el]).contains("</a:prstGeom><a:noFill/></p:spPr>"))
    }

    // MARK: pictures and backgrounds (shared)

    func testAPictureHasRoomPastItsBoxForWhatReachesBeyondIt() {
        var bordered = Element.image("asset:x", w: 100, h: 100)
        bordered.x = 50; bordered.y = 50
        bordered.stroke = "#000000"
        bordered.strokeWidth = 20
        XCTAssertEqual(PptxExporter.margin(bordered), 10, accuracy: 1e-9)
        let xml = slideXML([bordered])
        XCTAssertTrue(xml.contains("<a:off x=\"381000\" y=\"381000\"/><a:ext cx=\"1143000\" cy=\"1143000\"/>"), xml)
        // A shadow's blur and a half and its longer offset.
        var shadowed = Element.text("Hi")
        shadowed.shadow = Shadow(blur: 10, offsetX: 4, offsetY: 6)
        XCTAssertEqual(PptxExporter.margin(shadowed), 21, accuracy: 1e-9)
        // A text effect's reach: Lift's shadow at type 40, its drop and a
        // blur and a half.
        var lifted = Element.text("Hi", fontSize: 40)
        lifted.effect = TextEffectSpec(type: "lift")
        XCTAssertEqual(PptxExporter.margin(lifted), 37.2, accuracy: 1e-9)
    }

    /// A gradient or photo behind the page fills the slide's background;
    /// the pictures are numbered on from it.
    func testAPhotoBackgroundFillsTheSlidesBackground() {
        var sticker = Element.sticker("🎉")
        sticker.id = "s"
        let d = onePage([sticker], background: .image("asset:bg"))
        let parts = slide(d)
        let fill = "<p:bg><p:bgPr><a:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></a:blipFill>"
            + "<a:effectLst/></p:bgPr></p:bg>"
        XCTAssertTrue(parts.xml.contains(fill), parts.xml)
        XCTAssertTrue(parts.xml.contains("<p:cNvPr id=\"2\" name=\"s\"/>"))
        XCTAssertTrue(parts.xml.contains("<a:blip r:embed=\"rId3\"/>"))
        XCTAssertTrue(parts.rels.contains("Target=\"../media/image1.jpeg\""))
        XCTAssertTrue(parts.rels.contains("Target=\"../media/image2.png\""))
        XCTAssertEqual(parts.media.first?.source, .background)
    }

    /// A picture that did not draw is left out, and the next shape takes
    /// its number; a background that did not is white.
    func testWhatDidNotDrawIsLeftOut() {
        var shadowed = Element.text("Hi")
        shadowed.shadow = Shadow(blur: 10, offsetX: 4, offsetY: 6)
        var rect = Element.shape("rect")
        rect.id = "r"
        let d = onePage([shadowed, rect], background: .image("asset:bg"))
        let parts = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, drawn: [])
        XCTAssertFalse(parts.xml.contains("<p:pic>"))
        XCTAssertTrue(parts.xml.contains("<p:cNvPr id=\"2\" name=\"r\"/>"), parts.xml)
        let white = "<p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>"
        XCTAssertTrue(parts.xml.contains(white))
        XCTAssertFalse(parts.rels.contains("media"))
    }

    /// A link to follow is a click on the element, its relationship before
    /// the picture's; anything else is no link.
    func testALinkIsAClickOnTheElement() {
        var photo = Element.image("asset:x")
        photo.id = "i"
        photo.link = "https://canvia.app/?a=1&b=2"
        photo.altText = " A \"cat\" "
        var script = Element.shape("rect")
        script.id = "r"
        script.link = "javascript:alert(1)"
        let parts = slide(onePage([photo, script]))
        let props = "<p:cNvPr id=\"2\" name=\"i\" descr=\"A &quot;cat&quot;\"><a:hlinkClick r:id=\"rId2\"/></p:cNvPr>"
        XCTAssertTrue(parts.xml.contains(props), parts.xml)
        XCTAssertTrue(parts.xml.contains("<a:blip r:embed=\"rId3\"/>"))
        XCTAssertTrue(parts.xml.contains("<p:cNvPr id=\"3\" name=\"r\"/>"))
        XCTAssertTrue(parts.rels.contains("Target=\"https://canvia.app/?a=1&amp;b=2\" TargetMode=\"External\"/>"), parts.rels)
        XCTAssertFalse(parts.rels.contains("javascript"))
    }

    // MARK: the package

    func testEveryFixedPartIsWellFormed() {
        for part in PptxExporter.packageParts(design: fixture(), noted: [true]) {
            XCTAssertTrue(isWellFormed(part.xml), part.name)
        }
    }

    // MARK: the zip writer

    func testCRC32CheckValue() {
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(ZipWriter.crc32(Data()), 0)
    }

    func testAnArchiveReadsBack() throws {
        var bytes = Data()
        let zip = ZipWriter { bytes.append($0) }
        try zip.add("a.txt", Data("hello".utf8))
        try zip.add("dir/b.xml", Data("<b/>".utf8))
        try zip.finish()
        XCTAssertThrowsError(try zip.add("late", Data()))
        let entries = try readZip(bytes)
        XCTAssertEqual(entries.map(\.name), ["a.txt", "dir/b.xml"])
        XCTAssertEqual(entries.map { String(decoding: $0.data, as: UTF8.self) }, ["hello", "<b/>"])
        // The end record counts both and points at the directory.
        let end = bytes.suffix(22)
        XCTAssertEqual(Array(end.prefix(4)), [0x50, 0x4B, 0x05, 0x06])
        XCTAssertEqual(Int(end[end.startIndex + 10]), 2)
    }

    // MARK: reading a zip back

    private struct Entry {
        var name: String
        var data: Data
    }

    /// The local entries in file order, each checked against its CRC.
    private func readZip(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        var entries: [Entry] = []
        var at = 0
        while at + 30 <= bytes.count, u32(at) == 0x0403_4b50 {
            XCTAssertEqual(u16(at + 8), 0, "stored")
            let size = u32(at + 18)
            let nameLength = u16(at + 26), extra = u16(at + 28)
            let nameStart = at + 30
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            let start = nameStart + nameLength + extra
            let body = Data(bytes[start..<(start + size)])
            XCTAssertEqual(UInt32(u32(at + 14)), ZipWriter.crc32(body), name)
            entries.append(Entry(name: name, data: body))
            at = start + size
        }
        XCTAssertEqual(u32(at), 0x0201_4b50, "the central directory follows the entries")
        return entries
    }
}
