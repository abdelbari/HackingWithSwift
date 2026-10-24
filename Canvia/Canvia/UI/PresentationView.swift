// Presenter mode: the design full screen, one page at a time.
//
// A deck made in a design tool gets shown from the phone — held up in a
// meeting, mirrored to a screen — and a scrollable editor with a toolbar is
// not that. This is: black surround, the page fitted, tap or swipe to move,
// a tap on a linked element to open its link, a clock, the page's notes for
// the person holding the phone, and autoplay on each page's own timing.
// Hidden pages are stepped over, and left out of the count.
// The clips on the page are heard while it is up, and the audio tracks run
// under the whole talk from where the first page comes in the video, each
// at its place, a looping one for as long as the talk runs, fading out as
// it ends; a speaker button turns the sound off for this talk.
// Pages turn as PageTransitions lays them out, as the video draws them. A
// page whose elements leave waits, turned by hand, with its exits held where
// they begin while the rest of it plays on; going on plays them, and the page
// turns once they are done.
// With a second screen attached (ExternalDisplay) the slides go there, drawn
// from the same PresentSession, and the phone shows the presenter's console
// instead, with its page grid and pointer; the screen taken away mid-talk,
// the phone presents again on the same page. Without one, Present is as it
// was.
// Loop, beside Autoplay, goes round from the last page shown to the first,
// the music from its start — kept in the design, so a kiosk keeps looping.
// The presenter's effects (Presenter.effects) come from the keys 1 to 9, B,
// C, O, Q, U and X, or the sparkle button's grid, and show on both screens.

import SwiftUI

struct PresentationView: View {
    let design: Design
    var startPage = 0
    /// Loop turned on or off, for the design to keep.
    var onLoopChange: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    /// The page up, its clock and autoplay: what the phone and a second
    /// screen both draw.
    @State private var session: PresentSession
    @State private var showingNotes = false
    @State private var showingChrome = true
    /// The console's page grid, to go straight to a page.
    @State private var showingPages = false
    /// The effects' grid, the sparkle button's.
    @State private var showingEffects = false
    /// When the talk began, for the music.
    @State private var started = Date()
    /// The talk's timer, which the console can pause and reset.
    @State private var timer = PresenterTimer(startingAt: Date())
    @State private var now = Date()
    @State private var autoplayTask: Task<Void, Never>?
    @State private var settleTask: Task<Void, Never>?
    @State private var exitTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    /// Settings ▸ Accessibility's Reduce motion, over the phone's own
    /// (AccessibilityPrefs).
    @AppStorage(AccessibilityPrefs.reduceMotionKey) private var reduceMotionChoice = AccessibilityPrefs.system
    private var reduceMotion: Bool {
        AccessibilityPrefs.reducesMotion(reduceMotionChoice, systemReduces: systemReducesMotion)
    }
    @Environment(\.openURL) private var openURL
    /// Said for a moment when a link has no app here to open it.
    @State private var linkRefused: String?
    @State private var refusedTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    /// Which way the language reads, which the arrow keys turn by.
    @Environment(\.layoutDirection) private var reading
    /// What is heard: the page's clips from when it came up, the music from
    /// `musicFrom` seconds into the video when the talk began. Played to the
    /// phone's sound route, which with a screen attached is the screen.
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
    /// The pages expanded to a whiteboard, which come up whole — zoomed to
    /// fit their bounds and margin (Whiteboards) — and then pinch in and
    /// pan: the zoom over the fit, 1 to boardMaxZoom, about the middle of
    /// the screen, and how far it is moved. Each page comes up fitted again.
    private let boards: Set<String>
    @State private var boardZoom: CGFloat = 1
    @State private var boardPan: CGSize = .zero
    @GestureState private var pinching: CGFloat = 1
    @GestureState private var panning: CGSize = .zero
    /// Two fingers are pinching, and a drag is under way: a touch that
    /// pinched neither turns the page nor pans when it ends, as on Android.
    @GestureState private var magnifying = false
    @GestureState private var swiping = false
    /// A finger is down, from the first to touch until the last lifts: a
    /// touch that pinched keeps that until it ends, however it ends.
    @GestureState private var touching = false
    @State private var pinchedThisTouch = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(design: Design, startPage: Int = 0, onLoopChange: @escaping (Bool) -> Void = { _ in }) {
        // An expanded whiteboard shows its bounds and their margin, as it
        // exports (Whiteboards).
        let shown = Whiteboards.flattened(design)
        self.design = shown
        self.startPage = startPage
        self.onLoopChange = onLoopChange
        boards = Set(design.pages.filter(Whiteboards.isExpanded).map(\.id))
        _session = State(initialValue: PresentSession(design: shown))
    }

