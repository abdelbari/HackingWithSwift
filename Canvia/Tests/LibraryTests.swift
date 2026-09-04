// The design library: the trash, and finding a design among many.

import XCTest
@testable import Canvia

final class LibraryTests: XCTestCase {

    private var ids: [String] = []

    override func tearDown() {
        for id in ids { DesignLibrary.delete(id: id) }
        ids = []
    }

    private func saved(_ title: String, pages: Int = 1) -> Design {
        var d = Design(title: title, width: 300, height: 200)
        d.pages = (0..<pages).map { _ in Page() }
        DesignLibrary.save(d)
        ids.append(d.id)
        return d
    }

    // MARK: trash

    func testTrashedDesignsLeaveRecentsAndCanComeBack() {
        let d = saved("Poster")
        XCTAssertTrue(DesignLibrary.recents().contains { $0.id == d.id })

        DesignLibrary.trash(id: d.id)
        XCTAssertFalse(DesignLibrary.recents().contains { $0.id == d.id })
        XCTAssertTrue(DesignLibrary.trashed().contains { $0.id == d.id })
        XCTAssertNil(DesignLibrary.load(id: d.id), "a trashed design must not open")

        DesignLibrary.restore(id: d.id)
        XCTAssertTrue(DesignLibrary.recents().contains { $0.id == d.id })
        XCTAssertFalse(DesignLibrary.trashed().contains { $0.id == d.id })
        XCTAssertEqual(DesignLibrary.load(id: d.id)?.title, "Poster")
    }

    func testTheTrashKeepsVersionsForARestore() {
        let d = saved("Versioned")
        XCTAssertTrue(DesignLibrary.snapshot(d, force: true))
        DesignLibrary.trash(id: d.id)
        DesignLibrary.restore(id: d.id)
        XCTAssertEqual(DesignLibrary.versions(for: d.id).count, 1)
    }

    func testOnlyWhatIsPastRetentionIsPurged() {
        let old = saved("Old"), fresh = saved("Fresh")
        let now = Date()
        DesignLibrary.trash(id: old.id, now: now.addingTimeInterval(-DesignLibrary.trashRetention - 60))
        DesignLibrary.trash(id: fresh.id, now: now.addingTimeInterval(-60))
        let purged = DesignLibrary.purgeTrash(now: now)
        XCTAssertEqual(purged, [old.id])
        XCTAssertEqual(DesignLibrary.trashed().map(\.id).filter { [old.id, fresh.id].contains($0) }, [fresh.id])
    }

    func testDeleteForeverRemovesFromTheTrashToo() {
        let d = saved("Gone")
        DesignLibrary.trash(id: d.id)
        DesignLibrary.delete(id: d.id)
        XCTAssertFalse(DesignLibrary.trashed().contains { $0.id == d.id })
        XCTAssertFalse(DesignLibrary.recents().contains { $0.id == d.id })
    }

    // MARK: search and sort

    private func recent(_ title: String, pages: Int = 1, width: Double = 1080, at: Double) -> RecentDesign {
        RecentDesign(id: UID.make("doc"), title: title, width: width, height: 1080,
                     pages: pages, updatedAt: at, thumbnail: nil)
    }

    func testSearchMatchesTitlesLooselyAndSizesExactly() {
        let list = [recent("Café menu", at: 3), recent("Summer sale", at: 2),
                    recent("Untitled", width: 1920, at: 1)]
        XCTAssertEqual(DesignLibrary.filter(list, query: "cafe").map(\.title), ["Café menu"])
        XCTAssertEqual(DesignLibrary.filter(list, query: "SALE").map(\.title), ["Summer sale"])
        XCTAssertEqual(DesignLibrary.filter(list, query: "1920x1080").map(\.title), ["Untitled"])
        XCTAssertEqual(DesignLibrary.filter(list, query: "  ").count, 3, "blank is no filter")
        XCTAssertTrue(DesignLibrary.filter(list, query: "zzz").isEmpty)
    }

    func testEachSortIsWhatItSays() {
        let list = [recent("b", pages: 1, at: 1), recent("A", pages: 3, at: 2), recent("c", pages: 3, at: 3)]
        XCTAssertEqual(DesignLibrary.filter(list, query: "", sort: .recent).map(\.title), ["c", "A", "b"])
        XCTAssertEqual(DesignLibrary.filter(list, query: "", sort: .name).map(\.title), ["A", "b", "c"])
        XCTAssertEqual(DesignLibrary.filter(list, query: "", sort: .largest).map(\.title), ["c", "A", "b"],
                       "ties on page count fall back to most recent")
    }
}
