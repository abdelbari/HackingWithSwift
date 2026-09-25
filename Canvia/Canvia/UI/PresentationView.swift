// Presenter mode: the design full screen, one page at a time.
//
// A deck made in a design tool gets shown from the phone — held up in a
// meeting, mirrored to a screen — and a scrollable editor with a toolbar is
// not that. This is: black surround, the page fitted, tap or swipe to move,
// a clock, the page's notes for the person holding the phone, and autoplay
// on each page's own timing.

import SwiftUI

struct PresentationView: View {
    let design: Design
    var startPage = 0
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var showingNotes = false
    @State private var showingChrome = true
    @State private var autoplay = false
    @State private var started = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var autoplayTask: Task<Void, Never>?
    /// How the page now showing came in, and how the one before it left.
    @State private var moving: AnyTransition = .opacity
    /// When the page now showing came up: its entrances play from here.
    @State private var shownAt = Date()
    /// Whether everything on the page has come to rest, so the clock that
    /// plays it can stop.
    @State private var settled = false
    @State private var settleTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var page: Page { design.pages[min(index, design.pages.count - 1)] }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                pageView(in: geo.size)
                    .id(page.id)
                    .transition(moving)
                    // A later page always lies over an earlier one: a slide
                    // forward comes in on top, a slide back goes in under
                    // the page leaving.
                    .zIndex(Double(index))
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width < 0 { go(1) } else { go(-1) }
                    })
                    .onTapGesture { location in
                        if location.x > geo.size.width * 0.66 { go(1) }
                        else if location.x < geo.size.width * 0.33 { go(-1) }
                        else { withAnimation { showingChrome.toggle() } }
                    }
                if showingChrome { chrome }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            index = min(max(startPage, 0), design.pages.count - 1)
            started = Date()
            UIApplication.shared.isIdleTimerDisabled = true
            pageArrived()
        }
        .onDisappear {
            autoplayTask?.cancel()
            settleTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(clock) { _ in elapsed = Date().timeIntervalSince(started) }
    }

    private func pageView(in size: CGSize) -> some View {
        let pageSize = design.size(for: page)
        let scale = min(size.width / max(pageSize.width, 1), size.height / max(pageSize.height, 1))
        let shown = page
        let start = shownAt
        let hold = holdSeconds(shown)
        let plays = Self.moves(shown, in: design) && !reduceMotion
        // The page's entrances play as it arrives, and a drifting photo
        // drifts over its hold — the Android twin's presenter plays them too.
        return TimelineView(.animation(minimumInterval: nil, paused: !plays || settled)) { context in
            PageRenderView(design: design, page: shown)
                .environment(\.animationTime, Self.clock(at: context.date, from: start, hold: hold, playing: plays))
        }
        .scaleEffect(scale)
        .frame(width: pageSize.width * scale, height: pageSize.height * scale)
        .position(x: size.width / 2, y: size.height / 2)
        .accessibilityLabel("Page \(index + 1) of \(design.pages.count)")
    }

    /// The page's clock at `date`: seconds since it came up, and its hold;
    /// none when it does not play.
    private static func clock(at date: Date, from start: Date, hold: Double, playing: Bool) -> (time: Double, hold: Double)? {
        guard playing else { return nil }
        return (time: max(0, date.timeIntervalSince(start)), hold: hold)
    }

    /// Whether anything on the page moves: an entrance, a loop, a drift.
    private static func moves(_ page: Page, in design: Design) -> Bool {
        (design.masterElements(behind: page) + page.elements).contains { $0.animation != nil || $0.kenBurns != nil }
    }

    private func holdSeconds(_ page: Page) -> Double {
        page.holdSeconds ?? design.motion?.secondsPerPage ?? MotionSettings().secondsPerPage
    }

    /// When the page's movement is over: its last entrance, or its hold for a
    /// drift; never, for a loop.
    private func motionEnd(_ page: Page) -> Double {
        let elements = design.masterElements(behind: page) + page.elements
        var end = elements.compactMap { $0.animation?.end }.max() ?? 0
        if elements.contains(where: { $0.kenBurns != nil }) { end = max(end, holdSeconds(page)) }
        return end
    }

    /// The page just came up: its clock starts, and stops once all of it is
    /// at rest.
    private func pageArrived() {
        shownAt = Date()
        settled = false
        settleTask?.cancel()
        let end = motionEnd(page)
        guard end.isFinite else { return }
        let showing = index
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(end + 0.1))
            guard !Task.isCancelled, showing == index else { return }
            settled = true
        }
    }

    /// How `page` gives way to the next: its own transition, else the
    /// design's — a fade, or a cut with cross-fade off. The same rule the
    /// video and the Android twin use.
    private func transition(after page: Page) -> String {
        if let own = page.transition, MovieExporter.transitions.contains(own) { return own }
        return design.motion?.crossfade == false ? "cut" : "fade"
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").padding(10) }
                    .accessibilityLabel("End presentation")
                Spacer()
                Text(timeString)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Elapsed \(timeString)")
                Spacer()
                Button {
                    autoplay.toggle()
                    if autoplay { scheduleAdvance() } else { autoplayTask?.cancel() }
                } label: { Image(systemName: autoplay ? "pause.fill" : "play.fill").padding(10) }
                    .accessibilityLabel(autoplay ? "Pause autoplay" : "Autoplay")
                Button { showingNotes.toggle() } label: {
                    Image(systemName: (page.notes?.isEmpty == false) ? "note.text" : "note").padding(10)
                }
                .accessibilityLabel("Notes")
            }
            .foregroundStyle(.white)
            .background(.black.opacity(0.35))
            Spacer()
            if showingNotes {
                ScrollView {
                    Text(page.notes?.isEmpty == false ? page.notes! : "No notes for this page.")
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 160)
                .background(.black.opacity(0.6))
            }
            Text("\(index + 1) / \(design.pages.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .padding(6)
        }
    }

    private var timeString: String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func go(_ delta: Int) {
        let next = index + delta
        guard design.pages.indices.contains(next) else { return }
        // Going on, the page being left decides; going back, the page being
        // returned to, played in reverse.
        let via = transition(after: delta > 0 ? page : design.pages[next])
        let animation: Animation?
        switch via {
        case "cut":
            moving = .identity
            animation = nil
        case "slide" where !reduceMotion:
            // Forward: the next page slides in from the right over this one,
            // which goes once it is covered. Back: this one slides away to
            // the right, showing the earlier page beneath.
            moving = delta > 0
                ? .asymmetric(insertion: .move(edge: .trailing),
                              removal: .opacity.animation(.linear(duration: 0.01).delay(0.5)))
                : .asymmetric(insertion: .identity, removal: .move(edge: .trailing))
            animation = .easeOut(duration: 0.5)
        default:
            moving = .opacity
            animation = .easeInOut(duration: 0.25)
        }
        // The transition is read when the views change, so it is set first,
        // and the page moves on the next turn of the run loop.
        DispatchQueue.main.async {
            withAnimation(animation) { index = next }
            pageArrived()
            if autoplay { scheduleAdvance() }
        }
    }

    /// Wait this page's own hold (or the document's), then move on; stop at
    /// the last page rather than looping back to a title slide.
    private func scheduleAdvance() {
        autoplayTask?.cancel()
        let hold = page.holdSeconds ?? design.motion?.secondsPerPage ?? MotionSettings().secondsPerPage
        autoplayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(hold, 0.5)))
            guard !Task.isCancelled, autoplay else { return }
            if index + 1 < design.pages.count { go(1) } else { autoplay = false }
        }
    }
}
