// A print bleed you can see and design into: Canva's "Show print bleed".
//
// A design may carry a `bleed`, in page units, round every page. While it
// does, the editor shows that band beyond the trim, things may be put out
// into it, a page's background runs through it, and the print-ready PDF
// prints it — the page at its true size with the band round it, rather than
// enlarged to make one. Every other export is the trim, as ever. The
// Android twin's Bleed, with the same tests.

import CoreGraphics
import Foundation

enum Bleed {

    /// The bleed "Show print bleed" sets, in millimetres: what print shops
    /// ask for (Canva's 3 mm, an eighth of an inch near enough).
    static let mm = 3.0

    /// The dots per inch a design that says none is bled at — a print
    /// design's (Units.printDPI), so a design in pixels gets 35.5 px.
    static let dpi = Units.printDPI

    /// How long the "Bleed" label shows once the band is, in seconds.
    static let labelSeconds = 3.0

    /// The bleed "Show print bleed" gives `design`: `mm` at the design's
    /// own dpi, or at `dpi` when it says none — a design in pixels among
    /// them — to the nearest half unit (Guides.halfPixel): 3 × dpi / 25.4,
    /// so 35.5 at 300 dpi, 11.5 at 96, 17.5 at 150.
    static func bleedPx(_ design: Design) -> Double {
        let own = design.dpi.flatMap { $0 > 0 && $0.isFinite ? $0 : nil } ?? dpi
        return Guides.halfPixel(mm * own / 25.4)
    }

    /// `design`'s bleed in page units: its own when it has one above
    /// nothing, else 0 — no bleed.
    static func of(_ design: Design) -> Double {
        guard let bleed = design.bleed, bleed.isFinite, bleed > 0 else { return 0 }
        return bleed
    }

    /// Whether "Show print bleed" is on for `design`.
    static func shown(_ design: Design) -> Bool { of(design) > 0 }

    /// `design` with "Show print bleed" turned `on` — `bleedPx` — or off,
    /// the key gone.
    static func withBleed(_ design: Design, on: Bool) -> Design {
        var out = design
        out.bleed = on ? bleedPx(design) : nil
        return out
    }

    /// A page of `size` with `bleed` round every side, in page units: from
    /// -bleed at its top left.
    static func bledRect(size: CGSize, bleed: Double) -> CGRect {
        CGRect(x: -bleed, y: -bleed, width: Double(size.width) + 2 * bleed, height: Double(size.height) + 2 * bleed)
    }

    /// The bleed the print sheet's Bleed stepper starts at, in points: the
    /// design's own on paper, or none.
    static func printPoints(_ design: Design) -> Double {
        of(design) * PrintLayout.pxToPt(design)
    }
}
