// Recently deleted on Home: designs, uploads and folders apart, each with
// Restore, Delete forever (asked first) and an Empty of its own. What went
// to Recently deleted with a folder is listed under the folder, not beside
// it, and comes back with it. As the Android twin's Recently deleted.

import SwiftUI

/// One upload or font of your own in Recently deleted.
struct TrashedUpload: Identifiable, Equatable {
    var id: String
    var title: String
    var systemImage: String
    /// When it went, in epoch milliseconds.
    var deleted: Double
    var font: Bool

    /// What an upload is called in Recently deleted: its file's name where
    /// it came with one, else what kind it is.
    init(upload entry: Uploads.Entry) {
        id = entry.id
        switch entry.kind {
        case .image:
            title = entry.fileName ?? tr("Photo")
            systemImage = "photo"
        case .video:
            title = entry.fileName ?? tr("Video")
            systemImage = "film"
        case .audio:
            title = entry.fileName ?? tr("Audio")
            systemImage = "music.note"
        }
        deleted = entry.deleted ?? entry.added
        font = false
    }

    /// A font of your own, by its family.
    init(font: Uploads.FontEntry) {
        id = font.id
        title = font.family
        systemImage = "textformat"
        deleted = font.deleted ?? font.added
        self.font = true
    }
}

/// Collapsed by default: what was deleted is not what the home screen is
/// for, but it has to be findable for the thirty days it is kept.
struct RecentlyDeletedSection: View {
    var designs: [RecentDesign]
    var uploads: [TrashedUpload]
    var folders: [DesignLibrary.HomeFolder]
    @Binding var expanded: Bool
    /// Designs gone for good, so an Undo still on offer for them goes.
    var onGoneForGood: ([String]) -> Void
    /// Something came back or went: the shelf is read again.
    var onChanged: () -> Void

    /// Designs, Uploads or Folders.
    @State private var segment = 0
    @State private var deletingDesign: RecentDesign?
    @State private var deletingUpload: TrashedUpload?
    @State private var deletingFolder: DesignLibrary.HomeFolder?
    @State private var emptying = false

    /// What went with a folder, listed under it.
    private var withFolders: Set<String> { Set(folders.flatMap { $0.designs + $0.uploads }) }
    private var shownDesigns: [RecentDesign] { designs.filter { !withFolders.contains($0.id) } }
    private var shownUploads: [TrashedUpload] { uploads.filter { !withFolders.contains($0.id) } }

    /// Every row Recently deleted has, of the three lists.
    var total: Int { shownDesigns.count + shownUploads.count + folders.count }

    private var days: Int { Int(DesignLibrary.trashRetention / 86_400) }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                segmentPicker
                rows
                Text(footer)
                    .font(.caption).foregroundStyle(.secondary)
                if !segmentEmpty {
                    Button("Empty", role: .destructive) { emptying = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Recently deleted (\(total))")
                .font(.title3.weight(.bold))
        }
        .padding(.horizontal)
        .modifier(TrashDialogs(deletingDesign: $deletingDesign, deletingUpload: $deletingUpload,
                               deletingFolder: $deletingFolder, emptying: $emptying, emptyQuestion: emptyQuestion,
                               onEmpty: emptySegment, onGoneForGood: onGoneForGood, onChanged: onChanged))
    }

