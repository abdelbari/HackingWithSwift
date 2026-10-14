// A PowerPoint file opened as a new design (PptxReader): the file mapped
// rather than read in — the deck is inflated part by part, so only one
// picture is ever held — read, and each picture it shows stored among the
// photos as a design file's are. Off the main thread; the text boxes are
// grown to fit this phone's faces back on it, as a design file's are, and
// the design goes on the shelf. The Android twin's PowerPoints.

import Foundation
import UniformTypeIdentifiers

enum PowerPoints {

    /// Posted once a deck is on the shelf, so Home shows its card.
    static let didImport = Notification.Name("CanviaPowerPointImported")

    /// A deck's type, for the file picker: the system's, or the one
    /// Canvia-Info.plist imports.
    static var contentType: UTType {
        UTType(PptxReader.typeIdentifier) ?? UTType(filenameExtension: PptxReader.fileExtension) ?? .data
    }

    enum DeckError: LocalizedError {
        case notADeck
        case tooBig
        case notSaved

        var errorDescription: String? {
            switch self {
            case .notADeck: return PptxReader.notADeck
            case .tooBig: return PptxReader.tooBig
            case .notSaved: return "Couldn't save the design"
            }
        }
    }

    /// A deck just made a design: the design, on the shelf already, and
    /// what came in and what did not.
    struct Opened: Identifiable {
        var design: Design
        var summary: String
        var id: String { design.id }
    }

    /// Whether the file at `url` is a deck: named .pptx, or a ZIP — which a
    /// design file never is — so a deck picked with "Open a Canvia design
    /// file", or handed over as bare bytes, still comes in as one.
    static func isDeck(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == PptxReader.fileExtension { return true }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return PptxReader.isZip((try? handle.read(upToCount: 4)) ?? Data())
    }

    /// The deck at `url` read, named by its file, its pictures stored; one
    /// whose bytes do not make a picture is left out of the design.
    static func read(at url: URL) throws -> PptxReader.Imported {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= PptxReader.maxFileBytes else { throw DeckError.tooBig }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let parts = PptxReader.Parts.of(data),
              let imported = PptxReader.read(parts: parts, title: PptxReader.title(fromFile: url.lastPathComponent)) else {
            throw DeckError.notADeck
        }
        var stored: [String: String] = [:]
        for (key, path) in imported.media {
            autoreleasepool {
                guard let bytes = parts.bytes(path), let prepared = ImageDownsampler.prepare(bytes),
                      let src = MediaStore.store(prepared) else { return }
                stored[key] = src
            }
        }
        return PptxReader.placed(imported, stored: stored)
    }

    /// The deck at `url` as a new design on the shelf, named as no other
    /// there (`taken`), its picture drawn for its card.
    @MainActor
    static func importFile(at url: URL, taken: [String]) async throws -> Opened {
        var imported = try await Task.detached(priority: .userInitiated) {
            try PowerPoints.read(at: url)
        }.value
        imported.design.title = Titles.unique(imported.design.title, taken: taken)
        imported.design.normalizeTextHeights()
        guard DesignLibrary.save(imported.design) else { throw DeckError.notSaved }
        DesignLibrary.writeThumbnail(for: imported.design)
        NotificationCenter.default.post(name: didImport, object: nil)
        return Opened(design: imported.design, summary: imported.summary)
    }
}
