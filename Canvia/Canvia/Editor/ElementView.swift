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

struct ElementView: View {
    let element: Element

    var body: some View {
        content
            .frame(width: element.w, height: element.h)
            .scaleEffect(x: element.flipH ? -1 : 1, y: element.flipV ? -1 : 1)
            .rotationEffect(.degrees(element.rotation))
            .opacity(element.opacity)
            .position(x: element.x + element.w / 2, y: element.y + element.h / 2)
    }

    @ViewBuilder
    private var content: some View {
        switch element.type {
        case .shape: ShapeElementView(element: element)
        case .text: TextElementView(element: element)
        case .image: ImageElementView(element: element)
        case .sticker: StickerElementView(element: element)
        case .line: LineElementView(element: element)
        }
    }
}

// MARK: - shape

struct LibraryShape: Shape {
    let definition: ShapeDef
    let cornerRadius: Double

    func path(in rect: CGRect) -> Path {
        if definition.rectLike == true && cornerRadius > 0 {
            let r = min(cornerRadius, rect.width / 2, rect.height / 2)
            return Path(roundedRect: rect, cornerRadius: r)
        }
        return Path(SVGPath.scaledPath(definition.path, to: rect.size))
    }
}

struct ShapeElementView: View {
    let element: Element

    var body: some View {
        let def = ContentLibrary.shape(element.shapeId)
        let shape = LibraryShape(definition: def, cornerRadius: element.radius ?? 0)
        let fill = element.fill ?? .solid("#8b5cf6")
        ZStack {
            if fill.kind == "gradient", let stops = fill.stops {
                let pts = fill.unitPoints
                shape.fill(LinearGradient(
                    stops: stops.map { .init(color: Color(hex: $0.color), location: $0.offset) },
                    startPoint: pts.start, endPoint: pts.end))
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
        let el = element
        let effect = TextEffect.from(el.effect)
        let text = FontLibrary.displayText(for: el)
        guard !text.isEmpty else { return }
        var attrs = FontLibrary.attributes(for: el)
        let fontSize = el.fontSize ?? 42
        let color = UIColor(hex: el.color ?? "#1f2430")
        let rect = CGRect(origin: .zero, size: size)

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
                let scale = max(frameW / ui.size.width, frameH / ui.size.height)
                let dispW = ui.size.width * scale
                let dispH = ui.size.height * scale
                let cropX = element.cropX ?? 0.5
                let cropY = element.cropY ?? 0.5
                // object-position math: the focus fraction of the image
                // aligns with the same fraction of the frame.
                let offsetX = (dispW - frameW) * (0.5 - cropX)
                let offsetY = (dispH - frameH) * (0.5 - cropY)
                Image(uiImage: ui)
                    .resizable()
                    .frame(width: dispW, height: dispH)
                    .position(x: frameW / 2 + offsetX, y: frameH / 2 + offsetY)
                    .scaleEffect(element.cropScale ?? 1,
                                 anchor: UnitPoint(x: cropX, y: cropY))
            } else {
                Color(hex: "#e3e6ea")
                    .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary))
            }
        }
        .frame(width: element.w, height: element.h)
        .clipShape(RoundedRectangle(cornerRadius: element.radius ?? 0))
        .overlay {
            if let stroke = element.stroke, let sw = element.strokeWidth, sw > 0 {
                RoundedRectangle(cornerRadius: element.radius ?? 0)
                    .stroke(Color(hex: stroke), lineWidth: sw)
            }
        }
    }

    private func resolvedImage() -> UIImage? {
        guard let base = PhotoLibrary.resolve(element.src) else { return nil }
        let preset = ImageFilterPreset.from(element.filter)
        return ImageFilterEngine.apply(preset, to: base, cacheKey: element.src ?? "")
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

// MARK: - full page (canvas layer, thumbnails, export)

struct PageRenderView: View {
    let design: Design
    let page: Page

    var body: some View {
        ZStack {
            backgroundView
            ForEach(page.elements) { el in
                ElementView(element: el)
            }
        }
        .frame(width: design.width, height: design.height)
        .clipped()
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
