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
    /// Every design type, searchable and by category.
    case designTypes
    case settings
    /// The brand kits, with no design attached.
    case brandKit

    var id: String {
        switch self {
        case .start(let presetId): return "start-\(presetId)"
        case .pickSize: return "pick-size"
        case .customSize: return "custom-size"
        case .help: return "help"
        case .designTypes: return "design-types"
        case .settings: return "settings"
        case .brandKit: return "brand-kit"
        }
    }
}

struct HomeView: View {
    var onOpen: (Design) -> Void
    /// Photos, clips or a PDF picked under Import, landed in the inbox, for
    /// the app's "New design from shared" sheet.
    var onImport: (SharedInbox.Box) -> Void = { _ in }

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
    /// An Import row tapped in the New design sheet: its picker, once that
    /// sheet has gone.
    @State private var importAfterSheet: ImportChoice?
    /// The PowerPoint file picker, up.
    @State private var pickingDeck = false
    /// Import's photo and clip picker, and its PDF picker, up.
    @State private var pickingMedia = false
    @State private var pickingPDF = false
    /// A PowerPoint picked, with PowerPoint… or "Canvia design file…", to
    /// be read in as a new design. A list the host empties as it takes
    /// each one, so every deck is read once.
    @State private var deckURLs: [URL] = []
    /// Your own templates, first under the templates.
    @State private var userTemplates: [UserTemplate] = []
    /// The brand kit in use, whose templates lead the rest.
    @State private var brandKit = BrandKit()
    /// The "Your templates" chip: only your own templates.
    @State private var yoursOnly = false
    @State private var renamingTemplate: UserTemplate?
    @State private var templateRenameText = ""
    @State private var deletingTemplate: UserTemplate?
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
    /// A built-in template, while its preview is up.
    @State private var previewing: Template?
    /// One of your own of several pages, while its strip asks which.
    @State private var ownSet: TemplateChoice?
    @State private var folder: String?
    /// The Starred chip: starred folders, then starred designs.
    @State private var starredOnly = false
    /// The folders starred, from the home-folders preference.
    @State private var starredFolders: Set<String> = []
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
    /// The design Copy & resize is open for, from its card's menu.
    @State private var copyResizing: Design?
    /// The copies just made, while their toast offers to open them.
    @State private var madeCopies: [Design] = []
    /// Cards drawn ringed: the copies just made.
    @State private var highlighted: Set<String> = []
    /// The design whose Share… is open over Home, as saved.
    @State private var exporting: Design?
    /// The design presented from its card.
    @State private var presenting: Design?
    /// Share… or Present on a design whose file does not read, said.
    @State private var unopened = false
    /// Select's Share, asking what as.
    @State private var sharingPicked = false
    /// The last export's settings, which sharing from Home uses.
    @AppStorage(ExportLast.key) private var exportLast = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        shelf
            .onAppear {
                reload()
                if Onboarding.needsTour { touring = true }
                // Copies the editor made and was asked to show.
                let asked = HomeHighlight.take()
                if !asked.isEmpty { highlighted = Set(asked) }
            }
            .sheet(item: $copyResizing) { source in
                CopyResizeSheet(source: source) { made in showCopies(made) }
            }
            .sheet(isPresented: $touring, onDismiss: { Onboarding.markSeen() }) {
                WelcomeTour { touring = false }
            }
            .sheet(item: $homeSheet, onDismiss: afterSheet) { shown in
                sheetView(shown)
            }
            // A deck as a new design, then the sheet that says what came in.
            .background { deckPicker }
            .background { designFilePicker }
            .modifier(HomeSharing(exporting: $exporting, presenting: $presenting, unopened: $unopened))
            .importPickers(media: $pickingMedia, pdf: $pickingPDF, onLanded: onImport) { importError = $0 }
            .powerPointImport($deckURLs, onOpen: onOpen)
            .onReceive(NotificationCenter.default.publisher(for: PowerPoints.didImport)) { _ in reload() }
            .modifier(HomeDialogs(filingInto: $filingInto, newFolderName: $newFolderName, renaming: $renaming,
                                  renameText: $renameText, move: move) { reload() })
    }

    /// The shelf, the templates and what floats over them — apart from the
    /// sheets and dialogs `body` hangs on it, so each chain type-checks in
    /// good time.
    private var shelf: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                // Always there: it finds templates as well as designs, and
                // an empty shelf still has templates to search.
                searchBar
                if loaded && recents.isEmpty && damaged.isEmpty && trashed.isEmpty {
                    firstRunCard
                }
                if showsPhotoStart { photoStartCard }
                if !recents.isEmpty || !damaged.isEmpty {
                    HStack {
                        Text("Recent designs")
                            .font(.title3.weight(.bold))
                        Spacer()
                        sortMenu
                    }
                    .padding(.horizontal)
                    // All, Starred, then the folders.
                    if !recents.isEmpty { folderChips }
                    if starredOnly {
                        starredPart
                    } else if shownRecents.isEmpty {
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
                // Sizes the search names, above the templates: "tiktok"
                // finds TikTok Video, to start one.
                if !matchingTypes.isEmpty { designTypeMatches }
                templatesPart
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
            if selecting { AccessibilityNotification.Announcement(trn("%d selected|%d selected", pickedDesigns.count)).post() }
        }
        .overlay(alignment: .bottom) { trashedToast }
        .overlay(alignment: .bottom) { copiesToast }
        // An export still running — from the editor, or asked for here; a
        // tap opens its design.
        .overlay(alignment: .bottom) {
            ExportPill {
                if let id = ExportQueue.shared.current?.designId, let design = DesignLibrary.load(id: id) {
                    onOpen(design)
                }
            }
            .padding(.bottom, 12)
        }
        .overlay { if openingFile { OpeningDesignCard() } }
    }

    @ViewBuilder
    private func sheetView(_ shown: HomeSheet) -> some View {
        switch shown {
        case .start(let presetId):
            StartSheet(initialPresetId: presetId, onCreate: createFromSheet,
                       onCustomSize: { homeSheet = .customSize }, onImport: importFromSheet)
        case .pickSize:
            StartSheet(initialPresetId: nil, onCreate: createFromSheet,
                       onCustomSize: { homeSheet = .customSize }, onImport: importFromSheet)
        case .customSize:
            CustomSizeSheet(onCreate: createFromSheet)
        case .help:
            HowCanviaWorksSheet {
                replayTour = true
                homeSheet = nil
            }
        case .designTypes:
            DesignTypesSheet { preset in homeSheet = .start(presetId: preset.id) }
        case .settings:
            SettingsSheet(onTour: {
                replayTour = true
                homeSheet = nil
            })
            // A restore, or Recently deleted emptied, shows on the shelf.
            .onDisappear { reload() }
        case .brandKit:
            StandaloneBrandKitSheet()
                // Its templates lead Home's.
                .onDisappear { reload() }
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

    /// The PowerPoint file picker, on a view of its own so it does not
    /// share one with the design file's.
    private var deckPicker: some View {
        Color.clear.fileImporter(isPresented: $pickingDeck, allowedContentTypes: [PowerPoints.contentType]) { result in
            if case .success(let url) = result { deckURLs.append(url) }
        }
    }

    /// An Import row in the New design sheet: the sheet goes, then its
    /// picker comes up.
    private func importFromSheet(_ choice: ImportChoice) {
        importAfterSheet = choice
        homeSheet = nil
    }

    /// Import's row: its picker.
    private func startImport(_ choice: ImportChoice) {
        switch choice {
        case .media: pickingMedia = true
        case .pdf: pickingPDF = true
        case .powerPoint: pickingDeck = true
        case .designFile: importing = true
        }
    }

    private func afterSheet() {
        if let choice = importAfterSheet {
            importAfterSheet = nil
            startImport(choice)
        }
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
            let (shelf, binned, mine) = await Task.detached(priority: .userInitiated) {
                () -> (DesignLibrary.Shelf, [RecentDesign], [UserTemplate]) in
                (DesignLibrary.shelf(), DesignLibrary.trashed(), UserTemplates.all())
            }.value
            guard generation == reloads else { return }
            userTemplates = mine
            brandKit = BrandKit.load()
            show(shelf, trashed: binned)
        }
    }

    private func show(_ shelf: DesignLibrary.Shelf, trashed: [RecentDesign]) {
        recents = shelf.designs
        starredFolders = DesignLibrary.starredFolders()
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
    /// backup) comes back in through here: Import's "Canvia design file…".
    private var designFilePicker: some View {
        // Any file, not only JSON: a design sent from Android can arrive as
        // plain text or bare bytes, depending on the app it came through, so
        // what is inside decides.
        Color.clear.fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            guard case .success(let url) = result else { return }
            // A PowerPoint is a ZIP, which a design file never is: it comes
            // in as a deck.
            if PowerPoints.isDeck(url) {
                deckURLs.append(url)
                return
            }
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

    /// The designs to show, damaged ones among them in their place — or,
    /// under Starred, the starred ones.
    private var shownRecents: [RecentDesign] {
        if starredOnly { return starredShelf.designs }
        return DesignLibrary.filter(recents + damaged, query: query, sort: sort, folder: folder)
    }

    private var starredShelf: (folders: [String], designs: [RecentDesign]) {
        DesignLibrary.starredShelf(recents, starredFolders: starredFolders, query: query, sort: sort)
    }

    private var folders: [String] { DesignLibrary.folders(in: recents) }

    /// Whatever is on the shelf is one of the samples seeded at the first
    /// launch, or nothing is: a way to start from a photo instead.
    private var showsPhotoStart: Bool {
        loaded && damaged.isEmpty && DesignLibrary.onlySamples(recents)
    }

    /// "Start from a photo": Import's photo and clip picker.
    private var photoStartCard: some View {
        Button { pickingMedia = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start from a photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Pick photos or videos, and each becomes a page of a new design.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var shownTemplates: [Template] {
        let matching = ContentLibrary.filteredTemplates(in: templateCategory, matching: query)
        // Starred templates first.
        let starred = Set(Favorites.ids(of: "template"))
        return matching.filter { starred.contains($0.id) } + matching.filter { !starred.contains($0.id) }
    }

    /// The design types the search finds, at most eight.
    private var matchingTypes: [SizePreset] {
        Array(SizePreset.search(query).prefix(8))
    }

    /// "Design types: TikTok Video" — each a chip that opens its start.
    private var designTypeMatches: some View {
        let found = matchingTypes
        return VStack(alignment: .leading, spacing: 8) {
            Text("Design types: \(found.map(\.name).joined(separator: ", "))")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(found) { preset in
                        Button {
                            homeSheet = .start(presetId: preset.id)
                        } label: {
                            Label("\(preset.name) · \(preset.dimensions)", systemImage: preset.icon)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Theme.card, in: Capsule())
                                .overlay(Capsule().stroke(Theme.hairline))
                                .foregroundStyle(Theme.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Start a \(preset.name)")
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: chips

    /// One row of categories over the templates, so browsing is a tap
    /// rather than a scroll through everything: "Your templates" after All
    /// when you have templates of your own, as on the Android twin.
    private var templateCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(tr("All"), selected: templateCategory == nil && !yoursOnly) {
                    templateCategory = nil
                    yoursOnly = false
                }
                if !userTemplates.isEmpty {
                    chip(UserTemplates.sectionTitle, selected: yoursOnly) {
                        yoursOnly.toggle()
                        templateCategory = nil
                    }
                }
                ForEach(ContentLibrary.templateCategories, id: \.self) { category in
                    chip(category, selected: templateCategory == category) {
                        templateCategory = templateCategory == category ? nil : category
                        yoursOnly = false
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(tr("All"), selected: folder == nil && !starredOnly) {
                    folder = nil
                    starredOnly = false
                }
                chip(tr("Starred"), selected: starredOnly, systemImage: "star") {
                    starredOnly.toggle()
                    folder = nil
                }
                ForEach(folders, id: \.self) { name in
                    chip(name, selected: folder == name, systemImage: starredFolders.contains(name) ? "star.fill" : "folder") {
                        folder = folder == name ? nil : name
                        starredOnly = false
                    }
                    .accessibilityLabel(starredFolders.contains(name) ? tr("%@, starred", name) : name)
                    .contextMenu {
                        starFolderButton(name)
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
        guard let plan = DesignLibrary.renamePlan(recents, from: from, to: to) else { return }
        if plan.merges { merging = plan } else { applyRename(plan) }
    }

    private func applyRename(_ plan: DesignLibrary.FolderRename) {
        for id in plan.ids { DesignLibrary.move(id: id, toFolder: plan.name) }
        DesignLibrary.renameFolderStar(plan.from, to: plan.name)
        folder = plan.name
        reload()
    }

    /// The folder goes, its designs either out of any folder or to
    /// Recently deleted with one Undo for them all; the shelf shows
    /// everything again. Kept designs leave no folder to star; deleted
    /// with its designs, the folder keeps its star should they come back,
    /// as on the Android twin.
    private func deleteFolder(_ name: String, trashingDesigns: Bool) {
        let inFolder = recents.filter { $0.folder == name }
        folder = nil
        if trashingDesigns {
            trash(inFolder)
        } else {
            DesignLibrary.renameFolderStar(name, to: nil)
            for design in inFolder { DesignLibrary.move(id: design.id, toFolder: nil) }
            reload()
        }
    }

    /// Add to starred / Remove from starred, for a folder chip.
    private func starFolderButton(_ name: String) -> some View {
        let on = starredFolders.contains(name)
        return Button {
            DesignLibrary.setFolderStarred(name, !on)
            starredFolders = DesignLibrary.starredFolders()
        } label: {
            Label(on ? tr("Remove from starred") : tr("Add to starred"), systemImage: on ? "star.slash" : "star")
        }
    }

    /// Under Starred: the starred folders first, each opening its folder,
    /// then the starred designs in the current sort — or, with none, where
    /// stars come from.
    @ViewBuilder
    private var starredPart: some View {
        let starred = starredShelf
        if starred.folders.isEmpty && starred.designs.isEmpty {
            Text(DesignLibrary.starredEmpty)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(starred.folders, id: \.self) { name in folderCard(name) }
                ForEach(starred.designs) { recent in designCard(recent) }
            }
            .padding(.horizontal)
        }
    }

    /// A starred folder among the starred designs: its name and how many
    /// designs it holds; a tap shows them.
    private func folderCard(_ name: String) -> some View {
        let count = recents.filter { $0.folder == name }.count
        let said = trn("%d design|%d designs", count)
        return Button {
            starredOnly = false
            folder = name
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 96)
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(said).font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            .overlay(alignment: .topLeading) { starBadge }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), folder, \(said), starred")
        .contextMenu { starFolderButton(name) }
    }

    /// The small star on a starred card.
    private var starBadge: some View {
        Image(systemName: "star.fill")
            .font(.caption)
            .foregroundStyle(.yellow)
            .padding(5)
            .background(.black.opacity(0.35), in: Circle())
            .padding(6)
            .accessibilityHidden(true)
    }

    /// Stars or unstars the designs, then shows it.
    private func star(_ designs: [RecentDesign], _ on: Bool) {
        for design in designs where !design.damaged { DesignLibrary.setStarred(id: design.id, on) }
        stopSelecting()
        reload()
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
            TextField("Search designs, sizes and templates", text: $query)
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
            Text("Recently deleted (\(trashed.count))")
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
        return tr("Delete “%@” forever?", entry.title)
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

    /// "Made 3 resized copies", with Open: one copy opens, several are
    /// shown on the shelf — every folder, no search — ringed.
    @ViewBuilder
    private var copiesToast: some View {
        if !madeCopies.isEmpty {
            HStack(spacing: 12) {
                Text(CopyResize.doneText(count: madeCopies.count))
                    .font(.subheadline)
                    .lineLimit(2)
                Button("Open") {
                    let made = madeCopies
                    hideCopies()
                    if made.count == 1, let only = made.first {
                        onOpen(only)
                    } else {
                        query = ""
                        folder = nil
                        starredOnly = false
                        highlighted = Set(made.map(\.id))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                Button {
                    hideCopies()
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

    /// The copies on the shelf, ringed, and their toast up.
    private func showCopies(_ made: [Design]) {
        guard !made.isEmpty else { return }
        highlighted = Set(made.map(\.id))
        reload()
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { madeCopies = made }
        AccessibilityNotification.Announcement(CopyResize.doneText(count: made.count)).post()
    }

    private func hideCopies() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { madeCopies = [] }
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
        if designs.count == 1, let gone = designs.first { return tr("Moved “%@” to Recently deleted", gone.title) }
        return trn("Moved %d design to Recently deleted|Moved %d designs to Recently deleted", designs.count)
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
                heroButton(tr("New design"), systemImage: "plus") { homeSheet = .pickSize }
                overflowMenu
                // The brand kit, set up without opening a design.
                heroButton(tr("Brand kit"), systemImage: "paintpalette") { homeSheet = .brandKit }
                heroButton(tr("Settings"), systemImage: "gearshape") { homeSheet = .settings }
            }

            Text("What will you design today?")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // A size opens on its blank page and everything already
                    // made at that size, rather than straight into an empty
                    // page with no idea there was a head start on offer.
                    ForEach(SizePreset.hero) { preset in
                        Button {
                            homeSheet = .start(presetId: preset.id)
                        } label: {
                            heroTile(systemImage: preset.icon, title: preset.name,
                                     lines: [preset.dimensions, Templates.countText(for: preset)])
                        }
                        .accessibilityLabel("\(preset.name), \(Self.spokenSize(preset.dimensions)), "
                                            + Templates.spokenCount(for: preset))
                    }
                    // Every other design type, searchable, by category.
                    Button {
                        homeSheet = .designTypes
                    } label: {
                        heroTile(systemImage: "square.grid.2x2", title: tr("More sizes"),
                                 lines: [trn("%d design type|%d design types", SizePreset.all.count)])
                    }
                    .accessibilityLabel(tr("More sizes") + ", " + trn("%d design type|%d design types", SizePreset.all.count))
                    Button {
                        homeSheet = .customSize
                    } label: {
                        heroTile(systemImage: "slider.horizontal.3", title: tr("Custom size"), lines: [tr("Any dimensions")])
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

    /// Home's ⋯: Import, then how Canvia works.
    private var overflowMenu: some View {
        Menu {
            Section(ImportChoice.groupTitle) {
                ForEach(ImportChoice.allCases) { choice in
                    Button { startImport(choice) } label: { Label(choice.title, systemImage: choice.systemImage) }
                }
            }
            Button { homeSheet = .help } label: { Label("How Canvia works", systemImage: "questionmark.circle") }
        } label: {
            heroCircle("ellipsis")
        }
        .accessibilityLabel("More")
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
            .overlay(alignment: .topLeading) { if recent.starred { starBadge } }
            // A copy just made, ringed until the next one is opened.
            .overlay {
                if highlighted.contains(recent.id) {
                    RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recent.starred ? tr("%@, %@, starred", recent.title, caption(for: recent).spoken)
                                           : "\(recent.title), \(caption(for: recent).spoken)")
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
                Button {
                    star([recent], !recent.starred)
                } label: {
                    Label(recent.starred ? tr("Remove from starred") : tr("Add to starred"),
                          systemImage: recent.starred ? "star.slash" : "star")
                }
                Button {
                    copyResizing = DesignLibrary.load(id: recent.id)
                } label: { Label("Copy & resize", systemImage: "rectangle.on.rectangle.angled") }
                Section { shareItems(recent) }
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

    /// Share…, Send a copy, Present and Print…, on the design as saved,
    /// without opening the editor.
    @ViewBuilder
    private func shareItems(_ recent: RecentDesign) -> some View {
        Button {
            withDesign(recent.id) { exporting = $0 }
        } label: { Label("Share…", systemImage: "square.and.arrow.up") }
        Button {
            HomeExports.sendCopy(recent.id, queue: ExportQueue.shared)
        } label: { Label("Send a copy", systemImage: "paperplane") }
        Button {
            withDesign(recent.id) { presenting = $0 }
        } label: { Label("Present", systemImage: "play.rectangle") }
        if UIPrintInteractionController.isPrintingAvailable {
            Button {
                HomeExports.printDesign(recent.id, queue: ExportQueue.shared)
            } label: { Label("Print…", systemImage: "printer") }
        }
    }

    /// Design `id` read from its file off the main thread, then `use`d;
    /// "That design can't be opened" when it does not read, as the Android
    /// twin's withDesign says.
    private func withDesign(_ id: String, _ use: @escaping (Design) -> Void) {
        Task { @MainActor in
            guard let design = try? await HomeExports.load(id) else {
                unopened = true
                return
            }
            use(design)
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
            design.title = tr("%@ (copy)", design.title)
            // A copy is not starred.
            design.isStarred = false
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
        return picked.contains(recent.id) ? tr("selected") : tr("not selected")
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
            Button(all ? tr("Deselect all") : tr("Select all")) {
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
        let said = trn("%d selected|%d selected", chosen.count)
        return HStack(spacing: 18) {
            Text(said)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Menu {
                moveItems(chosen)
            } label: {
                barLabel(tr("Move to folder…"), systemImage: "folder")
            }
            .disabled(chosen.isEmpty)
            .accessibilityLabel("Move to folder…")
            Button { duplicate(chosen) } label: {
                barLabel(tr("Duplicate"), systemImage: "plus.square.on.square")
            }
            .disabled(!chosen.contains { !$0.damaged })
            .accessibilityLabel("Duplicate")
            starBarButton(chosen)
            Button { sharingPicked = true } label: {
                barLabel(tr("Share"), systemImage: "square.and.arrow.up")
            }
            .disabled(chosen.isEmpty)
            .accessibilityLabel("Share")
            Button(role: .destructive) {
                let gone = chosen
                stopSelecting()
                trash(gone)
            } label: {
                barLabel(tr("Delete"), systemImage: "trash")
            }
            .disabled(chosen.isEmpty)
            .accessibilityLabel("Delete")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .confirmationDialog(trn("Share %d design|Share %d designs", chosen.count), isPresented: $sharingPicked,
                            titleVisibility: .visible) {
            Button { share(chosen, as: .png) } label: { Text(verbatim: "PNG") }
            Button { share(chosen, as: .pdf) } label: { Text(verbatim: "PDF") }
            Button("Design files") { share(chosen, as: .designFiles) }
        }
    }

    /// The designs picked, damaged ones too — each said if it cannot be
    /// exported — one after another on the export queue; their files come
    /// to one share sheet.
    private func share(_ designs: [RecentDesign], as format: HomeExports.Format) {
        let ids = designs.map(\.id)
        guard !ids.isEmpty else { return }
        HomeExports.enqueue(ids, as: format, settings: HomeExports.settings(exportLast), queue: ExportQueue.shared)
        stopSelecting()
    }

    /// Add to starred, or Remove from starred once every design picked is.
    private func starBarButton(_ chosen: [RecentDesign]) -> some View {
        let designs = chosen.filter { !$0.damaged }
        let allStarred = !designs.isEmpty && designs.allSatisfy(\.starred)
        let title = allStarred ? tr("Remove from starred") : tr("Add to starred")
        return Button { star(designs, !allStarred) } label: {
            barLabel(title, systemImage: allStarred ? "star.slash" : "star")
        }
        .disabled(designs.isEmpty)
        .accessibilityLabel(title)
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
        let said: String = tr("Restored “%@”", design.title)
        AccessibilityNotification.Announcement(said).post()
        reload()
    }

    /// Its size, then when it was last touched and how many pages — and
    /// which folder, while every folder is showing. Heard as "1080 by 1920"
    /// rather than a multiplication.
    private func caption(for recent: RecentDesign) -> (shown: String, spoken: String) {
        // "210 × 297 mm" for a design measured in a physical unit.
        let size = recent.sizeText
        let when = RelativeTime.text(ms: recent.updatedAt)
        let pages = RelativeTime.pages(recent.pages)
        var shown = "\(size) · \(when) · \(pages)"
        var spoken = "\(Self.spokenSize(size)), \(when), \(pages)"
        if folder == nil, let name = recent.folder {
            shown += " · \(name)"
            spoken += ", " + tr("in %@", name)
        }
        return (shown, spoken)
    }

    /// "1080 × 1920" as it is said: "1080 by 1920".
    private static func spokenSize(_ size: String) -> String {
        size.replacingOccurrences(of: " × ", with: " " + tr("by") + " ")
    }

    // MARK: templates

    /// The templates: the brand kit's first, under "From <kit name>", then
    /// your own, under "Your templates", then the library's — or yours alone
    /// under the Yours chip.
    private var templatesPart: some View {
        templatesStack
            // Here rather than on a grid, so a card in the brand kit's row
            // opens it too when every one of yours is the kit's.
            .sheet(item: $ownSet) { shown in
                TemplateSetSheet(name: shown.name, design: shown.design, note: TemplateSetSheet.startNote,
                                 applyAll: { create(UserTemplates.newDesign(from: shown.design)) },
                                 usePage: { create(UserTemplates.newDesign(from: shown.design, onlyPage: $0)) })
            }
    }

    private var templatesStack: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start from a template")
                .font(.title3.weight(.bold))
                .padding(.horizontal)
            templateCategoryChips
            if templateCategory == nil {
                BrandTemplatesRow(kit: brandKit, entries: shownUserTemplates, tileWidth: 160,
                                  titleFont: .headline, inset: 16) { userTemplateCard($0) }
            }
            if templateCategory == nil && !otherUserTemplates.isEmpty {
                Text(UserTemplates.sectionTitle)
                    .font(.headline)
                    .padding(.horizontal)
                userTemplatesGrid
            }
            if yoursOnly {
                if shownUserTemplates.isEmpty {
                    Text("None of your templates matches “\(query)”.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            } else if shownTemplates.isEmpty {
                Text("No template matches “\(query)”.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                templatesGrid
            }
        }
        .modifier(UserTemplateDialogs(renaming: $renamingTemplate, renameText: $templateRenameText,
                                      deleting: $deletingTemplate) { reload() })
        // A template's own page first; a new design is empty, so every
        // page of a set makes it of them all.
        .sheet(item: $previewing, onDismiss: { favoritesVersion += 1 }) { template in
            TemplatePreviewSheet(template: template, note: TemplateSetSheet.startNote) { chosen, page in
                create(page.map { chosen.instantiate(onlyPage: $0) } ?? chosen.instantiate())
            }
        }
    }

    private var shownUserTemplates: [UserTemplate] {
        UserTemplates.matching(userTemplates, query: query)
    }

    /// Your own that are not the brand kit's: those lead in its row.
    private var otherUserTemplates: [UserTemplate] {
        brandKit.otherEntries(shownUserTemplates)
    }

    /// Your own: a tap makes a new design from a fresh copy — one of
    /// several pages shows its strip first, all of them or the page picked
    /// alone, as the Android twin's Home asks.
    private var userTemplatesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(otherUserTemplates) { entry in
                userTemplateCard(entry)
            }
        }
        .padding(.horizontal)
    }

    private func startOwn(_ entry: UserTemplate) {
        guard let template = UserTemplates.load(id: entry.id) else { return }
        if template.pages.count > 1 {
            ownSet = TemplateChoice(id: entry.id, name: entry.name, design: template)
        } else {
            create(UserTemplates.newDesign(from: template))
        }
    }

    /// One of your own templates as a card, under "Your templates" and in
    /// the brand kit's row.
    private func userTemplateCard(_ entry: UserTemplate) -> some View {
        Button {
            startOwn(entry)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                UserTemplateThumb(entry: entry)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.name), your template, \(entry.caption)")
        .contextMenu {
            Button {
                templateRenameText = entry.name
                renamingTemplate = entry
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { deletingTemplate = entry } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// "Business · 1920 × 1080 · 10 pages".
    private func templateCaption(_ template: Template) -> String {
        let line = "\(UserTemplates.shownCategory(template.category)) · \(Int(template.width)) × \(Int(template.height))"
        return template.pageCount > 1 ? line + " · " + trn("%d page|%d pages", template.pageCount) : line
    }

    private var templatesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(shownTemplates) { template in
                Button {
                    previewing = template
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        TemplateThumb(template: template)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.subheadline.weight(.semibold))
                            Text(templateCaption(template))
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
                        Label(on ? tr("Remove from favourites") : tr("Add to favourites"), systemImage: on ? "star.slash" : "star")
                    }
                }
            }
        }
        .padding(.horizontal)
        .id(favoritesVersion)
    }
}

/// Home's new-folder and rename alerts, apart from its body.
private struct HomeDialogs: ViewModifier {
    @Binding var filingInto: [String]
    @Binding var newFolderName: String
    @Binding var renaming: RecentDesign?
    @Binding var renameText: String
    var move: ([String], String?) -> Void
    var reload: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("New folder", isPresented: Binding(
                get: { !filingInto.isEmpty },
                set: { if !$0 { filingInto = [] } })) {
                TextField("Folder name", text: $newFolderName)
                Button("Move") {
                    move(filingInto, newFolderName)
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
}
