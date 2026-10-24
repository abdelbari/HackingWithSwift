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
///
/// The one exception is a clip played live, which shows whatever frame has
/// been decoded so far (`VideoStore.peek`), at a moment timed by the
/// clip's length once the live path has read it. ImageElementView reads the
/// store's frame version itself, so it is that view, not this one, that
/// SwiftUI draws again when a frame lands, and this view's equality still
/// holds. So does a photo whose focus keeps its subject sharp, on screen:
/// it reads the engine's count of subjects found
/// (`ImageFilterEngine.subjectsFound`) and is drawn again when its subject
/// is found; and a photo with clarity or pixelate, whose look is made off
/// the main thread (`ImageFilterEngine.looksBaked`).
struct ElementView: View {
    let element: Element
    @Environment(\.animationTime) private var animationTime
    @Environment(\.exitTime) private var exitTime
    @Environment(\.pageNumber) private var pageNumber
    @Environment(\.liveVideo) private var liveVideo
    @Environment(\.clipsPlay) private var clipsPlay
    @Environment(\.pausedClips) private var pausedClips
    @Environment(\.playsPictures) private var playsPictures
    @Environment(\.captionTime) private var captionTime
    @Environment(\.captionsPlay) private var captionsPlay
    @Environment(\.onScreen) private var onScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The element with "{page}" and "{pages}" filled in, where the page is
    /// known: what a reveal counts and cuts, so the words that appear are the
    /// words that stay — as the Android twin reveals them. A caption box
    /// shows the cue at the page's moment while it plays; at rest, the cue
    /// at the timeline's playhead — the first cue while it stands before it
    /// — or its first (Captions.shown).
    private var resolved: Element {
        var el = element
        if el.captions != nil {
            el = Captions.shown(el, at: animationTime?.time ?? captionTime, still: animationTime == nil && !captionsPlay)
        }
        guard let pageNumber, el.text?.contains("{page") == true else { return el }
        el.fillPageTokens(number: pageNumber.number, count: pageNumber.count)
        return el
    }

    /// The element's entrance and exit state at the environment's time, and
    /// nothing outside its timing; settled when there is no time, which is
    /// the editor at rest.
    private var motion: ElementAnimation.State {
        guard let clock = animationTime else { return .settled }
        // A reveal counts the characters as they read, style marks left out.
        // Exits are played by their own clock where Present holds them back.
        // Reduce Motion: words on screen are shown whole and stay, never
        // cut, rising or moving a unit at a time — their text-kind entrance
        // and exit left out, as the Android twin shows them.
        let reduced = reduceMotion && onScreen
        var state = Timeline.motion(of: reduced ? Timeline.withoutTextKinds(element) : element,
                                    time: clock.time, hold: clock.hold, exitTime: exitTime,
                                    text: resolved.text.map(RichText.strip))
        if reduced {
            state.visibleCharacters = nil
            state.unitClock = nil
        }
        return state
    }

    /// The element as drawn now: text cut to the revealed characters, a
    /// photo's crop drifted along its Ken Burns.
    private var shown: Element {
        var el = resolved
        let motion = self.motion
        // A chart's slice or ring sweeping round as it grows.
        let sweep = motion.sweep
        if sweep < 1 { el = DataGraphics.swept(el, share: sweep) }
        if let n = motion.visibleCharacters, let text = el.text {
            // Fitted type stays at the size the whole text fits at, rather than
            // filling the box with the first letter and shrinking as the rest
            // arrive; and the words shown keep their style marks round them,
            // so none is ever drawn — as the Android twin reveals them.
            if el.fitText == true {
                el.fontSize = FontLibrary.fittingFontSize(for: resolved)
                el.fitText = nil
            }
            el.setText(RichText.revealed(text, count: n))
        }
        if let clock = animationTime, let drift = el.kenBurns, el.type == .image {
            let crop = drift.crop(from: el, fraction: clock.hold > 0 ? clock.time / clock.hold : 0)
            el.cropScale = crop.scale; el.cropX = crop.x; el.cropY = crop.y
        }
        // A photo's motion: its picture enlarged and slid inside its frame.
        if el.type == .image && (motion.cropZoom != 1 || motion.cropX != nil) {
            el.cropScale = (el.cropScale ?? 1) * motion.cropZoom
            if let x = motion.cropX { el.cropX = x }
        }
        // A clip shows the frame its trim, speed and loop put at this moment
        // while the page plays, timed by the length already known when it
        // plays live and by the length read there and then in a video; and
        // at rest, the frame at its start.
        if let src = el.src, let parts = VideoStore.split(src), parts.time == nil {
            let clip = el.clip ?? ClipPlayback()
            if let clock = animationTime, !pausedClips.contains(el.id) {
                let length = liveVideo ? VideoStore.knownLength(parts.id) : VideoStore.duration(of: parts.id)
                el.src = VideoStore.src(parts.id, at: VideoStore.clipTime(clock.time, clip: clip, duration: length))
            } else {
                el.src = VideoStore.atRest(el)
            }
        }
        // An animated picture shows the frame the page's moment falls on
        // while the page plays, looping; at rest, its first.
        if let clock = animationTime, AnimStore.isAnim(el.src) {
            el.src = AnimStore.playing(el.src, at: clock.time)
        }
        // A generated loop likewise, round and round (MotionLibrary).
        if let clock = animationTime, MotionLibrary.isMotion(el.src) {
            el.src = MotionLibrary.playing(el.src, at: clock.time)
        }
        return el
    }

    /// `el` as it shows at `date` on a picture's own clock, which goes
    /// round from the start of the hour.
    private static func playing(_ el: Element, at date: Date) -> Element {
        var out = el
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
        out.src = MotionLibrary.isMotion(el.src) ? MotionLibrary.playing(el.src, at: time) : AnimStore.playing(el.src, at: time)
        return out
    }

    /// The motion as drawn: a drawing on of anything but a shape's outline
    /// shows it from its left, as a reveal does.
    private var drawnMotion: ElementAnimation.State {
        var state = motion
        if state.draw < 1 && element.type != .shape {
            state.reveal *= state.draw
            state.draw = 1
        }
        return state
    }

    var body: some View {
        let motion = drawnMotion
        return content(drawing: motion.draw)
            .frame(width: element.w, height: element.h)
            // A cropped graphic shows only its crop (GraphicClip), cut in
            // its own box before it is flipped and turned.
            .modifier(GraphicClipMask(rect: GraphicClip.ownRect(element)))
            // A styled shadow (ShadowShapes) is a silhouette of its own,
            // drawn behind the element in the element's space, where the
            // drop shadow below is cast too.
            .background { styledShadow }
            // A chart's part growing from its anchor, or a line drawn on
            // from its left, in the element's own turned space.
            .modifier(GrowReveal(state: motion, w: element.w, h: element.h, reach: (element.strokeWidth ?? 0) + 1))
            .scaleEffect(motion.scale)
            .offset(motion.offset)
            // Type rising from its baseline is seen only within its box.
            .modifier(RestingClip(on: motion.clipped, w: element.w, h: element.h))
            // Before the flip and rotation, so the shadow is cast in the
            // element's own space and turns with it — a shadow applied after
            // rotation would always fall straight down whatever the element
            // was doing, which is not how light works.
            .shadow(color: shadowColor, radius: element.shadow?.blur ?? 0,
                    x: element.shadow?.offsetX ?? 0, y: element.shadow?.offsetY ?? 0)
            .scaleEffect(x: element.flipH ? -1 : 1, y: element.flipV ? -1 : 1)
            .rotationEffect(.degrees(element.rotation + motion.rotation))
            .opacity(motion.showsNothing ? 0 : element.opacity * motion.opacity)
            .blendMode(BlendModes.swiftUI(element.blendMode))
            .position(x: element.x + element.w / 2, y: element.y + element.h / 2)
            // Left to right in any language, drawn alone for an export too.
            .designDirection()
    }

