// Uploads and Home's folders in Recently deleted, with the shared fixture
// Fixtures/uploads-trash.json — the Android twin's UploadsTrashTest reads
// the same file.

import XCTest
@testable import Canvia

final class UploadsTrashTests: XCTestCase {

    /// The shared vectors: the launch sweep takes what has waited more than
    /// thirty days, and only that.
    func testTheLaunchSweepTakesWhatHasWaitedMoreThanThirtyDays() throws {
        let fixture = try SharedFixture.object("uploads-trash")
        let now = try XCTUnwrap(fixture["now"] as? NSNumber).doubleValue
        let before = try XCTUnwrap(fixture["before"] as? [[String: Any]])
        let after = try XCTUnwrap(fixture["after"] as? [[String: Any]])
        XCTAssertEqual(Uploads.stale(before, now: now), fixture["stale"] as? [String])
        XCTAssertTrue(NSArray(array: Uploads.swept(before, now: now)).isEqual(to: after))
        // Read as entries, the deleted time comes through, a font aside.
        let entries = Uploads.entries(of: before)
        XCTAssertNil(entries.first { $0.id == "img-live" }?.deleted)
        XCTAssertEqual(entries.first { $0.id == "vid-edge" }?.deleted, 1_757_408_000_000)
        XCTAssertEqual(entries.first { $0.id == "img-old" }?.folder, "Trips")
    }

    func testDeletingMarksTheEntryRestoringTakesTheMarkAwayTheRestIsKept() {
        let raw: [[String: Any]] = [["id": "img-a", "kind": "image", "added": 1, "folder": "Trips", "x": 1],
                                    ["id": "img-b", "kind": "image", "added": 2]]
        let gone = Uploads.trashing(raw, ids: ["img-a"], now: 500)
        XCTAssertEqual(Uploads.deletedTime(gone[0]), 500)
        XCTAssertEqual(gone[0]["folder"] as? String, "Trips")
        XCTAssertEqual(gone[0]["x"] as? Int, 1)
        XCTAssertNil(Uploads.deletedTime(gone[1]))
        // Deleted again, it keeps the time it went.
        XCTAssertEqual(Uploads.deletedTime(Uploads.trashing(gone, ids: ["img-a"], now: 900)[0]), 500)
        let back = Uploads.restoring(gone, ids: ["img-a"])
        XCTAssertNil(back[0][Uploads.deletedKey])
        XCTAssertTrue(NSArray(array: back).isEqual(to: raw))
        // A deleted that is no number is no time.
        XCTAssertNil(Uploads.deletedTime(["id": "x", "deleted": "yesterday"]))
    }

    func testAFolderGoesToRecentlyDeletedWithWhatWentWithItAndComesBackWithItsStar() {
        typealias Folder = DesignLibrary.HomeFolder
        let folders = [Folder(name: "Trips", starred: true), Folder(name: "Work")]
        let gone = DesignLibrary.trashingFolder(folders, path: "Trips", now: 700, designs: ["d1"], uploads: ["img-a"])
        let deleted = Folder(name: "Trips", starred: true, deleted: 700, designs: ["d1"], uploads: ["img-a"])
        XCTAssertEqual(DesignLibrary.deletedFolders(gone), [deleted])
        XCTAssertEqual(gone.filter { $0.deleted == nil }.map(\.name), ["Work"])
        let text = DesignLibrary.homeFoldersJSON(gone)
        XCTAssertEqual(text, #"["Work",{"deleted":700,"designs":["d1"],"name":"Trips","starred":true,"uploads":["img-a"]}]"#)
        XCTAssertEqual(DesignLibrary.homeFolders(fromJSON: text), gone)
        // The Android twin's order of keys reads the same.
        let android = #"["Work",{"name":"Trips","starred":true,"deleted":700,"designs":["d1"],"uploads":["img-a"]}]"#
        XCTAssertEqual(DesignLibrary.homeFolders(fromJSON: android), gone)
        // Renaming a live folder of the same name leaves it be.
        XCTAssertEqual(DesignLibrary.deletedFolders(DesignLibrary.renamingFolder(gone, from: "Trips", to: "Holidays")), [deleted])
        XCTAssertEqual(DesignLibrary.leavingTrash(gone, folder: deleted, restored: true),
                       [Folder(name: "Work"), Folder(name: "Trips", starred: true)])
        XCTAssertEqual(DesignLibrary.leavingTrash(gone, folder: deleted, restored: false), [Folder(name: "Work")])
        let day = 86_400_000.0
        XCTAssertEqual(DesignLibrary.staleFolders(gone, now: 700 + 31 * day), [deleted])
        XCTAssertEqual(DesignLibrary.staleFolders(gone, now: 700 + 30 * day), [])
    }

    func testAStarredFolderInRecentlyDeletedIsNotStarredOnHome() throws {
        let name = "home-folders-trash-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let gone = DesignLibrary.trashingFolder([.init(name: "Trips", starred: true)], path: "Trips", now: 1,
                                                designs: [], uploads: [])
        DesignLibrary.setHomeFolders(gone, defaults: defaults)
        XCTAssertEqual(DesignLibrary.starredFolders(defaults), [])
        XCTAssertEqual(DesignLibrary.storedHomeFolders(defaults), gone)
    }
}
