// Folders as a whole, and Select on Home: what renaming a folder moves, and
// which designs a Select picks. A folder is still only the `folder` each
// design is filed under, so renaming or emptying one moves its designs, one
// by one, with move(id:toFolder:). The Android twin's Shelf
// (core/content/Shelf.kt) by the same rules.

import Foundation

extension DesignLibrary {

    /// The longest a folder's name can be, in UTF-16 units as Android
    /// counts a String's length, so a name one phone takes the other does.
    static let folderNameLimit = 40

    /// A folder name as it is kept: trimmed, and none when it is blank.
    static func folderName(_ raw: String?) -> String? {
        guard let name = raw?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    /// What renaming a folder does.
    struct FolderRename: Equatable {
        /// The designs filed under the new name: every one in the folder.
        var ids: [String]
        /// The new name, as it is kept.
        var name: String
        /// Another folder already has the name, so the two become one.
        var merges: Bool
    }

    /// What renaming the folder `from` to `to` would do, or nil when `to`
    /// is no name for a folder — blank, or past `folderNameLimit` — or is
    /// the folder's own, so Rename has nothing to do. A folder of the same
    /// name, exactly, is a merge.
    static func renamePlan(_ designs: [RecentDesign], from: String, to: String) -> FolderRename? {
        guard let name = folderName(to), name.utf16.count <= folderNameLimit, name != from else { return nil }
        let ids = designs.filter { $0.folder == from }.map(\.id)
        let merges = designs.contains { $0.folder == name }
        return FolderRename(ids: ids, name: name, merges: merges)
    }

    // MARK: select

    /// The designs picked among `shelf`, in its order: what Move,
    /// Duplicate and Delete act on, whether on show or filtered out of
    /// sight. One picked that is no longer there is passed by.
    static func picked(_ picked: Set<String>, among shelf: [RecentDesign]) -> [RecentDesign] {
        shelf.filter { picked.contains($0.id) }
    }

    /// Whether every design on show is picked, so the bar offers
    /// "Deselect all".
    static func allPicked(_ picked: Set<String>, among shown: [RecentDesign]) -> Bool {
        !shown.isEmpty && shown.allSatisfy { picked.contains($0.id) }
    }

    /// "Select all", or "Deselect all" once every design on show is picked;
    /// either way only the designs on show.
    static func togglingAll(_ picked: Set<String>, among shown: [RecentDesign]) -> Set<String> {
        let ids = shown.map(\.id)
        return allPicked(picked, among: shown) ? picked.subtracting(ids) : picked.union(ids)
    }
}
