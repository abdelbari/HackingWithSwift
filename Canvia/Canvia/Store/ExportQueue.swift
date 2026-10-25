// Exports that keep going once the sheet is closed, or the app is left.
//
// The queue belongs to the app, not to the Export sheet: the sheet hands it
// a job made from a snapshot of the design as it was at that moment
// (ExportSnapshot), so editing carries on beside it, and closing the sheet
// leaves it running. One export runs at a time; another asked for meanwhile
// waits its turn. A pill above the editor's toolbar, and on Home, says how
// far along it is, and its X stops it.
//
// Out of the app, on iOS 26 and later, the export runs under the system's
// continued processing task (ContinuedExport), asked for as it starts, or
// as the app is left with it running: the system shows how far along it is
// and lets it finish — or stops it, when the export stops cleanly and a
// notification says "Export stopped — open Canvia to finish". Below iOS 26
// the work is wrapped in a background task. When the time the system gives
// runs out, the export stops between two pages or frames (every exporter
// steps aside through Pacer.breathe, which waits here) — a video's writer
// simply waits, open, for its next frame — and a notification says
// "Paused — return to Canvia to finish"; coming back carries it on. Done
// while away, a notification says so, with Share and Open; the file is
// shared or opened as the app comes back, as it would have been in the
// sheet. The Android twin holds its job in a foreground
// service, with the same words (ExportChoices).

import Observation
import QuickLook
import UIKit
import UserNotifications

@MainActor
@Observable
final class ExportQueue {

    static let shared = ExportQueue(host: .app)

    /// What a finished export hands back, to share, print or say.
    struct Result {
        /// The files to share.
        var urls: [URL] = []
        /// What Save to Photos came to, and whether anything went in.
        var photosNote: String?
        var photosSaved = true
        /// A video whose music could not be put under it.
        var musicLost = false
        /// A PDF to hand to the printer.
        var print: PrintRequest?
        /// Said beside the share: the designs of several that could not be
        /// exported ("Couldn't export 1 of 5").
        var skipped: String?
        /// Said beside the share, as a matter of fact: a PNG that could
        /// not be compressed enough and went out as a normal one.
        var note: String?
        /// Why it could not finish, said in its turn as any other result
        /// is — as the Android twin's ExportHandoff.Say — so a second
        /// failure does not replace the first.
        var failed: String?

        /// Nothing to share, open or print — a failure, or only what
        /// Photos took — so only said.
        var isOnlySaid: Bool { urls.isEmpty && print == nil }
    }

    /// The printer's part of "Send to a printer".
    struct PrintRequest {
        var url: URL
        var jobName: String
        var landscape: Bool
    }

    /// The work of one export: it renders from what it captured when it was
    /// made, reporting the fraction done, and checks for a Cancel between
    /// pages or frames.
    typealias Work = @MainActor (_ report: @escaping @Sendable (Double) -> Void) async throws -> Result

    struct Job: Identifiable {
        let id = UUID()
        /// What the pill and the progress card say: "Rendering the video".
        let label: String
        /// The design it is of, for the pill on Home to open.
        let designId: String
        /// Its place among several designs exported at once, whose files
        /// are handed over together once the last is done; nil for one.
        var batch: Batch? = nil
        /// What the system shows of it while it keeps going out of the app
        /// (ContinuedExport): "Exporting <title>", what it makes under
        /// that, and how many frames or pages it counts; none, and it is
        /// "Exporting <label>", out of 100.
        var title: String? = nil
        var detail: String = ""
        var units: Int = 0
        /// How it is made again should it fail (Retry); none, and it is
        /// tried again as it was, with nothing smaller to suggest.
        var retry: Retry? = nil
        let work: Work
    }

    /// What a failed job is tried again with: the design as it was, to
    /// name the page of a photo gone missing; the settings it was asked
    /// for with, to suggest a smaller try (ExportFailure.suggestion); and
    /// its work made with those smaller settings.
    struct Retry {
        var design: Design?
        var settings: ExportFailure.Asked?
        var smaller: (@MainActor (ExportFailure.Asked) -> Work)?
    }

