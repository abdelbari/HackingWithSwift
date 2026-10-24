// Zoom to selection: the view framing what is selected, from the zoom
// pill's menu, Command-2, the quick actions' magnifier on something small,
// or a double tap on it (Viewport.zoomToBox). The view only — nothing is
// written to the design — and Fit takes it back, as on the Android twin.

import SwiftUI

extension DesignStore {

    /// Whether what is selected is small on screen (Viewport.isSmall): the
    /// quick actions offer the magnifier, and a double tap on it frames it.
    var selectionIsSmallOnScreen: Bool {
        guard let box = selectionBox else { return false }
        return Viewport.isSmall(box, zoom: zoom)
    }

    /// The zoom framing the selection would come to, as the canvas works it
    /// out with the screen it has: the part of the page on screen at the
    /// zoom it is, fit and the canvas's furthest zoom.
    var selectionFrameZoom: Double? {
        guard let box = selectionBox, viewport.width > 0, viewport.height > 0 else { return nil }
        let screen = CGSize(width: viewport.width * zoom, height: viewport.height * zoom)
        return Viewport.zoomToBox(box, viewport: screen, fit: fitZoom,
                                  maxZoom: Geometry.zoomRange(fit: fitZoom).upperBound).zoom
    }

    /// The view brought to the selection, and said: "Zoomed to selection,
    /// 250 percent". Nothing, with nothing selected.
    func zoomToSelection() {
        guard let box = selectionBox else { return }
        requestCanvas(.frame(box))
        guard let wanted = selectionFrameZoom else { return }
        AccessibilityNotification.Announcement(Self.zoomedToSelectionNote(wanted)).post()
    }

    /// What VoiceOver says as the view frames the selection.
    static func zoomedToSelectionNote(_ zoom: Double) -> String {
        tr("Zoomed to selection, %d percent", Int((zoom * 100).rounded()))
    }
}
