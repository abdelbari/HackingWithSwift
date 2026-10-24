// Canvia — a Canva-inspired design studio for iOS.
// Entry point + home ⇄ editor routing.

import CoreSpotlight
import SwiftUI

@main
struct CanviaApp: App {
    /// Hands the window scene a delegate that hears Home Screen quick
    /// actions.
    @UIApplicationDelegateAdaptor(CanviaAppDelegate.self) private var appDelegate
    @State private var editingStore: DesignStore?
    /// Why a design file handed to the app could not be opened.
    @State private var openError: String?
    /// A design file handed over, while it is being read in.
    @State private var openingFile = false
    /// A workbook opened in Canvia with several sheets with rows, and the
    /// title its design takes, while the sheet to chart is chosen.
    @State private var sheetsIn: SheetsIn?
    /// A quick action or Siri asked for a design that has since gone.
    @State private var designMissing = false
    /// Photos, videos, PDFs or SVGs opened in Canvia, landed in the inbox,
    /// while the "New design from shared" sheet is up.
    @State private var sharedBox: SharedInbox.Box?
    /// Files opened in Canvia together arrive one at a time; they are
    /// gathered for a moment, then landed as one share.
    @State private var arriving: [URL] = []
    @State private var arrivingTask: Task<Void, Never>?
    /// PowerPoints opened in Canvia, to be read in as new designs
    /// (PowerPoints). A list, not one slot: decks opened together arrive
    /// one after another before the view updates, and each must be kept.
    /// The host empties it as it takes them, so each is read once.
    @State private var deckURLs: [URL] = []
    @Environment(\.scenePhase) private var scenePhase
    /// Settings' Appearance: System, Light or Dark.
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    init() {
        // Launch is the one moment no editor can be holding freshly added
        // media that hasn't been saved yet, so it's the safe time to sweep.
        // Trash first, so what it empties is not still holding media. The
        // photos, soundtracks and clips are swept together, over one read
        // of the library rather than one each. Your uploads are listed
        // first — everything already stored, the first time — as the sweep
        // never takes one.
        DesignLibrary.purgeTrash()
        // Shares never brought in — the app stopped with the sheet up.
        SharedInbox.sweep()
        Uploads.seedIfNeeded()
        DesignLibrary.pruneUnusedFiles()
        // The bundled fonts and your own, registered with CoreText for this
        // process before anything is measured or drawn.
        FontLibrary.registerBundledFonts()
        FontStore.registerInstalled()
        // The samples with their pictures, so the first Home shows two
        // finished designs rather than two grey boxes. An App is made on
        // the main thread, where ImageRenderer draws.
        let samples = DesignLibrary.seedStartersIfNeeded()
        MainActor.assumeIsolated {
            for sample in samples { DesignLibrary.writeThumbnail(for: sample) }
        }
        _editingStore = State(initialValue: Self.storeForLaunchArguments() ?? Self.storeForLaunchRequest())
    }

    /// A design file handed to the app, opened as a new design in the
    /// editor — the one open saves as it closes, as leaving it always does.
    /// Read in away from the main thread, under an "Opening the design…"
    /// card, since a file with clips in it takes a while.
    private func openDesignFile(_ url: URL) {
        guard url.isFileURL else { return }
        let taken = DesignLibrary.recents().map(\.title)
        openingFile = true
        Task { @MainActor in
            defer {
                openingFile = false
                DesignPackage.discardInboxCopy(url)
            }
            do {
                var design = try await DesignPackage.importFileInBackground(at: url, taken: taken)
                design.updatedAt = Date().timeIntervalSince1970 * 1000
                DesignLibrary.save(design)
                withAnimation(.snappy(duration: 0.28)) { editingStore = DesignStore(design: design) }
            } catch {
                openError = error.localizedDescription
            }
        }
    }

    /// A workbook's sheets to choose one from, and the design's title.
    struct SheetsIn {
        var sheets: [XlsxReader.Sheet]
        var title: String
    }