    /// An export that failed, kept to try again — its job as it was asked
    /// for — until dismissed, at most ExportFailure.keptCount, newest
    /// first: the pill's row and the failure notification offer Try again
    /// (Retry these, for a batch) and, when there is one, the smaller
    /// `suggestion` — as the Android twin's Exports.Failed.
    struct Failed: Identifiable {
        let id: UUID
        let label: String
        /// "Export failed. It's too large to make at this size."
        let message: String
        let failure: ExportFailure.Failure
        let suggestion: ExportFailure.Suggestion?
        /// A batch's designs that failed, by title, listed under its
        /// message; empty for one design.
        var titles: [String] = []
        /// Made again: as it was, or smaller.
        let again: @MainActor (_ smaller: Bool) -> Void
    }

    /// One of several designs exported at once — Home's Select ▸ Share: a
    /// job each, in turn, sharing an id.
    struct Batch {
        let id: UUID
        /// Zero-based.
        let index: Int
        let total: Int
        /// The designs of it that failed, by id, exported again as a batch
        /// of their own: Retry these. None, and a failure is only said.
        var again: (@MainActor ([String]) -> Void)? = nil
    }

    /// What the parts of a batch have come to so far, until its last.
    private struct BatchMade {
        var urls: [URL] = []
        var failed = 0
        var left: Int
        /// The parts that failed, and why the last of them did.
        var failedJobs: [Job] = []
        var why = ExportFailure.Reason.other
    }

    /// An export done, until it is shared, printed or said.
    struct Finished: Identifiable {
        let id: UUID
        let label: String
        let designId: String
        let result: Result
    }

    /// How a notification's action asked for the file.
    enum Request: Equatable {
        case share, open
    }

    /// Begins and ends the background task, asks for an export's continued
    /// processing task on iOS 26 (`beginContinued`, whether it was asked
    /// for), says whether the app is out of sight, and posts and takes down
    /// an export's notification — one for each export, so one done does
    /// not replace another's: the app's own, or none in a test.
    struct Host {
        var begin: @MainActor (_ expired: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier
        var end: @MainActor (UIBackgroundTaskIdentifier) -> Void
        var isAway: @MainActor () -> Bool
        var notify: @MainActor (_ job: UUID, _ title: String, _ body: String, _ actions: Bool) -> Void
        var clear: @MainActor (_ job: UUID) -> Void
        var beginContinued: @MainActor (_ job: UUID, _ title: String, _ subtitle: String) -> Bool = { _, _, _ in false }
        /// Withdraws export `job`'s request the system has not started:
        /// the export is over before it was.
        var cancelContinued: @MainActor (_ job: UUID) -> Void = { _ in }
        /// A failure's notification, with Try again and, when there is
        /// one, the smaller try it suggests (`smaller`, its label).
        var notifyFailed: @MainActor (_ job: UUID, _ title: String, _ body: String, _ smaller: String?) -> Void
            = { _, _, _, _ in }

        static let app = Host(
            begin: { expired in
                UIApplication.shared.beginBackgroundTask(withName: "Export") {
                    MainActor.assumeIsolated { expired() }
                }
            },
            end: { id in
                if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
            },
            isAway: { UIApplication.shared.applicationState != .active },
            notify: { job, title, body, actions in
                ExportNotifications.post(job: job, title: title, body: body, actions: actions)
            },
            clear: { job in ExportNotifications.clear(job: job) },
            beginContinued: { job, title, subtitle in
                ContinuedExport.submit(job: job, title: title, subtitle: subtitle)
            },
            cancelContinued: { job in ContinuedExport.cancel(job: job) },
            notifyFailed: { job, title, body, smaller in
                ExportNotifications.postFailed(job: job, title: title, body: body, smaller: smaller)
            })

        static let none = Host(begin: { _ in .invalid }, end: { _ in }, isAway: { false },
                               notify: { _, _, _, _ in }, clear: { _ in })
    }

    /// The system's task an export runs under out of the app
    /// (ContinuedExport.Handle): how far along it is reported to it, and
    /// its end.
    struct Continued {
        var job: UUID
        var handle: ContinuedExport.Handle
    }

