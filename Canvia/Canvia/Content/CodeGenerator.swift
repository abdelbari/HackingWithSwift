// QR codes, drawn on device.
//
// A design tool without one sends people to a website to make a picture and
// then back to import it — for something Core Image has generated locally
// since iOS 7. Menus, posters, business cards and event flyers all want one,
// which is most of what this app is for.
//
// Codes are not stored: the payload is the element's src ("qr:<text>"), so a
// code is regenerated from the document rather than kept as a file. That
// keeps them editable, keeps documents self-contained, and keeps resolution
// synchronous and deterministic, which is what lets ElementView stay
// Equatable on its element.
//
// The pipeline is deliberately pixel-level rather than "draw the filter's
// output into a context and scale it up". Two attempts at that shipped codes
// that looked perfect and decoded as nothing, because drawing carries two
// silent conventions — which way up a CGImage lands in a given context, and
// which of the two tones the generator calls "on". Neither is visible in the
// result. So the filter's output is read into a boolean grid, normalised
// against the QR standard's own structure (finder patterns are dark, and sit
// at three corners, never the fourth), and the final bitmap is written byte
// by byte. Nothing in the output path is drawn, so nothing in it can be
// mirrored or inverted.
//
// A code's look is its element's: the modules' colour, the background's
// (or none) and the margin round them (Look, the keys qrColor,
// qrBackground and qrMargin, each written only when not the default). The
// canvas, the PDF, SVG and PowerPoint draw a plain code's modules as
// rectangles (vector), as the Android twin does.

import CoreGraphics
import CoreImage
import UIKit

enum CodeGenerator {

    /// Element sources for a code carry the payload inline.
    static let prefix = "qr:"

    static func source(for payload: String) -> String { prefix + payload }

    static func payload(from source: String) -> String? {
        source.hasPrefix(prefix) ? String(source.dropFirst(prefix.count)) : nil
    }

    /// Why `text` cannot be a code — nothing to encode, or more than a code
    /// holds — or nil when it can. Said under the field while a code is
    /// edited in place, which keeps the last good code until then, in the
    /// Android twin's words. Not trimmed: a code scans as exactly what was
    /// typed.
    static func problem(with text: String) -> String? {
        if text.isEmpty { return tr("A code needs a link or some words; it keeps the last until then.") }
        if modules(for: text) == nil { return tr("Too long for a QR code; it keeps the last that fitted.") }
        return nil
    }