    /// Clear when there is no shadow: SwiftUI's shadow modifier with a clear
    /// colour draws nothing, so the modifier can stay in the chain and the
    /// view tree keeps one shape whether or not a shadow is set. Clear for
    /// a styled shadow too, which `styledShadow` draws.
    private var shadowColor: Color {
        guard let shadow = ShadowShapes.cast(element), !ShadowShapes.isStyled(shadow) else { return .clear }
        return Color(hex: shadow.color).opacity(shadow.opacity)
    }

    /// A curved, page lift, angle or backdrop shadow (ShadowShapes), blurred
    /// and offset as the drop shadow is. The angle style shears the
    /// element's own alpha silhouette through its projective transform —
    /// the element drawn again in the shadow's colour through its mask —
    /// as the Android twin shears the drawn pixels; the others fill their
    /// path. Text casts the drop shadow whatever its style (ShadowShapes.cast).
    @ViewBuilder
    private var styledShadow: some View {
        if let shadow = ShadowShapes.cast(element), ShadowShapes.isStyled(shadow) {
            if ShadowShapes.style(of: shadow) == "angle" {
                angleShadow(shadow)
            } else {
                ShadowSilhouette(shadow: shadow, w: element.w, h: element.h)
            }
        }
    }

    @ViewBuilder
    private func angleShadow(_ shadow: Shadow) -> some View {
        if let cast = ShadowShapes.angle(w: element.w, h: element.h, angle: ShadowShapes.angle(shadow),
                                         distance: ShadowShapes.distance(shadow)) {
            Rectangle()
                .fill(Color(hex: shadow.color).opacity(shadow.opacity))
                .frame(width: element.w, height: element.h)
                .mask { content().frame(width: element.w, height: element.h) }
                .blur(radius: ShadowShapes.blur(of: shadow))
                .projectionEffect(ShadowSilhouette.projection(cast.matrix))
                .offset(x: shadow.offsetX, y: shadow.offsetY)
        }
    }

    /// What the element draws; a shape drawing itself on shows `drawing` of
    /// its outline.
    @ViewBuilder
    private func content(drawing: Double = 1) -> some View {
        let el = shown
        switch el.type {
        case .shape:
            if drawing < 1 {
                DrawingOn(element: el, share: drawing)
            } else {
                ShapeElementView(element: el)
            }
        case .text: TextElementView(element: el, units: motion.unitClock)
        case .image:
            if playsPictures && animationTime == nil && (AnimStore.isAnim(el.src) || MotionLibrary.isMotion(el.src)) {
                // Play in the editor: the picture on a clock of its own, going
                // round for as long as it is on the canvas.
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    ImageElementView(element: Self.playing(el, at: context.date))
                }
            } else {
                // Whether the page's clock runs, read here once so a photo
                // is not drawn again on every tick of it — not for a scrub,
                // whose time stands still between drags.
                ImageElementView(element: el, clipPlays: clipsPlay && animationTime != nil && !pausedClips.contains(el.id))
            }
        case .sticker: StickerElementView(element: el)
        case .line: LineElementView(element: el)
        }
    }
}

/// A cropped graphic cut to its crop (GraphicClip.ownRect), in the
/// element's own box; nothing at all for no crop.
private struct GraphicClipMask: ViewModifier {
    let rect: CGRect?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let rect {
            content.clipShape(ClipWindow(window: rect))
        } else {
            content
        }
    }
}

/// The crop's box, where it is in the element's box whatever size the
/// element is laid out at.
private struct ClipWindow: Shape {
    let window: CGRect

    func path(in rect: CGRect) -> Path {
        Path(window)
    }
}

/// Seen only within the element's resting box, `w` by `h`, while `on`: a
/// line of type rising from its baseline. No effect at all otherwise.
private struct RestingClip: ViewModifier {
    let on: Bool
    let w: Double
    let h: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content.frame(width: w, height: h).clipped()
        } else {
            content
        }
    }
}

/// A shape drawing itself on (ElementAnimation's draw), `share` of the way:
/// its outline's subpaths in turn, each for its share of their whole length
/// (ElementAnimation.drawn), traced along with trimmedPath in its border's
/// colour — or its fill's, with no border; its fill, if it has one, fading
/// in as it goes. As the Android twin measures and draws it.
struct DrawingOn: View {
    let element: Element
    let share: Double

    var body: some View {
        Canvas { context, size in
            guard share > 0 else { return }
            let shape = LibraryShape(definition: ContentLibrary.shape(for: element), cornerRadius: element.radius ?? 0,
                                     corners: element.corners)
            let outline = shape.path(in: CGRect(origin: .zero, size: size))
            let fill = element.fill
            if let fill, fill.kind == "solid" || fill.kind == "gradient" {
                context.fill(outline, with: .color(Color(hex: fill.primaryColor).opacity(share)),
                             style: FillStyle(eoFill: element.fillRule == "evenodd"))
            }
            let stroked = element.stroke != nil && (element.strokeWidth ?? 0) > 0
            let ink = Color(hex: (stroked ? element.stroke : fill?.primaryColor) ?? "#222222")
            let style = StrokeStyle(lineWidth: stroked ? element.strokeWidth ?? 2 : 2, lineCap: .round, lineJoin: .round)
            let parts = SVGPath.subpaths(outline.cgPath)
            let lengths = parts.map { SVGPath.subpathLengths(of: $0).reduce(0, +) }
            let shares = ElementAnimation.drawn(lengths, p: share)
            for (part, f) in zip(parts, shares) where f > 0 {
                context.stroke(Path(part).trimmedPath(from: 0, to: CGFloat(f)), with: .color(ink), style: style)
            }
        }
        .frame(width: element.w, height: element.h)
    }
}

/// A chart part as it grows in (ElementAnimation.growState): scaled about
/// its anchor, and a line or area cut to the share of its box drawn on so
/// far from the left — its stroke's reach beyond the box kept, as the
/// Android twin's renderer clips it. Nothing is masked once it is in, and
/// an element at rest is drawn as it was before charts grew: no effect at
/// all, so a page's export and its cut at the edge are what they were.
private struct GrowReveal: ViewModifier {
    let state: ElementAnimation.State
    let w: Double
    let h: Double
    let reach: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if state.scaleX == 1 && state.scaleY == 1 && state.reveal >= 1 {
            content
        } else if state.reveal < 1 {
            content
                .scaleEffect(x: state.scaleX, y: state.scaleY, anchor: UnitPoint(x: state.anchorX, y: state.anchorY))
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: max(0, w * state.reveal + reach), height: 3 * h + 2 * reach)
                        .offset(x: -reach, y: -h - reach)
                }
        } else {
            content
                .scaleEffect(x: state.scaleX, y: state.scaleY, anchor: UnitPoint(x: state.anchorX, y: state.anchorY))
        }
    }
}

/// A styled shadow's silhouette (ShadowShapes.path) filled in its colour,
/// blurred and offset, in a view the element's size: behind the element
/// on the canvas and behind the Shadow sheet's cards. The angle style's
/// silhouette here is its box's corners through the transform — right for
/// a card, and what the SVG writes.
struct ShadowSilhouette: View {
    let shadow: Shadow
    let w: Double
    let h: Double

    var body: some View {
        if let path = ShadowShapes.path(for: shadow, w: w, h: h) {
            Path(path)
                .fill(Color(hex: shadow.color).opacity(shadow.opacity))
                .frame(width: w, height: h)
                .blur(radius: ShadowShapes.blur(of: shadow))
                .offset(x: shadow.offsetX, y: shadow.offsetY)
        }
    }

