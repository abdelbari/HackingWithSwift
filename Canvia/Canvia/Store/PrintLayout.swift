// Paper: fitting a page onto a sheet, printing at actual size, tiling a
// poster across sheets, and the marks a print shop wants.
//
// A design is pixels at its own dpi — 96 when it has none; paper is points
// at 72. Fit shrinks or grows
// the page to the printable area; actual size prints it at its true
// dimensions and, when that is bigger than the sheet, tiles it with an
// overlap so the pieces can be trimmed and joined. Bleed extends the page
// outward — the design's own, drawn into (Bleed), or the page enlarged to
// make one — and crop marks show where to cut. Several to a sheet sets
// small pages — business cards, labels, stickers — at actual size in a
// centred grid with crop marks shared along every trim line, a back page
// mirrored for long-edge flip when printed double-sided.

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
        Paper(id: "a5", name: "A5", size: CGSize(width: 420, height: 595)),
        Paper(id: "legal", name: "Legal", size: CGSize(width: 612, height: 1008)),
        Paper(id: "photo-4x6", name: "Photo 4×6", size: CGSize(width: 288, height: 432)),
        Paper(id: "photo-5x7", name: "5×7", size: CGSize(width: 360, height: 504)),
    ]

    /// The raw values are the shared print JSON's "fit".
    enum Fit: String, CaseIterable, Identifiable {
        case fit, actual, tile, several
        var id: String { rawValue }
        var name: String {
            switch self {
            case .fit: return "Fit to paper"
            case .actual: return "Actual size"
            case .tile: return "Tile a poster"
            case .several: return "Several to a sheet"
            }
        }
    }

    /// What Several to a sheet fills a sheet with.
    enum Several: String, CaseIterable, Identifiable {
        /// One page, as many times as fit: a sheet a page.
        case repeatPage
        /// The chosen pages in order, one each, as many sheets as it takes.
        case oneOfEach
        var id: String { rawValue }
        var name: String { self == .repeatPage ? "Repeat this page" : "One of each" }
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
        /// Several to a sheet: one page repeated, or one of each.
        var several = Several.repeatPage
        /// Points between neighbouring pages on a sheet of several; nil is
        /// the default, `gapPoints`.
        var gap: Double?
        /// Several to a sheet on both sides: a design of two pages prints
        /// its second on the back, its columns mirrored for long-edge flip.
        var duplex = false

        /// The gap used: as set, else none without bleed and twice the
        /// bleed with it, so neighbours' bleeds never overlap.
        var gapPoints: Double { max(0, gap ?? (bleed > 0 ? 2 * bleed : 0)) }

        var sheet: CGSize {
            landscape ? CGSize(width: paper.size.height, height: paper.size.width) : paper.size
        }
        var printable: CGRect {
            CGRect(x: margin, y: margin, width: sheet.width - 2 * margin, height: sheet.height - 2 * margin)
        }
    }

    /// PDF points per page pixel: 72 / the design's dpi, and 72 / 96 for a
    /// design with none — exactly what every PDF came out at before units.
    /// The plain PDF, the print PDF and the PDF's links all go by it, so an
    /// A4 page at 300 dpi is a 595 × 842 pt page.
    static func pxToPt(_ design: Design) -> Double {
        design.pointsPerPixel
    }

    /// The design page in points, bleed included.
    static func pagePoints(design: Design, bleed: Double) -> CGSize {
        pagePoints(size: design.size, dpi: design.effectiveDPI, bleed: bleed)
    }

    /// A page of `size` pixels at `dpi` in points: at 96 unless told.
    static func pagePoints(size: CGSize, dpi: Double = Units.screenDPI, bleed: Double) -> CGSize {
        let scale = Units.pointsPerPixel(dpi: dpi)
        return CGSize(width: Double(size.width) * scale + 2 * bleed,
                      height: Double(size.height) * scale + 2 * bleed)
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

    /// The crop marks one sheet carries: at the page's trim — the bled page
    /// less its bleed — mapped onto the sheet, and on a tiled poster only at
    /// the trim corners this tile holds, so an inner tile has none and no
    /// mark lands on blank paper. The Android twin's `sheetMarks`.
    static func sheetMarks(sheet: CGRect, source: CGRect, page: CGSize, bleed: Double) -> [(CGPoint, CGPoint)] {
        let scale = sheet.width / max(source.width, 1)
        let trim = trimOnSheet(sheet: sheet, source: source, page: page, bleed: bleed)
        let slack = 0.5
        let reach = sheet.insetBy(dx: -slack, dy: -slack)
        // Clear of the printed bleed, not only of the trim: 4 pt from the
        // trim put every mark on the bleed's artwork, and from 18 pt of
        // bleed wholly inside it, where on a dark page the cutter could not
        // see it. The Android twin keeps the same gap.
        let gap = bleed * scale + 4
        return cropMarkSegments(around: trim, gap: gap).filter { segment in
            let (a, b) = segment
            // Each mark starts a gap out from its corner, along its own line.
            let across = a.y == b.y
            let corner = across
                ? CGPoint(x: a.x - (b.x > a.x ? gap : -gap), y: a.y)
                : CGPoint(x: a.x, y: a.y - (b.y > a.y ? gap : -gap))
            return corner.x >= reach.minX && corner.x <= reach.maxX && corner.y >= reach.minY && corner.y <= reach.maxY
        }
    }

    /// The page's trim — the bled page less its `bleed` — where it lands on
    /// the sheet, in sheet points from the top left.
    static func trimOnSheet(sheet: CGRect, source: CGRect, page: CGSize, bleed: Double) -> CGRect {
        let scale = sheet.width / max(source.width, 1)
        return CGRect(x: sheet.minX + (bleed - source.minX) * scale,
                      y: sheet.minY + (bleed - source.minY) * scale,
                      width: (page.width - 2 * bleed) * scale,
                      height: (page.height - 2 * bleed) * scale)
    }

    /// A sheet's TrimBox and BleedBox — where a print shop cuts, and how far
    /// its artwork runs past that — in PDF points up from the bottom of a
    /// sheet `sheetHeight` tall, for a sheet holding one whole page. None
    /// for a tile of a poster, which holds a piece. The Android twin's
    /// `boxes`, which its writer adds after the page is drawn.
    static func boxes(sheet: CGRect, source: CGRect, page: CGSize, bleed: Double,
                      sheetHeight: Double) -> (trim: CGRect, bleed: CGRect)? {
        guard source.minX == 0, source.minY == 0, source.width >= page.width, source.height >= page.height
        else { return nil }
        let trim = trimOnSheet(sheet: sheet, source: source, page: page, bleed: bleed)
        let reach = bleed * Double(sheet.width) / max(Double(source.width), 1)
        func flipped(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: CGFloat(sheetHeight) - r.maxY, width: r.width, height: r.height)
        }
        return (flipped(trim), flipped(trim.insetBy(dx: -reach, dy: -reach)))
    }

    /// How a page is drawn into its bled area in points: where its top left
    /// lands, the points a page unit takes, and what part of the page shows,
    /// in page units.
    struct Drawing: Equatable {
        var origin: CGPoint
        var scale: Double
        var clip: CGRect
    }

    /// A page of `size` drawn with `bleed` points round it. Of a design that
    /// `designed` its bleed (Bleed): at its true size, set in by the bleed,
    /// and seen out to the bleed's edge — so what was put past the trim
    /// prints in the band, and the trim is exactly the plain PDF's page.
    /// Otherwise enlarged evenly to cover the whole bled area, centred —
    /// never stretched, so a circle stays round — and cut at its own edge:
    /// the bleed a print shop makes when none was designed. The Android
    /// twin's `drawing`.
    static func drawing(size: CGSize, bleed: Double, pxToPt: Double, designed: Bool) -> Drawing {
        let w = Double(size.width), h = Double(size.height)
        if designed {
            let reach = bleed / max(pxToPt, 1e-9)
            return Drawing(origin: CGPoint(x: bleed, y: bleed), scale: pxToPt,
                           clip: CGRect(x: -reach, y: -reach, width: w + 2 * reach, height: h + 2 * reach))
        }
        let pw = w * pxToPt + 2 * bleed, ph = h * pxToPt + 2 * bleed
        let fill = max(pw / max(w, 1), ph / max(h, 1))
        return Drawing(origin: CGPoint(x: (pw - w * fill) / 2, y: (ph - h * fill) / 2), scale: fill,
                       clip: CGRect(x: 0, y: 0, width: w, height: h))
    }

    // MARK: several to a sheet

    /// The grid of pages on one sheet: a page of `page` points (its bleed
    /// in) at actual size, `gap` between neighbours. Columns are
    /// floor((printable width + gap) / (page width + gap)), and rows the
    /// same down. A page too big for even one is fitted alone onto the
    /// sheet, as Fit to paper places it — the Android twin's
    /// PrintLayout.grid. The grid is centred in the printable area; its
    /// cells come row by row, top left first.
    static func grid(page: CGSize, printable: CGRect, gap: Double) -> (cols: Int, rows: Int, cells: [CGRect]) {
        let pw = Double(page.width), ph = Double(page.height)
        let fitAcross = ((Double(printable.width) + gap) / max(pw + gap, 1e-9)).rounded(.down)
        let fitDown = ((Double(printable.height) + gap) / max(ph + gap, 1e-9)).rounded(.down)
        guard pw > 0, ph > 0, fitAcross >= 1, fitDown >= 1 else {
            return (1, 1, [fitRect(page: page, in: printable)])
        }
        let cols = Int(fitAcross), rows = Int(fitDown)
        let across = Double(cols) * pw + Double(cols - 1) * gap
        let down = Double(rows) * ph + Double(rows - 1) * gap
        let left = Double(printable.midX) - across / 2
        let top = Double(printable.midY) - down / 2
        var cells: [CGRect] = []
        for r in 0..<rows {
            for c in 0..<cols {
                cells.append(CGRect(x: left + Double(c) * (pw + gap), y: top + Double(r) * (ph + gap), width: pw, height: ph))
            }
        }
        return (cols, rows, cells)
    }

    /// Where column `column` of a front lands on its back, for long-edge
    /// flip: mirrored, so column 0 is behind column cols − 1.
    static func duplexColumn(_ column: Int, cols: Int) -> Int {
        cols - 1 - column
    }

    /// The pages on each sheet, cell by cell (`perSheet` cells a sheet), of
    /// `indices`: one page filling each sheet of its own when repeating;
    /// the pages in order, one each, when not. Double-sided with exactly
    /// two pages: the first fills the front and the second the back.
    static func severalSheets(indices: [Int], perSheet: Int, mode: Several, duplex: Bool) -> [[Int]] {
        let n = max(1, perSheet)
        guard !indices.isEmpty else { return [] }
        if duplex && indices.count == 2 {
            return indices.map { Array(repeating: $0, count: n) }
        }
        switch mode {
        case .repeatPage:
            return indices.map { Array(repeating: $0, count: n) }
        case .oneOfEach:
            return stride(from: 0, to: indices.count, by: n).map { Array(indices[$0..<min($0 + n, indices.count)]) }
        }
    }

    /// The cell page `slot` of a sheet goes in: in reading order, or on a
    /// back (`mirrored`) with its column mirrored.
    static func cellIndex(_ slot: Int, cols: Int, mirrored: Bool) -> Int {
        guard mirrored, cols > 0 else { return slot }
        let row = slot / cols, column = slot % cols
        return row * cols + duplexColumn(column, cols: cols)
    }

    /// The crop marks for a sheet of several pages: those round each trim,
    /// as cropMarkSegments draws them `gap` out from its corners, once
    /// each, left out where they would touch any page placed — its bleed
    /// included, its edge too, so none lies along a neighbour's cut — so
    /// the marks neighbours share sit only in the margins and gaps, along
    /// every trim line.
    static func gridMarks(trims: [CGRect], placed: [CGRect], gap: Double) -> [(CGPoint, CGPoint)] {
        var out: [(CGPoint, CGPoint)] = []
        for trim in trims {
            for segment in cropMarkSegments(around: trim, gap: gap) {
                let lands = placed.contains { segmentTouches(segment, $0) }
                let twice = out.contains { $0.0 == segment.0 && $0.1 == segment.1 }
                if !lands && !twice { out.append(segment) }
            }
        }
        return out
    }

    /// Whether an upright or level segment meets `rect`, its edge included.
    static func segmentTouches(_ segment: (CGPoint, CGPoint), _ rect: CGRect) -> Bool {
        let reach = rect.insetBy(dx: -0.01, dy: -0.01)
        let (a, b) = segment
        return max(a.x, b.x) > reach.minX && min(a.x, b.x) < reach.maxX
            && max(a.y, b.y) > reach.minY && min(a.y, b.y) < reach.maxY
    }

    /// "10 per sheet, 2 sheets".
    static func severalNote(perSheet: Int, sheets: Int) -> String {
        "\(perSheet) per sheet, \(sheets) \(sheets == 1 ? "sheet" : "sheets")"
    }

    /// Said under the Bleed stepper when the design has no bleed of its own,
    /// so the page is enlarged to make one.
    static let enlargedNote = "Bleed made by enlarging slightly"

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
