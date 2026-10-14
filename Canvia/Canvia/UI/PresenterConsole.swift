// The presenter's console: what the phone shows while the slides are on a
// second screen. The page up, small — press and hold on it to point, a red
// dot on the screen at the same place on the page — the page coming (or
// "End of presentation"), the page's title, the time on it beside its hold,
// the notes in large type made larger or smaller with A− and A+, the talk's
// timer (tap to pause, hold to reset), the count, and Previous, Pages and
// Next. Clips play on the screen only: here the pages are drawn still.

import SwiftUI

struct PresenterConsole<Controls: View>: View {
    let session: PresentSession
    /// The talk's timer, as `Presenter.clockText` writes it.
    let elapsed: String
    let timerPaused: Bool
    /// Seconds the page up has been showing.
    let onPage: Double
    /// Where the page up sits among the pages shown.
    let place: (number: Int, count: Int)
    let toggleTimer: () -> Void
    let resetTimer: () -> Void
    let previous: () -> Void
    let next: () -> Void
    let end: () -> Void
    let showPages: () -> Void
    /// The sound, autoplay, loop and effects buttons, as the phone's own
    /// bar has them.
    @ViewBuilder let controls: Controls
    @State private var notesSize = Presenter.defaultNotesSize

    var body: some View {
        VStack(spacing: 12) {
            topBar
            slides
            heading
            notes
            bottomBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
    }

    private var visible: [Int] { session.design.visiblePageIndices }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button(action: end) { Image(systemName: "xmark").padding(10) }
                .accessibilityLabel("End presentation")
            timer
            Spacer()
            Text(PageTitles.counter(place.number, of: place.count, title: nil))
                .font(.headline.monospacedDigit())
                .accessibilityLabel("Page \(place.number) of \(place.count)")
            Spacer()
            controls
        }
    }

    /// The talk's timer, as on the Android twin: a tap pauses it or starts
    /// it again, and a press and hold offers Pause or Resume timer and Reset
    /// timer.
    private var timer: some View {
        Menu {
            Button(timerPaused ? "Resume timer" : "Pause timer", action: toggleTimer)
            Button("Reset timer", action: resetTimer)
        } label: {
            Label(elapsed, systemImage: timerPaused ? "pause.circle" : "timer")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(timerPaused ? Color.white.opacity(0.55) : Color.white)
        } primaryAction: {
            toggleTimer()
        }
        .accessibilityLabel("Elapsed \(elapsed)")
        .accessibilityValue(timerPaused ? "paused" : "")
    }

    private var slides: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                caption("Now")
                PresenterPreview(session: session)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                caption("Next")
                upNext
            }
            .frame(width: 128)
        }
        .frame(height: 190)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .accessibilityHidden(true)
    }

    /// The page coming, drawn still, or where the talk ends.
    @ViewBuilder
    private var upNext: some View {
        if let index = Presenter.next(after: session.index, in: visible, loop: session.loop) {
            let page = session.design.pages[index]
            let size = session.design.size(for: page)
            PageThumbnail(design: session.design, page: page)
                .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityLabel("Next, " + PageTitles.counter(index < session.index ? 1 : place.number + 1,
                                                                  of: place.count, title: page.title))
        } else {
            Text(Presenter.endOfPresentation)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3)))
        }
    }

    /// The page's title, when it has one, and the time on it beside its
    /// hold.
    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(session.page.title.flatMap(PageTitles.kept) ?? "")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            // "This page 0:07 · holds 2.5 s", read as it is written, as on
            // the Android twin.
            Text("This page " + Presenter.pageTime(onPage, hold: session.holdSeconds(session.page)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var notes: some View {
        VStack(spacing: 6) {
            HStack {
                caption("Notes")
                Spacer()
                Button { notesSize = Presenter.notesSize(notesSize, steps: -1) } label: {
                    Text("A−").font(.callout.weight(.semibold)).padding(.horizontal, 8)
                }
                .disabled(notesSize <= Presenter.notesSizes.lowerBound)
                .accessibilityLabel("Smaller notes")
                Button { notesSize = Presenter.notesSize(notesSize, steps: 1) } label: {
                    Text("A+").font(.title3.weight(.semibold)).padding(.horizontal, 8)
                }
                .disabled(notesSize >= Presenter.notesSizes.upperBound)
                .accessibilityLabel("Larger notes")
            }
            ScrollView {
                Text(notesText)
                    .font(.system(size: notesSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Each page's notes begin at their top.
            .id(session.page.id)
        }
        .frame(maxHeight: .infinity)
    }

    private var notesText: String {
        if let notes = session.page.notes, !notes.isEmpty { return notes }
        return "No notes for this page."
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            stepButton("Previous", symbol: "chevron.left", action: previous)
                .disabled(PageVisibility.previous(before: session.index, in: visible) == nil)
            Button(action: showPages) {
                Image(systemName: "square.grid.2x2")
                    .font(.title3)
                    .frame(width: 56, height: 48)
                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Pages")
            stepButton("Next", symbol: "chevron.right", action: next)
                .disabled(Presenter.next(after: session.index, in: visible, loop: session.loop) == nil)
        }
    }

    private func stepButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(title == "Next" ? "Next page" : "Previous page")
    }
}

/// The page up, small and still, fitted to the space it has; a press and
/// hold on it points at the same place on the page on the screen.
struct PresenterPreview: View {
    let session: PresentSession

    var body: some View {
        GeometryReader { geo in
            let design = session.design
            let page = session.page
            let pageSize = design.size(for: page)
            let scale = min(geo.size.width / max(pageSize.width, 1), geo.size.height / max(pageSize.height, 1))
            ZStack {
                PageRenderView(design: design, page: page)
                    .environment(\.onScreen, true)
                    .overlay(alignment: .topLeading) { PointerDot(point: session.pointer, page: pageSize) }
                    .scaleEffect(scale)
                    .frame(width: pageSize.width * scale, height: pageSize.height * scale)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(PresenterPointing.gesture(session: session, in: geo.size))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page up")
        .accessibilityHint("Press and hold to point at the screen")
    }
}
