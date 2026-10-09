// Keeping the person's work: saves that land whole or say they did not, a
// design whose file no longer reads shown and brought back from a version,
// and no sweep while one is damaged.

import XCTest
import UIKit
@testable import Canvia

final class DataSafetyTests: XCTestCase {

    private var ids: [String] = []

    override func tearDown() {
        for id in ids { DesignLibrary.delete(id: id) }
        ids = []
        super.tearDown()
    }

    private func saved(_ title: String) -> Design {
        let d = Design(title: title, width: 300, height: 200)
        XCTAssertTrue(DesignLibrary.save(d))
        ids.append(d.id)
        return d
    }

    // MARK: saving

    /// A save that cannot be written says so, and leaves the last good
    /// file where it was rather than half of a new one. JSON has no way to
    /// write a width that is not a number, so encoding fails here as a full
    /// disk fails on a phone.
    func testAFailedSaveIsReportedAndKeepsTheLastGoodFile() {
        var d = saved("Kept")
        d.title = "Never written"
        d.width = .nan
        XCTAssertFalse(DesignLibrary.save(d))
        XCTAssertEqual(DesignLibrary.load(id: d.id)?.title, "Kept")
        XCTAssertEqual(DesignLibrary.load(id: d.id)?.width, 300)
    }

    @MainActor
    func testTheBannerSaysWhatTheAndroidTwinSays() {
        XCTAssertEqual(EditorView.saveFailedMessage,
                       "Couldn't save your changes. Your phone may be out of space. Canvia will keep trying.")
    }

    // MARK: damaged designs

    /// Half a design, as a save cut short before saves were atomic left it.
    private func damage(_ id: String) throws {
        try Data("{\"id\": \"\(id)\", \"title\": \"Cut sh".utf8)
            .write(to: DesignLibrary.designsDir.appendingPathComponent("\(id).json"))
    }

    func testADamagedDesignIsACardOfItsOwn() throws {
        let d = saved("Soon damaged")
        XCTAssertTrue(DesignLibrary.shelf().designs.contains { $0.id == d.id })
        try damage(d.id)
        let shelf = DesignLibrary.shelf()
        XCTAssertFalse(shelf.designs.contains { $0.id == d.id })
        let card = try XCTUnwrap(shelf.damaged.first { $0.id == d.id }, "a damaged design was left out without a word")
        XCTAssertEqual(card.title, "Damaged design")
        XCTAssertTrue(card.damaged)
        XCTAssertFalse(DesignLibrary.recents().contains { $0.id == d.id }, "a damaged design cannot be opened")
    }

    /// Restored from the newest version that reads, under the same id, and
    /// the card is the design again.
    func testADamagedDesignComesBackFromItsNewestVersionThatReads() throws {
        var d = saved("Oldest")
        XCTAssertTrue(DesignLibrary.snapshot(d, force: true, now: Date(timeIntervalSinceNow: -900)))
        d.title = "Newer"
        XCTAssertTrue(DesignLibrary.snapshot(d, force: true, now: Date(timeIntervalSinceNow: -600)))
        d.title = "Newest, but damaged"
        XCTAssertTrue(DesignLibrary.snapshot(d, force: true, now: Date(timeIntervalSinceNow: -300)))
        let newest = try XCTUnwrap(DesignLibrary.versions(for: d.id).first)
        try Data("{\"pages\": [".utf8).write(to: newest.url)
        try damage(d.id)

        let restored = try XCTUnwrap(DesignLibrary.restoreLastVersion(of: d.id))
        XCTAssertEqual(restored.id, d.id)
        XCTAssertEqual(restored.title, "Newer")
        let shelf = DesignLibrary.shelf()
        XCTAssertFalse(shelf.damaged.contains { $0.id == d.id })
        XCTAssertEqual(shelf.designs.first { $0.id == d.id }?.title, "Newer")
        XCTAssertEqual(DesignLibrary.load(id: d.id)?.title, "Newer")
    }

    func testNothingToRestoreWithoutAVersion() throws {
        let d = saved("No history")
        try damage(d.id)
        XCTAssertNil(DesignLibrary.restoreLastVersion(of: d.id))
        XCTAssertTrue(DesignLibrary.shelf().damaged.contains { $0.id == d.id })
    }

    /// Edited when it was restored, as on the Android twin, so its card
    /// says so and sorts first rather than among older designs.
    func testARestoredDesignIsEditedNow() throws {
        var d = saved("Restored")
        d.updatedAt = 1_600_000_000_000
        XCTAssertTrue(DesignLibrary.snapshot(d, force: true))
        try damage(d.id)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let restored = try XCTUnwrap(DesignLibrary.restoreLastVersion(of: d.id, now: now))
        XCTAssertEqual(restored.updatedAt, 1_800_000_000_000)
        XCTAssertEqual(DesignLibrary.shelf().designs.first { $0.id == d.id }?.updatedAt, 1_800_000_000_000)
    }

    /// Deleted, a damaged design goes to Recently deleted with its versions,
    /// as on the Android twin, so it can still come back and be mended.
    func testADamagedDesignGoesToRecentlyDeleted() throws {
        let d = saved("Soon damaged")
        XCTAssertTrue(DesignLibrary.snapshot(d, force: true))
        try damage(d.id)
        DesignLibrary.trash(id: d.id)
        let entry = try XCTUnwrap(DesignLibrary.trashed().first { $0.id == d.id },
                                  "a damaged design was left out of Recently deleted")
        XCTAssertEqual(entry.title, DesignLibrary.damagedTitle)
        XCTAssertTrue(entry.damaged)

        DesignLibrary.restore(id: d.id)
        XCTAssertTrue(DesignLibrary.shelf().damaged.contains { $0.id == d.id })
        XCTAssertEqual(DesignLibrary.restoreLastVersion(of: d.id)?.title, "Soon damaged")
    }

    // MARK: no sweep while something is damaged

    private func orphanPhoto() throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { _ in }
        let src = try XCTUnwrap(MediaStore.storeOpaque(image))
        return MediaStore.directory.appendingPathComponent("\(src.dropFirst("media:".count)).jpg")
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// What a damaged design uses cannot be known, so nothing is swept until
    /// it is restored or deleted.
    func testNothingIsSweptWhileADesignIsDamaged() throws {
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        let orphan = try orphanPhoto()
        defer { try? FileManager.default.removeItem(at: orphan) }
        let d = saved("Soon damaged")
        try damage(d.id)
        DesignLibrary.pruneUnusedFiles(pasteboard: board)
        XCTAssertTrue(exists(orphan), "swept while a design could not be read")
        DesignLibrary.delete(id: d.id)
        DesignLibrary.pruneUnusedFiles(pasteboard: board)
        XCTAssertFalse(exists(orphan), "the sweep never came back")
    }

    func testNothingIsSweptWhileAVersionIsDamaged() throws {
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        let orphan = try orphanPhoto()
        defer { try? FileManager.default.removeItem(at: orphan) }
        let d = saved("Versioned")
        XCTAssertTrue(DesignLibrary.snapshot(d, force: true))
        let version = try XCTUnwrap(DesignLibrary.versions(for: d.id).first)
        try Data("{\"pages\": [".utf8).write(to: version.url)
        DesignLibrary.pruneUnusedMedia(pasteboard: board)
        XCTAssertTrue(exists(orphan), "swept while a version could not be read")
        DesignLibrary.delete(id: d.id)
        DesignLibrary.pruneUnusedMedia(pasteboard: board)
        XCTAssertFalse(exists(orphan))
    }
}
