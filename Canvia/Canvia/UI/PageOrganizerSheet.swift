// Every page at once, as a grid of thumbnails: tap to tick, press and hold
// to lift a page — or every ticked page — and drag it to its new place, the
// gap it would go into marked; + between two thumbnails puts a blank page
// there. Ticked pages are duplicated, copied, hidden, locked or deleted from
// the bar below, and what was copied is pasted from the top. As the Android
// twin's organiser.
//
// The bottom bar shows a strip of thumbnails and moves a page one step at a
// time. That is fine for four pages; for a twenty-page deck, moving the
// closing slide to the front is nineteen taps. Here it is one drag.

import SwiftUI

struct PageOrganizerSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var confirmingDelete = false
    /// The pages lifted and where they would go (PageDragging).
    @State private var lift = PageLift()
    @State private var frames = PageFrames()
    @State private var edges = PageEdgeScroll()
    /// True while a lift's press is held, so one the scroll view takes over
    /// is put down where it was.
    @GestureState private var holding = false

    private static let space = "organizer"
    private static let spacing = 20.0

    /// "Copy", or "Copy 3 pages" with several ticked, as on the Android twin.
    private var copyPagesLabel: String {
        selected.count > 1 ? trn("Copy %d page|Copy %d pages", selected.count) : tr("Copy")
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(trn("%d page|%d pages", store.design.pages.count))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
                .confirmationDialog(selected.count == 1 ? tr("Delete this page?") : trn("Delete %d page?|Delete %d pages?", selected.count),
                                    isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        store.deletePages(selected)
                        selected = []
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
        .presentationDetents([.large])
    }

    /// The grid, two columns on a narrow phone up to four on a wide screen
    /// (PageOrder.columns), with the lifted pages' gap over it.
    private var content: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    grid(columns: PageOrder.columns(forWidth: Double(outer.size.width)), proxy: proxy)
                }
                .coordinateSpace(name: Self.space)
                .reportsViewport(to: frames)
                .overlay {
                    PageGapMarker(lift: lift, pages: store.design.pages, frames: frames, spacing: Self.spacing)
                }
            }
        }
        .background(Theme.workspace)
        .onChange(of: holding) { _, held in if !held { putDown(moving: false) } }
        .onDisappear { edges.stop() }
    }

    private func grid(columns: Int, proxy: ScrollViewProxy) -> some View {
        let items = Array(repeating: GridItem(.flexible(), spacing: CGFloat(Self.spacing)), count: columns)
        return LazyVGrid(columns: items, spacing: 16) {
            ForEach(Array(store.design.pages.enumerated()), id: \.element.id) { index, page in
                cell(index: index, page: page)
                    .overlay(alignment: .leading) {
                        if !lift.isActive && index == 0 { addButton(at: 0, leading: true) }
                    }
                    .overlay(alignment: .trailing) {
                        if !lift.isActive { addButton(at: index + 1, leading: false) }
                    }
            }
        }
        // A gap's width at the leading edge, so the + before page 1 sits
        // in it as the others sit between pages.
        .padding(.vertical, 16)
        .padding(.trailing, 16)
        .padding(.leading, CGFloat(Self.spacing))
        // A tap ticks the page under it; a press and hold lifts it.
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .named(Self.space)) { point in
            let pages = store.design.pages
            if let i = frames.page(at: point, in: pages) { toggle(pages[i].id) }
        }
        .gesture(liftGesture(columns: columns, proxy: proxy))
    }

    // MARK: a page

    /// A thumbnail with its number and title under it, ticked or not; faded
    /// while it is lifted.
    private func cell(index: Int, page: Page) -> some View {
        let on = selected.contains(page.id)
        let drawn = VStack(spacing: 6) {
            thumbnail(index: index, page: page, on: on)
            Text(PageTitles.named(index + 1, title: page.title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .opacity(lift.ids.contains(page.id) ? 0.35 : 1)
        .reportsPageFrame(page.id, in: Self.space, to: frames)
        return spoken(drawn, index: index, page: page, on: on)
    }

    /// The whole cell as one thing to VoiceOver, as it reads to the eye —
    /// as the list's row read — ticked by its action, and moved by the
    /// Move page actions.
    private func spoken(_ cell: some View, index: Int, page: Page, on: Bool) -> some View {
        let label = Self.spokenRow(number: index + 1, title: page.title, current: index == store.pageIndex,
                                   hidden: page.hidden == true, locked: PageLocks.isLocked(page),
                                   elements: page.elements.count, notes: page.notes)
        return cell
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(on ? tr("ticked") : tr("not ticked"))
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { toggle(page.id) }
            .pageMoveActions(store, index: index, id: page.id)
    }

    private func thumbnail(index: Int, page: Page, on: Bool) -> some View {
        let size = store.design.size(for: page)
        let current = index == store.pageIndex
        return PageThumbnail(design: store.design, page: page, pixelWidth: 280)
            .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
            // Faded with the eye struck through when hidden, as in the pages
            // bar, and the padlock beside it when locked.
            .opacity(page.hidden == true ? 0.4 : 1)
            .overlay(alignment: .topLeading) { badges(page) }
            .overlay(alignment: .topTrailing) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, on ? Theme.accent : Color.gray)
                    .padding(4)
            }
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(current ? Theme.accent : Theme.hairline, lineWidth: current ? 2.5 : 1))
            .frame(maxWidth: .infinity, maxHeight: 140)
    }

    @ViewBuilder
    private func badges(_ page: Page) -> some View {
        if page.hidden == true || PageLocks.isLocked(page) {
            HStack(spacing: 3) {
                if page.hidden == true { Image(systemName: "eye.slash") }
                if PageLocks.isLocked(page) { Image(systemName: "lock.fill") }
            }
            .font(.caption2.weight(.bold))
            .imageScale(.small)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .padding(3)
        }
    }

    /// + in the gap `gap` — before page 1, between two pages, or after the
    /// last — a blank page there, with the background of the page to its
    /// left (DesignStore.insertPage). Said as Android's gutters say it.
    private func addButton(at gap: Int, leading: Bool) -> some View {
        let label = gap >= store.design.pages.count ? tr("Add a page at the end")
            : tr("Add a page before page %d", gap + 1)
        return Button { store.insertPage(at: gap) } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Theme.accent)
        }
        .buttonStyle(.plain)
        .offset(x: CGFloat(Self.spacing / 2 + 10) * (leading ? -1 : 1))
        .accessibilityLabel(label)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    // MARK: dragging

    /// Press and hold on a page, then drag: it — or every ticked page, when
    /// it is one of them — lifted and carried to a gap.
    private func liftGesture(columns: Int, proxy: ScrollViewProxy) -> some Gesture {
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
                    let id = pages[i].id
                    lift = PageLift(ids: selected.contains(id) ? selected : [id])
                    store.buzz(.tick)
                }
                follow(drag.location, columns: columns, proxy: proxy)
            }
            .onEnded { _ in putDown(moving: true) }
    }

    /// The finger at `point`: the gap under it marked, and the grid scrolled
    /// on while it is held near the top or the bottom.
    private func follow(_ point: CGPoint, columns: Int, proxy: ScrollViewProxy) {
        lift.finger = point
        lift.gap = PageOrder.gap(at: point, frames: frames.indexed(store.design.pages))
        let edge = PageOrder.edgeScroll(Double(point.y), length: Double(frames.viewport.height), margin: 60)
        edges.hold(edge) { direction in scrollOn(direction, by: columns, proxy: proxy) }
    }

    /// One row further up or down, the gap found again under the finger;
    /// false at either end.
    private func scrollOn(_ direction: Int, by columns: Int, proxy: ScrollViewProxy) -> Bool {
        let pages = store.design.pages
        let shown = frames.shown(pages, vertical: true)
        guard lift.isActive, let edge = direction > 0 ? shown.last : shown.first else { return false }
        let target = min(max(edge + direction * columns, 0), pages.count - 1)
        guard target != edge else { return false }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(pages[target].id, anchor: direction > 0 ? .bottom : .top)
        }
        if let finger = lift.finger { lift.gap = PageOrder.gap(at: finger, frames: frames.indexed(pages)) }
        return true
    }

    /// Let go: the lifted pages moved to the gap as one undo step when
    /// `moving`, else — the press taken over — put back.
    private func putDown(moving: Bool) {
        edges.stop()
        guard lift.isActive else { return }
        if moving, let gap = lift.gap { store.movePages(lift.ids, to: gap) }
        lift = PageLift()
    }

    // MARK: the bar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        // What was copied — from this design or another — after the page
        // being worked.
        ToolbarItem(placement: .topBarLeading) {
            Button(store.pastePageTitle) { store.pastePage() }
                .disabled(!store.hasPageOnClipboard)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Group {
                Button {
                    store.duplicatePages(selected)
                    selected = []
                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .disabled(selected.isEmpty)
                Spacer()
                // The ticked pages, in order, to paste into this design or
                // another; they stay ticked.
                Button {
                    store.copyPages(selected)
                } label: { Label(copyPagesLabel, systemImage: "doc.on.doc") }
                    .disabled(selected.isEmpty)
            }
            Spacer()
            Button {
                if let id = selected.first, selected.count == 1,
                   let i = store.design.pages.firstIndex(where: { $0.id == id }) {
                    store.setPage(i)
                    dismiss()
                }
            } label: { Label("Go to page", systemImage: "arrow.forward.circle") }
                .disabled(selected.count != 1)
            Spacer()
            // Show when every page picked is hidden; otherwise Hide,
            // which hides the rest of them too.
            Button {
                store.setPagesHidden(selected, hidden: !selectionHidden)
                selected = []
            } label: {
                Label(selectionHidden ? tr("Show") : tr("Hide"), systemImage: selectionHidden ? "eye" : "eye.slash")
            }
                .disabled(selected.isEmpty)
            Spacer()
            lockButton
            Spacer()
            // Locked pages are skipped, and said; never every page.
            Button(role: .destructive) {
                confirmingDelete = true
            } label: { Label("Delete", systemImage: "trash") }
                .disabled(selected.isEmpty || deletable >= store.design.pages.count)
        }
    }

    /// Unlock when every page picked is locked; otherwise Lock, which locks
    /// the rest of them too — one undo step either way.
    private var lockButton: some View {
        Button {
            store.setPagesLocked(selected, locked: !selectionLocked)
            selected = []
        } label: {
            Label(selectionLocked ? tr("Unlock") : tr("Lock"), systemImage: selectionLocked ? "lock.open" : "lock")
        }
        .disabled(selected.isEmpty)
    }

    /// How many of the pages picked Delete would take: the unlocked ones.
    private var deletable: Int {
        store.design.pages.filter { selected.contains($0.id) && !PageLocks.isLocked($0) }.count
    }

    /// Whether every page picked is locked, so the bar offers Unlock.
    private var selectionLocked: Bool {
        let picked = store.design.pages.filter { selected.contains($0.id) }
        return !picked.isEmpty && picked.allSatisfy(PageLocks.isLocked)
    }

    /// Whether every page picked is hidden, so the bar offers Show.
    private var selectionHidden: Bool {
        let picked = store.design.pages.filter { selected.contains($0.id) }
        return !picked.isEmpty && picked.allSatisfy { $0.hidden == true }
    }

    /// What VoiceOver says for a page's cell, as the Android twin's reads.
    static func spokenRow(number: Int, title: String?, current: Bool, hidden: Bool = false,
                          locked: Bool = false, elements: Int, notes: String?) -> String {
        var label = tr("Page %d", number)
        if let title = title.flatMap(PageTitles.kept) { label += ", " + title }
        if current { label += ", " + tr("current") }
        if hidden { label += ", " + tr("hidden") }
        if locked { label += ", " + PageLocks.spoken }
        label += ", " + trn("%d element|%d elements", elements)
        if let notes, !notes.isEmpty { label += ", " + notes }
        return label
    }
}
