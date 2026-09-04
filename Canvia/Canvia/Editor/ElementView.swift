// Element rendering. One view per element kind, all pure SwiftUI (no
// UIViewRepresentable) so the exact same views render on the canvas, in
// thumbnails, and through ImageRenderer for export.
//
// Text is drawn inside a SwiftUI Canvas with NSAttributedString using the
// same attributes as FontLibrary.measuredHeight — display, measurement and
// export share one text pipeline, which is what keeps wrapping consistent.

import SwiftUI
import UIKit
import CoreText
import CoreGraphics

// MARK: - dispatch

/// `element` is the only input. Everything else the subviews reach for —
/// `ContentLibrary.shape`, `PhotoLibrary.resolve`, `ImageFilterEngine.apply`
/// — resolves synchronously and deterministically from fields of that
/// element, so two `ElementView`s with equal elements render identically.
///
/// That is what makes the `Equatable` conformance below sound, and it is a
/// real constraint rather than an observation: if image resolution ever
/// becomes asynchronous, or a subview starts reading mutable state that is
/// not part of `Element`, this view would keep showing a stale render and
/// the conformance must go.
struct ElementView: View {
    let element: Element
    @Environment(\.animationTime) private var animationTime

    /// The element's entrance state at the environment's time; settled when
    /// there is no time, which is the editor at rest.
    private var motion: ElementAnimation.State {
        guard let clock = animationTime, let animation = element.animation else { return .settled }
        return animation.state(at: clock.time, text: element.text, size: max(element.w, element.h))
    }

    /// The element as drawn now: text cut to the revealed characters, a
    /// photo's crop drifted along its Ken Burns.
    private var shown: Element {
        var el = element
        if let n = motion.visibleCharacters, let text = el.text { el.text = String(text.prefix(n)) }
        if let clock = animationTime, let drift = el.kenBurns, el.type == .image {
            let crop = drift.crop(from: el, fraction: clock.hold > 0 ? clock.time / clock.hold : 0)
            el.cropScale = crop.scale; el.cropX = crop.x; el.cropY = crop.y
        }
        return el
    }

    var body: some View {
        content
            .frame(width: element.w, height: element.h)
            .scaleEffect(motion.scale)
            .offset(motion.offset)
            // Before the flip and rotation, so the shadow is cast in the
            // element's own space and turns with it — a shadow applied after
            // rotation would always fall straight down whatever the element
            // was doing, which is not how light works.
            .shadow(color: shadowColor, radius: element.shadow?.blur ?? 0,
                    x: element.shadow?.offsetX ?? 0, y: element.shadow?.offsetY ?? 0)
            .scaleEffect(x: element.flipH ? -1 : 1, y: element.flipV ? -1 : 1)
            .rotationEffect(.degrees(element.rotation))
            .opacity(element.opacity * motion.opacity)
            .blendMode(BlendModes.swiftUI(element.blendMode))
            .position(x: element.x + element.w / 2, y: element.y + element.h / 2)
    }

    /// Clear when there is no shadow: SwiftUI's shadow modifier with a clear
    /// colour draws nothing, so the modifier can stay in the chain and the
    /// view tree keeps one shape whether or not a shadow is set.
    private var shadowColor: Color {
        guard let shadow = element.shadow else { return .clear }
        return Color(hex: shadow.color).opacity(shadow.opacity)
    }

    @ViewBuilder
    private var content: some View {
        let el = shown
        switch el.type {
        case .shape: ShapeElementView(element: el)
        case .text: TextElementView(element: el)
        case .image: ImageElementView(element: el)
        case .sticker: StickerElementView(element: el)
        case .line: LineElementView(element: el)
        }
    }
}

// MARK: - shape

struct LibraryShape: Shape {
    let definition: ShapeDef
    let cornerRadius: Double
    /// Top-left, top-right, bottom-right, bottom-left; nil is cornerRadius
    /// on all four.
    var corners: [Double]? = nil

    func path(in rect: CGRect) -> Path {
        if definition.rectLike == true, let corners, corners.count == 4, corners.contains(where: { $0 > 0 }) {
            return Path(Self.roundedRect(rect, corners: corners))
        }
        if definition.rectLike == true && cornerRadius > 0 {
            let r = min(cornerRadius, rect.width / 2, rect.height / 2)
            return Path(roundedRect: rect, cornerRadius: r)
        }
        return Path(SVGPath.scaledPath(definition.path, to: rect.size))
    }

