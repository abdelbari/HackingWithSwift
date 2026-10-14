// The presenter's effects (Presenter.effects) as Present draws them over the
// page up: a countdown, confetti, bubbles, a call for quiet and a curtain —
// blur is the page's own, in PresentStage. Drawn by PresentStage, so the
// phone and the screen the room sees show the same, from the same seeded
// particles. With Reduce Motion on, each moving one is a still stand-in.
// Only Present draws them: they are never in a design or an export. And the
// grid a touch opens them from, the sparkle button's.

import SwiftUI

/// The effects showing, over the page fitted to `size`.
struct PresentEffectsLayer: View {
    let session: PresentSession
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = session.effects.filter { $0.id != "blur" }
        if !shown.isEmpty {
            let pageSize = session.design.size(for: session.page)
            let scale = min(size.width / max(pageSize.width, 1), size.height / max(pageSize.height, 1))
            let frame = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
            // Every frame while anything moves; twice a second for a still
            // stand-in or a countdown alone.
            TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : nil, paused: false)) { context in
                PresentEffectsFrame(shown: Presenter.live(shown, at: context.date), date: context.date,
                                    still: reduceMotion, size: frame)
            }
            .frame(width: frame.width, height: frame.height)
            .clipped()
            .position(x: size.width / 2, y: size.height / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// One frame of the effects showing at `date`, in a page of `size` points.
private struct PresentEffectsFrame: View {
    let shown: [Presenter.Shown]
    let date: Date
    let still: Bool
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(shown, id: \.id) { effect in
                layer(effect)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func layer(_ effect: Presenter.Shown) -> some View {
        let t = max(0, date.timeIntervalSince(effect.since))
        switch effect.id {
        case "confetti":
            PresentParticles(particles: Presenter.confetti, rising: false, t: still ? Presenter.stillTime : t)
        case "bubbles":
            PresentParticles(particles: Presenter.bubbles, rising: true, t: still ? Presenter.stillTime : t)
        case "quiet":
            quiet
        case "curtain":
            PresentCurtain(closed: still ? 1 : min(1, t / Presenter.curtainSeconds))
        default:
            if let minutes = Presenter.timerMinutes(effect.id) {
                countdown(Presenter.countdown(minutes: minutes, elapsed: t))
            }
        }
    }

    private var side: CGFloat { min(size.width, size.height) }

    /// "🤫" and "Quiet, please", in the middle.
    private var quiet: some View {
        VStack(spacing: side * 0.02) {
            Text("\u{1F92B}")
                .font(.system(size: side * 0.28))
            Text("Quiet, please")
                .font(.system(size: side * 0.07, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: side * 0.01)
        }
    }

    /// The time left, in a dark pill at the page's top right.
    private func countdown(_ text: String) -> some View {
        Text(text)
            .font(.system(size: side * 0.08, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, side * 0.035)
            .padding(.vertical, side * 0.015)
            .background(Capsule().fill(Color.black.opacity(0.65)))
            .padding(side * 0.04)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

/// Confetti falling, or bubbles rising, `t` seconds in.
private struct PresentParticles: View {
    let particles: [Presenter.Particle]
    let rising: Bool
    let t: Double

    var body: some View {
        Canvas { context, size in
            let side = Double(min(size.width, size.height))
            for p in particles {
                guard let at = Presenter.particlePosition(p, t: t, rising: rising) else { continue }
                let centre = CGPoint(x: at.x * Double(size.width), y: at.y * Double(size.height))
                if rising {
                    bubble(p, at: centre, side: side, in: context)
                } else {
                    piece(p, at: centre, side: side, in: context)
                }
            }
        }
    }

    private func bubble(_ p: Presenter.Particle, at centre: CGPoint, side: Double, in context: GraphicsContext) {
        let d = p.size * side * 2.5
        let ring = Path(ellipseIn: CGRect(x: Double(centre.x) - d / 2, y: Double(centre.y) - d / 2, width: d, height: d))
        context.fill(ring, with: .color(.white.opacity(0.18)))
        context.stroke(ring, with: .color(.white.opacity(0.85)), lineWidth: max(1, d * 0.06))
    }

    private func piece(_ p: Presenter.Particle, at centre: CGPoint, side: Double, in context: GraphicsContext) {
        let d = p.size * side
        var turned = context
        turned.translateBy(x: centre.x, y: centre.y)
        turned.rotate(by: .degrees(p.spin * 360 * t))
        let colour = Presenter.confettiColours[min(max(p.colour, 0), Presenter.confettiColours.count - 1)]
        turned.fill(Path(CGRect(x: -d / 2, y: -d / 4, width: d, height: d / 2)), with: .color(Color(hex: colour)))
    }
}

/// Two red curtains drawn in from the sides: `closed` 0 is open, 1 shut.
private struct PresentCurtain: View {
    let closed: Double

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2 * closed
            ZStack {
                drape
                    .frame(width: half)
                    .frame(maxWidth: .infinity, alignment: .leading)
                drape
                    .frame(width: half)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var drape: some View {
        LinearGradient(colors: [Color(hex: "#5c0a14"), Color(hex: "#a3162a"), Color(hex: "#5c0a14")],
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// The effects in a grid, each with the key that gives it: what the sparkle
/// button opens on a phone with no keyboard.
struct PresentEffectsSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Presenter.effects) { effect in tile(effect) }
                }
                .padding(16)
            }
            .background(Theme.workspace)
            .navigationTitle("Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func tile(_ effect: Presenter.Effect) -> some View {
        Button {
            dismiss()
            onPick(effect.id)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: effect.symbol)
                    .font(.title2)
                Text(effect.name)
                    .font(.footnote.weight(.semibold))
                Text(effect.key.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(effect.name)
        .accessibilityHint("Key \(effect.key.uppercased())")
    }
}
