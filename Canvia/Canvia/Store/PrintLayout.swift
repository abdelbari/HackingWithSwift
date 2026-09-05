// Paper: fitting a page onto a sheet, printing at actual size, tiling a
// poster across sheets, and the marks a print shop wants.
//
// A design is pixels at 96 dpi; paper is points at 72. Fit shrinks or grows
// the page to the printable area; actual size prints it at its true
// dimensions and, when that is bigger than the sheet, tiles it with an
// overlap so the pieces can be trimmed and joined. Bleed extends the page
// outward and crop marks show where to cut.

import CoreGraphics
import Foundation

enum PrintLayout {

    struct Paper: Identifiable, Hashable {
        var id: String
        var name: String
        /// Points, portrait.
        var size: CGSize
    }

    static let papers: [Paper] = [
        Paper(id: "a4", name: "A4", size: CGSize(width: 595, height: 842)),
        Paper(id: "a3", name: "A3", size: CGSize(width: 842, height: 1191)),
        Paper(id: "letter", name: "US Letter", size: CGSize(width: 612, height: 792)),
        Paper(id: "tabloid", name: "Tabloid", size: CGSize(width: 792, height: 1224)),
    ]

    enum Fit: String, CaseIterable, Identifiable {
        case fit, actual, tile
        var id: String { rawValue }
        var name: String {
            switch self {
            case .fit: return "Fit to paper"
            case .actual: return "Actual size"
            case .tile: return "Tile a poster"
            }
        }
    }

    struct Options: Equatable {
        var paper = papers[0]
        var landscape = false
        var fit = Fit.fit
        /// Points around the sheet a printer cannot reach.
        var margin: Double = 18
        /// Points of bleed beyond the page, printed and marked.
        var bleed: Double = 0
        var cropMarks = false
        /// Points of overlap between tiles.
        var overlap: Double = 18

        var sheet: CGSize {
            landscape ? CGSize(width: paper.size.height, height: paper.size.width) : paper.size
        }
        var printable: CGRect {
            CGRect(x: margin, y: margin, width: sheet.width - 2 * margin, height: sheet.height - 2 * margin)
        }
    }

    /// The design page in points, bleed included.
    static func pagePoints(design: Design, bleed: Double) -> CGSize {
        pagePoints(size: design.size, bleed: bleed)
    }

    static func pagePoints(size: CGSize, bleed: Double) -> CGSize {
        CGSize(width: size.width * DesignExporter.pxToPt + 2 * bleed,
               height: size.height * DesignExporter.pxToPt + 2 * bleed)
    }

    /// Where the page lands on the sheet when fitted: centred, as large as
    /// the printable area allows.
    static func fitRect(page: CGSize, in printable: CGRect) -> CGRect {
        let scale = min(printable.width / max(page.width, 1), printable.height / max(page.height, 1))
        let w = page.width * scale, h = page.height * scale
        return CGRect(x: printable.midX - w / 2, y: printable.midY - h / 2, width: w, height: h)
    }

    /// The pieces of a page too big for one sheet, in page points: each is
    /// the region of the page one sheet carries, overlapping its neighbours
    /// by `overlap`. Row-major, top-left first.
    static func tiles(page: CGSize, printable: CGSize, overlap: Double) -> [CGRect] {
        let stepW = max(printable.width - overlap, 1), stepH = max(printable.height - overlap, 1)
        let cols = max(1, Int(ceil((page.width - overlap) / stepW)))
        let rows = max(1, Int(ceil((page.height - overlap) / stepH)))
        var out: [CGRect] = []
        for r in 0..<rows {
            for c in 0..<cols {
                out.append(CGRect(x: Double(c) * stepW, y: Double(r) * stepH,
                                  width: printable.width, height: printable.height))
            }
        }
        return out
    }

    /// Crop marks: short lines outside each corner of `rect`, `gap` away.
    static func cropMarkSegments(around rect: CGRect, length: Double = 14, gap: Double = 4) -> [(CGPoint, CGPoint)] {
        var s: [(CGPoint, CGPoint)] = []
        for (x, dir) in [(rect.minX, -1.0), (rect.maxX, 1.0)] {
            for y in [rect.minY, rect.maxY] {
                s.append((CGPoint(x: x + dir * gap, y: y), CGPoint(x: x + dir * (gap + length), y: y)))
            }
        }
        for (y, dir) in [(rect.minY, -1.0), (rect.maxY, 1.0)] {
            for x in [rect.minX, rect.maxX] {
                s.append((CGPoint(x: x, y: y + dir * gap), CGPoint(x: x, y: y + dir * (gap + length))))
            }
        }
        return s
    }
}
