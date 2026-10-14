// Share… and Present from a design's card on Home (HomeExports): the Export
// sheet over Home for the design as saved, with no editor behind it; and
// Present from its first page.

import SwiftUI

struct HomeSharing: ViewModifier {
    @Binding var exporting: Design?
    @Binding var presenting: Design?

    func body(content: Content) -> some View {
        content
            .sheet(item: $exporting) { design in
                HomeExportSheet(design: design)
            }
            .fullScreenCover(item: $presenting) { design in
                PresentationView(design: design, startPage: 0) { on in Self.keepLoop(on, of: design.id) }
            }
    }

    /// Loop turned on or off in Present, kept with the design, as the
    /// editor keeps it.
    private static func keepLoop(_ on: Bool, of id: String) {
        guard var design = DesignLibrary.load(id: id), design.presentLoops != on else { return }
        design.presentLoops = on
        design.updatedAt = Date().timeIntervalSince1970 * 1000
        DesignLibrary.save(design)
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