    /// A homography's nine entries (ShadowShapes.homography) as SwiftUI's
    /// projection, which multiplies a row vector: x' = (m11 x + m21 y +
    /// m31) / (m13 x + m23 y + m33).
    static func projection(_ m: [Double]) -> ProjectionTransform {
        var t = ProjectionTransform()
        t.m11 = CGFloat(m[0]); t.m21 = CGFloat(m[1]); t.m31 = CGFloat(m[2])
        t.m12 = CGFloat(m[3]); t.m22 = CGFloat(m[4]); t.m32 = CGFloat(m[5])
        t.m13 = CGFloat(m[6]); t.m23 = CGFloat(m[7]); t.m33 = CGFloat(m[8])
        return t
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
            return Path(roundedRect: rect, cornerRadius: r, style: .circular)
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
        // Where its outline crosses itself or nests — a ring, a letter's
        // hole in an imported graphic — even-odd leaves the inside empty.
        let rule = FillStyle(eoFill: element.fillRule == "evenodd")
        ZStack {
            if fill.kind == "gradient", fill.stops != nil {
                shape.fill(fill.gradientStyle(), style: rule)
            } else if fill.kind == "pattern" || fill.kind == "image" {
                // A pattern or a photo is a view, not a ShapeStyle, so it is
                // clipped to the shape rather than poured into it.
                fill.fillView()
                    .frame(width: element.w, height: element.h)
                    .clipShape(shape, style: rule)
            } else if fill.kind == "none" {
                // An outline only — a drawn stroke, or a shape whose fill
                // was cleared. The transparent rectangle keeps the frame.
                Color.clear
            } else {
                shape.fill(Color(hex: fill.color ?? "#8b5cf6"), style: rule)
            }
            if let stroke = element.stroke, let sw = element.strokeWidth, sw > 0 {
                if Freehand.isMarker(element) {
                    MarkerInk(element: element, shape: shape, ink: stroke, width: sw)
                } else {
                    shape.stroke(Color(hex: stroke), style: .border(element.dash, width: sw))
                }
            }
            // Its words, over the fill and the border, set in its text-safe
            // box as a text box sets them. Turned back where the shape is
            // flipped, so they read the right way round wherever it points.
            if ShapeText.words(of: element) != nil {
                let box = ShapeText.box(for: element)
                TextElementView(element: ShapeText.textElement(for: element))
                    .scaleEffect(x: element.flipH ? -1 : 1, y: element.flipV ? -1 : 1)
                    .position(x: box.midX, y: box.midY)
            }
        }
    }
}

/// A marker's stroke: round at its ends, in pieces each twice its width
/// along it, each a little thinner or not by its share of the stroke's
/// texture (Freehand.markerAlphas, seeded from its own path, so it is the
/// same every time it is drawn) — laid over the last in a layer of their
/// own, each replacing what is under it, so the round ends where they meet
/// do not darken. The Android twin draws it the same way.
struct MarkerInk: View {
    let element: Element
    let shape: LibraryShape
    let ink: String
    let width: Double

    var body: some View {
        Canvas { context, size in
            let colour = Color(hex: ink)
            let line = shape.path(in: CGRect(origin: .zero, size: size))
            let count = Freehand.markerPieceCount(length: Freehand.markerLength(element, size: size), width: width)
            let alphas = Freehand.markerAlphas(count: count, seed: Freehand.markerSeed(element.pathData ?? ""))
            let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            context.drawLayer { layer in
                layer.blendMode = .copy
                for i in 0..<count {
                    let piece = line.trimmedPath(from: CGFloat(i) / CGFloat(count), to: CGFloat(i + 1) / CGFloat(count))
                    layer.stroke(piece, with: .color(colour.opacity(alphas[i])), style: style)
                }
            }
        }
        .frame(width: element.w, height: element.h)
    }
}

extension StrokeStyle {
    /// A shape's or a photo's border `width` wide: solid, dashed or dotted
    /// as BorderDash measures it, its joins round.
    static func border(_ dash: String?, width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: BorderDash.roundCaps(dash) ? .round : .butt, lineJoin: .round,
                    dash: (BorderDash.intervals(dash, width: width) ?? []).map { CGFloat($0) },
                    dashPhase: BorderDash.phase(dash, width: width))
    }
}

// MARK: - text

struct TextElementView: View {
    let element: Element
    /// Text moving a unit at a time (ElementAnimation.unitKinds): the move
    /// and its moment; nil draws the words whole.
    var units: ElementAnimation.UnitClock? = nil
    @Environment(\.pageNumber) private var pageNumber

    var body: some View {
        SwiftUI.Canvas { context, size in
            context.withCGContext { cg in
                if let units {
                    drawUnits(units, in: cg, size: size)
                } else {
                    drawText(in: cg, size: size)
                }
            }
        }
        // Never clip: effects (shadows, glow) extend past the box.
        .frame(width: element.w, height: element.h)
    }

    private func drawText(in cg: CGContext, size: CGSize) {
        var el = element
        let effect = TextEffect.from(el.effect)
        // Page tokens resolve here, where the page is known.
        if let pageNumber {
            el.fillPageTokens(number: pageNumber.number, count: pageNumber.count)
        }
        // Letters full of a photo draw in its average colour wherever the
        // effect needs a solid ink — Neon's glow, Hollow's stroke, Splice's
        // copies — and the picture over them where it shows (takesPhoto).
        if let fill = el.textFill, fill.isPhoto, let src = fill.src, let average = PhotoPalette.averageColour(src) {
            el.color = average
        }
        let text = FontLibrary.displayText(for: el)
        guard !text.isEmpty else { return }
        if TextOutliner.followsAPath(el) {
            // The page's numbers filled in, as on a straight line.
            drawCurvedText(el, in: cg, size: size, effect: effect)
            return
        }
        // Fitted text is measured at the size that fills the box.
        if el.fitText == true { el.fontSize = FontLibrary.fittingFontSize(for: el) }
        let attrs = FontLibrary.attributes(for: el)
        let fontSize = el.fontSize ?? 42
        let color = UIColor(hex: el.color ?? "#1f2430")
        let fx = TextEffect.resolve(el.effect, fontSize: fontSize, ink: el.color ?? "#1f2430")
        // Vertical alignment: the text's own height against the box's.
        let measured = FontLibrary.measuredHeight(for: el)
        let slack = max(0, size.height - measured)
        let dy: Double = el.vAlign == "middle" ? slack / 2 : el.vAlign == "bottom" ? slack : 0
        let rect = CGRect(x: 0, y: dy, width: size.width, height: size.height - dy)

        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }

