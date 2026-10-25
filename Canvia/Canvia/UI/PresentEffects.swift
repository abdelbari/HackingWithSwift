// The presenter's effects (Presenter.effects) as Present draws them over the
// page up: a countdown, confetti, bubbles, a call for quiet, a curtain, a
// drumroll's spotlight and a mic drop — blur is the page's own, in
// PresentStage. Drawn by PresentStage, so the
// phone and the screen the room sees show the same, from the same seeded
// particles. With Reduce Motion on, each moving one is a still stand-in.
// Only Present draws them: they are never in a design or an export. And the
// grid a touch opens them from, the sparkle button's.

import SwiftUI

/// The effects showing, over the page fitted to `size`.
struct PresentEffectsLayer: View {
    let session: PresentSession
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    /// Settings ▸ Accessibility's Reduce motion, over the phone's own
    /// (AccessibilityPrefs).
    @AppStorage(AccessibilityPrefs.reduceMotionKey) private var reduceMotionChoice = AccessibilityPrefs.system
    private var reduceMotion: Bool {
        AccessibilityPrefs.reducesMotion(reduceMotionChoice, systemReduces: systemReducesMotion)
    }

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
        case "confetti", "bubbles":
            PresentParticles(id: effect.id, t: still ? Presenter.stillTime : t)
        case "quiet":
            quiet
        case "curtain":
            PresentCurtain(closed: still ? 1 : min(1, t / Presenter.curtainSeconds))
        case "drumroll":
            // With animations off, the sound alone and its glyph, still.
            if still { glyph(Self.drum) } else { PresentSpotlight(light: Presenter.spotlight(t)) }
        case "micdrop":
            if still { glyph(Self.mic) } else { PresentMicDrop(drop: Presenter.micDrop(t), t: t) }
        default:
            if let minutes = Presenter.timerMinutes(effect.id) {
                countdown(Presenter.countdown(minutes: minutes, elapsed: t))
            }
        }
    }

    private var side: CGFloat { min(size.width, size.height) }

    /// "🤫", large in the middle, as the Android twin draws it.
    private var quiet: some View {
        Text("\u{1F92B}")
            .font(.system(size: side * 0.35))
    }

    /// The drumroll's and the mic drop's glyphs, as the Android twin's.
    static let drum = "\u{1F941}"
    static let mic = "\u{1F3A4}"

    /// A glyph, still in the middle: the drumroll and the mic drop under
    /// Reduce Motion.
    private func glyph(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: side * 0.3))
    }

    /// The time left, in a dark pill low on the page, in the middle — where
    /// the Android twin puts it.
    private func countdown(_ text: String) -> some View {
        Text(text)
            .font(.system(size: side * 0.12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, side * 0.04)
            .padding(.vertical, side * 0.02)
            .background(RoundedRectangle(cornerRadius: side * 0.04).fill(Color.black.opacity(170.0 / 255)))
            .padding(.bottom, side * 0.06)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// Confetti falling, or bubbles rising, `t` seconds in, where
/// Presenter.particles puts them: a piece of confetti a strip its size
/// across and twice that down, turned; a bubble a ring of its size, its
/// colour faint inside — as the Android twin draws them.
private struct PresentParticles: View {
    let id: String
    let t: Double

    var body: some View {
        Canvas { context, size in
            let side = Double(min(size.width, size.height))
            for p in Presenter.particles(id, t: t) {
                let centre = CGPoint(x: p.x * Double(size.width), y: p.y * Double(size.height))
                let colour = Color(hex: Presenter.effectColours[p.colour % Presenter.effectColours.count])
                let r = p.size * side
                if id == "bubbles" {
                    bubble(at: centre, radius: r, colour: colour, in: context)
                } else {
                    piece(at: centre, radius: r, turn: p.turn, colour: colour, in: context)
                }
            }
        }
    }

    private func bubble(at centre: CGPoint, radius r: Double, colour: Color, in context: GraphicsContext) {
        let ring = Path(ellipseIn: CGRect(x: Double(centre.x) - r, y: Double(centre.y) - r, width: 2 * r, height: 2 * r))
        context.fill(ring, with: .color(colour.opacity(70.0 / 255)))
        context.stroke(ring, with: .color(colour.opacity(200.0 / 255)), lineWidth: r * 0.12)
    }

    private func piece(at centre: CGPoint, radius r: Double, turn: Double, colour: Color, in context: GraphicsContext) {
        var turned = context
        turned.translateBy(x: centre.x, y: centre.y)
        turned.rotate(by: .degrees(turn))
        turned.fill(Path(CGRect(x: -r / 2, y: -r, width: r, height: 2 * r)), with: .color(colour))
    }
}

/// The drumroll's spotlight (Presenter.spotlight): the slide's edges dimmed
/// round a circle that closes in with the roll and opens at the crash, its
/// edge soft over the last fifth of its radius — as the Android twin draws
/// it.
private struct PresentSpotlight: View {
    let light: Presenter.Spotlight

    var body: some View {
        Canvas { context, size in
            let side = Double(min(size.width, size.height))
            let centre = CGPoint(x: light.x * Double(size.width), y: light.y * Double(size.height))
            let dark = Color.black.opacity(light.dim)
            let gradient = Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.8),
                .init(color: dark, location: 1),
            ])
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(gradient, center: centre, startRadius: 0,
                                               endRadius: max(light.radius * side, 1)))
        }
    }
}

/// The mic drop (Presenter.micDrop): the microphone falling from the top,
/// bouncing where it lands, the dust it raises and the slide going to
/// black — as the Android twin draws it.
private struct PresentMicDrop: View {
    let drop: Presenter.MicDrop
    let t: Double

    var body: some View {
        Canvas { context, size in
            let side = Double(min(size.width, size.height))
            var turned = context
            turned.translateBy(x: size.width / 2, y: drop.y * Double(size.height))
            turned.rotate(by: .degrees(drop.turn))
            let mic = turned.resolve(Text(verbatim: PresentEffectsFrame.mic).font(.system(size: Presenter.micSize * side)))
            turned.draw(mic, at: .zero)
            // The dust settles as it falls.
            let settle = min(max((t - Presenter.micLands) / 0.6, 0), 1)
            let dust = Color(white: 200.0 / 255).opacity(200.0 / 255 * (1 - settle))
            for p in drop.dust {
                let r = p.size * side
                let at = CGRect(x: p.x * Double(size.width) - r, y: p.y * Double(size.height) - r, width: 2 * r, height: 2 * r)
                context.fill(Path(ellipseIn: at), with: .color(dust))
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(drop.black)))
        }
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
            .navigationTitle("Magic shortcuts")
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
