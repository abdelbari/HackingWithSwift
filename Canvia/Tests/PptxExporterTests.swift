// PowerPoint export: the units, what each element becomes, the slide XML
// for the shared fixture — character for character, the same vectors the
// Android twin's PptxWriter is tested with — and the file itself: a ZIP whose
// entries come in the required order, every one of them intact.

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
        var text = Element.text("Hello", fontSize: 32, w: 400)
        text.id = "text1"
        text.x = 40; text.y = 40; text.h = 40
        text.fontFamily = "lora"
        text.align = "left"
        var rect = Element.shape("rect", w: 200, h: 100)
        rect.id = "rect1"
        rect.x = 100; rect.y = 200
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

    private func onePage(_ elements: [Element], background: Background = .color("#ffffff")) -> Design {
        var d = Design(title: "Deck", width: 800, height: 600)
        d.pages = [Page(background: background, elements: elements)]
        return d
    }

    private func isWellFormed(_ xml: String) -> Bool {
        XMLParser(data: Data(xml.utf8)).parse()
    }

    // MARK: units

    func testEMUConversionRows() {
        let rows: [(px: Double, emu: Int)] = [
            (0, 0), (1, 9525), (0.5, 4763), (96, 914_400), (1080, 10_287_000),
            (1920, 18_288_000), (-10, -95_250), (33.3, 317_183),
        ]
        for row in rows { XCTAssertEqual(PptxExporter.emu(row.px), row.emu, "\(row.px) px") }
        XCTAssertEqual(PptxExporter.emu(.nan), 0)
    }

    /// Hundredths of a point: px × 0.75 pt.
    func testTypeSizeRows() {
        let rows: [(px: Double, size: Int)] = [(42, 3150), (32, 2400), (12, 900), (10.5, 788), (0, 0)]
        for row in rows { XCTAssertEqual(PptxExporter.fontSize(row.px), row.size, "\(row.px) px") }
    }

    /// 60000ths of a degree, clockwise, turned into 0..<360 first.
    func testAngleRows() {
        let rows: [(degrees: Double, angle: Int)] = [
            (0, 0), (45, 2_700_000), (-90, 16_200_000), (360, 0), (450, 5_400_000), (720.5, 30_000),
        ]
        for row in rows { XCTAssertEqual(PptxExporter.angle(row.degrees), row.angle, "\(row.degrees)°") }
    }

    /// A slide's side stays within the one to 56 inches PowerPoint opens.
    func testSlideSizeIsTheDesignsKeptWithinWhatPowerPointOpens() {
        XCTAssertEqual(PptxExporter.slideEdge(1080), 10_287_000)
        XCTAssertEqual(PptxExporter.slideEdge(50), 914_400)
        XCTAssertEqual(PptxExporter.slideEdge(6000), 51_206_400)
    }

    // MARK: the shared vectors

    func testTheFixtureSlideXMLIsTheSharedVector() {
        let parts = slide(fixture())
        let expected = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
            "<p:sld xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" ",
            "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" ",
            "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">",
            "<p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"F4F4F6\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>",
            "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>",
            "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"text1\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>",
            "<p:spPr><a:xfrm><a:off x=\"381000\" y=\"381000\"/><a:ext cx=\"3810000\" cy=\"381000\"/></a:xfrm>",
            "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>",
            "<p:txBody><a:bodyPr lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"/><a:lstStyle/>",
            "<a:p><a:r><a:rPr sz=\"2400\"><a:solidFill><a:srgbClr val=\"1F2430\"/></a:solidFill>",
            "<a:latin typeface=\"Lora\"/></a:rPr><a:t>Hello</a:t></a:r></a:p></p:txBody></p:sp>",
            "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"rect1\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>",
            "<p:spPr><a:xfrm><a:off x=\"952500\" y=\"1905000\"/><a:ext cx=\"1905000\" cy=\"952500\"/></a:xfrm>",
            "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>",
            "<a:solidFill><a:srgbClr val=\"8B5CF6\"/></a:solidFill></p:spPr></p:sp>",
            "<p:pic><p:nvPicPr><p:cNvPr id=\"4\" name=\"photo1\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>",
            "<p:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>",
            "<p:spPr><a:xfrm><a:off x=\"3810000\" y=\"1905000\"/><a:ext cx=\"2286000\" cy=\"1714500\"/></a:xfrm>",
            "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>",
            "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>",
        ].joined()
        XCTAssertEqual(parts.xml, expected)
        XCTAssertTrue(isWellFormed(parts.xml))
    }

    func testTheFixtureSlideRelationshipsAreTheSharedVector() {
        let parts = slide(fixture())
        let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        let expected = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
            "<Relationship Id=\"rId1\" Type=\"\(base)slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/>",
            "<Relationship Id=\"rId2\" Type=\"\(base)image\" Target=\"../media/image1.png\"/>",
            "</Relationships>",
        ].joined()
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
        XCTAssertEqual(PptxExporter.presentationXML(width: 800, height: 600, slides: 1, notes: false), expected)
    }

    // MARK: what each element becomes

    func testEachElementBecomesWhatKeepsItEditable() {
        XCTAssertEqual(PptxExporter.form(of: Element.text("Hi")), .text)
        XCTAssertEqual(PptxExporter.form(of: Element.shape("rect")), .shape("rect"))
        XCTAssertEqual(PptxExporter.form(of: Element.shape("circle")), .shape("ellipse"))
        XCTAssertEqual(PptxExporter.form(of: Element.line()), .line)
        XCTAssertEqual(PptxExporter.form(of: Element.image("asset:x")), .picture)
        XCTAssertEqual(PptxExporter.form(of: Element.sticker("🎉")), .picture)
        XCTAssertEqual(PptxExporter.form(of: Element.shape("star-5")), .picture)

        var gradient = Element.shape("rect")
        gradient.fill = Paint(kind: "gradient", color: nil, angle: 90,
                              stops: [GradientStop(offset: 0, color: "#ff0000"), GradientStop(offset: 1, color: "#0000ff")])
        XCTAssertEqual(PptxExporter.form(of: gradient), .shape("rect"))
        gradient.fill?.gradientKind = "radial"
        XCTAssertEqual(PptxExporter.form(of: gradient), .picture)
    }

    /// What no text box or preset carries comes through as a picture.
    func testWhatAPresetCannotCarryIsAPicture() {
        var rounded = Element.shape("rect")
        rounded.radius = 12
        var patterned = Element.shape("rect")
        patterned.fill = .pattern("dots", color: "#000000", secondary: "#ffffff")
        var shadowed = Element.shape("circle")
        shadowed.shadow = Shadow()
        var worded = Element.shape("rect")
        worded.text = "Buy"
        var glowing = Element.text("Hi")
        glowing.effect = TextEffectSpec(type: "neon")
        var curved = Element.text("Hi")
        curved.curve = 120
        var flipped = Element.text("Hi")
        flipped.flipH = true
        var drawn = Element.shape("rect")
        drawn.pathData = "M0,0L100,100"
        for el in [rounded, patterned, shadowed, worded, glowing, curved, flipped, drawn] {
            XCTAssertEqual(PptxExporter.form(of: el), .picture)
        }
    }

    // MARK: text

    func testInlineStylesBecomeRunsAndLinesParagraphs() {
        var el = Element.text("Hi **bold** and ~~gone~~\n\n_it_")
        el.id = "t"
        let paragraphs = PptxExporter.paragraphs(of: el)
        XCTAssertEqual(paragraphs.count, 3)
        XCTAssertEqual(paragraphs[0].map(\.text), ["Hi ", "bold", " and ", "gone"])
        XCTAssertTrue(paragraphs[0][1].style.bold)
        XCTAssertTrue(paragraphs[0][3].style.strike)
        XCTAssertTrue(paragraphs[1].isEmpty)
        XCTAssertEqual(paragraphs[2].map(\.text), ["it"])
        XCTAssertTrue(paragraphs[2][0].style.italic)

        let xml = slide(onePage([el])).xml
        XCTAssertTrue(xml.contains("<a:rPr sz=\"3150\" b=\"1\">"), xml)
        XCTAssertTrue(xml.contains("<a:rPr sz=\"3150\" strike=\"sngStrike\">"))
        XCTAssertTrue(xml.contains("<a:p><a:pPr algn=\"ctr\"/><a:endParaRPr sz=\"3150\"/></a:p>"))
        XCTAssertTrue(isWellFormed(xml))
    }

    func testTheBoxsTypeCarriesOver() {
        var el = Element.text("Tom & Jerry <3")
        el.fontWeight = 700
        el.italic = true
        el.underline = true
        el.uppercase = true
        el.letterSpacing = 2
        el.align = "right"
        el.vAlign = "bottom"
        el.rotation = -90
        el.opacity = 0.5
        el.fontFamily = "didone"
        let xml = slide(onePage([el])).xml
        XCTAssertTrue(xml.contains("<a:rPr sz=\"3150\" b=\"1\" i=\"1\" u=\"sng\" cap=\"all\" spc=\"150\">"), xml)
        XCTAssertTrue(xml.contains("<a:srgbClr val=\"1F2430\"><a:alpha val=\"50000\"/></a:srgbClr>"))
        XCTAssertTrue(xml.contains("<a:latin typeface=\"Playfair Display\"/>"))
        XCTAssertTrue(xml.contains("<a:pPr algn=\"r\"/>"))
        XCTAssertTrue(xml.contains("bIns=\"0\" anchor=\"b\"/>"))
        XCTAssertTrue(xml.contains("<a:xfrm rot=\"16200000\">"))
        XCTAssertTrue(xml.contains("<a:t>Tom &amp; Jerry &lt;3</a:t>"))
        XCTAssertTrue(isWellFormed(xml))
    }

    /// A colour or a size of its own on some words is a run of its own.
    func testColouredAndSizedWordsAreRunsOfTheirOwn() {
        var el = Element.text("one two")
        el.setSpans([TextSpan(start: 4, end: 7, color: "#ff0000", scale: 2)])
        let runs = PptxExporter.paragraphs(of: el)[0]
        XCTAssertEqual(runs.map(\.text), ["one ", "two"])
        XCTAssertEqual(runs[1].color, "#ff0000")
        XCTAssertEqual(runs[1].scale, 2)
        let xml = slide(onePage([el])).xml
        XCTAssertTrue(xml.contains("<a:rPr sz=\"6300\"><a:solidFill><a:srgbClr val=\"FF0000\"/>"), xml)
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

    // MARK: shapes and lines

    func testAShapesFillBorderAndOpacity() {
        var el = Element.shape("circle", w: 100, h: 50)
        el.id = "c"
        el.fill = .solid("#ff000080")
        el.stroke = "#000000"
        el.strokeWidth = 4
        el.opacity = 0.5
        let xml = slide(onePage([el])).xml
        XCTAssertTrue(xml.contains("<a:prstGeom prst=\"ellipse\"><a:avLst/></a:prstGeom>"), xml)
        XCTAssertTrue(xml.contains("<a:solidFill><a:srgbClr val=\"FF0000\"><a:alpha val=\"25098\"/></a:srgbClr></a:solidFill>"))
        XCTAssertTrue(xml.contains("<a:ln w=\"38100\"><a:solidFill><a:srgbClr val=\"000000\"><a:alpha val=\"50000\"/>"))

        el.fill = .clear
        el.stroke = nil
        el.opacity = 1
        XCTAssertTrue(slide(onePage([el])).xml.contains("</a:prstGeom><a:noFill/></p:spPr>"))
    }

    /// The CSS angle, 0° up, is 90° less in DrawingML, which starts at the
    /// right.
    func testALinearGradientIsAGradientFill() {
        var el = Element.shape("rect")
        el.fill = Paint(kind: "gradient", color: nil, angle: 180,
                        stops: [GradientStop(offset: 0, color: "#ff0000"), GradientStop(offset: 0.5, color: "#0000ff")])
        let expected = [
            "<a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FF0000\"/></a:gs>",
            "<a:gs pos=\"50000\"><a:srgbClr val=\"0000FF\"/></a:gs></a:gsLst>",
            "<a:lin ang=\"5400000\"/></a:gradFill>",
        ].joined()
        XCTAssertEqual(PptxExporter.fillXML(el.fill, opacity: 1), expected)
    }

    func testALineHasItsDashAndEnds() {
        var el = Element.line(w: 300)
        el.x = 10; el.y = 20; el.h = 8
        el.dash = "dashed"
        el.endCap = "arrow"
        el.startCap = "dot"
        let xml = slide(onePage([el])).xml
        XCTAssertTrue(xml.contains("<a:off x=\"95250\" y=\"228600\"/><a:ext cx=\"2857500\" cy=\"0\"/>"), xml)
        XCTAssertTrue(xml.contains("<a:prstGeom prst=\"line\">"))
        let ends = "<a:prstDash val=\"dash\"/><a:headEnd type=\"oval\"/><a:tailEnd type=\"triangle\"/></a:ln>"
        XCTAssertTrue(xml.contains("<a:ln w=\"38100\" cap=\"rnd\">"))
        XCTAssertTrue(xml.contains(ends))

        el.flipH = true
        XCTAssertTrue(slide(onePage([el])).xml.contains("<a:headEnd type=\"triangle\"/><a:tailEnd type=\"oval\"/>"))
    }

    // MARK: pictures, backgrounds, links, notes, transitions

    /// A picture has room round it for its border: half the border's width.
    func testAPictureReachesPastItsBoxByItsBorder() {
        var el = Element.image("asset:x", w: 100, h: 100)
        el.x = 50; el.y = 50
        el.stroke = "#000000"
        el.strokeWidth = 20
        XCTAssertEqual(PptxExporter.margin(el), 10)
        let xml = slide(onePage([el])).xml
        XCTAssertTrue(xml.contains("<a:off x=\"381000\" y=\"381000\"/><a:ext cx=\"1143000\" cy=\"1143000\"/>"), xml)
    }

    /// A gradient or photo behind the page is a picture filling the slide,
    /// the first thing on it; the pictures are numbered on from it.
    func testABackgroundPictureFillsTheSlideFirst() {
        let paint = Paint(kind: "gradient", color: nil, angle: 0,
                          stops: [GradientStop(offset: 0, color: "#ff0000"), GradientStop(offset: 1, color: "#0000ff")])
        let d = onePage([Element.sticker("🎉")], background: .gradient(paint))
        let parts = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 4)
        XCTAssertEqual(parts.media.map(\.name), ["image4.jpeg", "image5.png"])
        XCTAssertEqual(parts.media.first?.source, .background)
        XCTAssertFalse(parts.xml.contains("<p:bg>"))
        let picture = "<p:cNvPr id=\"2\" name=\"Background\"/>"
        XCTAssertTrue(parts.xml.contains(picture), parts.xml)
        XCTAssertTrue(parts.xml.contains("<a:off x=\"0\" y=\"0\"/><a:ext cx=\"7620000\" cy=\"5715000\"/>"))
        XCTAssertTrue(parts.rels.contains("Target=\"../media/image4.jpeg\""))
    }

    /// A link to follow is a click on the element, its relationship before
    /// the picture's; anything else is no link.
    func testALinkIsAClickOnTheElement() {
        var photo = Element.image("asset:x")
        photo.link = "https://example.com/?a=1&b=2"
        photo.altText = "A \"view\""
        var script = Element.shape("rect")
        script.link = "javascript:alert(1)"
        let parts = slide(onePage([photo, script]))
        XCTAssertTrue(parts.xml.contains("descr=\"A &quot;view&quot;\"><a:hlinkClick r:id=\"rId2\"/></p:cNvPr>"), parts.xml)
        XCTAssertTrue(parts.xml.contains("<a:blip r:embed=\"rId3\"/>"))
        XCTAssertTrue(parts.rels.contains("Target=\"https://example.com/?a=1&amp;b=2\" TargetMode=\"External\"/>"), parts.rels)
        XCTAssertFalse(parts.rels.contains("javascript"))
        XCTAssertEqual(parts.xml.components(separatedBy: "hlinkClick").count - 1, 1)
    }

    func testNotesBecomeANotesSlide() {
        var d = onePage([])
        d.pages[0].notes = "  Say hello\nto <everyone> & smile \n"
        let parts = slide(d)
        let notes = parts.notes ?? ""
        XCTAssertTrue(notes.contains("<a:t>Say hello</a:t>"), notes)
        XCTAssertTrue(notes.contains("<a:t>to &lt;everyone&gt; &amp; smile</a:t>"))
        XCTAssertTrue(isWellFormed(notes))
        XCTAssertTrue(parts.rels.hasSuffix("Target=\"../notesSlides/notesSlide1.xml\"/></Relationships>"))
        XCTAssertTrue(isWellFormed(PptxExporter.notesRels(slide: 1)))

        d.pages[0].notes = " \n "
        XCTAssertNil(slide(d).notes)
    }

    /// A slide comes in the way the page before it gives way; the first
    /// comes in with none.
    func testTransitionsFadePushAndCut() {
        var d = Design(title: "Deck", width: 800, height: 600)
        d.pages = [Page(), Page(), Page(), Page()]
        d.pages[0].transition = "push"
        d.pages[2].transition = "cut"
        let slides = PptxExporter.deck(design: d, indices: [0, 1, 2, 3])
        XCTAssertFalse(slides[0].xml.contains("<p:transition>"))
        XCTAssertTrue(slides[1].xml.hasSuffix("<p:transition><p:push/></p:transition></p:sld>"))
        XCTAssertTrue(slides[2].xml.contains("<p:transition><p:fade/></p:transition>"))
        XCTAssertTrue(slides[3].xml.contains("<p:transition><p:cut/></p:transition>"))
        d.pages[0].transition = "zoom"
        XCTAssertFalse(PptxExporter.deck(design: d, indices: [0, 1])[1].xml.contains("<p:transition>"))
    }

    // MARK: the package

    func testEveryFixedPartIsWellFormed() {
        let d = fixture()
        var withNotes = d
        withNotes.pages[0].notes = "Hi"
        let slides = PptxExporter.deck(design: withNotes, indices: [0])
        for part in PptxExporter.packageParts(design: withNotes, slides: slides) {
            XCTAssertTrue(isWellFormed(part.xml), part.name)
        }
        XCTAssertTrue(PptxExporter.contentTypes(slides: slides).contains(
            "<Override PartName=\"/ppt/notesSlides/notesSlide1.xml\" "
                + "ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml\"/>"))
        XCTAssertTrue(PptxExporter.presentationRels(slides: 1, notes: true).contains(
            "Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster\""))
        XCTAssertEqual(PptxExporter.mimeType,
                       "application/vnd.openxmlformats-officedocument.presentationml.presentation")
    }

    /// The file: the content types first, then the package's parts, then
    /// each slide with its relationships, notes and pictures — a hidden page
    /// left out of All pages, as the PDF leaves it — every entry intact.
    func testTheZipListsItsEntriesInTheRequiredOrder() async throws {
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
            "ppt/slides/slide1.xml", "ppt/slides/_rels/slide1.xml.rels", "ppt/media/image1.png",
            "ppt/slides/slide2.xml", "ppt/slides/_rels/slide2.xml.rels",
            "ppt/notesSlides/notesSlide2.xml", "ppt/notesSlides/_rels/notesSlide2.xml.rels",
            "ppt/media/image2.png",
        ]
        XCTAssertEqual(entries.map(\.name), expected)
        let slides = PptxExporter.deck(design: d, indices: [0, 2])
        XCTAssertEqual(PptxExporter.entryNames(design: d, slides: slides), expected)
        for entry in entries where entry.name.hasSuffix(".xml") || entry.name.hasSuffix(".rels") {
            XCTAssertTrue(isWellFormed(String(decoding: entry.data, as: UTF8.self)), entry.name)
        }
        // The pictures are PNGs.
        for entry in entries where entry.name.hasPrefix("ppt/media/") {
            XCTAssertEqual(Array(entry.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], entry.name)
        }
        let slide1 = entries.first { $0.name == "ppt/slides/slide1.xml" }.map { String(decoding: $0.data, as: UTF8.self) }
        XCTAssertEqual(slide1, slides[0].xml)
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
