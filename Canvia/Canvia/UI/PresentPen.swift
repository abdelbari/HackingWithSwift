// Present's pen and what VoiceOver finds on the slide: the ink drawn over
// the page up (PresentInk) on the phone, the console's page and the screen
// the room sees alike; the Pen button and its bar — three colours, three
// widths, Clear and Fade ink; and the slide's stops for VoiceOver
// (PresentSpeech), each over the part of the page it reads. None of it is
// ever saved to the design or drawn in an export.

import SwiftUI

/// The ink on the page up, in a page of `page` size, drawn in the page's own
/// units under the page's scale; nothing without strokes. While a lifted
/// stroke is fading it redraws every frame.
struct PresentInkLayer: View {
    let ink: PresentInk.Ink
    let page: CGSize
    @AppStorage(PresentInk.fadePref) private var fade = true

    var body: some View {
        if !ink.strokes.isEmpty {
            TimelineView(.animation(minimumInterval: nil, paused: !ink.fading(fade))) { context in
                PresentInkCanvas(ink: ink, now: context.date.timeIntervalSinceReferenceDate, fade: fade, page: page)
            }
            .frame(width: page.width, height: page.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The strokes at `now`, each smoothed as a drawn line is in the editor
/// (Freehand.cgPath) and as solid as PresentInk.alpha says; a tap, one
/// point, is a dot.
private struct PresentInkCanvas: View {
    let ink: PresentInk.Ink
    let now: Double
    let fade: Bool
    let page: CGSize

    var body: some View {
        Canvas { context, _ in
            for stroke in ink.strokes {
                let alpha = PresentInk.alpha(stroke, now: now, fade: fade)
                guard alpha > 0, let first = stroke.points.first else { continue }
                let colour = Color(hex: PresentInk.color(stroke)).opacity(alpha)
                let width = CGFloat(PresentInk.width(stroke, page: page))
                if stroke.points.count == 1 {
                    let dot = CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width)
                    context.fill(Path(ellipseIn: dot), with: .color(colour))
                } else {
                    let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                    context.stroke(Path(Freehand.cgPath(stroke.points)), with: .color(colour), style: style)
                }
            }
        }
    }
}

/// Present's Pen, beside the magic shortcuts: on, a finger on the slide
/// draws rather than turning the page.
struct PresentPenButton: View {
    let session: PresentSession

    var body: some View {
        Button { session.penOn.toggle() } label: {
            Image(systemName: "pencil.tip.crop.circle")
                .symbolVariant(session.penOn ? .fill : .none)
                .padding(10)
        }
        .accessibilityLabel("Pen")
        .accessibilityValue(session.penOn ? tr("On") : tr("Off"))
    }
}

/// The pen's row while it is on: its three colours and three widths, Clear,
/// which wipes the ink, and Fade ink, each labelled for VoiceOver.
struct PresentPenBar: View {
    let session: PresentSession
    @AppStorage(PresentInk.fadePref) private var fade = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(PresentInk.colors.indices, id: \.self) { n in colourButton(n) }
                ForEach(PresentInk.widths.indices, id: \.self) { n in widthButton(n) }
                Button("Clear") { session.ink = PresentInk.Ink() }
                    .padding(.horizontal, 8)
                Toggle("Fade ink", isOn: $fade)
                    .fixedSize()
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 8)
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.35))
    }

    private func colourButton(_ n: Int) -> some View {
        let chosen = session.penColor == n
        return Button { session.penColor = n } label: {
            Circle()
                .fill(Color(hex: PresentInk.colors[n]))
                .overlay(Circle().stroke(Color.white.opacity(chosen ? 1 : 0.5), lineWidth: chosen ? 3 : 1))
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(PresentInk.colorNames[n])
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func widthButton(_ n: Int) -> some View {
        let chosen = session.penWidth == n
        return Button { session.penWidth = n } label: {
            Circle()
                .fill(Color.white.opacity(chosen ? 1 : 0.5))
                .frame(width: CGFloat(6 + 6 * n), height: CGFloat(6 + 6 * n))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(PresentInk.widthNames[n])
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The slide up as VoiceOver finds it: a stop for each of
/// PresentSpeech.items, in its order, each over the part of the page it
/// reads in a view of `size` that fits the page in its middle. A heading is
/// a header; a link says so and opens with a double tap, as a tap on it
/// does. Nothing here is drawn or takes a touch.
struct PresentSlideReader: View {
    let design: Design
    let page: Page
    let size: CGSize
    let follow: (String) -> Void

    var body: some View {
        let items = PresentSpeech.items(page, in: design)
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { n, item in
                stop(item, priority: Double(items.count - n))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }

    private func stop(_ item: PresentSpeech.Stop, priority: Double) -> some View {
        let rect = frame(of: item)
        return Color.clear
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .accessibilityElement()
            .accessibilityLabel(item.label)
            .accessibilityAddTraits(Self.traits(item.kind))
            .accessibilityAction {
                if let url = item.url { follow(url) }
            }
            .accessibilitySortPriority(priority)
            .position(x: rect.midX, y: rect.midY)
    }

    /// What VoiceOver calls a stop of `kind`.
    static func traits(_ kind: String) -> AccessibilityTraits {
        switch kind {
        case PresentSpeech.heading: return .isHeader
        case PresentSpeech.image, PresentSpeech.chart: return .isImage
        case PresentSpeech.link: return .isLink
        default: return []
        }
    }

    /// Where `item` lies on the screen: round everything it is read from —
    /// all a chart's parts for a chart — the page fitted as Present fits it.
    private func frame(of item: PresentSpeech.Stop) -> CGRect {
        let pageSize = design.size(for: page)
        let scale = min(size.width / max(pageSize.width, 1), size.height / max(pageSize.height, 1))
        let dx = (size.width - pageSize.width * scale) / 2
        let dy = (size.height - pageSize.height * scale) / 2
        let parts = page.elements.filter { $0.id == item.id || ($0.chart?.id == item.id && $0.chartPart != nil) }
        guard let first = parts.first else { return .zero }
        let bounds = parts.dropFirst().reduce(Geometry.aabb(first)) { $0.union(Geometry.aabb($1)) }
        return CGRect(x: dx + bounds.minX * scale, y: dy + bounds.minY * scale,
                      width: bounds.width * scale, height: bounds.height * scale)
    }
}
