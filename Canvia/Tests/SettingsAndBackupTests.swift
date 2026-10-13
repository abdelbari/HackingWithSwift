// Settings and backup: the manifest as both phones write it, the merge
// rule a restore follows, brand kits merged, the STORE zip read back, what
// a restore says, and the defaults Settings keeps.

import XCTest
import SwiftUI
@testable import Canvia

final class SettingsAndBackupTests: XCTestCase {

    // MARK: manifest

    static let manifest = #"{"counts":{"brandKits":2,"designs":3,"fonts":1,"templates":2,"trash":1,"uploads":4},"created":1727000000000,"format":"canvia-backup","platform":"ios","version":1}"#

    func testTheManifestRoundTrips() throws {
        var m = Backup.Manifest(created: 1_727_000_000_000)
        m.counts = Backup.Counts(designs: 3, trash: 1, templates: 2, uploads: 4, fonts: 1, brandKits: 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(m), as: UTF8.self), Self.manifest)
        XCTAssertEqual(try Backup.manifest(from: Data(Self.manifest.utf8)), m)
    }

    func testAManifestFromTheOtherPhoneReadsWithWhatItHas() throws {
        // Only the version is needed; keys this build does not know pass.
        let android = #"{"version":1,"created":5,"counts":{"designs":2,"stickers":9},"platform":"android"}"#
        let m = try Backup.manifest(from: Data(android.utf8))
        XCTAssertEqual(m.counts.designs, 2)
        XCTAssertEqual(m.counts.uploads, 0)
        XCTAssertEqual(m.platform, "android")
        XCTAssertNil(m.format)

        XCTAssertThrowsError(try Backup.manifest(from: nil), "no manifest: not a backup")
        XCTAssertThrowsError(try Backup.manifest(from: Data(#"{"format":"canvia-package","version":1}"#.utf8)))
        XCTAssertThrowsError(try Backup.manifest(from: Data(#"{"created":5}"#.utf8)), "no version")
        do {
            _ = try Backup.manifest(from: Data(#"{"version":2,"created":5}"#.utf8))
            XCTFail("a newer backup")
        } catch {
            XCTAssertEqual(error.localizedDescription, Backup.BackupError.newer.localizedDescription)
        }
    }

    // MARK: the merge rule

    func testARestoreNeverReplacesADesignWithAnOlderOrTheSameCopy() {
        let rows: [(incoming: Double, existing: Double?, expected: Backup.Merge)] = [
            (200, nil, .add),
            (200, 100, .replace),
            (100, 200, .keep),
            (100, 100, .keep),
            (0, nil, .add),
            // The same design back from the Android twin, which keeps whole
            // milliseconds: the same, not newer, either way round.
            (124, 123.6, .keep),
            (123.6, 124, .keep),
        ]
        for row in rows {
            XCTAssertEqual(Backup.merge(incoming: row.incoming, existing: row.existing), row.expected,
                           "\(row.incoming) over \(String(describing: row.existing))")
        }
    }

    func testBrandKitsMergeWithoutLosingAny() {
        var mine = BrandKit(id: "kit-1", name: "My brand")
        mine.addColor("#111111")
        var theirs = BrandKit(id: "kit-1", name: "My brand")
        theirs.addColor("#222222")
        var autumn = BrandKit(id: "kit_autumn", name: "Autumn")
        autumn.fonts.body = BrandFont(family: "serif")

        // Here, the first kit is still empty: the backup's takes its place.
        var kits = BrandKits.fresh
        XCTAssertEqual(Backup.mergeKits(BrandKits(activeId: "kit-1", kits: [theirs, autumn]), into: &kits), 2)
        XCTAssertEqual(kits.kits, [theirs, autumn])
        XCTAssertEqual(kits.activeId, "kit-1")

        // The same again: nothing.
        XCTAssertEqual(Backup.mergeKits(BrandKits(activeId: "kit-1", kits: [theirs, autumn]), into: &kits), 0)

        // Different under the same id: beside it, under a fresh id and name.
        kits = BrandKits(activeId: "kit-1", kits: [mine])
        XCTAssertEqual(Backup.mergeKits(BrandKits(activeId: "kit-1", kits: [theirs]), into: &kits), 1)
        XCTAssertEqual(kits.kits.count, 2)
        XCTAssertEqual(kits.kits[0], mine)
        XCTAssertEqual(kits.kits[1].name, "My brand 2")
        XCTAssertNotEqual(kits.kits[1].id, "kit-1")
        XCTAssertEqual(kits.kits[1].palettes, theirs.palettes)
        XCTAssertEqual(kits.activeId, "kit-1", "the kit in use stays in use")

        // A kit with nothing in it — another phone's untouched first kit —
        // brings nothing.
        kits = BrandKits(activeId: "kit-1", kits: [mine])
        XCTAssertEqual(Backup.mergeKits(BrandKits.fresh, into: &kits), 0)
        XCTAssertEqual(kits.kits, [mine])
    }

    // MARK: what a restore says

    func testARestoreSaysWhatItBroughtIn() {
        var r = Backup.Report()
        XCTAssertEqual(Backup.summary(r), "Nothing new to restore.")
        r.fonts = 1
        XCTAssertEqual(Backup.summary(r), "Restored 1 font.")
        r = Backup.Report(designs: 3, templates: 1, uploads: 12, kept: 2)
        XCTAssertEqual(Backup.summary(r), "Restored 3 designs, 1 template and 12 uploads. 2 already here were kept.")
        r = Backup.Report(designs: 1, trash: 2, brandKits: 1, kept: 1)
        XCTAssertEqual(Backup.summary(r), "Restored 1 design, 2 deleted designs and 1 brand kit. 1 already here was kept.")
        XCTAssertEqual(Backup.summary(Backup.Report(kept: 4)), "Nothing new to restore. 4 already here were kept.")
        XCTAssertEqual(Backup.fileName(Date(timeIntervalSince1970: 1_727_000_000)).hasSuffix(".canviabackup"), true)
    }

    // MARK: the zip

    func testTheCRCIsZipsOwn() {
        XCTAssertEqual(ZipStore.crc32(Data("123456789".utf8)), 0xcbf4_3926)
        XCTAssertEqual(ZipStore.crc32(Data()), 0)
        // Summed a piece at a time, the same.
        let running = ZipStore.crc32(continuing: 0xffff_ffff, Data("1234".utf8))
        XCTAssertEqual(ZipStore.crc32(continuing: running, Data("56789".utf8)) ^ 0xffff_ffff, 0xcbf4_3926)
    }

    /// An entry streamed a piece at a time — as a backup writes each design
    /// file and every upload — reads back as one added whole, its CRC and
    /// size filled in in its local header, where the Android twin's
    /// ZipInputStream reads them.
    func testAnEntryStreamedInPiecesReadsBackWhole() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clip = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let clipURL = dir.appendingPathComponent("vid_a.mp4")
        try clip.write(to: clipURL)
        let url = dir.appendingPathComponent("streamed.canviabackup")
        let writer = try ZipStore.Writer(url: url)
        try writer.add("a.txt", Data("hello".utf8))
        try writer.add("pieces.bin", pieces: { write in
            try write(clip.prefix(4_000))
            try write(clip.dropFirst(4_000))
        })
        let handle = try FileHandle(forReadingFrom: clipURL)
        try writer.add("videos/vid_a.mp4", from: handle)
        try handle.close()
        try writer.finish()

        let reader = try ZipStore.Reader(url: url)
        XCTAssertEqual(reader.entries.count, 3)
        XCTAssertEqual(reader.file("a.txt"), Data("hello".utf8))
        XCTAssertEqual(reader.file("pieces.bin"), clip)
        XCTAssertEqual(reader.file("videos/vid_a.mp4"), clip)

        // The second entry's local header, after the first's 30 + 5 + 5
        // bytes: its CRC, then both sizes.
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }
        let bytes = try Data(contentsOf: url)
        let second = 40
        XCTAssertEqual(Array(bytes[second..<(second + 4)]), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertEqual(Array(bytes[(second + 14)..<(second + 26)]),
                       le32(ZipStore.crc32(clip)) + le32(10_000) + le32(10_000))
    }

    /// A long clip goes into a backup's design file a piece at a time: no
    /// piece handed on comes near the clip or its base64 — neither is ever
    /// held whole — and the pieces join into a file that reads back with
    /// the clip in it, byte for byte.
    func testALongClipIsStreamedIntoTheDesignFileInPieces() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clip = Data((0..<300_001).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let clipURL = dir.appendingPathComponent("vid_long.mov")
        try clip.write(to: clipURL)
        var design = Design(title: "Long clip", width: 1080, height: 1920)
        design.pages = [Page(elements: [Element.image(VideoStore.src("vid_long", at: nil), w: 16, h: 9)])]
        let photo = DesignPackage.Media(ext: "png", data: Data([1, 2, 3]))
        let package = DesignPackage.Package(design: design, media: ["img_a": photo])

        var pieces: [Data] = []
        try DesignPackage.stream(package, clips: ["vid_long": clipURL], pieceBytes: 3_000) { pieces.append($0) }
        let largest = pieces.map(\.count).max() ?? 0
        XCTAssertLessThan(largest, 20_000, "no piece near the clip's 300 KB, nor its 400 KB of base64")
        XCTAssertGreaterThan(pieces.count, 100)

        let file = pieces.reduce(into: Data()) { $0.append($1) }
        let read = try JSONDecoder().decode(DesignPackage.Package.self, from: file)
        XCTAssertEqual(read.format, DesignPackage.format)
        XCTAssertEqual(read.videos?["vid_long"]?.data, clip)
        XCTAssertEqual(read.videos?["vid_long"]?.ext, "mov")
        XCTAssertEqual(read.media["img_a"]?.data, Data([1, 2, 3]))
        XCTAssertEqual(read.design.title, "Long clip")
        XCTAssertEqual(read.design.pages.first?.elements.first?.src, "video:vid_long")
        let text = String(decoding: file, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix(#"{"design":"#), text.prefix(40).description)
        XCTAssertTrue(text.hasSuffix(#""ext":"mov"}}}"#))
    }

    func testAStoreZipReadsBackFileForFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).canviabackup")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try ZipStore.Writer(url: url, date: Date(timeIntervalSince1970: 1_727_000_000))
        let design = Data(#"{"format":"canvia-package"}"#.utf8)
        let photo = Data((0..<300).map { UInt8($0 % 256) })
        try writer.add("manifest.json", Data(Self.manifest.utf8))
        try writer.add("designs/Café.canvia.json", design)
        try writer.add("media/img_a.jpg", photo)
        try writer.add("empty.txt", Data())
        try writer.finish()

        let reader = try ZipStore.Reader(url: url)
        XCTAssertEqual(reader.entries.count, 4)
        XCTAssertEqual(reader.file("manifest.json"), Data(Self.manifest.utf8))
        XCTAssertEqual(reader.file("designs/Café.canvia.json"), design, "UTF-8 names")
        XCTAssertEqual(reader.file("media/img_a.jpg"), photo)
        XCTAssertEqual(reader.file("empty.txt"), Data())
        XCTAssertNil(reader.file("missing"))
        XCTAssertEqual(reader.names(in: "designs/"), ["designs/Café.canvia.json"])
        XCTAssertEqual(reader.names(in: "media/"), ["media/img_a.jpg"])

        // Every entry stored, its CRC in the local header.
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertEqual(bytes[bytes.startIndex + 8], 0, "STORE")
        let crc = ZipStore.crc32(Data(Self.manifest.utf8))
        XCTAssertEqual(Array(bytes[14..<18]), [UInt8(crc & 0xff), UInt8(crc >> 8 & 0xff),
                                              UInt8(crc >> 16 & 0xff), UInt8(crc >> 24)])
    }

    func testWhatIsNotAStoreZipIsTurnedAway() throws {
        XCTAssertThrowsError(try ZipStore.Reader(data: Data("not a zip at all, not even close".utf8)))
        XCTAssertThrowsError(try ZipStore.Reader(data: Data()))

        // The same archive with its one entry marked deflated.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try ZipStore.Writer(url: url)
        try writer.add("a.txt", Data("hello".utf8))
        try writer.finish()
        var bytes = try Data(contentsOf: url)
        let central = try XCTUnwrap(bytes.indices.dropLast(4).first {
            bytes[$0] == 0x50 && bytes[$0 + 1] == 0x4b && bytes[$0 + 2] == 0x01 && bytes[$0 + 3] == 0x02
        })
        bytes[central + 10] = 8
        XCTAssertThrowsError(try ZipStore.Reader(data: bytes))
    }

    // MARK: settings

    func testAppearanceIsSystemLightOrDark() {
        XCTAssertNil(Appearance.scheme("system"))
        XCTAssertEqual(Appearance.scheme("light"), .light)
        XCTAssertEqual(Appearance.scheme("dark"), .dark)
        XCTAssertNil(Appearance.scheme("sepia"), "one this build does not know follows the phone")
        XCTAssertEqual(Appearance.allCases.map(\.label), ["System", "Light", "Dark"])
        XCTAssertEqual(Appearance.key, "appearance")
    }

    func testTheDefaultExportFormatIsListedFirst() {
        XCTAssertEqual(AppDefaults.formatOrder("png"), ["png", "jpg", "pdf", "svg"])
        XCTAssertEqual(AppDefaults.formatOrder("jpg"), ["jpg", "png", "pdf", "svg"])
        XCTAssertEqual(AppDefaults.formatOrder("pdf"), ["png", "jpg", "pdf", "svg"], "a picture format, or none")
        XCTAssertEqual(AppDefaults.formatOrder("gif"), ["png", "jpg", "pdf", "svg"])
        XCTAssertEqual(AppDefaults.exportFormats.map(AppDefaults.formatLabel), ["PNG", "JPG"], "as the Android twin offers them")
    }

    func testCustomSizeOpensInTheDefaultUnit() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "unit-\(UUID().uuidString)"))
        XCTAssertEqual(AppDefaults.unit(defaults), "px")
        defaults.set("mm", forKey: AppDefaults.unitKey)
        XCTAssertEqual(AppDefaults.unit(defaults), "mm")
        defaults.set("furlong", forKey: AppDefaults.unitKey)
        XCTAssertEqual(AppDefaults.unit(defaults), "px")
    }

    func testAFileNameFromABackupIsKeptInsideItsFolder() {
        XCTAssertTrue(DesignPackage.isSafeFileName("img_abc123.jpg"))
        XCTAssertTrue(DesignPackage.isSafeFileName("audio_x1.m4a"))
        XCTAssertFalse(DesignPackage.isSafeFileName("../designs/x.json"))
        XCTAssertFalse(DesignPackage.isSafeFileName("a/b"))
        XCTAssertFalse(DesignPackage.isSafeFileName(""))
    }
}
