// A dashed or dotted border round a shape, a photo or a frame.
//
// The line's own `dash` key, read on shapes and images too: "dashed" or
// "dotted", and no key at all for solid, so an older build simply draws the
// border solid. The intervals are the line's, scaled by the border's width
// w: a dash of 3w and a gap of 2w with square-cut ends, or a dot every 2.2w
// with round ends (a dash of 0.01 that a round cap makes a dot). The
// pattern starts half a dash in, so a dash sits centred on the outline's
// first point — a rectangle's corner — and the pattern meets itself there
// in the middle of a dash rather than at a gap's ragged end. The canvas,
// the SVG and the PDF draw these numbers, as the Android twin's renderer
// does, and a PowerPoint file names its own "dash" and "sysDot";
// BorderStyleTests holds the shared rows.

import CoreGraphics
import Foundation

enum BorderDash {

    /// The styles the Border control offers, in its order: the key's value,
    /// nil for solid, and the name it shows.
    static let styles: [(key: String?, name: String)] = [
        (nil, tr("Solid")), ("dashed", tr("Dashed")), ("dotted", tr("Dotted")),
    ]

    /// `dash` as kept on a shape or a photo: "dashed" or "dotted", else nil
    /// — a line's "solid" included.
    static func kept(_ dash: String?) -> String? {
        dash == "dashed" || dash == "dotted" ? dash : nil
    }

    /// The on and off lengths for a border `width` wide, nil when solid.
    static func intervals(_ dash: String?, width: Double) -> [Double]? {
        switch kept(dash) {
        case "dashed": return [3 * width, 2 * width]
        case "dotted": return [0.01, 2.2 * width]
        default: return nil
        }
    }

    /// How far into the pattern the outline starts: half a dash.
    static func phase(_ dash: String?, width: Double) -> Double {
        (intervals(dash, width: width)?.first ?? 0) / 2
    }

    /// Whether the ends of each dash are round: a dot's are, a dash's are
    /// cut square, and a solid border keeps the round ends it always had.
    static func roundCaps(_ dash: String?) -> Bool {
        kept(dash) != "dashed"
    }

    /// The name the Border control shows for a style.
    static func name(_ dash: String?) -> String {
        styles.first { $0.key == kept(dash) }?.name ?? tr("Solid")
    }
}
