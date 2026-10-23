// Bottom pages bar: thumbnails, add/duplicate/move/delete. Press and hold
// a thumbnail to drag the page to another place in the strip, which scrolls
// on at its ends (PageDragging).

import SwiftUI
import UIKit

struct PagesBar: View {
    @Bindable var store: DesignStore
    @State private var confirmingDelete = false
    @State private var editingNotes = false
    @State private var organizing = false
    /// A page lifted to be dragged along the strip (PageDragging).
    @State private var lift = PageLift()
    @State private var frames = PageFrames()
    @State private var edges = PageEdgeScroll()
    /// True while a lift's press is held, so one the scroll view takes over
    /// is put back.
    @GestureState private var holding = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    private static let space = "pagesBar"
    private static let spacing = 8.0

    var body: some View {
        HStack(spacing: 10) {
            strip

            HStack(spacing: 2) {
                Button { organizing = true } label: { Image(systemName: "square.grid.2x2") }
                    .accessibilityLabel("Organize pages")
                if store.pagePlays {
                    Button {
                        if store.previewTime == nil { store.playPreview() } else { store.stopPreview() }
                    } label: { Image(systemName: store.previewTime == nil ? "play.circle" : "stop.circle") }
                        .accessibilityLabel(store.previewTime == nil ? tr("Play this page's animation") : tr("Stop preview"))
                }
                Menu {
                    Button { store.duplicatePage() } label: {
                        Label("Duplicate page", systemImage: "plus.square.on.square")
                    }
                    Button { store.copyPage() } label: {
                        Label("Copy page", systemImage: "doc.on.doc")
                    }
                    Button { store.pastePage() } label: {
                        Label("Paste page after", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!store.hasPageOnClipboard)
                    // Hiding the only page would leave nothing to present;
                    // a lone page already hidden can still be shown again.
                    if store.design.pages.count > 1 || store.page.hidden == true {
                        Button { store.setPageHidden(store.page.hidden != true) } label: {
                            Label(store.page.hidden == true ? tr("Show page") : tr("Hide page"),
                                  systemImage: store.page.hidden == true ? "eye" : "eye.slash")
                        }
                    }
                    Button { store.setPageLocked(!store.isPageLocked) } label: {
                        Label(store.isPageLocked ? tr("Unlock page") : tr("Lock page"),
                              systemImage: store.isPageLocked ? "lock.open" : "lock")
                    }
                    // An endless canvas round the page, and back to its frame.
                    Button { store.toggleWhiteboard() } label: {
                        Label(store.isWhiteboard ? tr("Collapse") : tr("Expand to whiteboard"),
                              systemImage: store.isWhiteboard ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                } label: { Image(systemName: "plus.square.on.square") }
                    .accessibilityLabel(pageMenuLabel)
                    .accessibilityShowsLargeContentViewer()
                // Said as what they do to the page: the symbols alone read
                // as "Back" and "Forward", which sound like navigation.
                Button { store.movePage(by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(store.pageIndex == 0)
                    .accessibilityLabel("Move page left")
                    .accessibilityShowsLargeContentViewer()
                Button { store.movePage(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(store.pageIndex >= store.design.pages.count - 1)
                    .accessibilityLabel("Move page right")
                    .accessibilityShowsLargeContentViewer()
                Button { editingNotes = true } label: {
                    Image(systemName: (store.page.notes?.isEmpty == false)
                          ? "note.text" : "note")
                }
                .accessibilityLabel("Page title and notes")
                .accessibilityShowsLargeContentViewer()
                Button(role: .destructive) {
                    // A page can hold an hour's work and the bin is next to
                    // the arrows. Undo covers it, but only if you notice
                    // before the next edit pushes it down the stack.
                    // A locked page always asks.
                    if store.page.elements.isEmpty && !store.isPageLocked {
                        store.deletePage()
                    } else {
                        confirmingDelete = true
                    }
                } label: { Image(systemName: "trash") }
                    .disabled(store.design.pages.count <= 1)
                    .accessibilityLabel("Delete page \(store.pageIndex + 1)")
                    .accessibilityShowsLargeContentViewer()
            }
            .font(.subheadline)
            .padding(.trailing, 12)
        }
        .frame(height: 72)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Divider() }
        .asksBeforeDeletingPage($confirmingDelete, store: store)
        .sheet(isPresented: $editingNotes) {
            PageNotesSheet(store: store)
        }
        .sheet(isPresented: $organizing) {
            PageOrganizerSheet(store: store)
        }
    }

    /// The page menu as VoiceOver says it: what is in it.
    private var pageMenuLabel: String {
        let locked = store.isPageLocked
        if store.page.hidden == true {
            return locked ? tr("Duplicate, copy, paste, show or unlock page") : tr("Duplicate, copy, paste, show or lock page")
        }
        if store.design.pages.count > 1 {
            return locked ? tr("Duplicate, copy, paste, hide or unlock page") : tr("Duplicate, copy, paste, hide or lock page")
        }
        return locked ? tr("Duplicate, copy, paste or unlock page") : tr("Duplicate, copy, paste or lock page")
    }

    /// The thumbnails, made as they scroll into view, then +.
    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: CGFloat(Self.spacing)) {
                    ForEach(Array(store.design.pages.enumerated()), id: \.element.id) { index, page in
                        pageThumb(index: index, page: page)
                    }
                    Button { store.addPage() } label: {
                        Image(systemName: "plus")
                            .frame(width: 40, height: 56)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                .foregroundStyle(.secondary))
                    }
                    .accessibilityLabel("Add page")
                }
                .padding(.horizontal, 12)
                // A tap goes to the page under it; a press and hold lifts it.
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .named(Self.space)) { point in
                    if let i = frames.page(at: point, in: store.design.pages) { store.setPage(i) }
                }
                .gesture(liftGesture(proxy: proxy))
            }
            .coordinateSpace(name: Self.space)
            .reportsViewport(to: frames)
            .overlay {
                PageGapMarker(lift: lift, pages: store.design.pages, frames: frames, spacing: Self.spacing)
            }
        }
        .onChange(of: holding) { _, held in if !held { putDown(moving: false) } }
        .onDisappear { edges.stop() }
        // The pages lie left to right in any language, as the timeline's
        // and the canvas's do, so Move page left and right are where they
        // say; the buttons beside them read as the language does.
        .designDirection()
    }

