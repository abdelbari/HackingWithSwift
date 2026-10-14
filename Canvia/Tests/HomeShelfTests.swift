// The shelf: when each design was last touched, in the Android twin's words.

import XCTest
@testable import Canvia

final class HomeShelfTests: XCTestCase {

    private let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT") ?? .current
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) throws -> Date {
        try XCTUnwrap(gmt.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)))
    }

    private func said(_ then: Date, at now: Date) -> String {
        RelativeTime.text(ms: then.timeIntervalSince1970 * 1000, now: now, calendar: gmt,
                          locale: Locale(identifier: "en_US_POSIX"))
    }

    func testTheTimeReadsAsThePhoneReadsIt() throws {
        let now = try date(2026, 3, 15, 12)
        XCTAssertEqual(said(now.addingTimeInterval(90), at: now), "Just now", "a clock that runs ahead")
        XCTAssertEqual(said(now.addingTimeInterval(-30), at: now), "Just now")
        XCTAssertEqual(said(now.addingTimeInterval(-60), at: now), "1 minute ago")
        XCTAssertEqual(said(now.addingTimeInterval(-59 * 60), at: now), "59 minutes ago")
        XCTAssertEqual(said(try date(2026, 3, 15, 11), at: now), "1 hour ago")
        XCTAssertEqual(said(try date(2026, 3, 15, 0, 5), at: now), "11 hours ago")
        XCTAssertEqual(said(try date(2026, 3, 14, 23), at: now), "Yesterday")
        XCTAssertEqual(said(try date(2026, 3, 14, 1), at: now), "Yesterday")
        XCTAssertEqual(said(try date(2026, 3, 10, 12), at: now), "5 days ago")
        XCTAssertEqual(said(try date(2026, 3, 5, 9), at: now), "5 Mar")
        XCTAssertEqual(said(try date(2025, 9, 8, 9), at: now), "8 Sep 2025")
    }

    /// Minutes before midnight are still minutes; two calendar days back is
    /// never "1 days ago".
    func testTheEdgesOfADay() throws {
        let justAfterMidnight = try date(2026, 3, 18, 0, 10)
        XCTAssertEqual(said(try date(2026, 3, 17, 23, 50), at: justAfterMidnight), "20 minutes ago")
        let early = try date(2026, 3, 18, 1)
        XCTAssertEqual(said(try date(2026, 3, 16, 23), at: early), "2 days ago")
    }

    /// On until turned off, as the Android twin's switch starts.
    func testVibrationIsOnUntilTurnedOff() throws {
        let name = "haptics-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertTrue(Haptics.isOn(defaults))
        defaults.set(false, forKey: Haptics.key)
        XCTAssertFalse(Haptics.isOn(defaults))
        defaults.set(true, forKey: Haptics.key)
        XCTAssertTrue(Haptics.isOn(defaults))
    }

    // MARK: quick actions

    private func recent(_ id: String, _ title: String, at: Double) -> RecentDesign {
        RecentDesign(id: id, title: title, width: 1080, height: 1080, pages: 1, updatedAt: at)
    }

    /// New post, New story, then the two most recently touched designs.
    func testQuickActionsStartOrPickUp() {
        let items = QuickActions.items(recents: [recent("a", "Old", at: 1), recent("b", "  ", at: 3),
                                                 recent("c", "Newest", at: 5)])
        XCTAssertEqual(items.map(\.title), ["New post", "New story", "Newest", "Untitled design"])
        XCTAssertEqual(items.map(\.type), [QuickActions.newType, QuickActions.newType,
                                           QuickActions.openType, QuickActions.openType])
        XCTAssertEqual(items[1].info[QuickActions.presetKey], "insta-story")
        XCTAssertEqual(items[2].info[QuickActions.designKey], "c")
        XCTAssertEqual(QuickActions.items(recents: []).count, 2)
    }

    /// A new design of the type, named after it — any type in the
    /// catalogue, so it starts in its unit; an open for a safe id only;
    /// nothing for an action this app does not know.
    func testAQuickActionBecomesALaunchRequest() throws {
        XCTAssertEqual(QuickActions.request(type: QuickActions.newType, info: [QuickActions.presetKey: "insta-story"]),
                       .newType(id: "insta-story", title: "Instagram Story"))
        XCTAssertEqual(QuickActions.request(type: QuickActions.newType, info: [:]),
                       .newType(id: "insta-post", title: "Instagram Post"))
        XCTAssertEqual(QuickActions.request(type: QuickActions.newType, info: [QuickActions.presetKey: "tiktok-video"]),
                       .newType(id: "tiktok-video", title: "TikTok Video"))
        let first = try XCTUnwrap(SizePreset.all.first)
        XCTAssertEqual(QuickActions.request(type: QuickActions.newType, info: [QuickActions.presetKey: "billboard"]),
                       .newType(id: first.id, title: first.name))
        XCTAssertEqual(QuickActions.request(type: QuickActions.openType, info: [QuickActions.designKey: "doc_ab-12"]),
                       .open(id: "doc_ab-12"))
        XCTAssertNil(QuickActions.request(type: QuickActions.openType, info: [QuickActions.designKey: "../secrets"]))
        XCTAssertNil(QuickActions.request(type: QuickActions.openType, info: [:]))
        XCTAssertNil(QuickActions.request(type: "app.canvia.dance", info: [:]))
        XCTAssertFalse(QuickActions.isSafeId("é"))
        XCTAssertFalse(QuickActions.isSafeId(""))
    }

    func testPagesAndMidSentence() {
        XCTAssertEqual(RelativeTime.pages(1), "1 page")
        XCTAssertEqual(RelativeTime.pages(4), "4 pages")
        XCTAssertEqual(RelativeTime.lowercasedFirst("Yesterday"), "yesterday")
        XCTAssertEqual(RelativeTime.lowercasedFirst("5 Mar"), "5 Mar")
    }

    // MARK: starred

    /// "starred": true only when starred; a file without the key, or with
    /// false, reads as not starred and is written back without it.
    func testTheStarRoundTripsAndIsLeftOutWhenOff() throws {
        var design = Design(title: "Star", width: 100, height: 100)
        let plain = String(decoding: try JSONEncoder().encode(design), as: UTF8.self)
        XCTAssertFalse(plain.contains("starred"))
        XCTAssertFalse(try JSONDecoder().decode(Design.self, from: Data(plain.utf8)).isStarred)

        design.isStarred = true
        let data = try JSONEncoder().encode(design)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""starred":true"#))
        var back = try JSONDecoder().decode(Design.self, from: data)
        XCTAssertTrue(back.isStarred)

        back.isStarred = false
        XCTAssertNil(back.starred)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(back), as: UTF8.self).contains("starred"))
        let off = Data(#"{"id":"d1","title":"Off","starred":false}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Design.self, from: off).starred)
        let odd = Data(#"{"id":"d1","title":"Odd","starred":"yes"}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Design.self, from: odd).isStarred)
    }

    /// The shelf carries the star, so Home need not open the design; and
    /// writes it only when on.
    func testTheShelfEntryCarriesTheStar() throws {
        var design = Design(title: "Shelf", width: 100, height: 100)
        let plain = DesignLibrary.ShelfEntry(design, id: design.id, modified: 1)
        XCTAssertNil(plain.starred)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(plain), as: UTF8.self).contains("starred"))
        design.isStarred = true
        let entry = DesignLibrary.ShelfEntry(design, id: design.id, modified: 1)
        let back = try JSONDecoder().decode(DesignLibrary.ShelfEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(back.starred, true)
    }

    /// Starred folders first, then the starred designs, both in the
    /// current sort and search; a starred folder with nothing left in it is
    /// not shown.
    func testTheStarredFilter() {
        var a = recent("a", "Alpha", at: 1)
        a.starred = true
        a.folder = "Clients"
        var b = recent("b", "Beta", at: 5)
        b.starred = true
        let c = recent("c", "Gamma", at: 9)
        var d = recent("d", "Delta", at: 3)
        d.folder = "Archive"
        let designs = [a, b, c, d]
        let starred: Set<String> = ["Clients", "Archive", "Gone"]
        let byDate = DesignLibrary.starredShelf(designs, starredFolders: starred, query: "", sort: .recent)
        XCTAssertEqual(byDate.folders, ["Archive", "Clients"])
        XCTAssertEqual(byDate.designs.map(\.id), ["b", "a"])
        let byName = DesignLibrary.starredShelf(designs, starredFolders: starred, query: "", sort: .name)
        XCTAssertEqual(byName.designs.map(\.id), ["a", "b"])
        let searched = DesignLibrary.starredShelf(designs, starredFolders: [], query: "bet", sort: .recent)
        XCTAssertEqual(searched.folders, [])
        XCTAssertEqual(searched.designs.map(\.id), ["b"])
        XCTAssertEqual(DesignLibrary.starredEmpty, "Star a design from its ⋯ menu to find it here.")
    }

    /// The Android twin's ShelfTest rows: a folder sorts as its designs
    /// together do, and a search narrows folders by name.
    func testStarredFoldersSortAndSearchAsOnAndroid() {
        func item(_ id: String, _ title: String, pages: Int, at: Double, folder: String?) -> RecentDesign {
            var made = RecentDesign(id: id, title: title, width: 1080, height: 1080, pages: pages, updatedAt: at, folder: folder)
            made.starred = ["b", "c", "d"].contains(id)
            return made
        }
        let designs = [
            item("a", "Café menu", pages: 2, at: 30, folder: "Clients"),
            item("b", "birthday card", pages: 1, at: 50, folder: nil),
            item("c", "Annual report", pages: 9, at: 10, folder: "clients work"),
            item("d", "Poster", pages: 9, at: 40, folder: "Clients"),
            item("e", "Zine", pages: 3, at: 20, folder: "Archive"),
        ]
        let starred: Set<String> = ["Clients", "Archive", "Gone"]
        // "Gone" holds nothing; "Clients" (newest 40) before "Archive" (20).
        let recent = DesignLibrary.starredShelf(designs, starredFolders: starred, query: "", sort: .recent)
        XCTAssertEqual(recent.folders, ["Clients", "Archive"])
        XCTAssertEqual(recent.designs.map(\.id), ["b", "d", "c"])
        let named = DesignLibrary.starredShelf(designs, starredFolders: starred, query: "", sort: .name)
        XCTAssertEqual(named.folders, ["Archive", "Clients"])
        XCTAssertEqual(named.designs.map(\.id), ["c", "b", "d"])
        // Most pages: a folder's pages added up — Clients 11, Archive 3.
        let largest = DesignLibrary.starredShelf(designs, starredFolders: starred, query: "", sort: .largest)
        XCTAssertEqual(largest.folders, ["Clients", "Archive"])
        XCTAssertEqual(largest.designs.map(\.id), ["d", "c", "b"])
        let found = DesignLibrary.starredShelf(designs, starredFolders: starred, query: "arch", sort: .recent)
        XCTAssertEqual(found.folders, ["Archive"])
        XCTAssertEqual(found.designs.map(\.id), [])
        XCTAssertEqual(DesignLibrary.starredShelf(designs, starredFolders: starred, query: "ÁRCH", sort: .recent).folders,
                       ["Archive"])
    }

    /// The home-folders list: bare names still read, starred ones written
    /// as objects; a star follows a rename and goes with a delete.
    func testStarredFoldersInTheHomeFoldersList() throws {
        let read = DesignLibrary.homeFolders(fromJSON: #"["Old", {"name":"Clients","starred":true}, 4, {"x":1}, " Old "]"#)
        XCTAssertEqual(read, [DesignLibrary.HomeFolder(name: "Old"),
                              DesignLibrary.HomeFolder(name: "Clients", starred: true)])
        XCTAssertEqual(DesignLibrary.homeFoldersJSON(read), #"["Old",{"name":"Clients","starred":true}]"#)
        XCTAssertEqual(DesignLibrary.homeFolders(fromJSON: "not json"), [])

        let name = "home-folders-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(#"["Old"]"#, forKey: DesignLibrary.homeFoldersKey)
        DesignLibrary.setFolderStarred("Clients", true, defaults: defaults)
        DesignLibrary.setFolderStarred("Old", true, defaults: defaults)
        XCTAssertEqual(DesignLibrary.starredFolders(defaults), ["Clients", "Old"])
        DesignLibrary.setFolderStarred("Old", false, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: DesignLibrary.homeFoldersKey), #"["Old",{"name":"Clients","starred":true}]"#)
        DesignLibrary.renameFolderStar("Clients", to: "Customers", defaults: defaults)
        XCTAssertEqual(DesignLibrary.starredFolders(defaults), ["Customers"])
        DesignLibrary.renameFolderStar("Customers", to: nil, defaults: defaults)
        XCTAssertEqual(DesignLibrary.starredFolders(defaults), [])
        XCTAssertEqual(DesignLibrary.renamePlan([filed("x", in: "Mine")], from: "Mine", to: "Ours")?.from, "Mine")
    }

    private func filed(_ id: String, in folder: String) -> RecentDesign {
        var r = recent(id, id, at: 1)
        r.folder = folder
        return r
    }

    /// A copy — duplicated, copied and resized, or kept from a version — is
    /// not starred; a design restored from Recently deleted still is.
    func testCopiesAreNotStarredButARestoreKeepsTheStar() throws {
        var design = Design(title: "Kept", width: 100, height: 100)
        design.isStarred = true
        XCTAssertFalse(CopyResize.freshCopy(of: design).isStarred)
        XCTAssertFalse(CopyResize.madeCopy(of: design, taken: []).isStarred)

        XCTAssertTrue(DesignLibrary.save(design))
        defer { DesignLibrary.delete(id: design.id) }
        let copy = try XCTUnwrap(DesignLibrary.saveCopy(of: design, savedAt: Date(), folder: nil))
        defer { DesignLibrary.delete(id: copy.id) }
        XCTAssertFalse(copy.isStarred)

        DesignLibrary.trash(id: design.id)
        DesignLibrary.restore(id: design.id)
        XCTAssertEqual(DesignLibrary.load(id: design.id)?.isStarred, true)
        XCTAssertTrue(DesignLibrary.setStarred(id: design.id, false))
        XCTAssertEqual(DesignLibrary.load(id: design.id)?.starred, nil)
        XCTAssertEqual(DesignLibrary.load(id: design.id)?.updatedAt, design.updatedAt, "starring is not an edit")
    }
}
