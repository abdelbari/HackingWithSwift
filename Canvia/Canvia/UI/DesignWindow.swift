// A design in a window of its own, for iPad side by side: opened from the
// home screen's context menu, closed back to nothing rather than to home.

import SwiftUI

struct DesignWindow: View {
    @Binding var id: String?
    @State private var store: DesignStore?
    @Environment(\.dismissWindow) private var dismissWindow
    /// Settings' Appearance, as the main window wears it.
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    var body: some View {
        Group {
            if let store {
                if Docs.isDoc(store.design) {
                    DocEditorView(store: store) { dismissWindow() }
                } else {
                    EditorView(store: store) { dismissWindow() }
                }
            } else {
                ContentUnavailableView("This design is no longer here",
                                       systemImage: "rectangle.slash",
                                       description: Text("It may have been deleted from the home screen."))
            }
        }
        .preferredColorScheme(Appearance.scheme(appearance))
        .onAppear {
            if store == nil, let id, let design = DesignLibrary.load(id: id) {
                store = DesignStore(design: design)
            }
        }
    }
}