    private let host: Host
    /// The export running, and how far along it is.
    private(set) var current: Job?
    private(set) var progress: Double = 0
    /// The exports asked for while one runs, in turn.
    private(set) var waiting: [Job] = []
    /// The exports done, oldest first, each until it is taken: one done
    /// while another waits to be delivered — the app away — is kept too.
    var finished: [Finished] = []
    /// Something to say once the sheet has gone: a save to Photos, a video
    /// without its music, a failure.
    var note: String?
    /// Out of the app with the background time run out: the export waits
    /// between two pages or frames until the app is back.
    private(set) var paused = false
    /// A notification's Share or Open, waiting for the app to come back,
    /// and the export whose notification it was (tapped).
    var requested: Request?
    var requestedJob: UUID?
    /// Whether a delivered export's share sheet, preview or print dialog is
    /// up; the next is delivered once it has gone.
    var delivering = false
    /// Whether the Export sheet is up, which then shows what is done
    /// itself.
    var sheetOpen = false
    /// The exports that failed, kept to try again, newest first.
    private(set) var failedExports: [Failed] = []

    @ObservationIgnored private var batches: [UUID: BatchMade] = [:]
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Result, Error>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// The export whose continued processing task has been asked for, and
    /// the task itself once the system has started it.
    private(set) var continuedAsked: UUID?
    @ObservationIgnored private(set) var continuedTask: Continued?
    /// How the last few exports went, by job: a task the system starts
    /// for one already over ends as it went, not as failed.
    @ObservationIgnored private var outcomes: [(job: UUID, success: Bool)] = []

    init(host: Host) {
        self.host = host
    }

    var isBusy: Bool { current != nil || !waiting.isEmpty }

    /// Whether the export running goes on once Canvia is left: its
    /// continued processing task was granted (ContinuedExport).
    var keepsGoing: Bool { current != nil && continuedAsked == current?.id }

    /// "Rendering the video 42%", for the pill.
    var pillText: String? {
        current.map { ExportChoices.pillText(label: $0.label, fraction: progress) }
    }

    /// Runs the job now, or after those ahead of it.
    func enqueue(_ job: Job) {
        waiting.append(job)
        guard runner == nil else { return }
        runner = Task { await drain() }
    }

    /// Stops the export running, or takes one waiting out of the line.
    func cancel(_ id: UUID) {
        if current?.id == id {
            running?.cancel()
        } else {
            let gone = waiting.filter { $0.id == id }
            waiting.removeAll { $0.id == id }
            for job in gone { collect(job, urls: [], failed: 0) }
        }
    }

    /// Stops the export running; those waiting go on.
    func cancelCurrent() {
        if let id = current?.id { cancel(id) }
    }

    /// Stops every export, those waiting first so none starts after: the
    /// Stop of "Keep exporting in the background?", as the Android twin's
    /// Exports.cancelAll.
    func cancelAll() {
        let gone = waiting
        waiting.removeAll()
        for job in gone { collect(job, urls: [], failed: 0) }
        cancelCurrent()
    }

    /// Returns once nothing runs or waits.
    func waitUntilIdle() async {
        while let runner { await runner.value }
    }

    /// The oldest finished export handed over, forgotten here, and its
    /// notification taken down.
    func takeFinished() -> Finished? {
        guard !finished.isEmpty else { return nil }
        return take(at: 0)
    }

    /// A notification tapped for export [job]: its Share or Open hands that
    /// export on first, as asked; a tap on the notification itself
    /// (request nil) leaves every export to be handed on in turn, oldest
    /// first — as the Android twin's Exports.acted.
    func tapped(_ request: Request?, job: UUID?) {
        guard let request else { return }
        requestedJob = job
        requested = request
    }

    /// Whether the next takeRequested would hand on is only said: it waits
    /// until the pill is free, so each is said in turn.
    var nextIsOnlySaid: Bool {
        let target = requestedJob.flatMap { id in finished.first { $0.id == id } }
        guard let next = target ?? finished.first else { return false }
        return next.result.isOnlySaid
    }

    /// The next finished export to deliver, and how a notification asked
    /// for it: the one whose notification was tapped, else the oldest. The
    /// tap is used up either way, so one for an export delivered already
    /// does not change how a later one is delivered — as the Android twin's
    /// ExportsReady takes them.
    func takeRequested() -> (finished: Finished, request: Request?)? {
        let request = requested
        let target = requestedJob
        requested = nil
        requestedJob = nil
        if let target, let i = finished.firstIndex(where: { $0.id == target }) {
            return (take(at: i), request)
        }
        guard let oldest = takeFinished() else { return nil }
        return (oldest, target == nil ? request : nil)
    }

