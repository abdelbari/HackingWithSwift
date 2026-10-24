// "Slides: 3" in a carousel page's menus — the pages bar's and the ⋮ over
// each page in the column — with − and +, 2 to 10 (PageSplit): the page a
// slide narrower or wider each step, the menu kept open to step again, as
// the Android twin's page menu keeps it. Nothing for a page that is not cut.

import SwiftUI

struct SlidesMenuItems: View {
    @Bindable var store: DesignStore
    let index: Int

    var body: some View {
        if let split = store.design.pages.indices.contains(index) ? store.design.pages[index].split : nil {
            ControlGroup {
                Button { step(split.columns - 1) } label: { Label("Fewer slides", systemImage: "minus") }
                    .disabled(split.columns <= PageSplit.minColumns)
                Button { step(split.columns + 1) } label: { Label("More slides", systemImage: "plus") }
                    .disabled(split.columns >= PageSplit.maxColumns)
            } label: {
                Text(tr("Slides: %d", split.columns))
            }
            .menuActionDismissBehavior(.disabled)
        }
    }

    /// This page made the one worked, then given `columns` slides.
    private func step(_ columns: Int) {
        store.setPage(index)
        store.stepSlides(to: columns)
    }
}
