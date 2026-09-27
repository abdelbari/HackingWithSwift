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
        guard let first = design.pages.first else { return }
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: first))
        renderer.scale = CGFloat(thumbnailScale(pageWidth: Double(design.size(at: 0).width)))
        // The alpha channel is discarded by jpegData when the thumbnail is
        // written, so compositing it is wasted work.
        renderer.isOpaque = true
        if let image = renderer.uiImage {
            saveThumbnail(image, for: design.id)
        }
    }

    /// Designs on the shelf with no thumbnail get one. Each is tried once a
    /// launch, so a design that will not render is not re-rendered on every
    /// visit to Home. True when any was written.
    @MainActor
    @discardableResult
    static func fillMissingThumbnails(_ recents: [RecentDesign]) -> Bool {
        var wrote = false
        for recent in recents where recent.thumbnail == nil && !thumbnailTried.contains(recent.id) {
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
}
