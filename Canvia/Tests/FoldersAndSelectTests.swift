// Folders renamed and deleted as a whole, Select on Home over the designs on
// show, and a kept version saved as a copy — the same cases as the Android
// twin's.

import XCTest
@testable import Canvia

final class FoldersAndSelectTests: XCTestCase {

    private func recent(_ id: String, _ title: String, folder: String?) -> RecentDesign {
        RecentDesign(id: id, title: title, width: 100, height: 100, pages: 1, updatedAt: 0, folder: folder)
    }

    private var shelf: [RecentDesign] {
        [recent("a", "Beach", folder: "Trips"), recent("b", "Hike", folder: "Trips"),
         recent("c", "Work poster", folder: "Work"), recent("d", "Ski", folder: "Trips"),
         recent("e", "Loose", folder: nil)]
    }

    // MARK: rename folder

    func testRenameMovesExactlyTheFoldersDesigns() {
        let plan = DesignLibrary.renamePlan(shelf, from: "Trips", to: "  Holidays ")
        XCTAssertEqual(plan?.ids, ["a", "b", "d"])
        XCTAssertEqual(plan?.name, "Holidays")
        XCTAssertEqual(plan?.merges, false)
    }

    func testRenameToABlankOrOverlongNameIsRejected() {
        XCTAssertNil(DesignLibrary.renamePlan(shelf, from: "Trips", to: "   "))
        XCTAssertNil(DesignLibrary.renamePlan(shelf, from: "Trips", to: String(repeating: "x", count: 41)))
        XCTAssertNotNil(DesignLibrary.renamePlan(shelf, from: "Trips", to: String(repeating: "x", count: 40)))
        // Counted in UTF-16 units, as Android counts: 21 emoji are 42.
        XCTAssertNil(DesignLibrary.renamePlan(shelf, from: "Trips", to: String(repeating: "😀", count: 21)))
        XCTAssertNotNil(DesignLibrary.renamePlan(shelf, from: "Trips", to: String(repeating: "😀", count: 20)))
    }

    func testRenameOntoAnotherFolderIsAMerge() {
        let plan = DesignLibrary.renamePlan(shelf, from: "Trips", to: " Work")
        XCTAssertEqual(plan?.merges, true)
        XCTAssertEqual(plan?.ids, ["a", "b", "d"])
        // Exactly the same name only: another case is a folder of its own.
        XCTAssertEqual(DesignLibrary.renamePlan(shelf, from: "Trips", to: "work")?.merges, false)
        // Its own name is no rename at all, even with spaces around it.
        XCTAssertNil(DesignLibrary.renamePlan(shelf, from: "Trips", to: "Trips"))
        XCTAssertNil(DesignLibrary.renamePlan(shelf, from: "Trips", to: " Trips "))
    }

    func testFolderNameIsTrimmedAndBlankIsNone() {
        XCTAssertEqual(DesignLibrary.folderName("  Clients "), "Clients")
        XCTAssertNil(DesignLibrary.folderName("   "))
        XCTAssertNil(DesignLibrary.folderName(nil))
    }

    func testRenamingRefilesTheDesignsOnDisk() throws {
        var one = Design(title: "one", width: 100, height: 100)
        one.folder = "Trips"
        var two = Design(title: "two", width: 100, height: 100)
        two.folder = "Trips"
        XCTAssertTrue(DesignLibrary.save(one))
        XCTAssertTrue(DesignLibrary.save(two))
        defer {
            DesignLibrary.delete(id: one.id)
            DesignLibrary.delete(id: two.id)
        }
        let plan = try XCTUnwrap(DesignLibrary.renamePlan(
            [recent(one.id, "one", folder: "Trips"), recent(two.id, "two", folder: "Trips")],
            from: "Trips", to: "Holidays"))
        for id in plan.ids { XCTAssertTrue(DesignLibrary.move(id: id, toFolder: plan.name)) }
        XCTAssertEqual(DesignLibrary.load(id: one.id)?.folder, "Holidays")
        XCTAssertEqual(DesignLibrary.load(id: two.id)?.folder, "Holidays")
    }

