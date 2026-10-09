// The picture on a design's card on Home: its first page, about 300 points
// wide, rendered from the same view the canvas draws.
//
// Written when the editor closes, and — so no card is a grey box — for the
// sample designs the first launch puts on the shelf, and for any design
// that reached the shelf without ever being opened here (a file from the
// Android twin, say). The Android twin writes its samples' thumbnails as it
// seeds them, too.

import SwiftUI
import UIKit

extension DesignLibrary {

    /// The width, in points, a thumbnail is rendered at.
    static let thumbnailWidth: Double = 300

    /// The render scale that puts a page `width` wide at the thumbnail's
    /// width.
    static func thumbnailScale(pageWidth width: Double) -> Double {
        thumbnailWidth / max(width, 1)
    }

    /// Render page one of `design` and keep it as the design's thumbnail.
    @MainActor
    static func writeThumbnail(for design: Design) {
        if let image = thumbnailImage(for: design) {
            saveThumbnail(image, for: design.id)
        }
    }

    /// Page one of `design` at the thumbnail's width, as its card shows it;
    /// a kept version's row in Version history draws with this too.
    @MainActor
    static func thumbnailImage(for design: Design) -> UIImage? {
        guard let first = design.pages.first else { return nil }
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: first))
        renderer.scale = CGFloat(thumbnailScale(pageWidth: Double(design.size(at: 0).width)))
        // The alpha channel is discarded by jpegData when the thumbnail is
        // written, so compositing it is wasted work.
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Designs on the shelf with no thumbnail get one. Each is tried once a
    /// launch, so a design that will not render is not re-rendered on every
    /// visit to Home. True when any was written.
    @MainActor
    @discardableResult
    static func fillMissingThumbnails(_ recents: [RecentDesign]) -> Bool {
        var wrote = false
        for recent in recents where recent.thumbnailStamp == nil && !recent.damaged
            && !thumbnailTried.contains(recent.id) {
            thumbnailTried.insert(recent.id)
            guard let design = load(id: recent.id) else { continue }
            writeThumbnail(for: design)
            wrote = true
        }
        return wrote
    }

    /// Ids tried this launch.
    @MainActor
    private static var thumbnailTried: Set<String> = []

    // MARK: on the cards

    /// Where a design's picture is kept: beside the shelf, or in the trash
    /// with the design.
    static func thumbnailURL(for id: String, trashed: Bool = false) -> URL {
        (trashed ? trashDir : thumbsDir).appendingPathComponent("\(id).jpg")
    }

    /// When each design's picture was last written, in epoch milliseconds,
    /// by design id, from one listing of the folder rather than a look at
    /// each file.
    static func thumbnailStamps(trashed: Bool) -> [String: Double] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: trashed ? trashDir : thumbsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [:] }
        var stamps: [String: Double] = [:]
        for url in files where url.pathExtension == "jpg" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            stamps[url.deletingPathExtension().lastPathComponent] = (date?.timeIntervalSince1970 ?? 0) * 1000
        }
        return stamps
    }

    /// Pictures already read, by design and when each was written, so a
    /// card scrolled back to, or Home shown again, draws at once.
    private static let cardImages: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    private static func cardImageKey(_ id: String, stamp: Double, trashed: Bool) -> NSString {
        "\(trashed ? "trash" : "shelf")/\(id)@\(stamp)" as NSString
    }

    /// The card's picture if it has been read already.
    static func cachedCardImage(for id: String, stamp: Double, trashed: Bool) -> UIImage? {
        cardImages.object(forKey: cardImageKey(id, stamp: stamp, trashed: trashed))
    }

    /// The card's picture, read and decoded off the main thread.
    static func cardImage(for id: String, stamp: Double, trashed: Bool) async -> UIImage? {
        let key = cardImageKey(id, stamp: stamp, trashed: trashed)
        if let hit = cardImages.object(forKey: key) { return hit }
        let url = thumbnailURL(for: id, trashed: trashed)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
            // Decoded here rather than at its first draw, on the main thread.
            return image.preparingForDisplay() ?? image
        }.value
        if let image { cardImages.setObject(image, forKey: key) }
        return image
    }
}

/// A design's picture on its card: read from disk as the card first shows,
/// not every card's before Home can draw, and grey until then or when there
/// is none.
struct ShelfThumbnail: View {
    let id: String
    /// When the picture was written; a new one is read when it changes.
    let stamp: Double?
    var trashed = false
    @State private var image: UIImage?

    init(id: String, stamp: Double?, trashed: Bool = false) {
        self.id = id
        self.stamp = stamp
        self.trashed = trashed
        _image = State(initialValue: stamp.flatMap {
            DesignLibrary.cachedCardImage(for: id, stamp: $0, trashed: trashed)
        })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(.systemGray5)
            }
        }
        .task(id: stamp) {
            guard let stamp else {
                image = nil
                return
            }
            image = await DesignLibrary.cardImage(for: id, stamp: stamp, trashed: trashed)
        }
    }
}
