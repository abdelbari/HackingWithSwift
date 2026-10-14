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
    /// sight, and posts notifications: the app's own, or none in a test.
    struct Host {
        var begin: @MainActor (_ expired: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier
        var end: @MainActor (UIBackgroundTaskIdentifier) -> Void
        var isAway: @MainActor () -> Bool
        var notify: @MainActor (_ title: String, _ body: String, _ actions: Bool) -> Void

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
            notify: { title, body, actions in ExportNotifications.post(title: title, body: body, actions: actions) })

        static let none = Host(begin: { _ in .invalid }, end: { _ in }, isAway: { false }, notify: { _, _, _ in })
    }

    private let host: Host
    /// The export running, and how far along it is.
    private(set) var current: Job?
    private(set) var progress: Double = 0
    /// The exports asked for while one runs, in turn.
    private(set) var waiting: [Job] = []
    /// The last export done, until it is taken.
    var finished: Finished?
    /// Why the last export failed, until it is said.
    var failure: String?
    /// Something to say once the sheet has gone: a save to Photos, a video
    /// without its music, a failure.
    var note: String?
    /// Out of the app with the background time run out: the export waits
    /// between two pages or frames until the app is back.
    private(set) var paused = false
    /// A notification's Share or Open, waiting for the app to come back.
    var requested: Request?
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
        failure = nil
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

    /// Returns once nothing runs or waits.
    func waitUntilIdle() async {
        while let runner { await runner.value }
    }

    /// The finished export handed over, and forgotten here.
    func takeFinished() -> Finished? {
        defer { finished = nil }
        return finished
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
                finished = Finished(id: job.id, label: job.label, designId: job.designId, result: result)
                if host.isAway() { host.notify(ExportChoices.readyTitle, Self.readyBody(result), !result.urls.isEmpty) }
            } catch is CancellationError {
                // Asked for; nothing to say.
            } catch {
                failure = ExportChoices.failedText(error.localizedDescription)
                if host.isAway() { host.notify(ExportChoices.failedTitle, error.localizedDescription, false) }
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
        return result.urls.count == 1 ? first.lastPathComponent : "\(result.urls.count) files"
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
        guard current != nil, host.isAway() else { return }
        paused = true
        host.notify(ExportChoices.pausedTitle, ExportChoices.paused, false)
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

    static func post(title: String, body: String, actions: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if actions { content.categoryIdentifier = category }
        let request = UNNotificationRequest(identifier: "canvia.export", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Share, Open, or the notification itself — which shares, as the sheet
    /// would have.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let open = response.actionIdentifier == Self.openAction
        Task { @MainActor in
            ExportQueue.shared.requested = open ? .open : .share
        }
        completionHandler()
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

    static func share(_ urls: [URL]) {
        guard !urls.isEmpty, let top = topController else { return }
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
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
        // iPad refuses the sheet-less presentation and raises rather than
        // failing quietly, so it gets an anchor rect.
        if let anchor = topController?.view, UIDevice.current.userInterfaceIdiom == .pad {
            controller.present(from: CGRect(x: anchor.bounds.midX, y: anchor.bounds.midY, width: 1, height: 1),
                               in: anchor, animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }

    /// A result delivered with the sheet gone: printed, shared — or opened,
    /// when Open asked — and what there is to say put in the pill.
    static func deliver(_ finished: ExportQueue.Finished, request: ExportQueue.Request?, queue: ExportQueue) {
        let result = finished.result
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

    private final class PreviewSource: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
