// Back up everything, and restore it here or on the other phone.
//
// A backup is one .canviabackup file: a ZIP in STORE mode (ZipStore) that
// either phone writes and reads alike —
//
//   manifest.json            {"format": "canvia-backup", "version": 1,
//                             "created": <epoch ms>, "platform": "ios",
//                             "counts": {"designs", "trash", "templates",
//                                        "uploads", "fonts", "brandKits"}}
//   designs/<id>.canvia.json  each design as a design file (DesignPackage),
//   trash/<id>.canvia.json    its photos, clips, music and fonts inside;
//   templates/<id>.canvia.json  Recently deleted, and your templates, the same
//   usertemplates.json       your templates' list
//   brandkits.json           the brand kits
//   uploads.json             your uploads' list, as kept in Documents
//   media/<id>.<ext>         the photos your uploads and logos are,
//   videos/<id>.<ext>        their clips,
//   audio/<id>               the music, and <id>.name beside it, its name,
//   fonts/<sha12>.<ext>      and your fonts.
//
// Restoring merges, keeping every id: what is not here is added; a design
// or template already here is replaced only by a newer one (its updatedAt
// later, in whole milliseconds), never by an older or the same; a file
// already here is kept; the design open in the editor is kept as it is.
// Nothing here is ever deleted by a restore. The Android twin writes and
// reads the same names, and restores by the same rules.

import Foundation

enum Backup {

    static let ext = "canviabackup"
    static let format = "canvia-backup"
    static let version = 1

    /// How many of each the backup holds.
    struct Counts: Codable, Equatable, Sendable {
        var designs = 0
        var trash = 0
        var templates = 0
        var uploads = 0
        var fonts = 0
        var brandKits = 0
    }

    struct Manifest: Codable, Equatable, Sendable {
        var format: String? = Backup.format
        var version: Int = Backup.version
        /// When it was made, in epoch milliseconds.
        var created: Double
        var platform: String? = "ios"
        var counts = Counts()
    }

    // Read leniently, as a backup from another build or the other phone
    // may have more, or fewer, keys.

    enum BackupError: LocalizedError {
        case notABackup
        case newer
        var errorDescription: String? {
            switch self {
            case .notABackup: return "This file is not a Canvia backup."
            case .newer: return "This backup was made by a newer Canvia. Update Canvia to restore it."
            }
        }
    }

    /// The manifest read back; a backup is one whose format, when it says,
    /// is ours, and whose version this build reads.
    static func manifest(from data: Data?) throws -> Manifest {
        guard let data, let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              (manifest.format ?? format) == format else { throw BackupError.notABackup }
        guard manifest.version <= version else { throw BackupError.newer }
        return manifest
    }

    // MARK: the merge rule

    enum Merge: Equatable {
        /// Not here: added.
        case add
        /// Here, and the backup's is newer: replaced by it.
        case replace
        /// Here, as new or newer: kept as it is.
        case keep
    }

    /// What a restore does with a design or template the backup holds,
    /// edited at `incoming`, when the one here with its id was edited at
    /// `existing` (nil when there is none): added, replaced only when the
    /// backup's is strictly newer, else kept. Compared in whole
    /// milliseconds, as the Android twin keeps them: a design that went
    /// through it and came back is the same design, not a newer one.
    static func merge(incoming: Double, existing: Double?) -> Merge {
        guard let existing else { return .add }
        return incoming.rounded() > existing.rounded() ? .replace : .keep
    }

    /// The brand kits the backup holds merged into these: a kit with
    /// nothing in it is passed over — another phone's untouched first kit
    /// brings nothing; a kit whose id is not here is added; one the same as
    /// the kit here is passed over; one whose kit here is still empty takes
    /// its place; any other is added beside it under a fresh id and a name
    /// no kit has. The kit in use stays in use. Returns how many were added
    /// or filled in.
    static func mergeKits(_ incoming: BrandKits, into kits: inout BrandKits) -> Int {
        var added = 0
        for kit in incoming.kits where !kit.isEmpty {
            if let i = kits.kits.firstIndex(where: { $0.id == kit.id }) {
                if kits.kits[i] == kit { continue }
                if kits.kits[i].isEmpty {
                    kits.kits[i] = kit
                } else {
                    var copy = kit
                    copy.id = UID.make("kit")
                    copy.name = Titles.unique(kit.name, taken: kits.kits.map(\.name))
                    kits.kits.append(copy)
                }
            } else {
                var named = kit
                named.name = Titles.unique(kit.name, taken: kits.kits.map(\.name))
                kits.kits.append(named)
            }
            added += 1
        }
        return added
    }

