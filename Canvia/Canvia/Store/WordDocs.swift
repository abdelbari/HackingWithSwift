// A Word document opened as a new Doc (DocxReader): read off the main
// thread, each picture it shows stored among the photos as a deck's are,
// and the Doc put on the shelf under its file's name. And Turn into a Doc:
// a design's words as a new Doc beside it (Docs.fromDesign). The Android
// twin's WordDocs.

import Foundation
import UniformTypeIdentifiers

enum WordDocs {

    /// A Word document's type, for the file picker: the system's, or the
    /// one Canvia-Info.plist imports.
    static var contentType: UTType { DocxReader.contentType }

    enum WordError: LocalizedError {
        case notADocument
        case tooBig
        case notSaved

        var errorDescription: String? {
            switch self {
            case .notADocument: return DocxReader.notADocument
            case .tooBig: return DocxReader.tooBig
            case .notSaved: return tr("Couldn't save the design")
            }
        }
    }

    /// Whether the file at `url` is a Word document — which is a ZIP as a
    /// deck is, so it is asked before a deck: called .docx, or, for one
    /// that arrived as any file (picked as a design file, or sent with a
    /// bare name), a ZIP holding word/document.xml, as on Android.
    static func isWordDocument(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == DocxReader.fileExtension { return true }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        let head = (try? handle.read(upToCount: 4)) ?? Data()
        try? handle.close()
        guard PptxReader.isZip(head),
              let zip = try? ZipStore.Reader(url: url, inflating: true) else { return false }
        return zip.entries["word/document.xml"] != nil
    }

    /// The document at `url` read as a Doc named by its file, its pictures
    /// stored; one whose bytes do not make a picture is left out.
    static func read(at url: URL) throws -> Design {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= DocxReader.maxFileBytes else { throw WordError.tooBig }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let parts = PptxReader.Parts.of(data),
              let imported = DocxReader.read(parts: parts, title: DocxReader.title(fromFile: url.lastPathComponent)) else {
            throw WordError.notADocument
        }
        var stored: [String: String] = [:]
        for (key, path) in imported.media {
            autoreleasepool {
                guard let bytes = parts.bytes(path), let prepared = ImageDownsampler.prepare(bytes),
                      let src = MediaStore.store(prepared) else { return }
                stored[key] = src
            }
        }
        return DocxReader.placed(imported, stored: stored).design
    }

    /// The document at `url` as a new Doc on the shelf, named by its file
    /// as it is, as the Android twin names it; its picture drawn for its
    /// card.
    @MainActor
    static func importFile(at url: URL) async throws -> Design {
        var design = try await Task.detached(priority: .userInitiated) { try WordDocs.read(at: url) }.value
        design.titleAuto = false
        guard DesignLibrary.save(design) else { throw WordError.notSaved }
        DesignLibrary.writeThumbnail(for: design)
        return design
    }

    /// Turn into a Doc: a new Doc of `design`'s words — its pages' notes
    /// too with `notes` — saved on the shelf in its folder, named
    /// "<title> (Doc)" as it is, as the Android twin names it; `design` is
    /// left as it is. Nil when it could not be saved.
    @MainActor
    static func turnIntoDoc(_ design: Design, notes: Bool) -> Design? {
        var doc = Docs.fromDesign(design, notes: notes)
        doc.titleAuto = false
        guard DesignLibrary.save(doc) else { return nil }
        DesignLibrary.writeThumbnail(for: doc)
        return doc
    }
}
