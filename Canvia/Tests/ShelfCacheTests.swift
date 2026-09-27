// The shelf cache: Home's summaries of the designs, read from shelf.json
// while each design's file is unchanged, and kept right as designs are
// renamed, copied, filed, trashed and restored.

import XCTest
import UIKit
@testable import Canvia

final class ShelfCacheTests: XCTestCase {

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

    private var shelfURL: URL {
        DesignLibrary.designsDir.appendingPathComponent(DesignLibrary.shelfFileName)
    }

    private func cachedEntries() throws -> [DesignLibrary.ShelfEntry] {
        try JSONDecoder().decode([DesignLibrary.ShelfEntry].self, from: Data(contentsOf: shelfURL))
    }

    private func onShelf(_ id: String) -> RecentDesign? {
        DesignLibrary.recents().first { $0.id == id }
    }

    /// An unchanged design is summarised from the cache, not decoded again;
    /// once its file changes, it is read afresh.
    func testUnchangedDesignsComeFromTheCache() throws {
        let d = saved("Cached")
        XCTAssertEqual(onShelf(d.id)?.title, "Cached")
        var entries = try cachedEntries()
        let i = try XCTUnwrap(entries.firstIndex { $0.id == d.id })
        XCTAssertEqual(entries[i].width, 300)
        XCTAssertEqual(entries[i].pages, 1)
        XCTAssertEqual(entries[i].createdAt, d.createdAt, accuracy: 0.001)
        entries[i].title = "From the cache"
        try JSONEncoder().encode(entries).write(to: shelfURL)
        XCTAssertEqual(onShelf(d.id)?.title, "From the cache", "an unchanged design was decoded again")

        var renamed = d
        renamed.title = "Renamed"
        XCTAssertTrue(DesignLibrary.save(renamed))
        XCTAssertEqual(onShelf(d.id)?.title, "Renamed", "a changed design was not read again")
    }

    func testAnEntryGoesWithItsDesign() throws {
        let d = saved("Short-lived")
        XCTAssertNotNil(onShelf(d.id))
        XCTAssertTrue(try cachedEntries().contains { $0.id == d.id })
        DesignLibrary.delete(id: d.id)
        XCTAssertNil(onShelf(d.id))
        XCTAssertFalse(try cachedEntries().contains { $0.id == d.id })
    }

    /// The cache sits among the designs and is not taken for one, nor for
    /// a damaged one.
    func testTheCacheIsNotADesign() {
        _ = saved("Neighbour")
        let shelf = DesignLibrary.shelf()
        XCTAssertFalse(shelf.designs.contains { $0.id == "shelf" })
        XCTAssertFalse(shelf.damaged.contains { $0.id == "shelf" })
    }

    /// Rename, duplicate, move to a folder, trash and restore each show on
    /// the shelf at once.
    func testTheShelfFollowsEverythingHomeDoesToADesign() {
        var d = saved("Original")
        XCTAssertNotNil(onShelf(d.id))

        d.title = "Renamed"
        XCTAssertTrue(DesignLibrary.save(d))
        XCTAssertEqual(onShelf(d.id)?.title, "Renamed")

        var copy = d
        copy.id = UID.make("doc")
        copy.title += " (copy)"
        XCTAssertTrue(DesignLibrary.save(copy))
        ids.append(copy.id)
        XCTAssertEqual(onShelf(copy.id)?.title, "Renamed (copy)")
        XCTAssertEqual(onShelf(d.id)?.title, "Renamed")

        XCTAssertTrue(DesignLibrary.move(id: d.id, toFolder: "Work"))
        XCTAssertEqual(onShelf(d.id)?.folder, "Work")

        DesignLibrary.trash(id: d.id)
        XCTAssertNil(onShelf(d.id))
        DesignLibrary.restore(id: d.id)
        XCTAssertEqual(onShelf(d.id)?.title, "Renamed")
        XCTAssertEqual(onShelf(d.id)?.folder, "Work")
    }

    /// A card's picture is not read with the shelf, only its time; the
    /// card reads it when it shows, and keeps it.
    func testACardReadsItsPictureWhenItShows() async throws {
        let d = saved("Pictured")
        XCTAssertNil(onShelf(d.id)?.thumbnailStamp)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 20), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 30, height: 20))
        }
        DesignLibrary.saveThumbnail(picture, for: d.id)
        let stamp = try XCTUnwrap(onShelf(d.id)?.thumbnailStamp)
        XCTAssertNil(DesignLibrary.cachedCardImage(for: d.id, stamp: stamp, trashed: false))
        let shown = await DesignLibrary.cardImage(for: d.id, stamp: stamp, trashed: false)
        XCTAssertEqual(shown?.size, CGSize(width: 30, height: 20))
        XCTAssertNotNil(DesignLibrary.cachedCardImage(for: d.id, stamp: stamp, trashed: false))
    }
}
