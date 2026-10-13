// Move to page and Select multiple: the selection carried to another page,
// and a selection built one tap at a time — see PageMove for where moved
// things land.

import Foundation

extension DesignStore {

    // MARK: move to page

    /// The selection — whole groups, and the connectors joined to it —
    /// taken off this page and put on page `index` (zero-based) where it
    /// sat, on top of what is there in the order it was in, as one undo
    /// step. That page becomes the one shown, the moved things still
    /// selected. Anything locked stays behind; a selection all locked is
    /// refused with a buzz.
    func moveSelectedToPage(_ index: Int) {
        guard design.pages.indices.contains(index), index != pageIndex, !selection.isEmpty else { return }
        endTextEdit()
        finishCrop()
        let ids = PageMove.moving(page.elements, selection: selection)
        guard !ids.isEmpty else {
            buzz(.reject)
            return
        }
        let source = pageIndex
        let moved = PageMove.clamped(page.elements.filter { ids.contains($0.id) },
                                     from: pageSize, to: design.size(at: index))
        apply { d in
            d.pages[source].elements.removeAll { ids.contains($0.id) }
            d.pages[index].elements.append(contentsOf: moved)
        }
        pageIndex = index
        selection = Set(moved.map(\.id))
        announce("Moved to page \(index + 1)")
    }

    /// A page Move to page offers: where it is, zero-based, and its name.
    struct MoveTarget: Identifiable, Equatable {
        var index: Int
        var name: String
        var id: Int { index }
    }

    /// The pages Move to page offers: every one but this, by number and
    /// title — "Page 2 · Intro".
    var moveTargets: [MoveTarget] {
        design.pages.indices.filter { $0 != pageIndex }.map { i in
            MoveTarget(index: i, name: PageTitles.named(i + 1, title: design.pages[i].title))
        }
    }

    // MARK: select multiple

    /// What VoiceOver hears as Select multiple comes on, as TalkBack does
    /// on the Android twin; the view that turns it on says it.
    static let selectMultipleOn = "Select multiple on"

    /// Select multiple on, from the toolbar or the menu.
    func startSelectingMultiple() {
        endTextEdit()
        selectingMultiple = true
    }

    /// Done, Escape or a panel opening: the mode ends, the selection stays.
    func endSelectingMultiple() {
        guard selectingMultiple else { return }
        selectingMultiple = false
    }

    /// A tap on element `id` while Select multiple is on: it — its whole
    /// group, as anywhere else — comes into the selection or goes out of it.
    func tapInSelectMultiple(_ id: String) {
        select(id, additive: true)
    }
}
