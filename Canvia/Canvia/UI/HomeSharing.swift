// Share…, Mockups and Present from a design's card on Home (HomeExports):
// the Export sheet over Home for the design as saved, with no editor behind
// it; Mockups, whose New design from mockup opens the design it makes once
// the sheet has gone, and whose Add to this design saves the design with
// the mockup on it and reads the cards again; and Present from its first
// page. Home only reads the design: Loop turned on or
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
    /// A design saved from here, changed: Home reads its cards again.
    var changed: () -> Void = {}
    /// The design New design from mockup made, opened as Mockups goes.
    @State private var made: Design?

    func body(content: Content) -> some View {
        content
            .sheet(item: $exporting) { design in
                HomeExportSheet(design: design)
            }
            .sheet(item: $mockingUp, onDismiss: openMade) { design in
                MockupSheet(design: design, onNewDesign: { made = $0 }, onChanged: changed)
            }
            .fullScreenCover(item: $presenting) { design in
                // A Doc as its pages.
                PresentationView(design: DocPages.drawn(design), startPage: 0)
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
/// made once, which nothing saves — a Doc's of its pages, its Word document
/// made from its blocks.
private struct HomeExportSheet: View {
    @State private var store: DesignStore
    private let doc: Design?

    init(design: Design) {
        _store = State(initialValue: DesignStore(design: DocPages.drawn(design)))
        doc = Docs.isDoc(design) ? design : nil
    }

    var body: some View {
        ExportSheet(store: store, readOnly: true, doc: doc)
    }
}