    /// What a restore brought in, and what it kept as it was.
    struct Report: Equatable, Sendable {
        var designs = 0
        var trash = 0
        var templates = 0
        var uploads = 0
        var fonts = 0
        var brandKits = 0
        /// Designs and templates already here, as new or newer.
        var kept = 0
    }

    /// "Restored 3 designs, 1 template and 12 uploads. 2 already here were
    /// kept." — or "Nothing new to restore." Counts of none are left out.
    static func summary(_ report: Report) -> String {
        var parts: [String] = []
        func add(_ n: Int, _ one: String, _ many: String) {
            if n > 0 { parts.append("\(n) \(n == 1 ? one : many)") }
        }
        add(report.designs, "design", "designs")
        add(report.trash, "deleted design", "deleted designs")
        add(report.templates, "template", "templates")
        add(report.uploads, "upload", "uploads")
        add(report.fonts, "font", "fonts")
        add(report.brandKits, "brand kit", "brand kits")
        var text = "Nothing new to restore."
        if let last = parts.last {
            let list = parts.count == 1 ? last : "\(parts.dropLast().joined(separator: ", ")) and \(last)"
            text = "Restored \(list)."
        }
        if report.kept > 0 {
            text += report.kept == 1 ? " 1 already here was kept." : " \(report.kept) already here were kept."
        }
        return text
    }

    /// What a backup that failed says, as the Android twin says it: that
    /// there is too much for one file, when that is why; otherwise only that
    /// it failed.
    static func backupFailure(_ error: Error) -> String {
        let failed = "Couldn't back up."
        guard let zip = error as? ZipStore.ZipError, case .tooBig = zip else { return failed }
        return "\(failed) \(zip.localizedDescription)"
    }

    /// What a restore that failed says, as the Android twin says it: why,
    /// when the file is not a backup this build reads; otherwise only that
    /// it failed.
    static func restoreFailure(_ error: Error) -> String {
        if error is BackupError || error is ZipStore.ZipError { return error.localizedDescription }
        return "Couldn't restore that backup."
    }

