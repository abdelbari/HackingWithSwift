// CMYK for a print shop, as the Android twin's CmykTest has it, table for
// table: one formula from colour to ink, the 300% limit and the 95% black,
// pixels on white paper, the colours that print duller, the colour profile
// remembered, the size note, and the DeviceCMYK PDF itself.

import XCTest
import CoreGraphics
@testable import Canvia

final class CmykTests: XCTestCase {

    // The conversion table both phones run: "#rrggbb" -> C, M, Y, K as bytes.
    func testColoursBecomeInkByOneFormula() throws {
        let table: [(String, [UInt8])] = [
            // Pure black, as text is: black ink alone.
            ("#000000", [0, 0, 0, 255]),
            // Paper.
            ("#ffffff", [0, 0, 0, 0]),
            // Greys are black ink alone: grey replaced in full.
            ("#808080", [0, 0, 0, 127]),
            ("#ff0000", [0, 255, 255, 0]),
            ("#00ff00", [255, 0, 255, 0]),
            ("#0000ff", [255, 255, 0, 0]),
            ("#cc6633", [0, 128, 191, 51]),
            ("#336699", [170, 85, 0, 102]),
            // Almost black: K held to 95%, and the ink to 300% in all —
            // 0.6 more of C, M and Y would be 330%, so they are scaled down.
            ("#010101", [174, 174, 174, 242]),
            // Dark navy, well under the limit, is left as it is.
            ("#0a0a14", [128, 128, 0, 235]),
        ]
        for (hex, expected) in table {
            XCTAssertEqual(try XCTUnwrap(Cmyk.fromHex(hex)).bytes, expected, hex)
        }
        XCTAssertNil(Cmyk.fromHex("#12"))
    }

    func testNoColourTakesMoreThan300PercentOfInkNorMoreThan95PercentBlackButBlackItself() {
        for r in stride(from: 0, through: 255, by: 15) {
            for g in stride(from: 0, through: 255, by: 15) {
                for b in stride(from: 0, through: 255, by: 15) {
                    let ink = Cmyk.fromRGB(r, g, b)
                    XCTAssertLessThanOrEqual(ink.c + ink.m + ink.y + ink.k, Cmyk.inkLimit + 1e-9)
                    if r + g + b > 0 { XCTAssertLessThanOrEqual(ink.k, Cmyk.maxK + 1e-9) }
                }
            }
        }
    }

    func testPixelsAreLaidOnWhitePaperBeforeTheyBecomeInk() {
        let argb: [UInt32] = [
            0xFF00_0000, // opaque black
            0x0000_0000, // clear: paper
            0x8000_0000, // half black: a grey
            0xFFFF_0000,
        ]
        var out = [UInt8](repeating: 0, count: 16)
        Cmyk.convert(argb, from: 0, count: 4, into: &out, at: 0)
        XCTAssertEqual(Array(out[0..<4]), [0, 0, 0, 255])
        XCTAssertEqual(Array(out[4..<8]), [0, 0, 0, 0])
        XCTAssertEqual(Array(out[8..<12]), [0, 0, 0, 128])
        XCTAssertEqual(Array(out[12..<16]), [0, 255, 255, 0])
    }

    // The gamut table: ΔE between a colour and its ink as printed, and
    // whether it warns (above 35).
    func testNeonAndVerySaturatedColoursPrintDullerEverydayOnesDoNot() throws {
        let table: [(String, Double)] = [
            ("#000000", 0), ("#ffffff", 0), ("#808080", 0),
            ("#ff0000", 7.1), ("#ff8800", 3.5), ("#336699", 9.8), ("#8b5cf6", 33.5),
            ("#39ff14", 36.4), ("#00ff00", 44.0), ("#00ffff", 50.5), ("#0000ff", 55.4), ("#ff00ff", 55.6),
        ]
        for (hex, delta) in table {
            XCTAssertEqual(try XCTUnwrap(Cmyk.deltaE(hex)), delta, accuracy: 0.05, hex)
            XCTAssertEqual(Cmyk.outOfGamut(hex), delta > Cmyk.gamutDeltaE, hex)
        }
        var neon = Design(title: "n", width: 400, height: 300)
        var words = Element.text("Hi")
        words.color = "#39ff14"
        neon.pages = [Page(background: .color("#ffffff"), elements: [words])]
        XCTAssertEqual(Cmyk.dullerColours(neon), ["#39ff14"])
        var calm = Design(title: "c", width: 400, height: 300)
        var shape = Element.shape("rectangle")
        shape.fill = .solid("#336699")
        calm.pages = [Page(elements: [shape])]
        XCTAssertTrue(Cmyk.dullerColours(calm).isEmpty)
        XCTAssertEqual(Cmyk.dullerWarning, "Bright colours will print duller")
    }