    /// An Excel workbook handed to the app, read under the same card a
    /// design file shows, and opened as a new design with a chart of its
    /// sheet (Spreadsheets) — the one chosen first when it has several.
    private func openSpreadsheet(_ url: URL) {
        guard url.isFileURL else { return }
        let title = Spreadsheets.title(fromFileName: url.lastPathComponent)
        openingFile = true
        Task { @MainActor in
            let read = await Spreadsheets.read(at: url)
            openingFile = false
            DesignPackage.discardInboxCopy(url)
            switch read {
            case .rows(let imported): chart(imported.cells, title: title)
            case .sheets(let sheets): sheetsIn = SheetsIn(sheets: sheets, title: title)
            case .refused(let why): openError = why
            }
        }
    }

    /// A sheet's rows as a new design with a chart of them, opened.
    private func chart(_ rows: [[String]], title: String) {
        do {
            let design = try Spreadsheets.importRows(rows, title: title, taken: DesignLibrary.recents().map(\.title))
            withAnimation(.snappy(duration: 0.28)) { editingStore = DesignStore(design: design) }
        } catch {
            openError = error.localizedDescription
        }
    }

    /// A photo, video, PDF or SVG handed to the app, gathered with any that
    /// come with it, copied into the inbox and offered as a new design
    /// (SharedInbox). The copies handed over go once landed.
    private func receiveShared(_ url: URL) {
        arriving.append(url)
        arrivingTask?.cancel()
        arrivingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let urls = arriving
            arriving = []
            let box = await Task.detached(priority: .userInitiated) { SharedInbox.land(urls) }.value
            for url in urls { DesignPackage.discardInboxCopy(url) }
            if let box {
                sharedBox = box
            } else {
                openError = SharedInbox.failureText(failed: urls.count, total: urls.count)
            }
        }
    }

    /// An App Intent's or a quick action's request, if one is waiting: a
    /// new design at a size, or one of the library's designs.
    private static func storeForLaunchRequest() -> DesignStore? {
        guard let request = LaunchRequest.take() else { return nil }
        return store(for: request)
    }

    private static func store(for request: LaunchRequest.Request) -> DesignStore? {
        switch request {
        case .newDesign(let w, let h, let title):
            // Never a name already on the shelf: "Instagram Post 2".
            var design = Design(title: Titles.unique(title, taken: DesignLibrary.recents().map(\.title)),
                                width: w, height: h)
            design.updatedAt = Date().timeIntervalSince1970 * 1000
            DesignLibrary.save(design)
            return DesignStore(design: design)
        case .newType(let id, let title):
            // A size this build does not list is the first size.
            guard let preset = SizePreset.byId(id) ?? SizePreset.all.first else { return nil }
            var design = preset.makeDesign(title: Titles.unique(title, taken: DesignLibrary.recents().map(\.title)))
            design.updatedAt = Date().timeIntervalSince1970 * 1000
            DesignLibrary.save(design)
            return DesignStore(design: design)
        case .open(let id):
            return DesignLibrary.load(id: id).map { DesignStore(design: $0) }
        }
    }

    /// Serve a waiting request with the app in front. A design asked for by
    /// id that is no longer on the shelf says so rather than doing nothing.
    private func serveLaunchRequest() {
        guard let request = LaunchRequest.take() else { return }
        guard let store = Self.store(for: request) else {
            if case .open = request { designMissing = true }
            return
        }
        withAnimation(.snappy(duration: 0.28)) { editingStore = store }
    }

    /// `-canviaOpenTemplate <n>` opens straight into the editor on template n.
    ///
    /// This exists so CI can photograph the editor, not only the home screen:
    /// the two things hardest to review from source are how a screen is
    /// composed and whether dark mode holds up, and neither is visible in a
    /// screenshot of the launch screen. Debug-only, and driven by a launch
    /// argument, so it is not reachable in a shipped build at all.
    private static func storeForLaunchArguments() -> DesignStore? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-canviaOpenTemplate"),
              arguments.index(after: flag) < arguments.endIndex,
              let index = Int(arguments[arguments.index(after: flag)]),
              ContentLibrary.templates.indices.contains(index) else { return nil }
        return DesignStore(design: ContentLibrary.templates[index].instantiate())
        #else
        return nil
        #endif
    }

    /// The card shown while a file is read in, and the choice of sheet of
    /// a workbook with several.
    private var openingOverlay: some View {
        ZStack { if openingFile { OpeningDesignCard() } }
            .confirmationDialog("Choose a sheet", isPresented: choosingSheet, titleVisibility: .visible) {
                sheetButtons
            }
    }

    private var choosingSheet: Binding<Bool> {
        Binding(get: { sheetsIn != nil }, set: { if !$0 { sheetsIn = nil } })
    }

    /// A button for each sheet of the workbook opened, as Import data lists
    /// them.
    @ViewBuilder
    private var sheetButtons: some View {
        if let choice = sheetsIn {
            ForEach(Array(choice.sheets.enumerated()), id: \.offset) { _, sheet in
                Button(sheet.name) {
                    sheetsIn = nil
                    chart(DataGrid.fromRows(sheet.cells).cells, title: choice.title)
                }
            }
        }
        Button("Cancel", role: .cancel) { sheetsIn = nil }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let store = editingStore {
                    EditorView(store: store) {
                        withAnimation(.snappy(duration: 0.28)) { editingStore = nil }
                    }
                    // A new identity for each design, so one opened over
                    // another (from Siri or a quick action) closes the first
                    // — which saves it — rather than swapping it out unsaved.
                    .id(ObjectIdentifier(store))
                    // The transition was declared here from the start but had
                    // never played: neither assignment to editingStore was
                    // animated, so opening and closing a design just snapped.
                    .transition(.move(edge: .trailing))
                } else {
                    HomeView(onOpen: { design in
                        var opened = design
                        opened.updatedAt = Date().timeIntervalSince1970 * 1000
                        DesignLibrary.save(opened)
                        withAnimation(.snappy(duration: 0.28)) {
                            editingStore = DesignStore(design: opened)
                        }
                    }, onImport: { box in
                        // Import's photos, clips or PDF, as a share is.
                        sharedBox = box
                    })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            // A Spotlight result opens its design.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let id = SpotlightIndexer.designID(from: activity),
                      let design = DesignLibrary.load(id: id) else { return }
                withAnimation(.snappy(duration: 0.28)) { editingStore = DesignStore(design: design) }
            }
            // A suggested or handed-off design opens too.
            .onContinueUserActivity(DesignActivity.type) { activity in
                guard let id = DesignActivity.designID(from: activity),
                      let design = DesignLibrary.load(id: id) else { return }
                withAnimation(.snappy(duration: 0.28)) { editingStore = DesignStore(design: design) }
            }
            // An intent or quick action that ran while the app was already
            // open.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                serveLaunchRequest()
            }
            // A quick action can arrive after the scene is already active.
            .onReceive(NotificationCenter.default.publisher(for: QuickActions.requested)) { _ in
                serveLaunchRequest()
            }
            .alert("That design isn't here any more", isPresented: $designMissing) {
                Button("OK") { designMissing = false }
            }
            // A design file tapped in Files, opened from Mail or shared from
            // another app — at launch or while the app is open, once each.
            // A photo, video, PDF or SVG opened in Canvia becomes a design,
            // and so does a PowerPoint, after the sheet that says what came in.
            .onOpenURL { url in
                if SharedInbox.kind(of: url) != nil {
                    receiveShared(url)
                } else if Spreadsheets.isSpreadsheet(url) {
                    openSpreadsheet(url)
                } else if PowerPoints.isDeck(url) {
                    deckURLs.append(url)
                } else {
                    openDesignFile(url)
                }
            }
            .powerPointImport($deckURLs) { design in
                withAnimation(.snappy(duration: 0.28)) { editingStore = DesignStore(design: design) }
            }
            .sharedDesignSheet($sharedBox, editing: $editingStore, failure: $openError)
            // Exports finished with their sheet closed, shared as the app
            // comes back (ExportQueue).
            .modifier(ExportDelivery())
            .overlay { openingOverlay }
            .preferredColorScheme(Appearance.scheme(appearance))
            .alert("Couldn't open that file", isPresented: Binding(
                get: { openError != nil }, set: { if !$0 { openError = nil } })) {
                Button("OK") { openError = nil }
            } message: {
                Text(openError ?? "")
            }
        }

        // A second window on iPad, opened from a design's context menu.
        WindowGroup("Design", id: "design", for: String.self) { $id in
            DesignWindow(id: $id)
        }
    }
}