    /// A rectangle with a different radius at each corner, each clamped so
    /// neighbours never overlap.
    static func roundedRect(_ rect: CGRect, corners: [Double]) -> CGPath {
        let limit = min(rect.width, rect.height) / 2
        let r = corners.map { min(max($0, 0), limit) }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX + r[0], y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r[1], y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r[1]), radius: r[1])
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r[2]))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r[2], y: rect.maxY), radius: r[2])
        p.addLine(to: CGPoint(x: rect.minX + r[3], y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r[3]), radius: r[3])
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r[0]))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r[0], y: rect.minY), radius: r[0])
        p.closeSubpath()
        return p
    }
}

struct ShapeElementView: View {
    let element: Element

    var body: some View {
        let def = ContentLibrary.shape(for: element)
        let shape = LibraryShape(definition: def, cornerRadius: element.radius ?? 0, corners: element.corners)
        let fill = element.fill ?? .solid("#8b5cf6")
        ZStack {
            if fill.kind == "gradient", fill.stops != nil {
                shape.fill(fill.gradientStyle())
            } else if fill.kind == "pattern" || fill.kind == "image" {
                // A pattern or a photo is a view, not a ShapeStyle, so it is
                // clipped to the shape rather than poured into it.
                fill.fillView()
                    .frame(width: element.w, height: element.h)
                    .clipShape(shape)
            } else {
                shape.fill(Color(hex: fill.color ?? "#8b5cf6"))
            }
            if let stroke = element.stroke, let sw = element.strokeWidth, sw > 0 {
                shape.stroke(Color(hex: stroke), style: StrokeStyle(lineWidth: sw, lineJoin: .round))
            }
        }
    }
}

// MARK: - text

struct TextElementView: View {
    let element: Element
    @Environment(\.pageNumber) private var pageNumber

    var body: some View {
        SwiftUI.Canvas { context, size in
            context.withCGContext { cg in
                drawText(in: cg, size: size)
            }
        }
        // Never clip: effects (shadows, glow) extend past the box.
        .frame(width: element.w, height: element.h)
    }

    private func drawText(in cg: CGContext, size: CGSize) {
        var el = element
        let effect = TextEffect.from(el.effect)
        // Page tokens resolve here, where the page is known.
        if let pageNumber, let raw = el.text, raw.contains("{page") {
            el.text = raw.replacingOccurrences(of: "{page}", with: String(pageNumber.number))
                .replacingOccurrences(of: "{pages}", with: String(pageNumber.count))
        }
        let text = FontLibrary.displayText(for: el)
        guard !text.isEmpty else { return }
        if let degrees = el.curve, abs(degrees) >= TextOutliner.straightBelowDegrees {
            drawCurvedText(in: cg, size: size, effect: effect)
            return
        }
        // Fitted text is measured at the size that fills the box.
        if el.fitText == true { el.fontSize = FontLibrary.fittingFontSize(for: el) }
        var attrs = FontLibrary.attributes(for: el)
        let fontSize = el.fontSize ?? 42
        let color = UIColor(hex: el.color ?? "#1f2430")
        // Vertical alignment: the text's own height against the box's.
        let measured = FontLibrary.measuredHeight(for: el)
        let slack = max(0, size.height - measured)
        let dy: Double = el.vAlign == "middle" ? slack / 2 : el.vAlign == "bottom" ? slack : 0
        let rect = CGRect(x: 0, y: dy, width: size.width, height: size.height - dy)

        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }

        // Highlight bars behind each wrapped line.
        if effect == .highlight {
            let highlight = UIColor(hex: color.isLight ? "#1f2430" : "#ffe066")
            cg.setFillColor(highlight.cgColor)
            for line in lineFragments(text: text, attrs: attrs, width: size.width) {
                let pad = fontSize * 0.18
                cg.fill(CGRect(x: line.rect.minX - pad, y: line.rect.minY,
                               width: line.rect.width + pad * 2, height: line.rect.height))
            }
        }