    private func take(at index: Int) -> Finished {
        let done = finished.remove(at: index)
        host.clear(done.id)
        return done
    }

    private func drain() async {
        while !waiting.isEmpty {
            let job = waiting.removeFirst()
            current = job
            progress = 0
            beginBackground()
            beginContinued(job)
            let id = job.id
            // Called on the main actor by most exporters, and from the
            // video writer's queue by the MP4's.
            let reporter: @Sendable (Double) -> Void = { [weak self] fraction in
                if Thread.isMainThread {
                    MainActor.assumeIsolated { self?.report(fraction, for: id) }
                } else {
                    Task { @MainActor in self?.report(fraction, for: id) }
                }
            }
            let task = Task { try await job.work(reporter) }
            running = task
            // How the export went, for its continued processing task: one of
            // a batch hands nothing over itself until the last is done.
            var succeeded = false
            do {
                let result = try await task.value
                succeeded = job.batch != nil || result.failed == nil
                // What it made is the design's last export (Details).
                Self.noteExport(job.designId, result)
                if job.batch != nil {
                    collect(job, urls: result.urls, failed: result.failed == nil ? 0 : 1)
                } else {
                    finish(job.id, label: job.label, designId: job.designId, result: result)
                }
            } catch is CancellationError {
                // Asked for; nothing to say. One of a batch is left out.
                collect(job, urls: [], failed: 0)
            } catch {
                // Why, plainly, and kept to try again (ExportFailure).
                let kind = ExportFailure.classify(error)
                if kind == .cancelled {
                    collect(job, urls: [], failed: 0)
                } else if job.batch != nil {
                    collect(job, urls: [], failed: 1, why: kind)
                } else {
                    let kept = failure(job, kind: kind)
                    failedExports = ExportFailure.kept(failedExports, kept)
                    // Why it failed is the design's last export (Details).
                    DesignFacts.rememberFailedExport(job.designId, failure: kept.failure)
                    finished.append(Finished(id: job.id, label: job.label, designId: job.designId,
                                             result: Result(failed: kept.message)))
                    if host.isAway() {
                        host.notifyFailed(job.id, ExportChoices.failedTitle, kept.message, kept.suggestion?.label)
                    }
                }
            }
            running = nil
            current = nil
            endContinued(job.id, success: succeeded)
            endBackground()
        }
        runner = nil
    }

    /// What an export of design `designId` made, kept as its last export on
    /// this phone (DesignFacts): "print" for the printer, else the first
    /// file's type; what was only said, or only put in Photos, is none —
    /// as the Android twin's HomeExports.noteExport keeps it. Share to's
    /// files, handed to another app, are kept by the job itself
    /// (ExportJobs.sharedTo).
    private static func noteExport(_ designId: String, _ result: Result) {
        if result.print != nil {
            DesignFacts.rememberExport(designId, type: "print")
        } else {
            noteFiles(designId, result.urls)
        }
    }

    /// `urls`, made from design `designId`, kept as its last export: the
    /// first file's type; none made is nothing kept.
    static func noteFiles(_ designId: String, _ urls: [URL]) {
        guard let ext = urls.first?.pathExtension.lowercased(), !ext.isEmpty else { return }
        DesignFacts.rememberExport(designId, type: ext)
    }

    /// Job `job` failed as `kind`: what it says — a missing photo naming
    /// its page — what it suggests, and how it is made again from the
    /// design as it was, as it was or smaller.
    private func failure(_ job: Job, kind: ExportFailure.Reason) -> Failed {
        let design = job.retry?.design
        let page = kind == .missingMedia
            ? design.flatMap { d in ExportFailure.missingPage(d, pages: Array(d.pages.indices), exists: Self.mediaExists) }
            : nil
        let suggestion = ExportFailure.suggestion(kind, settings: job.retry?.settings)
        return Failed(id: job.id, label: job.label, message: ExportFailure.failedText(kind, page: page),
                      failure: ExportFailure.Failure(kind: kind, designIds: [job.designId]),
                      suggestion: suggestion, again: { [weak self] smaller in
            var work = job.work
            if smaller, let suggestion, let make = job.retry?.smaller { work = make(suggestion.settings) }
            // A fresh job, under an id of its own.
            self?.enqueue(Job(label: job.label, designId: job.designId, batch: job.batch, title: job.title,
                              detail: job.detail, units: job.units, retry: job.retry, work: work))
        })
    }

