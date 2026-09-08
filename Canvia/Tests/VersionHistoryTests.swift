// Version history: snapshots are deduplicated, rate-limited and capped, and
// restoring one is a single undo step.

import XCTest
@testable import Canvia

@MainActor
final class VersionHistoryTests: XCTestCase {

    private var design = Design(title: "history", width: 400, height: 300)

    override func setUp() {
        design = Design(title: "history", width: 400, height: 300)
        design.pages[0].elements = [Element.text("one", fontSize: 24, w: 200)]
        DesignLibrary.clearVersions(for: design.id)
    }

    override func tearDown() {
        DesignLibrary.clearVersions(for: design.id)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    func testFirstSnapshotIsWritten() {
        XCTAssertTrue(DesignLibrary.snapshot(design, now: at(0)))
        let versions = DesignLibrary.versions(for: design.id)
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(versions[0].pages, 1)
        XCTAssertEqual(versions[0].elements, 1)
    }

    func testIdenticalContentIsNotRecordedTwice() {
        XCTAssertTrue(DesignLibrary.snapshot(design, now: at(0)))
        XCTAssertFalse(DesignLibrary.snapshot(design, now: at(1000)))
        XCTAssertFalse(DesignLibrary.snapshot(design, force: true, now: at(2000)))
        XCTAssertEqual(DesignLibrary.versions(for: design.id).count, 1)
    }

    func testChangesInsideTheIntervalWaitUnlessForced() {
        XCTAssertTrue(DesignLibrary.snapshot(design, now: at(0)))
        design.pages[0].elements.append(Element.shape("rect"))
        XCTAssertFalse(DesignLibrary.snapshot(design, now: at(10)))
        XCTAssertTrue(DesignLibrary.snapshot(design, force: true, now: at(10)))
        design.pages[0].elements.append(Element.shape("circle"))
        XCTAssertTrue(DesignLibrary.snapshot(design, now: at(10 + DesignLibrary.versionInterval + 1)))
        XCTAssertEqual(DesignLibrary.versions(for: design.id).count, 3)
    }

    func testVersionsAreNewestFirstAndCapped() {
        let limit = DesignLibrary.versionLimit
        for i in 0..<(limit + 5) {
            design.title = "title \(i)"
            XCTAssertTrue(DesignLibrary.snapshot(design, force: true, now: at(Double(i))))
        }
        let versions = DesignLibrary.versions(for: design.id)
        XCTAssertEqual(versions.count, limit)
        XCTAssertEqual(versions.first?.savedAt, at(Double(limit + 4)))
        XCTAssertEqual(versions.last?.savedAt, at(5))
        XCTAssertEqual(DesignLibrary.load(version: versions[0])?.title, "title \(limit + 4)")
    }

    func testRestoreIsOneUndoStepAndKeepsTheId() {
        let store = DesignStore(design: design)
        XCTAssertTrue(DesignLibrary.snapshot(design, now: at(0)))
        let earlier = DesignLibrary.versions(for: design.id)[0]

        store.add(Element.shape("rect"))
        store.add(Element.shape("circle"))
        XCTAssertEqual(store.page.elements.count, 3)

        var old = DesignLibrary.load(version: earlier)!
        old.id = "someone-else"
        store.restore(old)
        XCTAssertEqual(store.page.elements.count, 1)
        XCTAssertEqual(store.design.id, design.id)
        XCTAssertEqual(store.announcement, "Restored an earlier version")

        store.undo()
        XCTAssertEqual(store.page.elements.count, 3)
    }

    func testDeletingADesignDropsItsHistory() {
        XCTAssertTrue(DesignLibrary.snapshot(design, now: at(0)))
        DesignLibrary.delete(id: design.id)
        XCTAssertTrue(DesignLibrary.versions(for: design.id).isEmpty)
    }

    // MARK: announcements

    func testDeleteAnnouncesWhatUndoWouldBringBack() {
        let store = DesignStore(design: design)
        store.selection = [store.page.elements[0].id]
        store.deleteSelected()
        XCTAssertEqual(store.announcement, "Deleted 1 element")
    }

    // MARK: photos

    func testOnlyPicturesAndVideosCanGoToPhotos() {
        XCTAssertTrue(PhotoSaver.canSave(URL(fileURLWithPath: "/tmp/a.png")))
        XCTAssertTrue(PhotoSaver.canSave(URL(fileURLWithPath: "/tmp/a.JPG")))
        XCTAssertTrue(PhotoSaver.canSave(URL(fileURLWithPath: "/tmp/a.mp4")))
        XCTAssertTrue(PhotoSaver.isVideo(URL(fileURLWithPath: "/tmp/a.mp4")))
        XCTAssertFalse(PhotoSaver.isVideo(URL(fileURLWithPath: "/tmp/a.gif")))
        XCTAssertFalse(PhotoSaver.canSave(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertFalse(PhotoSaver.canSave(URL(fileURLWithPath: "/tmp/a.svg")))
    }
}