        switch effect {
        case .shadow:
            cg.setShadow(offset: CGSize(width: fontSize * 0.06, height: fontSize * 0.06),
                         blur: fontSize * 0.12, color: UIColor.black.withAlphaComponent(0.55).cgColor)
        case .lift:
            cg.setShadow(offset: CGSize(width: 0, height: fontSize * 0.18),
                         blur: fontSize * 0.5, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        case .neon:
            cg.setShadow(offset: .zero, blur: fontSize * 0.35,
                         color: color.withAlphaComponent(0.85).cgColor)
        default:
            break
        }

        // A drop cap: the letter, then the rest framed around it. Only the
        // plain effect, since the letter and body are drawn as two runs.
        if effect == .none, let layout = FontLibrary.dropCapLayout(for: el) {
            drawDropCap(layout, attrs: attrs, in: cg, rect: rect, el: el)
            return
        }

        switch effect {
        case .outline:
            attrs[.strokeColor] = color
            attrs[.strokeWidth] = NSNumber(value: max(2.5, fontSize * 0.035) / fontSize * 100)
            attrs[.foregroundColor] = UIColor.clear
            NSAttributedString(string: text, attributes: attrs).draw(in: rect)
        case .splice:
            var shadowAttrs = attrs
            shadowAttrs[.foregroundColor] = color.withAlphaComponent(0.45)
            let offset = fontSize * 0.08
            NSAttributedString(string: text, attributes: shadowAttrs)
                .draw(in: rect.offsetBy(dx: offset, dy: offset))
            attrs[.strokeColor] = color
            attrs[.strokeWidth] = NSNumber(value: max(2.5, fontSize * 0.03) / fontSize * 100)
            attrs[.foregroundColor] = UIColor.clear
            NSAttributedString(string: text, attributes: attrs).draw(in: rect)
        case .glitch:
            var cyan = attrs, pink = attrs
            cyan[.foregroundColor] = UIColor(hex: "#00e5ff").withAlphaComponent(0.85)
            pink[.foregroundColor] = UIColor(hex: "#ff2d78").withAlphaComponent(0.85)
            let offset = fontSize * 0.06
            NSAttributedString(string: text, attributes: cyan).draw(in: rect.offsetBy(dx: offset, dy: 0))
            NSAttributedString(string: text, attributes: pink).draw(in: rect.offsetBy(dx: -offset, dy: 0))
            NSAttributedString(string: text, attributes: attrs).draw(in: rect)
        case .neon:
            // Multiple passes deepen the glow.
            let str = NSAttributedString(string: text, attributes: attrs)
            str.draw(in: rect)
            str.draw(in: rect)
        default:
            NSAttributedString(string: text, attributes: attrs).draw(in: rect)
        }

        // A gradient fill is painted through the letters after the fact: the
        // solid text above has already cast whatever shadow or glow the
        // effect asked for, and this replaces its face. Not for the effects
        // that draw the letters as strokes or doubles — a gradient across
        // an outline is a smear.
        if let fill = el.textFill, fill.kind == "gradient",
           [.none, .shadow, .lift, .neon, .highlight].contains(effect) {
            let renderer = UIGraphicsImageRenderer(size: size)
            var maskAttrs = attrs
            maskAttrs[.foregroundColor] = UIColor.black
            let mask = renderer.image { _ in
                NSAttributedString(string: text, attributes: maskAttrs).draw(in: rect)
            }
            guard let cgMask = mask.cgImage else { return }
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            // The context is in UIKit orientation; a CGImage mask is not.
            // Flip about the box so the letters land where they were drawn,
            // and paint the gradient in the same flipped space.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.clip(to: rect, mask: cgMask)
            Self.paintGradient(fill, in: cg, rect: rect, flipped: true)
            cg.restoreGState()
        }
    }

