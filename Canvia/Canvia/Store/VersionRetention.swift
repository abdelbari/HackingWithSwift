// How long version history reaches back, and the versions you name and keep.
//
// History is thinned rather than cut off: every version from the last two
// hours, then the newest of each hour for the past 48 hours, then the
// newest of each day for the past 60 days — and every pinned version, for
// good. At most 200 unpinned versions are kept, the newest. Pruning runs
// after each snapshot. The Android twin's VersionPolicy keeps by the same
// rule.
//
// Version files are named by when they were kept, in epoch milliseconds —
// "1760000000123.json", as the Android twin names them. Older builds of this
// app named them in seconds, "1760000000.123.json"; both are read.
//
// A version is pinned in the sidecar history/<designId>/meta.json:
// {"version":1,"pinned":{"<fileStem>":"Before client feedback"}}, an empty
// name being pinned without one.

import Foundation

extension DesignLibrary {

    /// Every version this recent is kept.
    static let keepAllWithin: TimeInterval = 2 * 3600
    /// Then the newest of each hour, this far back.
    static let keepHourlyWithin: TimeInterval = 48 * 3600
    /// Then the newest of each day, this far back.
    static let keepDailyWithin: TimeInterval = 60 * 24 * 3600
    /// The most unpinned versions a design keeps, whatever their times.
    static let versionCap = 200

    /// The sidecar's name in a design's history folder.
    static let versionMetaName = "meta.json"

    /// When a version file stem says it was kept, in epoch milliseconds:
    /// "1760000000123" as written now, or "1760000000.123", seconds, as
    /// older builds wrote it. Nil for anything else, meta.json among them.
    static func versionStamp(_ stem: String) -> Double? {
        if stem.contains(".") {
            guard let seconds = Double(stem), seconds.isFinite, seconds >= 0 else { return nil }
            return (seconds * 1000).rounded()
        }
        guard let ms = Int64(stem), ms >= 0 else { return nil }
        return Double(ms)
    }

