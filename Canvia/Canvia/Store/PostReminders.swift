// A planned post's reminder (PostPlanner): a local notification at its time
// (UNCalendarNotificationTrigger), with Share now — which copies the
// caption, makes the file from the design as it is then on the export queue
// and opens the share sheet as a finished export's Share does. Marking the
// post done or deleting it takes the reminder away. The Android twin's
// PostReminders, which sets an alarm for the same.

import UIKit
import UserNotifications

enum PostReminders {

    static let category = "canvia.post.due"
    static let shareNowAction = "canvia.post.share"
    static let identifierPrefix = "canvia.post."

    /// The keys a reminder carries its post by.
    static let designKey = "designId"
    static let postKey = "postId"

    /// Each post's own: one reminder never replaces another's.
    static func identifier(designId: String, postId: String) -> String {
        identifierPrefix + designId + "." + postId
    }

    /// The reminder's category, with its Share now, for ExportNotifications
    /// to register beside its own.
    static var notificationCategory: UNNotificationCategory {
        let share = UNNotificationAction(identifier: shareNowAction, title: tr("Share now"), options: [.foreground])
        return UNNotificationCategory(identifier: category, actions: [share], intentIdentifiers: [], options: [])
    }

    /// The reminder for `post` of `design` set, in place of any it had; none
    /// for a post done or whose time has gone.
    static func schedule(_ post: PlannedPost, of design: Design, now: Date = Date()) {
        let id = identifier(designId: design.id, postId: post.id)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard !post.done, let at = PostPlanner.date(post.at), at > now else { return }
        let content = UNMutableNotificationContent()
        content.title = tr("Time to post %@", design.title)
        content.body = post.caption.isEmpty ? tr("Your post is ready to share.") : post.caption
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = [designKey: design.id, postKey: post.id]
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Post `postId`'s reminder taken away, waiting or shown.
    static func cancel(designId: String, postId: String) {
        let id = identifier(designId: designId, postId: postId)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Every reminder of design `designId` taken away, waiting or shown:
    /// the design went to Recently deleted.
    static func cancelAll(designId: String) {
        let prefix = identifier(designId: designId, postId: "")
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
        center.getDeliveredNotifications { shown in
            center.removeDeliveredNotifications(withIdentifiers: shown.map(\.request.identifier).filter { $0.hasPrefix(prefix) })
        }
    }

    /// Design `designId`, back from Recently deleted, has its reminders
    /// again.
    static func restored(designId: String) {
        guard let design = DesignLibrary.load(id: designId) else { return }
        rescheduleAll([design])
    }

    /// The reminders brought in line with `design`'s posts, as they were in
    /// `before`: those gone or done taken away, the rest set.
    static func reschedule(_ design: Design, before: Design) {
        let now = PostPlanner.of(design)
        for old in PostPlanner.of(before) where !now.contains(where: { $0.id == old.id && !$0.done }) {
            cancel(designId: before.id, postId: old.id)
        }
        for post in now { schedule(post, of: design) }
    }

    /// Whether a notification is a post's reminder; its design and post.
    static func post(of request: UNNotificationRequest) -> (designId: String, postId: String)? {
        guard request.identifier.hasPrefix(identifierPrefix),
              let design = request.content.userInfo[designKey] as? String,
              let post = request.content.userInfo[postKey] as? String else { return nil }
        return (design, post)
    }

    /// Share now: the caption copied, and the post made from the design as
    /// it is now — its format, its pages — on the export queue, shared as
    /// it is done. Nothing for a post no longer there.
    @MainActor
    static func shareNow(designId: String, postId: String) async {
        guard let loaded = try? await HomeExports.load(designId),
              let post = PostPlanner.of(loaded).first(where: { $0.id == postId }) else {
            ExportQueue.shared.note = tr("Couldn't make the post")
            return
        }
        if !post.caption.isEmpty { UIPasteboard.general.string = post.caption }
        // A Doc as its pages.
        let design = DocPages.drawn(loaded)
        let ids = PostPlanner.pageIndices(design, post).map { design.pages[$0].id }
        let snapshot = ExportSnapshot(design, range: .chosen(ids), current: 0)
        let job = ExportQueue.Job(label: tr("Making the post"), designId: design.id, work: postExport(post.format, snapshot))
        // Shared once it is done, as any export finished with the Export
        // sheet closed is (ExportDelivery).
        ExportQueue.shared.enqueue(job)
    }

    /// The export a post's format makes.
    @MainActor
    static func postExport(_ format: String, _ snapshot: ExportSnapshot) -> ExportQueue.Work {
        let settings = MovieExporter.Settings(snapshot.design.motion)
        switch format {
        case "jpg":
            return ExportJobs.pictures(snapshot, format: .jpeg, scale: 2, longEdge: 0, quality: 0.92, transparent: false)
        case "pdf":
            return ExportJobs.pdf(snapshot, flatten: false, tagged: true)
        case "mp4":
            return ExportJobs.movie(snapshot, settings: settings)
        case "gif":
            return ExportJobs.gif(snapshot, settings: settings)
        default:
            return ExportJobs.pictures(snapshot, format: .png, scale: 2, longEdge: 0, quality: 0.92, transparent: false)
        }
    }

    /// At launch and after a restore: every post not done whose time is
    /// still to come has its reminder, as a restore may have left one unset.
    static func rescheduleAll(_ designs: [Design]) {
        for design in designs {
            for post in PostPlanner.of(design) { schedule(post, of: design) }
        }
    }
}