    // MARK: select

    func testSelectAllPicksOnlyTheDesignsOnShow() {
        let shown = DesignLibrary.filter(shelf, query: "", sort: .name, folder: "Trips")
        var picked = DesignLibrary.togglingAll([], among: shown)
        XCTAssertEqual(picked, ["a", "b", "d"])
        XCTAssertTrue(DesignLibrary.allPicked(picked, among: shown))
        // A search narrows what Select all takes.
        let searched = DesignLibrary.filter(shelf, query: "ski", sort: .name, folder: nil)
        XCTAssertEqual(DesignLibrary.togglingAll([], among: searched), ["d"])
        // Deselect all lets go of the shown ones only.
        picked.insert("e")
        XCTAssertFalse(DesignLibrary.allPicked(picked, among: DesignLibrary.filter(shelf, query: "", sort: .name, folder: nil)))
        XCTAssertEqual(DesignLibrary.togglingAll(picked, among: shown), ["e"])
        XCTAssertFalse(DesignLibrary.allPicked([], among: []))
    }

    func testEveryPickedDesignIsActedOnShownOrNot() {
        // "c" is in Work, out of sight while Trips is shown, and still taken;
        // "gone" is no longer on the shelf.
        let all = DesignLibrary.filter(shelf, query: "", sort: .name, folder: nil)
        XCTAssertEqual(DesignLibrary.picked(["a", "c", "d", "gone"], among: all).map(\.id), ["a", "d", "c"])
    }

    // MARK: copy of a version

    func testCopyOfVersionTitle() {
        XCTAssertEqual(DesignLibrary.versionCopyTitle("Poster", date: "3 Oct 2026, 14:05"),
                       "Poster (version from 3 Oct 2026, 14:05)")
        XCTAssertEqual(DesignLibrary.versionCopyTitle(Design().title, date: "3 Oct 2026, 14:05"),
                       "Untitled design (version from 3 Oct 2026, 14:05)")
        XCTAssertEqual(DesignLibrary.versionCopyTitle("  ", date: "3 Oct 2026, 14:05"),
                       "Untitled design (version from 3 Oct 2026, 14:05)")
    }

    func testCopyOfVersionIsANewDesignInTheSameFolder() throws {
        let started = Date().timeIntervalSince1970 * 1000
        var design = Design(title: "Poster", width: 400, height: 300)
        design.pages[0].elements = [Element.text("kept", fontSize: 24, w: 200)]
        design.folder = "Old"
        design.createdAt = started - 3 * 86_400_000
        XCTAssertTrue(DesignLibrary.save(design))
        XCTAssertTrue(DesignLibrary.snapshot(design, force: true))
        defer { DesignLibrary.delete(id: design.id) }
        let version = try XCTUnwrap(DesignLibrary.versions(for: design.id).first)
        let kept = try XCTUnwrap(DesignLibrary.load(version: version))

        let copy = try XCTUnwrap(DesignLibrary.saveCopy(of: kept, savedAt: version.savedAt, folder: "Now"))
        defer { DesignLibrary.delete(id: copy.id) }
        XCTAssertNotEqual(copy.id, design.id)
        XCTAssertEqual(copy.title, "Poster (version from \(DesignLibrary.versionCopyDate(version.savedAt)))")
        XCTAssertEqual(copy.folder, "Now")
        // Made now, as Android's copy is, not three days ago with the design.
        XCTAssertGreaterThanOrEqual(copy.createdAt, started)
        XCTAssertEqual(copy.pages[0].elements.first?.text, "kept")
        XCTAssertEqual(DesignLibrary.load(id: copy.id)?.title, copy.title)
        // The design it was kept of is as it was.
        XCTAssertEqual(DesignLibrary.load(id: design.id)?.title, "Poster")
        XCTAssertEqual(DesignLibrary.load(id: design.id)?.folder, "Old")
    }
}