    /// Generated codes are small and cheap, but they are re-resolved on every
    /// canvas render, so they are worth keeping.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 32
        return c
    }()

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// A QR code for `payload`, `side` points on each edge, in `style`:
    /// black on white with the standard margin unless it says otherwise.
    ///
    /// A tinted or low-contrast code is a code that may not scan, so a look
    /// that risks it is warned of (scanRisk) where it is chosen, not refused:
    /// it is the person's to judge.
    static func qr(_ payload: String, side: CGFloat = 512, style: Look = Look()) -> UIImage? {
        guard !payload.isEmpty, side >= 1 else { return nil }
        let pixels = Int(min(max(side, 24), 2048).rounded())
        let key = "\(pixels)|\(styleKey(style))|\(payload)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let grid = modules(for: payload), let image = render(grid, side: pixels, style: style) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    // MARK: the code's look

    /// What a code's keys hold when they are not written: modules in black
    /// on white, with the standard's four modules of margin round them.
    static let defaultColor = "#000000"
    static let defaultBackground = "#ffffff"
    /// The background key's word for none: the page shows through.
    static let noBackground = "none"
    /// The quiet zone the standard asks for, and the most margin offered.
    static let quiet = 4
    /// The side of a code's picture, in pixels, which the Android twin's
    /// placement follows so a code sits the same on both phones.
    static let pictureSide = 512

    /// How a code is drawn: its modules in `color`, over `background` — nil
    /// for none, clear — with `margin` modules (0 to 4) of it round them.
    /// The Android twin's QrCodes.Style.
    struct Look: Equatable {
        var color: String = CodeGenerator.defaultColor
        var background: String? = CodeGenerator.defaultBackground
        var margin: Int = CodeGenerator.quiet
    }

    /// `el`'s code style, a key it lacks — or one that is not a colour —
    /// being the default.
    static func style(of el: Element) -> Look {
        let color = el.qrColor.flatMap(hexColor) ?? defaultColor
        var background: String? = defaultBackground
        if el.qrBackground == noBackground {
            background = nil
        } else if let paper = el.qrBackground.flatMap(hexColor) {
            background = paper
        }
        let margin = min(max(el.qrMargin ?? quiet, 0), quiet)
        return Look(color: color, background: background, margin: margin)
    }

    /// `el` in `style`, each key kept only when it is not the default — so a
    /// code in black on white with the full margin has none of them.
    static func styled(_ el: Element, _ style: Look) -> Element {
        var out = el
        out.qrColor = keptColor(style.color)
        if let paper = style.background {
            out.qrBackground = keptBackground(paper)
        } else {
            out.qrBackground = noBackground
        }
        out.qrMargin = keptMargin(Double(style.margin))
        return out
    }

    /// A `qrColor` as kept: "#rrggbb", lower case; nil for the default and
    /// for anything that is not a colour.
    static func keptColor(_ raw: String) -> String? {
        guard let hex = hexColor(raw), hex != defaultColor else { return nil }
        return hex
    }

    /// A `qrBackground` as kept: "none", or "#rrggbb" lower case; nil for
    /// the default and for anything that is neither.
    static func keptBackground(_ raw: String) -> String? {
        if raw == noBackground { return noBackground }
        guard let hex = hexColor(raw), hex != defaultBackground else { return nil }
        return hex
    }

    /// A `qrMargin` as kept: whole modules, held to 0…4 (a fraction cut
    /// off, as the Android twin reads it); nil for 4, the default, and for
    /// a number that is none.
    static func keptMargin(_ raw: Double) -> Int? {
        guard raw.isFinite else { return nil }
        let margin = Int(min(max(raw, 0), Double(quiet)))
        return margin == quiet ? nil : margin
    }

    /// "#rrggbb", lower case, or nil for what is not a colour.
    private static func hexColor(_ text: String) -> String? {
        guard let c = ColorTools.rgb255(text) else { return nil }
        return String(format: "#%02x%02x%02x", c.r, c.g, c.b)
    }

    /// What the code sheet says of a look that may not scan.
    static let scanRiskWarning = tr("This may be hard to scan")

    /// scanRiskWarning when a code in `color` over `background` — nil for
    /// none, when `pageBehind` is what shows — may not scan: the two under
    /// 3:1 apart (WCAG's contrast ratio), or the code the lighter of the
    /// two, as many scanners read only dark on light. Nil when it should
    /// scan. The Android twin's scanRisk, on the same test rows.
    static func scanRisk(color: String, background: String?, pageBehind: String) -> String? {
        let behind = background ?? pageBehind
        let faint = ContrastAudit.ratio(color, behind) < 3
        let inverted = ContrastAudit.luminance(color) > ContrastAudit.luminance(behind)
        return faint || inverted ? scanRiskWarning : nil
    }

    /// Where an `n`-module code with `margin` modules round it sits across
    /// its picture, as fractions of the side: a whole number of pixels a
    /// module, centred — the Android twin's placement, number for number.
    static func placement(_ n: Int, margin: Int = quiet) -> (from: Double, to: Double) {
        let around = 2 * min(max(margin, 0), quiet)
        let unit = max(pictureSide / max(n + around, 1), 1)
        let inset = max((pictureSide - unit * n) / 2, 0)
        return (Double(inset) / Double(pictureSide), Double(inset + unit * n) / Double(pictureSide))
    }

    /// The dark modules of `grid` as rectangles, a module a unit: each run
    /// of them along a row one rectangle, rows top down, left to right.
    static func runs(_ grid: [[Bool]]) -> [CGRect] {
        var out: [CGRect] = []
        for (y, row) in grid.enumerated() {
            var x = 0
            while x < row.count {
                guard row[x] else {
                    x += 1
                    continue
                }
                let start = x
                while x < row.count && row[x] { x += 1 }
                out.append(CGRect(x: start, y: y, width: x - start, height: 1))
            }
        }
        return out
    }

    /// A code as the canvas and the exports draw it in vectors: its
    /// `background` square — nil for none — and its dark `modules` (each
    /// run along a row one rectangle), in the element's own space (its
    /// frame's top left at 0, 0) and cut to its frame, in `style`'s colours.
    struct Vector: Equatable {
        var style: Look
        var background: CGRect?
        var modules: [CGRect]
    }

    /// `el`'s code as Vector rectangles: its picture placed in the frame as
    /// any picture is (Crop.drawnPicture of the 512-pixel square), the
    /// modules where placement puts them. Nil for anything but a code, and
    /// for a code whose look is more than its colours — a filter, a dial, a
    /// duotone, a blur, an outline or glow, pixels, a turn inside its frame,
    /// a frame shape, rounded corners or a border — which is drawn as its
    /// picture. The Android twin's QrCodes.vector.
    static func vector(_ el: Element) -> Vector? {
        guard el.type == .image, el.w > 0, el.h > 0, let payload = payload(from: el.src ?? ""),
              plainLook(el), let grid = modules(for: payload) else { return nil }
        let style = style(of: el)
        let side = Double(pictureSide)
        let picture = Crop.drawnPicture(el, image: CGSize(width: side, height: side))
        let n = grid.count
        let place = placement(n, margin: style.margin)
        let module: Double = Double(picture.width) * (place.to - place.from) / Double(n)
        let left: Double = Double(picture.minX) + Double(picture.width) * place.from
        let top: Double = Double(picture.minY) + Double(picture.height) * place.from
        let frame = CGRect(x: 0, y: 0, width: el.w, height: el.h)
        let modules = runs(grid).compactMap { run -> CGRect? in
            let r = CGRect(x: left + Double(run.minX) * module, y: top + Double(run.minY) * module,
                           width: Double(run.width) * module, height: module)
            return cut(r, to: frame)
        }
        let background = style.background == nil ? nil : cut(picture, to: frame)
        return Vector(style: style, background: background, modules: modules)
    }

    /// Whether `el` looks like nothing but its colours: what vector draws.
    private static func plainLook(_ el: Element) -> Bool {
        let unfiltered = (el.filter ?? "none") == "none" && (el.adjustments ?? Adjustments()) == Adjustments()
        let unaffected = el.duotone == nil && el.focusBlur == nil && el.edge == nil
        let whole = (el.pixelate ?? 0) == 0 && (el.straighten ?? 0) == 0
        let shaped = el.maskShapeId.flatMap { ContentLibrary.shapeMap[$0] } != nil
        let rounded = (el.radius ?? 0) != 0 || (el.corners ?? []).contains { $0 > 0 }
        let bordered = el.stroke != nil && (el.strokeWidth ?? 0) > 0
        return unfiltered && unaffected && whole && !shaped && !rounded && !bordered
    }

    /// `r` cut to `frame`; nil when nothing of it is left.
    private static func cut(_ r: CGRect, to frame: CGRect) -> CGRect? {
        let x0 = max(r.minX, frame.minX), y0 = max(r.minY, frame.minY)
        let x1 = min(r.maxX, frame.maxX), y1 = min(r.maxY, frame.maxY)
        guard x1 > x0, y1 > y0 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// `el`'s picture when it is a code: in its own colours and margin, and
    /// the key its looks are kept by, which tells those apart. Nil for
    /// anything else, and for a code that cannot be made.
    static func picture(of el: Element) -> (image: UIImage, key: String)? {
        guard let src = el.src, let payload = payload(from: src) else { return nil }
        let style = style(of: el)
        guard let image = qr(payload, style: style) else { return nil }
        return (image, style == Look() ? src : "\(src)|\(styleKey(style))")
    }

    /// A style as a cache key's part.
    private static func styleKey(_ style: Look) -> String {
        "\(style.color)/\(style.background ?? noBackground)/\(style.margin)"
    }

    // MARK: the code as data

    /// The code as a square grid of modules, `true` where dark, with the
    /// generator's own margin trimmed off and its orientation normalised.
    ///
    /// Internal rather than private so the tests can assert the structure the
    /// QR standard guarantees — which is the only check that does not depend
    /// on a decoder being available.
    static func modules(for payload: String) -> [[Bool]]? {
        if let kept = grids.object(forKey: payload as NSString) { return kept.rows }
        guard let made = madeModules(for: payload) else { return nil }
        grids.setObject(Grid(made), forKey: payload as NSString)
        return made
    }

    /// A code's modules, kept: the canvas draws a code's rectangles from
    /// them every time it draws it (vector).
    private final class Grid {
        let rows: [[Bool]]
        init(_ rows: [[Bool]]) { self.rows = rows }
    }

    private static let grids: NSCache<NSString, Grid> = {
        let c = NSCache<NSString, Grid>()
        c.countLimit = 64
        return c
    }()

    private static func madeModules(for payload: String) -> [[Bool]]? {
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        // Medium recovers ~15% of a damaged or partly covered code, which is
        // the level almost every printed code in the world uses.
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let raw = ciContext.createCGImage(output, from: output.extent) else { return nil }

        guard var grid = read(raw) else { return nil }
        grid = normalisedPolarity(grid)
        guard let trimmed = trimmedToCode(grid) else { return nil }
        return uprighted(trimmed)
    }

    /// One byte per pixel, `true` where dark. Read onto white, so a generator
    /// that returns its modules over transparency is read the same way as one
    /// that returns them over an opaque background.
    private static func read(_ image: CGImage) -> [[Bool]]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w < 4096, h < 4096 else { return nil }
        var bytes = [UInt8](repeating: 255, count: w * h)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        return (0..<h).map { y in (0..<w).map { x in bytes[y * w + x] < 128 } }
    }

    /// A QR is roughly half dark inside its own bounds and has a light margin
    /// around it, so a grid that comes back mostly dark was handed to us
    /// inverted. Fixing it here means the generator's tone convention cannot
    /// silently produce a code that scanners read as blank.
    private static func normalisedPolarity(_ grid: [[Bool]]) -> [[Bool]] {
        let total = grid.count * (grid.first?.count ?? 0)
        guard total > 0 else { return grid }
        let dark = grid.reduce(0) { $0 + $1.filter { $0 }.count }
        return Double(dark) / Double(total) > 0.6 ? grid.map { $0.map(!) } : grid
    }

    /// Drop the generator's margin: the code proper is the bounding box of
    /// dark modules, whose corners are finder patterns and so always dark.
    private static func trimmedToCode(_ grid: [[Bool]]) -> [[Bool]]? {
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for (y, row) in grid.enumerated() {
            for (x, dark) in row.enumerated() where dark {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let size = max(maxX - minX + 1, maxY - minY + 1)
        // A QR symbol is square and 21, 25, 29 … 177 modules on a side.
        guard size >= 21, size <= 177 else { return nil }
        return (0..<size).map { y in
            (0..<size).map { x in
                let sy = minY + y, sx = minX + x
                guard sy < grid.count, sx < grid[sy].count else { return false }
                return grid[sy][sx]
            }
        }
    }

    /// Put the finder patterns back where the standard says they go.
    ///
    /// They occupy the top-left, top-right and bottom-left 7x7 corners and
    /// never the bottom-right, so the empty corner says which way the grid was
    /// read — and a mirrored QR decodes as nothing while looking entirely
    /// correct, which is exactly how this shipped broken twice.
    private static func uprighted(_ grid: [[Bool]]) -> [[Bool]] {
        let n = grid.count
        guard n >= 21 else { return grid }
        let tl = finderScore(grid, atX: 0, y: 0)
        let tr = finderScore(grid, atX: n - 7, y: 0)
        let bl = finderScore(grid, atX: 0, y: n - 7)
        let br = finderScore(grid, atX: n - 7, y: n - 7)
        let empty = [tl, tr, bl, br].enumerated().min { $0.element < $1.element }?.offset ?? 3
        switch empty {
        case 3: return grid                                   // bottom-right: correct
        case 1: return grid.reversed().map { $0 }             // top-right empty: flipped vertically
        case 2: return grid.map { $0.reversed().map { $0 } }  // bottom-left empty: flipped horizontally
        default: return grid.reversed().map { $0.reversed().map { $0 } }
        }
    }

    /// How much the 7x7 block at this corner looks like a finder pattern: a
    /// solid ring, a light ring inside it, and a solid 3x3 core — 33 dark
    /// modules of 49.
    private static func finderScore(_ grid: [[Bool]], atX x0: Int, y y0: Int) -> Int {
        var score = 0
        for dy in 0..<7 {
            for dx in 0..<7 {
                let y = y0 + dy, x = x0 + dx
                guard y >= 0, y < grid.count, x >= 0, x < grid[y].count else { continue }
                let ring = dx == 0 || dx == 6 || dy == 0 || dy == 6
                let core = (2...4).contains(dx) && (2...4).contains(dy)
                let expected = ring || core
                if grid[y][x] == expected { score += 1 }
            }
        }
        return score
    }

    // MARK: the code as pixels

    /// Write the bitmap byte by byte. No drawing, so no orientation or
    /// interpolation convention can get between the grid and the pixels: row
    /// zero of the buffer is row zero of the CGImage by definition.
    private static func render(_ grid: [[Bool]], side: Int, style: Look) -> UIImage? {
        let n = grid.count
        guard n > 0, side > 0 else { return nil }
        // The margin's modules of quiet zone on every side — four, what the
        // standard asks for, unless the code's look says fewer — and a whole
        // number of pixels per module, so every module edge lands on a pixel
        // boundary at any size.
        let around = 2 * min(max(style.margin, 0), quiet)
        let unit = max(side / max(n + around, 1), 1)
        let drawn = unit * n
        let inset = max((side - drawn) / 2, 0)
        // Black on white stays one grey byte a pixel; colours, or a clear
        // background, take four.
        guard style != Look() else { return grey(grid, side: side, unit: unit, inset: inset) }
        let ink = ColorTools.rgb255(style.color) ?? (r: 0, g: 0, b: 0)
        let paper = style.background.flatMap(ColorTools.rgb255)
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        if let paper {
            for i in 0..<(side * side) {
                bytes[i * 4] = UInt8(paper.r)
                bytes[i * 4 + 1] = UInt8(paper.g)
                bytes[i * 4 + 2] = UInt8(paper.b)
                bytes[i * 4 + 3] = 255
            }
        }
        for y in 0..<n {
            for x in 0..<n where grid[y][x] {
                let top = inset + y * unit, left = inset + x * unit
                guard top >= 0, left >= 0, top + unit <= side, left + unit <= side else { continue }
                for row in top..<(top + unit) {
                    for column in left..<(left + unit) {
                        let at = (row * side + column) * 4
                        bytes[at] = UInt8(ink.r)
                        bytes[at + 1] = UInt8(ink.g)
                        bytes[at + 2] = UInt8(ink.b)
                        bytes[at + 3] = 255
                    }
                }
            }
        }
        // Every pixel is opaque or wholly clear, so premultiplied is as
        // written.
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGImage(width: side, height: side,
                               bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                               space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// Black modules on white, one grey byte a pixel.
    private static func grey(_ grid: [[Bool]], side: Int, unit: Int, inset: Int) -> UIImage? {
        let n = grid.count
        var bytes = [UInt8](repeating: 255, count: side * side)
        for y in 0..<n {
            for x in 0..<n where grid[y][x] {
                let top = inset + y * unit, left = inset + x * unit
                guard top >= 0, left >= 0, top + unit <= side, left + unit <= side else { continue }
                for row in top..<(top + unit) {
                    let start = row * side + left
                    for i in start..<(start + unit) { bytes[i] = 0 }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: side, height: side,
                               bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                               space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}
