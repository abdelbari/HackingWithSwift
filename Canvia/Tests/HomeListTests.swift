// Home's list view and Date created, as the Android twin's ShelfTest has
// them.

import XCTest
@testable import Canvia

final class HomeListTests: XCTestCase {

    private func made(_ id: String, _ title: String, edited: Double, created: Double) -> RecentDesign {
        RecentDesign(id: id, title: title, width: 1080, height: 1080, pages: 1, updatedAt: edited, createdAt: created)
    }

    /// Newest made first, a tie by title; Last edited stays the default.
    func testDateCreatedIsNewestMadeFirstATieByTitle() {
        let shelf = [
            made("a", "Poster", edited: 90, created: 10),
            made("b", "banner", edited: 10, created: 30),
            made("c", "Agenda", edited: 50, created: 30),
            made("d", "Card", edited: 70, created: 20),
        ]
        XCTAssertEqual(DesignLibrary.filter(shelf, query: "", sort: .created).map(\.id), ["c", "b", "d", "a"])
        XCTAssertEqual(DesignLibrary.filter(shelf, query: "", sort: .recent).map(\.id), ["a", "d", "c", "b"])
        XCTAssertEqual(DesignLibrary.Sort.allCases.first, .recent)
        XCTAssertEqual(DesignLibrary.Sort.created.label, "Date created")
    }

    /// Folders sort by the newest made inside them, a tie by name.
    func testFoldersSortByTheNewestMadeInside() {
        var a = made("a", "One", edited: 1, created: 10)
        a.folder = "Work"
        var b = made("b", "Two", edited: 2, created: 40)
        b.folder = "Home"
        var c = made("c", "Three", edited: 3, created: 40)
        c.folder = "Art"
        XCTAssertEqual(DesignLibrary.sortedFolders(["Work", "Home", "Art"], of: [a, b, c], sort: .created),
                       ["Art", "Home", "Work"])
    }

    /// The row's second line and what a screen reader hears of it.
    func testARowSaysItsTypeSizeAndWhenEdited() {
        var poster = made("p", "Poster", edited: 0, created: 0)
        poster.starred = true
        XCTAssertEqual(HomeLayout.line(poster, edited: "3 days ago"), "1080 × 1080 · Edited 3 days ago")
        XCTAssertEqual(HomeLayout.spoken(poster, edited: "Yesterday"), "Poster, edited yesterday, starred")
        poster.type = "insta-post"
        if let name = SizePreset.byId("insta-post")?.name {
            XCTAssertEqual(HomeLayout.line(poster, edited: "3 days ago"), "\(name) · 1080 × 1080 · Edited 3 days ago")
        }
    }

    /// Anything but "list" is the grid.
    func testTheLayoutIsTheGridUnlessSetToTheList() {
        XCTAssertEqual(HomeLayout.key, "homeLayout")
        XCTAssertTrue(HomeLayout.isList("list"))
        XCTAssertFalse(HomeLayout.isList("grid"))
        XCTAssertFalse(HomeLayout.isList(""))
        XCTAssertEqual(HomeLayout.toggleLabel(showingList: false), "Show as list")
    }
}
