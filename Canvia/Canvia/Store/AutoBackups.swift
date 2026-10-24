// "Back up automatically" (AutoBackup): the backup "Back up everything"
// writes, written on its own into the folder picked — kept as a
// security-scoped bookmark — whenever one is due: a day or a week since the
// last, with something changed since. The system's processing task
// "com.canvia.backup" runs it in the background, a day apart, and so does
// leaving the app (inside a background task), when one is due. Each is
// "Canvia backup <date>.canviabackup" (Backup.fileName), and the oldest past
// the number kept go. A folder gone, or Canvia's access to it taken away,
// is kept as the last error, which Home says until the folder is chosen
// again. The Android twin's AutoBackups does the same with JobScheduler.

import BackgroundTasks
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AutoBackups {

    static let shared = AutoBackups()

    /// The processing task, in Canvia-Info.plist's
    /// BGTaskSchedulerPermittedIdentifiers.
    static let taskId = "com.canvia.backup"

    /// The preference as it stands, kept under AutoBackup.key.
    private(set) var config: AutoBackup.Config
    /// Whether one is being written now.
    private(set) var running = false

    private let defaults: UserDefaults
    /// The backup written as the app is left, and the background task it
    /// runs in.
    @ObservationIgnored private var leaving: Task<Void, Never>?
    @ObservationIgnored private var leavingTask: UIBackgroundTaskIdentifier = .invalid

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        config = AutoBackup.decode(defaults.string(forKey: AutoBackup.key))
    }

    /// The preference changed and kept at once, and the next run asked for
    /// as it now stands.
    func update(_ change: (inout AutoBackup.Config) -> Void) {
        var next = config
        change(&next)
        guard next != config else { return }
        config = next
        defaults.set(AutoBackup.encode(next), forKey: AutoBackup.key)
        Self.schedule(on: next.on)
    }

    enum AutoBackupError: LocalizedError {
        case folderGone
        var errorDescription: String? { AutoBackup.failed }
    }

    // MARK: the folder

    /// The folder picked (from the Files picker): kept as a bookmark, and
    /// on — and the first backup written there now when one is due. False,
    /// with nothing changed, when Canvia may not keep it.
    @discardableResult
    func chose(_ folder: URL) -> Bool {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil,
                                                       relativeTo: nil) else { return false }
        update {
            $0.on = true
            $0.folder = bookmark.base64EncodedString()
            $0.lastError = nil
        }
        Task { await runIfDue() }
        return true
    }

    /// Off: nothing written on its own from now on; the folder kept, for
    /// turning it on again.
    func turnOff() {
        update { $0.on = false }
    }

    /// The folder the bookmark names, and whether it had to be renewed.
    private func folderURL(_ bookmark: String) throws -> URL {
        guard let data = Data(base64Encoded: bookmark) else { throw AutoBackupError.folderGone }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { throw AutoBackupError.folderGone }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            update { $0.folder = fresh.base64EncodedString() }
        }
        return url
    }

    // MARK: running

    /// When the newest design, upload or brand kit changed, in ms since
    /// 1970, or nil when there is nothing at all.
    static func newestChange() -> Int64? {
        var stamps: [Double] = DesignLibrary.recents().map(\.updatedAt)
        stamps += DesignLibrary.trashed().map(\.updatedAt)
        stamps += Uploads.all().map(\.added)
        if let kits = try? BrandKits.fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let changed = kits.contentModificationDate {
            stamps.append(changed.timeIntervalSince1970 * 1000)
        }
        return stamps.max().map { Int64($0.rounded(.down)) }
    }

    /// A backup written into the folder when one is due (AutoBackup.isDue)
    /// — or, when `force`d (Back up now), whenever it is on with a folder —
    /// unless one is being written already. Whether one was. A folder gone,
    /// or its access taken away, is kept as the last error.
    @discardableResult
    func runIfDue(force: Bool = false, now: Date = Date()) async -> Bool {
        let config = self.config
        guard config.on, let folder = config.folder, !running else { return false }
        let ms = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        guard force || AutoBackup.isDue(config, now: ms, newestChange: Self.newestChange()) else { return false }
        running = true
        defer { running = false }
        do {
            let bytes = try await write(into: folder, keep: config.keep, date: now)
            update {
                $0.lastAt = ms
                $0.lastBytes = bytes
                $0.lastError = nil
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            update { $0.lastError = error.localizedDescription }
            return false
        }
    }

    /// Today's backup written into the folder — over one of the same day —
    /// and those past `keep` deleted, oldest first (AutoBackup.pruned).
    /// Written whole beside the app first, so the folder never holds one
    /// cut short. How many bytes it came to.
    private func write(into bookmark: String, keep: Int, date: Date) async throws -> Int64 {
        let name = Backup.fileName(date)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("auto-" + name)
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try await Backup.write(to: temporary, now: date) { _ in }
        let folder = try folderURL(bookmark)
        guard folder.startAccessingSecurityScopedResource() else { throw AutoBackupError.folderGone }
        defer { folder.stopAccessingSecurityScopedResource() }
        let files = FileManager.default
        guard (try? folder.checkResourceIsReachable()) == true else { throw AutoBackupError.folderGone }
        let target = folder.appendingPathComponent(name)
        if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
        try files.copyItem(at: temporary, to: target)
        let size = (try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let names = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        for gone in AutoBackup.pruned(names, keep: keep) {
            try? files.removeItem(at: folder.appendingPathComponent(gone))
        }
        return Int64(size)
    }

    // MARK: in the background

    /// At launch, before it is over as the system asks: the processing
    /// task's handler, which writes a backup when one is due.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            let work = Task { @MainActor in
                let backups = AutoBackups.shared
                let wrote = await backups.runIfDue()
                task.setTaskCompleted(success: wrote || backups.config.lastError == nil)
                AutoBackups.schedule(on: backups.config.on)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// The next run asked for a day from now while it is on — on power or
    /// not, needing no network — and the one asked for taken away when it
    /// is off.
    static func schedule(on: Bool) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId)
        guard on else { return }
        let request = BGProcessingTaskRequest(identifier: taskId)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(AutoBackup.dayMs / 1000))
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The app left: a backup written when one is due, inside a background
    /// task so it can finish — stopped cleanly should that time run out.
    func appLeft() {
        guard config.on, !running, leaving == nil else { return }
        leavingTask = UIApplication.shared.beginBackgroundTask(withName: "Backup") {
            MainActor.assumeIsolated { AutoBackups.shared.leaving?.cancel() }
        }
        leaving = Task { @MainActor in
            await self.runIfDue()
            self.leaving = nil
            if self.leavingTask != .invalid { UIApplication.shared.endBackgroundTask(self.leavingTask) }
            self.leavingTask = .invalid
        }
    }
}
