// How the view moves on its own while a finger works the canvas: the edge
// scroll that carries a dragged thing past the edge of the screen, and how
// far a flick of the view glides on. Both phones share these rules and test
// rows (the Android twin's Viewport.edgeScroll and Viewport.flingCarry).

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
}