    /// Whether a photo's file is still there: one of the app's own photos
    /// ("media:<id>") by its file; anything else is taken to be.
    nonisolated private static func mediaExists(_ src: String) -> Bool {
        guard src.hasPrefix("media:") else { return true }
        let id = String(src.dropFirst(6))
        return MediaStore.extensions.contains { ext in
            FileManager.default.fileExists(atPath: MediaStore.directory.appendingPathComponent("\(id).\(ext)").path)
        }
    }

    /// Failed export `id` tried again: as it was, or with its smaller
    /// suggestion. It leaves the list, its message and notification with
    /// it; failing again puts it back.
    func retry(_ id: UUID, smaller: Bool = false) {
        guard let entry = failedExports.first(where: { $0.id == id }) else { return }
        dismissFailed(id)
        if note == entry.message { note = nil }
        entry.again(smaller && entry.suggestion != nil)
    }

    /// Failed export `id` let go, with what is left of it to say.
    func dismissFailed(_ id: UUID) {
        failedExports.removeAll { $0.id == id }
        finished.removeAll { $0.id == id && $0.result.isOnlySaid }
        host.clear(id)
    }

    /// Whether a finished export's failure is in the list, where its row
    /// says it — so it is not said again in the pill.
    func isKeptFailure(_ id: UUID) -> Bool {
        failedExports.contains { $0.id == id }
    }

    private func finish(_ id: UUID, label: String, designId: String, result: Result) {
        finished.append(Finished(id: id, label: label, designId: designId, result: result))
        if host.isAway() { host.notify(id, ExportChoices.readyTitle, Self.readyBody(result), !result.urls.isEmpty) }
    }

    /// One part of a batch done, failed, stopped or taken out of the line:
    /// its files kept with the others'. After the last, every file is
    /// handed over at once, what could not be exported said beside them —
    /// or, with none made, said alone. Nothing for a job of one design.
    private func collect(_ job: Job, urls: [URL], failed: Int, why: ExportFailure.Reason = .other) {
        guard let batch = job.batch else { return }
        var made = batches[batch.id] ?? BatchMade(left: batch.total)
        made.urls += urls
        made.failed += failed
        if failed > 0 {
            made.failedJobs.append(job)
            made.why = why
        }
        made.left -= 1
        guard made.left <= 0 else {
            batches[batch.id] = made
            return
        }
        batches[batch.id] = nil
        let note = HomeExports.failureText(failed: made.failed, total: batch.total)
        // Those that failed, named under "Couldn't export 2 of 5", with
        // Retry these: a batch of them alone, as this one was asked.
        if let note, let again = batch.again, !made.failedJobs.isEmpty {
            let ids = made.failedJobs.map(\.designId)
            let entry = Failed(id: batch.id, label: note, message: note,
                               failure: ExportFailure.Failure(kind: made.why, designIds: ids), suggestion: nil,
                               titles: made.failedJobs.map { $0.title ?? $0.designId }, again: { _ in again(ids) })
            failedExports = ExportFailure.kept(failedExports, entry)
        }
        if !made.urls.isEmpty {
            finish(batch.id, label: job.label, designId: job.designId, result: Result(urls: made.urls, skipped: note))
        } else if let note {
            finished.append(Finished(id: batch.id, label: job.label, designId: job.designId, result: Result(failed: note)))
            if host.isAway() { host.notify(batch.id, ExportChoices.failedTitle, note, false) }
        }
    }

    /// The notification's line: the file, or what was saved.
    private static func readyBody(_ result: Result) -> String {
        if let note = result.photosNote { return note }
        guard let first = result.urls.first else { return "" }
        return result.urls.count == 1 ? first.lastPathComponent : trn("%d file|%d files", result.urls.count)
    }

