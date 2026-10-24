// Replace font: one font swapped for another throughout the design
// (FontSwap), as one step named "Replace font" — from the font picker's
// "Replace everywhere…" and its "Change all (N)", as the Android twin's
// view model records it.

import Foundation

extension DesignStore {

    /// `from` swapped for `to` wherever the design uses it and is not
    /// locked, each text measured again, as one step. Returns how many
    /// places changed; none, and nothing recorded, when nothing uses it.
    @discardableResult
    func replaceFontEverywhere(from: String, to: String) -> Int {
        let total = FontSwap.count(design, family: from)
        let next = FontSwap.replaced(design, from: from, to: to, heightFor: measure)
        guard total > 0, next != design else { return 0 }
        // Words being typed are a step of their own.
        if hasPendingChanges && (editingTextId != nil || dictationTarget != nil) { commit() }
        namedStep = tr("Replace font")
        apply { $0 = next }
        buzz(.confirm)
        announce(Self.replacedFontNote(total))
        return total
    }

    /// What Replace font says it did.
    static func replacedFontNote(_ count: Int) -> String {
        trn("Replaced the font in %d place|Replaced the font in %d places", count)
    }
}
