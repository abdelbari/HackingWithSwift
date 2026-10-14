// Exports that keep going once the sheet is closed, or the app is left.
//
// The queue belongs to the app, not to the Export sheet: the sheet hands it
// a job made from a snapshot of the design as it was at that moment
// (ExportSnapshot), so editing carries on beside it, and closing the sheet
// leaves it running. One export runs at a time; another asked for meanwhile
// waits its turn. A pill above the editor's toolbar, and on Home, says how
// far along it is, and its X stops it.
//
// Out of the app, the work is wrapped in a background task. When the time
// the system gives runs out, the export stops between two pages or frames
// (every exporter steps aside through Pacer.breathe, which waits here) —
// a video's writer simply waits, open, for its next frame — and a
// notification says "Paused — return to Canvia to finish"; coming back
// carries it on. Done while away, a notification says so, with Share and
// Open; the file is shared or opened as the app comes back, as it would
// have been in the sheet. The Android twin holds its job in a foreground
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
        let work: Work
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

    /// Begins and ends the background task, says whether the app is out of
    /// sight, and posts and takes down an export's notification — one for
    /// each export, so one done does not replace another's: the app's own,
    /// or none in a test.
    struct Host {
        var begin: @MainActor (_ expired: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier
        var end: @MainActor (UIBackgroundTaskIdentifier) -> Void
        var isAway: @MainActor () -> Bool
        var notify: @MainActor (_ job: UUID, _ title: String, _ body: String, _ actions: Bool) -> Void
        var clear: @MainActor (_ job: UUID) -> Void

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
            clear: { job in ExportNotifications.clear(job: job) })

        static let none = Host(begin: { _ in .invalid }, end: { _ in }, isAway: { false },
                               notify: { _, _, _, _ in }, clear: { _ in })
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

    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Result, Error>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(host: Host) {
        self.host = host
    }

    var isBusy: Bool { current != nil || !waiting.isEmpty }

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
            waiting.removeAll { $0.id == id }
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
        waiting.removeAll()
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
            do {
                let result = try await task.value
                finished.append(Finished(id: job.id, label: job.label, designId: job.designId, result: result))
                if host.isAway() { host.notify(job.id, ExportChoices.readyTitle, Self.readyBody(result), !result.urls.isEmpty) }
            } catch is CancellationError {
                // Asked for; nothing to say.
            } catch {
                let failed = Result(failed: ExportChoices.failedText(error.localizedDescription))
                finished.append(Finished(id: job.id, label: job.label, designId: job.designId, result: failed))
                if host.isAway() { host.notify(job.id, ExportChoices.failedTitle, error.localizedDescription, false) }
            }
            running = nil
            current = nil
            endBackground()
        }
        runner = nil
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
    /// and says so, until the app is back.
    private func backgroundTimeRanOut() {
        endBackground()
        guard let job = current, host.isAway() else { return }
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

    init(_ design: Design, range: DesignExporter.PageRange, current: Int) {
        self.design = design
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

    /// At launch: this object hears the actions, and the done category has
    /// its Share and Open.
    static func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        let share = UNNotificationAction(identifier: shareAction, title: ExportChoices.shareAction, options: [.foreground])
        let open = UNNotificationAction(identifier: openAction, title: ExportChoices.openAction, options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: category, actions: [share, open],
                                                                  intentIdentifiers: [], options: [])])
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
        let request = Self.request(for: response.actionIdentifier)
        let identifier = response.notification.request.identifier
        let job = identifier.hasPrefix(Self.identifierPrefix)
            ? UUID(uuidString: String(identifier.dropFirst(Self.identifierPrefix.count))) : nil
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

    /// In the app, the pill already says it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
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
        if let failed = result.failed {
            queue.note = failed
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
