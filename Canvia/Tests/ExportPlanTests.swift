// Round 32's export sheet, as the Android twin's ExportPlanTest checks it:
// the ZIP's name and the names inside it, the "zip" and "pngCompress" keys,
// the compressed PNG (PngWriter) and when it is kept, and the accessibility
// row's rule and words.

import CryptoKit
import ImageIO
import XCTest
@testable import Canvia

final class ExportPlanTests: XCTestCase {

    // MARK: one ZIP

    func testTheZipAndItsEntriesAreNamedAsTheFilesAre() {
        XCTAssertEqual(ExportPlan.zipName("Q3 / report"), "Q3-report.zip")
        XCTAssertEqual(ExportPlan.zipName(""), "design.zip")
        XCTAssertEqual(ExportPlan.entryNames("Café menu", ext: "png", pages: [0, 2, 4]),
                       ["Café-menu-1.png", "Café-menu-3.png", "Café-menu-5.png"])
        XCTAssertEqual(ExportPlan.entryNames("Poster", ext: "svg", pages: [3]), ["Poster.svg"])
        // The files the pictures are written to carry the same names.
        let design = Design(title: "Café menu")
        XCTAssertEqual(DesignExporter.fileURL(for: design, ext: "png", suffix: "-3").lastPathComponent,
                       ExportPlan.entryNames("Café menu", ext: "png", pages: [0, 2])[1])
    }

    func testZipIsOfferedForSeveralPicturesOrSvgs() {
        XCTAssertTrue(ExportPlan.offersZip(format: "png", files: 2))
        XCTAssertTrue(ExportPlan.offersZip(format: "jpg", files: 3))
        XCTAssertTrue(ExportPlan.offersZip(format: "svg", files: 2))
        XCTAssertFalse(ExportPlan.offersZip(format: "png", files: 1))
        XCTAssertFalse(ExportPlan.offersZip(format: "pdf", files: 5))
        XCTAssertFalse(ExportPlan.offersZip(format: "mp4", files: 5))
    }

