// Presenter mode: the design full screen, one page at a time.
//
// A deck made in a design tool gets shown from the phone — held up in a
// meeting, mirrored to a screen — and a scrollable editor with a toolbar is
// not that. This is: black surround, the page fitted, tap or swipe to move,
// a tap on a linked element to open its link, a clock, the page's notes for
// the person holding the phone, and autoplay on each page's own timing.
// Hidden pages are stepped over, and left out of the count.
// The clips on the page are heard while it is up, and the music runs on
// under the whole talk from where the first page comes in the video, fading
// out as it ends; a speaker button turns the sound off for this talk.
// Pages turn as PageTransitions lays them out, as the video draws them. A
// page whose elements leave waits, turned by hand, with its exits held where
// they begin while the rest of it plays on; going on plays them, and the page
// turns once they are done.

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
    /// Where the clock its exits play by reads nought: when the page came
    /// up, or later when autoplay was turned on while they were held.
    @State private var exitZero = Date()
    /// Whether everything on the page has come to rest, so the clock that
    /// plays it can stop.
    @State private var settled = false
    @State private var settleTask: Task<Void, Never>?
    /// When the person went on from a page whose elements leave, so its
    /// clock runs on through the exits; nil before that.
    @State private var exitFrom: Date?
    /// Where the exits' clock stood when autoplay was turned off, so a page
    /// whose exits had begun keeps it there; nil before that.
    @State private var stoppedAt: Double?
    @State private var exitTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    /// Said for a moment when a link has no app here to open it.
    @State private var linkRefused: String?
    @State private var refusedTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    /// What is heard: the page's clips from when it came up, the music from
    /// `musicFrom` seconds into the video when the talk began.
    @State private var sound = PageSound(presenting: true)
    /// Off for this talk only.
    @State private var soundOn = true
    /// Whether the design has anything to hear on this phone, so the
    /// speaker button is only there when it does something.
    @State private var heard = false
    @State private var musicFrom = 0.0
    /// Gone to the background, where the sound stopped, to start again on
    /// the way back.
    @State private var away = false
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
                        // A linked element opens its link, as a click on it
                        // does in the PDF.
                        if let url = link(at: location, in: geo.size) { open(url) }
                        else if location.x > geo.size.width * 0.66 { go(1) }
                        else if location.x < geo.size.width * 0.33 { go(-1) }
                        else { withAnimation { showingChrome.toggle() } }
                    }
                if showingChrome { chrome }
                if let linkRefused { refusedNote(linkRefused) }
            }
        }
        .statusBarHidden(true)
        .background(keyCommands)
        .onAppear {
            // A hidden page is not shown: Present starts at the next page
            // that is, or the one before when none after it is.
            let asked = min(max(startPage, 0), design.pages.count - 1)
            index = PageVisibility.start(at: asked, in: design.visiblePageIndices) ?? asked
            started = Date()
            musicFrom = AudioMix.pageStart(design: design, index: index)
            UIApplication.shared.isIdleTimerDisabled = true
            pageArrived()
        }
        .onDisappear {
            autoplayTask?.cancel()
            settleTask?.cancel()
            exitTask?.cancel()
            sound.stop(fade: true)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(clock) { _ in elapsed = Date().timeIntervalSince(started) }
        .task { heard = await PageSound.heard(in: design) }
        // Silent in the background; on the way back the page's clips start
        // again from its clock, and the music from the talk's.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                away = true
                sound.stop()
            } else if phase == .active, away {
                away = false
                startSound()
            }
        }
    }

    private func pageView(in size: CGSize) -> some View {
        let pageSize = design.size(for: page)
        let scale = min(size.width / max(pageSize.width, 1), size.height / max(pageSize.height, 1))
        let shown = page
        let start = shownAt
        let exitStart = exitZero
        let hold = holdSeconds(shown)
        let plays = Self.moves(shown, in: design) && !reduceMotion
        // Turned by hand, the exits of a page whose elements leave are held
        // where they begin, until the person goes on, while its loops, clips,
        // drifts and entrances play on; with autoplay they run freely.
        let waitAt = heldAt(shown)
        let exiting = exitFrom
        // The page's entrances play as it arrives, and a drifting photo
        // drifts over its hold — the Android twin's presenter plays them too.
        return TimelineView(.animation(minimumInterval: nil, paused: !plays || settled)) { context in
            let now = Self.clock(at: context.date, from: start, hold: hold, playing: plays,
                                 heldAt: waitAt, exitFrom: exiting, exitZero: exitStart)
            PageRenderView(design: design, page: shown)
                .environment(\.animationTime, now.map { (time: $0.time, hold: $0.hold) })
                .environment(\.exitTime, now?.exitTime)
                // A clip plays from the frames decoded so far, never waiting
                // on the next: this redraws every display frame, and a
                // decode on the main thread each time made it stutter.
                .environment(\.liveVideo, true)
        }
        .scaleEffect(scale)
        .frame(width: pageSize.width * scale, height: pageSize.height * scale)
        .position(x: size.width / 2, y: size.height / 2)
        .accessibilityLabel(spokenPlace)
        .accessibilityActions {
            // Turning the page without a swipe or a tap on its edge, for
            // VoiceOver and Switch Control — the same turn, transition and
            // autoplay a swipe gives. Both are always there, as on the
            // Android twin; at either end the one that goes nowhere does
            // nothing.
            Button("Next page") { go(1) }
            Button("Previous page") { go(-1) }
            ForEach(Self.links(on: shown, in: design), id: \.self) { url in
                Button("Open \(Links.shown(url))") {
                    if let target = URL(string: url) { open(target) }
                }
            }
        }
    }

    /// Follow a link — and when nothing on this phone takes it (a phone
    /// number on an iPad, a scheme no app handles), say so rather than do
    /// nothing, as the Android twin does.
    private func open(_ url: URL) {
        openURL(url) { accepted in
            guard !accepted else { return }
            let said = Self.refusedText(url.absoluteString)
            AccessibilityNotification.Announcement(said).post()
            refusedTask?.cancel()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { linkRefused = said }
            refusedTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { linkRefused = nil }
            }
        }
    }

    private var hasNotes: Bool { page.notes?.isEmpty == false }

    /// Where the page showing sits among the pages shown, hidden pages not
    /// counted: "2 / 5" when the second of five pages shown is up.
    private var place: (number: Int, count: Int) {
        let visible = design.visiblePageIndices
        guard let at = visible.firstIndex(of: index) else { return (index + 1, design.pages.count) }
        return (at + 1, visible.count)
    }

    /// The page as VoiceOver says it: "Page 2 of 5", and its title.
    private var spokenPlace: String {
        var label = "Page \(place.number) of \(place.count)"
        if let title = page.title.flatMap(PageTitles.kept) { label += ", " + title }
        return label
    }

    /// The Notes button, as VoiceOver says it.
    static func notesLabel(hasNotes: Bool) -> String {
        hasNotes ? "Notes" : "Notes, none for this page"
    }

    /// "No app here opens example.com/menu" — the link as the page shows it.
    static func refusedText(_ url: String) -> String {
        "No app here opens \(Links.shown(url))"
    }

    private func refusedNote(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.18), in: Capsule())
                .padding(.bottom, 40)
                .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// The page's links, each once, in drawing order.
    private static func links(on page: Page, in design: Design) -> [String] {
        var seen = Set<String>()
        return Links.areas(design: design, page: page).map(\.url).filter { seen.insert($0).inserted }
    }

    /// The link under `location`, in a view of `size` that fits the page as
    /// pageView does; nil where there is none.
    private func link(at location: CGPoint, in size: CGSize) -> URL? {
        let pageSize = design.size(for: page)
        let scale: CGFloat = min(size.width / max(pageSize.width, 1), size.height / max(pageSize.height, 1))
        guard scale > 0 else { return nil }
        let dx: CGFloat = (size.width - pageSize.width * scale) / 2
        let dy: CGFloat = (size.height - pageSize.height * scale) / 2
        let point = CGPoint(x: (location.x - dx) / scale, y: (location.y - dy) / scale)
        guard let url = Links.at(design: design, page: page, point: point) else { return nil }
        return URL(string: url)
    }

    /// A reading of `clock(at:…)`.
    typealias Reading = (time: Double, hold: Double, exitTime: Double)

    /// The page's clock at `date`: seconds since it came up, which never
    /// waits, so loops, clips and entrances play on in step with the clips'
    /// sound; its hold; and the clock its exits play by, which counts from
    /// `exitZero` (else from when the page came up), held at `heldAt`, when
    /// there is one, until the exits are played from `exitFrom`: then it
    /// runs on from `heldAt` to the hold. None when the page does not play.
    static func clock(at date: Date, from start: Date, hold: Double, playing: Bool,
                      heldAt: Double? = nil, exitFrom: Date? = nil, exitZero: Date? = nil) -> Reading? {
        guard playing else { return nil }
        let time = max(0, date.timeIntervalSince(start))
        var exitTime = max(0, date.timeIntervalSince(exitZero ?? start))
        if let heldAt {
            if let exitFrom {
                exitTime = min(hold, heldAt + max(0, date.timeIntervalSince(exitFrom)))
            } else {
                exitTime = min(exitTime, heldAt)
            }
        }
        return (time: time, hold: hold, exitTime: exitTime)
    }

    /// Whether anything on the page moves: an entrance, an exit, a loop, a
    /// drift, a clip playing.
    private static func moves(_ page: Page, in design: Design) -> Bool {
        design.drawnElements(on: page).contains {
            $0.animation != nil || $0.exitAnimation != nil || $0.kenBurns != nil || VideoStore.isVideo($0.src)
        }
    }

    /// How long before the page's end its exits begin; 0 when nothing leaves.
    private func exitSpan(_ page: Page) -> Double {
        ElementAnimation.exitSpan(design.masterElements(behind: page) + page.elements)
    }

    /// Where the page's clock waits for the person to go on: where its exits
    /// begin. None with autoplay, which runs the clock freely — unless the
    /// exits are already playing — or when nothing leaves.
    private func heldAt(_ page: Page) -> Double? {
        guard !autoplay || exitFrom != nil else { return nil }
        return Self.heldPoint(hold: holdSeconds(page), span: exitSpan(page), stoppedAt: stoppedAt)
    }

    /// Where the exits begin, `span` before the hold — or later, where the
    /// clock stood when autoplay was turned off after they had begun, so
    /// elements already gone stay gone; none when nothing leaves.
    static func heldPoint(hold: Double, span: Double, stoppedAt: Double?) -> Double? {
        guard span > 0 else { return nil }
        return max(0, hold - span, stoppedAt ?? 0)
    }

    private func holdSeconds(_ page: Page) -> Double {
        page.holdSeconds ?? design.motion?.secondsPerPage ?? MotionSettings().secondsPerPage
    }

    /// When the page's movement is over: its last entrance, or its hold for a
    /// drift or an exit; never, for a loop or a clip, which plays while the
    /// page is up.
    private func motionEnd(_ page: Page) -> Double {
        let elements = design.drawnElements(on: page)
        if elements.contains(where: { VideoStore.isVideo($0.src) }) { return .infinity }
        var end = elements.compactMap { $0.animation?.end }.max() ?? 0
        if elements.contains(where: { $0.kenBurns != nil || $0.exitAnimation != nil }) {
            end = max(end, holdSeconds(page))
        }
        return end
    }

    /// The page just came up: its clock starts, and stops once all of it is
    /// at rest; its clips are heard from now, the music playing on.
    private func pageArrived() {
        shownAt = Date()
        exitZero = shownAt
        stoppedAt = nil
        startSound()
        settle(after: motionEnd(page))
    }

    /// The clock that plays the page runs, and stops `seconds` from now;
    /// never, when they are not finite.
    private func settle(after seconds: Double) {
        settled = false
        settleTask?.cancel()
        guard seconds.isFinite else { return }
        let showing = index
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, seconds) + 0.1))
            guard !Task.isCancelled, showing == index else { return }
            settled = true
        }
    }

    /// Going on by hand from a page whose elements leave: its exits' clock
    /// runs on from where it was held through them — the clips playing on,
    /// not started again — and the page turns once they are done. False when
    /// there is nothing to play first: no exits, autoplay, Reduce Motion.
    private func beginExit(to next: Int) -> Bool {
        guard exitFrom == nil, let held = heldAt(page), Self.moves(page, in: design), !reduceMotion else { return false }
        let left = max(0, holdSeconds(page) - held)
        exitFrom = Date()
        settle(after: max(left, motionEnd(page) - Date().timeIntervalSince(shownAt)))
        let showing = index
        exitTask?.cancel()
        exitTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled, showing == index else { return }
            turn(to: next)
        }
        return true
    }

    /// Autoplay turned on partway through a page whose elements leave: its
    /// exits' clock runs on from where it was held, and the page turns at
    /// its hold on that clock, rather than its exits playing out early and
    /// the page standing empty. The page's own clock, which its loops and
    /// clips play by, is not set back.
    private func autoplayFromHere() {
        guard exitFrom == nil else { return }
        let span = exitSpan(page)
        let hold = holdSeconds(page)
        guard span > 0, Self.moves(page, in: design), !reduceMotion else {
            scheduleAdvance()
            return
        }
        let held = Self.heldPoint(hold: hold, span: span, stoppedAt: stoppedAt) ?? 0
        let now = min(Date().timeIntervalSince(exitZero), held)
        exitZero = Date().addingTimeInterval(-now)
        settle(after: max(motionEnd(page) - Date().timeIntervalSince(shownAt), hold - now, 0))
        scheduleAdvance(after: max(hold - now, 0.1))
    }

    /// Autoplay turned off: the exits' clock stays where it stands, waiting
    /// there for the person to go on, rather than going back to where they
    /// begin and bringing back elements that have already left.
    private func autoplayStopped() {
        guard exitFrom == nil else { return }
        stoppedAt = min(Date().timeIntervalSince(exitZero), holdSeconds(page))
    }

    /// The sound with the page's clock: the clips of the page up, the music
    /// on from where it is in the talk; none with the sound off.
    private func startSound() {
        guard soundOn else {
            sound.stop()
            return
        }
        sound.music(design: design, offset: musicFrom, since: started)
        sound.page(AudioMix.clips(design: design, page: page), since: shownAt)
    }

    /// How `page` gives way to the next: its own transition, else the
    /// design's — a fade, or a cut with cross-fade off. The same rule the
    /// video and the Android twin use.
    private func transition(after page: Page) -> String {
        PageTransitions.transitionKind(after: page, in: design)
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
                if heard {
                    Button {
                        soundOn.toggle()
                        startSound()
                    } label: {
                        Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill").padding(10)
                    }
                    .accessibilityLabel(soundOn ? "Sound on" : "Sound off")
                }
                Button {
                    autoplay.toggle()
                    if autoplay {
                        autoplayFromHere()
                    } else {
                        autoplayTask?.cancel()
                        autoplayStopped()
                    }
                } label: { Image(systemName: autoplay ? "pause.fill" : "play.fill").padding(10) }
                    .accessibilityLabel(autoplay ? "Pause autoplay" : "Autoplay")
                Button { showingNotes.toggle() } label: {
                    // A blank note, dimmed, when this page has none — as on
                    // the Android twin — so the button says so before it is
                    // pressed.
                    Image(systemName: hasNotes ? "note.text" : "note")
                        .opacity(hasNotes ? 1 : 0.5)
                        .padding(10)
                }
                .accessibilityLabel(Self.notesLabel(hasNotes: hasNotes))
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
            // The page's title beside the count — for the presenter, never
            // on the page itself.
            Text(PageTitles.counter(place.number, of: place.count, title: page.title))
                .lineLimit(1)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .padding(6)
        }
    }

    /// A keyboard, or the clicker a presenter holds — which sends Page Down
    /// and Page Up, or the arrows — turns the pages with the same transition
    /// and autoplay a swipe gives, and Escape ends the presentation, as on
    /// the Android twin.
    private var keyCommands: some View {
        Group {
            Group {
                key(.rightArrow, "Next page") { go(1) }
                key(.downArrow, "Next page") { go(1) }
                key(.pageDown, "Next page") { go(1) }
                key(.space, "Next page") { go(1) }
                key(.return, "Next page") { go(1) }
            }
            Group {
                key(.leftArrow, "Previous page") { go(-1) }
                key(.upArrow, "Previous page") { go(-1) }
                key(.pageUp, "Previous page") { go(-1) }
                key(.home, "First page") { turn(to: design.visiblePageIndices.first) }
                key(.end, "Last page") { turn(to: design.visiblePageIndices.last) }
            }
            key(.escape, "End presentation") { dismiss() }
        }
    }

    private func key(_ key: KeyEquivalent, _ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var timeString: String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// One page on, or one back, among the pages shown: a hidden page is
    /// stepped over. Going on by hand from a page whose elements leave plays
    /// them first; going on again meanwhile turns the page at once.
    private func go(_ delta: Int) {
        let visible = design.visiblePageIndices
        guard delta > 0 else {
            turn(to: PageVisibility.previous(before: index, in: visible))
            return
        }
        guard let next = PageVisibility.next(after: index, in: visible) else { return }
        if exitFrom == nil, !autoplay, beginExit(to: next) { return }
        turn(to: next)
    }

    /// Turn to page `target`, by index; nowhere when it is nil or the page
    /// already up.
    private func turn(to target: Int?) {
        guard let next = target, next != index, design.pages.indices.contains(next) else { return }
        // Any exits still playing are over; the page leaving keeps its
        // clock as it was drawn.
        exitTask?.cancel()
        let forward = next > index
        // Going on, the page being left decides; going back, the page being
        // returned to, played in reverse. With a hidden page between, that
        // is the page before the gap, as the video plays it.
        let earlier = forward ? page : design.pages[next]
        let via = transition(after: earlier)
        let animation: Animation?
        if via == "cut" || reduceMotion {
            moving = .identity
            animation = nil
        } else {
            // Both pages laid out by PageTransitions as the turn goes, the
            // later page on top (zIndex); a fade over its own curve, the
            // others at an even pace, since the layers ease themselves.
            let seconds = PageTransitions.presentSeconds(via, own: earlier.transitionSeconds)
            moving = PageTurnEffect.transition(via, forward: forward,
                                               leaving: design.size(for: page),
                                               coming: design.size(for: design.pages[next]))
            animation = via == "fade" ? .easeInOut(duration: seconds) : .linear(duration: seconds)
        }
        // The transition is read when the views change, so it is set first,
        // and the page moves on the next turn of the run loop.
        DispatchQueue.main.async {
            withAnimation(animation) { index = next }
            exitFrom = nil
            pageArrived()
            if autoplay { scheduleAdvance() }
        }
    }

    /// Wait this page's own hold (or the document's) — or `wait` seconds,
    /// when given — then move on; stop at the last page shown rather than
    /// looping back to a title slide.
    private func scheduleAdvance(after wait: Double? = nil) {
        autoplayTask?.cancel()
        let hold = page.holdSeconds ?? design.motion?.secondsPerPage ?? MotionSettings().secondsPerPage
        let delay = wait ?? max(hold, 0.5)
        autoplayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, autoplay else { return }
            if PageVisibility.next(after: index, in: design.visiblePageIndices) != nil {
                go(1)
            } else {
                autoplay = false
                autoplayStopped()
            }
        }
    }
}

