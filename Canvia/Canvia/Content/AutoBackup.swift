// Settings ▸ Backup's "Back up automatically": the backup (Backup) written
// on its own, daily or weekly, into a folder the person picked, keeping the
// newest few — so a lost phone loses no more than a week. Kept as the
// preference "autoBackup" on both phones, and carried in a backup's own
// settings under the same key:
//
//   {"on": true, "every": "daily"|"weekly", "keep": 3, "folder": "<uri or
//    bookmark b64>", "lastAt": ms, "lastBytes": n, "lastError": string|null}
//
// every key written, in that order — "folder" null until one is picked,
// "lastAt" and "lastBytes" 0 until the first backup. A key missing, or of
// another kind, reads as its default. The rules are the Android twin's
// core/persistence/AutoBackup.kt, with the shared fixture
// Tests/Fixtures/auto-backup.json; AutoBackups writes them.

import Foundation

enum AutoBackup {

    static let key = "autoBackup"

    static let daily = "daily"
    static let weekly = "weekly"

    /// How often, as the Settings row offers it: Daily, Weekly.
    static let everyChoices = [daily, weekly]

    /// How many backups are kept, as the Settings row offers it.
    static let keepChoices = [1, 3, 5]

    static let dayMs: Int64 = 24 * 60 * 60 * 1000

    /// What every backup it writes is called, before its date
    /// (Backup.fileName).
    static let prefix = "Canvia backup "

    struct Config: Equatable {
        var on = false
        var every = AutoBackup.weekly
        var keep = 3
        /// The folder's security-scoped bookmark in base 64 here, Android's
        /// tree URI there; nil until a folder is picked.
        var folder: String?
        /// When the last one was written, in ms since 1970; 0 for never.
        var lastAt: Int64 = 0
        /// How big it was, in bytes.
        var lastBytes: Int64 = 0
        /// Why the last try could not run; nil when it ran.
        var lastError: String?
    }

    /// A day or a week, in ms.
    static func intervalMs(_ every: String) -> Int64 { every == daily ? dayMs : 7 * dayMs }

    /// Whether a backup is due at `now`: on, with a folder, at least its
    /// interval since the last (`lastAt`) — and something changed since:
    /// the newest design, upload or brand kit, `newestChange` (its
    /// updatedAt; nil for nothing at all), after `lastAt`. Nothing changed
    /// is skipped, however long ago the last was; a first backup is due as
    /// soon as there is anything to back up.
    static func isDue(_ config: Config, now: Int64, newestChange: Int64?) -> Bool {
        guard config.on, let folder = config.folder, !folder.isEmpty else { return false }
        guard now - config.lastAt >= intervalMs(config.every) else { return false }
        guard let newestChange else { return false }
        return newestChange > config.lastAt
    }

    /// Whether `name` is one of its backups: the prefix, then anything,
    /// then ".canviabackup".
    static func isOurs(_ name: String) -> Bool {
        name.hasPrefix(prefix) && name.hasSuffix("." + Backup.ext)
    }

    /// The backups in a folder of `names` to delete so that `keep` are
    /// left: of the names that are its backups (`isOurs`), all but the last
    /// `keep` in name order — the date in the name sorts them oldest first
    /// — oldest first. Anything else in the folder is never touched.
    static func pruned(_ names: [String], keep: Int) -> [String] {
        let ours = names.filter(isOurs).sorted()
        return Array(ours.prefix(max(ours.count - max(keep, 1), 0)))
    }

    /// "Last backed up 2 days ago · 184 MB": the Settings row, from the
    /// time since it ran (`ago`, RelativeTime's words) and its `size`.
    static func lastNote(ago: String, size: String) -> String {
        tr("Last backed up %@ · %@", ago, size)
    }

    /// What a backup that could not run says, on Home's banner and in
    /// Settings.
    static var failed: String { tr("Automatic backup couldn't run — choose the folder again") }

    // MARK: the preference

    /// As JSON writes it, every key — the folder and the error as null
    /// when there are none: what a backup's settings carry.
    static func object(_ config: Config) -> [String: Any] {
        [
            "on": config.on, "every": config.every, "keep": config.keep,
            "folder": config.folder.map { $0 as Any } ?? NSNull(),
            "lastAt": config.lastAt, "lastBytes": config.lastBytes,
            "lastError": config.lastError.map { $0 as Any } ?? NSNull(),
        ]
    }

    /// The preference as stored: every key, in the order above, written
    /// out here so the text is the Android twin's character for character.
    static func encode(_ config: Config) -> String {
        func text(_ value: String?) -> String { value.map(ExportLast.quoted) ?? "null" }
        let fields = [
            "\"on\":" + String(config.on),
            "\"every\":" + ExportLast.quoted(config.every),
            "\"keep\":" + String(config.keep),
            "\"folder\":" + text(config.folder),
            "\"lastAt\":" + String(config.lastAt),
            "\"lastBytes\":" + String(config.lastBytes),
            "\"lastError\":" + text(config.lastError),
        ]
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// The settings in `object`; each key missing, of another kind or out
    /// of range at its default: "every" one of everyChoices, "keep" one of
    /// keepChoices, the times never before 1970.
    static func read(_ object: [String: Any]) -> Config {
        var config = Config()
        if let on = object["on"], isBoolean(on), let value = on as? Bool { config.on = value }
        if let every = object["every"] as? String, everyChoices.contains(every) { config.every = every }
        if let keep = whole(object["keep"]), keepChoices.contains(Int(keep)) { config.keep = Int(keep) }
        if let folder = object["folder"] as? String, !folder.isEmpty { config.folder = folder }
        config.lastAt = max(whole(object["lastAt"]) ?? 0, 0)
        config.lastBytes = max(whole(object["lastBytes"]) ?? 0, 0)
        config.lastError = object["lastError"] as? String
        return config
    }

    /// The settings in `text`; the defaults when there are none that read.
    static func decode(_ text: String?) -> Config {
        guard let data = text?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return Config() }
        return read(object)
    }

    /// Whether a value JSON read is a true or false, not a number.
    private static func isBoolean(_ value: Any) -> Bool {
        (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
    }

    /// A whole number JSON read — never a true or false, a fraction or a
    /// string — or nil.
    private static func whole(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded(), abs(double) < 9e15 else { return nil }
        return number.int64Value
    }
}
