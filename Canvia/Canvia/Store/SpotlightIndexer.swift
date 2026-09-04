// Designs in Spotlight: findable by title and by the words typed into them.
//
// Every save re-indexes the design with its title, every text element's
// words as searchable content and its thumbnail; a delete removes it.
// Opening a result hands the app the design id through the user activity.

import CoreSpotlight
import UIKit
import UniformTypeIdentifiers

enum SpotlightIndexer {

    static let domain = "com.canvia.designs"

    /// Every distinct word in the design's text, for the searchable content.
    static func words(in design: Design) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for page in design.pages {
            for el in page.elements where el.type == .text {
                for word in (el.text ?? "").split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                    let w = word.lowercased()
                    if w.count > 1, seen.insert(w).inserted { out.append(w) }
                }
            }
        }
        return out
    }

    static func attributes(for design: Design, thumbnail: UIImage? = nil) -> CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .content)
        attrs.title = design.title
        let words = words(in: design)
        attrs.contentDescription = words.isEmpty
            ? "\(design.pages.count == 1 ? "1 page" : "\(design.pages.count) pages"), \(Int(design.width)) × \(Int(design.height))"
            : words.prefix(40).joined(separator: " ")
        attrs.keywords = Array(words.prefix(60))
        attrs.thumbnailData = thumbnail?.jpegData(compressionQuality: 0.6)
        return attrs
    }

    static func index(_ design: Design) { index(design, thumbnail: nil) }

    static func index(_ design: Design, thumbnail: UIImage?) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let item = CSSearchableItem(uniqueIdentifier: design.id, domainIdentifier: domain,
                                    attributeSet: attributes(for: design, thumbnail: thumbnail))
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    static func remove(_ id: String) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id])
    }

    /// The design id a Spotlight result carries.
    static func designID(from activity: NSUserActivity) -> String? {
        guard activity.activityType == CSSearchableItemActionType else { return nil }
        return activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    }
}