    private func report(_ fraction: Double, for id: UUID) {
        guard current?.id == id else { return }
        progress = min(1, max(0, fraction))
        if let continued = continuedTask, continued.job == id, let job = current {
            let total = Int64(Self.units(job))
            continued.handle.report(Int64((progress * Double(total)).rounded(.down)), total)
        }
    }

    // MARK: in the background

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = host.begin { [weak self] in self?.backgroundTimeRanOut() }
    }

    private func endBackground() {
        host.end(backgroundTask)
        backgroundTask = .invalid
    }

    /// The system's time is up: the export waits at its next page or frame,
    /// and says so, until the app is back — unless it runs on under its
    /// continued processing task.
    private func backgroundTimeRanOut() {
        endBackground()
        guard let job = current, host.isAway(), continuedTask?.job != job.id else { return }
        paused = true
        host.notify(job.id, ExportChoices.pausedTitle, ExportChoices.paused, false)
    }

    /// The app is back: a paused export carries on, under a fresh
    /// background task in case it is left again.
    func resume() {
        guard paused else { return }
        paused = false
        if current != nil { beginBackground() }
    }

    // MARK: on iOS 26, out of the app

    /// What the system counts an export in: its frames or pages, or a
    /// hundredth of the way for one that does not say.
    static func units(_ job: Job) -> Int { job.units > 0 ? job.units : 100 }

    /// "Exporting <title>": what the system shows over an export that keeps
    /// going out of the app.
    static func continuedTitle(_ job: Job) -> String {
        tr("Exporting %@", job.title ?? job.label)
    }

    /// The export's continued processing task asked for, once: as it
    /// starts, or — not granted then — as the app is left with it running
    /// (`left`).
    private func beginContinued(_ job: Job) {
        guard continuedAsked != job.id else { return }
        if host.beginContinued(job.id, Self.continuedTitle(job), job.detail) { continuedAsked = job.id }
    }

    /// The app has gone to the background: an export running asks for its
    /// continued processing task, if it has not yet.
    func left() {
        if let job = current { beginContinued(job) }
    }

    /// The system has started export `job`'s continued processing task:
    /// how far along it is reported to it from now on, and a paused export
    /// carries on under it. Should the system stop it, the export stops
    /// cleanly and says so. One for an export already over is ended at
    /// once.
    func continued(_ handle: ContinuedExport.Handle, job: UUID) {
        guard current?.id == job else {
            handle.finish(outcomes.last(where: { $0.job == job })?.success ?? false)
            return
        }
        continuedTask = Continued(job: job, handle: handle)
        handle.onExpiry { [weak self] in
            Task { @MainActor in self?.continuedExpired(job) }
        }
        report(progress, for: job)
        if paused {
            paused = false
            beginBackground()
        }
    }

    /// The system stopped export `job`'s continued processing task: the
    /// export is cancelled, and a notification says to open Canvia to
    /// finish.
    func continuedExpired(_ job: UUID) {
        guard let continued = continuedTask, continued.job == job else { return }
        continuedTask = nil
        continued.handle.finish(false)
        cancel(job)
        host.notify(job, ExportChoices.failedTitle, ExportChoices.stoppedAway, false)
    }

    /// The export over: its continued processing task, when it has one,
    /// ended as it went; asked for but not yet started, withdrawn, so the
    /// system does not start it later and show it as failed.
    private func endContinued(_ job: UUID, success: Bool) {
        if let task = continuedTask {
            task.handle.finish(success)
        } else if let asked = continuedAsked {
            host.cancelContinued(asked)
        }
        continuedTask = nil
        continuedAsked = nil
        outcomes.append((job: job, success: success))
        if outcomes.count > 20 { outcomes.removeFirst(outcomes.count - 20) }
    }

