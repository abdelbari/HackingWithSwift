// Barcodes and QR content and style, the shared encode fixtures both phones
// run (the Android twin's BarcodesTest): the bars each kind makes, the
// reasons a payload is refused, the payload each QR form makes, the module
// matrices at each error correction level, the styled code's shapes — and
// codes read back by Vision, as a phone camera would, where it can read.

import XCTest
import UIKit
@testable import Canvia

final class BarcodesTests: XCTestCase {

    private func widths(_ kind: Barcodes.Symbology, _ text: String) -> [Int] {
        Barcodes.encode(kind, text).widths ?? []
    }

    private func code(_ kind: Barcodes.Symbology, _ text: String, w: Double = 600, h: Double = 200) -> Element {
        .image(Barcodes.source(kind, text), w: w, h: h)
    }

    // MARK: the shared encode table

    func testEAN13AndUPCAMakeTheStandardBarsTheirCheckDigitWorkedOutOrChecked() {
        let ean = Barcodes.encode(.ean13, "590123412345")
        XCTAssertEqual(ean.readable, "5901234123457")
        XCTAssertEqual(ean.widths, [1, 1, 1, 3, 1, 1, 2, 1, 1, 2, 3, 1, 2, 2, 2, 2, 1, 2, 2, 1, 4, 1, 1, 2, 3, 1, 1, 1, 1, 1,
                                    1, 1, 2, 2, 2, 1, 2, 1, 2, 2, 1, 4, 1, 1, 1, 1, 3, 2, 1, 2, 3, 1, 1, 3, 1, 2, 1, 1, 1])
        XCTAssertEqual(widths(.ean13, "590123412345").reduce(0, +), 95)
        XCTAssertEqual(Barcodes.encode(.ean13, "5901234123457"), ean)
        XCTAssertEqual(Barcodes.encode(.ean13, "590-1234 12345 7"), ean)
        let upc = Barcodes.encode(.upca, "03600029145")
        XCTAssertEqual(upc.readable, "036000291452")
        XCTAssertEqual(upc.widths, [1, 1, 1, 3, 2, 1, 1, 1, 4, 1, 1, 1, 1, 1, 4, 3, 2, 1, 1, 3, 2, 1, 1, 3, 2, 1, 1, 1, 1, 1,
                                    1, 1, 2, 1, 2, 2, 3, 1, 1, 2, 2, 2, 2, 1, 1, 1, 3, 2, 1, 2, 3, 1, 2, 1, 2, 2, 1, 1, 1])
    }

    func testCode39IsStarsRoundItsCharactersAWideElementThreeNarrow() {
        let c = Barcodes.encode(.code39, "ab-1")
        XCTAssertEqual(c.readable, "AB-1")
        // Star, four characters, star: 9 elements each and a gap between.
        XCTAssertEqual(c.widths?.count, 6 * 9 + 5)
        XCTAssertEqual(c.widths.map { Array($0.prefix(9)) }, [1, 3, 1, 1, 3, 1, 3, 1, 1])
        XCTAssertEqual(c.widths?.reduce(0, +), 6 * (6 + 3 * 3) + 5)
    }

    func testCode128PicksBOrCByTheSharedRule() {
        let table: [(String, [Int])] = [
            ("Canvia", [104, 35, 65, 78, 86, 73, 65, 57]),
            ("123456", [105, 12, 34, 56, 44]),
            ("12345", [104, 17, 99, 23, 45, 53]),
            ("AB12CD", [104, 33, 34, 17, 18, 35, 36, 101]),
            ("No.123456", [104, 46, 79, 14, 99, 12, 34, 56, 63]),
        ]
        for (text, values) in table { XCTAssertEqual(Barcodes.code128Values(text), values, text) }
        // Six modules a symbol, thirteen for the stop.
        XCTAssertEqual(widths(.code128, "123456").reduce(0, +), 5 * 11 + 13)
    }

    func testAnInvalidPayloadSaysWhy() throws {
        let table: [(Barcodes.Symbology, String, String)] = [
            (.ean13, "12345", "EAN-13 needs 12 or 13 digits"),
            (.ean13, "5901234123450", "The check digit should be 7"),
            (.upca, "12AB", "UPC-A needs 11 or 12 digits"),
            (.code39, "a_b", "Code 39 takes A–Z, 0–9, spaces and - . $ / + %"),
            (.code128, "café", "Code 128 takes only the letters, digits and signs on a keyboard"),
            (.code128, "", "Type something to encode"),
            (.code39, String(repeating: "X", count: 81), "That is too long for a barcode"),
        ]
        for (kind, text, reason) in table {
            XCTAssertEqual(Barcodes.encode(kind, text), .invalid(reason), "\(kind) \(text)")
        }
        // The reason is the caption where the bars would be.
        let v = try XCTUnwrap(Barcodes.vector(code(.ean13, "12345")))
        XCTAssertTrue(v.bars.isEmpty)
        XCTAssertEqual(v.caption, "EAN-13 needs 12 or 13 digits")
    }

