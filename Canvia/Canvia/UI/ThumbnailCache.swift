// Page thumbnails made once and kept, and made one at a time. A deck of a
// hundred pages used to render every thumbnail as it opened — the pages
// bar's and, scrolling through pages, the column's — each a full
// ImageRenderer pass on the main thread, and all of them again whenever a
// photo's focus subject was found. Now every thumbnail — pages bar,
// organiser, export's page picker, the column — asks here: one already
// made for a page as it stands comes back at once, and the rest wait their
// turn, the ones on screen first, at most one pass per turn of the main run
// loop so scrolling and touches go on between them, and a thumbnail
// scrolled away before its turn is never made.

import SwiftUI
import UIKit

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let images: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 600
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    /// A thumbnail waiting its turn.
    private struct Waiting {
        let id: Int
        let key: String
        let priority: Int
        let make: @MainActor () -> UIImage?
        let done: CheckedContinuation<UIImage?, Never>
    }

    private var waiting: [Waiting] = []
    private var nextId = 0
    private var scheduled = false

    /// What a thumbnail is kept under: the page's id, a hash of the page as
    /// it is written — and of what the master draws behind it, and its size
    /// — how many looks made off the main thread (`baked`) and focus
    /// subjects found (`subjects`) it has seen, and how many pixels wide it
    /// is drawn. Any change to what is drawn is another key, so a kept
    /// thumbnail is never out of date.
    nonisolated static func key(page: Page, design: Design, baked: Int, subjects: Int, pixelWidth: Int) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var hasher = Hasher()
        hasher.combine((try? encoder.encode(page)) ?? Data())
        hasher.combine((try? encoder.encode(design.masterElements(behind: page))) ?? Data())
        let size = design.size(for: page)
        hasher.combine(size.width)
        hasher.combine(size.height)
        return "\(page.id)|\(hasher.finalize())|\(baked)|\(subjects)|\(pixelWidth)"
    }

    func cached(_ key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    /// The thumbnail kept under `key`, or made by `make` in its turn — the
    /// lowest `priority` first, then the first asked — and kept. Nil when
    /// the task asking is cancelled first: its view gone, scrolled away, or
    /// its page changed again.
    func image(_ key: String, priority: Int, make: @escaping @MainActor () -> UIImage?) async -> UIImage? {
        if let hit = cached(key) { return hit }
        let id = nextId
        nextId += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<UIImage?, Never>) in
                waiting.append(Waiting(id: id, key: key, priority: priority, make: make, done: done))
                scheduleNext()
            }
        } onCancel: {
            Task { @MainActor in ThumbnailCache.shared.abandon(id) }
        }
    }

    /// A job no longer wanted, answered with nothing.
    private func abandon(_ id: Int) {
        guard let i = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: i).done.resume(returning: nil)
    }

    /// The next job on a turn of its own.
    private func scheduleNext() {
        guard !scheduled, !waiting.isEmpty else { return }
        scheduled = true
        Task { @MainActor in ThumbnailCache.shared.makeNext() }
    }

    /// One thumbnail made — the first in line — then the next scheduled.
    private func makeNext() {
        scheduled = false
        let order = waiting.indices.min { a, b in
            (waiting[a].priority, waiting[a].id) < (waiting[b].priority, waiting[b].id)
        }
        guard let order else { return }
        let job = waiting.remove(at: order)
        let image = cached(job.key) ?? job.make()
        if let image {
            let pixels = image.size.width * image.size.height * image.scale * image.scale
            images.setObject(image, forKey: job.key as NSString, cost: Int(pixels) * 4)
        }
        job.done.resume(returning: image)
        scheduleNext()
    }
}