    func testTheColourProfileIsRememberedAsRgbOrCmykRgbByDefault() throws {
        XCTAssertEqual(PrintLayout.ColourProfile.of("cmyk"), .cmyk)
        XCTAssertEqual(PrintLayout.ColourProfile.of(nil), .rgb)
        XCTAssertEqual(PrintLayout.ColourProfile.of("lab"), .rgb)
        XCTAssertEqual(PrintLayout.Options().colourProfile, .rgb)
        let kept = ExportLast(format: "print", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                              pages: "all", colourProfile: "cmyk")
        XCTAssertEqual(try XCTUnwrap(ExportLast.read(kept.json)).colourProfile, "cmyk")
        // Round 31's web page settings are written after it, as on Android.
        XCTAssertTrue(kept.json.hasSuffix(
            #","colourProfile":"cmyk","html":{"nav":true,"mobileStack":true,"embedMedia":true},"zip":false,"pngCompress":false,"pdfTagged":true}"#))
        let odd = kept.json.replacingOccurrences(of: "cmyk", with: "hsv")
        XCTAssertEqual(try XCTUnwrap(ExportLast.read(odd)).colourProfile, "rgb")
        let older = try XCTUnwrap(ExportLast.read(#"{"format":"pdf","scale":2,"longEdge":null,"jpegQuality":0.85,"transparent":false,"pages":"all"}"#))
        XCTAssertEqual(older.colourProfile, "rgb")
    }

    func testTheSizeNoteCountsASheetAt300DpiFourBytesAPixelPackedToHalf() {
        let px = CmykPdf.pixels(CGSize(width: 612, height: 792))
        XCTAssertEqual(px.width, 2550)
        XCTAssertEqual(px.height, 3300)
        XCTAssertEqual(CmykPdf.estimatedBytes(sheets: 1, size: CGSize(width: 612, height: 792)), 16_830_000)
        XCTAssertEqual(CmykPdf.note(24_400_000), "CMYK · flattened · about 24 MB")
        XCTAssertEqual(CmykPdf.note(1000), "CMYK · flattened · about 1 MB")
    }

    func testTheCmykPDFHoldsEachSheetAsPackedDeviceCMYKInkWithItsBoxesAndBlackOnlyMarks() throws {
        let colours: [UInt32] = [0xFF00_0000, 0xFFFF_FFFF, 0xFFFF_0000, 0x0000_0000]
        // 3 × 300 pixels: more rows than one band.
        let sheet = CmykPdf.Sheet(width: 3, height: 300, rows: { top, count, into in
            for row in 0..<count {
                for x in 0..<3 { into[row * 3 + x] = colours[(top + row + x) % 4] }
            }
        })
        let trim = CGRect(x: 9, y: 9, width: 594, height: 774)
        let bleed = CGRect(x: 0, y: 0, width: 612, height: 792)
        let marks = [(CGPoint(x: 1, y: 9), CGPoint(x: 5, y: 9))]
        let bytes = try CmykPdf.write([sheet, sheet], size: CGSize(width: 612, height: 792), trim: [trim, nil],
                                      bleed: [bleed, nil], marks: [marks, []])
        let text = String(decoding: bytes.map { $0 < 0x80 ? $0 : 0x3F }, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("%PDF-1.4\n"))
        XCTAssertTrue(text.hasSuffix("%%EOF\n"))
        XCTAssertTrue(text.contains("/Type /Pages /Kids [3 0 R 7 0 R] /Count 2"))
        XCTAssertTrue(text.contains("/MediaBox [0 0 612.00 792.00] /TrimBox [9.00 9.00 603.00 783.00] /BleedBox [0.00 0.00 612.00 792.00]"))
        // The second sheet has no boxes.
        XCTAssertTrue(text.contains("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612.00 792.00] /Resources"))
        XCTAssertTrue(text.contains("/Width 3 /Height 300 /ColorSpace /DeviceCMYK /BitsPerComponent 8 /Filter /FlateDecode"))
        // The marks: black ink alone, measured up from the bottom.
        XCTAssertTrue(text.contains("0 0 0 1 K 0.5 w\n1.00 783.00 m 5.00 783.00 l S\n"))
        // Every cross-reference entry points at its object.
        let xrefAt = try XCTUnwrap(text.range(of: "xref\n0 ", options: .backwards)).lowerBound
        let entries = text[xrefAt...].components(separatedBy: "\n").dropFirst(3).filter { $0.hasSuffix(" n ") }
        XCTAssertEqual(entries.count, 10)
        let raw = Array(bytes)
        for (i, entry) in entries.enumerated() {
            let offset = try XCTUnwrap(Int(entry.prefix(10)))
            let head = String(decoding: raw[offset..<min(offset + 12, raw.count)], as: UTF8.self)
            XCTAssertTrue(head.hasPrefix("\(i + 1) 0 obj"), head)
        }
        // The picture unpacks to the ink, row by row: a zlib stream, its
        // two-byte header and Adler-32 round raw DEFLATE.
        let image = try XCTUnwrap(text.range(of: "/DeviceCMYK"))
        let streamAt = try XCTUnwrap(text.range(of: "stream\n", range: image.upperBound..<text.endIndex))
        let start = text.utf8.distance(from: text.startIndex, to: streamAt.upperBound)
        let lengthObj = try XCTUnwrap(text.range(of: "6 0 obj\n"))
        let lengthLine = text[lengthObj.upperBound...].prefix { $0 != "\n" }
        let length = try XCTUnwrap(Int(lengthLine))
        XCTAssertEqual(Array(raw[start..<start + 2]), [0x78, 0x9C])
        let packed = Data(raw[(start + 2)..<(start + length - 4)])
        let ink = try XCTUnwrap(ZipStore.inflate(packed, size: 3 * 300 * 4))
        let px = Array(ink)
        XCTAssertEqual(Array(px[0..<12]), [0, 0, 0, 255, 0, 0, 0, 0, 0, 255, 255, 0])
        // Row 129, the second band: starting a colour on.
        XCTAssertEqual(Array(px[(129 * 12)..<(129 * 12 + 4)]), [0, 0, 0, 0])
        // The Adler-32 of the ink, after it.
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in px {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let sum = b << 16 | a
        let tail = raw[(start + length - 4)..<(start + length)]
        XCTAssertEqual(Array(tail), [UInt8(sum >> 24), UInt8(sum >> 16 & 0xff), UInt8(sum >> 8 & 0xff), UInt8(sum & 0xff)])
    }
}
