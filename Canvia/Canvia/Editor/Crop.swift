// The geometry of a photo inside its frame, for crop mode.
//
// A photo element is two boxes: the frame — the element's own x/y/w/h,
// which is what the page shows — and the picture, the whole image at the
// size it is drawn, which always covers the frame and usually overflows it.
// The document keeps the picture as three numbers: cropScale, how far past
// "just covers the frame" it is enlarged, and cropX/cropY, the share of the
// overflow that lies to the left of and above the frame. ImageElementView
// draws exactly that, so the picture can never leave a gap whatever the
// numbers say.
//
// Crop mode edits the picture three ways, all here: moving it behind the
// frame, zooming it about a point, and trimming the frame by one of its
// eight handles, which moves an edge of the frame across the picture while
// the picture itself stays where it is on the page.
//
// The same maths as the Android twin's Crop (core/geometry/Crop.kt), rule
// for rule, so a crop made on either phone writes the same numbers into the
// same fields and looks the same on the other.
//
// Every box here is in the frame's own coordinates: origin at the frame's
// top-left, axes turned with the element. `picture` is the picture as seen
// — a flipped photo's is mirrored, so dragging it right moves it right —
// and `drawnPicture` is the same box before the flip, which is what the
// renderer lays out before it applies the flip to the whole element.

import CoreGraphics
import Foundation

enum Crop {

    /// The most a zoom enlarges a picture past covering its frame. A trim may
    /// leave a picture further in than this (a small frame over a big
    /// picture), and that is kept: zooming out is always allowed, only
    /// zooming further in stops here.
    static let maxZoom = 10.0

    /// The smallest frame a trim leaves, in page units, unless the picture
    /// itself is narrower.
    static let minFrame = 16.0

    private static let epsilon = 1e-9

    /// How near a frame's sides are to a ratio's trim for it to be that
    /// shape already, in page units: the Android twin's Crop.SAME_SHAPE.
    static let sameShape = 1e-6

    /// Closer than this, in page units, two pictures are the same picture —
    /// so rounding noise never records an Undo that changes nothing.
    private static let same = 1e-3

    /// The scale that makes an `image` just cover a `w` × `h` frame.
    static func cover(w: Double, h: Double, image: CGSize) -> Double {
        max(w / Double(image.width), h / Double(image.height))
    }

    /// The scale that makes the whole `image` just fit inside the frame.
    static func fit(w: Double, h: Double, image: CGSize) -> Double {
        min(w / Double(image.width), h / Double(image.height))
    }

