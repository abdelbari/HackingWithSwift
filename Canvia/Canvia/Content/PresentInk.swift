// The presenter's pen: strokes drawn over the slide in Present, on the phone
// and the screen the room sees alike, to circle or underline something as
// it is talked about. Never saved to the design or exported — it is gone
// with the page, or at Clear, or, while Fade ink is on, a little after each
// stroke is lifted.
//
// Strokes are kept in the page's own units, so they sit on the same spot of
// the page on either screen, and are drawn through Freehand.cgPath, the
// smoothing a drawn line has in the editor. The rules both phones share, so
// ink fades alike on either (Tests/Fixtures/present_ink.json, the Android
// twin's PresentInk).

import CoreGraphics
import Foundation

enum PresentInk {

    /// The pen's colours, as #rrggbb, in the order the bar offers them:
    /// red, yellow and white.
    static let colors = ["#ff3b30", "#ffcc00", "#ffffff"]

    /// The colours' names, as the bar says them.
    static var colorNames: [String] { [tr("Red"), tr("Yellow"), tr("White")] }

    /// The pen's three widths, as a share of the page's shorter side, thin
    /// to thick, so a line is as thick on the page on either screen.
    static let widths = [0.004, 0.008, 0.016]

    /// The widths' names, as the bar says them.
    static var widthNames: [String] { [tr("Thin"), tr("Medium"), tr("Thick")] }

    /// The colour and width a pen starts with: red, medium.
    static let startColor = 0
    static let startWidth = 1

    /// Fade ink's setting, on unless turned off — the Android twin's
    /// preference of the same name.
    static let fadePref = "presentInkFade"

    /// With Fade ink on, how long a lifted stroke stays whole, and how long
    /// it then takes to fade out, in seconds.
    static let fadeAfter = 3.0
    static let fadeSeconds = 0.5

    /// The keys: L locks the laser, so a touch points at once; P turns the
    /// pen on and off; E clears the ink. None of them is a magic shortcut's
    /// (Presenter.effects).
    static let laserKey = "l"
    static let penKey = "p"
    static let clearKey = "e"

    /// One stroke: its points on the page, its colour and width (indices
    /// into `colors` and `widths`), and when it was lifted, in seconds on
    /// the talk's clock, or nil while it is still being drawn.
    struct Stroke: Equatable {
        var points: [CGPoint]
        var color = PresentInk.startColor
        var width = PresentInk.startWidth
        var liftedAt: Double?
    }

    /// How solid `stroke` is at `now`: whole while it is drawn and for
    /// `fadeAfter` seconds after it is lifted, then fading evenly to nothing
    /// over `fadeSeconds`. Without `fade`, whole until it is cleared.
    static func alpha(_ stroke: Stroke, now: Double, fade: Bool) -> Double {
        guard let lifted = stroke.liftedAt, fade else { return 1 }
        let past = now - lifted - fadeAfter
        return min(max(1 - past / fadeSeconds, 0), 1)
    }

    /// `stroke`'s width in page units on a page of `page` size.
    static func width(_ stroke: Stroke, page: CGSize) -> Double {
        widths[min(max(stroke.width, 0), widths.count - 1)] * Double(min(page.width, page.height))
    }

    /// The colour `stroke` is drawn in.
    static func color(_ stroke: Stroke) -> String {
        colors[min(max(stroke.color, 0), colors.count - 1)]
    }

    /// The ink on the page up: its strokes, oldest first.
    struct Ink: Equatable {
        var strokes: [Stroke] = []

        /// A stroke begun at `point`.
        func started(at point: CGPoint, color: Int, width: Int) -> Ink {
            Ink(strokes: strokes + [Stroke(points: [point], color: color, width: width)])
        }

        /// The stroke being drawn carried on to `point`; nothing while none is.
        func extended(to point: CGPoint) -> Ink {
            guard var last = strokes.last, last.liftedAt == nil else { return self }
            last.points.append(point)
            return Ink(strokes: Array(strokes.dropLast()) + [last])
        }

        /// The stroke being drawn lifted at `now`.
        func lifted(at now: Double) -> Ink {
            guard var last = strokes.last, last.liftedAt == nil else { return self }
            last.liftedAt = now
            return Ink(strokes: Array(strokes.dropLast()) + [last])
        }

        /// Without the strokes that have faded away by `now`.
        func kept(at now: Double, fade: Bool) -> Ink {
            Ink(strokes: strokes.filter { PresentInk.alpha($0, now: now, fade: fade) > 0 })
        }

        /// Whether a lifted stroke is still to fade, so the clock runs on.
        func fading(_ fade: Bool) -> Bool {
            fade && strokes.contains { $0.liftedAt != nil }
        }
    }
}
