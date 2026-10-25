// What VoiceOver says about an element on the canvas, and what it can do
// to it.
//
// The hit areas are plain rectangles with gestures on them; to VoiceOver
// that is a page of unlabelled buttons. Each one gets a name that says what
// it is (and, for text, what it says), a value that says where it is and
// how big, and the edits that otherwise need a drag: move, delete,
// duplicate, layer order. All pure functions of the element, so the words
// are testable.

import Foundation

enum CanvasAccessibility {

    /// Alt text when there is some; the name given it in Layers; "Empty
    /// text" for a box with no words; otherwise the same name the Layers
    /// sheet and the snap guides use — "Heading: SALE", "Red oval", "Blue
    /// line", "QR code", "Empty photo frame" — a line with words on it
    /// "Line, labelled Yes" — as the Android twin names its TalkBack
    /// nodes. A part of a chart is its chart's summary, and a table's cell,
    /// among the page's `elements`, says where it is and under which header
    /// (DataGraphics.spokenCell).
    static func label(for el: Element, on elements: [Element] = []) -> String {
        // A chart is one thing to a reader, named by its summary; its parts'
        // own alt text is what Next value and Previous value step through.
        if let chart = ChartSpeech.summary(of: el) { return chart }
        if let alt = el.altText?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
            return alt
        }
        if let own = LayerNames.custom(of: el) { return own }
        if let cell = el.table, let words = DataGraphics.spokenCell(elements, id: cell.id, row: cell.row, col: cell.col) {
            return words
        }
        if el.type == .text, RichText.strip(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tr("Empty text")
        }
        // A line with words on it: "Line, labelled Yes" (LineLabels).
        if let labelled = LineLabels.spoken(el) { return labelled }
        return ElementNames.name(of: el)
    }

    /// Position and size as percentages of the page: "at 12% across, 40%
    /// down; 50% wide, 30% tall". Pixels would be true and meaningless.
    static func value(for el: Element, design: Design) -> String {
        let w = max(design.width, 1), h = max(design.height, 1)
        func pct(_ v: Double, of total: Double) -> String { "\(Int((v / total * 100).rounded()))%" }
        var parts = [
            tr("at %@ across, %@ down", pct(el.x, of: w), pct(el.y, of: h)),
            tr("%@ wide, %@ tall", pct(el.w, of: w), pct(el.h, of: h)),
        ]
        let turn = Int(el.rotation.rounded()) % 360
        if turn != 0 { parts.append(trn("rotated %d degrees|rotated %d degrees", turn)) }
        if el.locked { parts.append(tr("locked")) } else if el.lockPosition == true { parts.append(tr("position locked")) }
        // Its link to a page, as Links.spoken reads it: "Link to page 3, Pricing".
        if let link = el.link, let said = Links.spoken(link, in: design) {
            parts.append(said)
        }
        return parts.joined(separator: "; ")
    }

    /// One step of a nudge action, in page units: a hundredth of the page's
    /// longer side, so it means the same thing on a business card and a
    /// poster.
    static func nudge(for design: Design) -> Double {
        (max(design.width, design.height) / 100).rounded()
    }
}

extension CanvasAccessibility {
    /// The elements of `elements` that stand for their chart to VoiceOver:
    /// of each chart, the part read first in `order`. The chart's other
    /// parts are hidden from it, so the chart is one stop — as the Android
    /// twin groups a chart's members into one node.
    static func chartStops(_ elements: [Element], order: [String]) -> (heads: Set<String>, hidden: Set<String>) {
        var heads: Set<String> = []
        var hidden: Set<String> = []
        var seen: Set<String> = []
        let byId = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in order {
            guard let el = byId[id], let chart = el.chart?.id, el.chartPart != nil else { continue }
            if seen.insert(chart).inserted { heads.insert(id) } else { hidden.insert(id) }
        }
        return (heads, hidden)
    }

    /// The labels Next value and Previous value step through on chart
    /// `id`: its series parts' alt text, in the page's order
    /// (ChartSpeech.stops).
    static func values(ofChart id: String, in elements: [Element]) -> [String] {
        ChartSpeech.stops(elements.filter { $0.chart?.id == id })
    }

    /// The stop after (or before) `current` among `count`, from the first
    /// (or last) when none is current; held at the ends.
    static func steppedValue(_ current: Int?, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return forward ? 0 : count - 1 }
        return min(max(current + (forward ? 1 : -1), 0), count - 1)
    }
}

extension CanvasAccessibility {
    /// The order a sighted reader takes the page in — rows top to bottom,
    /// left to right within a row — so VoiceOver reads it the same way
    /// rather than in the order things were added. Elements whose tops are
    /// within a twelfth of the page height of the row's first share a row.
    static func readingOrder(_ elements: [Element], pageHeight: Double) -> [String] {
        let tolerance = max(pageHeight, 1) / 12
        let byTop = elements.sorted { a, b in a.y != b.y ? a.y < b.y : a.x < b.x }
        var rows: [[Element]] = []
        for el in byTop {
            if let last = rows.last, let head = last.first, abs(el.y - head.y) <= tolerance {
                rows[rows.count - 1].append(el)
            } else {
                rows.append([el])
            }
        }
        return rows.flatMap { row in row.sorted { a, b in a.x != b.x ? a.x < b.x : a.y < b.y } }.map(\.id)
    }
}

extension CanvasAccessibility {
    /// How much Make larger and Make smaller change an element: a tenth.
    static let sizeStep = 0.1
    /// How far Turn clockwise and Turn anticlockwise turn it, in degrees.
    static let turnStep = 15.0

    /// `el` made larger (or smaller) by `sizeStep` about its centre, by one
    /// factor for every side, as the Android twin's
    /// Resize.scaledAboutCentre: a text's type scales with its box, and its
    /// tracking with it; a photo, a shape, anything else keeps its
    /// proportions, and a photo its crop; a line grows along its length and
    /// keeps its thickness. The factor stops where a side would go under 8
    /// (a line's length only) or the type under 4, so nothing is squashed
    /// out of shape, and smaller never makes something larger; nil when it
    /// is there already.
    static func scaled(_ el: Element, larger: Bool) -> Element? {
        guard el.w > 0, el.h > 0 else { return nil }
        var least = 8 / el.w
        if el.type != .line { least = max(least, 8 / el.h) }
        if el.type == .text { least = max(least, 4 / (el.fontSize ?? 42)) }
        var factor = max(larger ? 1 + sizeStep : 1 - sizeStep, least)
        if !larger { factor = min(factor, 1) }
        guard factor != 1 else { return nil }
        let w = el.w * factor
        let h = el.type == .line ? el.h : el.h * factor
        let c = el.center
        var out = el
        out.w = w
        out.h = h
        out.x = c.x - w / 2
        out.y = c.y - h / 2
        if el.type == .text {
            out.fontSize = (el.fontSize ?? 42) * factor
            out.letterSpacing = el.letterSpacing.map { $0 * factor }
        }
        return out
    }

    /// A turn of `turnStep` clockwise (or anticlockwise) from `rotation`,
    /// landing on a multiple of it: 7° goes to 15° clockwise and to 0°
    /// anticlockwise. In 0..<360.
    static func turned(_ rotation: Double, clockwise: Bool) -> Double {
        let steps = rotation / turnStep
        // Within a billionth of a step of a multiple, it is on it, as on the
        // Android twin (Geometry.turnStep).
        let next = clockwise ? (steps + 1e-9).rounded(.down) + 1 : (steps - 1e-9).rounded(.up) - 1
        let degrees = next * turnStep
        return (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
}
