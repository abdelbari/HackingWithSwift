// Connectors: lines that hold on to the two elements they join.
//
// A connector is an ordinary line element that remembers the ids of its
// ends. Every time the design changes, the store lays the line again from
// the edge of one to the edge of the other, so an org chart or a flow
// diagram keeps its arrows when the boxes move. An end that is deleted
// lets go: the line stays where it was as a plain line.

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

    /// Lays every connector on the page again. Returns whether anything moved.
    @discardableResult
    static func resolve(_ page: inout Page) -> Bool {
        var changed = false
        let byId = Dictionary(page.elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in page.elements.indices {
            let el = page.elements[i]
            guard el.type == .line, el.connectFrom != nil || el.connectTo != nil else { continue }
            guard let fromId = el.connectFrom, let toId = el.connectTo,
                  let from = byId[fromId], let to = byId[toId], from.id != el.id, to.id != el.id else {
                // An end is gone: the line lets go and stays put.
                page.elements[i].connectFrom = nil
                page.elements[i].connectTo = nil
                changed = true
                continue
            }
            let g = geometry(from: from.frame, to: to.frame, thickness: el.thickness ?? 4)
            if el.x != g.x || el.y != g.y || el.w != g.w || el.h != g.h || el.rotation != g.rotation {
                page.elements[i].x = g.x
                page.elements[i].y = g.y
                page.elements[i].w = g.w
                page.elements[i].h = g.h
                page.elements[i].rotation = g.rotation
                changed = true
            }
        }
        return changed
    }

    static func resolve(in design: inout Design) {
        for p in design.pages.indices { resolve(&design.pages[p]) }
    }
}
