// Home ▸ Planned: every post planned, across the designs, as a month's
// Calendar or a List. The calendar starts its weeks on the locale's first
// day and runs the way the language reads; a day with posts shows up to two
// of their pages and "+N", today is ringed, and a day with a post gone by
// and not done is tinted. A tap lists that day's posts and offers Plan a
// post…, which picks a design and opens its plan sheet at 9:00 that day
// (PostPlanner.morningOf). A post's page held and dragged to another day —
// or moved with Move to date… — keeps its time (PostPlanner.movedTo): its
// design saved, its reminder set again, and Undo offered a few seconds. The
// list has the posts' pages too, in Overdue, Upcoming and Done. The JSON is
// as it was: each design's "plannedPosts". The Android twin's PlannedSheet.

import SwiftUI

struct PlannedSheet: View {
    var onOpen: (Design) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var designs: [Design]?
    @State private var version = 0
    @State private var showsCalendar = true
    @State private var month = PlannedSheet.Month.current()
    @State private var chosenDay: Int?
    /// The day a dragged post is held over.
    @State private var targetDay: Int?
    /// What a move said, and the post as it was, while Undo is offered.
    @State private var undo: MoveUndo?
    /// Plan a post…: the day, while its design is chosen; then the design
    /// and the time its sheet opens on.
    @State private var choosingFor: DayKey?
    @State private var pendingPlan: PlanTarget?
    @State private var planning: PlanTarget?
    /// Move to date…, while its date is picked.
    @State private var moving: PostPlanner.Planned?