    /// Press and hold, then drag: the page lifted and carried along the
    /// strip, the gap it would go into marked, the strip scrolled on at its
    /// ends.
    private func liftGesture(proxy: ScrollViewProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .updating($holding) { value, held, _ in
                if case .second(true, _) = value { held = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value, let drag else { return }
                if !lift.isActive {
                    let pages = store.design.pages
                    guard let i = frames.page(at: drag.startLocation, in: pages) else { return }
                    lift = PageLift(ids: [pages[i].id])
                    store.buzz(.tick)
                }
                lift.finger = drag.location
                lift.gap = PageOrder.gap(at: drag.location, frames: frames.indexed(store.design.pages))
                let edge = PageOrder.edgeScroll(Double(drag.location.x), length: Double(frames.viewport.width), margin: 44)
                edges.hold(edge) { direction in scrollOn(direction, proxy: proxy) }
            }
            .onEnded { _ in putDown(moving: true) }
    }

    /// One thumbnail further along, the gap found again under the finger;
    /// false at either end.
    private func scrollOn(_ direction: Int, proxy: ScrollViewProxy) -> Bool {
        let pages = store.design.pages
        let shown = frames.shown(pages, vertical: false)
        guard lift.isActive, let edge = direction > 0 ? shown.last : shown.first else { return false }
        let target = min(max(edge + direction, 0), pages.count - 1)
        guard target != edge else { return false }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(pages[target].id, anchor: direction > 0 ? .trailing : .leading)
        }
        if let finger = lift.finger { lift.gap = PageOrder.gap(at: finger, frames: frames.indexed(pages)) }
        return true
    }

    /// Let go: the page moved to the gap as one undo step when `moving`,
    /// else — the press taken over — put back.
    private func putDown(moving: Bool) {
        edges.stop()
        guard lift.isActive else { return }
        if moving, let gap = lift.gap { store.movePages(lift.ids, to: gap) }
        lift = PageLift()
    }

    private func pageThumb(index: Int, page: Page) -> some View {
        let pageSize = store.design.size(for: page)
        let aspect = pageSize.width / max(pageSize.height, 1)
        let spoken = Self.spokenThumb(number: index + 1, title: page.title, current: index == store.pageIndex,
                                      hidden: page.hidden == true, locked: PageLocks.isLocked(page))
        return thumbFace(index: index, page: page, aspect: aspect)
            .opacity(lift.ids.contains(page.id) ? 0.35 : 1)
            .reportsPageFrame(page.id, in: Self.space, to: frames)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { store.setPage(index) }
            .pageMoveActions(store, index: index, id: page.id)
    }

