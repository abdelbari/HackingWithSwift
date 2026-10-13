// The print bleed on the canvas (Bleed): a band of the design's bleed round
// the page, through which the page's background runs and into which things
// may be put, with a light tint over it and a dashed trim line at the page's
// edge. Drawn round the page by the canvas only — Present, thumbnails and
// every plain export draw the trim, as before — and nothing in it takes a
// touch or is read by VoiceOver.

import SwiftUI

struct BleedBand: View {
    let design: Design
    let page: Page
    /// The bleed, in page units.
    let bleed: Double
    /// One point on screen, in page units, so the band's lines and label
    /// stay the same size on glass whatever the zoom.
    let unit: Double
    /// Whether the "Bleed" label shows: for the band's first few seconds.
    var labelled = false

    var body: some View {
        let size = design.size(for: page)
        let whole = CGSize(width: size.width + 2 * bleed, height: size.height + 2 * bleed)
        return ZStack {
            // The page and its bleed together cast the page's shadow.
            Rectangle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.16), radius: 12 * unit, y: 3 * unit)
            // What runs out past the trim, faded by half: the page itself
            // is drawn over the trim, whole.
            PageRenderView(design: design, page: page, bleed: bleed)
                .opacity(0.5)
            tint(size: size, whole: whole)
        }
        .frame(width: whole.width, height: whole.height)
        .overlay(alignment: .topLeading) {
            if labelled { label }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The light tint over the band, outside the trim.
    private func tint(size: CGSize, whole: CGSize) -> some View {
        let trim = CGRect(x: bleed, y: bleed, width: size.width, height: size.height)
        return Canvas { context, _ in
            var band = Path(CGRect(origin: .zero, size: whole))
            band.addRect(trim)
            context.fill(band, with: .color(Theme.accent.opacity(0.08)), style: FillStyle(eoFill: true))
        }
    }

    /// "Bleed", just above the band's top left corner.
    private var label: some View {
        Text("Bleed")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accent, in: Capsule())
            .scaleEffect(unit, anchor: .bottomLeading)
            .alignmentGuide(.top) { $0[.bottom] + CGFloat(4 * unit) }
            .transition(.opacity)
    }
}

/// The page's trim — its edge, where a print shop cuts — dashed, black on
/// white so it shows over any colour. Drawn over the page while a bleed is
/// shown.
struct TrimLine: View {
    let size: CGSize
    /// One point on screen, in page units.
    let unit: Double

    var body: some View {
        Rectangle()
            .stroke(Color.white, lineWidth: unit)
            .overlay(
                Rectangle()
                    .stroke(Color.black.opacity(0.75), style: StrokeStyle(lineWidth: unit, dash: [4 * unit, 3 * unit]))
            )
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