    @MainActor
    func testTheZipHoldsEachFileUnderItsName() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("Poster-1.png"), b = dir.appendingPathComponent("Poster-2.png")
        try Data("one".utf8).write(to: a)
        try Data("two".utf8).write(to: b)
        let zip = dir.appendingPathComponent("Poster.zip")
        try ExportJobs.writeZip([a, b], to: zip)
        let reader = try ZipStore.Reader(url: zip)
        XCTAssertEqual(reader.file("Poster-1.png"), Data("one".utf8))
        XCTAssertEqual(reader.file("Poster-2.png"), Data("two".utf8))
        XCTAssertEqual(reader.entries.count, 2)
    }

    func testTheNewKeysAreRememberedAndReadLeniently() throws {
        let on = ExportLast(format: "png", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                            pages: "all", zip: true, pngCompress: true)
        XCTAssertTrue(on.json.hasSuffix(#""embedMedia":true,"layout":"scroll","autoplay":0.0,"loop":false},"zip":true,"pngCompress":true,"pdfTagged":true}"#))
        XCTAssertEqual(ExportLast.read(on.json), on)
        let old = try XCTUnwrap(ExportLast.read(#"{"format":"png"}"#))
        XCTAssertFalse(old.zip)
        XCTAssertFalse(old.pngCompress)
        let odd = try XCTUnwrap(ExportLast.read(#"{"format":"png","zip":"yes","pngCompress":1}"#))
        XCTAssertFalse(odd.zip)
        XCTAssertFalse(odd.pngCompress)
    }

    // MARK: a compressed PNG

    /// 16 × 16: four flat quarters — red, green, blue and see-through —
    /// and a half-clear white stripe across the middle.
    private func fixture() -> [UInt8] {
        var out: [UInt8] = []
        for y in 0..<16 {
            for x in 0..<16 {
                if y == 7 || y == 8 {
                    out += [255, 255, 255, 128]
                } else if y < 8 {
                    out += x < 8 ? [255, 0, 0, 255] : [0, 255, 0, 255]
                } else {
                    out += x < 8 ? [0, 0, 255, 255] : [0, 0, 0, 0]
                }
            }
        }
        return out
    }

    /// Shared: Android's ExportFilesTest holds the same palette.
    func testFewColoursAreKeptExactly() {
        let indexed = PngWriter.quantize(fixture())
        XCTAssertEqual(indexed.palette, [[255, 255, 255, 128], [0, 0, 255, 255], [0, 255, 0, 255], [255, 0, 0, 255],
                                         [0, 0, 0, 0]],
                       "one colour a bucket, in bucket order: alpha, then red, green, blue; clear last")
        XCTAssertEqual(indexed.indices.count, 256)
        XCTAssertEqual(indexed.indices[0], 3)
        XCTAssertEqual(indexed.indices[15 * 16 + 15], 4)
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Android's first fixture, 24 × 16: four clear columns, then opaque
    /// colours above and half-clear ones below.
    private func fewColours() -> [UInt8] {
        var out: [UInt8] = []
        for y in 0..<16 {
            for x in 0..<24 {
                if x < 4 {
                    out += [0, 0, 0, 0]
                } else if y < 8 {
                    out += [UInt8(x * 10), UInt8(y * 30), 200, 255]
                } else {
                    out += [255, UInt8(x * 10), 0, 128]
                }
            }
        }
        return out
    }

    /// Android's second, 64 × 64: a gradient of thousands of colours, some
    /// of them see-through.
    private func manyColours() -> [UInt8] {
        var out: [UInt8] = []
        for y in 0..<64 {
            for x in 0..<64 {
                out += [UInt8(x * 4), UInt8(y * 4), UInt8((x + y) * 2), (x + y) % 5 == 0 ? 100 : 255]
            }
        }
        return out
    }

    /// Shared: Android's PngWriter writes these same bytes from the same
    /// pixels (ExportFilesTest).
    func testTheCompressedPngFixturesAreByteForByteAndroids() throws {
        let files = [
            try XCTUnwrap(PngWriter.png(rgba: fewColours(), width: 24, height: 16, dpi: nil)),
            try XCTUnwrap(PngWriter.png(rgba: manyColours(), width: 64, height: 64, dpi: nil)),
            try XCTUnwrap(PngWriter.png(rgba: fixture(), width: 16, height: 16, dpi: nil)),
        ]
        XCTAssertEqual(files.map(sha), [
            "a2b8d2ad27183d522f696538800c97fad8adabf4be635851aa7854130b4afafb",
            "d6d8970a45b476e41f2a6ec3abd4a1bcb6c8cc2d253240ebbc0088a1a830c6f3",
            "ba43a31aa189dd67b64a6ee0aa4419083ac0a1242a0e078d22cdc621cdc19f06",
        ])
    }

    /// Shared: Android's Deflate writes the same streams.
    func testTheSharedDeflateIsAndroids() {
        var x: UInt64 = 12345
        let noise = (0..<70_000).map { _ -> UInt8 in
            x = (x &* 1_103_515_245 &+ 12345) & 0x7FFF_FFFF
            return UInt8(truncatingIfNeeded: x >> 16)
        }
        let inputs: [[UInt8]] = [
            [],
            Array("Wikipedia".utf8),
            [UInt8](repeating: 7, count: 1000),
            noise,
            (0..<100_000).map { UInt8($0 / 300 % 3) },
        ]
        XCTAssertEqual(inputs.map { sha(Deflate.zlib($0)) }, [
            "b171e283c6145acf2b923098dbbc40ffc39b4f1db0212928f9869747376c4ac8",
            "ea97e7309b0076a6698bc3114b23a8ee8f72c9152b937217cb5f8b918aaa3149",
            "886914295ed25d481dd0c1a93bc2aa23bdae9f0e06098a61b36413456818dd2a",
            "4b76b1191007d0a4d4ad04b0befab1b03f05ed3703ca2867b482d115cfbf9ffe",
            "434b75b7a80109f0c79e54763fab92caa50604aaea283050b00cc534ee7d3535",
        ])
    }

    func testManyColoursAreCutTo256() {
        var pixels: [UInt8] = []
        for i in 0..<4096 { pixels += [UInt8(i % 64 * 4), UInt8(i / 64 * 4), UInt8((i * 7) % 256), 255] }
        let indexed = PngWriter.quantize(pixels)
        XCTAssertEqual(indexed.palette.count, 256)
        XCTAssertEqual(indexed.indices.count, 4096)
        XCTAssertTrue(indexed.indices.allSatisfy { Int($0) < indexed.palette.count })
    }

    func testTheIndexedPngReadsBackAsItsPixels() throws {
        let rgba = fixture()
        let data = try XCTUnwrap(PngWriter.png(rgba: rgba, width: 16, height: 16, dpi: 300))
        let bytes = [UInt8](data)
        XCTAssertEqual(Array(bytes[0..<8]), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(String(decoding: bytes[12..<16], as: UTF8.self), "IHDR")
        XCTAssertEqual(Array(bytes[24..<26]), [8, 3], "8-bit, indexed")
        for chunk in ["pHYs", "PLTE", "tRNS", "IDAT", "IEND"] {
            XCTAssertNotNil(data.range(of: Data(chunk.utf8)), chunk)
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 16)
        let back = try XCTUnwrap(PngWriter.rgba(of: image))
        // Opaque pixels come back exactly; the half-clear one within a step.
        XCTAssertEqual(Array(back[0..<4]), [255, 0, 0, 255])
        XCTAssertEqual(back[(15 * 16 + 15) * 4 + 3], 0)
        XCTAssertEqual(Int(back[(7 * 16) * 4 + 3]), 128, accuracy: 1)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertEqual((properties?[kCGImagePropertyDPIWidth] as? Double) ?? 0, 300, accuracy: 0.5)
    }

    func testTheZlibStreamHasItsHeaderAndSum() throws {
        XCTAssertEqual(PngWriter.adler32(Data("Wikipedia".utf8)), 0x11E6_0398)
        let stream = try XCTUnwrap(PngWriter.zlib(Data(repeating: 7, count: 1000)))
        XCTAssertEqual(Array(stream.prefix(2)), [0x78, 0xDA])
        XCTAssertLessThan(stream.count, 30)
    }

    func testACompressedPngIsKeptOnlyWhenFifteenPercentSmaller() {
        XCTAssertTrue(ExportPlan.keepsCompressed(compressed: 85, normal: 100))
        XCTAssertFalse(ExportPlan.keepsCompressed(compressed: 86, normal: 100))
        // Shared: Android's ExportFilesTest holds the same sizes.
        XCTAssertEqual(ExportPlan.estimatedPngBytes(width: 2160, height: 2160), 2160 * 2160 * 12 / 8)
        XCTAssertEqual(ExportPlan.estimatedCompressedPngBytes(width: 2160, height: 2160), 2160 * 2160 * 4 / 8)
        XCTAssertEqual(ExportPlan.estimatedCompressedPngBytes(width: 10, height: 10), 2048)
    }

    // MARK: accessibility first

    func testTheRowShowsForReadTypesUntilPutAwayAtThisRevision() {
        XCTAssertTrue(ExportPlan.showsA11yNudge(format: "pdf", findings: 3, remind: true, revision: 10, dismissed: nil))
        XCTAssertTrue(ExportPlan.showsA11yNudge(format: "png", findings: 1, remind: true, revision: 10, dismissed: 9))
        XCTAssertFalse(ExportPlan.showsA11yNudge(format: "pdf", findings: 3, remind: true, revision: 10, dismissed: 10))
        XCTAssertFalse(ExportPlan.showsA11yNudge(format: "pdf", findings: 0, remind: true, revision: 10, dismissed: nil))
        XCTAssertFalse(ExportPlan.showsA11yNudge(format: "pdf", findings: 3, remind: false, revision: 10, dismissed: nil))
        // A film's row counts its captions findings alone (nudgeFindings).
        XCTAssertTrue(ExportPlan.showsA11yNudge(format: "mp4", findings: 3, remind: true, revision: 10, dismissed: nil))
        XCTAssertFalse(ExportPlan.showsA11yNudge(format: "gif", findings: 0, remind: true, revision: 10, dismissed: nil))
        XCTAssertFalse(ExportPlan.showsA11yNudge(format: "svg", findings: 3, remind: true, revision: 10, dismissed: nil))
    }

    func testTheRowSaysHowManySuggestionsOnThePagesGoingOut() {
        let findings = [
            AccessibilityFinding(kind: .altText, pageIndex: 0, elementId: "a", message: "", fix: nil),
            AccessibilityFinding(kind: .smallText, pageIndex: 1, elementId: "b", message: "", fix: nil),
            AccessibilityFinding(kind: .smallText, pageIndex: 2, elementId: "c", message: "", fix: nil),
        ]
        XCTAssertEqual(AccessibilityAudit.suggestions(findings), "3 accessibility suggestions")
        XCTAssertEqual(AccessibilityAudit.suggestions(Array(findings.prefix(1))), "1 accessibility suggestion")
        XCTAssertEqual(AccessibilityAudit.onPages(findings, [0, 2]).map(\.elementId), ["a", "c"])
        XCTAssertEqual(AccessibilityAudit.summary(findings), "3 things on 3 pages")
    }

    func testThePutAwayRevisionIsKeptInTheMetaAndTheSettingInABackup() throws {
        var meta = DesignLibrary.VersionMeta(pinned: ["1": "Kept"])
        XCTAssertFalse(String(decoding: try XCTUnwrap(meta.data), as: UTF8.self).contains("a11yNudgeDismissed"))
        meta.a11yNudgeDismissed = 1_760_000_000_123
        let text = String(decoding: try XCTUnwrap(meta.data), as: UTF8.self)
        XCTAssertEqual(text, #"{"a11yNudgeDismissed":1760000000123,"pinned":{"1":"Kept"},"version":1}"#)
        XCTAssertEqual(DesignLibrary.VersionMeta.read(Data(text.utf8)), meta)
        let settings = Backup.encodeSettings(autoLists: true, use: nil, exportA11yNudge: false)
        XCTAssertEqual(Backup.decodeA11yNudge(settings), false)
        XCTAssertNil(Backup.decodeA11yNudge(Backup.encodeSettings(autoLists: true, use: nil)))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ExportPlanTests"))
        defaults.removePersistentDomain(forName: "ExportPlanTests")
        XCTAssertTrue(ExportPlan.remindsA11y(defaults), "on unless turned off")
        defaults.set(false, forKey: ExportPlan.a11yNudgeKey)
        XCTAssertFalse(ExportPlan.remindsA11y(defaults))
    }
}
