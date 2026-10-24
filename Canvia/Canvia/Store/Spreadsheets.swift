// An Excel workbook opened in Canvia from another app — "Open in", as a
// deck is (PowerPoints) — as a new design: one square page with a column chart
// of the workbook's first sheet with rows (XlsxReader, DataGrid.fromRows),
// across the page's middle as Add puts a chart, named by its file and put
// on the shelf. The rows past what a chart takes in are left out, as Import
// data leaves them. The Android twin's share-in does the same.

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
    /// `title`: one 1080 square page with a column chart across its middle;
    /// nil when the rows draw nothing.
    static func design(rows: [[String]], title: String) -> Design? {
        var design = Design(title: title, width: 1080, height: 1080)
        design.pages = [Page()]
        let page = design.pages[0]
        let spec = ChartSpec(kind: DataGraphics.ChartKind.column.rawValue, data: DataGrid.chartText(rows))
        let frame = CGRect(x: 108, y: 216, width: 864, height: 648)
        let elements = DataGraphics.chart(spec, in: frame, palette: DataGraphics.palette(for: design, page: page),
                                          ink: DataGraphics.ink(for: page))
        guard !elements.isEmpty else { return nil }
        design.pages[0].elements = elements
        return design
    }

    /// The workbook at `url` as a new design on the shelf, named by its
    /// file as no other there is (`taken`), its picture drawn for its card.
    @MainActor
    static func importFile(at url: URL, taken: [String]) async throws -> Design {
        let read = await Task.detached(priority: .userInitiated) { DataGrid.read(dataAt: url) }.value
        let rows: [[String]]
        switch read {
        case .rows(let imported): rows = imported.cells
        case .sheets(let sheets): rows = DataGrid.fromRows(sheets.first?.cells ?? []).cells
        case .refused(let why): throw SheetError.refused(why)
        }
        let name = url.deletingPathExtension().lastPathComponent
        guard var design = Self.design(rows: rows, title: name.isEmpty ? tr("Chart") : name) else {
            throw SheetError.refused(tr("Nothing to draw: type some values, or values above zero."))
        }
        design.title = Titles.unique(design.title, taken: taken)
        design.normalizeTextHeights()
        guard DesignLibrary.save(design) else { throw SheetError.notSaved }
        DesignLibrary.writeThumbnail(for: design)
        return design
    }
}