    /// How long Undo stays after a move — the Android twin's UNDO_MILLIS.
    static let undoSeconds = 6.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Planned posts", selection: $showsCalendar) {
                        Text("Calendar").tag(true)
                        Text("List").tag(false)
                    }
                    .pickerStyle(.segmented)
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Planned posts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { undoBar }
        }
        .task(id: version) { await load() }
        .modifier(PlannedSheetDialogs(choosingFor: $choosingFor, pendingPlan: $pendingPlan, planning: $planning,
                                      moving: $moving, choices: choices, design: { byId[$0] },
                                      change: change, move: move))
    }

    @ViewBuilder
    private var content: some View {
        if let designs {
            let planned = PostPlanner.all(designs)
            if showsCalendar {
                calendarPart(planned)
            } else if planned.isEmpty {
                Text("Nothing planned — plan a post from Share")
                    .foregroundStyle(.secondary)
            } else {
                PlannedList(planned: planned, designs: byId, actions: actions)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private var byId: [String: Design] {
        Dictionary((designs ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var actions: PostActions {
        PostActions(open: { open($0) },
                    done: { item in change(item.designId) { PostPlanner.markedDone($0, id: item.post.id) } },
                    delete: { item in change(item.designId) { PostPlanner.removed($0, id: item.post.id) } },
                    moveToDate: { moving = $0 })
    }

    // MARK: the calendar

    @ViewBuilder
    private func calendarPart(_ planned: [PostPlanner.Planned]) -> some View {
        let days = PostPlanner.month(planned, year: month.year, month: month.month, zone: .current)
        MonthGrid(month: $month, days: days, designs: byId, chosen: $chosenDay, target: $targetDay) { id, day in
            dropPost(id, on: day, among: planned)
        }
        if let chosen = chosenDay, days.indices.contains(chosen - 1) {
            DayPosts(date: month.date(chosen), posts: days[chosen - 1].posts, designs: byId, actions: actions) {
                choosingFor = DayKey(year: month.year, month: month.month, day: chosen)
            }
        }
    }

    /// A post dragged onto `day`: moved there, its time kept.
    private func dropPost(_ id: String, on day: Int, among planned: [PostPlanner.Planned]) -> Bool {
        guard let item = planned.first(where: { $0.id == id }) else { return false }
        move(item, year: month.year, month: month.month, day: day)
        return true
    }

    /// `item` moved to that day, keeping its time, and Undo offered.
    private func move(_ item: PostPlanner.Planned, year: Int, month: Int, day: Int) {
        let moved = PostPlanner.movedTo(item.post, year: year, month: month, day: day, zone: .current)
        guard moved != item.post, let at = PostPlanner.date(moved.at) else { return }
        change(item.designId) { PostPlanner.saved($0, moved) }
        let said = tr("Moved to %@", at.formatted(date: .abbreviated, time: .omitted))
        undo = MoveUndo(said: said, designId: item.designId, post: item.post)
        AccessibilityNotification.Announcement(said).post()
    }

    // MARK: undo

    @ViewBuilder
    private var undoBar: some View {
        if let undo {
            HStack {
                Text(undo.said).foregroundStyle(.white)
                Spacer()
                Button("Undo") {
                    self.undo = nil
                    change(undo.designId) { PostPlanner.saved($0, undo.post) }
                }
                .foregroundStyle(.white)
                .fontWeight(.semibold)
            }
            .padding(14)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .task(id: undo.id) {
                try? await Task.sleep(for: .seconds(Self.undoSeconds))
                if self.undo?.id == undo.id { self.undo = nil }
            }
        }
    }

    // MARK: reading and saving

    /// A post's time as the phone says a date and time.
    static func when(_ post: PlannedPost) -> String {
        guard let date = PostPlanner.date(post.at) else { return post.at }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Every design read away from the main thread, and their posts listed;
    /// each post still to come has its reminder, as a restore may have left
    /// one unset.
    private func load() async {
        let read = await Task.detached(priority: .userInitiated) { () -> [Design] in
            DesignLibrary.shelf().designs.compactMap { DesignLibrary.load(id: $0.id) }
        }.value
        designs = read
        PostReminders.rescheduleAll(read)
    }

    private func open(_ id: String) {
        guard let design = byId[id] else { return }
        dismiss()
        onOpen(design)
    }

    /// Design `designId` changed by `change` and saved, its reminders set
    /// as its posts now stand, and the posts read again.
    private func change(_ designId: String, _ change: (Design) -> Design) {
        guard let before = DesignLibrary.load(id: designId) else { return }
        let after = change(before)
        guard DesignLibrary.save(after) else { return }
        PostReminders.reschedule(after, before: before)
        version += 1
    }

    /// The designs to choose from for Plan a post…, edited last first.
    private var choices: [Design] { (designs ?? []).sorted { $0.updatedAt > $1.updatedAt } }
}

extension PlannedSheet {

    /// A month of a year, as the calendar shows it.
    struct Month: Equatable {
        var year: Int
        var month: Int

        static func current(_ now: Date = Date()) -> Month {
            let parts = Calendar.current.dateComponents([.year, .month], from: now)
            return Month(year: parts.year ?? 2026, month: parts.month ?? 1)
        }

        /// The month before (-1) or after (+1).
        func adding(_ months: Int) -> Month {
            let index = year * 12 + (month - 1) + months
            return Month(year: index / 12, month: index % 12 + 1)
        }

        /// Noon on `day` of it, on this phone's clock.
        func date(_ day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        }

        /// "November 2026", as the locale writes a month.
        var title: String {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("yMMMM")
            return f.string(from: date(1))
        }
    }

    /// A day of the calendar, for Plan a post….
    struct DayKey: Identifiable, Equatable {
        var year: Int
        var month: Int
        var day: Int
        var id: String { "\(year)-\(month)-\(day)" }
    }

    /// A design and the time its plan sheet opens on.
    struct PlanTarget: Identifiable, Equatable {
        var designId: String
        var start: Date
        var id: String { designId }
    }

    /// A move, and the post as it was before it.
    struct MoveUndo: Equatable {
        var id = UUID()
        var said: String
        var designId: String
        var post: PlannedPost
    }
}

/// What can be done to a post wherever it is listed.
private struct PostActions {
    var open: (String) -> Void
    var done: (PostPlanner.Planned) -> Void
    var delete: (PostPlanner.Planned) -> Void
    var moveToDate: (PostPlanner.Planned) -> Void
}

/// Plan a post…'s design, then its sheet; and Move to date…'s date.
private struct PlannedSheetDialogs: ViewModifier {
    @Binding var choosingFor: PlannedSheet.DayKey?
    @Binding var pendingPlan: PlannedSheet.PlanTarget?
    @Binding var planning: PlannedSheet.PlanTarget?
    @Binding var moving: PostPlanner.Planned?
    let choices: [Design]
    /// A design as the plan sheet starts from it: as last read.
    var design: (String) -> Design?
    var change: (String, (Design) -> Design) -> Void
    var move: (PostPlanner.Planned, Int, Int, Int) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $choosingFor, onDismiss: planChosen) { day in
                DesignChooser(designs: choices) { picked in choose(picked, on: day) }
            }
            .sheet(item: $planning) { target in planSheet(target) }
            .sheet(item: $moving) { item in
                MoveToDateSheet(item: item) { year, month, day in move(item, year, month, day) }
            }
    }

    /// The design picked for the day: its sheet opens on 9:00 that day once
    /// the chooser has gone.
    private func choose(_ picked: Design, on day: PlannedSheet.DayKey) {
        let at = PostPlanner.morningOf(year: day.year, month: day.month, day: day.day, zone: .current)
        pendingPlan = PlannedSheet.PlanTarget(designId: picked.id, start: PostPlanner.date(at) ?? Date())
        choosingFor = nil
    }

    private func planChosen() {
        guard let next = pendingPlan else { return }
        pendingPlan = nil
        planning = next
    }

    @ViewBuilder
    private func planSheet(_ target: PlannedSheet.PlanTarget) -> some View {
        if let shown = design(target.designId) {
            let id = shown.id
            PlanPostForm(design: shown, startAt: target.start,
                         onPlan: { post in change(id) { PostPlanner.saved($0, post) } },
                         onDone: { postId in change(id) { PostPlanner.markedDone($0, id: postId) } },
                         onDelete: { postId in change(id) { PostPlanner.removed($0, id: postId) } })
        }
    }
}

/// The month: its name between back and on, the weekdays from the locale's
/// first, and a cell a day. A post's page held and dragged lands on the day
/// it is let go over (`onDrop`). Laid out the way the language reads.
private struct MonthGrid: View {
    @Binding var month: PlannedSheet.Month
    let days: [PostPlanner.Day]
    let designs: [String: Design]
    @Binding var chosen: Int?
    @Binding var target: Int?
    var onDrop: (String, Int) -> Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        let blanks = PostPlanner.leadingBlanks(year: month.year, month: month.month,
                                               firstWeekday: Calendar.current.firstWeekday)
        VStack(spacing: 6) {
            header
            weekdays
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<(blanks + days.count), id: \.self) { index in
                    if index < blanks {
                        Color.clear.frame(height: 64)
                    } else {
                        cell(days[index - blanks])
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { show(month.adding(-1)) } label: {
                Image(systemName: "chevron.backward").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(month.title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { show(month.adding(1)) } label: {
                Image(systemName: "chevron.forward").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next month")
        }
    }

    private func show(_ next: PlannedSheet.Month) {
        month = next
        chosen = nil
    }

    /// The weekdays' short names, from the locale's first.
    private var weekdays: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(first + i) % 7])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func cell(_ day: PostPlanner.Day) -> some View {
        let date = month.date(day.day)
        let isToday = Calendar.current.isDateInToday(date)
        let overdue = day.posts.contains { PostPlanner.overdue($0.post, now: Date()) }
        let said = day.posts.isEmpty ? "\(day.day)" : tr("%@, %@", "\(day.day)", trn("%d post|%d posts", day.posts.count))
        return VStack(spacing: 2) {
            Text(verbatim: "\(day.day)")
                .font(.caption2)
                .frame(width: 22, height: 22)
                .overlay { if isToday { Circle().stroke(Theme.accent, lineWidth: 2) } }
            HStack(spacing: 2) {
                ForEach(Array(day.posts.prefix(2))) { item in
                    PostThumbnail(item: item, designs: designs)
                        .frame(width: 16)
                        .draggable(item.id)
                }
            }
            if day.posts.count > 2 {
                Text(verbatim: "+\(day.posts.count - 2)").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .top)
        .background(fill(day.day, overdue: overdue), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { chosen = day.day }
        .dropDestination(for: String.self) { ids, _ in
            target = nil
            guard let id = ids.first else { return false }
            return onDrop(id, day.day)
        } isTargeted: { over in
            if over { target = day.day } else if target == day.day { target = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(said)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(chosen == day.day ? .isSelected : [])
        .accessibilityAction { chosen = day.day }
    }

    /// Held over, or chosen; a day with a post gone by and not done; else
    /// the card.
    private func fill(_ day: Int, overdue: Bool) -> Color {
        if target == day || chosen == day { return Theme.accent.opacity(0.22) }
        return overdue ? Color.red.opacity(0.16) : Theme.card
    }
}

/// A post's first page, small, as the thumbnails cache it.
private struct PostThumbnail: View {
    let item: PostPlanner.Planned
    let designs: [String: Design]

    var body: some View {
        if let design = designs[item.designId],
           let index = PostPlanner.pageIndices(design, item.post).first,
           design.pages.indices.contains(index) {
            let page = design.pages[index]
            let size = design.size(for: page)
            PageThumbnail(design: design, page: page, pixelWidth: 120)
                .aspectRatio(min(max(size.width / max(size.height, 1), 0.45), 2.2), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .accessibilityHidden(true)
        }
    }
}

/// The day tapped: its posts, and Plan a post….
private struct DayPosts: View {
    let date: Date
    let posts: [PostPlanner.Planned]
    let designs: [String: Design]
    let actions: PostActions
    var onPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(date.formatted(date: .complete, time: .omitted))
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(posts) { item in PostRow(item: item, designs: designs, actions: actions) }
            Button("Plan a post…", action: onPlan)
                .buttonStyle(.bordered)
        }
    }
}

/// Every post: Overdue, then Upcoming, then Done, each soonest first.
private struct PlannedList: View {
    let planned: [PostPlanner.Planned]
    let designs: [String: Design]
    let actions: PostActions

    var body: some View {
        let now = Date()
        let overdue = planned.filter { PostPlanner.overdue($0.post, now: now) }
        let done = planned.filter { $0.post.done }
        let upcoming = planned.filter { !$0.post.done && !PostPlanner.overdue($0.post, now: now) }
        VStack(alignment: .leading, spacing: 8) {
            part(tr("Overdue"), overdue)
            part(tr("Upcoming"), upcoming)
            part(tr("Done"), done)
        }
    }

    @ViewBuilder
    private func part(_ title: String, _ list: [PostPlanner.Planned]) -> some View {
        if !list.isEmpty {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(list) { item in PostRow(item: item, designs: designs, actions: actions) }
        }
    }
}

/// One post: its page, its time, its design and format, its caption, and
/// Open, Mark done, Move to date… and Delete — Move to date… also as
/// VoiceOver's action.
private struct PostRow: View {
    let item: PostPlanner.Planned
    let designs: [String: Design]
    let actions: PostActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(alignment: .top, spacing: 12) {
                PostThumbnail(item: item, designs: designs).frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(PlannedSheet.when(item.post))
                    Text(item.title + " · " + item.post.format.uppercased())
                        .font(.caption)
                    if !item.post.caption.isEmpty {
                        Text(item.post.caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: Text("Move to date…")) { actions.moveToDate(item) }
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            Button("Open") { actions.open(item.designId) }
            if !item.post.done { Button("Mark done") { actions.done(item) } }
            Button("Move to date…") { actions.moveToDate(item) }
            Button("Delete", role: .destructive) { actions.delete(item) }
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
    }
}

/// Plan a post…'s first question: which design.
private struct DesignChooser: View {
    let designs: [Design]
    var onPick: (Design) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(designs, id: \.id) { design in
                Button(design.title) { onPick(design) }
                    .foregroundStyle(Theme.ink)
            }
            .navigationTitle("Choose a design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Move to date…: the day picked, the time kept.
private struct MoveToDateSheet: View {
    let item: PostPlanner.Planned
    var onMove: (Int, Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()

    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .navigationTitle("Move to date…")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Move") { move() } }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear { day = PostPlanner.date(item.post.at) ?? Date() }
    }

    private func move() {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        if let year = parts.year, let month = parts.month, let date = parts.day { onMove(year, month, date) }
        dismiss()
    }
}
