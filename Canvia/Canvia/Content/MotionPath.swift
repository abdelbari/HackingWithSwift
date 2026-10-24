// Animate's Create: an element held and dragged round its page, recorded as
// the path it then plays along (ElementAnimation's "path") — the Android
// twin's MotionPath, rule for rule.
//
// The element is left where the finger lifts, and that is where it rests:
// the path is kept from there, so it plays from where the drag began to
// where it ended and settles, as every entrance does.

import Foundation

enum MotionPath {

    /// One point of a path: page units from the element's resting centre,
    /// and how far through the path it is passed, 0 to 1.
    struct Point: Equatable {
        var dx: Double
        var dy: Double
        var t: Double
    }

    /// One moment of a drag: where the element's centre was on the page,
    /// and when, in seconds.
    struct Sample: Equatable {
        var x: Double
        var y: Double
        var time: Double
    }

    /// A point as a file keeps it, `[dx, dy, t]`: none when it is not three
    /// numbers, t kept within 0…1.
    struct Reading: Decodable {
        var point: Point?

        init(from decoder: Decoder) throws {
            let xs = (try? [Double](from: decoder)) ?? []
            guard xs.count >= 3, xs.prefix(3).allSatisfy(\.isFinite) else { return }
            point = Point(dx: xs[0], dy: xs[1], t: min(max(xs[2], 0), 1))
        }
    }

    /// How near each other two kept points may be, in page units.
    static let minGap = 2.0
    /// The most points a path keeps.
    static let maxPoints = 200
    /// The speeds its slider offers.
    static let minSpeed = 0.25
    static let maxSpeed = 4.0
    /// The shortest and longest a recorded path plays, in seconds.
    static let minSeconds = 0.3
    static let maxSeconds = 10.0

    /// A drag's `samples` as a path:
    /// - thinned — the first kept, then each at least minGap from the last
    ///   kept; the last always kept, taking the place of the one before it
    ///   when that is nearer than minGap;
    /// - at most maxPoints, picked evenly by place in the list (the
    ///   nearest, halves up) when there are more;
    /// - each from the last sample — where the element rests — to the
    ///   hundredth, with t its time since the first over the whole drag's,
    ///   to the thousandth (by place in the list when the drag took no time).
    /// Empty when fewer than two points are left: a drag that went nowhere.
    static func recorded(_ samples: [Sample]) -> [Point] {
        guard samples.count >= 2, let end = samples.last else { return [] }
        var kept = [samples[0]]
        // Indices into `samples`, so the last is known by place.
        var keptLast = 0
        for i in 1..<samples.count {
            let s = samples[i], last = kept[kept.count - 1]
            if hypot(s.x - last.x, s.y - last.y) >= minGap {
                kept.append(s)
                keptLast = i
            }
        }
        if keptLast != samples.count - 1 {
            let last = kept[kept.count - 1]
            if kept.count > 1 && hypot(end.x - last.x, end.y - last.y) < minGap {
                kept[kept.count - 1] = end
            } else {
                kept.append(end)
            }
        }
        guard kept.count >= 2 else { return [] }
        // Too short to travel at all: back where it began.
        if kept.count == 2 && hypot(end.x - kept[0].x, end.y - kept[0].y) < minGap { return [] }
        let picked: [Sample]
        if kept.count <= maxPoints {
            picked = kept
        } else {
            let span = Double(kept.count - 1)
            picked = (0..<maxPoints).map { i in kept[Int((Double(i) * span / Double(maxPoints - 1) + 0.5).rounded(.down))] }
        }
        let t0 = picked[0].time
        let elapsed = picked[picked.count - 1].time - t0
        return picked.enumerated().map { i, s in
            let t = elapsed > 0 ? (s.time - t0) / elapsed : Double(i) / Double(picked.count - 1)
            return Point(dx: hundredth(s.x - end.x), dy: hundredth(s.y - end.y), t: thousandth(min(max(t, 0), 1)))
        }
    }

    /// How long a recorded path plays at speed 1: the drag's own time, to a
    /// tenth, within minSeconds…maxSeconds.
    static func seconds(_ samples: [Sample]) -> Double {
        let elapsed = samples.count < 2 ? 0 : samples[samples.count - 1].time - samples[0].time
        return min(max((elapsed * 10 + 0.5).rounded(.down) / 10, minSeconds), maxSeconds)
    }

    /// A speed as its slider leaves it: to the quarter, within
    /// minSpeed…maxSpeed.
    static func speed(_ value: Double) -> Double {
        min(max((value * 4).rounded() / 4, minSpeed), maxSpeed)
    }

    /// Whether `points` hold a path that goes somewhere.
    static func travels(_ points: [Point]?) -> Bool {
        guard let points, points.count >= 2 else { return false }
        return points.contains { hypot($0.dx - points[0].dx, $0.dy - points[0].dy) >= minGap }
    }

    /// The furthest a path takes the element from rest, for fitting a preview.
    static func reach(_ points: [Point]) -> Double {
        points.map { max(abs($0.dx), abs($0.dy)) }.max() ?? 0
    }

    /// A speed as its slider shows it: "1x", "0.25x", "2.5x".
    static func speedLabel(_ speed: Double) -> String {
        var s = String(format: "%.2f", speed)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s + "x"
    }

    private static func hundredth(_ v: Double) -> Double { (v * 100 + 0.5).rounded(.down) / 100 }
    private static func thousandth(_ v: Double) -> Double { (v * 1000 + 0.5).rounded(.down) / 1000 }
}
