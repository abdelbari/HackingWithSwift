// Contextual tips: earned, one at a time, never twice.
//
// A tip is shown when the thing it is about has just become relevant — the
// first text element, the first multi-selection — and only then. Each fires
// once per install, at most one every so often, so the editor never
// nags and a returning user never sees the tour again.

import Foundation

enum TipEvent: String, Equatable {
    case firstElementAdded, textAdded, photoAdded, multiSelected, manyElements, curvedText
    case rotated, pageAdded, drewStroke, dropped
}

struct Tip: Equatable, Identifiable {
    var id: String
    var text: String
    var systemImage: String
}

final class TipEngine {

    static let shared = TipEngine()

    /// The least time between two tips. Long enough that a tip is a remark,
    /// not a stream.
    var minimumInterval: TimeInterval = 45

    private let defaults: UserDefaults
    private let key = "canvia.tips.shown"
    private var lastShown: Date?
    private var now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    static let tips: [TipEvent: Tip] = [
        .firstElementAdded: Tip(id: "first", text: "Pinch anywhere to zoom — even over what you just added. Drag from empty page to select several things.",
                                systemImage: "hand.draw"),
        .textAdded: Tip(id: "text", text: "Double-tap text to edit it in place. The Curve slider bends it; Effects and gradients are in the toolbar.",
                        systemImage: "textformat"),
        .photoAdded: Tip(id: "photo", text: "Select the photo for Crop, Filters, a Frame in any shape, or Cut out to remove its background.",
                         systemImage: "photo"),
        .multiSelected: Tip(id: "multi", text: "Several selected: drag a corner to resize them together, or Group them from the menu so they stay together.",
                            systemImage: "square.on.square"),
        .manyElements: Tip(id: "many", text: "Getting busy? The Layers sheet in the menu lists everything on the page, top-most first.",
                           systemImage: "square.3.layers.3d"),
        .curvedText: Tip(id: "curve", text: "Curved text grows taller as it bends — drag its corners if the box looks tight.",
                         systemImage: "textformat.abc"),
        .rotated: Tip(id: "rotate", text: "Rotation snaps at every 45° and taps when it lands; keep turning to leave the snap. Position sets an exact angle.",
                      systemImage: "rotate.right"),
        .pageAdded: Tip(id: "page", text: "New page. Swipe the pages bar to move between pages, and use its notes button for speaker notes and this page's timing.",
                        systemImage: "doc.on.doc"),
        .drewStroke: Tip(id: "stroke", text: "Each stroke is a shape: tap the pencil again to stop drawing, then select a stroke to recolour, resize or delete it.",
                         systemImage: "pencil.tip"),
        .dropped: Tip(id: "drop", text: "Dropped in place. Pictures, text and links from other apps can be dragged straight onto the page.",
                      systemImage: "square.and.arrow.down.on.square"),
    ]

    private var shown: Set<String> {
        get { Set(defaults.stringArray(forKey: key) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: key) }
    }

    /// The tip to show for an event, or nil: already shown, none for this
    /// event, or too soon after the last one.
    func tip(for event: TipEvent) -> Tip? {
        guard let tip = Self.tips[event], !shown.contains(tip.id) else { return nil }
        if let last = lastShown, now().timeIntervalSince(last) < minimumInterval { return nil }
        shown.insert(tip.id)
        lastShown = now()
        return tip
    }

    func reset() {
        defaults.removeObject(forKey: key)
        lastShown = nil
    }
}
