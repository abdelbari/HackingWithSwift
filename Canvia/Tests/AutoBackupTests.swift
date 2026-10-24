// Settings ▸ Backup's "Back up automatically" — the Android twin's
// AutoBackupTest, with the shared fixture Fixtures/auto-backup.json: when a
// backup is due, which files keep-N pruning deletes, and the preference as
// both phones write it, in a backup's settings too.

import XCTest
@testable import Canvia

final class AutoBackupTests: XCTestCase {

    private func shared() throws -> [String: Any] {
        try SharedFixture.object("auto-backup")
    }

    /// Shared: the fixture's "due" rows, the same on both phones.
    func testABackupIsDueAfterItsIntervalWhenSomethingChangedSinceTheLast() throws {
        let rows = try XCTUnwrap(try shared()["due"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 10)
        for row in rows {
            let name = try XCTUnwrap(row["name"] as? String)
            let config = AutoBackup.read(try XCTUnwrap(row["config"] as? [String: Any]))
            let now = try XCTUnwrap(row["now"] as? NSNumber).int64Value
            let newest = (row["newest"] as? NSNumber)?.int64Value
            XCTAssertEqual(AutoBackup.isDue(config, now: now, newestChange: newest),
                           try XCTUnwrap(row["due"] as? Bool), name)
        }
    }

    /// Shared: the same file's pruning rows.
    func testPruningKeepsTheNewestNOfItsOwnBackupsAndTouchesNothingElse() throws {
        let rows = try XCTUnwrap(try shared()["prune"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 5)
        for row in rows {
            let files = try XCTUnwrap(row["files"] as? [String])
            let keep = try XCTUnwrap(row["keep"] as? Int)
            XCTAssertEqual(AutoBackup.pruned(files, keep: keep), try XCTUnwrap(row["deleted"] as? [String]),
                           try XCTUnwrap(row["name"] as? String))
        }
    }

    func testEachBackupIsNamedForItsDay() throws {
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12)))
        XCTAssertEqual(Backup.fileName(day), "Canvia backup 2026-10-24.canviabackup")
        let next = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 5, hour: 12)))
        XCTAssertEqual(Backup.fileName(next), "Canvia backup 2027-01-05.canviabackup")
        XCTAssertTrue(AutoBackup.isOurs(Backup.fileName(day)))
        XCTAssertFalse(AutoBackup.isOurs("Canvia backup 2026-01-01.zip"))
    }

    func testThePreferenceIsWrittenWholeInOrderAndReadBackWithItsDefaults() {
        let config = AutoBackup.Config(on: true, every: AutoBackup.daily, keep: 5, folder: "content://tree/1",
                                       lastAt: 1_700_000_000_000, lastBytes: 184_000_000, lastError: nil)
        XCTAssertEqual(AutoBackup.encode(config),
                       #"{"on":true,"every":"daily","keep":5,"folder":"content://tree/1","lastAt":1700000000000,"lastBytes":184000000,"lastError":null}"#)
        XCTAssertEqual(AutoBackup.decode(AutoBackup.encode(config)), config)
        XCTAssertEqual(AutoBackup.encode(AutoBackup.Config()),
                       #"{"on":false,"every":"weekly","keep":3,"folder":null,"lastAt":0,"lastBytes":0,"lastError":null}"#)
        // Missing, of another kind or out of range: the default.
        XCTAssertEqual(AutoBackup.decode(nil), AutoBackup.Config())
        XCTAssertEqual(AutoBackup.decode(#"{"on":"yes","every":"hourly","keep":4,"folder":"","lastAt":-5}"#),
                       AutoBackup.Config())
        XCTAssertEqual(AutoBackup.decode(#"{"on":true,"keep":1}"#), AutoBackup.Config(on: true, keep: 1))
        XCTAssertEqual(AutoBackup.decode(#"{"on":1,"keep":true}"#), AutoBackup.Config(), "numbers are not switches")
        XCTAssertEqual(AutoBackup.intervalMs(AutoBackup.weekly), 7 * AutoBackup.dayMs)
        XCTAssertEqual(AutoBackup.intervalMs(AutoBackup.daily), AutoBackup.dayMs)
    }

    func testABackupsOwnSettingsCarryItUnderTheSameKey() throws {
        let config = AutoBackup.Config(on: true, every: AutoBackup.weekly, keep: 3, folder: "bookmark==",
                                       lastAt: 5, lastBytes: 6, lastError: "gone")
        let data = Backup.encodeSettings(autoLists: true, use: nil, exportA11yNudge: true, proofTypography: true,
                                         accessibility: AccessibilityPrefs.Settings(), recentSearches: [],
                                         recentTemplates: [], autoBackup: config)
        XCTAssertEqual(Backup.decodeAutoBackup(data), config)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let written = try XCTUnwrap(object["autoBackup"] as? [String: Any])
        XCTAssertEqual(Set(written.keys), ["on", "every", "keep", "folder", "lastAt", "lastBytes", "lastError"])
        XCTAssertNil(Backup.decodeAutoBackup(Data(#"{"autoLists":true}"#.utf8)))
    }

    func testTheSettingsRowSaysWhenAndHowBig() {
        XCTAssertEqual(AutoBackup.lastNote(ago: "2 days ago", size: "184 MB"), "Last backed up 2 days ago · 184 MB")
    }
}
