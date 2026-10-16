// How the view moves on its own while a finger works the canvas: the edge
// scroll that carries a dragged thing past the edge of the screen, how far a
// flick of the view glides on, and the zoom typing into small words brings
// them up to. Both phones share these rules and test rows (the Android
// twin's Viewport.edgeScroll, Viewport.flingCarry and Viewport.typingZoom).

import CoreGraphics
import Foundation

enum Viewport {

    /// How near an edge of the canvas, in points, a finger dragging
    /// something starts the view scrolling that way.
    static let edgeBand = 40.0
    /// The fastest the view scrolls, with the finger at or past the edge, in
    /// points a frame.
    static let edgeMaxSpeed = 14.0

    /// How far the view scrolls this frame, in points, with a finger
    /// dragging something at `finger` in a canvas showing `viewport` — the
    /// part of the screen the page shows in, less the bars and any panel
    /// over it. On each axis, `depth` is how far inside the band along that
    /// side the finger is (`edge` less its distance to the side, kept within
    /// 0…edge, so a finger past the side is at full depth), and the view
    /// moves toward that side at maxSpeed × (depth / edge)². Positive is
    /// right and down: the view moves on to show more that way.
    static func edgeScroll(finger: CGPoint, viewport: CGRect,
                           edge: Double = Viewport.edgeBand, maxSpeed: Double = Viewport.edgeMaxSpeed) -> CGVector {
        guard edge > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        func speed(_ distance: Double) -> Double {
            let depth = min(max(edge - distance, 0), edge)
            let share = depth / edge
            return maxSpeed * share * share
        }
        let x = Double(finger.x), y = Double(finger.y)
        let dx = speed(Double(viewport.maxX) - x) - speed(x - Double(viewport.minX))
        let dy = speed(Double(viewport.maxY) - y) - speed(y - Double(viewport.minY))
        return CGVector(dx: dx, dy: dy)
    }

    /// The edge scroll's top speed under Reduce Motion: half.
    static func topSpeed(reduceMotion: Bool) -> Double {
        reduceMotion ? edgeMaxSpeed / 2 : edgeMaxSpeed
    }

    /// How far a flick of the view carries, in seconds of its speed as the
    /// finger lifts: the view glides on to where it would be that long
    /// later, kept within where it may go.
    static let flingCarry = 0.2
    /// A lift slower than this, in points a second, is a lift, not a flick:
    /// the view stays where it is.
    static let flingMinSpeed = 50.0

    /// Where a view at `offset`, lifted moving at `velocity` (points a
    /// second, the way the content moves under the finger), glides to:
    /// on by flingCarry of its speed; nil when it was too slow to glide.
    static func flingTarget(offset: CGPoint, velocity: CGPoint) -> CGPoint? {
        guard Double(hypot(velocity.x, velocity.y)) > flingMinSpeed else { return nil }
        let carry = CGFloat(flingCarry)
        return CGPoint(x: offset.x - velocity.x * carry, y: offset.y - velocity.y * carry)
    }

    // MARK: typing zoom

    /// Settings ▸ Editing's "Zoom in to type small text": on unless turned
    /// off. A setting of the phone, never of the design.
    static let typingZoomKey = "canvia.typingZoom"
    /// Words drawn at least this tall on screen, in points, are read as
    /// they are: typing in them never zooms.
    static let minReadable = 14.0
    /// The size on screen typing zooms small words up to, in points.
    static let typingTarget = 18.0
    /// The room kept beside a box zoomed to for typing, in points in all.
    static let typingMargin = 48.0

    /// The zoom typing into words `fontSize` tall, in a box `box` (in page
    /// units), brings the view to, shown in `viewport` (on screen, the
    /// keyboard taken off) at `zoom`: nil when they already stand at least
    /// `minReadable` tall on screen; else the zoom that sets them `target`
    /// tall, no further in than `maxZoom`, and never so far that the box is
    /// wider than the screen less typingMargin. Nil too when that is no
    /// closer than `zoom`: typing never zooms out.
    static func typingZoom(fontSize: Double, box: CGRect, viewport: CGRect, zoom: Double,
                           minReadable: Double = Viewport.minReadable, target: Double = Viewport.typingTarget,
                           maxZoom: Double) -> Double? {
        guard fontSize > 0, fontSize * zoom < minReadable else { return nil }
        var wanted = min(target / fontSize, maxZoom)
        if box.width > 0 { wanted = min(wanted, (Double(viewport.width) - typingMargin) / Double(box.width)) }
        return wanted > zoom ? wanted : nil
    }

    /// How far above a box's bottom the middle of its last line sits, as a
    /// share of the type's size: where the caret opens without a tap.
    static let typingLastLine = 0.6

    /// The line typing zooms in on, as a y on the page: the one tapped
    /// (`tapY`), held within `box` — a tap just past its edge opens it all
    /// the same — else the last, where the caret goes without a tap, its
    /// middle `typingLastLine` of `fontSize` above the box's bottom (and
    /// never above its top). The same rule on both phones.
    static func typingLine(box: CGRect, fontSize: Double, tapY: Double?) -> Double {
        let line = tapY ?? Double(box.maxY) - fontSize * typingLastLine
        return max(Double(box.minY), min(Double(box.maxY), line))
    }
}
