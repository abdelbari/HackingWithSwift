// Where something is filed — a design, an upload, or a folder: the folders
// in use as a tree, each indented under the one it is in, "No folder" at
// the top (or what taking it out of its folder says), and New folder here, a
// folder made inside the one picked. A folder is only a path on what is
// filed in it, so a folder exists while something is in it. `excluded`
// folders cannot be picked — a folder, and those inside it, for a folder
// being moved — and a new folder past DesignLibrary.folderDepthLimit levels
// is refused. The Android twin's MoveToFolderDialog.

import SwiftUI

struct FolderPicker: View {
    /// What the sheet is called: "Move to folder", "Move folder “Acme”".
    let heading: String
    /// Where it is now; nil at the top.
    let current: String?
    /// Every folder in use (DesignLibrary.allFolders).
    let folders: [String]
    /// What the top row says.
    var takeOut: String = tr("No folder")
    var excluded: (String) -> Bool = { _ in false }
    /// The path picked — nil for the top.
    var onMove: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?
    @State private var fresh = ""

    init(heading: String, current: String?, folders: [String], takeOut: String = tr("No folder"),
         excluded: @escaping (String) -> Bool = { _ in false }, onMove: @escaping (String?) -> Void) {
        self.heading = heading
        self.current = current
        self.folders = folders
        self.takeOut = takeOut
        self.excluded = excluded
        self.onMove = onMove
        _chosen = State(initialValue: current)
    }

    /// Where the move goes: a new folder inside the one picked, or that one.
    private var target: String? {
        fresh.trimmingCharacters(in: .whitespaces).isEmpty ? chosen : DesignLibrary.childPath(chosen, fresh)
    }

    private var canMove: Bool {
        let blank = fresh.trimmingCharacters(in: .whitespaces).isEmpty
        guard target != current else { return false }
        if blank { return true }
        guard let target else { return false }
        return DesignLibrary.isFolderName(fresh) && DesignLibrary.isFolderPath(target)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(takeOut, depth: 0, path: nil)
                    ForEach(DesignLibrary.allFolders(folders), id: \.self) { path in
                        row(DesignLibrary.leafName(path), depth: DesignLibrary.segments(path).count, path: path)
                    }
                }
                Section {
                    TextField(chosen.map { tr("New folder in %@", DesignLibrary.leafName($0)) } ?? tr("New folder here"),
                              text: $fresh)
                }
            }
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        let picked = target
                        dismiss()
                        onMove(picked)
                    }
                    .disabled(!canMove)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// One folder of the tree: its name, indented a step a level.
    private func row(_ name: String, depth: Int, path: String?) -> some View {
        let enabled = path.map { !excluded($0) } ?? true
        let selected = chosen == path
        return Button {
            chosen = path
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
                if depth > 0 { Image(systemName: "folder").foregroundStyle(.secondary) }
                Text(name).lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(16 * max(depth - 1, 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Where Home is in its folders: All, then each folder on the way, a tap
/// going back up to it — the last, where it is, said as such.
struct FolderBreadcrumb: View {
    let path: String
    var onGo: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button("All") { onGo(nil) }
                ForEach(DesignLibrary.breadcrumb(path), id: \.path) { step in
                    Image(systemName: "chevron.forward")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    if step.path == path {
                        Text(step.name)
                            .font(.subheadline.weight(.semibold))
                            .accessibilityValue(Text("Current folder"))
                    } else {
                        Button(step.name) { onGo(step.path) }
                    }
                }
            }
            .font(.subheadline)
        }
    }
}

/// A folder inside the one Home shows, above its designs: its name and what
/// is in it; a tap opens it, and its menu stars, renames, moves or deletes
/// it — as VoiceOver's actions too.
struct FolderTile: View {
    let path: String
    let count: Int
    let starred: Bool
    var onOpen: () -> Void
    var onStar: () -> Void
    var onRename: () -> Void
    var onMove: () -> Void
    var onDelete: () -> Void

    var body: some View {
        let name = DesignLibrary.leafName(path)
        let inside = trn("%d item|%d items", count)
        return Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: starred ? "star.fill" : "folder.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(inside).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(starred ? tr("%@, folder, %@, starred", name, inside) : tr("%@, folder, %@", name, inside))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: Text(starred ? tr("Remove from starred") : tr("Add to starred"))) { onStar() }
        .accessibilityAction(named: Text("Rename folder…")) { onRename() }
        .accessibilityAction(named: Text("Move folder…")) { onMove() }
        .accessibilityAction(named: Text("Delete folder…")) { onDelete() }
    }

    @ViewBuilder
    private var menu: some View {
        Button(action: onStar) {
            Label(starred ? tr("Remove from starred") : tr("Add to starred"), systemImage: starred ? "star.slash" : "star")
        }
        Button(action: onRename) { Label("Rename folder…", systemImage: "pencil") }
        Button(action: onMove) { Label("Move folder…", systemImage: "folder") }
        Button(role: .destructive, action: onDelete) { Label("Delete folder…", systemImage: "trash") }
    }
}
