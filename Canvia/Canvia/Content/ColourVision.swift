// The design as people with a colour vision deficiency see it — Check
// accessibility's "View as" and its colourVision findings — on both phones
// by one rule: Machado, Oliveira and Fernandes (2009) at severity 1.0 for
// protanopia, deuteranopia and tritanopia, and greyscale (the luminance,
// 0.2126 R + 0.7152 G + 0.0722 B) for achromatopsia, each a 3 × 3 matrix
// applied to linear sRGB: a colour is made linear (the sRGB curve, 0.04045),
// multiplied, clamped to 0…1, made sRGB again and rounded to 0…255. The
// Android twin's ColourVision.

import Foundation

enum ColourVision {

    /// A way of seeing, by the key both phones give it, in the View as
    /// row's order.
    enum Sight: String, CaseIterable, Identifiable {
        case typical, protanopia, deuteranopia, tritanopia, achromatopsia
        var id: String { rawValue }

        /// What the View as row says.
        var label: String {
            switch self {
            case .typical: return tr("Typical")
            case .protanopia: return tr("Red-blind")
            case .deuteranopia: return tr("Green-blind")
            case .tritanopia: return tr("Blue-blind")
            case .achromatopsia: return tr("Greyscale")
            }
        }

        /// Its matrix, rows R, G, B of linear sRGB; nil for typical sight.
        var matrix: [Double]? {
            switch self {
            case .typical:
                return nil
            case .protanopia:
                return [0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998]
            case .deuteranopia:
                return [0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881]
            case .tritanopia:
                return [1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900]
            case .achromatopsia:
                return [0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722]
            }
        }
    }

    /// The four that are checked, in the View as row's order.
    static let simulated: [Sight] = Sight.allCases.filter { $0.matrix != nil }

    /// Chart colours closer than this (CIE76 ΔE) are hard to tell apart.
    static let chartDeltaE = 10.0