        // Highlight bars behind each wrapped line.
        if effect == .highlight {
            cg.setFillColor(UIColor(hex: fx.color).withAlphaComponent(fx.alpha).cgColor)
            // At the size the words are drawn (fitted type is not its stored
            // size) and where they start in the box (vertically aligned text
            // is not at the top).
            for line in lineFragments(el, width: size.width,
                                      pitch: fontSize * (el.lineHeight ?? 1.25), top: rect.minY) {
                let bar = CGRect(x: line.rect.minX - fx.pad, y: line.rect.minY,
                                 width: line.rect.width + fx.pad * 2, height: line.rect.height)
                // CoreGraphics refuses a corner wider than half the bar.
                let radius = min(fx.radius(barHeight: bar.height), bar.width / 2, bar.height / 2)
                if radius > 0 {
                    cg.addPath(CGPath(roundedRect: bar, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    cg.fillPath()
                } else {
                    cg.fill(bar)
                }
            }
        }

        // Marks behind chosen words, over the bars and under the letters
        // and whatever their effect casts.
        TextHighlights.draw(TextHighlights.rects(for: el, width: size.width, top: rect.minY), in: cg)

        if fx.casts { Self.castShadow(fx, in: cg) }

        // A drop cap: the letter, then the rest framed around it. Only the
        // plain effect, since the letter and body are drawn as two runs.
        if effect == .none, let layout = FontLibrary.dropCapLayout(for: el) {
            drawDropCap(layout, attrs: attrs, in: cg, rect: rect, el: el)
            return
        }

        // Every effect starts from the words as drawn, inline bold, italic,
        // underline and strike included, and lays its own colour or stroke
        // over every run — so a **bold** word stays bold in outline, splice,
        // echo and glitch, as the Android twin draws them from one layout.
        // Words in a colour of their own keep it through the effects: the
        // hollow letters are stroked in it, and Auto copies follow it.
        let styled = FontLibrary.attributedString(for: el)
        let whole = NSRange(location: 0, length: styled.length)
        func over(_ extra: [NSAttributedString.Key: Any]) -> NSAttributedString {
            let copy = NSMutableAttributedString(attributedString: styled)
            copy.addAttributes(extra, range: whole)
            return copy
        }
        /// The letters, each in its own colour turned `alpha` see-through.
        func faded(_ alpha: Double) -> NSAttributedString {
            let copy = NSMutableAttributedString(attributedString: styled)
            styled.enumerateAttribute(.foregroundColor, in: whole) { value, part, _ in
                let ink = value as? UIColor ?? color
                copy.addAttribute(.foregroundColor, value: ink.withAlphaComponent(alpha), range: part)
            }
            return copy
        }
        // Splice's and echo's copies follow the letters' colour unless they
        // have one of their own.
        let copiesFollow = (effect == .splice || effect == .echo) && el.effect?.color == nil
        // The copies splice, glitch and echo lay behind the letters.
        for copy in fx.copies {
            let drawn = copiesFollow ? faded(copy.alpha)
                : over([.foregroundColor: UIColor(hex: copy.color).withAlphaComponent(copy.alpha)])
            drawn.draw(in: rect.offsetBy(dx: copy.dx, dy: copy.dy))
        }
        switch effect {
        case .outline, .splice:
            let hollow = NSMutableAttributedString(attributedString: styled)
            styled.enumerateAttribute(.foregroundColor, in: whole) { value, part, _ in
                hollow.addAttribute(.strokeColor, value: value as? UIColor ?? color, range: part)
            }
            hollow.addAttributes([.strokeWidth: NSNumber(value: fx.stroke / fontSize * 100),
                                  .foregroundColor: UIColor.clear], range: whole)
            hollow.draw(in: rect)
        case .outlined:
            // The stroke first and the letters over it, so they keep their
            // full width. Every run at the same width, a larger word's too,
            // as the Android twin's paint strokes them: CoreText takes the
            // width as a share of each run's own size.
            if fx.stroke > 0 {
                let ring = NSMutableAttributedString(attributedString: styled)
                styled.enumerateAttribute(.font, in: whole) { value, part, _ in
                    let size = Double((value as? UIFont)?.pointSize ?? CGFloat(fontSize))
                    ring.addAttribute(.strokeWidth, value: NSNumber(value: fx.stroke / max(size, 1) * 100), range: part)
                }
                ring.addAttributes([.strokeColor: UIColor(hex: fx.color),
                                    .foregroundColor: UIColor.clear], range: whole)
                ring.draw(in: rect)
            }
            styled.draw(in: rect)
        case .neon:
            // Multiple passes deepen the glow.
            styled.draw(in: rect)
            styled.draw(in: rect)
        default:
            styled.draw(in: rect)
        }

        // A gradient fill is painted through the letters after the fact: the
        // solid text above has already cast whatever shadow or glow the
        // effect asked for, and this replaces its face. Not for the effects
        // that draw the letters as strokes or doubles — a gradient across
        // an outline is a smear. Outline's letters are filled, so they take
        // it, the stroke round them left as it is.
        let photo = Self.pouredPhoto(el, effect: effect)
        if let fill = el.textFill, fill.kind == "gradient" && effect.takesGradient || photo != nil {
            let renderer = UIGraphicsImageRenderer(size: size)
            // The letters as drawn, bold runs and all, so the gradient
            // lands on exactly the glyphs above.
            let mask = renderer.image { _ in
                over([.foregroundColor: UIColor.black]).draw(in: rect)
            }
            guard let cgMask = mask.cgImage else { return }
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            // The context is in UIKit orientation; a CGImage mask is not.
            // Flip about the box so the letters land where they were drawn,
            // and paint the gradient in the same flipped space.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            // The mask was rendered over the whole box, so it clips over the
            // whole box — into `rect` it was squashed when the text sat lower.
            // The gradient spans the text's part of the box, which in this
            // flipped space runs from the bottom up to where the words start.
            cg.clip(to: CGRect(origin: .zero, size: size), mask: cgMask)
            if let photo {
                // The picture where the window puts it over the whole box,
                // drawn back in the box's own orientation.
                cg.scaleBy(x: 1, y: -1)
                cg.translateBy(x: 0, y: -size.height)
                Self.drawPhoto(photo, in: PhotoFills.window(photo, box: size, paint: fill), into: cg)
            } else {
                Self.paintGradient(fill, in: cg,
                                   rect: CGRect(x: 0, y: 0, width: size.width, height: size.height - rect.minY),
                                   flipped: true)
            }
            cg.restoreGState()
        }
    }

    // MARK: a unit at a time

    /// The words moving a unit at a time: each letter, word or line of the
    /// words as they read (ElementAnimation.units over RichText.strip, at
    /// the box's own size, as unitFrames counts them) clipped out of the
    /// whole drawing — spans, lists and effects as they are — and drawn at
    /// its frame's place, scale, turn, opacity, blur and share shown; what
    /// belongs to no unit (a list's markers, a drop cap's letter) drawn as
    /// it stands. Words not set in lines (a curve, a path, a column, a
    /// warp) fade as one, as far in as their units are on average — as the
    /// Android twin draws them.
    private func drawUnits(_ clock: ElementAnimation.UnitClock, in cg: CGContext, size: CGSize) {
        var el = element
        if let pageNumber { el.fillPageTokens(number: pageNumber.number, count: pageNumber.count) }
        let units = ElementAnimation.units(RichText.strip(el.text ?? ""), by: clock.animation.unit)
        let frames = clock.animation.frames(units, at: clock.time, size: el.fontSize ?? 42)
        // Every unit in place: the words whole, as they stand.
        guard !frames.isEmpty, !frames.allSatisfy(clock.animation.atRest) else {
            drawText(in: cg, size: size)
            return
        }
        guard !TextOutliner.followsAPath(el) else {
            drawFaded(frames, in: cg, size: size)
            return
        }
        if el.fitText == true { el.fontSize = FontLibrary.fittingFontSize(for: el) }
        let slack = max(0, Double(size.height) - FontLibrary.measuredHeight(for: el))
        let top: Double = el.vAlign == "middle" ? slack / 2 : el.vAlign == "bottom" ? slack : 0
        guard let placed = unitLines(el, units: units, width: Double(size.width), top: top, height: Double(size.height)) else {
            drawFaded(frames, in: cg, size: size)
            return
        }
        let boxes: [[CGRect]] = placed.ranges.map { unit in
            placed.lines.compactMap { line -> CGRect? in
                let from = max(unit.location, line.start), to = min(NSMaxRange(unit), line.end)
                guard to > from else { return nil }
                let left = line.x(from), right = line.x(to)
                return CGRect(x: left, y: line.top, width: right - left, height: line.bottom - line.top)
            }
        }
        // Everything outside the moving units — units at rest too — once,
        // as it stands.
        cg.saveGState()
        let rest = CGMutablePath()
        rest.addRect(CGRect(origin: .zero, size: size).insetBy(dx: -size.width, dy: -size.height))
        for (frame, rects) in zip(frames, boxes) where !clock.animation.atRest(frame) {
            for rect in rects { rest.addRect(rect) }
        }
        cg.addPath(rest)
        cg.clip(using: .evenOdd)
        drawText(in: cg, size: size)
        cg.restoreGState()
        let ink = UIColor(hex: el.color ?? "#1f2430")
        for (frame, rects) in zip(frames, boxes) where !rects.isEmpty && !clock.animation.atRest(frame) {
            drawUnit(frame, rects: rects, clock: clock, ink: ink, in: cg, size: size)
        }
    }

    /// The whole words at the average of their units' opacity, none drawn
    /// while every unit is hidden.
    private func drawFaded(_ frames: [ElementAnimation.UnitFrame], in cg: CGContext, size: CGSize) {
        let alpha = frames.map(\.alpha).reduce(0, +) / Double(max(frames.count, 1))
        guard alpha > 0 else { return }
        cg.saveGState()
        cg.setAlpha(alpha)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        drawText(in: cg, size: size)
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    /// The lines `el`'s words are drawn in, and each unit (plain offsets)
    /// moved onto them: past a list's markers, and past a drop cap's letter
    /// onto the body framed beside it. Nil where the units cannot be found.
    private func unitLines(_ el: Element, units: [NSRange], width: Double, top: Double,
                           height: Double) -> (lines: [TextHighlights.LineBox], ranges: [NSRange])? {
        let shown = FontLibrary.displayRanges(units, for: el)
        guard TextEffect.from(el.effect) == .none, let layout = FontLibrary.dropCapLayout(for: el) else {
            let lines = TextHighlights.lines(FontLibrary.attributedString(for: el), el: el, width: width, top: top)
            return (lines, shown)
        }
        let drawn = FontLibrary.attributedString(for: el).string as NSString
        guard drawn.hasPrefix(layout.letter) else { return nil }
        var cut = (layout.letter as NSString).length
        while cut < drawn.length, drawn.character(at: cut) == 32 { cut += 1 }
        let body = FontLibrary.dropCapText(for: el, layout).body
        let rect = CGRect(x: 0, y: top, width: width, height: height - top)
        let lines = TextHighlights.dropCapLines(body, capRect: layout.capRect, rect: rect)
        let ranges = shown.map { unit -> NSRange in
            let from = min(max(0, unit.location - cut), body.length)
            let to = min(max(from, NSMaxRange(unit) - cut), body.length)
            return NSRange(location: from, length: to - from)
        }
        return (lines, ranges)
    }

    /// One unit at its frame, about its centre.
    private func drawUnit(_ frame: ElementAnimation.UnitFrame, rects: [CGRect], clock: ElementAnimation.UnitClock,
                          ink: UIColor, in cg: CGContext, size: CGSize) {
        let bounds = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.translateBy(x: bounds.midX + frame.dx, y: bounds.midY + frame.dy)
        cg.rotate(by: frame.rotation * .pi / 180)
        cg.scaleBy(x: frame.scale, y: frame.scale)
        cg.translateBy(x: -bounds.midX, y: -bounds.midY)
        let block = clock.animation.kind == "block"
        if frame.alpha > 0 {
            cg.saveGState()
            // Write on: the share drawn on so far, from the left.
            let shown = block ? rects : rects.map { CGRect(x: $0.minX, y: $0.minY, width: $0.width * frame.clip, height: $0.height) }
            cg.clip(to: shown)
            cg.setAlpha(frame.alpha)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            if frame.blur > 0.5 {
                // Clarify: soft copies round the letters, a stand-in blur.
                for k in 0..<6 {
                    let angle = Double(k) * .pi / 3
                    cg.saveGState()
                    cg.setAlpha(0.3)
                    cg.translateBy(x: cos(angle) * frame.blur * 0.5, y: sin(angle) * frame.blur * 0.5)
                    drawText(in: cg, size: size)
                    cg.restoreGState()
                }
            } else {
                drawText(in: cg, size: size)
            }
            cg.endTransparencyLayer()
            cg.restoreGState()
        }
        // Block's bar in the text's colour: across the unit to its clip,
        // then, from clip 1, off it from the left as the words show.
        guard block, frame.clip > 0, frame.clip < 2 else { return }
        cg.setFillColor(ink.cgColor)
        let from = max(0, frame.clip - 1), to = min(1, frame.clip)
        for rect in rects {
            cg.fill(CGRect(x: rect.minX + rect.width * from, y: rect.minY,
                           width: rect.width * (to - from), height: rect.height))
        }
    }

    /// The photo in `el`'s letters, when they are full of one the effect
    /// lets through (TextEffect.takesPhoto) and this phone can open.
    static func pouredPhoto(_ el: Element, effect: TextEffect) -> UIImage? {
        guard let fill = el.textFill, fill.isPhoto, effect.takesPhoto else { return nil }
        return PhotoLibrary.resolve(fill.src)
    }

    /// `image` over `rect` in a context in UIKit orientation (y down):
    /// CoreGraphics lays an image out y up, so it is flipped about the
    /// rect, whatever context is current.
    static func drawPhoto(_ image: UIImage, in rect: CGRect, into cg: CGContext) {
        guard let picture = image.cgImage else { return }
        cg.saveGState()
        cg.translateBy(x: 0, y: rect.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(picture, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        cg.restoreGState()
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
                                             weight: FontLibrary.weight(of: el), italic: FontLibrary.isItalic(el))
        capAttrs[.paragraphStyle] = nil
        // The cap in the colour of the word it starts; the body with every
        // word's own colour and size, as the Android twin draws them.
        let text = FontLibrary.dropCapText(for: el, layout)
        if let colour = text.capColour { capAttrs[.foregroundColor] = colour }
        let cap = NSAttributedString(string: layout.letter, attributes: capAttrs)
        let capSize = cap.size()
        // Sit the cap's baseline on the third line's baseline.
        let line = (el.fontSize ?? 42) * (el.lineHeight ?? 1.25)
        let capTop = rect.minY + line * FontLibrary.dropCapLines - capSize.height
        cap.draw(at: CGPoint(x: rect.minX, y: capTop))

        guard text.body.length > 0 else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(text.body)
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

    /// The shadow, lift or glow the letters cast, as the effect resolved it.
    static func castShadow(_ fx: ResolvedEffect, in cg: CGContext) {
        cg.setShadow(offset: CGSize(width: fx.dx, height: fx.dy), blur: fx.blur,
                     color: UIColor(hex: fx.color).withAlphaComponent(fx.alpha).cgColor)
    }

    /// Curved text is drawn from its outlines rather than by NSAttributedString,
    /// because there is no attributed-string way to bend a baseline. The
    /// effects that survive that are the ones a filled path can carry — the
    /// shadows and the glow; outline and splice become a stroke on the same
    /// path at the effect's thickness, Outline a stroke under the filled
    /// path, and glitch and echo become offset fills.
    private func drawCurvedText(_ resolved: Element, in cg: CGContext, size: CGSize, effect: TextEffect) {
        var el = resolved
        el.w = size.width
        el.h = size.height
        // The glyphs by the colour each word is set in; the box's own first.
        guard let outlines = TextOutliner.inkedPaths(for: el) else { return }
        let path = outlines.whole, parts = outlines.parts
        let fontSize = el.fontSize ?? 42
        let ink = el.color ?? "#1f2430"
        let fx = TextEffect.resolve(el.effect, fontSize: fontSize, ink: ink)
        func fillParts(alpha: Double = 1) {
            for part in parts {
                cg.addPath(part.path)
                cg.setFillColor(UIColor(hex: part.color ?? ink).withAlphaComponent(alpha).cgColor)
                cg.fillPath()
            }
        }

        if fx.casts { Self.castShadow(fx, in: cg) }

        switch effect {
        case .outline, .splice:
            cg.setLineWidth(TextEffect.outlineStroke(fontSize: fontSize,
                                                     thickness: TextEffect.value(el.effect, .thickness, for: effect)))
            cg.setLineJoin(.round)
            for part in parts {
                cg.addPath(part.path)
                cg.setStrokeColor(UIColor(hex: part.color ?? ink).cgColor)
                cg.strokePath()
            }
        case .glitch, .echo:
            // Echo's Auto copies follow each word's colour, as on a line.
            let copiesFollow = effect == .echo && el.effect?.color == nil
            for copy in fx.copies {
                cg.saveGState()
                cg.translateBy(x: copy.dx, y: copy.dy)
                if copiesFollow {
                    fillParts(alpha: copy.alpha)
                } else {
                    cg.addPath(path)
                    cg.setFillColor(UIColor(hex: copy.color).withAlphaComponent(copy.alpha).cgColor)
                    cg.fillPath()
                }
                cg.restoreGState()
            }
            fillParts()
        case .outlined:
            // The stroke round the letters, then the letters filled over it.
            if fx.stroke > 0 {
                cg.saveGState()
                cg.setLineWidth(fx.stroke)
                cg.setLineJoin(.round)
                cg.setStrokeColor(UIColor(hex: fx.color).cgColor)
                cg.addPath(path)
                cg.strokePath()
                cg.restoreGState()
            }
            fallthrough
        default:
            fillParts()
            // The outline is a path, so the gradient clips to it directly —
            // no mask, no flip; the path is already in this context's space.
            // A photo in the letters the same, where the window puts it.
            if let fill = el.textFill, fill.kind == "gradient" {
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                cg.addPath(path)
                cg.clip()
                Self.paintGradient(fill, in: cg, rect: CGRect(origin: .zero, size: size), flipped: false)
                cg.restoreGState()
            } else if let fill = el.textFill, let photo = Self.pouredPhoto(el, effect: effect) {
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                cg.addPath(path)
                cg.clip()
                Self.drawPhoto(photo, in: PhotoFills.window(photo, box: size, paint: fill), into: cg)
                cg.restoreGState()
            }
        }
    }

    private struct LineFragment {
        var rect: CGRect
    }

    /// Wrapped line rectangles for the highlight effect, from the very
    /// string that is drawn — inline bold and all — framed at the box's
    /// width: each line from where CoreText sets it (indents, a list's
    /// hanging marker and the alignment all in its origin) to the end of
    /// its ink, and a justified line that is not a paragraph's last across
    /// the whole box — as the Android twin spans each bar from its layout's
    /// line left to line right.
    private func lineFragments(_ el: Element, width: Double, pitch: Double, top: Double) -> [LineFragment] {
        let attributed = FontLibrary.attributedString(for: el)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return [] }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let string = attributed.string as NSString
        // Paragraph spacing, as FontLibrary sets it: after each line break.
        let gap = (el.fontSize ?? 42) * max(0, el.paragraphSpacing ?? 0)
        let justified = el.align == "justify"
        var lineTop = top
        var fragments: [LineFragment] = []
        for (i, line) in lines.enumerated() {
            let range = CTLineGetStringRange(line)
            let end = range.location + range.length
            let endsParagraph = end >= string.length || (end > 0 && string.character(at: end - 1) == 10)
            let topY = lineTop
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let full = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            // Each line the pitch, unless its paragraph has room for a larger
            // word (RichText.makeRoom): then its own height, up to that room —
            // so the lines below a grown one start where they are drawn, as
            // the Android twin takes each bar's top from its layout.
            let style = range.location < attributed.length
                ? attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                : nil
            let room = max(pitch, Double(style?.maximumLineHeight ?? 0))
            lineTop += min(max(Double(ascent + descent + leading), pitch), room)
            if endsParagraph { lineTop += gap }
            let inked = full - CTLineGetTrailingWhitespaceWidth(line)
            guard inked > 0.5 else { continue }
            let x = Double(origins[i].x)
            let lineWidth = justified && !endsParagraph ? max(inked, width - x) : inked
            fragments.append(LineFragment(rect: CGRect(x: x, y: topY, width: lineWidth, height: pitch)))
        }
        return fragments
    }

}

// MARK: - image

struct ImageElementView: View {
    let element: Element
    /// Whether the page's clock runs, so a clip played live plays on in a
    /// player of its own (ClipPlayers).
    var clipPlays = false
    @Environment(\.liveVideo) private var liveVideo
    @Environment(\.onScreen) private var onScreen
    @Environment(\.clipsInOrder) private var clipsInOrder

    var body: some View {
        // Resolved here, not inside the GeometryReader, so that a clip played
        // live — whose frame version is read on the way — is watched by this
        // view, and drawn again when its next frame lands; and so is a
        // subject found for focus.
        // A plain code is drawn as rectangles, sharp at any size and vectors
        // in a PDF; any other picture through its look.
        let code = CodeGenerator.vector(element)
        let barcode = code == nil ? Barcodes.vector(element) : nil
        let picture = code == nil && barcode == nil ? resolvedPicture() : nil
        let waits = waitsForSubject()
        let later = makesLookLater()
        let resolved = picture.map {
            ImageFilterEngine.apply(look: element, to: $0.image, cacheKey: $0.key, waits: waits, later: later)
        }
        GeometryReader { _ in
            if let code {
                CodeVectorView(code: code)
            } else if let barcode {
                BarcodeVectorView(element: element, code: barcode)
            } else if let ui = resolved {
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
                // Solid as it always was, square-cornered; dashed or dotted
                // as a shape's border is.
                frame.stroke(Color(hex: stroke), style: BorderDash.kept(element.dash) == nil
                             ? StrokeStyle(lineWidth: sw) : .border(element.dash, width: sw))
            }
        }
        // An outline or glow round what the photo shows, behind it and past
        // its frame — after the clip, so the frame does not cut it away. It
        // is part of what casts the element's shadow (ElementView's), as the
        // Android twin casts a photo's shadow from its edge.
        .background {
            if let picture, let edge = PhotoEffects.edge(element, picture: picture.image, key: picture.key) {
                Image(uiImage: edge.image)
                    .resizable()
                    .frame(width: element.w + 2 * edge.pad, height: element.h + 2 * edge.pad)
                    .allowsHitTesting(false)
            }
        }
        // Edge, picture and border flattened into one layer, so ElementView's
        // opacity and shadow apply to the whole photo, as the Android twin
        // draws an element in one layer: a see-through photo never shows
        // its own solid outline through it, nor shades its edge.
        .compositingGroup()
    }

    private var frame: FrameShape {
        FrameShape(definition: ContentLibrary.frameShape(element.maskShapeId),
                   cornerRadius: element.radius ?? 0)
    }

    /// Whether the look waits for the subject its focus keeps sharp to be
    /// found: a file does; on screen the photo shows the focus circle
    /// meanwhile, and reading the count of subjects found draws it again
    /// when its subject lands.
    private func waitsForSubject() -> Bool {
        guard onScreen, element.focusBlur?.subject == true else { return true }
        _ = ImageFilterEngine.subjectsFound.version
        return false
    }

    /// Whether clarity or pixelate is made off the main thread: on screen
    /// it is, the photo showing its last look meanwhile, and reading the
    /// count of looks made draws it again when its own is ready.
    private func makesLookLater() -> Bool {
        guard onScreen, ImageFilterEngine.makesLater(element) else { return false }
        _ = ImageFilterEngine.looksBaked.version
        return true
    }

    /// The picture before its look, and the key its looks are kept by.
    private func resolvedPicture() -> (image: UIImage, key: String)? {
        let base: UIImage
        let key: String
        if liveVideo, let src = element.src, VideoStore.isVideo(src) {
            // Played live, a clip never makes the screen wait for a frame to
            // decode: it shows the latest it has, and the version read here
            // brings the next one in when it is ready. While the page's
            // clock runs, its player plays it on at its speed.
            _ = VideoStore.live.version
            let playing: ClipPlayback? = clipPlays ? (element.clip ?? ClipPlayback()) : nil
            guard let shown = VideoStore.peek(src, playing: playing, for: element.id) else { return nil }
            base = shown.image
            // Keyed by the frame shown, not the moment asked for, so a
            // filtered copy is never kept of a stand-in frame.
            key = shown.key
        } else if let readers = clipsInOrder, let src = element.src, VideoStore.isVideo(src) {
            // A video export asks for each clip's frames in order, and its
            // reader reads on from the last rather than seeking for each.
            guard let image = VideoStore.read(src, by: readers) else { return nil }
            base = image
            key = src
        } else if onScreen, let src = element.src, AnimStore.split(src)?.time != nil {
            // An animated picture playing on screen — Play in the editor,
            // Present — never waits for a frame either: small frames are
            // decoded on a worker, and the version read here draws the next.
            _ = AnimStore.live.version
            guard let shown = AnimStore.peek(src) else { return nil }
            base = shown.image
            key = shown.key
        } else if let src = element.src, CodeGenerator.payload(from: src) != nil {
            // A code in its own colours and margin, its looks kept apart by
            // them.
            guard let code = CodeGenerator.picture(of: element) else { return nil }
            base = code.image
            key = code.key
        } else {
            guard let image = PhotoLibrary.resolve(element.src) else { return nil }
            base = image
            // An animated picture's looks are kept by the frame shown, not
            // the moment asked for, so a frame held is never made again.
            key = element.src.map { AnimStore.isAnim($0) ? AnimStore.shownKey($0) : $0 } ?? ""
        }
        return (base, key)
    }
}

/// A QR code as rectangles (CodeGenerator.vector): its background, unless
/// it has none, then its modules in its colour, in the element's own space.
/// Shapes, not pixels, so a PDF of the page keeps them as vectors.
/// A styled code's dots and eyes are its outline (CodeGenerator.marks),
/// filled even-odd so the eyes' rings stay open; a logo sits on a pad of
/// the background's colour in its middle.
struct CodeVectorView: View {
    let code: CodeGenerator.Vector

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let paper = code.style.background, let box = code.background {
                Path(box).fill(Color(hex: paper))
            }
            if code.marks.isEmpty {
                Path { path in path.addRects(code.modules) }
                    .fill(Color(hex: code.style.color))
            } else {
                Path(CodeGenerator.path(code.marks))
                    .fill(Color(hex: code.style.color), style: FillStyle(eoFill: true))
            }
            if let pad = code.logoPad {
                logo(on: pad)
            }
        }
    }

    @ViewBuilder
    private func logo(on pad: CGRect) -> some View {
        Path(pad).fill(Color(hex: code.style.background ?? CodeGenerator.defaultBackground))
        if let src = code.style.logo, let picture = PhotoLibrary.resolve(src), let box = CodeGenerator.logoBox(pad) {
            let shown = CodeGenerator.fitted(picture.size, in: box)
            Image(uiImage: picture)
                .resizable()
                .frame(width: shown.width, height: shown.height)
                .offset(x: shown.minX, y: shown.minY)
        }
    }
}

/// A barcode as rectangles (Barcodes.vector): its background, unless it
/// has none, its bars in its colour, and its words — or why it cannot be
/// made — under them, in the element's own space: a text element
/// (Barcodes.captionElement) drawn as any other is, wrapping as it does,
/// as the SVG, the PowerPoint and the Android twin draw it. Shapes and
/// text, not pixels, so a PDF of the page keeps them as vectors.
struct BarcodeVectorView: View {
    let element: Element
    let code: Barcodes.Drawing

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let paper = code.style.background, let box = code.background {
                Path(box).fill(Color(hex: paper))
            }
            Path { path in path.addRects(code.bars) }
                .fill(Color(hex: code.style.color))
            if let words = caption {
                TextElementView(element: words)
                    .position(x: words.x + words.w / 2, y: words.y + words.h / 2)
            }
        }
    }

    /// The words under the bars, at full opacity: the element's own is
    /// applied to the whole code.
    private var caption: Element? {
        guard var words = Barcodes.captionElement(element, code) else { return nil }
        words.opacity = 1
        return words
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
        SwiftUI.Canvas { context, _ in
            Self.drawRoute(element, in: context)
        }
        .frame(width: element.w, height: element.h)
    }

    /// A line (LineRoutes) in its own box: one stroke along its route —
    /// across its middle when straight, its corners round, a curve a
    /// quadratic — dashed 3:2 or dotted, stopping short of its heads, and
    /// each end's head (LineEnds) pointing along its segment.
    static func drawRoute(_ el: Element, in context: GraphicsContext) {
        let t = max(el.thickness ?? 4, 0.5)
        let color = Color(hex: el.color ?? "#1f2430")
        let route = LineRoutes.route(el)
        let points = LineRoutes.trimmed(route, startBack: LineRoutes.strokeBack(el, cap: el.startCap),
                                        endBack: LineRoutes.strokeBack(el, cap: el.endCap))
        var stroke = Path()
        stroke.move(to: points[0])
        if route.curved && points.count == 3 {
            stroke.addQuadCurve(to: points[2], control: points[1])
        } else {
            for p in points.dropFirst() { stroke.addLine(to: p) }
        }
        var style = StrokeStyle(lineWidth: t, lineCap: .round, lineJoin: .round)
        if el.dash == "dashed" { style.dash = [t * 3, t * 2] }
        if el.dash == "dotted" { style.dash = [0.01, t * 2.2] }
        context.stroke(stroke, with: .color(color), style: style)
        for head in LineEnds.heads(el) {
            drawHead(head, color: color, in: context)
        }
    }

    /// One head: filled, or stroked as wide as its line, round-joined.
    static func drawHead(_ head: LineEnds.Head, color: Color, in context: GraphicsContext) {
        let path = Path(LineEnds.path(head))
        if head.stroked {
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: head.width, lineCap: .round, lineJoin: .round))
        } else {
            context.fill(path, with: .color(color))
        }
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
    /// Page units shown beyond the trim on every side — a print bleed
    /// (Bleed) — or none. With some, the view is that much bigger all round:
    /// the page's background runs on through the band (PageBackgroundFill),
    /// and what is put out past the trim shows up to the bleed's edge and is
    /// cut there. Only the canvas's bleed band and the print-ready PDF ask
    /// for it; everything else draws the trim, cut at the page's edge. The
    /// trim is the same picture either way.
    var bleed: Double = 0
    /// The canvas's whiteboard (Whiteboards): the background cut at the
    /// frame, and what is on the page drawn wherever it is, past the frame
    /// too. Everything that leaves the app draws the flattened page instead.
    var board = false
    @Environment(\.animationTime) private var animationTime
    @Environment(\.captionTime) private var captionTime
    /// A tagged PDF's page (PdfTags): a sentinel before each element, the
    /// master's first, which the PDF's update turns into marked content.
    var sentinels = false

    var body: some View {
        if board { boardView } else if bleed > 0 { bled } else { trimmed }
    }

    /// A clip or an animated picture playing behind the page
    /// (BackgroundClip): the photo that plays it, over the background's
    /// white, behind every element — playing as the page plays, at rest its
    /// first frame, as any clip shows — or, in a still export made with the
    /// timeline open, the frame at its playhead (`captionTime`).
    @ViewBuilder
    private var clipBehind: some View {
        if let el = clipBackdrop {
            ElementView(element: el).equatable()
        }
    }

    private var clipBackdrop: Element? {
        guard var el = PageBackgrounds.clipElement(page, size: design.size(for: page), cover: Bleed.of(design)),
              let clip = page.backgroundClip else { return nil }
        if animationTime == nil, let at = captionTime {
            let length = VideoStore.split(clip.src).flatMap { VideoStore.duration(of: $0.id) }
            el.src = clip.src(at: at, duration: length)
        }
        return el
    }

    /// The page's own elements as drawn: while it plays, with its own
    /// animation played into them (PageAnimation).
    private var ownElements: [Element] {
        animationTime == nil ? page.elements : PageAnimation.playing(page).elements
    }

    private var boardView: some View {
        let size = design.size(for: page)
        return ZStack {
            ZStack(alignment: .topLeading) {
                PageBackgroundFill(background: page.background, size: size, cover: Bleed.of(design))
                clipBehind
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            drawn
        }
        .frame(width: size.width, height: size.height)
        .environment(\.pageNumber, pageNumberValue)
        .designDirection()
    }

    private var trimmed: some View {
        ZStack {
            PageBackgroundFill(background: page.background, size: design.size(for: page), cover: Bleed.of(design))
            clipBehind
            drawn
        }
        .frame(width: design.size(for: page).width, height: design.size(for: page).height)
        .clipped()
        .environment(\.pageNumber, pageNumberValue)
        .designDirection()
    }

    /// The page in the middle of its bleed: the background under all of
    /// it, and the page's own things placed on the trim as ever, free to
    /// run out into the band.
    private var bled: some View {
        let size = design.size(for: page)
        let whole = CGSize(width: size.width + 2 * bleed, height: size.height + 2 * bleed)
        return ZStack {
            PageBackgroundFill(background: page.background, size: size, reach: bleed, cover: Bleed.of(design))
            ZStack {
                clipBehind
                drawn
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: whole.width, height: whole.height)
        .clipped()
        .environment(\.pageNumber, pageNumberValue)
        .designDirection()
    }

    @ViewBuilder
    private var drawn: some View {
        if sentinels { sentinelled } else { plain }
    }

    /// What `plain` draws, sentinel k before the kth element drawn —
    /// design.drawnElements(on:), the order the PDF's tags are read in.
    private var sentinelled: some View {
        let elements = Array(design.drawnElements(on: page).enumerated())
        return ForEach(elements, id: \.element.id) { n, el in
            PdfSentinel(index: n + 1)
            ElementView(element: el).equatable()
        }
    }

    @ViewBuilder
    private var plain: some View {
        // The master page's elements, behind this page's own. Not on
        // the master itself, and not on a page that opted out.
        // A group's crop is put into each member's own box (GraphicClip).
        ForEach(GraphicClip.shown(design.masterElements(behind: page), in: design.masterPage?.elements ?? [])) { el in
            ElementView(element: el).equatable()
        }
        // A hidden element is never drawn, here or in anything that
        // renders through this view: exports, thumbnails, Present, video.
        ForEach(GraphicClip.shown(ownElements.filter { !$0.isHidden }, in: ownElements)) { el in
            // .equatable() so a drag re-renders the element that moved
            // rather than every element on the page. The store is
            // @Observable and a gesture mutates the document each frame,
            // so without this every text run re-lays out through CoreText
            // and every shape re-parses its path, on every frame, however
            // little actually changed.
            ElementView(element: el).equatable()
        }
    }

    private var pageNumberValue: (number: Int, count: Int)? {
        guard let index = design.pages.firstIndex(where: { $0.id == page.id }) else { return nil }
        return (index + 1, design.pages.count)
    }
}

/// A tagged PDF's sentinel (PdfTags): a speck at the page's top left in
/// the colour that numbers it, which the PDF's update takes out again.
struct PdfSentinel: View {
    let index: Int

    var body: some View {
        let c = PdfTags.sentinelComponents(index)
        Rectangle()
            .fill(Color(.sRGB, red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255))
            .frame(width: PdfTags.sentinelSize, height: PdfTags.sentinelSize)
            .position(x: PdfTags.sentinelSize / 2, y: PdfTags.sentinelSize / 2)
            .accessibilityHidden(true)
    }
}

/// A page's background, in a view `reach` page units bigger than the page
/// all round — a print bleed — or the page's own size, laid as Android's
/// PageRenderer.drawBackground lays it, so the trim shows the same thing
/// whether or not the band is drawn round it: a colour all over; a
/// gradient over the page, its end colours carried on through the band; a
/// photo filling the page and `cover` round it — the design's own bleed,
/// in every drawing of the page, trimmed or bled — centred on the page,
/// over white. Not clipped: the view it is in cuts it.
struct PageBackgroundFill: View {
    let background: Background
    /// The page's size, in page units.
    let size: CGSize
    /// How far this view reaches past the trim on every side.
    var reach: Double = 0
    /// How far past the trim a photo is laid: the design's bleed.
    var cover: Double = 0
    /// The page's clock while it plays, which a generated loop behind it
    /// goes round on (MotionLibrary).
    @Environment(\.animationTime) private var animationTime

    var body: some View {
        fill.frame(width: Double(size.width) + 2 * reach, height: Double(size.height) + 2 * reach)
    }

    @ViewBuilder
    private var fill: some View {
        switch background {
        case .color(let hex):
            Color(hex: hex)
        case .gradient(let paint):
            gradient(paint)
        case .image(let src):
            ZStack {
                Color.white
                if let ui = PhotoLibrary.resolve(shown(src)) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Double(size.width) + 2 * cover, height: Double(size.height) + 2 * cover)
                }
            }
        }
    }

    /// The background picture's source as it shows now: a loop at the
    /// page's moment while it plays.
    private func shown(_ src: String) -> String {
        guard let clock = animationTime, MotionLibrary.isMotion(src) else { return src }
        return MotionLibrary.playing(src, at: clock.time) ?? src
    }

    /// A gradient laid over the page in the middle of this view, as
    /// Android's shader clamps it past the page: a linear one along the
    /// page's own line, its end colours on through the band; a radial one
    /// round the page's ellipse, its outer colour beyond; an angular one
    /// sweeping on round the page's centre.
    @ViewBuilder
    private func gradient(_ paint: Paint) -> some View {
        if reach <= 0 || paint.kind != "gradient" || paint.stops == nil || paint.gradientKind == "angular" {
            paint.fillView()
        } else if paint.gradientKind == "radial" {
            ZStack {
                Color(hex: paint.stops?.max(by: { $0.offset < $1.offset })?.color ?? "#000000")
                paint.fillView()
                    .frame(width: size.width, height: size.height)
            }
        } else {
            let line = paint.unitPoints
            Rectangle().fill(LinearGradient(stops: paint.swiftUIStops,
                                            startPoint: onPage(line.start), endPoint: onPage(line.end)))
        }
    }

    /// A point in the page's unit square as one in this bigger view's.
    private func onPage(_ point: UnitPoint) -> UnitPoint {
        let w = Double(size.width), h = Double(size.height)
        return UnitPoint(x: (reach + Double(point.x) * w) / (w + 2 * reach),
                         y: (reach + Double(point.y) * h) / (h + 2 * reach))
    }
}
