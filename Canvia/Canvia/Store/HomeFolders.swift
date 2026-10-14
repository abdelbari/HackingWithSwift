// Folders as a whole, stars, and Select on Home: what renaming a folder
// moves, which folders and designs are starred, and which designs a Select
// picks. A folder is still only the `folder` each
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
        /// The folder renamed, whose star goes with it.
        var from = ""
    }

    /// What renaming the folder `from` to `to` would do, or nil when `to`
    /// is no name for a folder — blank, or past `folderNameLimit` — or is
    /// the folder's own, so Rename has nothing to do. A folder of the same
    /// name, exactly, is a merge.
    static func renamePlan(_ designs: [RecentDesign], from: String, to: String) -> FolderRename? {
        guard let name = folderName(to), name.utf16.count <= folderNameLimit, name != from else { return nil }
        let ids = designs.filter { $0.folder == from }.map(\.id)
        let merges = designs.contains { $0.folder == name }
        return FolderRename(ids: ids, name: name, merges: merges, from: from)
    }

    // MARK: starred

    /// The home-folders preference: the folders Home knows of, as a JSON
    /// list in which each is a bare name, "Clients", or {"name": "Clients",
    /// "starred": true} — the bare form, as older lists hold it, still read.
    /// Folders are their designs' `folder`, so only the starred ones need
    /// listing here.
    static let homeFoldersKey = "home-folders"

    /// One folder in the home-folders list.
    struct HomeFolder: Equatable, Sendable {
        var name: String
        var starred = false
    }

    /// The list read back; anything that is not a name or an object with
    /// one is passed over, and a name listed twice counts once, starred if
    /// either is.
    static func homeFolders(fromJSON text: String) -> [HomeFolder] {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        var folders: [HomeFolder] = []
        for item in raw {
            var folder: HomeFolder?
            if let name = item as? String {
                folder = folderName(name).map { HomeFolder(name: $0) }
            } else if let object = item as? [String: Any], let name = folderName(object["name"] as? String) {
                folder = HomeFolder(name: name, starred: (object["starred"] as? Bool) == true)
            }
            guard let folder else { continue }
            if let i = folders.firstIndex(where: { $0.name == folder.name }) {
                folders[i].starred = folders[i].starred || folder.starred
            } else {
                folders.append(folder)
            }
        }
        return folders
    }

    /// The list as written: a starred folder as {"name","starred":true},
    /// any other as its bare name.
    static func homeFoldersJSON(_ folders: [HomeFolder]) -> String {
        let raw: [Any] = folders.map { folder -> Any in
            guard folder.starred else { return folder.name }
            return ["name": folder.name, "starred": true] as [String: Any]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The folders starred on Home.
    static func starredFolders(_ defaults: UserDefaults = .standard) -> Set<String> {
        let folders = homeFolders(fromJSON: defaults.string(forKey: homeFoldersKey) ?? "[]")
        return Set(folders.filter(\.starred).map(\.name))
    }

    /// Stars or unstars a folder; the rest of the list is kept as it was.
    static func setFolderStarred(_ name: String, _ on: Bool, defaults: UserDefaults = .standard) {
        guard let name = folderName(name) else { return }
        var folders = homeFolders(fromJSON: defaults.string(forKey: homeFoldersKey) ?? "[]")
        if let i = folders.firstIndex(where: { $0.name == name }) {
            folders[i].starred = on
        } else if on {
            folders.append(HomeFolder(name: name, starred: true))
        }
        defaults.set(homeFoldersJSON(folders), forKey: homeFoldersKey)
    }

    /// A folder renamed takes its star along; one deleted (`to` nil) drops
    /// it. Merged into a folder already there, the merged folder is starred
    /// if either was.
    static func renameFolderStar(_ from: String, to: String?, defaults: UserDefaults = .standard) {
        var folders = homeFolders(fromJSON: defaults.string(forKey: homeFoldersKey) ?? "[]")
        guard let i = folders.firstIndex(where: { $0.name == from }) else { return }
        let was = folders.remove(at: i)
        if let to = folderName(to) {
            if let j = folders.firstIndex(where: { $0.name == to }) {
                folders[j].starred = folders[j].starred || was.starred
            } else {
                folders.append(HomeFolder(name: to, starred: was.starred))
            }
        }
        defaults.set(homeFoldersJSON(folders), forKey: homeFoldersKey)
    }

    /// Stars or unstars a design. Starring is not an edit, so the design's
    /// edit time stays, as filing it does. False when it does not read or
    /// could not be written.
    @discardableResult
    static func setStarred(id: String, _ on: Bool) -> Bool {
        guard var design = load(id: id) else { return false }
        guard design.isStarred != on else { return true }
        design.isStarred = on
        return save(design)
    }

    /// What the Starred chip shows: the starred folders that still hold a
    /// design, in the folder chips' order (by name), then the starred
    /// designs — in every folder — that match the search, in the current
    /// sort.
    static func starredShelf(_ designs: [RecentDesign], starredFolders: Set<String>, query: String,
                             sort: Sort) -> (folders: [String], designs: [RecentDesign]) {
        let starred = folders(in: designs).filter { starredFolders.contains($0) }
        return (starred, filter(designs.filter(\.starred), query: query, sort: sort))
    }

    /// What the Starred chip says with nothing starred.
    static let starredEmpty = "Star a design from its ⋯ menu to find it here."

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