    /// The cap at the top-left, the body in a CoreText frame whose path is
    /// the box minus the cap's corner — so lines wrap beside the letter and
    /// run full width once past it.
    private func drawDropCap(_ layout: FontLibrary.DropCapLayout, attrs: [NSAttributedString.Key: Any],
                             in cg: CGContext, rect: CGRect, el: Element) {
        var capAttrs = attrs
        var capEl = el
        capEl.fontSize = layout.capFontSize
        capEl.lineHeight = 1
        capAttrs[.font] = FontLibrary.uiFont(family: el.fontFamily, size: layout.capFontSize,
                                             weight: el.fontWeight ?? 400, italic: el.italic ?? false)
        capAttrs[.paragraphStyle] = nil
        let cap = NSAttributedString(string: layout.letter, attributes: capAttrs)
        let capSize = cap.size()
        // Sit the cap's baseline on the third line's baseline.
        let line = (el.fontSize ?? 42) * (el.lineHeight ?? 1.25)
        let capTop = rect.minY + line * FontLibrary.dropCapLines - capSize.height
        cap.draw(at: CGPoint(x: rect.minX, y: capTop))

        guard !layout.rest.isEmpty else { return }
        let body = NSAttributedString(string: layout.rest, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        // CoreText frames in a y-up space: build the path in the flipped
        // frame and draw with the context flipped to match.
        let frame = CGMutablePath()
        let full = CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height)
        frame.addRect(full)
        let notch = CGRect(x: rect.minX, y: rect.height - layout.capRect.height,
                           width: layout.capRect.width, height: layout.capRect.height)
        frame.addRect(notch)
        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), frame,
                                               [kCTFramePathFillRuleAttributeName: CTFramePathFillRule.evenOdd.rawValue] as CFDictionary)
        cg.saveGState()
        cg.textMatrix = .identity
        cg.translateBy(x: 0, y: rect.minY + rect.height)
        cg.scaleBy(x: 1, y: -1)
        CTFrameDraw(ctFrame, cg)
        cg.restoreGState()
    }

    /// Fill `rect` with the paint's gradient: linear along its CSS angle, or
    /// radial from the centre. Angular has no CoreGraphics equivalent and
    /// paints as linear here. With `flipped`, the context's y runs upward
    /// and the endpoints are mirrored so "0° is up" still means up on screen.
    static func paintGradient(_ paint: Paint, in cg: CGContext, rect: CGRect, flipped: Bool) {
        guard let stops = paint.stops, !stops.isEmpty else { return }
        let colors = stops.map { UIColor(hex: $0.color).cgColor } as CFArray
        let locations = stops.map { CGFloat($0.offset) }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: locations) else { return }
        if paint.gradientKind == "radial" {
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                  endRadius: max(rect.width, rect.height) / 2,
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            return
        }
        let pts = paint.unitPoints
        func point(_ u: UnitPoint) -> CGPoint {
            let y = flipped ? 1 - u.y : u.y
            return CGPoint(x: rect.minX + rect.width * u.x, y: rect.minY + rect.height * y)
        }
        cg.drawLinearGradient(gradient, start: point(pts.start), end: point(pts.end),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Curved text is drawn from its outlines rather than by NSAttributedString,
    /// because there is no attributed-string way to bend a baseline. The
    /// effects that survive that are the ones a filled path can carry — the
    /// shadows and the glow; outline and splice become a stroke on the same
    /// path, and glitch becomes two offset fills.
    private func drawCurvedText(in cg: CGContext, size: CGSize, effect: TextEffect) {
        var el = element
        el.w = size.width
        el.h = size.height
        guard let path = TextOutliner.path(for: el) else { return }
        let fontSize = el.fontSize ?? 42
        let color = UIColor(hex: el.color ?? "#1f2430")

        switch effect {
        case .shadow:
            cg.setShadow(offset: CGSize(width: fontSize * 0.06, height: fontSize * 0.06),
                         blur: fontSize * 0.12, color: UIColor.black.withAlphaComponent(0.55).cgColor)
        case .lift:
            cg.setShadow(offset: CGSize(width: 0, height: fontSize * 0.18),
                         blur: fontSize * 0.5, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        case .neon:
            cg.setShadow(offset: .zero, blur: fontSize * 0.35,
                         color: color.withAlphaComponent(0.85).cgColor)
        default:
            break
        }

        switch effect {
        case .outline, .splice:
            cg.addPath(path)
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(max(2.5, fontSize * 0.035))
            cg.setLineJoin(.round)
            cg.strokePath()
        case .glitch:
            for (dx, tint) in [(fontSize * 0.06, "#00e5ff"), (-fontSize * 0.06, "#ff2d78")] {
                cg.saveGState()
                cg.translateBy(x: dx, y: 0)
                cg.addPath(path)
                cg.setFillColor(UIColor(hex: tint).withAlphaComponent(0.85).cgColor)
                cg.fillPath()
                cg.restoreGState()
            }
            cg.addPath(path)
            cg.setFillColor(color.cgColor)
            cg.fillPath()
        default:
            cg.addPath(path)
            cg.setFillColor(color.cgColor)
            cg.fillPath()
            // The outline is a path, so the gradient clips to it directly —
            // no mask, no flip; the path is already in this context's space.
            if let fill = el.textFill, fill.kind == "gradient" {
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                cg.addPath(path)
                cg.clip()
                Self.paintGradient(fill, in: cg, rect: CGRect(origin: .zero, size: size), flipped: false)
                cg.restoreGState()
            }
        }
    }

    private struct LineFragment {
        var rect: CGRect
    }

    /// Wrapped line rectangles via CoreText, for the highlight effect.
    private func lineFragments(text: String, attrs: [NSAttributedString.Key: Any],
                               width: Double) -> [LineFragment] {
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return [] }
        let lineHeight = (element.fontSize ?? 42) * (element.lineHeight ?? 1.25)
        var fragments: [LineFragment] = []
        for (i, line) in lines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            guard lineWidth > 0.5 else { continue }
            let topY = Double(i) * lineHeight
            let alignedX: Double
            switch element.align ?? "center" {
            case "left": alignedX = 0
            case "right": alignedX = width - lineWidth
            default: alignedX = (width - lineWidth) / 2
            }
            fragments.append(LineFragment(rect: CGRect(
                x: alignedX, y: topY, width: lineWidth, height: lineHeight)))
        }
        return fragments
    }

}

