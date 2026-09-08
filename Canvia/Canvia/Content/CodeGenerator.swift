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

    /// Generated codes are small and cheap, but they are re-resolved on every
    /// canvas render, so they are worth keeping.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 32
        return c
    }()

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// A black-on-white QR code for `payload`, `side` points on each edge.
    ///
    /// Nothing here is configurable on purpose. A tinted or low-contrast code
    /// is a code that does not scan, and a design tool that lets you make one
    /// has helped you print a thousand useless flyers.
    static func qr(_ payload: String, side: CGFloat = 512) -> UIImage? {
        guard !payload.isEmpty, side >= 1 else { return nil }
        let pixels = Int(min(max(side, 24), 2048).rounded())
        let key = "\(pixels)|\(payload)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let grid = modules(for: payload), let image = render(grid, side: pixels) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    // MARK: the code as data

    /// The code as a square grid of modules, `true` where dark, with the
    /// generator's own margin trimmed off and its orientation normalised.
    ///
    /// Internal rather than private so the tests can assert the structure the
    /// QR standard guarantees — which is the only check that does not depend
    /// on a decoder being available.
    static func modules(for payload: String) -> [[Bool]]? {
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
    private static func render(_ grid: [[Bool]], side: Int) -> UIImage? {
        let n = grid.count
        guard n > 0, side > 0 else { return nil }
        // Four modules of quiet zone on every side — what the standard asks
        // for — and a whole number of pixels per module, so every module edge
        // lands on a pixel boundary at any size.
        let unit = max(side / (n + 8), 1)
        let drawn = unit * n
        let inset = max((side - drawn) / 2, 0)

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
