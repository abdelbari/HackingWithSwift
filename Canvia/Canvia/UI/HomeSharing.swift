// Share…, Mockups and Present from a design's card on Home (HomeExports):
// the Export sheet over Home for the design as saved, with no editor behind
// it; Mockups, whose New design from mockup opens the design it makes once
// the sheet has gone; and Present from its first page. Home only reads the design: Loop turned on or
// off there lasts for that presentation and is not saved, as the Android twin's.

import SwiftUI

struct HomeSharing: ViewModifier {
    @Binding var exporting: Design?
    @Binding var presenting: Design?
    /// Either asked for on a design whose file does not read.
    @Binding var unopened: Bool
    @Binding var mockingUp: Design?
    /// Opens a design made on Home.
    var open: (Design) -> Void = { _ in }
    /// The design New design from mockup made, opened as Mockups goes.
    @State private var made: Design?

    func body(content: Content) -> some View {
        content
            .sheet(item: $exporting) { design in
                HomeExportSheet(design: design)
            }
            .sheet(item: $mockingUp, onDismiss: openMade) { design in
                MockupSheet(design: design, onNewDesign: { made = $0 })
            }
            .fullScreenCover(item: $presenting) { design in
                PresentationView(design: design, startPage: 0)
            }
            .alert("That design can't be opened", isPresented: $unopened) {
                Button("OK", role: .cancel) {}
            }
    }

    private func openMade() {
        guard let design = made else { return }
        made = nil
        open(design)
    }
}

/// The Export sheet on a design read from its file: a store of its own,
/// made once, which nothing saves.
private struct HomeExportSheet: View {
    @State private var store: DesignStore

    init(design: Design) {
        _store = State(initialValue: DesignStore(design: design))
    }

    var body: some View {
        ExportSheet(store: store, readOnly: true)
    }
}
