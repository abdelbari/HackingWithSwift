// Heading roles (TextRoles), the tagged PDF's structure (PdfTags) and how
// the update writes it (PDFUpdate), and the headings check — over the shared
// fixture Fixtures/pdf-tags.json, which the Android twin's PdfTagsTest
// reads too.

import XCTest
@testable import Canvia

final class PdfTagsTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("pdf-tags") }

    private func design() throws -> Design {
        try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(fixture()["design"])))
    }

    /// Shared: the same structure outline on both phones.
    func testTheSharedDesignGivesTheSharedOutline() throws {
        let expected = try XCTUnwrap(fixture()["outline"] as? [String]).joined(separator: "\n")
        XCTAssertEqual(PdfTags.outline(try design()), expected)
    }

    /// Shared: each text's role, written or inferred by size rank.
    func testRolesAreTheWrittenOnesElseBySizeRank() throws {
        let d = try design()
        let roles = try XCTUnwrap(fixture()["roles"] as? [String: String])
        let byId = Dictionary(d.pages.flatMap(\.elements).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, role) in roles {
            XCTAssertEqual(TextRoles.of(try XCTUnwrap(byId[id]), in: d), role, id)
        }
        // Not text: no role.
        XCTAssertNil(TextRoles.of(try XCTUnwrap(byId["e4"]), in: d))
    }

    /// Shared: the web page's hidden text layer for the first page.
    func testTheWebPagesTextLayerHasRealHeadings() throws {
        let d = try design()
        XCTAssertEqual(HTMLExporter.textLayer(d, page: d.pages[0]), try XCTUnwrap(fixture()["textLayer"] as? String))
        XCTAssertEqual(HTMLExporter.textLayer(d, page: Page()), "")
    }

    func testInferenceRanksHeadingSizesAndNeverGuessesATitle() {
        let sizes = [96.0, 64, 48, 40]
        XCTAssertEqual(TextRoles.inferred(96, headingSizes: sizes), TextRoles.h1)
        XCTAssertEqual(TextRoles.inferred(64, headingSizes: sizes), TextRoles.h2)
        XCTAssertEqual(TextRoles.inferred(48, headingSizes: sizes), TextRoles.h3)
        XCTAssertEqual(TextRoles.inferred(40, headingSizes: sizes), TextRoles.h3)
        XCTAssertEqual(TextRoles.inferred(31.9, headingSizes: sizes), TextRoles.body)
        XCTAssertEqual(TextRoles.inferred(DesignStore.headingSize - 1, headingSizes: []), TextRoles.body)
        XCTAssertEqual(TextRoles.inferred(DesignStore.headingSize, headingSizes: [DesignStore.headingSize]), TextRoles.h1)
    }

    func testAddTextWritesTheBrandRolesTextRole() throws {
        XCTAssertEqual(BrandFonts.Role.allCases.map(TextRoles.forBrandRole),
                       ["title", "body", "h1", "h2", "body", "body", "quote", "caption"])
        let el = TextRoles.with(Element.text("Hi"), TextRoles.h2)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
        XCTAssertEqual(json["textRole"] as? String, "h2")
        XCTAssertNil(TextRoles.with(el, nil).textRole)
        // A key that does not read is Auto, and kept as it was.
        var odd = el
        odd.textRole = "h9"
        XCTAssertNil(TextRoles.stored(odd))
        let read = TextRoles.withReadAs(Element.text("Hi"), TextRoles.readArtifact)
        XCTAssertEqual(read.a11yRole, "artifact")
        var d = Design()
        d.pages = [Page(elements: [read])]
        XCTAssertFalse(TextRoles.isHeading(read, in: d))
        XCTAssertEqual(TextRoles.name(nil), "Auto")
        XCTAssertEqual(TextRoles.readAsName(TextRoles.readArtifact), "Not read")
    }

    func testReadAsWinsOverTheRoleAndAList() {
        var list = Element.text("A\nB")
        list.listStyle = "bullet"
        var d = Design()
        d.pages = [Page(elements: [list])]
        XCTAssertEqual(PdfTags.textRole(list, in: d), PdfTags.l)
        XCTAssertEqual(PdfTags.textRole(TextRoles.withReadAs(list, TextRoles.h3), in: d), PdfTags.h3)
        XCTAssertNil(PdfTags.textRole(TextRoles.withReadAs(list, TextRoles.readArtifact), in: d))
        XCTAssertEqual(PdfTags.textRole(TextRoles.with(Element.text("T", fontSize: 12), TextRoles.title), in: d), PdfTags.h1)
    }

    // MARK: sentinels

    private func count(_ pattern: String, in text: String) -> Int {
        (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? 0
    }

    /// Shared: the Android twin's content and its answer.
    func testSentinelsTurnIntoMarkedContent() {
        XCTAssertTrue(PdfTags.sentinelComponents(1) == (1, 0, 1))
        XCTAssertTrue(PdfTags.sentinelComponents(258) == (1, 1, 2))
        XCTAssertEqual(PdfTags.sentinelCode("0.0039", "0.0039", "0.0078"), 258)
        XCTAssertNil(PdfTags.sentinelCode("0", "0", "0.0039"))
        let content = "1 1 1 rg\n0 0 100 100 re\nf\n"
            + "q\n0.0039 0 0.0039 rg\n0 0 0.01 0.01 re\nf\nQ\nBT /F1 12 Tf (Hi) Tj ET\n"
            + "0.0039 0 0.0078 rg\n0 0 0.01 0.01 re\nf\n0 0 1 rg\n5 5 10 10 re\nf\n"
            + "0.0039 0 0.0118 rg\n0 0 0.01 0.01 re\nf\n/Im1 Do\n"
        let roles = ["a": "H1", "c": "Figure"]
        let marked = PdfTags.mark(content, drawn: ["a", "b", "c"], roleOf: { roles[$0] })
        XCTAssertEqual(marked.marked, [PdfTags.Marked(mcid: 0, elementId: "a"), PdfTags.Marked(mcid: 1, elementId: "c")])
        let out = marked.content
        XCTAssertTrue(out.hasPrefix("/Artifact BMC\n1 1 1 rg"))
        XCTAssertTrue(out.contains("/H1 <</MCID 0>> BDC\n"))
        XCTAssertTrue(out.contains("/Figure <</MCID 1>> BDC\n"))
        // The sentinels are gone; the page's own drawing stays.
        XCTAssertFalse(out.contains("0.01 0.01 re"))
        XCTAssertTrue(out.contains("(Hi) Tj") && out.contains("5 5 10 10 re") && out.contains("/Im1 Do"))
        // Balanced: every sequence opened is closed.
        XCTAssertEqual(count(#"\b(BDC|BMC)\b"#, in: out), count(#"\bEMC\b"#, in: out))
        XCTAssertEqual(count(#"\b(BDC|BMC)\b"#, in: out), 4)
    }

    /// Core Graphics sets a fill in the page's colour space with `sc`, and
    /// may draw a rectangle as a path: both are a sentinel's run.
    func testCoreGraphicsSentinelsAreFoundToo() {
        let content = "/Cs1 cs 1 1 1 sc\n0 0 612 792 re\nf\n"
            + "/Cs1 cs 0.0039216 0 0.0039216 sc\n0 0 0.0625 0.0625 re\nf\nBT (Hi) Tj ET\n"
            + "0.0039216 0 0.0078431 scn\n0 0 m\n0.0625 0 l\n0.0625 0.0625 l\nh\nf\n/Im1 Do\n"
        let roles = ["a": "P", "b": "Figure"]
        let marked = PdfTags.mark(content, drawn: ["a", "b"], roleOf: { roles[$0] }, firstMcid: 3)
        XCTAssertEqual(marked.marked.map(\.mcid), [3, 4])
        XCTAssertFalse(marked.content.contains("0.0625"))
        XCTAssertTrue(marked.content.contains("/P <</MCID 3>> BDC\n") && marked.content.contains("/Figure <</MCID 4>> BDC\n"))
        // A run with anything but a path in it is left drawn.
        let text = "0.0039 0 0.0039 rg\nBT (A) Tj ET\nf\n"
        XCTAssertTrue(PdfTags.mark(text, drawn: ["a"], roleOf: { _ in "P" }).marked.isEmpty)
    }

    // MARK: the update

    /// A Quartz- or Skia-shaped PDF whose pages draw sentinels 1…n,
    /// deflated, as the Android twin's test builds it.
    private func pdfWithSentinels(_ pageSentinels: [Int]) throws -> Data {
        var objects = ["<</Producer (Test)>>", "<</Type /Catalog\n/Pages 3 0 R>>"]
        let kids = pageSentinels.indices.map { "\(4 + $0 * 2) 0 R" }.joined(separator: " ")
        objects.append("<</Type /Pages\n/Count \(pageSentinels.count)\n/Kids [\(kids)]>>")
        func c(_ v: Int) -> String { v == 0 ? "0" : String(format: "%.4f", Double(v) / 255) }
        for (p, n) in pageSentinels.enumerated() {
            var plain = "1 1 1 rg\n0 0 1440 810 re\nf\n"
            for k in 0..<n {
                let i = k + 1
                plain += "q\n\(c(1)) \(c(i >> 8)) \(c(i & 0xFF)) rg\n0 0 0.01 0.01 re\nf\nQ\n"
                plain += "0.2 0.2 0.2 rg\n10 \(i * 10) 50 5 re\nf\n"
            }
            let packed = try XCTUnwrap(PDFUpdate.deflated(PDFUpdate.latin1(plain)))
            let data = String(decoding: packed.map { UInt16($0) }, as: UTF16.self)
            objects.append("<</Type /Page\n/Resources <</ProcSet [/PDF /Text]>>\n/MediaBox [0 0 1440 810]\n"
                           + "/Contents \(5 + p * 2) 0 R\n/Parent 3 0 R>>")
            objects.append("<</Filter /FlateDecode\n/Length \(packed.count)>> stream\n\(data)\nendstream")
        }
        var text = "%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n"
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(text.unicodeScalars.count)
            text += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xrefAt = text.unicodeScalars.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { text += String(format: "%010d 00000 n \n", o) }
        text += "trailer\n<</Size \(objects.count + 1)\n/Root 2 0 R\n/Info 1 0 R>>\nstartxref\n\(xrefAt)\n%%EOF"
        return PDFUpdate.latin1(text)
    }

    /// The objects of `pdf`'s last update, by number.
    private func updateObjects(_ pdf: Data, from: Int) -> [Int: String] {
        let tail = String(decoding: pdf.dropFirst(from).map { UInt16($0) }, as: UTF16.self)
        let ns = tail as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(\d+) 0 obj\n(.*?)\nendobj"#, options: .dotMatchesLineSeparators) else { return [:] }
        var out: [Int: String] = [:]
        for m in regex.matches(in: tail, range: NSRange(location: 0, length: ns.length)) {
            if let n = Int(ns.substring(with: m.range(at: 1))) { out[n] = ns.substring(with: m.range(at: 2)) }
        }
        return out
    }

    private func captures(_ pattern: String, in text: String) -> [String] {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// The PAC-style check: marked, a structure tree, every MCID on every
    /// page parented, every figure with /Alt, the pages in structure order.
    func testTheSharedDesignWritesATaggedPDFThatPassesAStructuralCheck() throws {
        let d = try design()
        let tags: [PDFUpdate.PageTags?] = d.visiblePageIndices.map { i in
            PDFUpdate.PageTags(nodes: PdfTags.page(d, d.pages[i]), drawn: d.drawnElements(on: d.pages[i]).map(\.id))
        }
        let pdf = try pdfWithSentinels(tags.map { $0?.drawn.count ?? 0 })
        let metadata = PDFUpdate.Metadata(info: PDFMetadata.info(d, version: "1.0"), lang: "en", tags: tags)
        let out = PDFUpdate.annotated(pdf, metadata: metadata)
        XCTAssertGreaterThan(out.count, pdf.count)
        let objects = updateObjects(out, from: pdf.count)
        let catalog = try XCTUnwrap(objects[2])
        XCTAssertTrue(catalog.contains("/MarkInfo << /Marked true >>"))
        XCTAssertTrue(catalog.contains("/Lang (en)"))
        let root = try XCTUnwrap(captures(#"/StructTreeRoot (\d+) 0 R"#, in: catalog).first.flatMap { Int($0) })
        let tree = try XCTUnwrap(objects[root])
        XCTAssertTrue(tree.contains("/Type /StructTreeRoot") && tree.contains("/RoleMap"))
        let parentNumber = try XCTUnwrap(captures(#"/ParentTree (\d+) 0 R"#, in: tree).first.flatMap { Int($0) })
        let parentTree = try XCTUnwrap(objects[parentNumber])
        // Each page: /StructParents and /Tabs /S, and its stream's MCIDs.
        for (p, pageNumber) in [4, 6].enumerated() {
            let page = try XCTUnwrap(objects[pageNumber])
            XCTAssertTrue(page.contains("/StructParents \(p) /Tabs /S"), page)
            let stream = try XCTUnwrap(objects[pageNumber + 1])
            let start = try XCTUnwrap(stream.range(of: "stream\n")).upperBound
            let end = try XCTUnwrap(stream.range(of: "\nendstream", options: .backwards)).lowerBound
            let packed = Data(stream[start..<end].unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
            let content = String(decoding: try XCTUnwrap(PDFUpdate.inflated(packed)).map { UInt16($0) }, as: UTF16.self)
            let mcids = captures(#"<</MCID (\d+)>> BDC"#, in: content).compactMap { Int($0) }
            XCTAssertEqual(mcids, Array(mcids.indices))
            XCTAssertFalse(mcids.isEmpty)
            XCTAssertEqual(count(#"\b(BDC|BMC)\b"#, in: content), count(#"\bEMC\b"#, in: content))
            // Every MCID parented: the page's entry has one reference each.
            let entry = try XCTUnwrap(captures(#"(?:\[|\] )\#(p) \[([^\]]*)\]"#, in: parentTree).first)
            let refs = captures(#"(\d+) 0 R"#, in: entry).compactMap { Int($0) }
            XCTAssertEqual(refs.count, mcids.count)
            XCTAssertFalse(entry.contains("null"))
            // And each parent holds that MCID among its kids.
            for (mcid, ref) in zip(mcids, refs) {
                let k = try XCTUnwrap(captures(#"/K \[([^\]]*)\]"#, in: try XCTUnwrap(objects[ref])).first)
                XCTAssertTrue(k.split(separator: " ").contains(Substring(String(mcid))))
            }
        }
        // Figures have /Alt; the header cells a scope.
        let elems = objects.values.filter { $0.contains("/Type /StructElem") }
        let figures = elems.filter { $0.contains("/S /Figure") }
        XCTAssertEqual(figures.count, 1)
        XCTAssertTrue(figures.allSatisfy { $0.contains("/Alt <FEFF") })
        XCTAssertEqual(elems.filter { $0.contains("/S /TH ") && $0.contains("/Scope /Column") }.count, 2)
        XCTAssertEqual(elems.filter { $0.contains("/S /Sect") }.count, 2)
    }

    func testAnUntaggedExportIsAsItWas() throws {
        let pdf = try pdfWithSentinels([2])
        let out = PDFUpdate.annotated(pdf, metadata: PDFUpdate.Metadata(info: [("Title", "T")], lang: "en"))
        let catalog = try XCTUnwrap(updateObjects(out, from: pdf.count)[2])
        XCTAssertFalse(catalog.contains("/MarkInfo"))
        XCTAssertFalse(catalog.contains("/StructTreeRoot"))
    }

    func testInflateAndDeflateRoundTrip() throws {
        let plain = PDFUpdate.latin1(String(repeating: "0 0 1 rg 5 5 10 10 re f\n", count: 20_000))
        let packed = try XCTUnwrap(PDFUpdate.deflated(plain))
        XCTAssertLessThan(packed.count, plain.count)
        XCTAssertEqual(PDFUpdate.inflated(packed), plain)
    }

    // MARK: the headings check

    private func text(_ id: String, y: Double, size: Double, role: String? = nil) -> Element {
        var el = Element.text(id, fontSize: size)
        el.id = id
        el.y = y
        return TextRoles.with(el, role)
    }

    func testTheSharedDesignHasNoHeadingsProblem() throws {
        XCTAssertTrue(AccessibilityAudit.headingFindings(try design()).isEmpty)
    }

    func testSkippedHeadingLevelsAreFoundAndFixed() throws {
        var d = Design()
        d.pages = [
            Page(elements: [text("a", y: 0, size: 20, role: "h1"), text("b", y: 300, size: 20, role: "h3"),
                            text("c", y: 600, size: 20, role: "h3")]),
            Page(elements: [text("d", y: 0, size: 20, role: "h2")]),
        ]
        let found = AccessibilityAudit.headingFindings(d)
        XCTAssertEqual(found.map(\.elementId), ["b"])
        XCTAssertEqual(found.first?.message, "Heading levels skip")
        XCTAssertEqual(found.first?.fix, .fixHeadingLevel)
        XCTAssertEqual(AccessibilityAudit.headingFix(d, id: "b"), TextRoles.h2)
        XCTAssertTrue(AccessibilityAudit.findings(d).contains { $0.kind == .headings })
        // Fixed, as one change on the element: its role the level asked for.
        let fixed = AccessibilityAudit.fixed(d, try XCTUnwrap(found.first))
        XCTAssertEqual(fixed.pages[0].elements[1].textRole, "h2")
        XCTAssertTrue(AccessibilityAudit.headingFindings(fixed).isEmpty)
        // The first heading an h2: a skip from nothing.
        var first = Design()
        first.pages = [Page(elements: [text("x", y: 0, size: 20, role: "h2")])]
        XCTAssertEqual(AccessibilityAudit.headingFix(first, id: "x"), TextRoles.h1)
        XCTAssertEqual(AccessibilityAudit.headingFindings(first).map(\.elementId), ["x"])
        let made = AccessibilityAudit.withHeading(TextRoles.withReadAs(text("x", y: 0, size: 20), TextRoles.readP),
                                                  role: TextRoles.h1)
        XCTAssertEqual(TextRoles.stored(made), TextRoles.h1)
        XCTAssertNil(TextRoles.readAs(made))
    }

    func testAMultiPageDesignWithNoHeadingSaysSoASinglePageDoesNot() {
        let pages = [
            Page(elements: [text("small", y: 0, size: 18), text("big", y: 300, size: 24)]),
            Page(elements: [text("more", y: 0, size: 18)]),
        ]
        var d = Design()
        d.pages = pages
        let found = AccessibilityAudit.headingFindings(d)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.message, "No heading on a multi-page PDF")
        XCTAssertEqual(found.first?.elementId, "big")
        XCTAssertEqual(found.first?.fix, .makeHeading)
        d.pages = [pages[0]]
        XCTAssertTrue(AccessibilityAudit.headingFindings(d).isEmpty)
        // A hidden second page does not make it multi-page.
        var hidden = pages[1]
        hidden.hidden = true
        d.pages = [pages[0], hidden]
        XCTAssertTrue(AccessibilityAudit.headingFindings(d).isEmpty)
    }

    // MARK: the setting

    func testPdfTaggedIsOnForAFreshSheetAndOffForASettingWithoutIt() throws {
        let fresh = ExportLast(format: "pdf", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false, pages: "all")
        XCTAssertTrue(fresh.pdfTagged)
        XCTAssertTrue(fresh.json.contains(#""pdfTagged":true"#))
        XCTAssertEqual(ExportLast.read(#"{"format":"pdf"}"#)?.pdfTagged, false)
        XCTAssertEqual(ExportLast.read(fresh.json)?.pdfTagged, true)
        var off = fresh
        off.pdfTagged = false
        XCTAssertEqual(ExportLast.read(off.json)?.pdfTagged, false)
    }
}