    private func thumbFace(index: Int, page: Page, aspect: CGFloat) -> some View {
        PageThumbnail(design: store.design, page: page)
            .frame(width: 56 * aspect, height: 56)
            .clipped()
            // A hidden page is faded, and its number carries the eye
            // struck through, as on the Android twin — beside the number
            // rather than in a corner of its own, which a story-shaped
            // thumbnail has no room for.
            .opacity(page.hidden == true ? 0.4 : 1)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 2) {
                    Text("\(index + 1)")
                    if page.hidden == true { Image(systemName: "eye.slash") }
                    if PageLocks.isLocked(page) { Image(systemName: "lock.fill") }
                }
                .font(.caption2.weight(.bold))
                .imageScale(.small)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                .padding(2)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(index == store.pageIndex ? Theme.accent : Color(.systemGray4),
                        lineWidth: index == store.pageIndex ? 2 : 1))
            // Differentiate Without Colour: the current page is also the
            // one with the check, not only the one with the purple edge.
            .overlay(alignment: .bottomTrailing) {
                if differentiate && index == store.pageIndex {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white, Theme.accent)
                        .padding(2)
                }
            }
    }

    /// What VoiceOver says for a page's thumbnail: which page and its title,
    /// whether it is the one on screen, and whether it is hidden or locked.
    static func spokenThumb(number: Int, title: String?, current: Bool, hidden: Bool,
                            locked: Bool = false) -> String {
        var label = tr("Page %d", number)
        if let title = title.flatMap(PageTitles.kept) { label += ", " + title }
        if current { label += ", " + tr("current") }
        if hidden { label += ", " + tr("hidden") }
        if locked { label += ", " + PageLocks.spoken }
        return label
    }
}

