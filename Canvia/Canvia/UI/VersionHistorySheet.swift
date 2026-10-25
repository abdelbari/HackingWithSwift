// Earlier versions of this design.
//
// Undo covers the last few minutes; this covers the last few weeks. A version
// is written at most every two minutes while editing and whenever the editor
// is left, and only when something actually changed — so the list is a set of
// moments, not a keystroke log. Older history is thinned rather than lost
// (VersionRetention), and a version named here is kept for good. Each row
// shows its version's first page, and opens the version page by page, to
// restore or to keep as a copy.

import SwiftUI
import UIKit

struct VersionHistorySheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [DesignLibrary.Version] = []
    /// The version open full screen.
    @State private var previewing: DesignLibrary.Version?
    /// Each version's first page, by its file's name, drawn once while the
    /// sheet is open.
    @State private var thumbnails: [String: UIImage] = [:]
    /// A version was restored from its preview, so the sheet goes with it.
    @State private var restored = false
    /// The version whose name is being typed, and the name.
    @State private var naming: DesignLibrary.Version?
    @State private var nameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if versions.isEmpty {
                    ContentUnavailableView(
                        "No earlier versions yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(tr("A version is kept every couple of minutes while you "
                                             + "edit, and each time you leave the editor.")))
                } else {
                    versionList
                }
            }
            .navigationTitle("Version history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fullScreenCover(item: $previewing, onDismiss: {
                if restored { dismiss() }
            }) { version in
                VersionPreview(store: store, version: version) { restored = true }
            }
        }
        .presentationDetents(sheetDetents)
        .task {
            versions = DesignLibrary.versions(for: store.design.id)
            await drawThumbnails()
        }
    }

    /// Under Today, Yesterday, This week and Earlier; each row opens its
    /// version, and holds Name this version… and Unpin.
    private var versionList: some View {
        List {
            ForEach(DesignLibrary.versionSections(versions)) { group in
                Section(tr(group.section.rawValue)) {
                    ForEach(group.versions) { version in
                        row(version)
                    }
                }
            }
        }
        .alert("Name this version", isPresented: Binding(
            get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Before client feedback", text: $nameText)
            Button("Save") {
                if let version = naming { pin(version, name: nameText) }
                naming = nil
            }
            Button("Cancel", role: .cancel) { naming = nil }
        } message: {
            Text("A named version is kept for good.")
        }
    }

    private func row(_ version: DesignLibrary.Version) -> some View {
        Button {
            previewing = version
        } label: {
            HStack(spacing: 12) {
                thumbnail(version)
                VStack(alignment: .leading, spacing: 2) {
                    if let name = version.pinnedName, !name.isEmpty {
                        Text(name).fontWeight(.semibold).lineLimit(1)
                    }
                    Text("\(version.savedAt, style: .relative) ago")
                    Text(summary(version))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if version.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Pinned")
                }
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .contextMenu { rowActions(version) }
        .swipeActions(edge: .trailing) { rowActions(version) }
    }

    @ViewBuilder
    private func rowActions(_ version: DesignLibrary.Version) -> some View {
        Button {
            nameText = version.pinnedName ?? ""
            naming = version
        } label: { Label("Name this version…", systemImage: "pin") }
        .tint(Theme.accent)
        if version.isPinned {
            Button {
                DesignLibrary.unpinVersion(version.stem, of: store.design.id)
                reloadVersions()
            } label: { Label("Unpin", systemImage: "pin.slash") }
        }
    }

    /// Pinned under the name typed, so pruning never takes it.
    private func pin(_ version: DesignLibrary.Version, name: String) {
        DesignLibrary.pinVersion(version.stem, of: store.design.id, name: name)
        reloadVersions()
    }

    /// The list read again for its pins; the pictures already drawn stay.
    private func reloadVersions() {
        let id = store.design.id
        Task { @MainActor in
            versions = await Task.detached(priority: .userInitiated) { DesignLibrary.versions(for: id) }.value
        }
    }

    private func thumbnail(_ version: DesignLibrary.Version) -> some View {
        Group {
            if let image = thumbnails[version.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(.systemGray5)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    /// Each row's picture in turn, newest first: the version read off the
    /// main thread, then its first page drawn with the cards' renderer —
    /// ImageRenderer works only on the main actor — one at a time, so the
    /// list scrolls while they come in.
    @MainActor
    private func drawThumbnails() async {
        for version in versions where thumbnails[version.id] == nil {
            let design = await Task.detached(priority: .userInitiated) {
                DesignLibrary.load(version: version)
            }.value
            guard !Task.isCancelled else { return }
            if let design, let image = DesignLibrary.thumbnailImage(for: design) {
                thumbnails[version.id] = image
            }
            await Task.yield()
        }
    }

    private func summary(_ v: DesignLibrary.Version) -> String {
        let pages = trn("%d page|%d pages", v.pages)
        let elements = trn("%d element|%d elements", v.elements)
        return "\(pages), \(elements)"
    }
}

/// One kept version, full screen and a page at a time, each page with a
/// badge saying whether it is the same as now, changed since or deleted
/// since (VersionDiff.pages): restored in place of the design, saved beside
/// it as a copy, or — the page shown — brought back into the design as one
/// undo step, or put in place of the page it was (Replace page).
struct VersionPreview: View {
    @Bindable var store: DesignStore
    let version: DesignLibrary.Version
    /// Called once the version is restored, so the history goes too.
    var onRestored: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The version, once read; nil too when it no longer reads.
    @State private var design: Design?
    @State private var loaded = false
    @State private var page = 0
    @State private var confirming = false
    /// "Copy saved", for a moment.
    @State private var copySaved = false
    @State private var savedTask: Task<Void, Never>?
    @State private var copyFailed = false
    /// Each page's badge (VersionDiff.pages), worked out once the version
    /// reads and again as the design changes, not on every swipe.
    @State private var states: [VersionDiff.PageState] = []

    var body: some View {
        NavigationStack {
            Group {
                if let design {
                    VStack(spacing: 12) {
                        TabView(selection: $page) {
                            ForEach(Array(design.pages.enumerated()), id: \.element.id) { index, shown in
                                pageView(design, shown, index: index)
                                    .padding()
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        Text(pageLine(design))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        pageActions(design)
                        actions
                    }
                } else if loaded {
                    ContentUnavailableView("This version can't be opened",
                                           systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.workspace)
            .overlay(alignment: .bottom) { if copySaved { savedNote } }
            .navigationTitle(RelativeTime.text(ms: version.savedAt.timeIntervalSince1970 * 1000))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Restore this version?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Restore") { restore() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current design is kept as a version too, and restoring can be undone.")
            }
            .alert("Couldn't save a copy", isPresented: $copyFailed) {
                Button("OK", role: .cancel) {}
            }
        }
        .task {
            let kept = version
            let read = await Task.detached(priority: .userInitiated) {
                DesignLibrary.load(version: kept)
            }.value
            design = read
            loaded = true
            await diff()
        }
        .task(id: store.design) { await diff() }
        .onDisappear { savedTask?.cancel() }
    }

    /// The badges worked out off the main thread: every page of both
    /// designs is written out to compare them.
    @MainActor
    private func diff() async {
        guard let kept = design else { return }
        let now = store.design
        let found = await Task.detached(priority: .userInitiated) {
            VersionDiff.pages(kept, now)
        }.value
        guard !Task.isCancelled, design == kept, store.design == now else { return }
        states = found
    }

    /// The page as large as the screen leaves room for.
    private func pageView(_ design: Design, _ shown: Page, index: Int) -> some View {
        GeometryReader { geo in
            let size = design.size(for: shown)
            let scale = min(geo.size.width / max(size.width, 1), geo.size.height / max(size.height, 1))
            PageRenderView(design: design, page: shown)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(design.pages.count)")
    }

    /// "Page 2 of 4 · Changed since".
    private func pageLine(_ design: Design) -> String {
        let place = tr("Page %d of %d", page + 1, design.pages.count)
        guard states.indices.contains(page) else { return place }
        return place + " · " + Self.badge(states[page].state)
    }

    /// What a page's badge says.
    static func badge(_ state: VersionDiff.PageChange) -> String {
        switch state {
        case .same: return tr("Same as now")
        case .changed: return tr("Changed since")
        case .onlyInVersion: return tr("Deleted since")
        }
    }

    /// Bring back this page, and — for a page the design still has —
    /// Replace page.
    private func pageActions(_ design: Design) -> some View {
        let shown = design.pages.indices.contains(page) ? design.pages[page] : nil
        let stillThere = shown.map { s in store.design.pages.contains { $0.id == s.id } } ?? false
        return HStack(spacing: 12) {
            Button { bringBack(design, shown, replace: false) } label: {
                Label("Bring back this page", systemImage: "arrow.uturn.backward.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(shown == nil)
            if stillThere {
                Button { bringBack(design, shown, replace: true) } label: {
                    Label("Replace page", systemImage: "rectangle.2.swap")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    /// The page shown into the design as it is now, one undo step; the
    /// version stays as it is, and the history goes, as after a restore.
    private func bringBack(_ design: Design, _ shown: Page?, replace: Bool) {
        guard let shown, store.bringBackPage(from: design, pageId: shown.id, replace: replace) else { return }
        onRestored()
        dismiss()
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button { saveCopy() } label: {
                Label("Make a copy", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button { confirming = true } label: {
                Label("Restore this version", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func restore() {
        guard let design else { return }
        // Keep what is on screen now as a version first, so restoring is
        // never a one-way door.
        DesignLibrary.snapshot(store.design, force: true)
        store.restore(design)
        onRestored()
        dismiss()
    }

    /// A design of its own, beside this one and in its folder; the design
    /// open in the editor is not touched.
    private func saveCopy() {
        guard let design else { return }
        guard let copy = DesignLibrary.saveCopy(of: design, savedAt: version.savedAt,
                                                folder: store.design.folder) else {
            copyFailed = true
            return
        }
        DesignLibrary.writeThumbnail(for: copy)
        AccessibilityNotification.Announcement(tr("Copy saved")).post()
        savedTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copySaved = true }
        savedTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copySaved = false }
        }
    }

    private var savedNote: some View {
        Label("Copy saved", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.bottom, 80)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

extension View {
    /// More's "Save a named version…": a name, then the design kept as a
    /// version now and pinned under it (DesignLibrary.saveNamedVersion).
    /// `onSaved` is told what to say.
    func namedVersionAlert(isPresented: Binding<Bool>, store: DesignStore,
                           onSaved: @escaping (String) -> Void) -> some View {
        modifier(NamedVersionAlert(isPresented: isPresented, store: store, onSaved: onSaved))
    }
}

private struct NamedVersionAlert: ViewModifier {
    @Binding var isPresented: Bool
    let store: DesignStore
    var onSaved: (String) -> Void
    @State private var typedName = ""

    func body(content: Content) -> some View {
        content
            .alert("Save a named version", isPresented: $isPresented) {
                TextField("Before client feedback", text: $typedName)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A named version is kept for good, under Version history.")
            }
            .onChange(of: isPresented) { _, open in
                if open { typedName = "" }
            }
    }

    private func save() {
        // Typing under way is kept first, so the version has it.
        store.finishCrop()
        store.endTextEdit()
        guard DesignLibrary.saveNamedVersion(store.design, name: typedName) != nil else {
            store.buzz(.reject)
            onSaved(tr("Couldn't save the version"))
            return
        }
        store.buzz(.confirm)
        onSaved(tr("Version saved"))
    }
}
