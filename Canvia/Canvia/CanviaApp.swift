// Canvia — a Canva-inspired design studio for iOS.
// Entry point + home ⇄ editor routing.

import SwiftUI

@main
struct CanviaApp: App {
    @State private var editingStore: DesignStore?

    init() {
        // Launch is the one moment no editor can be holding freshly added
        // media that hasn't been saved yet, so it's the safe time to sweep.
        DesignLibrary.pruneUnusedMedia()
    }

    var body: some Scene {
        WindowGroup {
            if let store = editingStore {
                EditorView(store: store) {
                    editingStore = nil
                }
                .transition(.move(edge: .trailing))
            } else {
                HomeView { design in
                    var opened = design
                    opened.updatedAt = Date().timeIntervalSince1970 * 1000
                    DesignLibrary.save(opened)
                    editingStore = DesignStore(design: opened)
                }
            }
        }
    }
}
