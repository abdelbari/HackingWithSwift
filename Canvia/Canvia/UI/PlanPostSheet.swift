// Share ▸ Plan a post…: a reminder at a date and time with the caption — a
// counter against X's 280 or Instagram's 2,200, by the design's type — the
// format (the export suggestion to begin with) and the pages, kept with the
// design (PostPlanner) and rung by PostReminders. Nothing is exported now:
// Share now makes the file then, edits and all. The design's other planned
// posts are listed under it, to mark done or delete. And Home ▸ Planned:
// every post still to come, across the designs. The Android twin's
// PlanPostSheet and PlannedSheet.

import SwiftUI

struct PlanPostSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// An hour from now, on the hour, to begin with.
    @State private var at = PlanPostSheet.startTime()
    @State private var caption = ""
    @State private var format = "png"
    /// None chosen is every shown page.
    @State private var pages: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                whenSection
                captionSection
                formatSection
                if store.design.visiblePageIndices.count > 1 { pagesSection }
                plannedSection
            }
            .navigationTitle("Plan a post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Plan post") { plan() } }
            }
        }
        .onAppear { format = PostPlanner.defaultFormat(store.design) }
    }

    /// The next whole hour but one: an hour from now, on the hour.
    static func startTime(now: Date = Date()) -> Date {
        let later = now.addingTimeInterval(3600)
        let hour = Calendar.current.dateInterval(of: .hour, for: later)?.start ?? later
        return hour
    }

    private var whenSection: some View {
        Section {
            DatePicker("Date", selection: $at, in: Date()..., displayedComponents: .date)
            DatePicker("Time", selection: $at, displayedComponents: .hourAndMinute)
        } footer: {
            Text("A reminder at the time, with the caption copied and the file made then — so later edits go with it.")
        }
    }

    private var captionSection: some View {
        let limit = PostPlanner.captionLimit(store.design)
        let over = PostPlanner.isTooLong(caption, limit: limit)
        return Section {
            TextField("Caption", text: $caption, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("Caption")
        } footer: {
            Text(PostPlanner.counter(caption, limit: limit))
                .foregroundStyle(over ? Color.red : Color.secondary)
                .monospacedDigit()
        }
    }

    private var formatSection: some View {
        Section("Format") {
            Picker("Format", selection: $format) {
                ForEach(PostPlanner.formats, id: \.self) { Text($0.uppercased()).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var pagesSection: some View {
        Section("Pages") {
            Toggle("All pages", isOn: Binding(get: { pages.isEmpty }, set: { if $0 { pages = [] } }))
            ForEach(store.design.visiblePageIndices, id: \.self) { i in
                Toggle(tr("Page %d", i + 1), isOn: pageBinding(store.design.pages[i].id))
            }
        }
    }

    private func pageBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { pages.contains(id) },
                set: { on in
                    if on { if !pages.contains(id) { pages.append(id) } } else { pages.removeAll { $0 == id } }
                })
    }

    /// This design's posts already planned, to mark done or delete.
    @ViewBuilder
    private var plannedSection: some View {
        let planned = PostPlanner.of(store.design)
        if !planned.isEmpty {
            Section("Planned") {
                ForEach(planned) { post in plannedRow(post) }
            }
        }
    }

    private func plannedRow(_ post: PlannedPost) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PlannedSheet.when(post) + (post.done ? " · " + tr("Done") : ""))
            if !post.caption.isEmpty {
                Text(post.caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                if !post.done { Button("Mark done") { markDone(post.id) } }
                Button("Delete", role: .destructive) { delete(post.id) }
            }
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
    }

    /// The post kept with the design, as one step, its reminder set — and
    /// notifications asked for the first time, as the reminder is one.
    private func plan() {
        let post = PlannedPost(id: PostPlanner.newId(), at: PostPlanner.iso(at), caption: caption, format: format,
                               pages: pages)
        let before = store.design
        store.apply { $0 = PostPlanner.saved($0, post) }
        ExportNotifications.askPermission()
        PostReminders.reschedule(store.design, before: before)
        dismiss()
    }

    /// Post `id` marked done, as one step, its reminder gone.
    private func markDone(_ id: String) {
        store.apply { $0 = PostPlanner.markedDone($0, id: id) }
        PostReminders.cancel(designId: store.design.id, postId: id)
    }

    /// Post `id` deleted, as one step, its reminder gone.
    private func delete(_ id: String) {
        store.apply { $0 = PostPlanner.removed($0, id: id) }
        PostReminders.cancel(designId: store.design.id, postId: id)
    }
}

/// Home ▸ Planned: every post planned and not yet done, across the designs,
/// soonest first (PostPlanner.upcoming) — each with its time, its design and
/// its caption, to open, mark done or delete; marking done or deleting takes
/// its reminder away. With none, how to plan one.
struct PlannedSheet: View {
    var onOpen: (Design) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var planned: [PostPlanner.Planned]?
    @State private var designs: [String: Design] = [:]
    @State private var version = 0

    var body: some View {
        NavigationStack {
            List { rows }
                .navigationTitle("Planned posts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .task(id: version) { await load() }
    }

    @ViewBuilder
    private var rows: some View {
        if let planned {
            if planned.isEmpty {
                Text("Nothing planned — plan a post from Share")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(planned) { item in row(item) }
            }
        } else {
            ProgressView()
        }
    }

    private func row(_ item: PostPlanner.Planned) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.when(item.post))
            Text(item.title + " · " + item.post.format.uppercased())
                .font(.caption)
            if !item.post.caption.isEmpty {
                Text(item.post.caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Button("Open") { open(item.designId) }
                Button("Mark done") { change(item) { PostPlanner.markedDone($0, id: $1) } }
                Button("Delete", role: .destructive) { change(item) { PostPlanner.removed($0, id: $1) } }
            }
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
    }

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
        designs = Dictionary(read.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        planned = PostPlanner.upcoming(read)
        PostReminders.rescheduleAll(read)
    }

    private func open(_ id: String) {
        guard let design = designs[id] else { return }
        dismiss()
        onOpen(design)
    }

    /// The post changed by `change` in its design and saved, its reminder
    /// taken away, and the list read again.
    private func change(_ item: PostPlanner.Planned, _ change: (Design, String) -> Design) {
        guard let design = designs[item.designId] else { return }
        _ = DesignLibrary.save(change(design, item.post.id))
        PostReminders.cancel(designId: item.designId, postId: item.post.id)
        version += 1
    }
}
