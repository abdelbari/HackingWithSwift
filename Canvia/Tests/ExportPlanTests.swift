// Round 32's export sheet, as the Android twin's ExportPlanTest checks it:
// the ZIP's name and the names inside it, the "zip" and "pngCompress" keys,
// the compressed PNG (PngWriter) and when it is kept, and the accessibility
// row's rule and words.

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
        XCTAssertTrue(on.json.hasSuffix(#""embedMedia":true},"zip":true,"pngCompress":true}"#))
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

    func testFewColoursAreKeptExactly() {
        let indexed = PngWriter.quantize(fixture())
        XCTAssertEqual(indexed.palette, [[0, 0, 0, 0], [255, 255, 255, 128], [0, 0, 255, 255], [0, 255, 0, 255],
                                         [255, 0, 0, 255]],
                       "one colour a bucket, in bucket order: alpha, then red, green, blue")
        XCTAssertEqual(indexed.indices.count, 256)
        XCTAssertEqual(indexed.indices[0], 4)
        XCTAssertEqual(indexed.indices[15 * 16 + 15], 0)
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
        XCTAssertLessThan(stream.count, 100)
    }

    func testACompressedPngIsKeptOnlyWhenFifteenPercentSmaller() {
        XCTAssertTrue(ExportPlan.keepsCompressed(compressed: 85, normal: 100))
        XCTAssertFalse(ExportPlan.keepsCompressed(compressed: 86, normal: 100))
        XCTAssertEqual(ExportPlan.estimatedPngBytes(width: 1080, height: 1080), 1_633_280)
        XCTAssertEqual(ExportPlan.estimatedCompressedPngBytes(width: 1080, height: 1080), 526_336)
    }

    // MARK: accessibility first

    func testTheRowShowsForReadTypesUntilPutAwayAtThisRevision() {
        XCTAssertTrue(ExportPlan.showsA11yNudge(format: "pdf", findings: 3, remind: true, revision: 10, dismissed: nil))
        XCTAssertTrue(ExportPlan.showsA11yNudge(format: "png", findings: 1, remind: true, revision: 10, dismissed: 9))
        XCTAssertFalse(ExportPlan.showsA11yNudge(format: "pdf", findings: 3, remind: true, revision: 10, dismissed: 10))
        XCTAssertFalse(ExportPlan.showsA11yNudge(format: "pdf", findings: 0, remind: true, revision: 10, dismissed: nil))
        XCTAssertFalse(ExportPlan.showsA11yNudge(format: "pdf", findings: 3, remind: false, revision: 10, dismissed: nil))
        XCTAssertFalse(ExportPlan.showsA11yNudge(format: "mp4", findings: 3, remind: true, revision: 10, dismissed: nil))
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
