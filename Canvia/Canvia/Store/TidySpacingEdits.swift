// Spacing after Tidy up: the gaps of a tidied selection changed all at
// once, from the Position sheet's Spacing slider or a gap handle on the
// canvas — live while it moves, one undo step named Spacing as it lets go
// (Geometry.respaced). Nothing is written to the file for it: the layout
// is read from where the members sit.

import CoreGraphics
import Foundation

extension DesignStore {

    /// What Spacing lays out: the selected things that can move — one
    /// holding its place stays where it is, as on the Android twin.
    var tidyMembers: [Element] {
        selectedElements.filter { !$0.holdsPlace }
    }

    /// The tidied layout and gap of the selection's things that can move
    /// (Geometry.tidyLayout): what Spacing shows and changes. Nil for fewer
    /// than two of them, or for anything not laid out evenly.
    var tidyLayout: Geometry.TidyLayout? {
        let members = tidyMembers
        guard members.count >= 2 else { return nil }
        return Geometry.tidyLayout(members)
    }

    /// The selection laid out again with `gap` between each two, into the
    /// step a slider or handle opened (commitSpacing closes it). Refused on
    /// a locked page.
    func setTidySpacingLive(_ gap: Double) {
        guard tidyLayout != nil, !refusesLockedPage(),
              let spaced = Geometry.respaced(tidyMembers, gap: gap) else { return }
        replaceTransient(spaced)
    }

    /// The spacing let go: one step, named Spacing.
    func commitSpacing() {
        namedStep = tr("Spacing")
        commit()
    }

    /// Spacing set at once — typed, or VoiceOver's adjustable step — as one
    /// step named Spacing.
    func setTidySpacing(_ gap: Double) {
        setTidySpacingLive(gap)
        commitSpacing()
    }
}
