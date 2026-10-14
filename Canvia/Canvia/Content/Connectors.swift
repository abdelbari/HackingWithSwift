// Connectors: lines that hold on to the two elements they join.
//
// A connector is an ordinary line element that remembers the ids of its
// ends. Every time the design changes, the store lays the line again from
// the edge of one to the edge of the other, so an org chart or a flow
// diagram keeps its arrows when the boxes move. An end that is deleted
// lets go: the line stays where it was as a plain line. An elbowed or
// curved connector takes the same two ends on its own route
// (LineRoutes.withEnds); a line tied by one end only — an end dragged onto
// an element — keeps that end on the element's edge, toward its free end,
// which stays where it is. As the Android twin lays them.

import CoreGraphics
import Foundation

enum Connectors {

    /// Where the ray from the rect's centre toward `target` leaves the rect
    /// — the point an arrow should start or end at.
    static func anchor(of rect: CGRect, toward target: CGPoint) -> CGPoint {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - c.x, dy = target.y - c.y
        guard dx != 0 || dy != 0 else { return c }
        let tx = dx == 0 ? Double.infinity : abs(rect.width / 2 / dx)
        let ty = dy == 0 ? Double.infinity : abs(rect.height / 2 / dy)
        let t = min(tx, ty, 1)
        return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
    }

    /// The box and rotation of a straight line from the edge of `a` to the
    /// edge of `b`: the box is centred on the midpoint, as long as the
    /// distance, at least 8 tall, and turned to point from a to b.
    static func geometry(from a: CGRect, to b: CGRect, thickness: Double) -> (x: Double, y: Double, w: Double, h: Double, rotation: Double) {
        let ca = CGPoint(x: a.midX, y: a.midY), cb = CGPoint(x: b.midX, y: b.midY)
        let start = anchor(of: a, toward: cb), end = anchor(of: b, toward: ca)
        let dx = end.x - start.x, dy = end.y - start.y
        let w = max(hypot(dx, dy), 1)
        let h = max(8, thickness)
        var rotation = atan2(dy, dx) * 180 / .pi
        rotation = (rotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return (x: (start.x + end.x) / 2 - w / 2, y: (start.y + end.y) / 2 - h / 2, w: w, h: h,
                rotation: (rotation * 10).rounded() / 10)
    }

    /// `line` laid from the edge of `a` to the edge of `b`: straight, as
    /// geometry lays it; elbowed or curved, on its route between the same
    /// two ends.
    static func laid(_ line: Element, from a: CGRect, to b: CGRect) -> Element {
        var out = line
        if LineRoutes.keepsLevel(line) {
            let start = anchor(of: a, toward: CGPoint(x: b.midX, y: b.midY))
            let end = anchor(of: b, toward: CGPoint(x: a.midX, y: a.midY))
            return LineRoutes.withEnds(line, start, end)
        }
        let g = geometry(from: a, to: b, thickness: line.thickness ?? 4)
        out.x = g.x
        out.y = g.y
        out.w = g.w
        out.h = g.h
        out.rotation = g.rotation
        return out
    }

    /// A line tied by its start (or, not `atStart`, its end) alone: that
    /// end where the ray from `box`'s centre toward the free end leaves it,
    /// the free end where it is. Itself when the tied end is there already,
    /// so laying it again changes nothing.
    static func laidFrom(_ line: Element, box: CGRect, atStart: Bool) -> Element {
        let now = LineRoutes.ends(of: line)
        let free = atStart ? now.end : now.start
        let held = anchor(of: box, toward: free)
        let tied = atStart ? now.start : now.end
        if Double(hypot(held.x - tied.x, held.y - tied.y)) < 1e-6 { return line }
        return atStart ? LineRoutes.withEnds(line, held, free) : LineRoutes.withEnds(line, free, held)
    }

    /// Lays every connector on the page again. Returns whether anything moved.
    @discardableResult
    static func resolve(_ page: inout Page) -> Bool {
        var changed = false
        let byId = Dictionary(page.elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in page.elements.indices {
            let el = page.elements[i]
            guard el.type == .line, el.connectFrom != nil || el.connectTo != nil else { continue }
            let from = el.connectFrom.flatMap { byId[$0] }.flatMap { $0.id == el.id ? nil : $0 }
            let to = el.connectTo.flatMap { byId[$0] }.flatMap { $0.id == el.id ? nil : $0 }
            var next = el
            if el.connectFrom != nil && el.connectTo != nil {
                if let from, let to {
                    next = laid(el, from: from.frame, to: to.frame)
                } else {
                    // An end is gone: the line lets go and stays put.
                    next.connectFrom = nil
                    next.connectTo = nil
                }
            } else if el.connectFrom != nil {
                // Tied by one end: it follows that, or lets go of it if gone.
                next = from.map { laidFrom(el, box: $0.frame, atStart: true) }
                    ?? LineRoutes.tied(el, atStart: true, to: nil)
            } else {
                next = to.map { laidFrom(el, box: $0.frame, atStart: false) }
                    ?? LineRoutes.tied(el, atStart: false, to: nil)
            }
            if next != el {
                page.elements[i] = next
                changed = true
            }
        }
        return changed
    }

    static func resolve(in design: inout Design) {
        for p in design.pages.indices { resolve(&design.pages[p]) }
    }
}