/// One page of a turn in Present, as PageTransitions lays it out at
/// `progress` of the way through: SwiftUI animates the progress from the
/// transition's active state to its identity, a page coming from 0 to 1 and
/// a page leaving from 0 to 1 the other way round.
private struct PageTurnEffect: ViewModifier, Animatable {
    let kind: String
    let forward: Bool
    /// The page coming, rather than the page leaving.
    let coming: Bool
    /// The page's own size, so a wipe or a circle clips to the page as it
    /// is fitted, not to the screen round it.
    let pageSize: CGSize
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let both = PageTransitions.layers(kind, t: progress, forward: forward)
        let layer = coming ? both.incoming : both.outgoing
        return content
            .mask { PageTurnMask(clip: layer.clip, pageSize: pageSize) }
            .modifier(PageTurnShift(dx: layer.dx, scale: layer.scale))
            .opacity(layer.alpha)
    }

    /// The turn from a page of size `leaving` to one of size `coming`.
    static func transition(_ kind: String, forward: Bool, leaving: CGSize, coming: CGSize) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: PageTurnEffect(kind: kind, forward: forward, coming: true, pageSize: coming, progress: 0),
                identity: PageTurnEffect(kind: kind, forward: forward, coming: true, pageSize: coming, progress: 1)),
            removal: .modifier(
                active: PageTurnEffect(kind: kind, forward: forward, coming: false, pageSize: leaving, progress: 1),
                identity: PageTurnEffect(kind: kind, forward: forward, coming: false, pageSize: leaving, progress: 0)))
    }
}

/// What shows of a page while it turns: everything, a strip from the page's
/// left edge, or a circle from its centre, the page fitted to the middle of
/// the screen as Present shows it.
private struct PageTurnMask: Shape {
    let clip: PageTransitions.Clip
    let pageSize: CGSize

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / max(pageSize.width, 1), rect.height / max(pageSize.height, 1))
        let w = pageSize.width * scale, h = pageSize.height * scale
        let page = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        switch clip {
        case .none:
            return Path(rect)
        case .rect(let fraction):
            return Path(CGRect(x: page.minX, y: page.minY, width: page.width * fraction, height: page.height))
        case .circle(let fraction):
            let radius = fraction * hypot(page.width, page.height) / 2
            return Path(ellipseIn: CGRect(x: page.midX - radius, y: page.midY - radius,
                                          width: radius * 2, height: radius * 2))
        }
    }
}

/// A page shifted sideways by a share of the screen's width and scaled about
/// its centre.
private struct PageTurnShift: GeometryEffect {
    let dx: Double
    let scale: Double

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: size.width / 2 + size.width * dx, y: size.height / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -size.width / 2, y: -size.height / 2))
    }
}
