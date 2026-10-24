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
/// made from its blocks. A Doc is laid out on its pages away from the main
/// actor, every block measured, as the editor's Export lays it out, the
/// sheet showing progress meanwhile; closing the sheet drops the layout.
private struct HomeExportSheet: View {
    let design: Design
    @State private var store: DesignStore?

    init(design: Design) {
        self.design = design
        // Any other design is ready as it is.
        _store = State(initialValue: Docs.isDoc(design) ? nil : DesignStore(design: design))
    }

    var body: some View {
        exportOrProgress.task { await layOut() }
    }

    @ViewBuilder
    private var exportOrProgress: some View {
        if let store {
            ExportSheet(store: store, readOnly: true, doc: Docs.isDoc(design) ? design : nil)
        } else {
            ProgressView()
                .presentationDetents([.medium])
        }
    }

    @MainActor
    private func layOut() async {
        guard store == nil else { return }
        let doc = design
        let styles = DocPages.styles()
        let laid = await Task.detached(priority: .userInitiated) { Docs.paginated(doc, styles: styles) }.value
        // Closed meanwhile: nothing to show.
        guard !Task.isCancelled else { return }
        store = DesignStore(design: laid)
    }
}

/// Details from a card (DesignDetailsSheet), on the design as saved: Replace…
/// swaps a missing font through it and saves it at once, and Show in
/// Uploads opens Home's Uploads once the sheet has gone.
struct HomeDetails: ViewModifier {
    @Binding var detailing: Design?
    var showUploads: () -> Void
    /// The design saved from here, changed: Home reads its cards again.
    var changed: () -> Void
    @State private var uploadsAsked = false

    func body(content: Content) -> some View {
        content
            .sheet(item: $detailing, onDismiss: afterDetails) { design in
                HomeDetailsSheet(design: design, changed: changed) {
                    uploadsAsked = true
                    detailing = nil
                }
            }
    }

    private func afterDetails() {
        guard uploadsAsked else { return }
        uploadsAsked = false
        showUploads()
    }
}

/// The Details sheet on a design read from its file: a store of its own,
/// made once, whose design is saved whenever Replace… changes it.
private struct HomeDetailsSheet: View {
    let design: Design
    var changed: () -> Void
    var showUploads: () -> Void
    @State private var store: DesignStore
    @State private var saveFailed = false

    init(design: Design, changed: @escaping () -> Void, showUploads: @escaping () -> Void) {
        self.design = design
        self.changed = changed
        self.showUploads = showUploads
        _store = State(initialValue: DesignStore(design: design))
    }

    var body: some View {
        DesignDetailsSheet(store: store) { _ in showUploads() }
            .onChange(of: store.design) { _, now in save(now) }
            .alert("Couldn't change the font", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            }
    }

    /// The design as Replace… left it, saved with its picture.
    private func save(_ now: Design) {
        guard now != design else { return }
        var saved = now
        saved.updatedAt = Date().timeIntervalSince1970 * 1000
        guard DesignLibrary.save(saved) else {
            saveFailed = true
            return
        }
        DesignLibrary.writeThumbnail(for: saved)
        changed()
    }
}