extension View {
    /// Deleting a page with something on it, or a locked one, asks first —
    /// from the pages bar, or a page's header while scrolling through
    /// pages. The page on screen is the one asked about.
    func asksBeforeDeletingPage(_ isPresented: Binding<Bool>, store: DesignStore) -> some View {
        confirmationDialog("Delete page \(store.pageIndex + 1)?",
                           isPresented: isPresented, titleVisibility: .visible) {
            Button("Delete page", role: .destructive) { store.deletePage() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(PageLocks.deleteMessage(elements: store.page.elements.count, locked: store.isPageLocked))
        }
    }
}

/// Notes about a page rather than on it: what to say over this slide, what
/// the client asked for, which photo still needs replacing — and the page's
/// title. Never rendered, so they cannot leak into an export.
///
/// Typing a note is one Undo, as on the Android twin: the keystrokes change
/// the page without recording, and the step is closed once — on Done, when
/// the sheet goes, or before another setting here makes a step of its own.
/// Each keystroke used to be a step, so Undo took a note back a letter at a
/// time and pushed everything older out of the history. A title typed is one
/// Undo the same way, and a step apart from the notes.
struct PageNotesSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// The notes as the sheet found them, to tell a real edit from typing
    /// that ended where it began.
    @State private var notesBefore: String?
    @State private var typing = false
    /// The title as typed, spaces and all: the page keeps it trimmed, which
    /// read back into the field would eat the space before the next word.
    @State private var titleText = ""
    @State private var titleBefore: String?
    @State private var typingTitle = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $titleText, prompt: Text("Intro, Agenda, Thank you…"))
                        .onChange(of: titleText) { typeTitle() }
                } header: {
                    Text("Title")
                } footer: {
                    Text("Names the page in the page list, Find and Present. Never on the page or in an export.")
                }
                Section("Notes") {
                    TextEditor(text: Binding(
                        get: { store.page.notes ?? "" },
                        set: { text in typeNotes(text) }))
                    .frame(minHeight: 120)
                }
                Section {
                    let hold = store.page.holdSeconds ?? store.design.motion?.secondsPerPage ?? MotionSettings().secondsPerPage
                    Stepper(value: Binding(
                        get: { hold },
                        set: { v in finishTyping(); store.applyToPage { $0.holdSeconds = v } }),
                            in: MotionSettings.pageHoldRange, step: 0.5) {
                        Text(holdLabel(hold))
                    }
                    Picker("Transition to the next page", selection: Binding(
                        get: { store.page.transition ?? "default" },
                        set: { v in finishTyping(); store.applyToPage { $0.transition = v == "default" ? nil : v } })) {
                        // In Android's order, the shared list's.
                        Text("Document setting").tag("default")
                        Text("Fade").tag("fade")
                        // The film editor's cut, not the clipboard's.
                        Text(tr("Cut", context: "transition")).tag("cut")
                        Text("Slide").tag("slide")
                        Text("Push").tag("push")
                        Text("Wipe").tag("wipe")
                        Text("Circle").tag("circle")
                        Text("Zoom").tag("zoom")
                    }
                    // A cut takes no time, so has no length to choose; a
                    // length from a file shows as the nearest — as Android
                    // has both.
                    if PageTransitions.transitionKind(after: store.page, in: store.design) != "cut" {
                        Picker("Length", selection: Binding(
                            get: { PageTransitions.lengthName(store.page.transitionSeconds) },
                            set: { name in
                                finishTyping()
                                let seconds = PageTransitions.lengths.first { $0.name == name }?.seconds
                                store.applyToPage { $0.transitionSeconds = seconds }
                            })) {
                            ForEach(PageTransitions.lengths.map { $0.name }, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    // Only when there are other pages to make turn so.
                    if store.design.pages.count > 1 {
                        Button("Apply to all pages") {
                            finishTyping()
                            store.applyTransitionToAllPages()
                        }
                    }
                    if store.page.holdSeconds != nil {
                        Button("Use the document's timing") {
                            finishTyping()
                            store.applyToPage { $0.holdSeconds = nil }
                        }
                    }
                } header: {
                    Text("In video and presentation")
                }
            }
                .navigationTitle(PageTitles.named(store.pageIndex + 1, title: store.page.title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            finishTyping()
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
        .onAppear { titleText = store.page.title ?? "" }
        .onDisappear { finishTyping() }
    }

    /// "Hold 3.0s", and "(document setting)" when the page has no time of
    /// its own.
    private func holdLabel(_ hold: Double) -> String {
        let seconds = String(format: "%.1f", hold)
        return store.page.holdSeconds == nil ? tr("Hold %@s (document setting)", seconds) : tr("Hold %@s", seconds)
    }

    /// A keystroke in the title: cut at the cap, and the page given the title
    /// trimmed, with the step left open. The field showing the page's own
    /// title, as it does when the sheet opens, is no edit at all.
    private func typeTitle() {
        let capped = String(titleText.prefix(PageTitles.maxLength))
        // Cut back, which comes round here again with the shorter text.
        guard capped == titleText else { titleText = capped; return }
        let title = PageTitles.cleaned(capped)
        guard typingTitle || title != store.page.title else { return }
        if !typingTitle {
            // The notes are a step of their own.
            finishNotes()
            titleBefore = store.page.title
            typingTitle = true
        }
        store.beginGesture()
        let index = store.pageIndex
        guard store.design.pages.indices.contains(index) else { return }
        store.design.pages[index].title = title
    }

    /// Close the title's typing as one step, or as none when it ended as it
    /// began.
    private func finishTitle() {
        guard typingTitle else { return }
        typingTitle = false
        if store.page.title == titleBefore {
            store.endGesture()
        } else {
            store.commit()
        }
    }

    /// Whatever is being typed, closed: before another setting here makes a
    /// step of its own, and when the sheet goes.
    private func finishTyping() {
        finishTitle()
        finishNotes()
    }

    /// A keystroke: the page changes, and the step stays open.
    private func typeNotes(_ text: String) {
        if !typing {
            // The title is a step of its own.
            finishTitle()
            notesBefore = store.page.notes
            typing = true
        }
        store.beginGesture()
        let index = store.pageIndex
        guard store.design.pages.indices.contains(index) else { return }
        store.design.pages[index].notes = text.isEmpty ? nil : text
    }

    /// Close the typing as one step — or as none, when the note ended as it
    /// began.
    private func finishNotes() {
        guard typing else { return }
        typing = false
        if store.page.notes == notesBefore {
            store.endGesture()
        } else {
            store.commit()
        }
    }
}

/// A page rendered once into a bitmap rather than kept as a live element
/// tree. A ten-page design would otherwise hold every element of every page
/// in the hierarchy — each text element re-running CoreText layout — just to
/// fill a row of 56pt thumbnails.
///
/// The bitmap comes from ThumbnailCache: kept for the page as it stands, or
/// made in its turn, those on screen first (`priority` 0). `task(id: page)`
/// asks again exactly when the page's contents change, because Page is
/// Equatable — but "when the contents change" includes every frame of a
/// drag, so a thumbnail already drawn asks again only once the page stops
/// changing (below).
struct PageThumbnail: View {
    let design: Design
    let page: Page
    /// How many pixels wide it is drawn.
    var pixelWidth = 140
    /// Its place in line when several wait to be drawn: 0 on screen, more
    /// further off.
    var priority = 0
    /// What shows until the thumbnail is made: the page drawn live, where
    /// the column shows a page near the view as a picture — the page itself
    /// meanwhile, as the Android twin draws it — or white when nil.
    var fallback: AnyView?
    @State private var image: UIImage?

    init(design: Design, page: Page, pixelWidth: Int = 140, priority: Int = 0, fallback: AnyView? = nil) {
        self.design = design
        self.page = page
        self.pixelWidth = pixelWidth
        self.priority = priority
        self.fallback = fallback
        // The page's last thumbnail shows from the first frame — never
        // white, nor the page drawn live, for a frame first — found by its
        // id alone, as the Android twin's PagePictures keeps one a page: the
        // key, a hash of the whole page, is made in the task below once per
        // change of the page, never here, where every frame of a pan builds
        // the view again. One for the page as it stands follows from the
        // task, as the last does after an edit.
        var kept: UIImage?
        MainActor.assumeIsolated { kept = ThumbnailCache.shared.lastThumbnail(pageId: page.id) }
        _image = State(initialValue: kept)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if let fallback {
                fallback
            } else {
                Color.white
            }
        }
        .task(id: thumbKey) {
            // Debounced once drawn, because a drag rewrites the page on every
            // frame. Without the wait, each of those frames started a full
            // ImageRenderer pass over the whole page — rasterising every
            // element, re-running CoreText for every text run — to refresh a
            // 56pt thumbnail nobody is looking at mid-gesture.
            //
            // task(id:) cancels the in-flight task whenever the id changes, so
            // during continuous movement none of them survive the sleep and
            // exactly one render happens once the page stops changing. Pages
            // that are not being edited keep the same id throughout, so they
            // are never re-rendered at all. A look made off the main thread
            // goes through the same wait: a dial dragged, or a clip playing,
            // finishes a run of them, which end in one render of each page
            // with such a photo, and none of any other page. A thumbnail not
            // yet drawn — scrolled into view — asks at once, and one kept
            // shows straight away.
            if image != nil {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
            }
            let key = ThumbnailCache.key(page: page, design: design, baked: bakedVersion,
                                         subjects: subjectsVersion, pixelWidth: pixelWidth)
            if let made = await ThumbnailCache.shared.image(key, priority: priority, make: render) {
                image = made
            }
        }
    }

    /// The thumbnail's task id: the page, the master's elements drawn
    /// behind it, its number and the page count when it shows one
    /// (Design.pageNumbering) — so an edit of the master, or pages moved,
    /// draws it again, as ThumbnailCache.key keeps it apart — for a page
    /// with a photo whose clarity or pixelate is made off the main thread
    /// how many such looks are made, for one with a photo whose focus keeps
    /// its subject sharp how many subjects are found — so a new one draws
    /// it again — and its width.
    private struct ThumbKey: Equatable {
        let page: Page
        let master: [Element]
        let number: Int
        let count: Int
        let baked: Int
        let subjects: Int
        let width: Int
    }

    private var thumbKey: ThumbKey {
        let numbering = design.pageNumbering(shownOn: page)
        return ThumbKey(page: page, master: design.masterElements(behind: page),
                        number: numbering?.number ?? 0, count: numbering?.count ?? 0,
                        baked: bakedVersion, subjects: subjectsVersion, width: pixelWidth)
    }

    /// The count of looks made off the main thread, read only by a page
    /// that has a photo waiting for one; 0 for any other, which never draws
    /// again for them.
    private var bakedVersion: Int {
        guard design.drawnElements(on: page).contains(where: ImageFilterEngine.makesLater) else { return 0 }
        return ImageFilterEngine.looksBaked.version
    }

    /// The count of focus subjects found off the main thread, read only by
    /// a page with a photo whose focus waits for its subject; 0 for any
    /// other, which a subject found elsewhere never draws again.
    private var subjectsVersion: Int {
        guard design.drawnElements(on: page).contains(where: { $0.focusBlur?.subject == true }) else { return 0 }
        return ImageFilterEngine.subjectsFound.version
    }

    @MainActor
    private func render() -> UIImage? {
        // On screen, so a focus subject is found off the main thread rather
        // than holding up the strip; the thumbnail is drawn again when it is.
        // An expanded whiteboard as its bounds and their margin.
        let shown = Whiteboards.drawn(design, page)
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: shown).environment(\.onScreen, true))
        renderer.scale = max(0.02, CGFloat(pixelWidth) / max(design.size(for: shown).width, 1))
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
