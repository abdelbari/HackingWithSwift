// Two small answers floating over the canvas, as the Android twin has them.
//
// The zoom pill says how far in you are — "Fit", or a percentage — and one
// tap goes between the whole page and actual size, which a pinch can only
// approximate. "Bring it back" appears when the selection has been scrolled
// clean out of sight: it is still selected, the toolbar still acts on it,
// and without a word about where it went the next edit lands on something
// you cannot see.
//
// In a view of their own so that only they redraw as the canvas scrolls;
// they read the viewport on every frame of a pan.

import SwiftUI

struct CanvasChips: View {
    @Bindable var store: DesignStore

    var body: some View {
        ZStack(alignment: .top) {
            if let box = offscreenSelection {
                chip("Bring it back") { store.requestCanvas(.reveal(box)) }
                    .accessibilityLabel("The selected thing is off screen")
                    .accessibilityHint("Brings it back into view")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if showsZoom {
                chip(zoomLabel) {
                    store.requestCanvas(atFit ? .zoom(secondZoom) : .fit)
                }
                .accessibilityLabel(zoomDescription)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .animation(.easeOut(duration: 0.2), value: offscreenSelection != nil)
    }

    // MARK: zoom

    /// Not while a drag's readout is up, nor where a pinch works something
    /// other than the canvas, nor with the pen or the eraser out.
    private var showsZoom: Bool {
        store.viewport.width > 0 && store.badge == nil && store.cropping == nil
            && store.drawing == nil && store.erasing == nil
    }

    /// At the fitting zoom, within 2%, with the whole page in sight: pan a
    /// fitted page half off the screen and it is no longer "Fit".
    private var atFit: Bool {
        let fit = store.fitZoom
        guard abs(store.zoom - fit) <= 0.02 * fit else { return false }
        let slack = 0.5 / max(store.zoom, 0.01)
        let page = CGRect(x: 0, y: 0, width: store.pageWidth, height: store.pageHeight)
        return store.viewport.insetBy(dx: -slack, dy: -slack).contains(page)
    }

    /// Where a tap at fit goes: actual size, or twice it when fitting is
    /// already actual size, so the tap always changes something.
    private var secondZoom: Double {
        abs(store.fitZoom - 1) <= 0.02 ? 2 : 1
    }

    private var percent: Int { Int((store.zoom * 100).rounded()) }

    private var zoomLabel: String { atFit ? "Fit" : "\(percent)%" }

    private var zoomDescription: String {
        guard atFit else { return "Zoomed to \(percent) percent. Tap to fit the whole page." }
        let second = Int((secondZoom * 100).rounded())
        return second == 100 ? "Whole page. Tap for actual size." : "Whole page. Tap to zoom to \(second) percent."
    }

    // MARK: selection

    /// The selection's box when every bit of it is out of sight; nil when
    /// any of it shows, or nothing is selected.
    private var offscreenSelection: CGRect? {
        guard store.viewport.width > 0, let box = store.selectionBox, !box.intersects(store.viewport) else { return nil }
        return box
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.thickMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}
