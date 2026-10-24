// Folders inside folders: the path rules both phones share — the Android
// twin's FolderPathsTest, row for row.

import XCTest
@testable import Canvia

final class FolderPathsTests: XCTestCase {

    private func item(_ id: String, _ folder: String?) -> RecentDesign {
        RecentDesign(id: id, title: id, width: 1080, height: 1080, pages: 1, updatedAt: 0, folder: folder)
    }

    private var shelf: [RecentDesign] {
        [item("a", "Clients/Acme/2026"), item("b", "Clients/Acme"), item("c", "Clients/Bolt"),
         item("d", "Personal"), item("e", nil)]
    }

    /// Shared: how a path is kept, row by row.
    func testAPathIsKeptTrimmedSegmentBySegmentEmptyOnesLeftOut() {
        let cases: [(String, String?)] = [
            ("Clients/Acme/2026", "Clients/Acme/2026"),
            (" Clients / Acme ", "Clients/Acme"),
            ("Clients//Acme/", "Clients/Acme"),
            ("Flat name", "Flat name"),
            ("  ", nil),
            ("/", nil),
        ]
        for (raw, kept) in cases { XCTAssertEqual(DesignLibrary.folderName(raw), kept, raw) }
    }

    /// Shared: what may name a folder and be one.
    func testNamesHaveNoSlashAndAtMost40UnitsPathsAtMostFourLevels() {
        XCTAssertTrue(DesignLibrary.isFolderName("Acme"))
        XCTAssertFalse(DesignLibrary.isFolderName("Acme/2026"))
        XCTAssertFalse(DesignLibrary.isFolderName("   "))
        XCTAssertTrue(DesignLibrary.isFolderName(String(repeating: "x", count: 40)))
        XCTAssertFalse(DesignLibrary.isFolderName(String(repeating: "x", count: 41)))
        // Forty UTF-16 units, not forty letters: 20 emoji are 40 units.
        XCTAssertTrue(DesignLibrary.isFolderName(String(repeating: "😀", count: 20)))
        XCTAssertFalse(DesignLibrary.isFolderName(String(repeating: "😀", count: 20) + "a"))
        XCTAssertTrue(DesignLibrary.isFolderPath("A/B/C/D"))
        XCTAssertFalse(DesignLibrary.isFolderPath("A/B/C/D/E"))
        XCTAssertFalse(DesignLibrary.isFolderPath("A/" + String(repeating: "x", count: 41)))
        XCTAssertFalse(DesignLibrary.isFolderPath(" A/B"))
    }

    func testSegmentsParentsLeavesAndTheBreadcrumb() {
        XCTAssertEqual(DesignLibrary.segments("Clients/Acme/2026"), ["Clients", "Acme", "2026"])
        XCTAssertEqual(DesignLibrary.parentOf("Clients/Acme/2026"), "Clients/Acme")
        XCTAssertNil(DesignLibrary.parentOf("Clients"))
        XCTAssertEqual(DesignLibrary.leafName("Clients/Acme/2026"), "2026")
        XCTAssertEqual(DesignLibrary.childPath("Clients", " Acme "), "Clients/Acme")
        XCTAssertEqual(DesignLibrary.childPath(nil, "Acme"), "Acme")
        let crumbs = DesignLibrary.breadcrumb("Clients/Acme")
        XCTAssertEqual(crumbs.map(\.name), ["Clients", "Acme"])
        XCTAssertEqual(crumbs.map(\.path), ["Clients", "Clients/Acme"])
        XCTAssertTrue(DesignLibrary.isInside("Clients/Acme/2026", "Clients"))
        XCTAssertTrue(DesignLibrary.isInside("Clients", "Clients"))
        XCTAssertFalse(DesignLibrary.isInside("Clientsville", "Clients"))
    }