    /// Where every exporter's pause between pages or frames waits while the
    /// export is paused; a Cancel meanwhile ends the wait.
    nonisolated static func waitWhilePaused() async throws {
        while true {
            let waiting = await ExportQueue.shared.paused
            guard waiting else { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}

/// The export as it was when it started: a copy of the design, and the
/// pages it writes, by index into that copy. Edits made meanwhile change
/// neither.
struct ExportSnapshot {
    let design: Design
    let pages: [Int]
    /// The page on screen when it started.
    let current: Int
    /// The editor's playhead on that page, in seconds into it: where its
    /// caption boxes stand in a picture of it; nil for their first cue.
    var captionTime: Double?

    init(_ design: Design, range: DesignExporter.PageRange, current: Int) {
        // An expanded whiteboard goes out as its bounds and their margin
        // (Whiteboards), in every format.
        self.design = Whiteboards.flattened(design)
        self.current = current
        pages = range.indices(in: design, current: current)
    }

    /// Exactly those pages, as the exporters take a range.
    var range: DesignExporter.PageRange { .chosen(pages.map { design.pages[$0].id }) }
}

/// The local notifications an export posts, and the Share and Open on
/// them.
final class ExportNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ExportNotifications()
    static let category = "canvia.export.done"
    static let shareAction = "canvia.export.share"
    static let openAction = "canvia.export.open"
    /// A failure's Try again, as it was or smaller.
    static let failedCategory = "canvia.export.failed"
    static let retryAction = "canvia.export.retry"
    static let retrySmallerAction = "canvia.export.retrySmaller"

    /// At launch: this object hears the actions, the done category has its
    /// Share and Open, and a planned post's reminder its Share now
    /// (PostReminders).
    static func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        let share = UNNotificationAction(identifier: shareAction, title: ExportChoices.shareAction, options: [.foreground])
        let open = UNNotificationAction(identifier: openAction, title: ExportChoices.openAction, options: [.foreground])
        center.setNotificationCategories(Set([UNNotificationCategory(identifier: category, actions: [share, open],
                                                                      intentIdentifiers: [], options: []),
                                              PostReminders.notificationCategory] + failureCategories))
    }

    /// A failure's: Try again alone, and Try again with each smaller try
    /// there can be — "Try at 1×", "Try at 1080p", "Try at 720p" — whose
    /// labels a category fixes when it is registered.
    static var failureCategories: [UNNotificationCategory] {
        let again = UNNotificationAction(identifier: retryAction, title: ExportFailure.tryAgain, options: [.foreground])
        let plain = UNNotificationCategory(identifier: failedCategory, actions: [again], intentIdentifiers: [], options: [])
        let smaller = smallerLabels.map { label in
            UNNotificationCategory(identifier: categoryFor(smaller: label),
                                   actions: [again, UNNotificationAction(identifier: retrySmallerAction, title: label,
                                                                         options: [.foreground])],
                                   intentIdentifiers: [], options: [])
        }
        return [plain] + smaller
    }

    /// Every label a smaller try can have (ExportFailure.suggestion).
    static var smallerLabels: [String] {
        [tr("Try at 1×")] + MovieExporter.Resolution.allCases.dropLast().map { tr("Try at %@", $0.rawValue) }
    }

    /// The category of a failure suggesting `smaller`, or of one with none.
    static func categoryFor(smaller: String?) -> String {
        guard let smaller, smallerLabels.contains(smaller) else { return failedCategory }
        return failedCategory + "|" + smaller
    }

    /// Export `job`'s failure: why, with Try again and the smaller try.
    static func postFailed(job: UUID, title: String, body: String, smaller: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryFor(smaller: smaller)
        let request = UNNotificationRequest(identifier: identifier(job: job), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Asked once, the first time an export is kept going in the
    /// background, as the Android twin asks at its first.
    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Each export's own, so one done does not replace another's; its
    /// "Paused" is replaced by its "ready".
    static let identifierPrefix = "canvia.export."

    static func identifier(job: UUID) -> String { identifierPrefix + job.uuidString }

    static func post(job: UUID, title: String, body: String, actions: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if actions { content.categoryIdentifier = category }
        let request = UNNotificationRequest(identifier: identifier(job: job), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Taken down once its export has been delivered in the app.
    static func clear(job: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier(job: job)])
    }

    /// Share or Open, for the export it was posted for; the notification
    /// itself opens the app, which hands every export on in turn
    /// (ExportQueue.tapped).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // A planned post's reminder: Share now, or the reminder itself,
        // makes the post and shares it.
        if let post = PostReminders.post(of: response.notification.request) {
            if response.actionIdentifier != UNNotificationDismissActionIdentifier {
                Task { @MainActor in await PostReminders.shareNow(designId: post.designId, postId: post.postId) }
            }
            completionHandler()
            return
        }
        let request = Self.request(for: response.actionIdentifier)
        let identifier = response.notification.request.identifier
        let job = identifier.hasPrefix(Self.identifierPrefix)
            ? UUID(uuidString: String(identifier.dropFirst(Self.identifierPrefix.count))) : nil
        // A failure's Try again, as it was or smaller.
        let action = response.actionIdentifier
        if action == Self.retryAction || action == Self.retrySmallerAction, let job {
            Task { @MainActor in
                ExportQueue.shared.retry(job, smaller: action == Self.retrySmallerAction)
            }
            completionHandler()
            return
        }
        Task { @MainActor in
            ExportQueue.shared.tapped(request, job: job)
        }
        completionHandler()
    }

    /// The Share or Open button tapped; nil for the notification itself.
    static func request(for action: String) -> ExportQueue.Request? {
        switch action {
        case openAction: return .open
        case shareAction: return .share
        default: return nil
        }
    }

    /// In the app, the pill already says an export's; a planned post's
    /// reminder shows, as it is the time to post.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(PostReminders.post(of: notification.request) != nil ? [.banner, .sound, .list] : [])
    }
}

/// A finished export delivered where the sheet is not there to: shared from
/// whatever is on screen, opened in Quick Look, or sent to the printer.
@MainActor
enum ExportPresenter {

