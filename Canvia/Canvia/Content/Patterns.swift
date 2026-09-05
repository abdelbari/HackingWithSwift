// Pattern fills: stripes, dots, checks and the rest, drawn on demand.
//
// Procedural rather than bitmap tiles, so a pattern is sharp at any zoom
// and any export scale, and recolours to whatever two colours the design
// wants. The same drawing routine paints the canvas and any bitmap the
// exporters need.

import SwiftUI
import UIKit

enum Patterns {

    static let names = ["stripes", "dots", "checks", "grid", "zigzag", "crosshatch"]

    static func displayName(_ id: String) -> String {
        switch id {
        case "stripes": return "Stripes"
        case "dots": return "Dots"
        case "checks": return "Checks"
        case "grid": return "Grid"
        case "zigzag": return "Zigzag"
        case "crosshatch": return "Crosshatch"
        default: return id.capitalized
        }
    }

    /// Paint `rect` with the pattern: background first, then the marks,
    /// tiled at the paint's scale.
    static func draw(_ paint: Paint, in cg: CGContext, rect: CGRect) {
        let fg = UIColor(hex: paint.color ?? "#1f2430").cgColor
        let bg = UIColor(hex: paint.secondary ?? "#ffffff").cgColor
        let tile = max(4, paint.scale ?? 24)
        cg.saveGState()
        cg.clip(to: rect)
        cg.setFillColor(bg)
        cg.fill(rect)
        cg.setFillColor(fg)
        cg.setStrokeColor(fg)
        cg.setLineWidth(max(1, tile * 0.12))

        let cols = Int(ceil(rect.width / tile)) + 1
        let rows = Int(ceil(rect.height / tile)) + 1
        switch paint.pattern ?? "stripes" {
        case "dots":
            for r in 0..<rows { for c in 0..<cols {
                let cx = rect.minX + (Double(c) + 0.5) * tile, cy = rect.minY + (Double(r) + 0.5) * tile
                cg.fillEllipse(in: CGRect(x: cx - tile * 0.18, y: cy - tile * 0.18, width: tile * 0.36, height: tile * 0.36))
            } }
        case "checks":
            for r in 0..<rows { for c in 0..<cols where (r + c) % 2 == 0 {
                cg.fill(CGRect(x: rect.minX + Double(c) * tile, y: rect.minY + Double(r) * tile, width: tile, height: tile))
            } }
        case "grid":
            for c in 0...cols {
                let x = rect.minX + Double(c) * tile
                cg.move(to: CGPoint(x: x, y: rect.minY)); cg.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for r in 0...rows {
                let y = rect.minY + Double(r) * tile
                cg.move(to: CGPoint(x: rect.minX, y: y)); cg.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            cg.strokePath()
        case "zigzag":
            for r in 0...rows {
                let y = rect.minY + Double(r) * tile
                cg.move(to: CGPoint(x: rect.minX, y: y))
                for c in 0...cols {
                    cg.addLine(to: CGPoint(x: rect.minX + (Double(c) + 0.5) * tile, y: y - tile * 0.4))
                    cg.addLine(to: CGPoint(x: rect.minX + Double(c + 1) * tile, y: y))
                }
            }
            cg.strokePath()
        case "crosshatch":
            let span = rect.width + rect.height
            var d = -rect.height
            while d < span {
                cg.move(to: CGPoint(x: rect.minX + d, y: rect.minY))
                cg.addLine(to: CGPoint(x: rect.minX + d + rect.height, y: rect.maxY))
                cg.move(to: CGPoint(x: rect.minX + d + rect.height, y: rect.minY))
                cg.addLine(to: CGPoint(x: rect.minX + d, y: rect.maxY))
                d += tile
            }
            cg.strokePath()
        default: // stripes: vertical bars, half the tile wide
            for c in 0..<cols {
                cg.fill(CGRect(x: rect.minX + Double(c) * tile, y: rect.minY, width: tile / 2, height: rect.height))
            }
        }
        cg.restoreGState()
    }

    /// The pattern as a bitmap, for tests and any exporter that wants pixels.
    static func image(_ paint: Paint, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(paint, in: ctx.cgContext, rect: CGRect(origin: .zero, size: size))
        }
    }
}

/// A pattern paint as a SwiftUI view, sized by its container.
struct PatternFill: View {
    let paint: Paint

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                Patterns.draw(paint, in: cg, rect: CGRect(origin: .zero, size: size))
            }
        }
    }
}
