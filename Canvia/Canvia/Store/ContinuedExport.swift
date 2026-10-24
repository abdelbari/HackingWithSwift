// An export that keeps going once Canvia is left, on iOS 26 and later: the
// system's continued processing task (BGContinuedProcessingTask), asked
// for as an export starts — or as the app is left with one running — under
// "com.canvia.export.<job id>", queued behind any other. The system shows
// its title and subtitle and how far along it is, which the queue reports
// (ExportQueue.progress); it ends when the export does, and should the
// system stop it, the export stops cleanly and says so. Below iOS 26 the
// queue's own background task is all there is, and an export left too long
// waits for the app to come back (ExportQueue). The Android twin's
// foreground service (ExportService) does this on every Android.
//
// The wildcard identifier is in Canvia-Info.plist's
// BGTaskSchedulerPermittedIdentifiers; its launch handler is registered as
// the app starts. Built only by a compiler that knows iOS 26's SDK.

import BackgroundTasks
import Foundation

enum ContinuedExport {

    /// Every export's task identifier starts so, its job's id after it.
    static let prefix = "com.canvia.export."
    /// What the app registers, and Info.plist permits.
    static let wildcard = prefix + "*"

    static func identifier(job: UUID) -> String { prefix + job.uuidString }

    /// The job a task identifier names, or nil for another.
    static func job(of identifier: String) -> UUID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }

    /// Whether an export keeps going in the background here: iOS 26 and
    /// later, built with its SDK.
    static var isSupported: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26, *) { return true }
        #endif
        return false
    }

    /// At launch, before the app finishes starting: the handler every
    /// export's task runs, which hands the task to the queue.
    static func register() {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: wildcard, using: nil) { task in
                guard let continued = task as? BGContinuedProcessingTask, let id = ContinuedExport.job(of: task.identifier) else {
                    task.setTaskCompleted(success: false)
                    return
                }
                let handle = Handle(continued)
                Task { @MainActor in ExportQueue.shared.continued(handle, job: id) }
            }
        }
        #endif
    }

    /// Asks for export `job`'s task: `title` and `subtitle` are what the
    /// system shows. Queued behind any other running; false when it could
    /// not be asked for, or this is not iOS 26.
    @MainActor
    static func submit(job: UUID, title: String, subtitle: String) -> Bool {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            let request = BGContinuedProcessingTaskRequest(identifier: identifier(job: job), title: title,
                                                           subtitle: subtitle)
            request.strategy = .queue
            do {
                try BGTaskScheduler.shared.submit(request)
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }

    /// The task as the queue holds it: how far along, its end, and what to
    /// do should the system stop it — closures, so the queue builds and is
    /// tested without iOS 26's types (ExportQueue.Continued).
    final class Handle {
        let report: (_ done: Int64, _ total: Int64) -> Void
        let finish: (_ success: Bool) -> Void
        let onExpiry: (_ expired: @escaping () -> Void) -> Void

        init(report: @escaping (Int64, Int64) -> Void, finish: @escaping (Bool) -> Void,
             onExpiry: @escaping (@escaping () -> Void) -> Void) {
            self.report = report
            self.finish = finish
            self.onExpiry = onExpiry
        }

        #if compiler(>=6.2)
        @available(iOS 26, *)
        convenience init(_ task: BGContinuedProcessingTask) {
            self.init(report: { done, total in
                task.progress.totalUnitCount = max(total, 1)
                task.progress.completedUnitCount = min(max(done, 0), max(total, 1))
            }, finish: { success in
                task.setTaskCompleted(success: success)
            }, onExpiry: { expired in
                task.expirationHandler = expired
            })
        }
        #endif
    }
}