    private static func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }

    private static func gamma(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    /// `hex` as `kind` sees it, "#rrggbb"; as it is for typical sight or a
    /// colour that does not read.
    static func simulate(_ hex: String, _ kind: Sight) -> String {
        guard let m = kind.matrix, let rgb = Cmyk.rgb(hex) else { return hex }
        let lin = [linear(Double(rgb.r) / 255), linear(Double(rgb.g) / 255), linear(Double(rgb.b) / 255)]
        let out: [Int] = (0..<3).map { row in
            let v = min(max(m[row * 3] * lin[0] + m[row * 3 + 1] * lin[1] + m[row * 3 + 2] * lin[2], 0), 1)
            return min(max(Int((gamma(v) * 255).rounded()), 0), 255)
        }
        return String(format: "#%02x%02x%02x", out[0], out[1], out[2])
    }

    /// CIE76 ΔE between two colours, in CIELAB under D65.
    static func deltaE(_ a: String, _ b: String) -> Double {
        guard let ra = Cmyk.rgb(a), let rb = Cmyk.rgb(b) else { return 0 }
        let la = Cmyk.lab([Double(ra.r) / 255, Double(ra.g) / 255, Double(ra.b) / 255])
        let lb = Cmyk.lab([Double(rb.r) / 255, Double(rb.g) / 255, Double(rb.b) / 255])
        return sqrt((0..<3).reduce(0.0) { $0 + pow(la[$1] - lb[$1], 2) })
    }

    /// A text that reads typically but not as some see it: the contrast
    /// finding Fix colour mends (ContrastAudit.fixed), its ratio the worst
    /// simulated, and the ways of seeing it fails in.
    struct TextFinding: Equatable {
        var contrast: ContrastAudit.Finding
        var kinds: [Sight]
    }

    /// A chart's two series that look alike as some see them: the chart's
    /// first element, the two series (by their n), and the ways.
    struct ChartFinding: Equatable {
        var pageIndex: Int
        var elementId: String
        var first: Int
        var second: Int
        var kinds: [Sight]
    }

    /// Each text on a shown page that passes the contrast check
    /// (ContrastAudit: the same texts, backdrop and threshold) but falls
    /// below its threshold when ink and backdrop, as drawn, are both seen as
    /// one of `simulated` sees them — page by page, bottom layer first.
    static func textFindings(_ design: Design) -> [TextFinding] {
        var out: [TextFinding] = []
        for (p, page) in design.pages.enumerated() where page.hidden != true {
            for el in page.elements where el.type == .text && el.textFill == nil && el.opacity > 0.05 && !el.isHidden {
                let back = ContrastAudit.backdrop(for: el, in: page)
                let ink = ContrastAudit.drawn(el.color ?? "#1f2430", over: back, opacity: el.opacity)
                let need = ContrastAudit.required(for: el)
                guard ContrastAudit.ratio(ink, back) >= need else { continue }
                let ratios = simulated.map { ContrastAudit.ratio(simulate(ink, $0), simulate(back, $0)) }
                let failing = simulated.indices.filter { ratios[$0] < need }
                guard let worst = failing.map({ ratios[$0] }).min() else { continue }
                let words = RichText.strip(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let finding = ContrastAudit.Finding(pageIndex: p, elementId: el.id, text: words, ratio: worst,
                                                    required: need, backdrop: back,
                                                    suggestion: suggestion(on: back, need: need))
                out.append(TextFinding(contrast: finding, kinds: failing.map { simulated[$0] }))
            }
        }
        return out
    }

    /// A chart mark's colour: a solid colour, or a gradient's first.
    private static func hex(of paint: Paint) -> String? {
        let colour: String?
        switch paint.kind {
        case "solid": colour = paint.color
        case "gradient": colour = paint.stops?.first?.color ?? paint.color
        default: colour = nil
        }
        guard let colour, Cmyk.rgb(colour) != nil else { return nil }
        return colour
    }

    /// Each pair of a chart's series — on a shown page, its solid colours or
    /// a gradient's first — at least chartDeltaE apart as drawn but closer
    /// as one of `simulated` sees them, the chart named by its bottom
    /// element; charts in the order their first element is, series in
    /// order, pairs (1, 2), (1, 3), (2, 3)…
    static func chartFindings(_ design: Design) -> [ChartFinding] {
        var out: [ChartFinding] = []
        for (p, page) in design.pages.enumerated() where page.hidden != true {
            let shown = page.elements.filter { !$0.isHidden }
            var order: [String] = []
            var members: [String: [Element]] = [:]
            for el in shown {
                guard let id = el.chart?.id else { continue }
                if members[id] == nil { order.append(id) }
                members[id, default: []].append(el)
            }
            for id in order {
                let parts = members[id] ?? []
                var colours: [Int: String] = [:]
                for el in parts {
                    guard let n = DesignStore.chartSeries(el.chartPart), colours[n] == nil,
                          let paint = DesignStore.chartColour(of: el) else { continue }
                    if let c = hex(of: paint) { colours[n] = c }
                }
                let series = colours.keys.sorted()
                for i in series.indices {
                    for j in series.indices where j > i {
                        let ca = colours[series[i]] ?? "", cb = colours[series[j]] ?? ""
                        if deltaE(ca, cb) < chartDeltaE { continue }
                        let kinds = simulated.filter { deltaE(simulate(ca, $0), simulate(cb, $0)) < chartDeltaE }
                        if !kinds.isEmpty, let first = parts.first {
                            out.append(ChartFinding(pageIndex: p, elementId: first.id,
                                                    first: series[i], second: series[j], kinds: kinds))
                        }
                    }
                }
            }
        }
        return out
    }

    /// The ink Fix colour gives a text that reads typically but not as some
    /// see it: the first of ContrastAudit's suggestion, the other of near
    /// black and white, black and white, that passes `need` on `back` as it
    /// is and in every one of `simulated`; else whichever reads best at its
    /// worst.
    static func suggestion(on back: String, need: Double) -> String {
        let first = ContrastAudit.suggestion(on: back, need: need)
        var inks: [String] = []
        for ink in [first, first == "#ffffff" ? "#16181d" : "#ffffff", "#000000", "#ffffff"] where !inks.contains(ink) {
            inks.append(ink)
        }
        func worst(_ ink: String) -> Double {
            ([Sight.typical] + simulated).map { ContrastAudit.ratio(simulate(ink, $0), simulate(back, $0)) }.min() ?? 0
        }
        if let passing = inks.first(where: { worst($0) >= need }) { return passing }
        var best = inks[0]
        for ink in inks.dropFirst() where worst(ink) > worst(best) { best = ink }
        return best
    }

    /// "Red-blind, Greyscale": the ways named, in the row's order.
    static func names(_ kinds: [Sight]) -> String {
        kinds.map(\.label).joined(separator: ", ")
    }

    /// What View as says to VoiceOver as it changes.
    static func announcement(_ kind: Sight) -> String {
        kind == .typical ? tr("Showing the design as it is") : tr("Showing the design as seen %@", kind.label)
    }

    /// The canvas's colour matrix for `kind` as CIColorMatrix's R, G and B
    /// vectors: Core Image works in linear light, so these are the same
    /// rows, applied as the check applies them. The preview only, never
    /// the check.
    static func previewVectors(_ kind: Sight) -> [[Double]]? {
        guard let m = kind.matrix else { return nil }
        return [[m[0], m[1], m[2], 0], [m[3], m[4], m[5], 0], [m[6], m[7], m[8], 0]]
    }
}
