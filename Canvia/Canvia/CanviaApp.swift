// Canvia — a Canva-inspired design studio for iOS.
// Entry point + home ⇄ editor routing.

import CoreSpotlight
import SwiftUI

@main
struct CanviaApp: App {
    @State private var editingStore: DesignStore?
    /// Why a design file handed to the app could not be opened.
    @State private var openError: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Launch is the one moment no editor can be holding freshly added
        // media that hasn't been saved yet, so it's the safe time to sweep.
        // Trash first, so what it empties is not still holding media. The
        // photos, soundtracks and clips are swept together, over one read
        // of the library rather than one each.
        DesignLibrary.purgeTrash()
        DesignLibrary.pruneUnusedFiles()
        DesignLibrary.seedStartersIfNeeded()
        _editingStore = State(initialValue: Self.storeForLaunchArguments() ?? Self.storeForLaunchRequest())
    }

    /// A design file handed to the app, opened as a new design in the
    /// editor — the one open saves as it closes, as leaving it always does.
    private func openDesignFile(_ url: URL) {
        guard url.isFileURL else { return }
        defer { DesignPackage.discardInboxCopy(url) }
        do {
            var design = try DesignPackage.importFile(at: url, taken: DesignLibrary.recents().map(\.title))
            design.updatedAt = Date().timeIntervalSince1970 * 1000
            DesignLibrary.save(design)
            withAnimation(.snappy(duration: 0.28)) { editingStore = DesignStore(design: design) }
        } catch {
            openError = error.localizedDescription
        }
    }

    /// An App Intent's request, if one is waiting: a new design at a size,
    /// or one of the library's designs.
    private static func storeForLaunchRequest() -> DesignStore? {
        guard let request = LaunchRequest.take() else { return nil }
        switch request {
        case .newDesign(let w, let h, let title):
            var design = Design(title: title, width: w, height: h)
            design.updatedAt = Date().timeIntervalSince1970 * 1000
            DesignLibrary.save(design)
            return DesignStore(design: design)
        case .open(let id):
            return DesignLibrary.load(id: id).map { DesignStore(design: $0) }
        }
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

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let store = editingStore {
                    EditorView(store: store) {
                        withAnimation(.snappy(duration: 0.28)) { editingStore = nil }
                    }
                    // The transition was declared here from the start but had
                    // never played: neither assignment to editingStore was
                    // animated, so opening and closing a design just snapped.
                    .transition(.move(edge: .trailing))
                } else {
                    HomeView { design in
                        var opened = design
                        opened.updatedAt = Date().timeIntervalSince1970 * 1000
                        DesignLibrary.save(opened)
                        withAnimation(.snappy(duration: 0.28)) {
                            editingStore = DesignStore(design: opened)
                        }
                    }
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
            // An intent that ran while the app was already open.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let store = Self.storeForLaunchRequest() else { return }
                withAnimation(.snappy(duration: 0.28)) { editingStore = store }
            }
            // A design file tapped in Files, opened from Mail or shared from
            // another app — at launch or while the app is open, once each.
            .onOpenURL { url in openDesignFile(url) }
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