// MARK: - image

struct ImageElementView: View {
    let element: Element

    var body: some View {
        GeometryReader { _ in
            if let ui = resolvedImage() {
                let frameW = element.w, frameH = element.h
                // Fill covers the frame and crops; fit shows the whole picture
                // and leaves the frame's remainder empty.
                let fit = element.cropFit == true
                let scale = fit
                    ? min(frameW / ui.size.width, frameH / ui.size.height)
                    : max(frameW / ui.size.width, frameH / ui.size.height)
                let dispW = ui.size.width * scale
                let dispH = ui.size.height * scale
                let cropX = element.cropX ?? 0.5
                let cropY = element.cropY ?? 0.5
                // object-position math: the focus fraction of the image
                // aligns with the same fraction of the frame.
                let offsetX = (dispW - frameW) * (0.5 - cropX)
                let offsetY = (dispH - frameH) * (0.5 - cropY)
                let tilt = element.straighten ?? 0
                // Levelling turns the picture inside the frame; in fill mode
                // it also grows so the frame's corners stay covered.
                let cover = fit ? 1 : Geometry.coverScale(width: frameW, height: frameH, degrees: tilt)
                Image(uiImage: ui)
                    .resizable()
                    .frame(width: dispW, height: dispH)
                    .rotationEffect(.degrees(tilt))
                    .position(x: frameW / 2 + offsetX, y: frameH / 2 + offsetY)
                    .scaleEffect((element.cropScale ?? 1) * cover,
                                 anchor: UnitPoint(x: cropX, y: cropY))
            } else {
                Color(hex: "#e3e6ea")
                    .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary))
            }
        }
        .frame(width: element.w, height: element.h)
        // Inside ImageElementView, not ElementView: the clip has to happen in
        // the element's own space, before the rotate/flip/position stack, or
        // the frame becomes a screen-space cookie cutter the photo slides
        // around underneath.
        .clipShape(frame)
        .overlay {
            if let stroke = element.stroke, let sw = element.strokeWidth, sw > 0 {
                // The same shape as the clip. A rounded rectangle here would
                // draw a rectangular border floating around a star-framed
                // photo.
                frame.stroke(Color(hex: stroke), lineWidth: sw)
            }
        }
    }

    private var frame: FrameShape {
        FrameShape(definition: element.maskShapeId.flatMap { ContentLibrary.shapeMap[$0] },
                   cornerRadius: element.radius ?? 0)
    }

    private func resolvedImage() -> UIImage? {
        guard let base = PhotoLibrary.resolve(element.src) else { return nil }
        let preset = ImageFilterPreset.from(element.filter)
        return ImageFilterEngine.apply(preset, adjustments: element.adjustments ?? .neutral,
                                       duotone: element.duotone,
                                       to: base, cacheKey: element.src ?? "")
    }
}