    /// "Canvia backup 2026-10-13.canviabackup".
    static func fileName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "Canvia backup \(f.string(from: date)).\(ext)"
    }

    // MARK: writing

    /// Everything, into a backup at `url`, `progress` told the fraction done
    /// as it goes. Cancelled, the half-written file is removed. Only a
    /// design's library photos are drawn here, on the main actor; every
    /// file is read, packed and written away from it.
    @MainActor
    static func write(to url: URL, now: Date = Date(),
                      progress: @escaping @MainActor (Double) -> Void) async throws -> Manifest {
        let live = designFiles(in: DesignLibrary.designsDir)
        let binned = designFiles(in: DesignLibrary.trashDir)
        let templates = UserTemplates.all()
        let uploads = Uploads.all()
        let fonts = FontStore.installed()
        let kits = BrandKits.load()
        let total = Double(live.count + binned.count + templates.count + uploads.count + fonts.count + 1)
        var done = 0.0
        func step() throws {
            try Task.checkCancellation()
            done += 1
            progress(min(done / total, 1))
        }

        let writer = try ZipStore.Writer(url: url, date: now)
        var finished = false
        defer {
            if !finished {
                writer.abandon()
                try? FileManager.default.removeItem(at: url)
            }
        }
        var manifest = Manifest(created: (now.timeIntervalSince1970 * 1000).rounded())
        var written = Set<String>()

        for file in live {
            let packed = try await pack(file, folder: "designs", into: writer)
            if packed { manifest.counts.designs += 1 }
            try step()
        }
        for file in binned {
            let packed = try await pack(file, folder: "trash", into: writer)
            if packed { manifest.counts.trash += 1 }
            try step()
        }
        var packedTemplates: [UserTemplate] = []
        for entry in templates {
            let packed = try await pack(UserTemplates.fileURL(for: entry.id), folder: "templates", into: writer)
            if packed { packedTemplates.append(entry) }
            try step()
        }
        manifest.counts.templates = packedTemplates.count
        try writer.add(UserTemplates.indexName, json(packedTemplates))

        try writer.add(BrandKits.fileName, json(kits))
        manifest.counts.brandKits = kits.kits.count
        for src in kits.allLogos {
            try await addSource(src, into: writer, written: &written)
        }

        if let list = try? Data(contentsOf: Uploads.fileURL) { try writer.add(Uploads.fileName, list) }
        for entry in uploads {
            switch entry.kind {
            case .image: try await addSource("media:\(entry.id)", into: writer, written: &written)
            case .video: try await addSource(VideoStore.src(entry.id, at: nil), into: writer, written: &written)
            case .audio:
                if let file = AudioStore.url(for: entry.id) {
                    try await add(file, as: "audio/\(entry.id)", into: writer, written: &written)
                    // The name it came with beside it, audio/<id>.name, as
                    // the Android twin writes it; a restore puts it back.
                    let name = AudioStore.nameFile(for: entry.id)
                    if FileManager.default.fileExists(atPath: name.path) {
                        try await add(name, as: "audio/\(name.lastPathComponent)", into: writer, written: &written)
                    }
                }
            }
            manifest.counts.uploads += 1
            try step()
        }
        for font in fonts {
            try await add(FontStore.directory.appendingPathComponent(font.file), as: "fonts/\(font.file)",
                          into: writer, written: &written)
            manifest.counts.fonts += 1
            try step()
        }

        try writer.add("manifest.json", json(manifest))
        try writer.finish()
        finished = true
        progress(1)
        return manifest
    }

    /// The design files in a folder, in name order.
    private static func designFiles(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { DesignLibrary.isDesignFile($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// One design as a design file under `folder`; false when its file does
    /// not read, and it is left out. Read and decoded away from the main
    /// actor; its library photos drawn on it; its files read, packed and
    /// written away from it again. Every clip goes in whole, however long
    /// and of whatever type, as the Android twin's backup packs them: a
    /// backup keeps the clip, where a file to share may carry a still. Each
    /// clip is streamed from its file into the backup a piece at a time
    /// (DesignPackage.stream), as the Android twin streams it: held whole,
    /// with its base64 and the encoded file beside it, a clip of a few
    /// minutes would take gigabytes and the app with it.
    @MainActor
    private static func pack(_ file: URL, folder: String, into writer: ZipStore.Writer) async throws -> Bool {
        let read = await Task.detached(priority: .userInitiated) { () -> Design? in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(Design.self, from: data)
        }.value
        guard let design = read else { return false }
        let drawn = DesignPackage.withLibraryPhotos(design)
        let name = "\(folder)/\(design.id).\(DesignPackage.ext)"
        try await Task.detached(priority: .userInitiated) {
            let gathered = DesignPackage.gatheredForBackup(drawn.design, media: drawn.media)
            try writer.add(name, pieces: { write in
                try DesignPackage.stream(gathered.package, clips: gathered.clips, into: write)
            })
        }.value
        return true
    }

    /// The file a photo or clip source shows, once, under media/ or videos/.
    /// A library picture is drawn by either phone, and is not a file.
    @MainActor
    private static func addSource(_ src: String, into writer: ZipStore.Writer, written: inout Set<String>) async throws {
        if src.hasPrefix("media:") {
            let id = String(src.dropFirst(6))
            for ext in MediaStore.extensions {
                let file = MediaStore.directory.appendingPathComponent("\(id).\(ext)")
                if FileManager.default.fileExists(atPath: file.path) {
                    try await add(file, as: "media/\(id).\(ext)", into: writer, written: &written)
                    return
                }
            }
        } else if let clip = VideoStore.split(src), let file = VideoStore.url(for: clip.id) {
            try await add(file, as: "videos/\(file.lastPathComponent)", into: writer, written: &written)
        }
    }

    /// A file into the backup as `name`, once, read and written a piece at
    /// a time away from the main actor; one that does not open is left out.
    @MainActor
    private static func add(_ file: URL, as name: String, into writer: ZipStore.Writer,
                            written: inout Set<String>) async throws {
        guard written.insert(name).inserted else { return }
        try await Task.detached(priority: .userInitiated) {
            guard let handle = try? FileHandle(forReadingFrom: file) else { return }
            defer { try? handle.close() }
            try writer.add(name, from: handle)
        }.value
    }

    private static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    // MARK: restoring

    /// The backup at `url` merged into this phone (see the merge rule
    /// above), `progress` told the fraction done. The design `open` in the
    /// editor is kept as it is, as its next save would put it back over the
    /// one restored. Cancelled, what is already in stays: a restore can be
    /// run again, and takes only what is still missing.
    @MainActor
    static func restore(from url: URL, open: String? = nil,
                        progress: @escaping @MainActor (Double) -> Void) async throws -> Report {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let reader = try await Task.detached(priority: .userInitiated) { try ZipStore.Reader(url: url) }.value
        _ = try manifest(from: reader.file("manifest.json"))

        var report = Report()
        let designs = reader.names(in: "designs/")
        let binned = reader.names(in: "trash/")
        let templates = reader.names(in: "templates/")
        let total = Double(designs.count + binned.count + templates.count + 2)
        var done = 0.0
        func step() throws {
            try Task.checkCancellation()
            done += 1
            progress(min(done / total, 1))
        }

        // The files first, so every design finds what it shows.
        report.fonts = await Task.detached(priority: .userInitiated) { () -> Int in
            Backup.restoreFiles(reader, folder: "media/", into: MediaStore.directory)
            Backup.restoreFiles(reader, folder: "videos/", into: VideoStore.directory)
            Backup.restoreFiles(reader, folder: "audio/", into: AudioStore.directory)
            return Backup.restoreFonts(reader)
        }.value
        report.uploads = restoreUploads(reader.file(Uploads.fileName))
        try step()

        for name in designs {
            let outcome = await Task.detached(priority: .userInitiated) {
                Backup.restoreDesign(reader.file(name), trashed: false, open: open)
            }.value
            count(outcome, into: &report, trashed: false)
            try step()
        }
        for name in binned {
            let outcome = await Task.detached(priority: .userInitiated) {
                Backup.restoreDesign(reader.file(name), trashed: true, open: open)
            }.value
            count(outcome, into: &report, trashed: true)
            try step()
        }

        // Templates of your own: each read, and its files stored, away from
        // the main actor; listed, measured and drawn back on it.
        let listed = reader.file(UserTemplates.indexName).map(UserTemplates.read) ?? []
        for name in templates {
            let here = UserTemplates.index()
            let outcome = await Task.detached(priority: .userInitiated) {
                Backup.restoreTemplate(reader.file(name), listed: listed, here: here)
            }.value
            switch outcome {
            case .kept:
                report.kept += 1
            case .unreadable:
                break
            case .restored(var design, let category):
                design.normalizeTextHeights()
                if UserTemplates.store(design, category: category) {
                    UserTemplates.writeThumbnail(for: design)
                    report.templates += 1
                }
            }
            try step()
        }

        if let data = reader.file(BrandKits.fileName), let incoming = BrandKits.read(data) {
            var kits = BrandKits.load()
            report.brandKits = mergeKits(incoming, into: &kits)
            if report.brandKits > 0 { kits.save() }
        }
        FontStore.installed()
        progress(1)
        return report
    }

    /// What became of one design in the backup.
    enum Outcome: Sendable {
        case added
        case kept
        case unreadable
    }

    private static func count(_ outcome: Outcome, into report: inout Report, trashed: Bool) {
        switch outcome {
        case .added: if trashed { report.trash += 1 } else { report.designs += 1 }
        case .kept: report.kept += 1
        case .unreadable: break
        }
    }

    /// What became of one template in the backup.
    enum TemplateOutcome {
        case kept
        case unreadable
        /// Its files stored here; the design to list, and its category.
        case restored(Design, String)
    }

    /// One template's file from the backup weighed against those `here`,
    /// named and timed as the backup's list (`listed`) has it
    /// (UserTemplates.restored), and, when it is to come in, its photos,
    /// clips and fonts stored under their own ids. Touches files only, for
    /// a caller away from the main actor; listing it is the caller's.
    private static func restoreTemplate(_ data: Data?, listed: [UserTemplate], here: [UserTemplate]) -> TemplateOutcome {
        guard let data, let package = try? JSONDecoder().decode(DesignPackage.Package.self, from: data),
              package.format == DesignPackage.format else { return .unreadable }
        let id = package.design.id
        let listing = listed.first { $0.id == id }
        let incoming = UserTemplates.restored(package.design, listed: listing).design.updatedAt
        let existing = here.first { $0.id == id }?.updatedAt
        guard merge(incoming: incoming, existing: existing) != .keep else { return .kept }
        let restored = UserTemplates.restored(DesignPackage.storeKeepingIds(package), listed: listing)
        return .restored(restored.design, restored.category)
    }

    /// When the design file at `url` was last edited; nil when there is none
    /// or it does not read.
    static func editedAt(_ url: URL) -> Double? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Stamp.self, from: data))?.updatedAt
    }

    private struct Stamp: Decodable {
        var updatedAt: Double?
    }

    /// One design file from the backup put in its place: on the shelf, or
    /// in Recently deleted. The design `open` in the editor is kept. A
    /// deleted design never displaces one on the shelf; one coming back to
    /// the shelf takes its own copy out of the trash. A design whose picture
    /// would now be out of date loses it, to be drawn again.
    private static func restoreDesign(_ data: Data?, trashed: Bool, open: String?) -> Outcome {
        guard let data, let package = try? JSONDecoder().decode(DesignPackage.Package.self, from: data),
              package.format == DesignPackage.format else { return .unreadable }
        let id = package.design.id
        guard DesignPackage.isSafeFileName(id) else { return .unreadable }
        guard id != open else { return .kept }
        let liveFile = DesignLibrary.designsDir.appendingPathComponent("\(id).json")
        let trashFile = DesignLibrary.trashDir.appendingPathComponent("\(id).json")
        let fm = FileManager.default
        if trashed {
            guard !fm.fileExists(atPath: liveFile.path),
                  merge(incoming: package.design.updatedAt, existing: editedAt(trashFile)) != .keep else { return .kept }
            let design = DesignPackage.storeKeepingIds(package)
            guard let encoded = try? JSONEncoder().encode(design),
                  (try? encoded.write(to: trashFile, options: .atomic)) != nil else { return .unreadable }
            try? fm.removeItem(at: DesignLibrary.thumbnailURL(for: id, trashed: true))
            return .added
        }
        let here = editedAt(liveFile) ?? editedAt(trashFile)
        guard merge(incoming: package.design.updatedAt, existing: here) != .keep else { return .kept }
        let design = DesignPackage.storeKeepingIds(package)
        guard DesignLibrary.save(design) else { return .unreadable }
        try? fm.removeItem(at: DesignLibrary.thumbnailURL(for: id))
        try? fm.removeItem(at: trashFile)
        try? fm.removeItem(at: DesignLibrary.thumbnailURL(for: id, trashed: true))
        return .added
    }

    /// The files under `folder` stored in `directory` under their own
    /// names, each only when no file of that name is here.
    private static func restoreFiles(_ reader: ZipStore.Reader, folder: String, into directory: URL) {
        for name in reader.names(in: folder) {
            let file = String(name.dropFirst(folder.count))
            guard DesignPackage.isSafeFileName(file) else { continue }
            let target = directory.appendingPathComponent(file)
            guard !FileManager.default.fileExists(atPath: target.path), let data = reader.file(name) else { continue }
            try? data.write(to: target, options: .atomic)
        }
    }

    /// Your fonts, added as a font is; returns how many were new here.
    private static func restoreFonts(_ reader: ZipStore.Reader) -> Int {
        let had = Set(FontStore.installed().map(\.id))
        var added = 0
        for name in reader.names(in: "fonts/") {
            guard let data = reader.file(name), case .success = FontStore.add(data) else { continue }
            if !had.contains(CustomFonts.sha12(data)) { added += 1 }
        }
        return added
    }

    /// Your uploads' list merged: each photo, clip or song not listed here
    /// is listed, with when it first came in, once its file is here. Fonts
    /// list themselves as they are added. Returns how many were new.
    private static func restoreUploads(_ data: Data?) -> Int {
        guard let data, let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return 0 }
        let here = Set(Uploads.all().map(\.id))
        var added = 0
        for case let item as [String: Any] in raw {
            guard let id = item["id"] as? String, !here.contains(id),
                  let kind = (item["kind"] as? String).flatMap(Uploads.Kind.init(rawValue:)) else { continue }
            let ms = (item["added"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
            Uploads.record(id, kind: kind, now: Date(timeIntervalSince1970: ms / 1000))
            if Uploads.all(kind).contains(where: { $0.id == id }) { added += 1 }
        }
        return added
    }
}

extension Backup.Counts {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        designs = (try? c.decode(Int.self, forKey: .designs)) ?? 0
        trash = (try? c.decode(Int.self, forKey: .trash)) ?? 0
        templates = (try? c.decode(Int.self, forKey: .templates)) ?? 0
        uploads = (try? c.decode(Int.self, forKey: .uploads)) ?? 0
        fonts = (try? c.decode(Int.self, forKey: .fonts)) ?? 0
        brandKits = (try? c.decode(Int.self, forKey: .brandKits)) ?? 0
    }
}

extension Backup.Manifest {
    /// Only the version is needed to read one; the rest take defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try? c.decode(String.self, forKey: .format)
        version = try c.decode(Int.self, forKey: .version)
        created = (try? c.decode(Double.self, forKey: .created)) ?? 0
        platform = try? c.decode(String.self, forKey: .platform)
        counts = (try? c.decode(Backup.Counts.self, forKey: .counts)) ?? Backup.Counts()
    }
}
