// An Excel workbook opened in Canvia from another app — "Open in", as a
// deck is (PowerPoints) — as a new design: one square page with a column chart
// of a sheet with rows (XlsxReader, DataGrid.fromRows) — the one there is,
// or the one chosen when there are several — across the page's middle as
// Add puts a chart, its legend shown, or a table of the rows when they hold
// no numbers to draw; named by its file and put on the shelf. The rows past
// what a chart takes in are left out, as Import data leaves them. The
// Android twin's share-in does the same.

import Foundation
import UniformTypeIdentifiers

enum Spreadsheets {

    static let typeIdentifier = "org.openxmlformats.spreadsheetml.sheet"
    static let fileExtension = "xlsx"

    /// A workbook's type, for the file picker: the system's, or the one
    /// Canvia-Info.plist imports.
    static var contentType: UTType {
        UTType(typeIdentifier) ?? UTType(filenameExtension: fileExtension) ?? .data
    }

    /// Whether the file at `url` is named as a workbook.
    static func isSpreadsheet(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == fileExtension
    }

    enum SheetError: LocalizedError {
        case refused(String)
        case notSaved

        var errorDescription: String? {
            switch self {
            case .refused(let why): return why
            case .notSaved: return tr("Couldn't save the design")
            }
        }
    }

    /// A new design of `rows` — a sheet's, as the grid takes them — titled
    /// `title`: one 1080 square page with a column chart across its middle,
    /// its legend shown, in the brand kit's colours (the new design having
    /// none of its own), or a table of the rows when they hold no numbers to
    /// draw; nil when there are no rows.
    static func design(rows: [[String]], title: String) -> Design? {
        var design = Design(title: title, width: 1080, height: 1080)
        design.pages = [Page()]
        let page = design.pages[0]
        var spec = ChartSpec(kind: DataGraphics.ChartKind.column.rawValue, data: DataGrid.chartText(rows))
        spec.legend = true
        let frame = CGRect(x: 108, y: 216, width: 864, height: 648)
        let palette = DataGraphics.palette(for: design, page: page, brand: BrandKit.load())
        var elements = DataGraphics.chart(spec, in: frame, palette: palette, ink: DataGraphics.ink(for: page))
        if elements.isEmpty, let accent = palette.first {
            elements = DataGraphics.table(rows, in: frame, accent: accent)
        }
        guard !elements.isEmpty else { return nil }
        design.pages[0].elements = elements
        return design
    }

    /// "Sales" for "Sales.xlsx"; an untitled design's name for none, as
    /// Android's XlsxReader.titleFrom names it.
    static func title(fromFileName fileName: String) -> String {
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = "." + fileExtension
        let bare = name.lowercased().hasSuffix(suffix)
            ? String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines) : name
        return bare.isEmpty ? tr("Untitled design") : bare
    }

    /// What the workbook at `url` holds, read away from the main thread:
    /// its one sheet's rows, its sheets with rows to choose one from, or
    /// why not.
    static func read(at url: URL) async -> DataGrid.DataRead {
        await Task.detached(priority: .userInitiated) { DataGrid.read(dataAt: url) }.value
    }

    /// `rows` — the sheet's, or the chosen one's — as a new design on the
    /// shelf, titled `title` as no other there is (`taken`), its picture
    /// drawn for its card.
    @MainActor
    static func importRows(_ rows: [[String]], title: String, taken: [String]) throws -> Design {
        guard var design = Self.design(rows: rows, title: title) else {
            throw SheetError.refused(tr("No rows to import in that file"))
        }
        design.title = Titles.unique(design.title, taken: taken)
        design.normalizeTextHeights()
        guard DesignLibrary.save(design) else { throw SheetError.notSaved }
        DesignLibrary.writeThumbnail(for: design)
        return design
    }
}