// MARK: - sticker

struct StickerElementView: View {
    let element: Element

    var body: some View {
        Text(element.glyph ?? "⭐")
            .font(.system(size: min(element.w, element.h) * 0.86))
            .minimumScaleFactor(0.2)
            .frame(width: element.w, height: element.h)
    }
}

// MARK: - line

struct LineElementView: View {
    let element: Element

    var body: some View {
        SwiftUI.Canvas { context, size in
            let el = element
            let t = el.thickness ?? 4
            let y = size.height / 2
            let color = Color(hex: el.color ?? "#1f2430")
            let capSize = max(t * 3, 10)
            var x1 = 0.0, x2 = size.width
            if el.startCap == "arrow" { x1 += capSize * 0.9 }
            if el.endCap == "arrow" { x2 -= capSize * 0.9 }

            var line = Path()
            line.move(to: CGPoint(x: x1, y: y))
            line.addLine(to: CGPoint(x: x2, y: y))
            var style = StrokeStyle(lineWidth: t, lineCap: .round)
            if el.dash == "dashed" { style.dash = [t * 3, t * 2] }
            if el.dash == "dotted" { style.dash = [0.01, t * 2.2] }
            context.stroke(line, with: .color(color), style: style)

            func cap(atStart: Bool, kind: String?) {
                guard let kind, kind != "none" else { return }
                if kind == "arrow" {
                    let tip = atStart ? 0.0 : size.width
                    let dir = atStart ? 1.0 : -1.0
                    var p = Path()
                    p.move(to: CGPoint(x: tip, y: y))
                    p.addLine(to: CGPoint(x: tip + dir * capSize, y: y - capSize * 0.6))
                    p.addLine(to: CGPoint(x: tip + dir * capSize, y: y + capSize * 0.6))
                    p.closeSubpath()
                    context.fill(p, with: .color(color))
                } else if kind == "dot" {
                    let cx = atStart ? t : size.width - t
                    let r = max(t * 1.4, 5)
                    context.fill(Path(ellipseIn: CGRect(x: cx - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(color))
                }
            }
            cap(atStart: true, kind: el.startCap)
            cap(atStart: false, kind: el.endCap)
        }
        .frame(width: element.w, height: element.h)
    }
}

extension ElementView: Equatable {
    static func == (lhs: ElementView, rhs: ElementView) -> Bool {
        lhs.element == rhs.element
    }
}

// MARK: - full page (canvas layer, thumbnails, export)

struct PageRenderView: View {
    let design: Design
    let page: Page

    var body: some View {
        ZStack {
            backgroundView
            // The master page's elements, behind this page's own. Not on
            // the master itself, and not on a page that opted out.
            ForEach(design.masterElements(behind: page)) { el in
                ElementView(element: el).equatable()
            }
            ForEach(page.elements) { el in
                // .equatable() so a drag re-renders the element that moved
                // rather than every element on the page. The store is
                // @Observable and a gesture mutates the document each frame,
                // so without this every text run re-lays out through CoreText
                // and every shape re-parses its path, on every frame, however
                // little actually changed.
                ElementView(element: el).equatable()
            }
        }
        .frame(width: design.width, height: design.height)
        .clipped()
        .environment(\.pageNumber, pageNumberValue)
    }

    private var pageNumberValue: (number: Int, count: Int)? {
        guard let index = design.pages.firstIndex(where: { $0.id == page.id }) else { return nil }
        return (index + 1, design.pages.count)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch page.background {
        case .color(let hex):
            Color(hex: hex)
        case .gradient(let paint):
            paint.fillView()
        case .image(let src):
            if let ui = PhotoLibrary.resolve(src) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: design.width, height: design.height)
                    .clipped()
            } else {
                Color.white
            }
        }
    }
}
