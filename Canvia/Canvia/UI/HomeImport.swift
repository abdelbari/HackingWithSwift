// Import, on Home's ⋯ and at the top of the New design sheet: a photo or a
// clip from the library, a PDF, a PowerPoint, a Word document (a new Doc,
// WordImport), or a Canvia design file. A
// photo, a clip or a PDF lands as something shared from another app does —
// copied into the inbox with its manifest (SharedInbox) while the picker's
// grant lasts — and the "New design from shared" sheet makes a design of
// it: a page for each, a PDF's pages as pages, and what could not be
// opened said. The Android twin's Home import, row for row.

import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The rows of Import, in order.
enum ImportChoice: String, CaseIterable, Identifiable {
    case media, pdf, powerPoint, word, designFile

    var id: String { rawValue }

    /// The group's heading.
    static var groupTitle: String { tr("Import") }

    var title: String {
        switch self {
        case .media: return tr("Photo or video…")
        case .pdf: return tr("PDF…")
        case .powerPoint: return tr("PowerPoint…")
        case .word: return tr("Word document")
        case .designFile: return tr("Canvia design file…")
        }
    }

    var systemImage: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .pdf: return "doc.richtext"
        case .powerPoint: return "rectangle.on.rectangle"
        case .word: return "doc.text"
        case .designFile: return "square.and.arrow.down"
        }
    }
}

/// A photo or a clip from the photo library as a file of its own: copied
/// out of what the picker hands over before that goes, keeping its type's
/// extension, which is what the inbox reads its kind from.
struct PickedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try PickedFile(copying: received.file, type: .movie)
        }
        FileRepresentation(importedContentType: .image) { received in
            try PickedFile(copying: received.file, type: .image)
        }
    }

    init(copying file: URL, type: UTType) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("picked", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = file.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "bin") : file.pathExtension
        let target = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.copyItem(at: file, to: target)
        url = target
    }
}

extension View {
    /// Import's photo and PDF pickers on this view: what is picked is
    /// landed in the inbox and handed to `onLanded`; with nothing landed,
    /// what could not be opened goes to `onFailed`.
    func importPickers(media: Binding<Bool>, pdf: Binding<Bool>, onLanded: @escaping (SharedInbox.Box) -> Void,
                       onFailed: @escaping (String) -> Void) -> some View {
        modifier(ImportPickers(pickingMedia: media, pickingPDF: pdf, onLanded: onLanded, onFailed: onFailed))
    }
}

private struct ImportPickers: ViewModifier {
    @Binding var pickingMedia: Bool
    @Binding var pickingPDF: Bool
    var onLanded: (SharedInbox.Box) -> Void
    var onFailed: (String) -> Void
    @State private var picked: [PhotosPickerItem] = []
    /// Copying in, under the "Opening the design…" card.
    @State private var landing = false

    func body(content: Content) -> some View {
        content
            // Photos and clips together, as many as a share brings in.
            .photosPicker(isPresented: $pickingMedia, selection: $picked,
                          maxSelectionCount: SharedInbox.maxItems, matching: .any(of: [.images, .videos]))
            .onChange(of: picked) { _, items in landPicked(items) }
            // On a view of its own, so it does not share one with another
            // file picker.
            .background {
                Color.clear.fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf]) { result in
                    if case .success(let url) = result { landFiles([url]) }
                }
            }
            .overlay { if landing { OpeningDesignCard() } }
    }

    /// Each photo or clip copied out in turn, then landed together.
    private func landPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        picked = []
        landing = true
        Task { @MainActor in
            var files: [URL] = []
            for item in items.prefix(SharedInbox.maxItems) {
                guard let file = try? await item.loadTransferable(type: PickedFile.self) else { continue }
                files.append(file.url)
            }
            let copied = files
            let box = await Task.detached(priority: .userInitiated) { SharedInbox.land(copied) }.value
            for url in copied { try? FileManager.default.removeItem(at: url) }
            landing = false
            finish(box, asked: min(items.count, SharedInbox.maxItems))
        }
    }

    /// The PDF, copied in under its security scope (SharedInbox.land).
    private func landFiles(_ urls: [URL]) {
        landing = true
        Task { @MainActor in
            let box = await Task.detached(priority: .userInitiated) { SharedInbox.land(urls) }.value
            landing = false
            finish(box, asked: urls.count)
        }
    }

    /// Those that would not copy out counted among what could not be
    /// opened, as a share counts them.
    private func finish(_ box: SharedInbox.Box?, asked: Int) {
        guard var box else {
            onFailed(SharedInbox.failureText(failed: asked, total: asked) ?? tr("Couldn't open that file"))
            return
        }
        box.asked = max(box.asked, asked)
        onLanded(box)
    }
}