    /// The file stem a version kept at `date` is written under.
    static func versionStem(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    /// The stems to keep of those given, by the rule above, at `now`.
    ///
    /// Each version falls in one tier by its age. The hours and days are
    /// whole hours and days of epoch time (UTC), so the rule needs no time
    /// zone and both phones keep the same files: within a tier, the newest
    /// version of each such hour or day is kept. A version from the future
    /// — a clock put back — counts as recent. Unparseable stems are passed
    /// over, so never kept here.
    static func retainedVersions(_ stems: [String], pinned: Set<String>, now: Date) -> Set<String> {
        let nowMs = now.timeIntervalSince1970 * 1000
        let hour = 3_600_000.0
        let day = 86_400_000.0
        var kept = Set<String>()
        // The newest stem per bucket, keyed by tier and bucket number.
        var newest: [String: (stem: String, ms: Double)] = [:]
        for stem in stems {
            guard let ms = versionStamp(stem) else { continue }
            let age = nowMs - ms
            if age < keepAllWithin * 1000 {
                kept.insert(stem)
                continue
            }
            let key: String
            if age < keepHourlyWithin * 1000 {
                key = "h\(Int64((ms / hour).rounded(.down)))"
            } else if age < keepDailyWithin * 1000 {
                key = "d\(Int64((ms / day).rounded(.down)))"
            } else {
                continue
            }
            if let held = newest[key], held.ms >= ms { continue }
            newest[key] = (stem, ms)
        }
        kept.formUnion(newest.values.map { $0.stem })
        // The cap, newest first, over the unpinned only.
        let unpinned = kept.subtracting(pinned)
            .compactMap { stem in versionStamp(stem).map { (stem, $0) } }
            .sorted { $0.1 > $1.1 }
        if unpinned.count > versionCap {
            kept.subtract(unpinned.dropFirst(versionCap).map { $0.0 })
        }
        // Pinned versions always stay.
        return kept.union(pinned.filter { stems.contains($0) })
    }

    /// Thins a design's history folder by the rule above: what is not kept
    /// is deleted, whether or not it still reads.
    static func pruneVersions(of id: String, now: Date = Date()) {
        let files = versionFiles(in: historyDir(for: id))
        let stems = files.map { $0.deletingPathExtension().lastPathComponent }
        let keep = retainedVersions(stems, pinned: Set(versionMeta(for: id).pinned.keys), now: now)
        for url in files where !keep.contains(url.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: pinned versions

    /// history/<designId>/meta.json: the pinned versions and their names.
    struct VersionMeta: Codable, Equatable, Sendable {
        var version = 1
        /// Version file stem → its name; "" is pinned without one.
        var pinned: [String: String] = [:]

        init(pinned: [String: String] = [:]) {
            self.pinned = pinned
        }

        private enum CodingKeys: String, CodingKey { case version, pinned }

        /// Lenient: a name that is not text is passed over, and a file from
        /// another build keeps what it can.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = (try? c.decode(Int.self, forKey: .version)) ?? 1
            let raw = (try? c.decode([String: PinnedName].self, forKey: .pinned)) ?? [:]
            pinned = raw.compactMapValues(\.name)
        }

        private struct PinnedName: Decodable {
            var name: String?
            init(from decoder: Decoder) throws {
                name = try? decoder.singleValueContainer().decode(String.self)
            }
        }

        /// As written, keys sorted.
        var data: Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try? encoder.encode(self)
        }

        static func read(_ data: Data) -> VersionMeta? {
            try? JSONDecoder().decode(VersionMeta.self, from: data)
        }
    }

    static func versionMetaURL(for id: String) -> URL {
        historyDir(for: id).appendingPathComponent(versionMetaName)
    }

    /// The design's pins; none when there is no sidecar or it does not read.
    static func versionMeta(for id: String) -> VersionMeta {
        guard let data = try? Data(contentsOf: versionMetaURL(for: id)) else { return VersionMeta() }
        return VersionMeta.read(data) ?? VersionMeta()
    }

    @discardableResult
    static func saveVersionMeta(_ meta: VersionMeta, for id: String) -> Bool {
        let dir = historyDir(for: id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = meta.data else { return false }
        return (try? data.write(to: versionMetaURL(for: id), options: .atomic)) != nil
    }

    /// Pins a version under a name — trimmed; blank is pinned without one.
    @discardableResult
    static func pinVersion(_ stem: String, of id: String, name: String) -> Bool {
        var meta = versionMeta(for: id)
        meta.pinned[stem] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return saveVersionMeta(meta, for: id)
    }

    /// Unpinned, it ages out with the rest at the next snapshot.
    @discardableResult
    static func unpinVersion(_ stem: String, of id: String) -> Bool {
        var meta = versionMeta(for: id)
        guard meta.pinned.removeValue(forKey: stem) != nil else { return true }
        return saveVersionMeta(meta, for: id)
    }

    /// The editor's "Save a named version…": the design kept as a version
    /// now, whatever the interval says, and pinned under `name`. When it is
    /// the same as the newest version already kept, that one is pinned
    /// instead. Returns the pinned stem, or nil when nothing could be kept.
    @discardableResult
    static func saveNamedVersion(_ design: Design, name: String, now: Date = Date()) -> String? {
        snapshot(design, force: true, now: now)
        guard let newest = versionFiles(in: historyDir(for: design.id)).first else { return nil }
        let stem = newest.deletingPathExtension().lastPathComponent
        return pinVersion(stem, of: design.id, name: name) ? stem : nil
    }

    /// Merges a backup's meta.json into this phone's: a pin already here
    /// keeps its name, one that is not is added. Returns whether anything
    /// changed.
    @discardableResult
    static func mergeVersionMeta(_ incoming: VersionMeta, for id: String) -> Bool {
        var meta = versionMeta(for: id)
        var changed = false
        for (stem, name) in incoming.pinned where meta.pinned[stem] == nil {
            meta.pinned[stem] = name
            changed = true
        }
        return changed ? saveVersionMeta(meta, for: id) : false
    }

    // MARK: sections

    /// The headings Version history groups its rows under.
    enum VersionSection: String, CaseIterable, Sendable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This week"
        case earlier = "Earlier"
    }

    /// Which heading a version kept at `date` goes under, by calendar days
    /// back from today in the phone's own calendar: 0 (or a date ahead) is
    /// Today, 1 Yesterday, 2 to 6 This week, and 7 or more Earlier.
    static func versionSection(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> VersionSection {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .yesterday
        case 2...6: return .thisWeek
        default: return .earlier
        }
    }

    /// One heading's versions, newest first.
    struct VersionGroup: Identifiable, Sendable {
        var section: VersionSection
        var versions: [Version]
        var id: String { section.rawValue }
    }

    /// The versions, newest first, under their headings in order; a
    /// heading with none is left out.
    static func versionSections(_ versions: [Version], now: Date = Date(),
                                calendar: Calendar = .current) -> [VersionGroup] {
        let grouped = Dictionary(grouping: versions) { versionSection($0.savedAt, now: now, calendar: calendar) }
        return VersionSection.allCases.compactMap { section in
            guard let rows = grouped[section], !rows.isEmpty else { return nil }
            return VersionGroup(section: section, versions: rows.sorted { $0.savedAt > $1.savedAt })
        }
    }
}
