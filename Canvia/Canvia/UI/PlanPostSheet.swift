// Share ▸ Plan a post…: a reminder at a date and time with the caption — a
// counter against X's 280 or Instagram's 2,200, by the design's type — the
// format (the export suggestion to begin with) and the pages, kept with the
// design (PostPlanner) and rung by PostReminders. Nothing is exported now:
// Share now makes the file then, edits and all. The design's other planned
// posts are listed under it, to mark done or delete. Home ▸ Planned's
// calendar opens it too (PlannedSheet). The Android twin's PlanPostSheet.

import SwiftUI

struct PlanPostSheet: View {
    @Bindable var store: DesignStore

    var body: some View {
        PlanPostForm(design: store.design, onPlan: plan, onDone: markDone, onDelete: delete)
    }

    /// The next whole hour but one: an hour from now, on the hour.
    static func startTime(now: Date = Date()) -> Date {
        let later = now.addingTimeInterval(3600)
        let hour = Calendar.current.dateInterval(of: .hour, for: later)?.start ?? later
        return hour
    }

    /// The post kept with the design, as one step, its reminder set.
    private func plan(_ post: PlannedPost) {
        let before = store.design
        store.apply { $0 = PostPlanner.saved($0, post) }
        PostReminders.reschedule(store.design, before: before)
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

/// The plan sheet itself, for `design` as it stands: what is planned goes
/// to `onPlan`, and the design's other posts are marked done or deleted
/// through `onDone` and `onDelete` — the editor's store, or Home's Planned
/// calendar saving the design itself. `startAt`, when given, is the time
/// it opens on: 9:00 on the day tapped in the calendar.
struct PlanPostForm: View {
    let design: Design
    var startAt: Date? = nil
    var onPlan: (PlannedPost) -> Void
    var onDone: (String) -> Void
    var onDelete: (String) -> Void
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
                if design.visiblePageIndices.count > 1 { pagesSection }
                plannedSection
            }
            .navigationTitle("Plan a post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Plan post") { plan() } }
            }
        }
        .onAppear {
            format = PostPlanner.defaultFormat(design)
            if let startAt { at = startAt }
        }
    }

    private var whenSection: some View {
        Section {
            DatePicker("Date", selection: $at, in: min(at, Date())..., displayedComponents: .date)
            DatePicker("Time", selection: $at, displayedComponents: .hourAndMinute)
        } footer: {
            Text("A reminder at the time, with the caption copied and the file made then — so later edits go with it.")
        }
    }

    private var captionSection: some View {
        let limit = PostPlanner.captionLimit(design)
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
            ForEach(design.visiblePageIndices, id: \.self) { i in
                Toggle(tr("Page %d", i + 1), isOn: pageBinding(design.pages[i].id))
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
        let planned = PostPlanner.of(design)
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
                if !post.done { Button("Mark done") { onDone(post.id) } }
                Button("Delete", role: .destructive) { onDelete(post.id) }
            }
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
    }

    /// Notifications asked for the first time, as the reminder is one —
    /// here, so the editor and Home's Planned calendar both ask, as the
    /// Android twin's sheet does.
    private func plan() {
        ExportNotifications.askPermission()
        onPlan(PlannedPost(id: PostPlanner.newId(), at: PostPlanner.iso(at), caption: caption, format: format,
                           pages: pages))
        dismiss()
    }
}
