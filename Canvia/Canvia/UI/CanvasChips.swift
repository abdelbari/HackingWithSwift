// Two small answers floating over the canvas, as the Android twin has them,
// and, while Copy style's paint mode is on, a chip that says so.
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
    /// Scroll through pages, from the More menu: the canvas is the column
    /// of every page.
    @AppStorage(PageColumn.key) private var pageScroll = true

    var body: some View {
        VStack(spacing: 8) {
            answers
            if store.stylePainting {
                paintChip.transition(.opacity)
            }
        }
        .padding(12)
        .animation(.easeOut(duration: 0.2), value: offscreenSelection != nil)
        .animation(.easeOut(duration: 0.2), value: store.stylePainting)
    }

    /// Bring it back, and the zoom pill.
    private var answers: some View {
        ZStack(alignment: .top) {
            if let box = offscreenSelection {
                chip(tr("Bring it back")) { store.requestCanvas(.reveal(box)) }
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
    }

    // MARK: paint mode

    /// "Tap something to paste the style", and Done, which ends paint mode.
    private var paintChip: some View {
        HStack(spacing: 12) {
            Image(systemName: "paintbrush.pointed.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(StylePaint.chip)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button("Done") { store.stylePainting = false }
                .font(.subheadline.weight(.bold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.thickMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
        .accessibilityElement(children: .contain)
    }

    // MARK: zoom

    /// Not while a drag's readout is up, nor where a pinch works something
    /// other than the canvas, nor with the pen or the eraser out.
    private var showsZoom: Bool {
        store.viewport.width > 0 && store.badge == nil && store.cropping == nil && store.graphicCropping == nil
            && store.drawing == nil && store.erasing == nil && store.brushing == nil
    }

    /// At the fitting zoom, within 2%, with the whole page in sight: pan a
    /// fitted page half off the screen and it is no longer "Fit". Scrolling
    /// through pages, the page's whole width: one taller than the canvas is
    /// scrolled through, never fitted any further — as on the Android twin.
    private var atFit: Bool {
        let fit = store.fitZoom
        guard abs(store.zoom - fit) <= 0.02 * fit else { return false }
        let slack = 0.5 / max(store.zoom, 0.01)
        let seen = store.viewport.insetBy(dx: -slack, dy: -slack)
        if pageScroll { return seen.minX <= 0 && seen.maxX >= store.pageWidth }
        return seen.contains(CGRect(x: 0, y: 0, width: store.pageWidth, height: store.pageHeight))
    }

    /// Where a tap at fit goes: actual size, or twice it when fitting is
    /// already actual size, so the tap always changes something.
    private var secondZoom: Double {
        abs(store.fitZoom - 1) <= 0.02 ? 2 : 1
    }

    private var percent: Int { Int((store.zoom * 100).rounded()) }

    private var zoomLabel: String { atFit ? tr("Fit") : "\(percent)%" }

    private var zoomDescription: String {
        guard atFit else { return tr("Zoomed to %d percent. Tap to fit the whole page.", percent) }
        let second = Int((secondZoom * 100).rounded())
        return second == 100 ? tr("Whole page. Tap for actual size.")
            : tr("Whole page. Tap to zoom to %d percent.", second)
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
