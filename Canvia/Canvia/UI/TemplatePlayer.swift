// One page of a template played as Present plays it — the same renderer,
// the page's entrances, exits, loops and the motion behind it, each moment
// of its hold — without a sound, and round again from its start when the
// hold is over, for as long as it is shown: the template preview's Play.
// The caller shows it only while motion is on (Reduce motion leaves the
// still page). The Android twin's TemplatePlayer.

import SwiftUI

struct TemplatePlayer: View {
    let design: Design
    let page: Page
    /// When it began playing: the page's clock reads nought here.
    @State private var start = Date()

    /// How long the last frame stays before the page plays again, in
    /// seconds — the Android twin's LOOP_PAUSE.
    static let loopPause = 0.8

    /// The page's hold, as Present holds it.
    private var hold: Double {
        page.holdSeconds ?? design.motion?.secondsPerPage ?? MotionSettings().secondsPerPage
    }

    /// The moment of the page shown `elapsed` seconds after it began: from
    /// nought to its hold, held there a moment, and round again.
    static func moment(_ elapsed: Double, hold: Double) -> Double {
        let span = hold + loopPause
        guard span > 0, elapsed.isFinite else { return 0 }
        let within = elapsed - (elapsed / span).rounded(.down) * span
        return min(max(0, within), hold)
    }

    var body: some View {
        GeometryReader { geo in
            let pageSize = design.size(for: page)
            let scale = min(geo.size.width / max(pageSize.width, 1), geo.size.height / max(pageSize.height, 1))
            playing
                .frame(width: pageSize.width, height: pageSize.height)
                .scaleEffect(scale)
                .frame(width: pageSize.width * scale, height: pageSize.height * scale)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .clipped()
        .onAppear { start = Date() }
    }

    /// The page at each moment of its clock, in its own units.
    private var playing: some View {
        let hold = self.hold
        return TimelineView(.animation) { context in
            let at = Self.moment(context.date.timeIntervalSince(start), hold: hold)
            PageRenderView(design: design, page: page)
                .environment(\.animationTime, (time: at, hold: hold))
                .environment(\.exitTime, at)
                .environment(\.onScreen, true)
        }
    }
}
