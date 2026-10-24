// A talk's slides, as Present shows them — on the phone, or on the screen
// the room sees while the phone shows the presenter's console — and the
// state both draw from: the page up, how it came in, its clock, autoplay
// and the pointer. One talk, so a page turned on the phone turns on the
// display with the same transition, and a display taken away mid-talk
// leaves the phone presenting on the same page.

import Observation
import SwiftUI

@MainActor
@Observable
final class PresentSession {
    let design: Design
    /// The page up, by index. Another page up lets the last one's clips'
    /// players go (ClipPlayers) — its own only, so a page playing in
    /// another window plays on.
    var index = 0 {
        didSet { if index != oldValue { ClipPlayers.shared.close(elements: clipElements(onPage: oldValue)) } }
    }

    /// The ids of the elements showing a clip on page `index` — the
    /// master's behind it too; none for an index out of range.
    func clipElements(onPage index: Int) -> Set<String> {
        guard design.pages.indices.contains(index) else { return [] }
        return Set(design.drawnElements(on: design.pages[index]).filter { VideoStore.isVideo($0.src) }.map(\.id))
    }
    /// How the page now showing came in, and how the one before it left.
    var moving: AnyTransition = .opacity
    /// When the page now showing came up: its entrances play from here.
    var shownAt = Date()
    /// Where the clock its exits play by reads nought: when the page came
    /// up, or later when autoplay was turned on while they were held.
    var exitZero = Date()
    /// Whether everything on the page has come to rest, so the clock that
    /// plays it can stop.
    var settled = false
    /// When the person went on from a page whose elements leave, so its
    /// clock runs on through the exits; nil before that.
    var exitFrom: Date?
    /// Where the exits' clock stood when autoplay was turned off, so a page
    /// whose exits had begun keeps it there; nil before that.
    var stoppedAt: Double?
    var autoplay = false
    /// Where the presenter points, in the page's own units: a red dot over
    /// the page while a finger is held down; nil otherwise.
    var pointer: CGPoint?
    /// At the end of the last page shown, go round to the first: the
    /// design's own setting, which the Loop button changes.
    var loop: Bool
    /// The presenter's effects showing over the page (Presenter.effects),
    /// on the phone and on the screen alike.
    var effects: [Presenter.Shown] = []
    /// Where the page up lies among the pages turning: one higher for each
    /// turn forward — Loop's round to the first page too — and one lower
    /// for each turn back.
    var layer: Double = 0

    init(design: Design) {
        self.design = design
        loop = design.presentLoops
    }

    /// Whether the page is blurred by the presenter.
    var blurred: Bool { effects.contains { $0.id == "blur" } }

    var page: Page { design.pages[min(index, design.pages.count - 1)] }

    func holdSeconds(_ page: Page) -> Double {
        page.holdSeconds ?? design.motion?.secondsPerPage ?? MotionSettings().secondsPerPage
    }

    /// How long before the page's end its exits begin; 0 when nothing leaves.
    func exitSpan(_ page: Page) -> Double {
        ElementAnimation.exitSpan(design.masterElements(behind: page) + page.elements)
    }

    /// Where the page's clock waits for the person to go on: where its exits
    /// begin. None with autoplay, which runs the clock freely — unless the
    /// exits are already playing — or when nothing leaves.
    func heldAt(_ page: Page) -> Double? {
        guard !autoplay || exitFrom != nil else { return nil }
        return PresentationView.heldPoint(hold: holdSeconds(page), span: exitSpan(page), stoppedAt: stoppedAt)
    }

    /// Whether anything on the page moves: an entrance, an exit, a loop, a
    /// drift, a clip playing, an animated picture, an element shown for
    /// part of the page, a caption box whose words change.
    static func moves(_ page: Page, in design: Design) -> Bool {
        design.drawnElements(on: page).contains {
            if Captions.plays($0) { return true }
            return $0.animation != nil || $0.exitAnimation != nil || $0.kenBurns != nil || VideoStore.isVideo($0.src)
                || AnimStore.isAnim($0.src) || $0.timing != nil
        }
    }
}