    private var segmentPicker: some View {
        Picker("Recently deleted", selection: $segment) {
            Text(verbatim: "\(tr("Designs")) (\(shownDesigns.count))").tag(0)
            Text(verbatim: "\(tr("Uploads")) (\(shownUploads.count))").tag(1)
            Text(verbatim: "\(tr("Folders")) (\(folders.count))").tag(2)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var rows: some View {
        switch segment {
        case 0:
            ForEach(shownDesigns) { entry in designRow(entry) }
        case 1:
            ForEach(shownUploads) { entry in uploadRow(entry) }
        default:
            ForEach(Array(folders.enumerated()), id: \.offset) { _, folder in folderRow(folder) }
        }
    }

    private var segmentEmpty: Bool {
        switch segment {
        case 0: return shownDesigns.isEmpty
        case 1: return shownUploads.isEmpty
        default: return folders.isEmpty
        }
    }

    private var footer: String {
        switch segment {
        case 0:
            return trn("Designs in Recently deleted are removed after %d day.|Designs in Recently deleted are removed after %d days.", days)
        case 1:
            return trn("Uploads in Recently deleted are removed after %d day.|Uploads in Recently deleted are removed after %d days.", days)
        default:
            return trn("Folders in Recently deleted are removed after %d day.|Folders in Recently deleted are removed after %d days.", days)
        }
    }

    // MARK: rows

    private func designRow(_ entry: RecentDesign) -> some View {
        TrashRow(title: entry.title, deleted: entry.updatedAt, onRestore: {
            DesignLibrary.restore(id: entry.id)
            PostReminders.restored(designId: entry.id)
            onChanged()
        }, onDelete: { deletingDesign = entry }) {
            ShelfThumbnail(id: entry.id, stamp: entry.thumbnailStamp, trashed: true)
        }
    }

    private func uploadRow(_ entry: TrashedUpload) -> some View {
        TrashRow(title: entry.title, deleted: entry.deleted, onRestore: {
            Uploads.restore([entry.id])
            if entry.font { FontStore.installed() }
            onChanged()
        }, onDelete: { deletingUpload = entry }) {
            Image(systemName: entry.systemImage).foregroundStyle(.secondary)
        }
    }

    private func folderRow(_ folder: DesignLibrary.HomeFolder) -> some View {
        TrashRow(title: DesignLibrary.leafName(folder.name), deleted: folder.deleted ?? 0, onRestore: {
            DesignLibrary.restoreFolder(folder)
            onChanged()
        }, onDelete: { deletingFolder = folder }) {
            Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
        }
    }

    // MARK: work

    /// The list shown emptied, for good.
    private func emptySegment() {
        switch segment {
        case 0:
            let ids = shownDesigns.map(\.id)
            for id in ids { DesignLibrary.deleteTrashed(id: id) }
            onGoneForGood(ids)
        case 1:
            for entry in shownUploads { Uploads.deleteForever(entry.id, font: entry.font) }
        default:
            for folder in folders {
                DesignLibrary.deleteFolderForever(folder)
                onGoneForGood(folder.designs)
            }
        }
        onChanged()
    }

    /// What emptying the list shown asks first.
    private var emptyQuestion: String {
        switch segment {
        case 0: return DesignLibrary.emptyTrashQuestion(count: shownDesigns.count)
        case 1: return trn("Delete %d upload forever?|Delete %d uploads forever?", shownUploads.count)
        default: return trn("Delete %d folder forever?|Delete %d folders forever?", folders.count)
        }
    }
}

/// One row of Recently deleted: its picture, its name, when it went, and
/// the two ways out.
private struct TrashRow<Picture: View>: View {
    var title: String
    var deleted: Double
    var onRestore: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var picture: Picture

    var body: some View {
        HStack(spacing: 12) {
            picture
                .frame(width: 56, height: 42)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("Deleted \(RelativeTime.lowercasedFirst(RelativeTime.text(ms: deleted)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore", action: onRestore)
                .buttonStyle(.bordered)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel(tr("Delete %@ forever", title))
        }
    }
}

/// Asked first, each: there is no coming back from any, and a row's bin
/// sits a finger's width from its Restore.
private struct TrashDialogs: ViewModifier {
    @Binding var deletingDesign: RecentDesign?
    @Binding var deletingUpload: TrashedUpload?
    @Binding var deletingFolder: DesignLibrary.HomeFolder?
    @Binding var emptying: Bool
    var emptyQuestion: String
    var onEmpty: () -> Void
    var onGoneForGood: ([String]) -> Void
    var onChanged: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(tr("Delete “%@” forever?", deletingDesign?.title ?? ""),
                                isPresented: Binding(get: { deletingDesign != nil },
                                                     set: { if !$0 { deletingDesign = nil } }),
                                titleVisibility: .visible) {
                Button("Delete forever", role: .destructive) {
                    if let entry = deletingDesign {
                        DesignLibrary.deleteTrashed(id: entry.id)
                        onGoneForGood([entry.id])
                    }
                    deletingDesign = nil
                    onChanged()
                }
                Button("Cancel", role: .cancel) { deletingDesign = nil }
            } message: {
                Text(DesignLibrary.cannotBeUndone)
            }
            .modifier(UploadAndFolderDialogs(deletingUpload: $deletingUpload, deletingFolder: $deletingFolder,
                                             emptying: $emptying, emptyQuestion: emptyQuestion, onEmpty: onEmpty,
                                             onGoneForGood: onGoneForGood, onChanged: onChanged))
    }
}

/// The rest of Recently deleted's questions: an upload, a folder, or a
/// whole list going for good.
private struct UploadAndFolderDialogs: ViewModifier {
    @Binding var deletingUpload: TrashedUpload?
    @Binding var deletingFolder: DesignLibrary.HomeFolder?
    @Binding var emptying: Bool
    var emptyQuestion: String
    var onEmpty: () -> Void
    var onGoneForGood: ([String]) -> Void
    var onChanged: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(tr("Delete “%@” forever?", deletingUpload?.title ?? ""),
                                isPresented: Binding(get: { deletingUpload != nil },
                                                     set: { if !$0 { deletingUpload = nil } }),
                                titleVisibility: .visible) {
                Button("Delete forever", role: .destructive) {
                    if let entry = deletingUpload { Uploads.deleteForever(entry.id, font: entry.font) }
                    deletingUpload = nil
                    onChanged()
                }
                Button("Cancel", role: .cancel) { deletingUpload = nil }
            } message: {
                Text(DesignLibrary.cannotBeUndone)
            }
            .confirmationDialog(tr("Delete “%@” forever?", DesignLibrary.leafName(deletingFolder?.name ?? "")),
                                isPresented: Binding(get: { deletingFolder != nil },
                                                     set: { if !$0 { deletingFolder = nil } }),
                                titleVisibility: .visible) {
                Button("Delete forever", role: .destructive) {
                    if let folder = deletingFolder {
                        DesignLibrary.deleteFolderForever(folder)
                        onGoneForGood(folder.designs)
                    }
                    deletingFolder = nil
                    onChanged()
                }
                Button("Cancel", role: .cancel) { deletingFolder = nil }
            } message: {
                Text(DesignLibrary.cannotBeUndone)
            }
            .confirmationDialog(emptyQuestion, isPresented: $emptying, titleVisibility: .visible) {
                Button("Delete forever", role: .destructive) { onEmpty() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(DesignLibrary.cannotBeUndone)
            }
    }
}

/// "Moved to Recently deleted", with Undo: for an upload deleted from
/// Home's Uploads or from Add, until Undo, its close button or the next
/// delete — as the Android twin's snackbar.
struct MovedToTrashToast: View {
    var onUndo: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Moved to Recently deleted")
                .font(.subheadline)
                .lineLimit(2)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 12)
        .onAppear {
            AccessibilityNotification.Announcement(tr("Moved to Recently deleted")).post()
        }
    }
}
