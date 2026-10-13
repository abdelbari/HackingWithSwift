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