    /// Shared: children and what a folder holds.
    func testChildrenAreTheFoldersRightInsideAncestorsIncluded() {
        let all = DesignLibrary.folders(in: shelf)
        XCTAssertEqual(all, ["Clients", "Clients/Acme", "Clients/Acme/2026", "Clients/Bolt", "Personal"])
        XCTAssertEqual(DesignLibrary.children(all, of: nil), ["Clients", "Personal"])
        XCTAssertEqual(DesignLibrary.children(all, of: "Clients"), ["Clients/Acme", "Clients/Bolt"])
        XCTAssertEqual(DesignLibrary.children(all, of: "Clients/Acme"), ["Clients/Acme/2026"])
        XCTAssertEqual(DesignLibrary.designs(shelf, in: "Clients/Acme", recursive: false).map(\.id), ["b"])
        XCTAssertEqual(DesignLibrary.designs(shelf, in: "Clients", recursive: true).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(DesignLibrary.designs(shelf, in: "Clients", recursive: false).map(\.id), [])
    }

    /// Shared: a rename rewrites every path under it, and merges into one
    /// already there.
    func testRenamingRewritesThePrefixOfEverythingInside() throws {
        let plan = try XCTUnwrap(DesignLibrary.renamePlan(shelf, from: "Clients/Acme", to: "Acme Ltd"))
        XCTAssertEqual(plan.name, "Clients/Acme Ltd")
        XCTAssertEqual(plan.ids, ["a", "b"])
        XCTAssertFalse(plan.merges)
        XCTAssertEqual(DesignLibrary.movedFolder("Clients/Acme/2026", from: "Clients/Acme", to: plan.name),
                       "Clients/Acme Ltd/2026")
        XCTAssertEqual(DesignLibrary.movedFolder("Clients/Bolt", from: "Clients/Acme", to: plan.name), "Clients/Bolt")
        XCTAssertEqual(DesignLibrary.renamePlan(shelf, from: "Clients/Acme", to: "Bolt")?.merges, true)
        XCTAssertNil(DesignLibrary.renamePlan(shelf, from: "Clients/Acme", to: "A/B"))
        XCTAssertNil(DesignLibrary.renamePlan(shelf, from: "Clients/Acme", to: "Acme"))
        // A folder only uploads are filed in is a merge too.
        XCTAssertEqual(DesignLibrary.renamePlan(shelf, from: "Clients/Acme", to: "Logos")?.merges, false)
        XCTAssertEqual(DesignLibrary.renamePlan(shelf, from: "Clients/Acme", to: "Logos",
                                                uploads: ["Clients/Logos"])?.merges, true)
    }

    /// Shared: moving a folder into another, cycles and depth refused.
    func testAFolderMovesIntoAnotherNeverIntoItselfNeverPastFourLevels() {
        let all = DesignLibrary.folders(in: shelf)
        XCTAssertEqual(DesignLibrary.movedInto(all, from: "Clients/Acme", into: "Personal"), "Personal/Acme")
        XCTAssertEqual(DesignLibrary.movedInto(all, from: "Clients/Acme", into: nil), "Acme")
        XCTAssertNil(DesignLibrary.movedInto(all, from: "Clients", into: "Clients/Acme"))
        XCTAssertNil(DesignLibrary.movedInto(all, from: "Clients", into: "Clients"))
        XCTAssertNil(DesignLibrary.movedInto(all, from: "Clients/Acme", into: "Clients"))
        // Acme holds 2026: in A/B/C it would be five deep.
        let deep = all + ["A/B/C"]
        XCTAssertNil(DesignLibrary.movedInto(deep, from: "Clients/Acme", into: "A/B/C"))
        XCTAssertEqual(DesignLibrary.movedInto(deep, from: "Clients/Bolt", into: "A/B/C"), "A/B/C/Bolt")
        // Move contents up: inside Acme, up a level.
        XCTAssertEqual(DesignLibrary.movedFolder("Clients/Acme/2026", from: "Clients/Acme", to: "Clients"), "Clients/2026")
        XCTAssertEqual(DesignLibrary.movedFolder("Clients/Acme", from: "Clients/Acme", to: "Clients"), "Clients")
        XCTAssertNil(DesignLibrary.movedFolder("Personal", from: "Personal", to: nil))
    }

    func testStarsAreKeptByWholePathAndFollowARename() {
        typealias Folder = DesignLibrary.HomeFolder
        let stars = [Folder(name: "Clients/Acme", starred: true), Folder(name: "Clients/Acme/2026", starred: true),
                     Folder(name: "Personal", starred: true)]
        let renamed = DesignLibrary.renamingFolder(stars, from: "Clients/Acme", to: "Clients/Acme Ltd")
        XCTAssertEqual(Set(renamed.filter(\.starred).map(\.name)), ["Clients/Acme Ltd", "Clients/Acme Ltd/2026", "Personal"])
        // Moved up to the top, a deleted folder's star goes; those inside it move.
        let up = DesignLibrary.renamingFolder(stars, from: "Clients/Acme", to: nil)
        XCTAssertEqual(Set(up.map(\.name)), ["2026", "Personal"])
        // Deleted with Move contents up, a starred folder does not star the one it is in.
        let removed = DesignLibrary.removingFolder(stars, from: "Clients/Acme", up: "Clients")
        XCTAssertEqual(Set(removed.filter(\.starred).map(\.name)), ["Clients/2026", "Personal"])
        let kept = DesignLibrary.removingFolder(stars + [Folder(name: "Clients", starred: true)], from: "Clients/Acme", up: "Clients")
        XCTAssertEqual(Set(kept.filter(\.starred).map(\.name)), ["Clients", "Clients/2026", "Personal"])
        XCTAssertEqual(Set(DesignLibrary.removingFolder(stars, from: "Clients/Acme", up: nil).map(\.name)), ["2026", "Personal"])
        let text = DesignLibrary.homeFoldersJSON(renamed)
        XCTAssertEqual(Set(DesignLibrary.homeFolders(fromJSON: text).map(\.name)), Set(renamed.map(\.name)))
    }

    func testAnUploadIsFiledInAFolderKeptWithItsEntry() throws {
        let raw: [[String: Any]] = [["id": "img-1", "kind": "image", "added": 1],
                                    ["id": "img-2", "kind": "image", "added": 2]]
        let filed = Uploads.filed(raw, id: "img-1", folder: " Clients / Acme ")
        XCTAssertEqual(filed[0]["folder"] as? String, "Clients/Acme")
        XCTAssertNil(filed[1]["folder"])
        let data = try JSONSerialization.data(withJSONObject: filed, options: [.sortedKeys])
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""folder":"Clients\/Acme""#)
                      || String(decoding: data, as: UTF8.self).contains(#""folder":"Clients/Acme""#))
        let read = Uploads.entries(of: filed)
        XCTAssertEqual(read[0].folder, "Clients/Acme")
        XCTAssertEqual(Uploads.inFolder(read, path: "Clients", recursive: true).map(\.id), ["img-1"])
        XCTAssertEqual(Uploads.inFolder(read, path: "Clients", recursive: false).map(\.id), [])
        XCTAssertNil(Uploads.entries(of: Uploads.filed(filed, id: "img-1", folder: nil))[0].folder)
        // A folder renamed takes its uploads with it.
        let moved = Uploads.entries(of: Uploads.refiled(filed, from: "Clients", to: "Customers"))
        XCTAssertEqual(moved[0].folder, "Customers/Acme")
    }

    /// Shared: a font is never filed, and one with a folder written reads as
    /// in none, so it never makes a folder on Home.
    func testAFontIsNeverInAFolder() {
        let font: [[String: Any]] = [["id": "abcdef012345", "kind": "font", "added": 1]]
        XCTAssertNil(Uploads.filed(font, id: "abcdef012345", folder: "Brand")[0]["folder"])
        let written: [[String: Any]] = [["id": "abcdef012345", "kind": "font", "added": 1, "folder": "Brand"]]
        XCTAssertTrue(Uploads.entries(of: written).isEmpty)
        XCTAssertEqual(Uploads.refiled(written, from: "Brand", to: "Logos")[0]["folder"] as? String, "Brand")
    }
}