    private var index: Int { session.index }
    private var page: Page { session.page }
    private var autoplay: Bool { session.autoplay }

    var body: some View {
        // A ZStack, not a Group: a Group hands its modifiers to each branch,
        // so a screen plugged in or pulled out mid-talk would run onAppear
        // again and start the talk over. Here the talk lives on the stack.
        ZStack {
            // With a second screen the slides are there, and the phone is
            // the presenter's console; without one, the phone presents.
            if ExternalDisplay.shared.attached {
                console
            } else {
                GeometryReader { geo in onPhone(in: geo.size) }
            }
        }
        .statusBarHidden(true)
        .background(keyCommands)
        .sheet(isPresented: $showingPages) {
            PresenterPagesSheet(design: design, current: index) { turn(to: $0) }
        }
        .sheet(isPresented: $showingEffects) {
            PresentEffectsSheet { show(effect: $0) }
        }
        .onAppear {
            // A hidden page is not shown: Present starts at the next page
            // that is, or the one before when none after it is.
            let asked = min(max(startPage, 0), design.pages.count - 1)
            session.index = PageVisibility.start(at: asked, in: design.visiblePageIndices) ?? asked
            started = Date()
            timer = PresenterTimer(startingAt: started)
            now = started
            musicFrom = AudioMix.pageStart(design: design, index: index)
            UIApplication.shared.isIdleTimerDisabled = true
            ExternalDisplay.shared.session = session
            pageArrived()
        }
        .onDisappear {
            autoplayTask?.cancel()
            settleTask?.cancel()
            exitTask?.cancel()
            sound.stop(fade: true)
            // The talk's clips' players: an export's readers are its own.
            ClipPlayers.shared.closeAll()
            UIApplication.shared.isIdleTimerDisabled = false
            if ExternalDisplay.shared.session === session { ExternalDisplay.shared.session = nil }
        }
        .onReceive(clock) { now = $0 }
        .onChange(of: ExternalDisplay.shared.attached) { _, attached in displayChanged(attached) }
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

    /// The talk on the phone itself: the page full screen, tap or swipe to
    /// turn it, the bar and the notes over it.
    private func onPhone(in size: CGSize) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PresentStage(session: session, size: size)
                .scaleEffect(onBoard ? boardZoom * pinching : 1)
                .offset(onBoard ? boardOffset : .zero)
                .gesture(swipe)
                .simultaneousGesture(boardPinch)
                .simultaneousGesture(touch)
                .onTapGesture { location in
                    // A linked element opens its link, as a click on it
                    // does in the PDF — where the page is fitted, so not
                    // while a whiteboard is pinched in.
                    if !zoomedIn, let url = link(at: location, in: size) { open(url) }
                    else if location.x > size.width * 0.66 { go(1) }
                    else if location.x < size.width * 0.33 { go(-1) }
                    else { withAnimation { showingChrome.toggle() } }
                }
                .accessibilityLabel(spokenPlace)
                .accessibilityActions { pageActions }
            if showingChrome { chrome }
            if showingChrome && onBoard { zoomToFit }
            if let linkRefused { refusedNote(linkRefused) }
        }
        .onChange(of: session.index) { _, _ in fitBoard() }
        // Ended or cancelled, the touch is over, and the next starts clean.
        .onChange(of: touching) { _, down in
            if !down { pinchedThisTouch = false }
        }
    }

    // MARK: whiteboards

    /// How far a whiteboard page pinches in, over its fit.
    static let boardMaxZoom: CGFloat = 8

    private var onBoard: Bool { boards.contains(page.id) }

    /// A whiteboard pinched in or moved, when a drag pans it rather than
    /// turning the page.
    private var zoomedIn: Bool { onBoard && (boardZoom > 1 || boardPan != .zero) }

    private var boardOffset: CGSize {
        CGSize(width: boardPan.width + panning.width, height: boardPan.height + panning.height)
    }

    /// A swipe turns the page; on a whiteboard pinched in, a drag pans it.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .updating($panning) { value, state, _ in
                if zoomedIn && !magnifying { state = value.translation }
            }
            .updating($swiping) { _, state, _ in state = true }
            .onEnded { value in
                let pinched = pinchedThisTouch || magnifying
                pinchedThisTouch = false
                if onBoard && pinched { return }
                if zoomedIn {
                    boardPan.width += value.translation.width
                    boardPan.height += value.translation.height
                } else if value.translation.width < 0 {
                    go(1)
                } else {
                    go(-1)
                }
            }
    }

    /// The whole touch, for as long as any finger is down.
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
    }

    /// Two fingers pinch a whiteboard in, never out past its fit.
    private var boardPinch: some Gesture {
        MagnifyGesture()
            .updating($pinching) { value, state, _ in
                if onBoard { state = value.magnification }
            }
            .updating($magnifying) { _, state, _ in state = true }
            .onChanged { _ in
                if onBoard { pinchedThisTouch = true }
            }
            .onEnded { value in
                // The rest of the touch still sees the pinch: a finger
                // left down cannot then swipe the page over.
                if !swiping && !touching { pinchedThisTouch = false }
                guard onBoard else { return }
                boardZoom = min(max(boardZoom * value.magnification, 1), Self.boardMaxZoom)
                if boardZoom == 1 { boardPan = .zero }
            }
    }

    /// Back to the whole whiteboard.
    private func fitBoard() {
        boardZoom = 1
        boardPan = .zero
    }

    /// Zoom to fit, under a whiteboard page: it comes up whole, and comes
    /// back to it.
    private var zoomToFit: some View {
        VStack {
            Spacer()
            Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { fitBoard() } } label: {
                Text("Zoom to fit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }
            .padding(.bottom, 40)
        }
    }

    /// A screen attached or taken away. Either way no one is pointing any
    /// more: a finger held on the console when it goes is never let go of.
    /// Back on the phone, whose own clock has no pause, the console's grid
    /// closes and a timer paused there runs on from where it stood, as on
    /// the Android twin.
    private func displayChanged(_ attached: Bool) {
        session.pointer = nil
        guard !attached else { return }
        showingPages = false
        if timer.paused { timer.toggle(at: Date()) }
        now = Date()
    }

    /// Turning the page without a swipe or a tap on its edge, for VoiceOver
    /// and Switch Control — the same turn, transition and autoplay a swipe
    /// gives. Both are always there, as on the Android twin; at either end
    /// the one that goes nowhere does nothing.
    @ViewBuilder
    private var pageActions: some View {
        Button("Next page") { go(1) }
        Button("Previous page") { go(-1) }
        ForEach(Self.links(on: page, in: design), id: \.self) { url in
            Button("Open \(Links.shown(url))") {
                if let target = URL(string: url) { open(target) }
            }
        }
    }

    /// The presenter's console, the slides being on the screen attached.
    private var console: some View {
        PresenterConsole(session: session,
                         elapsed: timeString,
                         timerPaused: timer.paused,
                         onPage: max(0, now.timeIntervalSince(session.shownAt)),
                         place: place,
                         toggleTimer: { timer.toggle(at: Date()); now = Date() },
                         resetTimer: { timer.reset(at: Date()); now = Date() },
                         previous: { go(-1) },
                         next: { go(1) },
                         end: { dismiss() },
                         showPages: { showingPages = true }) {
            soundButton
            autoplayButton
            loopButton
            effectsButton
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
        var label = tr("Page %d of %d", place.number, place.count)
        if let title = page.title.flatMap(PageTitles.kept) { label += ", " + title }
        return label
    }

    /// The Notes button, as VoiceOver says it.
    static func notesLabel(hasNotes: Bool) -> String {
        hasNotes ? tr("Notes") : tr("Notes, none for this page")
    }

    /// "No app here opens example.com/menu" — the link as the page shows it.
    static func refusedText(_ url: String) -> String {
        tr("No app here opens %@", Links.shown(url))
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
    /// PresentStage does; nil where there is none. Not kept to the page, so
    /// an element hanging off it opens its link in the margin too.
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

    /// Where the exits begin, `span` before the hold — or later, where the
    /// clock stood when autoplay was turned off after they had begun, so
    /// elements already gone stay gone; none when nothing leaves.
    static func heldPoint(hold: Double, span: Double, stoppedAt: Double?) -> Double? {
        guard span > 0 else { return nil }
        return max(0, hold - span, stoppedAt ?? 0)
    }

    /// When the page's movement is over: its last entrance, or its hold for a
    /// drift or an exit; never, for a loop, a clip or an animated picture,
    /// which plays while the page is up. An element with a timing comes and
    /// goes on the page's clock, so it plays until the last of those.
    private func motionEnd(_ page: Page) -> Double {
        let elements = design.drawnElements(on: page)
        if elements.contains(where: { VideoStore.isVideo($0.src) || AnimStore.isAnim($0.src) }) { return .infinity }
        var end = elements.compactMap { el in el.animation.map { (el.timing?.start ?? 0) + $0.end } }.max() ?? 0
        // A caption box's words change through the page's whole hold.
        if elements.contains(where: { $0.kenBurns != nil || $0.exitAnimation != nil || Captions.plays($0) }) {
            end = max(end, session.holdSeconds(page))
        }
        end = max(end, elements.compactMap { $0.timing.map { $0.end ?? $0.start } }.max() ?? 0)
        return end
    }

    /// The page just came up: its clock starts, and stops once all of it is
    /// at rest; its clips are heard from now, the music playing on.
    private func pageArrived() {
        session.shownAt = Date()
        session.exitZero = session.shownAt
        session.stoppedAt = nil
        startSound()
        settle(after: motionEnd(page))
    }

    /// The clock that plays the page runs, and stops `seconds` from now;
    /// never, when they are not finite.
    private func settle(after seconds: Double) {
        session.settled = false
        settleTask?.cancel()
        guard seconds.isFinite else { return }
        let showing = index
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, seconds) + 0.1))
            guard !Task.isCancelled, showing == index else { return }
            session.settled = true
        }
    }

    /// Going on by hand from a page whose elements leave: its exits' clock
    /// runs on from where it was held through them — the clips playing on,
    /// not started again — and the page turns once they are done. False when
    /// there is nothing to play first: no exits, autoplay, Reduce Motion.
    private func beginExit(to next: Int, looping: Bool = false) -> Bool {
        guard session.exitFrom == nil, let held = session.heldAt(page), PresentSession.moves(page, in: design),
              !reduceMotion else { return false }
        let left = max(0, session.holdSeconds(page) - held)
        session.exitFrom = Date()
        settle(after: max(left, motionEnd(page) - Date().timeIntervalSince(session.shownAt)))
        let showing = index
        exitTask?.cancel()
        exitTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled, showing == index else { return }
            turn(to: next, looping: looping)
        }
        return true
    }

    /// Autoplay turned on partway through a page whose elements leave: its
    /// exits' clock runs on from where it was held, and the page turns at
    /// its hold on that clock, rather than its exits playing out early and
    /// the page standing empty. The page's own clock, which its loops and
    /// clips play by, is not set back.
    private func autoplayFromHere() {
        guard session.exitFrom == nil else { return }
        let span = session.exitSpan(page)
        let hold = session.holdSeconds(page)
        guard span > 0, PresentSession.moves(page, in: design), !reduceMotion else {
            scheduleAdvance()
            return
        }
        let held = Self.heldPoint(hold: hold, span: span, stoppedAt: session.stoppedAt) ?? 0
        let reached = min(Date().timeIntervalSince(session.exitZero), held)
        session.exitZero = Date().addingTimeInterval(-reached)
        settle(after: max(motionEnd(page) - Date().timeIntervalSince(session.shownAt), hold - reached, 0))
        scheduleAdvance(after: max(hold - reached, 0.1))
    }

    /// Autoplay turned off: the exits' clock stays where it stands, waiting
    /// there for the person to go on, rather than going back to where they
    /// begin and bringing back elements that have already left.
    private func autoplayStopped() {
        guard session.exitFrom == nil else { return }
        session.stoppedAt = min(Date().timeIntervalSince(session.exitZero), session.holdSeconds(page))
    }

    /// The sound with the page's clock: the clips of the page up, the music
    /// on from where it is in the talk; none with the sound off.
    private func startSound() {
        guard soundOn else {
            sound.stop()
            return
        }
        sound.tracks(design: design, offset: musicFrom, since: started, film: .infinity)
        let length = Self.clipPageLength(autoplay: autoplay, hold: session.holdSeconds(page))
        sound.page(AudioMix.clips(design: design, page: page), since: session.shownAt, length: length)
    }

    /// How long a page's clips are heard for, for their fades: its hold
    /// when autoplay turns it on its own timing, so a looping clip fades out
    /// by the turn; none when it waits to be turned, and a looping clip
    /// plays on. As the Android twin's Present.
    static func clipPageLength(autoplay: Bool, hold: Double) -> Double? {
        autoplay ? hold : nil
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
                soundButton
                autoplayButton
                loopButton
                effectsButton
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
                    Text(page.notes?.isEmpty == false ? page.notes! : tr("No notes for this page."))
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

    /// The speaker, only when the design has something to hear.
    @ViewBuilder
    private var soundButton: some View {
        if heard {
            Button {
                soundOn.toggle()
                startSound()
            } label: {
                Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill").padding(10)
            }
            .accessibilityLabel(soundOn ? tr("Sound on") : tr("Sound off"))
        }
    }

    private var autoplayButton: some View {
        Button {
            session.autoplay.toggle()
            if autoplay {
                autoplayFromHere()
            } else {
                autoplayTask?.cancel()
                autoplayStopped()
            }
        } label: { Image(systemName: autoplay ? "pause.fill" : "play.fill").padding(10) }
            .accessibilityLabel(autoplay ? tr("Pause autoplay") : tr("Autoplay"))
    }

    /// Loop, beside Autoplay: lit while on. The design keeps it.
    private var loopButton: some View {
        Button {
            session.loop.toggle()
            onLoopChange(session.loop)
        } label: {
            Image(systemName: "repeat")
                .padding(8)
                .background(Circle().fill(Color.white.opacity(session.loop ? 0.3 : 0)))
                .opacity(session.loop ? 1 : 0.6)
        }
        .accessibilityLabel("Loop")
        .accessibilityValue(session.loop ? tr("On") : tr("Off"))
    }

    /// The effects' grid, for a phone with no keyboard to give them.
    private var effectsButton: some View {
        Button { showingEffects = true } label: { Image(systemName: "sparkles").padding(10) }
            .accessibilityLabel("Magic shortcuts")
    }

    /// An effect asked for, by key or from the grid: shown on both
    /// screens in place of any other; one of three seconds is let go of
    /// once they are up.
    private func show(effect id: String) {
        session.effects = Presenter.showing(session.effects, adding: id, at: Date())
        guard id != "clear", !Presenter.lasts(id) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Presenter.effectSeconds + 0.05))
            session.effects = Presenter.live(session.effects, at: Date())
        }
    }

    /// A keyboard, or the clicker a presenter holds — which sends Page Down
    /// and Page Up, or the arrows — turns the pages with the same transition
    /// and autoplay a swipe gives, and Escape ends the presentation, as on
    /// the Android twin. The left and right arrows go the way the language
    /// reads: right to left, the left arrow goes on (ReadingDirection).
    private var keyCommands: some View {
        Group {
            Group {
                arrowKey(.right)
                key(.downArrow, tr("Next page")) { go(1) }
                key(.pageDown, tr("Next page")) { go(1) }
                key(.space, tr("Next page")) { go(1) }
                key(.return, tr("Next page")) { go(1) }
            }
            Group {
                arrowKey(.left)
                key(.upArrow, tr("Previous page")) { go(-1) }
                key(.pageUp, tr("Previous page")) { go(-1) }
                key(.home, tr("First page")) { turn(to: design.visiblePageIndices.first) }
                key(.end, tr("Last page")) { turn(to: design.visiblePageIndices.last) }
            }
            key(.escape, tr("End presentation")) { dismiss() }
            // The effects' keys: 1 to 9, B, C, O, Q, U and X.
            ForEach(Presenter.effects) { effect in
                effectKeys(effect)
            }
        }
    }

    /// An effect's key, and for a letter its capital too, with Shift or
    /// Caps Lock: either case shows it, as on the Android twin.
    @ViewBuilder
    private func effectKeys(_ effect: Presenter.Effect) -> some View {
        let typed = KeyEquivalent(Character(effect.key))
        key(typed, effect.name) { show(effect: effect.id) }
        if effect.key.first?.isLetter == true {
            key(typed, effect.name, modifiers: .shift) { show(effect: effect.id) }
            key(typed, effect.name, modifiers: .capsLock) { show(effect: effect.id) }
        }
    }

    /// The left or right arrow, a page on or back as the language reads.
    private func arrowKey(_ arrow: ReadingDirection.Arrow) -> some View {
        let step = ReadingDirection.presentStep(arrow, reading: reading)
        return key(arrow == .left ? .leftArrow : .rightArrow, step > 0 ? tr("Next page") : tr("Previous page")) {
            go(step)
        }
    }

    /// Never mirrored by the system: the arrows' way is arrowKey's to say.
    private func key(_ key: KeyEquivalent, _ title: String, modifiers: EventModifiers = [],
                     action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: modifiers, localization: .withoutMirroring)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    /// The talk's timer: "12:05", "1:02:03".
    private var timeString: String {
        Presenter.clockText(timer.elapsed(at: now))
    }

    /// One page on, or one back, among the pages shown: a hidden page is
    /// stepped over, and with Loop on the last page goes on to the first.
    /// Going on by hand from a page whose elements leave plays them first;
    /// going on again meanwhile turns the page at once.
    private func go(_ delta: Int) {
        let visible = design.visiblePageIndices
        guard delta > 0 else {
            turn(to: PageVisibility.previous(before: index, in: visible))
            return
        }
        guard let next = Presenter.next(after: index, in: visible, loop: session.loop) else { return }
        // Round from the last page to the first.
        let looping = next < index
        if session.exitFrom == nil, !autoplay, beginExit(to: next, looping: looping) { return }
        turn(to: next, looping: looping)
    }

    /// Turn to page `target`, by index; nowhere when it is nil or the page
    /// already up. `looping` is going round from the last page shown to the
    /// first: a turn forward, by the first page's own transition — the
    /// page arrived at, not the one left, as the Android twin's goTo(wrap)
    /// plays it — with the music from its start.
    private func turn(to target: Int?, looping: Bool = false) {
        guard let next = target, next != index, design.pages.indices.contains(next) else { return }
        // Any exits still playing are over; the page leaving keeps its
        // clock as it was drawn. The pointer is on the page leaving, so it
        // goes with it, and so does the effect up, whichever it is, as on
        // the Android twin.
        exitTask?.cancel()
        session.pointer = nil
        session.effects = []
        if looping {
            sound.stop()
            musicFrom = 0
            started = Date()
        }
        let forward = looping || next > index
        // Going on, the page being left decides; going back, the page being
        // returned to, played in reverse. With a hidden page between, that
        // is the page before the gap, as the video plays it. Round the loop,
        // the first page's own, played forward (Presenter.transitionPage).
        let earlier = design.pages[Presenter.transitionPage(from: index, to: next, looping: looping)]
        let via = transition(after: earlier)
        let animation: Animation?
        if via == "cut" || reduceMotion {
            session.moving = .identity
            animation = nil
        } else {
            // Both pages laid out by PageTransitions as the turn goes, the
            // later page on top (zIndex); a fade over its own curve, the
            // others at an even pace, since the layers ease themselves.
            let seconds = PageTransitions.presentSeconds(via, own: earlier.transitionSeconds)
            session.moving = PageTurnEffect.transition(via, forward: forward,
                                                       leaving: design.size(for: page),
                                                       coming: design.size(for: design.pages[next]))
            animation = via == "fade" ? .easeInOut(duration: seconds) : .linear(duration: seconds)
        }
        // The transition is read when the views change, so it is set first,
        // and the page moves on the next turn of the run loop.
        DispatchQueue.main.async {
            withAnimation(animation) {
                session.layer += forward ? 1 : -1
                session.index = next
            }
            session.exitFrom = nil
            pageArrived()
            if autoplay { scheduleAdvance() }
        }
    }

    /// Wait this page's own hold (or the document's) — or `wait` seconds,
    /// when given — then move on; at the last page shown, round to the
    /// first with Loop on, else stop there rather than looping back to a
    /// title slide.
    private func scheduleAdvance(after wait: Double? = nil) {
        autoplayTask?.cancel()
        let delay = wait ?? max(session.holdSeconds(page), 0.5)
        autoplayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, autoplay else { return }
            if Presenter.next(after: index, in: design.visiblePageIndices, loop: session.loop) != nil {
                go(1)
            } else {
                session.autoplay = false
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