    /// The picture before any flip, in frame coordinates.
    static func drawnPicture(_ el: Element, image: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(x: 0, y: 0, width: el.w, height: el.h) }
        // "Fit" shows the whole picture inside the frame; the same focus
        // rule places it.
        let base = el.cropFit == true ? fit(w: el.w, h: el.h, image: image) : cover(w: el.w, h: el.h, image: image)
        let scale = base * max(1, el.cropScale ?? 1)
        let w = Double(image.width) * scale
        let h = Double(image.height) * scale
        let fx = min(max(el.cropX ?? 0.5, 0), 1)
        let fy = min(max(el.cropY ?? 0.5, 0), 1)
        return CGRect(x: -(w - el.w) * fx, y: -(h - el.h) * fy, width: w, height: h)
    }

    /// The picture as it appears in the frame, flip included.
    static func picture(_ el: Element, image: CGSize) -> CGRect {
        mirrored(el, drawnPicture(el, image: image))
    }

    /// The element whose picture sits at `seen` (frame coordinates, as
    /// seen), pushed back to cover the frame if it would leave a gap:
    /// enlarged when it is too small, then slid until no edge of the frame is
    /// uncovered. Nothing else about the element changes, and nothing at all
    /// when the picture would not visibly move.
    static func withPicture(_ el: Element, image: CGSize, seen: CGRect) -> Element {
        guard image.width > 0, image.height > 0, el.w > 0, el.h > 0 else { return el }
        let imageW = Double(image.width), imageH = Double(image.height)
        let cover = cover(w: el.w, h: el.h, image: image)
        let wanted = max(Double(seen.width) / imageW, Double(seen.height) / imageH)
        let scale = max(wanted, cover)
        let w = imageW * scale
        let h = imageH * scale
        // The lower bound through `min`: "just covers" can come out a hair
        // under the frame in floating point, and an empty range would pin
        // the picture to the wrong edge.
        let left = clamp(Double(seen.midX) - w / 2, min(el.w - w, 0), 0)
        let top = clamp(Double(seen.midY) - h / 2, min(el.h - h, 0), 0)
        let drawn = mirrored(el, CGRect(x: left, y: top, width: w, height: h))
        let before = drawnPicture(el, image: image)
        if abs(before.minX - drawn.minX) < same && abs(before.minY - drawn.minY) < same
            && abs(before.width - drawn.width) < same && abs(before.height - drawn.height) < same {
            return el
        }
        let overflowX = w - el.w
        let overflowY = h - el.h
        let zoom = scale / cover
        var out = el
        out.cropScale = abs(zoom - 1) < epsilon ? 1 : zoom
        out.cropX = overflowX > epsilon ? clamp(-Double(drawn.minX) / overflowX, 0, 1) : 0.5
        out.cropY = overflowY > epsilon ? clamp(-Double(drawn.minY) / overflowY, 0, 1) : 0.5
        return out
    }

    /// A page point in the frame's coordinates.
    static func toFrame(_ el: Element, _ page: CGPoint) -> CGPoint {
        let local = Geometry.rotate(page, around: el.center, degrees: -el.rotation)
        return CGPoint(x: local.x - el.x, y: local.y - el.y)
    }

    /// A point in the frame's coordinates, back on the page.
    static func toPage(_ el: Element, _ frame: CGPoint) -> CGPoint {
        Geometry.rotate(CGPoint(x: el.x + frame.x, y: el.y + frame.y), around: el.center, degrees: el.rotation)
    }

    /// The picture moved by `delta`, a page-space vector — turned into the
    /// frame's axes, so dragging a turned photo moves it under the finger.
    static func moved(_ el: Element, image: CGSize, by delta: CGPoint) -> Element {
        let d = Geometry.rotate(delta, around: .zero, degrees: -el.rotation)
        let seen = picture(el, image: image)
        return withPicture(el, image: image, seen: seen.offsetBy(dx: d.x, dy: d.y))
    }

    /// The picture enlarged by `factor` about `aroundPage`, the point that
    /// stays put — where the fingers are. Never smaller than covering the
    /// frame, and never further in than `maxZoom`, or than it already is.
    static func zoomed(_ el: Element, image: CGSize, by factor: Double, around aroundPage: CGPoint) -> Element {
        guard image.width > 0, image.height > 0, factor > 0 else { return el }
        let current = max(1, el.cropScale ?? 1)
        let target = clamp(current * factor, 1, max(current, maxZoom))
        return scaled(el, image: image, by: target / current, about: toFrame(el, aroundPage))
    }

    /// The picture at an absolute zoom — 1 just covers the frame — about the
    /// frame's centre: what the crop bar's slider sets.
    static func zoomed(_ el: Element, image: CGSize, to zoom: Double) -> Element {
        guard image.width > 0, image.height > 0 else { return el }
        let current = max(1, el.cropScale ?? 1)
        let target = clamp(zoom, 1, max(current, maxZoom))
        return scaled(el, image: image, by: target / current, about: CGPoint(x: el.w / 2, y: el.h / 2))
    }

    private static func scaled(_ el: Element, image: CGSize, by f: Double, about anchor: CGPoint) -> Element {
        let seen = picture(el, image: image)
        let grown = CGRect(x: anchor.x + (seen.minX - anchor.x) * f,
                           y: anchor.y + (seen.minY - anchor.y) * f,
                           width: seen.width * f,
                           height: seen.height * f)
        return withPicture(el, image: image, seen: grown)
    }

    /// The frame trimmed by dragging `handle` to `pointerPage`.
    ///
    /// Only the dragged edges move, and only across the picture: an edge
    /// stops at the picture's own edge, since past it there is nothing to
    /// show, and the frame keeps at least `minSize` (or the picture's extent,
    /// if that is smaller). The picture does not move on the page — the crop
    /// numbers are rewritten so it stays exactly where it was while the frame
    /// changes shape around it — and the opposite edges hold still however
    /// the element is turned. Corners trim two edges; nothing scales.
    static func trimmed(_ el: Element, image: CGSize, handle: Handle, to pointerPage: CGPoint,
                        minSize: Double = minFrame) -> Element {
        guard image.width > 0, image.height > 0 else { return el }
        let seen = picture(el, image: image)
        let p = toFrame(el, pointerPage)
        let px = Double(p.x), py = Double(p.y)
        let seenMinX = Double(seen.minX), seenMaxX = Double(seen.maxX)
        let seenMinY = Double(seen.minY), seenMaxY = Double(seen.maxY)
        var left = 0.0, right = el.w, top = 0.0, bottom = el.h
        switch handle.unit.x {
        case 0: left = max(min(px, right - min(minSize, right - seenMinX)), seenMinX)
        case 1: right = min(max(px, left + min(minSize, seenMaxX - left)), seenMaxX)
        default: break
        }
        switch handle.unit.y {
        case 0: top = max(min(py, bottom - min(minSize, bottom - seenMinY)), seenMinY)
        case 1: bottom = min(max(py, top + min(minSize, seenMaxY - top)), seenMaxY)
        default: break
        }
        let w = right - left
        let h = bottom - top
        guard w > 0, h > 0 else { return el }
        let centre = toPage(el, CGPoint(x: (left + right) / 2, y: (top + bottom) / 2))
        var framed = el
        framed.x = centre.x - w / 2
        framed.y = centre.y - h / 2
        framed.w = w
        framed.h = h
        // The same picture, measured from the new frame's corner.
        let kept = CGRect(x: seenMinX - left, y: seenMinY - top, width: seen.width, height: seen.height)
        return withPicture(framed, image: image, seen: kept)
    }

    /// The frame trimmed to `ratio` (width over height): the largest box
    /// of that shape inside the current frame, centred on it, so the frame
    /// only ever shrinks — a wider ratio keeps the width and cuts the
    /// height, a taller one keeps the height and cuts the width. The
    /// picture stays exactly where it is on the page, measured from the new
    /// frame's corner and re-covered (withPicture), as a trim leaves it. No
    /// rounding: the sides are whatever the ratio makes them, as on the
    /// Android twin. The element as it is for a ratio that is not positive,
    /// or a frame that already has that shape (both sides within sameShape
    /// of the trim).
    static func trimmedToRatio(_ el: Element, ratio: Double, image: CGSize) -> Element {
        guard ratio > 0, ratio.isFinite, el.w > 0, el.h > 0 else { return el }
        let w: Double, h: Double
        if el.w / el.h > ratio {
            h = el.h
            w = el.h * ratio
        } else {
            w = el.w
            h = el.w / ratio
        }
        guard abs(w - el.w) >= sameShape || abs(h - el.h) >= sameShape else { return el }
        let left = (el.w - w) / 2
        let top = (el.h - h) / 2
        let centre = el.center
        var framed = el
        framed.x = centre.x - w / 2
        framed.y = centre.y - h / 2
        framed.w = w
        framed.h = h
        guard image.width > 0, image.height > 0 else { return framed }
        // The same picture, measured from the new frame's corner.
        let seen = picture(el, image: image)
        let kept = CGRect(x: seen.minX - left, y: seen.minY - top, width: seen.width, height: seen.height)
        return withPicture(framed, image: image, seen: kept)
    }

    /// The frame turned a quarter turn clockwise about its centre, its
    /// width and height swapped so the picture's own sides turn with it,
    /// the rotation kept within 0..<360. The crop numbers are kept as they
    /// are: the picture re-covers the frame in its new shape, as on the
    /// Android twin.
    static func rotated90(_ el: Element) -> Element {
        let centre = el.center
        var out = el
        out.w = el.h
        out.h = el.w
        out.x = centre.x - out.w / 2
        out.y = centre.y - out.h / 2
        out.rotation = ((el.rotation + 90).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return out
    }

    /// How far the straighten dial reaches either way, in degrees.
    static let straightenReach = 45.0
    /// The dial's step, in degrees.
    static let straightenStep = 0.5

    /// What the straighten dial writes for `degrees`: to the nearest half
    /// degree, a half up, within ±straightenReach — and nil at level, so a
    /// levelled photo carries no key, as the crop sheet leaves it. The detent
    /// is the step itself: within a quarter degree of level is level.
    static func steppedStraighten(_ degrees: Double) -> Double? {
        guard degrees.isFinite else { return nil }
        let held = min(max(degrees, -straightenReach), straightenReach)
        let stepped = (held / straightenStep + 0.5).rounded(.down) * straightenStep
        return stepped == 0 ? nil : stepped
    }

    /// "12.5 deg": the dial's readout, one place always.
    static func straightenReadout(_ degrees: Double?) -> String {
        tr("%@ deg", String(format: "%.1f", degrees ?? 0))
    }

    /// Back to just covering the frame, centred. The frame is kept, and so
    /// are the straightening and the fit, which the crop sheet owns.
    static func reset(_ el: Element) -> Element {
        var out = el
        out.cropScale = 1
        out.cropX = 0.5
        out.cropY = 0.5
        return out
    }

    /// A new picture in the same frame — or none, an empty frame — centred,
    /// covering it and level. The frame is what the layout depends on, so a
    /// replacement keeps it, with its corners, look and border: what Replace
    /// does, and a picture dropped or picked into a frame, as the Android
    /// twin's Crop.replaced. What was brushed onto the old picture — its
    /// mask, the picture before its Cut out with it, and its retouch — was
    /// painted over that picture, and goes with it; and alt text drawn from
    /// it (`altTextSource` its source) no longer says what shows, and goes
    /// too. Alt text typed for the frame stays. So does a frame's colour in
    /// place of a photo (PhotoFrames.colourOf): a photo put in drops it, and
    /// a frame emptied — Detach image — is left with none.
    static func replaced(_ el: Element, src: String?) -> Element {
        var out = reset(el)
        out.src = src
        out.straighten = nil
        if el.type == .image { out.fill = nil }
        out.mask = nil
        out.retouch = nil
        if let from = el.altTextSource, from == el.src, src != el.src {
            out.altText = nil
            out.altTextSource = nil
        }
        return out
    }

    /// Whether the picture has been moved or zoomed from centred and covering.
    static func isAdjusted(_ el: Element) -> Bool {
        abs((el.cropScale ?? 1) - 1) > 1e-6 || abs((el.cropX ?? 0.5) - 0.5) > 1e-6
            || abs((el.cropY ?? 0.5) - 0.5) > 1e-6
    }

    /// Mirrors a box inside the frame the way the element's flips do. Its own
    /// inverse, so it converts in both directions.
    private static func mirrored(_ el: Element, _ r: CGRect) -> CGRect {
        CGRect(x: el.flipH ? el.w - (r.minX + r.width) : r.minX,
               y: el.flipV ? el.h - (r.minY + r.height) : r.minY,
               width: r.width, height: r.height)
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}

/// The crop bar's frame shapes, in the order the chips show them: Free, the
/// picture's own, then the shared list — 1:1, 4:5, 2:3, 3:4, 9:16 and 21:9,
/// each but 1:1 one of a pair kept landscape-normalised (5:4, 3:2, 4:3,
/// 16:9, 21:9) whose other way round the orientation chip turns it to. The
/// same names and ratios as the Android twin's Crop.aspects.
enum CropAspect: CaseIterable, Hashable {
    case free, original, square, fourFive, twoThree, threeFour, nineSixteen, twentyOneNine

    /// What the lit chip is, and whether the frame has it the other way
    /// round — 5:4 for the 4:5 chip, 9:21 for 21:9.
    struct Match: Equatable {
        var aspect: CropAspect
        var turned: Bool
    }

    /// Width and height as the chip offers it first; nil for Free and
    /// Original.
    var sides: (w: Int, h: Int)? {
        switch self {
        case .free, .original: return nil
        case .square: return (1, 1)
        case .fourFive: return (4, 5)
        case .twoThree: return (2, 3)
        case .threeFour: return (3, 4)
        case .nineSixteen: return (9, 16)
        case .twentyOneNine: return (21, 9)
        }
    }

    /// The pair as it is kept, the longer side first: 5:4 for 4:5.
    var landscape: (w: Int, h: Int)? {
        guard let s = sides else { return nil }
        return (w: max(s.w, s.h), h: min(s.w, s.h))
    }

    /// Whether the orientation chip turns it: a ratio with two ways round
    /// — not Free, Original or 1:1.
    var turns: Bool {
        guard let sides else { return false }
        return sides.w != sides.h
    }

    /// The chip's words.
    var name: String { name(turned: false) }

    /// The chip's words, the other way round when `turned` and it turns.
    func name(turned: Bool) -> String {
        switch self {
        case .free: return tr("Free")
        case .original: return tr("Original")
        default:
            guard let sides else { return "" }
            return turned && turns ? "\(sides.h):\(sides.w)" : "\(sides.w):\(sides.h)"
        }
    }

    /// Width over height; Original is the picture's own, and Free is none —
    /// the frame as it is.
    func ratio(image: CGSize) -> Double? {
        ratio(image: image, turned: false)
    }

    /// The same, the other way round (r becomes 1/r) when `turned` and it
    /// turns.
    func ratio(image: CGSize, turned: Bool) -> Double? {
        switch self {
        case .free: return nil
        case .original: return image.height > 0 ? Double(image.width) / Double(image.height) : nil
        default:
            guard let sides else { return nil }
            return turned && turns ? Double(sides.h) / Double(sides.w) : Double(sides.w) / Double(sides.h)
        }
    }

    /// The chip lit for `el`: the first whose ratio the frame has, within
    /// one percent — Original before 4:3 for a 4:3 picture — and Free when
    /// none does.
    static func matching(_ el: Element, image: CGSize) -> CropAspect {
        matched(el, image: image).aspect
    }

    /// The chip lit for `el`, and whether the frame has it turned.
    static func matched(_ el: Element, image: CGSize) -> Match {
        guard el.h > 0 else { return Match(aspect: .free, turned: false) }
        return matched(ratio: el.w / el.h, image: image)
    }

    /// The chip lit for a frame `have` wide to 1 high: the first, in the
    /// chips' order, whose ratio it has either way round within one percent
    /// (matchingAspect, both orientations) — its own way before the other —
    /// and Free when none does.
    static func matched(ratio have: Double, image: CGSize) -> Match {
        guard have > 0, have.isFinite else { return Match(aspect: .free, turned: false) }
        for aspect in allCases {
            guard let ratio = aspect.ratio(image: image), ratio > 0 else { continue }
            if abs(have / ratio - 1) < 0.01 { return Match(aspect: aspect, turned: false) }
            if aspect.turns && abs(have * ratio - 1) < 0.01 { return Match(aspect: aspect, turned: true) }
        }
        return Match(aspect: .free, turned: false)
    }

    /// The largest number a side of Custom… takes.
    static let customMost = 100

    /// Custom…'s width and height as typed, as a ratio: each a whole number
    /// from 1 to customMost, else nil — nothing applied.
    static func customRatio(_ w: String, _ h: String) -> Double? {
        guard let w = Int(w.trimmingCharacters(in: .whitespaces)), let h = Int(h.trimmingCharacters(in: .whitespaces)),
              (1...customMost).contains(w), (1...customMost).contains(h) else { return nil }
        return Double(w) / Double(h)
    }
}