    // MARK: the element

    func testABarcodeIsAPhotoWhoseSrcSaysItsKindAndPayload() throws {
        let src = Barcodes.source(.code128, "A: 1/2 é")
        XCTAssertEqual(src, "barcode:code128:A%3A%201%2F2%20%C3%A9")
        XCTAssertEqual(Barcodes.parse(src)?.kind, .code128)
        XCTAssertEqual(Barcodes.parse(src)?.payload, "A: 1/2 é")
        XCTAssertNil(Barcodes.parse("barcode:qr:1"))
        XCTAssertNil(Barcodes.parse("qr:hello"))
        XCTAssertTrue(CodeGenerator.isCode(src))
        XCTAssertTrue(CodeGenerator.isCode("qr:x"))
        XCTAssertFalse(CodeGenerator.isCode("media:a"))
        let el = code(.ean13, "5901234123457")
        XCTAssertTrue(Barcodes.showsText(el))
        var bare = el
        bare.barcodeText = false
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(bare), encoding: .utf8))
        XCTAssertTrue(json.contains(#""barcodeText":false"#), json)
        XCTAssertFalse(Barcodes.showsText(try JSONDecoder().decode(Element.self, from: Data(json.utf8))))
        XCTAssertFalse(try XCTUnwrap(String(data: JSONEncoder().encode(el), encoding: .utf8)).contains("barcodeText"))
        XCTAssertEqual(ElementNames.name(of: el), "EAN-13 barcode")
    }

    func testTheSharedLayoutBarsAcrossTheFrameWordsInItsLowestFifth() throws {
        let v = try XCTUnwrap(Barcodes.vector(code(.ean13, "5901234123457", w: 309, h: 150)))
        // 95 modules and 4 either side: 3 px a module.
        XCTAssertEqual(v.bars.count, 30)
        XCTAssertEqual(v.bars.first, CGRect(x: 12, y: 12, width: 3, height: 96))
        XCTAssertEqual(v.caption, "5901234123457")
        XCTAssertEqual(v.captionBox, CGRect(x: 0, y: 108, width: 309, height: 30))
        XCTAssertEqual(v.fontSize, 22.5)
        var bare = code(.ean13, "5901234123457", w: 309, h: 150)
        bare.barcodeText = false
        let without = try XCTUnwrap(Barcodes.vector(bare))
        XCTAssertNil(without.caption)
        XCTAssertEqual(without.bars.first?.height, 126)
    }

    func testEveryKindReadsBackAsItWasWritten() throws {
        let table: [(Element, String)] = [
            (code(.ean13, "590123412345"), "5901234123457"),
            (code(.upca, "03600029145"), "036000291452"),
            (code(.code39, "Canvia-39"), "CANVIA-39"),
            (code(.code128, "No.123456"), "No.123456"),
            (code(.code128, "Canvia 2026!", w: 900), "Canvia 2026!"),
        ]
        for (el, words) in table {
            let picture = try XCTUnwrap(Barcodes.picture(of: el, scale: 3))
            guard let read = TextRecognizer.codePayload(in: picture) else {
                throw XCTSkip("Vision found no barcode in this environment")
            }
            // A UPC-A is an EAN-13 led by 0, which some readers report so.
            XCTAssertTrue(read == words || read == "0" + words, "\(read) for \(words)")
        }
    }

    // MARK: QR content

    func testEachQRFormMakesItsStandardPayload() {
        func form(_ kind: QRForms.ContentType, _ fields: [String: String]) -> String {
            QRForms.payload(QRForms.Form(kind: kind, fields: fields))
        }
        XCTAssertEqual(form(.link, ["url": " https://canvia.app "]), "https://canvia.app")
        XCTAssertEqual(form(.text, ["text": " two words "]), " two words ")
        XCTAssertEqual(form(.wifi, ["ssid": "Cafe;Bar", "password": "pa:ss"]), "WIFI:T:WPA;S:Cafe\\;Bar;P:pa\\:ss;H:false;;")
        XCTAssertEqual(form(.wifi, ["ssid": "Guest", "security": "nopass", "hidden": "true"]), "WIFI:T:nopass;S:Guest;P:;H:true;;")
        XCTAssertEqual(form(.contact, ["first": "Ada", "last": "Lovelace", "org": "Engines, Ltd", "phone": "+44 20 1234"]),
                       "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Lovelace;Ada\r\nFN:Ada Lovelace\r\nORG:Engines\\, Ltd\r\nTEL:+44 20 1234\r\nEND:VCARD")
        XCTAssertEqual(form(.email, ["to": "hi@canvia.app", "subject": "Hello there", "body": "A&B"]),
                       "mailto:hi@canvia.app?subject=Hello%20there&body=A%26B")
        XCTAssertEqual(form(.email, ["to": "hi@canvia.app", "body": "x"]), "mailto:hi@canvia.app?body=x")
        XCTAssertEqual(form(.sms, ["number": "+15550100", "message": "See you at 6"]), "SMSTO:+15550100:See you at 6")
        XCTAssertEqual(form(.phone, ["number": "+15550100"]), "tel:+15550100")
        XCTAssertEqual(QRForms.ContentType.allCases.map(\.rawValue), ["link", "text", "wifi", "contact", "email", "sms", "phone"])
    }

    func testAQRFormIsKeptBesideItsPayloadAndNamesTheCode() throws {
        let form = QRForms.Form(kind: .wifi, fields: ["ssid": "Guest", "password": "", "security": "WPA"])
        let el = QRForms.with(.image(CodeGenerator.source(for: QRForms.payload(form))), form)
        XCTAssertEqual(el.qrForm, QRFormFields(type: "wifi", fields: ["ssid": "Guest", "security": "WPA"]))
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(el), encoding: .utf8))
        XCTAssertTrue(json.contains(#""type":"wifi""#), json)
        let back = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertEqual(QRForms.form(of: back), QRForms.Form(kind: .wifi, fields: ["ssid": "Guest", "security": "WPA"]))
        XCTAssertEqual(ElementNames.name(of: el), "Wi-Fi QR code")
        XCTAssertEqual(ElementNames.name(of: QRForms.with(el, nil)), "QR code")
        XCTAssertTrue(QRForms.isFilled(form))
        XCTAssertFalse(QRForms.isFilled(QRForms.Form(kind: .phone, fields: [:])))
        // As the Android twin writes it, a field that is no words left out.
        let android = #"{"type":"image","src":"qr:tel:1","qrForm":{"type":"phone","fields":{"number":"1","x":3}}}"#
        let read = try JSONDecoder().decode(Element.self, from: Data(android.utf8))
        XCTAssertEqual(QRForms.form(of: read), QRForms.Form(kind: .phone, fields: ["number": "1"]))
    }

    // MARK: QR style

    /// Shared with the Android twin: 1,500 bytes fit at L, M and Q but not
    /// at H, so a correction of H or a logo (which makes it H) is refused,
    /// while any other change, a short code and a barcode are not.
    func testACorrectionOrLogoTheWordsNoLongerFitAtIsRefused() {
        let long = Element.image(CodeGenerator.source(for: String(repeating: "x", count: 1500)))
        func look(ec: String = CodeGenerator.defaultLevel, logo: String? = nil, color: String = CodeGenerator.defaultColor) -> CodeGenerator.Look {
            var out = CodeGenerator.Look()
            out.ec = ec
            out.logo = logo
            out.color = color
            return out
        }
        XCTAssertTrue(CodeGenerator.holds(long, look(ec: "L")))
        XCTAssertTrue(CodeGenerator.holds(long, look(ec: "Q")))
        XCTAssertFalse(CodeGenerator.holds(long, look(ec: "H")))
        XCTAssertFalse(CodeGenerator.holds(long, look(logo: "media:logo")))
        XCTAssertTrue(CodeGenerator.holds(long, look(color: "#ff0000")))
        XCTAssertTrue(CodeGenerator.holds(Element.image(CodeGenerator.source(for: "hi")), look(logo: "media:logo")))
        XCTAssertTrue(CodeGenerator.holds(Element.image("barcode:code128:A1"), look(ec: "H")))
    }

    func testTheStyleKeysAreWrittenOnlyWhenNotTheDefaultAndALogoMakesTheLevelH() throws {
        let plain = Element.image(CodeGenerator.source(for: "https://canvia.app"))
        var look = CodeGenerator.Look()
        look.dots = "round"
        look.eyes = "circle"
        look.ec = "Q"
        let styled = CodeGenerator.styled(plain, look)
        XCTAssertEqual([styled.qrDots, styled.qrEyes, styled.qrEc, styled.qrLogo], ["round", "circle", "Q", nil])
        XCTAssertEqual(CodeGenerator.style(of: styled), look)
        var withLogo = CodeGenerator.Look()
        withLogo.logo = "media:logo"
        let logo = CodeGenerator.styled(plain, withLogo)
        XCTAssertEqual(logo.qrEc, "H")
        XCTAssertEqual(CodeGenerator.style(of: logo).level, "H")
        let back = CodeGenerator.styled(styled, CodeGenerator.Look())
        XCTAssertEqual([back.qrDots, back.qrEyes, back.qrEc, back.qrLogo], [nil, nil, nil, nil])
        // A value this build does not know reads as the default.
        let odd = #"{"type":"image","src":"qr:A","qrDots":"hearts","qrEc":"Z"}"#
        let read = try JSONDecoder().decode(Element.self, from: Data(odd.utf8))
        XCTAssertEqual(CodeGenerator.style(of: read).dots, CodeGenerator.square)
        XCTAssertEqual(CodeGenerator.style(of: read).ec, CodeGenerator.defaultLevel)
    }

    /// The error correction level a code's format information names
    /// (ISO/IEC 18004, 7.9): its 15 bits beside the top-left finder, most
    /// significant first, unmasked — the same from any encoder, whatever
    /// data mask it chose.
    private func levelOf(_ grid: [[Bool]]) -> String {
        let row: [(x: Int, y: Int)] = [(0, 8), (1, 8), (2, 8), (3, 8), (4, 8), (5, 8), (7, 8), (8, 8), (8, 7)]
        let column: [(x: Int, y: Int)] = (0...5).reversed().map { (x: 8, y: $0) }
        var bits = 0
        for p in row + column { bits = (bits << 1) | (grid[p.y][p.x] ? 1 : 0) }
        bits ^= 0x5412
        return ["M", "L", "H", "Q"][bits >> 13]
    }

    /// Whether `grid` has the patterns the standard fixes: the three
    /// finders, the timing rows and the dark module by the bottom left.
    private func hasTheFixedPatterns(_ grid: [[Bool]]) -> Bool {
        let n = grid.count
        for (ox, oy) in [(0, 0), (n - 7, 0), (0, n - 7)] {
            for dy in 0..<7 {
                for dx in 0..<7 where grid[oy + dy][ox + dx] != (max(abs(dx - 3), abs(dy - 3)) != 2) { return false }
            }
        }
        for i in 8..<(n - 8) where grid[6][i] != (i % 2 == 0) || grid[i][6] != (i % 2 == 0) { return false }
        return grid[n - 8][8]
    }

    func testTheSharedModuleMatricesAtEachLevel() throws {
        // The size of "https://canvia.app" at L, M, Q and H, its fixed
        // patterns and the level its format names — what the standard fixes,
        // not the dark modules' count, which follows the encoder's mask.
        let table: [(String, Int)] = [("L", 25), ("M", 25), ("Q", 25), ("H", 29)]
        XCTAssertEqual(CodeGenerator.levels, table.map { $0.0 })
        for (level, size) in table {
            guard let grid = CodeGenerator.modules(for: "https://canvia.app", level: level) else {
                throw XCTSkip("no code generator")
            }
            XCTAssertEqual(grid.count, size, level)
            XCTAssertTrue(hasTheFixedPatterns(grid), level)
            XCTAssertEqual(levelOf(grid), level)
        }
        XCTAssertTrue(CodeGenerator.isFinder(x: 6, y: 6, n: 25))
        XCTAssertTrue(CodeGenerator.isFinder(x: 18, y: 0, n: 25))
        XCTAssertTrue(CodeGenerator.isFinder(x: 0, y: 18, n: 25))
        XCTAssertFalse(CodeGenerator.isFinder(x: 18, y: 18, n: 25))
        XCTAssertFalse(CodeGenerator.isFinder(x: 7, y: 7, n: 25))
    }

    func testRoundDotsStyledEyesAndALogoStillScan() throws {
        let payload = "https://canvia.app/q?id=42"
        var looks: [CodeGenerator.Look] = []
        for dots in CodeGenerator.dotShapes {
            for eyes in CodeGenerator.eyeShapes {
                var look = CodeGenerator.Look()
                look.dots = dots
                look.eyes = eyes
                looks.append(look)
            }
        }
        var logo = CodeGenerator.Look()
        logo.dots = "rounded"
        logo.eyes = "rounded"
        logo.logo = "media:no-such-logo"
        looks.append(logo)
        for look in looks {
            guard let picture = CodeGenerator.qr(payload, side: 600, style: look) else { throw XCTSkip("no code generator") }
            guard let read = TextRecognizer.codePayload(in: picture) else {
                throw XCTSkip("Vision found no barcode in this environment")
            }
            XCTAssertEqual(read, payload, "\(look.dots) \(look.eyes)")
        }
    }

    func testTheEyesAreDrawnAsTheirOwnShapesRingsWithHoles() throws {
        guard let grid = CodeGenerator.modules(for: "Canvia") else { throw XCTSkip("no code generator") }
        var circles = CodeGenerator.Look()
        circles.eyes = "circle"
        let marks = CodeGenerator.marks(grid, style: circles)
        let rings = marks.filter { !$0.hole.isEmpty }
        XCTAssertEqual(rings.count, 3)
        XCTAssertEqual(rings.first?.box, CGRect(x: 0, y: 0, width: 7, height: 7))
        XCTAssertEqual(rings.first?.kind, .oval)
        // No dot inside a finder.
        XCTAssertFalse(marks.filter { $0.hole.isEmpty && $0.box.width < 3 }
            .contains { CodeGenerator.isFinder(x: Int($0.box.minX), y: Int($0.box.minY), n: grid.count) })
        // Square dots and eyes are the runs, exactly as before.
        XCTAssertEqual(CodeGenerator.marks(grid, style: CodeGenerator.Look()).map(\.box), CodeGenerator.runs(grid))
        let square = CodeGenerator.CodeMark(kind: .rect, box: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(CodeGenerator.svgData(CodeGenerator.outline([square])), "M0 0L1 0L1 1L0 1L0 0Z")
        // A hole is wound the other way round, so either fill rule leaves it open.
        let ring = CodeGenerator.outline([CodeGenerator.CodeMark(kind: .rect, box: CGRect(x: 0, y: 0, width: 3, height: 3),
                                                                  hole: [CodeGenerator.CodeMark(kind: .rect, box: CGRect(x: 1, y: 1, width: 1, height: 1))])])
        XCTAssertEqual(CodeGenerator.svgData(ring), "M0 0L3 0L3 3L0 3L0 0ZM1 1L1 2L2 2L2 1L1 1Z")
    }

    func testALogoTooLargeOrFaintRoundDotsAreWarnedOf() {
        var logo = CodeGenerator.Look()
        logo.logo = "media:logo"
        let small = CodeGenerator.styled(.image(CodeGenerator.source(for: "A")), logo)
        guard let grid = CodeGenerator.modules(of: small) else { return }
        XCTAssertEqual(grid.count, 21)
        XCTAssertTrue(CodeGenerator.risks(small, pageBehind: "#ffffff").contains(CodeGenerator.logoRisk))
        let big = CodeGenerator.styled(.image(CodeGenerator.source(for: "https://canvia.app")), logo)
        XCTAssertFalse(CodeGenerator.risks(big, pageBehind: "#ffffff").contains(CodeGenerator.logoRisk))
        var grey = CodeGenerator.Look()
        grey.color = "#888888"
        grey.dots = "round"
        let faint = CodeGenerator.styled(.image(CodeGenerator.source(for: "A")), grey)
        XCTAssertEqual(CodeGenerator.risks(faint, pageBehind: "#ffffff"), [CodeGenerator.dotsRisk])
        grey.dots = CodeGenerator.square
        XCTAssertEqual(CodeGenerator.risks(CodeGenerator.styled(faint, grey), pageBehind: "#ffffff"), [])
        XCTAssertEqual(CodeGenerator.logoRisk, "Logo too large")
        XCTAssertEqual(CodeGenerator.dotsRisk, "Low contrast dots")
    }

    func testAStyledCodeIsAnOutlineInEveryVectorAndALogoAPictureInPowerPoint() throws {
        var look = CodeGenerator.Look()
        look.dots = "round"
        var el = CodeGenerator.styled(.image(CodeGenerator.source(for: "https://canvia.app"), w: 300, h: 300), look)
        guard let v = CodeGenerator.vector(el) else { throw XCTSkip("no code generator") }
        XCTAssertTrue(v.modules.isEmpty)
        XCTAssertFalse(v.marks.isEmpty)
        XCTAssertNil(v.logoPad)
        XCTAssertTrue(SVGExporter.codeMarkup(el, v).contains("fill-rule=\"evenodd\""))
        XCTAssertEqual(PptxExporter.form(of: el), .code)
        look.logo = "media:logo"
        el = CodeGenerator.styled(el, look)
        let pad = try XCTUnwrap(CodeGenerator.vector(el)?.logoPad)
        XCTAssertEqual(pad.width, pad.height)
        XCTAssertEqual(PptxExporter.form(of: el), .picture)
        // A barcode goes out as rectangles and words.
        XCTAssertEqual(PptxExporter.form(of: code(.code128, "Canvia")), .code)
    }
}
