// Home screen: gradient hero with size presets + custom size, recent
// designs, and the template gallery.

import SwiftUI

/// The sheets Home opens, one at a time: a size's starts, the sizes
/// themselves, or a size of one's own.
enum HomeSheet: Identifiable, Equatable {
    case start(presetId: String)
    case pickSize
    case customSize
    case help

    var id: String {
        switch self {
        case .start(let presetId): return "start-\(presetId)"
        case .pickSize: return "pick-size"
        case .customSize: return "custom-size"
        case .help: return "help"
        }
    }
}

struct HomeView: View {
    var onOpen: (Design) -> Void

    @State private var recents: [RecentDesign] = []
    /// Design files that no longer read, each shown as a card of its own.
    @State private var damaged: [RecentDesign] = []
    /// The damaged design whose deletion is being asked about.
    @State private var deletingDamaged: RecentDesign?
    /// No version of a damaged design could be read.
    @State private var restoreFailed = false
    /// Whether the shelf has been read yet, so the first-run card does not
    /// flash up over a shelf that is still being read.
    @State private var loaded = false
    /// Counts the shelf's reads, so only the latest one is shown.
    @State private var reloads = 0
    @State private var homeSheet: HomeSheet?
    /// A design made in a sheet, opened once the sheet has gone rather than
    /// from under it.
    @State private var pendingOpen: Design?
    /// Asked for from the help sheet: the tour, once that sheet has gone.
    @State private var replayTour = false
    /// The Vibration switch, shared with the editor.
    @AppStorage(Haptics.key) private var haptics = true
    @State private var renaming: RecentDesign?
    @State private var renameText = ""
    @State private var query = ""
    @State private var sort = DesignLibrary.Sort.recent
    @State private var trashed: [RecentDesign] = []
    @State private var showingTrash = false
    /// The design in Recently deleted whose deletion for good is being
    /// asked about.
    @State private var deletingForever: RecentDesign?
    /// Emptying Recently deleted is being asked about.
    @State private var emptyingTrash = false
    @State private var importing = false
    @State private var favoritesVersion = 0
    @State private var importError: String?
    /// A design file being read in, while the "Opening the design…" card
    /// is up.
    @State private var openingFile = false
    @State private var templateCategory: String?
    @State private var folder: String?
    /// The designs a new folder is being named for.
    @State private var filingInto: [String] = []
    @State private var newFolderName = ""
    /// The folder whose new name is being typed.
    @State private var renamingFolder: String?
    @State private var folderRenameText = ""
    /// A rename onto a folder already there, while the merge is asked about.
    @State private var merging: DesignLibrary.FolderRename?
    /// The folder whose deletion is being asked about.
    @State private var deletingFolder: String?
    /// Select on Home: tapping a card picks it rather than opening it.
    @State private var selecting = false
    /// The ids picked in Select.
    @State private var picked: Set<String> = []
    @State private var touring = false
    /// The designs just moved to Recently deleted, all at once, while their
    /// one Undo is on offer.
    @State private var justTrashed: [RecentDesign] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                // Always there: it finds templates as well as designs, and
                // an empty shelf still has templates to search.
                searchBar
                if loaded && recents.isEmpty && damaged.isEmpty && trashed.isEmpty {
                    firstRunCard
                }
                importRow
                if !recents.isEmpty || !damaged.isEmpty {
                    HStack {
                        Text("Recent designs")
                            .font(.title3.weight(.bold))
                        Spacer()
                        sortMenu
                    }
                    .padding(.horizontal)
                    if !folders.isEmpty { folderChips }
                    if shownRecents.isEmpty {
                        Text("No design matches “\(query)”.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        recentsGrid
                    }
                }
                if !trashed.isEmpty {
                    trashSection
                }
                Text("Start from a template")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal)
                templateCategoryChips
                if shownTemplates.isEmpty {
                    Text("No template matches “\(query)”.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    templatesGrid
                }
            }
            .padding(.bottom, 40)
        }
        // Was a hardcoded near-white, which in dark mode left primary-coloured
        // text — white by then — on an almost white page.
        .background(Theme.workspace)
        .safeAreaInset(edge: .top, spacing: 0) { if selecting { selectTopBar } }
        .safeAreaInset(edge: .bottom, spacing: 0) { if selecting { selectBar } }
        // The bar's count, heard as each pick changes it.
        .onChange(of: picked) {
            if selecting { AccessibilityNotification.Announcement("\(pickedDesigns.count) selected").post() }
        }
        .overlay(alignment: .bottom) { trashedToast }
        .overlay { if openingFile { OpeningDesignCard() } }
        .onAppear {
            reload()
            if Onboarding.needsTour { touring = true }
        }
        .sheet(isPresented: $touring, onDismiss: { Onboarding.markSeen() }) {
            WelcomeTour { touring = false }
        }
        .sheet(item: $homeSheet, onDismiss: afterSheet) { shown in
            sheetView(shown)
        }
        .alert("New folder", isPresented: Binding(
            get: { !filingInto.isEmpty },
            set: { if !$0 { filingInto = [] } })) {
            TextField("Folder name", text: $newFolderName)
            Button("Move") {
                move(filingInto, to: newFolderName)
                filingInto = []
            }
            .disabled((DesignLibrary.folderName(newFolderName)?.utf16.count ?? 0) > DesignLibrary.folderNameLimit)
            Button("Cancel", role: .cancel) { filingInto = [] }
        }
        .alert("Rename design", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                // A name emptied out keeps the old one, as on the Android
                // twin: a card with no title, and exports named "design",
                // are not what clearing the field meant.
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, let target = renaming, var design = DesignLibrary.load(id: target.id) {
                    design.title = name
                    design.titleAuto = false
                    design.updatedAt = Date().timeIntervalSince1970 * 1000
                    DesignLibrary.save(design)
                    reload()
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    @ViewBuilder
    private func sheetView(_ shown: HomeSheet) -> some View {
        switch shown {
        case .start(let presetId):
            StartSheet(initialPresetId: presetId, onCreate: createFromSheet,
                       onCustomSize: { homeSheet = .customSize })
        case .pickSize:
            StartSheet(initialPresetId: nil, onCreate: createFromSheet,
                       onCustomSize: { homeSheet = .customSize })
        case .customSize:
            CustomSizeSheet(onCreate: createFromSheet)
        case .help:
            HowCanviaWorksSheet {
                replayTour = true
                homeSheet = nil
            }
        }
    }

    /// A new design, under a name the shelf does not already have — "Poster",
    /// then "Poster 2" — so no two cards read the same.
    private func create(_ design: Design) {
        var named = design
        named.title = Titles.unique(design.title, taken: recents.map(\.title))
        onOpen(named)
    }

    private func createFromSheet(_ design: Design) {
        pendingOpen = design
        homeSheet = nil
    }

    private func afterSheet() {
        if replayTour {
            replayTour = false
            Onboarding.reset(.standard)
            touring = true
        }
        guard let design = pendingOpen else { return }
        pendingOpen = nil
        create(design)
    }

    /// The shelf and the trash, read off the main thread — every design
    /// used to be decoded on it, and every card's picture built, each time
    /// Home appeared — and shown when they land. Only the latest read is
    /// shown, so one begun before a rename cannot land after it.
    private func reload() {
        reloads += 1
        let generation = reloads
        Task { @MainActor in
            let (shelf, binned) = await Task.detached(priority: .userInitiated) { () -> (DesignLibrary.Shelf, [RecentDesign]) in
                (DesignLibrary.shelf(), DesignLibrary.trashed())
            }.value
            guard generation == reloads else { return }
            show(shelf, trashed: binned)
        }
    }

    private func show(_ shelf: DesignLibrary.Shelf, trashed: [RecentDesign]) {
        recents = shelf.designs
        damaged = shelf.damaged
        self.trashed = trashed
        loaded = true
        // The icon's quick actions follow the shelf, so a deleted design
        // drops out of them.
        QuickActions.publish(recents: recents)
        // A folder exists while something is in it: when its last design
        // goes, the shelf shows everything again rather than nothing.
        if let f = folder, !DesignLibrary.folders(in: recents).contains(f) { folder = nil }
        // A design that reached the shelf without being opened here — a
        // file from the Android twin, a sample whose picture was not
        // written — gets its picture now rather than showing a grey box,
        // and the shelf is read again for its card to find it. Each design
        // is tried once a launch, so this does not go round again.
        if DesignLibrary.fillMissingThumbnails(recents) { reload() }
    }

    /// A design file made by Export on another device (or this one, as a
    /// backup) comes back in through here.
    private var importRow: some View {
        HStack {
            Button {
                importing = true
            } label: {
                Label("Open a Canvia design file", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
            }
            Spacer()
        }
        .padding(.horizontal)
        // Any file, not only JSON: a design sent from Android can arrive as
        // plain text or bare bytes, depending on the app it came through, so
        // what is inside decides.
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            guard case .success(let url) = result else { return }
            // Read, and its photos and clips written out, away from the
            // main thread: a clip-heavy file runs to a hundred megabytes and
            // more, and Home froze with no sign of why while it went in.
            let taken = recents.map(\.title)
            openingFile = true
            Task { @MainActor in
                defer { openingFile = false }
                do {
                    onOpen(try await DesignPackage.importFileInBackground(at: url, taken: taken))
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
        .alert("Couldn't open that file", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    /// The designs to show, damaged ones among them in their place.
    private var shownRecents: [RecentDesign] {
        DesignLibrary.filter(recents + damaged, query: query, sort: sort, folder: folder)
    }

    private var folders: [String] { DesignLibrary.folders(in: recents) }

    private var shownTemplates: [Template] {
        let matching = ContentLibrary.filteredTemplates(in: templateCategory, matching: query)
        // Starred templates first.
        let starred = Set(Favorites.ids(of: "template"))
        return matching.filter { starred.contains($0.id) } + matching.filter { !starred.contains($0.id) }
    }

    // MARK: chips

    /// One row of categories over the templates, so browsing is a tap
    /// rather than a scroll through everything.
    private var templateCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: templateCategory == nil) { templateCategory = nil }
                ForEach(ContentLibrary.templateCategories, id: \.self) { category in
                    chip(category, selected: templateCategory == category) {
                        templateCategory = templateCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: folder == nil) { folder = nil }
                ForEach(folders, id: \.self) { name in
                    chip(name, selected: folder == name, systemImage: "folder") {
                        folder = folder == name ? nil : name
                    }
                    .contextMenu {
                        Button {
                            folderRenameText = name
                            renamingFolder = name
                        } label: { Label("Rename folder…", systemImage: "pencil") }
                        Button(role: .destructive) {
                            deletingFolder = name
                        } label: { Label("Delete folder…", systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal)
        }
        .alert("Rename folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } })) {
            TextField("Folder name", text: $folderRenameText)
            Button("Rename") {
                if let from = renamingFolder { renameFolder(from, to: folderRenameText) }
                renamingFolder = nil
            }
            // Blank, or past forty characters, is no name for a folder.
            .disabled(DesignLibrary.renamePlan(recents, from: renamingFolder ?? "", to: folderRenameText) == nil)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
        .alert("Merge into ‘\(merging?.name ?? "")’?", isPresented: Binding(
            get: { merging != nil },
            set: { if !$0 { merging = nil } })) {
            Button("Merge") {
                if let plan = merging { applyRename(plan) }
                merging = nil
            }
            Button("Cancel", role: .cancel) { merging = nil }
        }
        .confirmationDialog("Delete ‘\(deletingFolder ?? "")’?", isPresented: Binding(
            get: { deletingFolder != nil },
            set: { if !$0 { deletingFolder = nil } }),
                            titleVisibility: .visible) {
            Button("Keep the designs") {
                if let name = deletingFolder { deleteFolder(name, trashingDesigns: false) }
                deletingFolder = nil
            }
            Button("Delete the designs too", role: .destructive) {
                if let name = deletingFolder { deleteFolder(name, trashingDesigns: true) }
                deletingFolder = nil
            }
            Button("Cancel", role: .cancel) { deletingFolder = nil }
        }
    }

    /// Every design in the folder filed under the new name, and the folder
    /// still the one shown — or, onto a folder already there, asked first.
    private func renameFolder(_ from: String, to: String) {
        guard let plan = DesignLibrary.renamePlan(recents, from: from, to: to), plan.name != from else { return }
        if plan.merges { merging = plan } else { applyRename(plan) }
    }

    private func applyRename(_ plan: DesignLibrary.FolderRename) {
        for id in plan.ids { DesignLibrary.move(id: id, toFolder: plan.name) }
        folder = plan.name
        reload()
    }

    /// The folder goes, its designs either out of any folder or to
    /// Recently deleted with one Undo for them all; the shelf shows
    /// everything again.
    private func deleteFolder(_ name: String, trashingDesigns: Bool) {
        let inFolder = recents.filter { $0.folder == name }
        folder = nil
        if trashingDesigns {
            trash(inFolder)
        } else {
            for design in inFolder { DesignLibrary.move(id: design.id, toFolder: nil) }
            reload()
        }
    }

    private func chip(_ title: String, selected: Bool, systemImage: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.caption) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Theme.accent : Theme.card, in: Capsule())
            .foregroundStyle(selected ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What the home screen says before there is anything on it. A blank
    /// space under the hero reads as a broken list; this says where things
    /// will go and what to do first.
    private var firstRunCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your designs will show up here")
                    .font(.subheadline.weight(.semibold))
                Text("Pick a size above or a template below to start. Everything saves itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // A way in from the card itself, as the Android twin's empty
                // shelf has: the starts for the most-made size.
                Button("Show me") { homeSheet = .start(presetId: "insta-post") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: search and sort

    /// One field for both lists. Twenty designs is where scrolling stops
    /// finding things; a search box is what finds them after that.
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search designs and templates", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(DesignLibrary.Sort.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Label(sort.label, systemImage: "arrow.up.arrow.down")
                .font(.subheadline)
        }
    }

    // MARK: trash

    /// Collapsed by default: what was deleted is not what the home screen is
    /// for, but it has to be findable for the thirty days it is kept.
    private var trashSection: some View {
        DisclosureGroup(isExpanded: $showingTrash) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(trashed) { entry in
                    HStack(spacing: 12) {
                        ShelfThumbnail(id: entry.id, stamp: entry.thumbnailStamp, trashed: true)
                            .frame(width: 56, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("Deleted \(RelativeTime.lowercasedFirst(RelativeTime.text(ms: entry.updatedAt)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            DesignLibrary.restore(id: entry.id)
                            reload()
                        }
                        .buttonStyle(.bordered)
                        Button(role: .destructive) {
                            deletingForever = entry
                        } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete forever")
                    }
                }
                Text("Designs in the trash are removed after 30 days.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Empty Recently deleted", role: .destructive) { emptyingTrash = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
            .padding(.top, 8)
        } label: {
            Text(trashed.count == 1 ? "Recently deleted (1)" : "Recently deleted (\(trashed.count))")
                .font(.title3.weight(.bold))
        }
        .padding(.horizontal)
        // Asked first, both: there is no coming back from either, and the
        // one design's bin sat a finger's width from its Restore.
        .confirmationDialog(deleteForeverQuestion,
                            isPresented: Binding(get: { deletingForever != nil },
                                                 set: { if !$0 { deletingForever = nil } }),
                            titleVisibility: .visible) {
            Button("Delete forever", role: .destructive) {
                if let entry = deletingForever {
                    DesignLibrary.deleteTrashed(id: entry.id)
                    // Gone for good is past undoing; the rest still come
                    // back with Undo.
                    if justTrashed.contains(where: { $0.id == entry.id }) {
                        justTrashed.removeAll { $0.id == entry.id }
                        if justTrashed.isEmpty { hideTrashed() }
                    }
                }
                deletingForever = nil
                reload()
            }
            Button("Cancel", role: .cancel) { deletingForever = nil }
        } message: {
            Text(DesignLibrary.cannotBeUndone)
        }
        .confirmationDialog(DesignLibrary.emptyTrashQuestion(count: trashed.count),
                            isPresented: $emptyingTrash, titleVisibility: .visible) {
            Button("Delete forever", role: .destructive) {
                DesignLibrary.emptyTrash()
                hideTrashed()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DesignLibrary.cannotBeUndone)
        }
    }

    /// What deleting one design for good asks first.
    private var deleteForeverQuestion: String {
        guard let entry = deletingForever else { return "" }
        return "Delete “\(entry.title)” forever?"
    }

    // MARK: undo a delete

    /// Stays until Undo, its close button, or the next delete replaces it,
    /// as the Android twin's snackbar with an action does: a toast that
    /// times out is gone before a screen reader has finished saying it.
    @ViewBuilder
    private var trashedToast: some View {
        if !justTrashed.isEmpty {
            HStack(spacing: 12) {
                Text(Self.trashedText(justTrashed))
                    .font(.subheadline)
                    .lineLimit(2)
                Button("Undo") {
                    for gone in justTrashed { DesignLibrary.restore(id: gone.id) }
                    hideTrashed()
                    reload()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                Button {
                    hideTrashed()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.horizontal)
            .padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showTrashed(_ designs: [RecentDesign]) {
        guard !designs.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { justTrashed = designs }
        AccessibilityNotification.Announcement(Self.trashedText(designs)).post()
    }

    private func hideTrashed() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { justTrashed = [] }
    }

    /// What the toast says: the design by name, or how many went at once.
    private static func trashedText(_ designs: [RecentDesign]) -> String {
        if designs.count == 1, let gone = designs.first { return "Moved “\(gone.title)” to Recently deleted" }
        return "Moved \(designs.count) designs to Recently deleted"
    }

    /// To the trash, not gone: thirty days to change your mind, in the
    /// section below — and one Undo right here for the change of mind that
    /// comes at once, however many went.
    private func trash(_ designs: [RecentDesign]) {
        guard !designs.isEmpty else { return }
        for design in designs { DesignLibrary.trash(id: design.id) }
        reload()
        showTrashed(designs)
    }

    // MARK: hero

    private var hero: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Text("Canvia")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !selecting && (!recents.isEmpty || !damaged.isEmpty) {
                    Button { startSelecting() } label: {
                        Text("Select")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                }
                heroButton("New design", systemImage: "plus") { homeSheet = .pickSize }
                heroButton("How Canvia works", systemImage: "questionmark") { homeSheet = .help }
                Menu {
                    Toggle(isOn: $haptics) { Label("Vibration", systemImage: "iphone.radiowaves.left.and.right") }
                } label: {
                    heroCircle("ellipsis")
                }
                .accessibilityLabel("More")
            }

            Text("What will you design today?")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // A size opens on its blank page and everything already
                    // made at that size, rather than straight into an empty
                    // page with no idea there was a head start on offer.
                    ForEach(SizePreset.all) { preset in
                        let count = ContentLibrary.templateCounts[preset.id] ?? 0
                        Button {
                            homeSheet = .start(presetId: preset.id)
                        } label: {
                            heroTile(systemImage: preset.icon, title: preset.name,
                                     lines: ["\(Int(preset.w)) × \(Int(preset.h))", "\(count) ready-made"])
                        }
                        .accessibilityLabel("\(preset.name), \(Int(preset.w)) by \(Int(preset.h)), \(count) ready-made designs")
                    }
                    Button {
                        homeSheet = .customSize
                    } label: {
                        heroTile(systemImage: "slider.horizontal.3", title: "Custom size", lines: ["Any dimensions"])
                    }
                    .accessibilityLabel("Custom size")
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.heroGradient)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26))
    }

    private func heroTile(systemImage: String, title: String, lines: [String]) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.caption.weight(.bold))
                .multilineTextAlignment(.center)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        // Relative styles above, so the tile has to grow with them: a fixed
        // 104pt box clipped the size label off at the larger accessibility
        // sizes.
        .frame(width: 108)
        .frame(minHeight: 112)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.16))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.25))))
    }

    /// A round white-on-purple button in the hero's top row.
    private func heroButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { heroCircle(systemImage) }
            .accessibilityLabel(label)
    }

    private func heroCircle(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.18), in: Circle())
    }

    // MARK: recents

    private var recentsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(shownRecents) { recent in
                if recent.damaged {
                    if selecting { pickableDamagedCard(recent) } else { damagedCard(recent) }
                } else {
                    designCard(recent)
                }
            }
        }
        .padding(.horizontal)
        .confirmationDialog("Delete this damaged design?", isPresented: Binding(
            get: { deletingDamaged != nil }, set: { if !$0 { deletingDamaged = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // To the trash with its versions, as any design goes, so a
                // version can still mend it if it is restored.
                if let entry = deletingDamaged { trash([entry]) }
                deletingDamaged = nil
            }
            Button("Cancel", role: .cancel) { deletingDamaged = nil }
        } message: {
            Text("It goes to Recently deleted, where it is kept for 30 days.")
        }
        .alert("No version to restore", isPresented: $restoreFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No earlier version of this design can be opened.")
        }
    }

    private func designCard(_ recent: RecentDesign) -> some View {
        Button {
            if selecting {
                toggle(recent)
            } else if let design = DesignLibrary.load(id: recent.id) {
                onOpen(design)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ShelfThumbnail(id: recent.id, stamp: recent.thumbnailStamp)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(caption(for: recent).shown)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(10)
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            .overlay(alignment: .topTrailing) { if selecting { checkCircle(picked.contains(recent.id)) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(recent.title), \(caption(for: recent).spoken)")
        .accessibilityValue(pickedValue(recent))
        .contextMenu {
            if !selecting {
                Button {
                    renameText = recent.title
                    renaming = recent
                } label: { Label("Rename", systemImage: "pencil") }
                Button {
                    duplicate([recent])
                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Menu {
                    moveItems([recent])
                } label: { Label("Move to folder", systemImage: "folder") }
                if supportsMultipleWindows {
                    Button {
                        openWindow(value: recent.id)
                    } label: { Label("Open in new window", systemImage: "macwindow.badge.plus") }
                }
                Button(role: .destructive) {
                    trash([recent])
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    /// Where `designs` can be filed: each folder — but the one they are
    /// all in already — a new one, or out of their folders.
    @ViewBuilder
    private func moveItems(_ designs: [RecentDesign]) -> some View {
        let ids = designs.map(\.id)
        let current = Set(designs.map(\.folder))
        ForEach(folders.filter { !(current.count == 1 && current.contains($0)) }, id: \.self) { name in
            Button(name) { move(ids, to: name) }
        }
        Button {
            newFolderName = ""
            filingInto = ids
        } label: { Label("New folder…", systemImage: "folder.badge.plus") }
        if designs.contains(where: { $0.folder != nil }) {
            Button(role: .destructive) {
                move(ids, to: nil)
            } label: { Label("Remove from folder", systemImage: "folder.badge.minus") }
        }
    }

    /// Files the designs under `folder`, or out of any for nil or blank;
    /// a design that no longer reads stays where it is.
    private func move(_ ids: [String], to folder: String?) {
        for id in ids { DesignLibrary.move(id: id, toFolder: folder) }
        stopSelecting()
        reload()
    }

    /// Each design copied whole under a fresh id, its picture with it.
    /// One that no longer reads has nothing to copy.
    private func duplicate(_ designs: [RecentDesign]) {
        for recent in designs where !recent.damaged {
            guard var design = DesignLibrary.load(id: recent.id) else { continue }
            let sourceId = design.id
            design.id = UID.make("doc")
            design.title += " (copy)"
            design.updatedAt = Date().timeIntervalSince1970 * 1000
            DesignLibrary.save(design)
            DesignLibrary.copyThumbnail(from: sourceId, to: design.id)
        }
        stopSelecting()
        reload()
    }

    // MARK: select

    private func startSelecting() {
        picked = []
        hideTrashed()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { selecting = true }
    }

    private func stopSelecting() {
        guard selecting else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { selecting = false }
        picked = []
    }

    private func toggle(_ recent: RecentDesign) {
        if picked.contains(recent.id) { picked.remove(recent.id) } else { picked.insert(recent.id) }
    }

    /// Every design picked that is still on the shelf, which the bar acts
    /// on: one picked and then filtered out of sight goes with the rest.
    private var pickedDesigns: [RecentDesign] {
        DesignLibrary.picked(picked, among: DesignLibrary.filter(recents + damaged, query: "", sort: sort, folder: nil))
    }

    /// Heard on each card in Select; nothing outside it.
    private func pickedValue(_ recent: RecentDesign) -> String {
        guard selecting else { return "" }
        return picked.contains(recent.id) ? "selected" : "not selected"
    }

    /// A damaged card in Select, picked by a tap anywhere on it, as a
    /// design's is: for Move and Delete, though Duplicate passes it by.
    private func pickableDamagedCard(_ entry: RecentDesign) -> some View {
        Button { toggle(entry) } label: {
            damagedCard(entry)
                .overlay(alignment: .topTrailing) { checkCircle(picked.contains(entry.id)) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.title), This design can't be opened.")
        .accessibilityValue(pickedValue(entry))
        .accessibilityAddTraits(.isButton)
    }

    /// Filled when the card is picked.
    private func checkCircle(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Theme.accent)
            .shadow(color: .black.opacity(0.25), radius: 2)
            .padding(8)
            .accessibilityHidden(true)
    }

    /// Over the shelf while selecting: all or none of the designs on show,
    /// and the way out.
    private var selectTopBar: some View {
        let all = DesignLibrary.allPicked(picked, among: shownRecents)
        return HStack {
            Button(all ? "Deselect all" : "Select all") {
                picked = DesignLibrary.togglingAll(picked, among: shownRecents)
            }
            .disabled(shownRecents.isEmpty)
            Spacer()
            Button("Done") { stopSelecting() }
                .fontWeight(.semibold)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .transition(.opacity)
    }

    /// Under the shelf while selecting: how many are picked, and what can
    /// be done with them all at once.
    private var selectBar: some View {
        let chosen = pickedDesigns
        let said = "\(chosen.count) selected"
        return HStack(spacing: 18) {
            Text(said)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Menu {
                moveItems(chosen)
            } label: {
                barLabel("Move to folder…", systemImage: "folder")
            }
            .disabled(chosen.isEmpty)
            .accessibilityLabel("Move to folder…")
            Button { duplicate(chosen) } label: {
                barLabel("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(!chosen.contains { !$0.damaged })
            .accessibilityLabel("Duplicate")
            Button(role: .destructive) {
                let gone = chosen
                stopSelecting()
                trash(gone)
            } label: {
                barLabel("Delete", systemImage: "trash")
            }
            .disabled(chosen.isEmpty)
            .accessibilityLabel("Delete")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func barLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage).font(.body)
            Text(title).font(.caption2)
        }
    }

    /// A design file that no longer reads, among the designs rather than
    /// left out of them without a word, as it used to be: brought back from
    /// its newest version that still reads, or deleted.
    private func damagedCard(_ entry: RecentDesign) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color(.systemGray5)
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 120)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("This design can't be opened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // In Select the whole card picks it instead.
                if !selecting {
                    Button("Restore last version") { restoreDamaged(entry) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Button("Delete", role: .destructive) { deletingDamaged = entry }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        .accessibilityElement(children: .contain)
    }

    /// The newest version that reads comes back under the same id, and the
    /// card is the design again, with a fresh picture.
    private func restoreDamaged(_ entry: RecentDesign) {
        guard let design = DesignLibrary.restoreLastVersion(of: entry.id) else {
            restoreFailed = true
            return
        }
        DesignLibrary.writeThumbnail(for: design)
        let said: String = "Restored “\(design.title)”"
        AccessibilityNotification.Announcement(said).post()
        reload()
    }

    /// Its size, then when it was last touched and how many pages — and
    /// which folder, while every folder is showing. Heard as "1080 by 1920"
    /// rather than a multiplication.
    private func caption(for recent: RecentDesign) -> (shown: String, spoken: String) {
        let w = Int(recent.width), h = Int(recent.height)
        let when = RelativeTime.text(ms: recent.updatedAt)
        let pages = RelativeTime.pages(recent.pages)
        var shown = "\(w) × \(h) · \(when) · \(pages)"
        var spoken = "\(w) by \(h), \(when), \(pages)"
        if folder == nil, let name = recent.folder {
            shown += " · \(name)"
            spoken += ", in \(name)"
        }
        return (shown, spoken)
    }

    // MARK: templates

    private var templatesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(shownTemplates) { template in
                Button {
                    create(template.instantiate())
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        TemplateThumb(template: template)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.subheadline.weight(.semibold))
                            Text("\(template.category) · \(Int(template.width)) × \(Int(template.height))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                    .overlay(alignment: .topTrailing) {
                        if Favorites.isFavorite("template", template.id) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .padding(6)
                                .accessibilityLabel("Favourite")
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    let on = Favorites.isFavorite("template", template.id)
                    Button {
                        Favorites.toggle("template", template.id)
                        favoritesVersion += 1
                    } label: {
                        Label(on ? "Remove from favourites" : "Add to favourites", systemImage: on ? "star.slash" : "star")
                    }
                }
            }
        }
        .padding(.horizontal)
        .id(favoritesVersion)
    }
}
