// Folders as a whole, stars, and Select on Home: what renaming a folder
// moves, which folders and designs are starred, and which designs a Select
// picks. A folder is still only the `folder` each design (and each upload,
// Uploads) is filed under — now a path, "Clients/Acme/2026", the folder
// 2026 in Acme in Clients — so renaming, moving or emptying one moves what
// is in it, one by one, with move(id:toFolder:). A flat name from before
// is a path of one level, so there is nothing to migrate. The Android
// twin's Shelf (core/content/Shelf.kt) by the same rules.

import Foundation

extension DesignLibrary {

    /// The longest a folder's name can be — each level of a path — in
    /// UTF-16 units as Android counts a String's length, so a name one
    /// phone takes the other does.
    static let folderNameLimit = 40

    /// What a folder's path is made of.
    static let folderSeparator: Character = "/"

    /// The deepest a folder may be: four levels.
    static let folderDepthLimit = 4

    /// A folder path as it is kept: each level trimmed, empty ones left
    /// out, joined by `folderSeparator`; none when nothing is left.
    static func folderName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw.split(separator: folderSeparator, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: String(folderSeparator))
    }

    /// Whether `raw` can name a folder: something left trimmed, no
    /// `folderSeparator` in it, and at most `folderNameLimit` UTF-16 units.
    static func isFolderName(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !name.contains(folderSeparator) && name.utf16.count <= folderNameLimit
    }

    /// Whether `path` is a folder something can be filed in: 1 to
    /// `folderDepthLimit` levels, each an `isFolderName`, written as kept.
    static func isFolderPath(_ path: String) -> Bool {
        let parts = segments(path)
        return (1...folderDepthLimit).contains(parts.count) && parts.allSatisfy(isFolderName)
            && folderName(path) == path
    }

    /// The folders a path goes through, its own last.
    static func segments(_ path: String?) -> [String] {
        folderName(path)?.split(separator: folderSeparator).map(String.init) ?? []
    }

    /// The folder `name` in `parent` (nil: at the top).
    static func childPath(_ parent: String?, _ name: String) -> String {
        folderName([parent, name.trimmingCharacters(in: .whitespaces)].compactMap { $0 }
            .joined(separator: String(folderSeparator))) ?? ""
    }

    /// The folder `path` is in; nil for one at the top.
    static func parentOf(_ path: String) -> String? {
        let parts = segments(path).dropLast()
        return parts.isEmpty ? nil : parts.joined(separator: String(folderSeparator))
    }

    /// A folder's own name, the last of its path.
    static func leafName(_ path: String) -> String { segments(path).last ?? path }

    /// Whether `folder` is `path` or somewhere inside it.
    static func isInside(_ folder: String?, _ path: String) -> Bool {
        guard let folder else { return false }
        return folder == path || folder.hasPrefix(path + String(folderSeparator))
    }

    /// The breadcrumb to `path`: each folder on the way, as its name and its
    /// path, from the top.
    static func breadcrumb(_ path: String?) -> [(name: String, path: String)] {
        let parts = segments(path)
        return parts.indices.map { i in
            (name: parts[i], path: parts[...i].joined(separator: String(folderSeparator)))
        }
    }

    /// `paths` and every folder on the way to each, once, alphabetically.
    static func allFolders(_ paths: [String]) -> [String] {
        var out = Set<String>()
        for path in paths { for step in breadcrumb(path) { out.insert(step.path) } }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The folders right inside `path` (nil: at the top) among `folders`
    /// — paths, as allFolders gives them — in order.
    static func children(_ folders: [String], of path: String?) -> [String] {
        let depth = segments(path).count
        return allFolders(folders).filter { f in
            segments(f).count == depth + 1 && (path.map { isInside(f, $0) } ?? true)
        }
    }

    /// The designs filed in `path` — and, `recursive`, in every folder
    /// inside it too.
    static func designs(_ designs: [RecentDesign], in path: String, recursive: Bool) -> [RecentDesign] {
        designs.filter { recursive ? isInside($0.folder, path) : $0.folder == path }
    }

    /// `folder` once `from` is `to`: the same place inside it; anything
    /// outside `from` is as it was. A rename, a move into another folder
    /// and Move contents up are each this.
    static func movedFolder(_ folder: String?, from: String, to: String?) -> String? {
        guard let folder, isInside(folder, from) else { return folder }
        let rest = String(folder.dropFirst(from.count)).drop { $0 == folderSeparator }
        return folderName([to, String(rest)].compactMap { $0 }.joined(separator: String(folderSeparator)))
    }

    /// What filing `from` in `into` (nil: the top) makes it, or nil when
    /// that cannot be: into itself or one inside it (a cycle), where it is
    /// already, or deeper than `folderDepthLimit` for anything inside it.
    static func movedInto(_ folders: [String], from: String, into: String?) -> String? {
        if let into, isInside(into, from) { return nil }
        let to = childPath(into, leafName(from))
        guard to != from else { return nil }
        let deepest = allFolders(folders).filter { isInside($0, from) }.map { segments($0).count }.max()
            ?? segments(from).count
        return segments(to).count + deepest - segments(from).count <= folderDepthLimit ? to : nil
    }

    /// What renaming a folder does.
    struct FolderRename: Equatable {
        /// The designs filed under the new name: every one in the folder,
        /// or in a folder inside it, each to the same place under it
        /// (movedFolder).
        var ids: [String]
        /// The new path, as it is kept: in the same folder as before.
        var name: String
        /// Another folder already has the name, so the two become one.
        var merges: Bool
        /// The folder renamed, whose star goes with it.
        var from = ""
    }

    /// What renaming the folder `from` to `to` would do, or nil when `to`
    /// is no name for a folder — blank, past `folderNameLimit`, or with a
    /// `folderSeparator` in it — or is the folder's own, so Rename has
    /// nothing to do. It stays where it is, in the same folder. A folder of
    /// that path already — exactly — is a merge. `uploads` are the folders
    /// uploads are filed in, which make folders too.
    static func renamePlan(_ designs: [RecentDesign], from: String, to: String,
                           uploads: [String] = []) -> FolderRename? {
        guard isFolderName(to) else { return nil }
        let name = childPath(parentOf(from), to)
        guard name != from else { return nil }
        let ids = designs.filter { isInside($0.folder, from) }.map(\.id)
        let merges = allFolders(designs.compactMap(\.folder) + uploads).contains(name)
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

    /// A folder renamed, or moved, takes its star along, and so does every
    /// folder inside it, to its new path (movedFolder); one deleted or moved
    /// up to the top (`to` nil) drops its own, those inside it moving up.
    /// Merged into a folder already there, the merged folder is starred if
    /// either was.
    static func renameFolderStar(_ from: String, to: String?, defaults: UserDefaults = .standard) {
        let folders = homeFolders(fromJSON: defaults.string(forKey: homeFoldersKey) ?? "[]")
        defaults.set(homeFoldersJSON(renamingFolder(folders, from: from, to: folderName(to))), forKey: homeFoldersKey)
    }

    /// `folders` after folder `from` is renamed, or moved, to `to` — the
    /// Android twin's Shelf.renamingFolder: stars are kept by whole path.
    static func renamingFolder(_ folders: [HomeFolder], from: String, to: String?) -> [HomeFolder] {
        let starred = to != nil && folders.contains { ($0.name == from || $0.name == to) && $0.starred }
        let inside = folders.filter { isInside($0.name, from) && $0.name != from }.compactMap { f in
            movedFolder(f.name, from: from, to: to).map { HomeFolder(name: $0, starred: f.starred) }
        }
        let rest = folders.filter { !isInside($0.name, from) && $0.name != to } + inside
        guard let to else { return rest }
        return rest.filter { $0.name != to } + (starred ? [HomeFolder(name: to, starred: true)] : [])
    }

    /// Folder `from` deleted with Move contents up, into `up` (nil: the
    /// top): those inside it keep their stars, and `up` is not starred for
    /// it (removingFolder).
    static func removeFolderStar(_ from: String, up: String?, defaults: UserDefaults = .standard) {
        let folders = homeFolders(fromJSON: defaults.string(forKey: homeFoldersKey) ?? "[]")
        defaults.set(homeFoldersJSON(removingFolder(folders, from: from, up: folderName(up))), forKey: homeFoldersKey)
    }

    /// `folders` after folder `from` is deleted with Move contents up, into
    /// its parent `up`: the folders inside it move up with their stars, its
    /// own star goes, and `up` stays starred or not as it was — the Android
    /// twin's Shelf.removingFolder.
    static func removingFolder(_ folders: [HomeFolder], from: String, up: String?) -> [HomeFolder] {
        let moved = renamingFolder(folders, from: from, to: up)
        guard let up else { return moved }
        let upStarred = folders.contains { $0.name == up && $0.starred }
        return moved.filter { $0.name != up } + (upStarred ? [HomeFolder(name: up, starred: true)] : [])
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
    /// design, then the starred designs — in every folder — each matching
    /// the search (a design by its title or size, then by its words) and in
    /// the current sort, as the Android twin's
    /// Shelf.starred shows them. A folder matches by its name, capitals and
    /// accents aside, and sorts as its designs together do (sortedFolders).
    static func starredShelf(_ designs: [RecentDesign], starredFolders: Set<String>, query: String,
                             sort: Sort) -> (folders: [String], designs: [RecentDesign]) {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let starred = folders(in: designs).filter { name in
            starredFolders.contains(name)
                && (needle.isEmpty || name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
        // Designs by title or size first, then by their words, as the main
        // shelf finds them; Type and Edited are applied by the caller.
        let found = filter(designs.filter(\.starred), query: query, sort: sort, folder: nil,
                           type: .all, edited: .any, now: 0, startOfToday: 0)
        return (sortedFolders(starred, of: designs, sort: sort), found)
    }

    /// Folders in a sort, each as its designs together: by its name, by its
    /// newest edit, or by its pages added up — the most first, then the
    /// newest.
    static func sortedFolders(_ names: [String], of designs: [RecentDesign], sort: Sort) -> [String] {
        // A folder holds what is in the folders inside it too.
        func inside(_ name: String) -> [RecentDesign] { designs.filter { isInside($0.folder, name) } }
        func newest(_ name: String) -> Double { inside(name).map(\.updatedAt).max() ?? 0 }
        func pages(_ name: String) -> Int { inside(name).reduce(0) { $0 + $1.pages } }
        switch sort {
        case .recent:
            return names.sorted { newest($0) > newest($1) }
        case .name:
            return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .largest:
            return names.sorted { pages($0) != pages($1) ? pages($0) > pages($1) : newest($0) > newest($1) }
        }
    }

    /// What the Starred chip says with nothing starred.
    static let starredEmpty = tr("Star a design from its ⋯ menu to find it here.")

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
