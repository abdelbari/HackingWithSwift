// One thing taken out of a group, or put into one, without ungrouping the
// rest: More's Remove from group for what a tap a level deeper selected,
// and Layers' drag of a row across a group's edge with its VoiceOver
// actions (Groups.removedFromGroup, Groups.addedToGroup). Each is one undo
// step — Ungroup or Group — and a locked element or page is refused, felt
// and said, as everywhere else. The Android twin's group membership.

import Foundation

extension DesignStore {

    /// Whether More offers Remove from group: what is selected is all in
    /// groups, and is not a whole outermost group — a member, or a level
    /// inside, as a tap a level deeper selects (Groups.deeper).
    var canRemoveFromGroup: Bool {
        let picked = selectedElements
        guard !picked.isEmpty, picked.allSatisfy({ $0.group != nil }) else { return false }
        return Groups.whole(page.elements, selection: selection) == nil
    }

    /// More's Remove from group, for what is selected.
    func removeSelectedFromGroup() {
        removeFromGroup(selection)
    }

    /// The elements `ids` each out of its innermost group, as one undo step
    /// named Ungroup; they stay selected.
    func removeFromGroup(_ ids: Set<String>) {
        guard !refusesGroupChange(ids) else { return }
        let after = Groups.removedFromGroup(page.elements, ids: ids)
        guard after != page.elements else { return }
        buzz(.grouped)
        // Words being typed are a step of their own.
        if hasPendingChanges && (editingTextId != nil || dictationTarget != nil) { commit() }
        namedStep = tr("Ungroup")
        applyToPage { $0.elements = after }
    }

    /// The elements `ids` into group `groupId`, above its top-most member,
    /// as one undo step named Group.
    func addToGroup(_ ids: Set<String>, group groupId: String) {
        guard !refusesGroupChange(ids) else { return }
        let after = Groups.addedToGroup(page.elements, ids: ids, groupId: groupId)
        guard after != page.elements else { return }
        buzz(.grouped)
        // Words being typed are a step of their own.
        if hasPendingChanges && (editingTextId != nil || dictationTarget != nil) { commit() }
        namedStep = tr("Group")
        applyToPage { $0.elements = after }
    }

    /// True — felt and said — when the page is locked, or any of `ids` is
    /// locked whole; a position lock may change group, as it may group.
    private func refusesGroupChange(_ ids: Set<String>) -> Bool {
        if refusesLockedPage() { return true }
        guard page.elements.contains(where: { ids.contains($0.id) && $0.locked }) else { return false }
        buzz(.reject)
        announce(tr("This element is locked"), undoable: false)
        return true
    }
}
