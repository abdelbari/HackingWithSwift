// Version history: snapshots are deduplicated, rate-limited and thinned by
// age, pinned versions stay, and restoring one is a single undo step.

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
        let cap = DesignLibrary.versionCap
        for i in 0..<(cap + 5) {
            design.title = "title \(i)"
            XCTAssertTrue(DesignLibrary.snapshot(design, force: true, now: at(Double(i))))
        }
        let versions = DesignLibrary.versions(for: design.id)
        XCTAssertEqual(versions.count, cap)
        XCTAssertEqual(versions.first?.savedAt, at(Double(cap + 4)))
        XCTAssertEqual(versions.last?.savedAt, at(5))
        XCTAssertEqual(DesignLibrary.load(version: versions[0])?.title, "title \(cap + 4)")
    }

    /// One cut short, as versions written in place could be, ages out with
    /// the rest by the time in its name rather than staying for good.
    func testAVersionThatDoesNotReadAgesOut() throws {
        XCTAssertTrue(DesignLibrary.snapshot(design, force: true, now: at(0)))
        let dir = try XCTUnwrap(DesignLibrary.versions(for: design.id).first).url.deletingLastPathComponent()
        let old = at(-61 * 24 * 3600)
        let cutShort = dir.appendingPathComponent(DesignLibrary.versionStem(old) + ".json")
        try Data("{\"pages\": [".utf8).write(to: cutShort)
        design.title = "later"
        XCTAssertTrue(DesignLibrary.snapshot(design, force: true, now: at(1)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cutShort.path), "a version that does not read was kept for good")
        XCTAssertEqual(DesignLibrary.versions(for: design.id).count, 2)
    }

    // MARK: retention

    /// Written in milliseconds, as the Android twin names them; the seconds
    /// older builds wrote read too, and meta.json is no version.
    func testVersionNamesAreMillisecondsAndOldNamesStillRead() throws {
        XCTAssertEqual(DesignLibrary.versionStem(at(0.25)), "1700000000250")
        XCTAssertEqual(DesignLibrary.versionStamp("1700000000250"), 1_700_000_000_250)
        XCTAssertEqual(DesignLibrary.versionStamp("1700000000.123"), 1_700_000_000_123)
        XCTAssertNil(DesignLibrary.versionStamp("meta"))
        XCTAssertNil(DesignLibrary.versionStamp("-5"))

        XCTAssertTrue(DesignLibrary.snapshot(design, now: at(0)))
        let dir = try XCTUnwrap(DesignLibrary.versions(for: design.id).first).url.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("1700000000000.json").path))
        let legacy = dir.appendingPathComponent("1699999000.500.json")
        try JSONEncoder().encode(design).write(to: legacy)
        let versions = DesignLibrary.versions(for: design.id)
        XCTAssertEqual(versions.map(\.stem), ["1700000000000", "1699999000.500"])
        XCTAssertEqual(versions[1].savedAt, Date(timeIntervalSince1970: 1_699_999_000.5))
    }

    /// Noon UTC on 14 November 2023, in epoch milliseconds.
    private let noon: Double = 1_699_963_200_000
    private let minute: Double = 60_000

    /// A stem `minutes` before noon.
    private func stem(_ minutes: Double) -> String {
        String(Int64(noon - minutes * minute))
    }

    /// Ten days of edits, one every ten minutes up to noon: every one of the
    /// last two hours (12), the newest of each whole UTC hour back to 48
    /// hours (47 — the 10:00 one heads its hour, as the newer ones of that
    /// hour are under two hours old), and the newest of each whole UTC day
    /// back to 60 days (9: noon two days back, which is 48 hours old, and
    /// 23:50 on each of the eight days before it).
    func testPruningATenDayEditLog() {
        let log = (0..<1440).map { stem(Double($0) * 10) }
        let kept = DesignLibrary.retainedVersions(log, pinned: [], now: Date(timeIntervalSince1970: noon / 1000))
        XCTAssertEqual(kept.count, 68)
        // The last two hours, whole.
        for k in 0..<12 { XCTAssertTrue(kept.contains(stem(Double(k) * 10)), "minute \(k * 10)") }
        // 10:00 heads its hour; 9:50 heads the next; 9:40 goes.
        XCTAssertTrue(kept.contains(stem(120)))
        XCTAssertTrue(kept.contains(stem(130)))
        XCTAssertFalse(kept.contains(stem(140)))
        // 12:50 two days back is the oldest hourly one; 12:00 two days back
        // is 48 hours old, so the newest of its day.
        XCTAssertTrue(kept.contains(stem(48 * 60 - 50)))
        XCTAssertFalse(kept.contains(stem(48 * 60 - 40)))
        XCTAssertTrue(kept.contains(stem(48 * 60)))
        XCTAssertFalse(kept.contains(stem(48 * 60 + 10)))
        // 23:50 on each day before that, the newest of each.
        for day in 3...10 {
            let lastOfDay = Double(day * 24 * 60 - 12 * 60 + 10)
            XCTAssertTrue(kept.contains(stem(lastOfDay)), "day \(day)")
            XCTAssertFalse(kept.contains(stem(lastOfDay + 10)), "day \(day)")
            XCTAssertFalse(kept.contains(stem(Double(day * 24 * 60))), "noon, day \(day)")
        }
        // The first edit of the log, ten days back, goes.
        XCTAssertFalse(kept.contains(stem(1439 * 10)))
    }

    /// The Android twin's fixture, kept the same by both phones: midnight
    /// UTC on 4 October 2024 (1 728 000 000 000 ms, a whole day and hour),
    /// version i kept at now - i × 10 minutes for i in 0..<1440. Kept: i = 0
    /// to 12 (12 the newest of its hour among those over two hours old),
    /// every 6th from 13 to 283 (the newest of each hour), 288 (48 hours
    /// old, the newest of its day among the daily ones) and 289 + 144k up to
    /// 1297 (the newest of each day before) — 68 in all.
    func testPruningTheAndroidTwinsTenDayLog() {
        let now: Double = 1_728_000_000_000
        func stem(_ i: Int) -> String { String(Int64(now - Double(i) * 600_000)) }
        let log = (0..<1440).map(stem)
        let kept = DesignLibrary.retainedVersions(log, pinned: [], now: Date(timeIntervalSince1970: now / 1000))
        var expected = Array(0...12)
        expected += Array(stride(from: 13, through: 283, by: 6))
        expected.append(288)
        expected += Array(stride(from: 289, through: 1297, by: 144))
        XCTAssertEqual(expected.count, 68)
        XCTAssertEqual(kept, Set(expected.map(stem)))
        // Pruned again at the same moment, nothing more goes.
        XCTAssertEqual(DesignLibrary.retainedVersions(Array(kept), pinned: [], now: Date(timeIntervalSince1970: now / 1000)), kept)
    }

    /// A pinned version stays whatever its age; past 60 days nothing else
    /// does.
    func testPinnedVersionsSurvive() {
        let old = stem(61 * 24 * 60)
        let olderPinned = stem(90 * 24 * 60)
        let middle = stem(3 * 24 * 60 + 30)
        let log = [stem(0), middle, stem(3 * 24 * 60), old, olderPinned]
        let kept = DesignLibrary.retainedVersions(log, pinned: [olderPinned, middle, "gone"],
                                                  now: Date(timeIntervalSince1970: noon / 1000))
        XCTAssertEqual(kept, [stem(0), middle, stem(3 * 24 * 60), olderPinned])
    }

    /// Two hundred unpinned at most, the newest; pinned ones on top.
    func testTheCapCountsOnlyUnpinned() {
        let log = (0..<300).map { stem(Double($0) / 6) }
        let pinned = stem(299.0 / 6)
        let kept = DesignLibrary.retainedVersions(log, pinned: [pinned], now: Date(timeIntervalSince1970: noon / 1000))
        XCTAssertEqual(kept.count, DesignLibrary.versionCap + 1)
        XCTAssertTrue(kept.contains(stem(0)))
        XCTAssertTrue(kept.contains(stem(199.0 / 6)))
        XCTAssertFalse(kept.contains(stem(201.0 / 6)))
        XCTAssertTrue(kept.contains(pinned))
    }

    /// Pruning on disk keeps a pinned version past its time.
    func testAPinnedVersionOutlivesTheRule() throws {
        let old = at(-70 * 24 * 3600)
        XCTAssertTrue(DesignLibrary.snapshot(design, force: true, now: old))
        let first = try XCTUnwrap(DesignLibrary.versions(for: design.id).first)
        XCTAssertTrue(DesignLibrary.pinVersion(first.stem, of: design.id, name: "  Before client feedback "))
        design.title = "later"
        XCTAssertTrue(DesignLibrary.snapshot(design, force: true, now: at(0)))
        let versions = DesignLibrary.versions(for: design.id)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions.last?.pinnedName, "Before client feedback")
        XCTAssertTrue(versions.last?.isPinned == true)

        XCTAssertTrue(DesignLibrary.unpinVersion(first.stem, of: design.id))
        design.title = "later still"
        XCTAssertTrue(DesignLibrary.snapshot(design, force: true, now: at(1)))
        XCTAssertEqual(DesignLibrary.versions(for: design.id).count, 2, "unpinned, it aged out")
    }

    /// "Save a named version…" keeps one now, inside the interval, and pins
    /// it; with nothing changed it pins the newest instead.
    func testSavingANamedVersionPinsIt() throws {
        XCTAssertTrue(DesignLibrary.snapshot(design, now: at(0)))
        design.title = "renamed"
        let stem = try XCTUnwrap(DesignLibrary.saveNamedVersion(design, name: "Draft", now: at(5)))
        XCTAssertEqual(stem, DesignLibrary.versionStem(at(5)))
        XCTAssertEqual(DesignLibrary.versionMeta(for: design.id).pinned, [stem: "Draft"])
        let again = try XCTUnwrap(DesignLibrary.saveNamedVersion(design, name: "", now: at(6)))
        XCTAssertEqual(again, stem, "the same design pins the version it already has")
        XCTAssertEqual(DesignLibrary.versionMeta(for: design.id).pinned, [stem: ""])
        XCTAssertEqual(DesignLibrary.versions(for: design.id).count, 2)
    }

    /// meta.json as both phones write it, and leniently read.
    func testVersionMetaRoundTrips() throws {
        let meta = DesignLibrary.VersionMeta(pinned: ["1700000000000": "Before client feedback", "1699999000.500": ""])
        let data = try XCTUnwrap(meta.data)
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"pinned":{"1699999000.500":"","1700000000000":"Before client feedback"},"version":1}"#)
        XCTAssertEqual(DesignLibrary.VersionMeta.read(data), meta)
        let odd = Data(#"{"version":1,"pinned":{"a":"Kept","b":3},"extra":true}"#.utf8)
        XCTAssertEqual(DesignLibrary.VersionMeta.read(odd)?.pinned, ["a": "Kept"])
        XCTAssertEqual(DesignLibrary.VersionMeta.read(Data("{}".utf8)), DesignLibrary.VersionMeta())

        XCTAssertTrue(DesignLibrary.saveVersionMeta(meta, for: design.id))
        XCTAssertEqual(DesignLibrary.versionMeta(for: design.id), meta)
        // A backup's pins merge in; a name already here is kept.
        XCTAssertTrue(DesignLibrary.mergeVersionMeta(
            DesignLibrary.VersionMeta(pinned: ["1700000000000": "Other", "1": "New"]), for: design.id))
        XCTAssertEqual(DesignLibrary.versionMeta(for: design.id).pinned["1700000000000"], "Before client feedback")
        XCTAssertEqual(DesignLibrary.versionMeta(for: design.id).pinned["1"], "New")
    }

    /// A backup holds each design's meta.json as history/<id>.meta.json, as
    /// the Android twin writes it, and restoring one merges its pins in.
    func testABackupsVersionMetaIsOneFilePerDesign() throws {
        XCTAssertEqual(Backup.versionMetaEntry(for: "doc_1"), "history/doc_1.meta.json")
        XCTAssertEqual(Backup.versionMetaID("history/doc_1.meta.json"), "doc_1")
        XCTAssertNil(Backup.versionMetaID("history/doc_1/meta.json"))
        XCTAssertNil(Backup.versionMetaID("history/.meta.json"))
        XCTAssertNil(Backup.versionMetaID("designs/doc_1.meta.json"))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).canviabackup")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try ZipStore.Writer(url: url)
        let meta = Data(#"{"version":1,"pinned":{"1728000000000":"Before client feedback"}}"#.utf8)
        try writer.add(Backup.versionMetaEntry(for: design.id), meta)
        try writer.finish()
        let reader = try ZipStore.Reader(url: url)
        Backup.restoreVersionMeta(reader)
        XCTAssertEqual(DesignLibrary.versionMeta(for: design.id).pinned, ["1728000000000": "Before client feedback"])
    }

    /// Today, Yesterday, This week (two to six days back) and Earlier, by
    /// calendar day.
    func testVersionsGroupByDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "GMT"))
        let now = Date(timeIntervalSince1970: noon / 1000)
        func section(_ hoursAgo: Double) -> DesignLibrary.VersionSection {
            DesignLibrary.versionSection(now.addingTimeInterval(-hoursAgo * 3600), now: now, calendar: calendar)
        }
        XCTAssertEqual(section(-1), .today)
        XCTAssertEqual(section(12), .today)
        XCTAssertEqual(section(13), .yesterday)
        XCTAssertEqual(section(36), .yesterday)
        XCTAssertEqual(section(37), .thisWeek)
        XCTAssertEqual(section(6 * 24 + 12), .thisWeek)
        XCTAssertEqual(section(6 * 24 + 13), .earlier)
        XCTAssertEqual(DesignLibrary.VersionSection.allCases.map(\.rawValue), ["Today", "Yesterday", "This week", "Earlier"])

        let url = URL(fileURLWithPath: "/tmp/v.json")
        let versions = [now.addingTimeInterval(-40 * 3600), now, now.addingTimeInterval(-3600)].map {
            DesignLibrary.Version(url: url, savedAt: $0, pages: 1, elements: 1)
        }
        let groups = DesignLibrary.versionSections(versions, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.section), [.today, .thisWeek])
        XCTAssertEqual(groups[0].versions.map(\.savedAt), [now, now.addingTimeInterval(-3600)])
    }

    func testRestoreIsOneUndoStepAndKeepsTheId() {
        let store = DesignStore(design: design)
        XCTAssertTrue(DesignLibrary.snapshot(design, now: at(0)))
        let earlier = DesignLibrary.versions(for: design.id)[0]

        store.add(Element.shape("rect"))
        store.add(Element.shape("circle"))
        XCTAssertEqual(store.page.elements.count, 3)

        // Starred after that version was kept: the star stays.
        store.design.isStarred = true
        var old = DesignLibrary.load(version: earlier)!
        old.id = "someone-else"
        XCTAssertFalse(old.isStarred)
        store.restore(old)
        XCTAssertEqual(store.page.elements.count, 1)
        XCTAssertEqual(store.design.id, design.id)
        XCTAssertTrue(store.design.isStarred)
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
        XCTAssertEqual(store.announcement, "Deleted")
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
