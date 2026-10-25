// The platform safe zone on the canvas (SafeZones): what the platform's
// profile row, caption, buttons and progress bar cover, as a translucent
// hatched band with the platform's name in a small label at its top. Drawn
// over the page by the canvas only, beside the bleed band — never in an
// export, Present, a thumbnail or a video — and nothing in it takes a touch
// or is read by VoiceOver.

import SwiftUI

struct SafeZoneLayer: View {
    let zone: SafeZones.Zone
    let size: CGSize
    /// One point on screen, in page units, so the hatching and the label
    /// stay the same size on glass whatever the zoom.
    let unit: Double

    var body: some View {
        let parts = SafeZones.covered(zone, size: size)
        return Canvas { context, _ in
            var covered = Path()
            for rect in parts { covered.addRect(rect) }
            context.fill(covered, with: .color(Color.black.opacity(0.14)))
            // Diagonal strokes over what is covered, every 12 points.
            context.clip(to: covered)
            let step = 12 * unit
            var hatch = Path()
            var x = -Double(size.height)
            while x < Double(size.width) {
                hatch.move(to: CGPoint(x: x, y: Double(size.height)))
                hatch.addLine(to: CGPoint(x: x + Double(size.height), y: 0))
                x += step
            }
            context.stroke(hatch, with: .color(Color.white.opacity(0.35)), lineWidth: 1 * unit)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) { label }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// "TikTok", just inside the top band's left corner.
    private var label: some View {
        Text(verbatim: zone.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.55), in: Capsule())
            .scaleEffect(unit, anchor: .topLeading)
            .offset(x: 8 * unit, y: 8 * unit)
    }
}
