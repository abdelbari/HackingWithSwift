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
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var page: Page { design.pages[min(index, design.pages.count - 1)] }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                pageView(in: geo.size)
                    .id(page.id)
                    .transition(.opacity)
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
        }
        .onDisappear {
            autoplayTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(clock) { _ in elapsed = Date().timeIntervalSince(started) }
    }

    private func pageView(in size: CGSize) -> some View {
        let scale = min(size.width / max(design.width, 1), size.height / max(design.height, 1))
        return PageRenderView(design: design, page: page)
            .scaleEffect(scale)
            .frame(width: design.width * scale, height: design.height * scale)
            .position(x: size.width / 2, y: size.height / 2)
            .accessibilityLabel("Page \(index + 1) of \(design.pages.count)")
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
        withAnimation(.easeInOut(duration: 0.25)) { index = next }
        if autoplay { scheduleAdvance() }
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