/// The page up, fitted to `size` on black's middle, turning as the talk
/// turns it, playing as it plays, with the pointer over it. Never the notes.
struct PresentStage: View {
    let session: PresentSession
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    /// Settings ▸ Accessibility's Reduce motion, over the phone's own
    /// (AccessibilityPrefs).
    @AppStorage(AccessibilityPrefs.reduceMotionKey) private var reduceMotionChoice = AccessibilityPrefs.system
    @AppStorage(AccessibilityPrefs.underlineLinksKey) private var underlineLinks = false
    private var reduceMotion: Bool {
        AccessibilityPrefs.reducesMotion(reduceMotionChoice, systemReduces: systemReducesMotion)
    }

    var body: some View {
        ZStack {
            ZStack {
                pageView
                    .id(session.page.id)
                    .transition(session.moving)
                    // A page turned to forward always lies over the one it
                    // leaves: a slide forward comes in on top — round from
                    // the last page to the first too — and a slide back goes
                    // in under the page leaving.
                    .zIndex(session.layer)
            }
            // Blur is the page's own; the other effects lie over it.
            .blur(radius: session.blurred ? min(size.width, size.height) * 0.03 : 0)
            PresentEffectsLayer(session: session, size: size)
        }
        // The pages turn and the pointer goes as the video draws them, left
        // to right in any language.
        .designDirection()
    }

    private var pageView: some View {
        let design = session.design
        let shown = session.page
        let pageSize = design.size(for: shown)
        let scale = min(size.width / max(pageSize.width, 1), size.height / max(pageSize.height, 1))
        let start = session.shownAt
        let exitStart = session.exitZero
        let hold = session.holdSeconds(shown)
        let moves = PresentSession.moves(shown, in: design)
        let plays = moves && !reduceMotion
        // Under Reduce Motion nothing moves, but a caption box still goes
        // through its cues on the page's clock, as on the Android twin:
        // only its words change, everything else drawn at rest.
        let speaks = moves && reduceMotion && design.drawnElements(on: shown).contains(where: Captions.plays)
        // Turned by hand, the exits of a page whose elements leave are held
        // where they begin, until the person goes on, while its loops, clips,
        // drifts and entrances play on; with autoplay they run freely.
        let waitAt = session.heldAt(shown)
        let exiting = session.exitFrom
        // The page's entrances play as it arrives, and a drifting photo
        // drifts over its hold — the Android twin's presenter plays them too.
        return TimelineView(.animation(minimumInterval: nil, paused: !(plays || speaks) || session.settled)) { context in
            let now = PresentationView.clock(at: context.date, from: start, hold: hold, playing: plays || speaks,
                                             heldAt: waitAt, exitFrom: exiting, exitZero: exitStart)
            let moving: PresentationView.Reading? = plays ? now : nil
            let said: Double? = speaks ? now?.time : nil
            PageRenderView(design: design, page: shown)
                .environment(\.animationTime, moving.map { (time: $0.time, hold: $0.hold) })
                .environment(\.exitTime, moving?.exitTime)
                .environment(\.captionTime, said)
                .environment(\.captionsPlay, speaks)
                // A clip plays from the frames decoded so far, never waiting
                // on the next: this redraws every display frame, and a
                // decode on the main thread each time made it stutter.
                .environment(\.liveVideo, true)
                .environment(\.clipsPlay, true)
                .environment(\.onScreen, true)
        }
        // Settings ▸ Accessibility's Underline links, never in an export.
        .overlay(alignment: .topLeading) { if underlineLinks { LinkUnderlines(design: design, page: shown) } }
        .overlay(alignment: .topLeading) { PointerDot(point: session.pointer, page: pageSize) }
        .scaleEffect(scale)
        .frame(width: pageSize.width * scale, height: pageSize.height * scale)
        .position(x: size.width / 2, y: size.height / 2)
    }
}

/// The pointer's red dot, at `point` on a page of `page` size, drawn in the
/// page's own units under the page's scale; nothing without a point.
struct PointerDot: View {
    let point: CGPoint?
    let page: CGSize

    var body: some View {
        if let point {
            let across = CGFloat(Presenter.pointerDiameter(page: page))
            Circle()
                .fill(Color.red)
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: across * 0.12))
                .shadow(color: .red.opacity(0.6), radius: across * 0.4)
                .frame(width: across, height: across)
                .offset(x: point.x - across / 2, y: point.y - across / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