    /// What is on top: the key window's root, through whatever it presents.
    static var topController: UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    /// The share sheet, preview or print dialog of a delivered export gone:
    /// the next can be delivered.
    private static func dismissed() {
        ExportQueue.shared.delivering = false
    }

    static func share(_ urls: [URL]) {
        guard !urls.isEmpty, let top = topController else { return }
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        ExportQueue.shared.delivering = true
        sheet.completionWithItemsHandler = { _, _, _, _ in
            MainActor.assumeIsolated { dismissed() }
        }
        // iPad shows it as a popover, which needs somewhere to point.
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY,
                                                                 width: 1, height: 1)
        top.present(sheet, animated: true)
    }

    /// Quick Look, which holds its source only weakly; kept here while it
    /// shows.
    private static var previewSource: PreviewSource?

    static func open(_ url: URL) {
        guard let top = topController else { return }
        let source = PreviewSource(url: url)
        previewSource = source
        let preview = QLPreviewController()
        preview.dataSource = source
        preview.delegate = source
        ExportQueue.shared.delivering = true
        top.present(preview, animated: true)
    }

    /// The print dialog for a PDF already written.
    static func print(_ request: ExportQueue.PrintRequest) {
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = request.jobName
        info.orientation = request.landscape ? .landscape : .portrait
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = request.url
        ExportQueue.shared.delivering = true
        let done: UIPrintInteractionController.CompletionHandler = { _, _, _ in
            MainActor.assumeIsolated { dismissed() }
        }
        // iPad refuses the sheet-less presentation and raises rather than
        // failing quietly, so it gets an anchor rect.
        let shown: Bool
        if let anchor = topController?.view, UIDevice.current.userInterfaceIdiom == .pad {
            shown = controller.present(from: CGRect(x: anchor.bounds.midX, y: anchor.bounds.midY, width: 1, height: 1),
                                       in: anchor, animated: true, completionHandler: done)
        } else {
            shown = controller.present(animated: true, completionHandler: done)
        }
        if !shown { dismissed() }
    }

    /// A result delivered with the sheet gone: printed, shared — or opened,
    /// when Open asked — and what there is to say put in the pill.
    static func deliver(_ finished: ExportQueue.Finished, request: ExportQueue.Request?, queue: ExportQueue) {
        let result = finished.result
        // A failure kept to try again says itself, in its row of the pill.
        let kept = queue.isKeptFailure(finished.id)
        if let failed = result.failed {
            if !kept { queue.note = failed }
            return
        }
        if let print = result.print {
            self.print(print)
        } else if request == .open, let first = result.urls.first {
            open(first)
        } else {
            share(result.urls)
        }
        if let note = result.photosNote {
            queue.note = note
        } else if result.musicLost {
            queue.note = ExportChoices.musicLost
        } else if let skipped = result.skipped, !kept {
            queue.note = skipped
        }
    }

    private final class PreviewSource: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            MainActor.assumeIsolated { ExportPresenter.dismissed() }
        }
    }
}
