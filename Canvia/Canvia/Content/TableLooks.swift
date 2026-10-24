// A table's look beyond its cells' own fills: which of its lines show
// (`borders` on the table key, and each cell rectangle's derived `sides`),
// where its words sit in their cells ("vAlign" on each cell's text), and
// the designs from the shared tables.json (Tools/generate_tables.py) that
// Add > Table inserts and the Table sheet's Design row restyles with. The
// Android twin's Tables and TableDesigns, rule for rule, held to the same
// fixtures (table-sides.json, table-restyle.json).

import Foundation

/// The table designs Add > Table and the Table sheet's Design row offer —
/// the shared tables.json, bundled as the Android twin bundles it. A design
/// is applied by Tables.restyled.
enum TableDesigns {

    /// One look, as the file has it. Colours are "#rrggbb", or "accent" /
    /// "accent2", which `resolve` turns into the brand's or the design's
    /// own; `pad` is the cells' inset as a share of their type
    /// (DataGraphics.tablePad); `borders` one of Tables.borderModes.
    struct TableDesign: Equatable, Identifiable {
        var id: String
        var name: String
        var headerFill: String
        var headerInk: String
        var headerWeight: Int
        var bodyFill: String
        var bandFill: String?
        var ink: String
        var border: String
        var borderWidth: Double
        var borders: String
        var radius: Double
        var pad: Double
        var font: String?

        /// Its name in the reader's language.
        var label: String { tr(name) }
    }

    /// The colour tokens a design may use in place of a colour.
    static let accent = "accent"
    static let accent2 = "accent2"

    /// Read once, on first use.
    static let all: [TableDesign] = {
        guard let url = Bundle.main.url(forResource: "tables", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("tables.json missing")
            return []
        }
        return designs(from: data)
    }()

    static func design(_ id: String?) -> TableDesign? {
        all.first { $0.id == id }
    }

    /// The designs in `data`, in its order; one missing a field passed over.
    /// A number is read only as a number and words only as words, as the
    /// Android twin reads them.
    static func designs(from data: Data) -> [TableDesign] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return list.compactMap { ($0 as? [String: Any]).flatMap(designOf) }
    }

    private static func designOf(_ o: [String: Any]) -> TableDesign? {
        func str(_ key: String) -> String? { o[key] as? String }
        func num(_ key: String) -> Double? {
            guard let n = o[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            return n.doubleValue.isFinite ? n.doubleValue : nil
        }
        guard let id = str("id"), !id.isEmpty, let name = str("name"), let headerFill = str("headerFill"),
              let headerInk = str("headerInk"), let headerWeight = num("headerWeight"), let bodyFill = str("bodyFill"),
              let ink = str("ink"), let border = str("border"), let borderWidth = num("borderWidth") else { return nil }
        let borders = str("borders").flatMap { Tables.borderModes.contains($0) ? $0 : nil } ?? "all"
        return TableDesign(id: id, name: name, headerFill: headerFill, headerInk: headerInk,
                           headerWeight: Int(headerWeight), bodyFill: bodyFill, bandFill: str("bandFill"), ink: ink,
                           border: border, borderWidth: borderWidth, borders: borders, radius: num("radius") ?? 0,
                           pad: num("pad") ?? DataGraphics.tablePad, font: str("font"))
    }

    /// `colour` with the tokens resolved: `accent` for "accent", `accent2`
    /// for "accent2"; a colour as it is.
    static func resolve(_ colour: String, accent: String, accent2: String) -> String {
        switch colour {
        case Self.accent: return accent
        case Self.accent2: return accent2
        default: return colour
        }
    }

    /// The colours "accent" and "accent2" stand for: the brand kit's first
    /// two (`brand`), else the design's own palette's first two
    /// (DataGraphics.palette); a list of one gives it for both.
    static func accents(brand: [String], palette: [String]) -> (String, String) {
        let from = !brand.isEmpty ? brand : (!palette.isEmpty ? palette : [DataGraphics.tableInk])
        return (from[0], from.count > 1 ? from[1] : from[0])
    }

    /// The 3x3 sample the gallery draws each design from.
    static var sample: [[String]] {
        [[tr("Item"), tr("Qty"), tr("Price")], [tr("Coffee"), "2", "3.50"], [tr("Bagel"), "1", "2.25"]]
    }
}

/// A table's lines, its words' place in their cells and its design, as
/// pure functions over a page's elements — the Android twin's Tables of the
/// same names.
enum Tables {

    // MARK: border sides

    /// The Borders control's six choices, in the order its chips show them,
    /// kept as the table key's `borders` (none for "all").
    static let borderModes = ["all", "outer", "inner", "horizontal", "vertical", "none"]

    /// The sides `cell` strokes in a table of `rows` rows and `cols` columns
    /// with border mode `mode`: "all" every side, "outer" only the sides on
    /// the table's outside edge, "inner" only those inside it, "horizontal"
    /// the top and bottom of every cell (the outside's among them),
    /// "vertical" the left and right, "none" none. A merged cell's edge is
    /// outside when its span reaches the table's last row or column. The
    /// letters come in "tlbr" order; an unknown mode is "all". The same rule
    /// on both phones (table-sides.json).
    static func sides(_ cell: TableCell, rows: Int, cols: Int, mode: String) -> String {
        let outside: [Character: Bool] = [
            "t": cell.row == 0,
            "l": cell.col == 0,
            "b": cell.row + cell.rowSpan - 1 >= rows - 1,
            "r": cell.col + cell.colSpan - 1 >= cols - 1,
        ]
        return String("tlbr".filter { side in
            switch mode {
            case "outer": return outside[side] == true
            case "inner": return outside[side] != true
            case "horizontal": return side == "t" || side == "b"
            case "vertical": return side == "l" || side == "r"
            case "none": return false
            default: return true
            }
        })
    }

    /// The border mode `cells` (a table's members) keep: the first cell's
    /// `borders`, else "all".
    static func borderMode(of cells: [Element]) -> String {
        cells.lazy.compactMap { $0.table?.borders }.first ?? "all"
    }

    /// Table `id`'s border mode.
    static func borderMode(_ elements: [Element], id: String) -> String {
        borderMode(of: DataGraphics.tableMembers(elements, id: id))
    }

    /// The lines a rectangle with `sides` strokes, each x1, y1, x2, y2 in
    /// its own box from 0, 0 — what the canvas and SVG draw in place of its
    /// outline; nil when it strokes the whole outline.
    static func sideLines(_ el: Element) -> [[Double]]? {
        guard let sides = el.sides else { return nil }
        return sides.map { side -> [Double] in
            switch side {
            case "t": return [0, 0, el.w, 0]
            case "l": return [0, 0, 0, el.h]
            case "b": return [0, el.h, el.w, el.h]
            default: return [el.w, 0, el.w, el.h]
            }
        }
    }

    /// `cells` (a table's members) with each rectangle's `sides` set from
    /// the table's border mode — taken off when all four show. What
    /// DataGraphics.relayout ends with, so a row or column added, deleted,
    /// merged or moved draws its lines again.
    static func withSides(_ cells: [Element]) -> [Element] {
        let places = cells.compactMap(\.table)
        guard !places.isEmpty else { return cells }
        let rows = (places.map { $0.row + $0.rowSpan }.max() ?? 0)
        let cols = (places.map { $0.col + $0.colSpan }.max() ?? 0)
        let mode = borderMode(of: cells)
        return cells.map { el in
            guard el.type == .shape, let cell = el.table else { return el }
            let found = sides(cell, rows: rows, cols: cols, mode: mode)
            let kept: String? = found == "tlbr" ? nil : found
            guard el.sides != kept else { return el }
            var out = el
            out.sides = kept
            return out
        }
    }

    /// Table `id` with border mode `mode` kept on every cell ("all" taking
    /// the key off) and its rectangles' sides set again; nil for an unknown
    /// mode or no change.
    static func withBorderMode(_ elements: [Element], id: String, mode: String) -> [Element]? {
        guard borderModes.contains(mode) else { return nil }
        let set = elements.map { el -> Element in
            guard var cell = el.table, cell.id == id else { return el }
            cell.borders = mode == "all" ? nil : mode
            var out = el
            out.table = cell
            return out
        }
        let sided = Dictionary(withSides(DataGraphics.tableMembers(set, id: id)).map { ($0.id, $0) },
                               uniquingKeysWith: { first, _ in first })
        let out = set.map { sided[$0.id] ?? $0 }
        return out == elements ? nil : out
    }

    // MARK: alignment in cells

    /// Where a cell's words sit: "top", "middle" or "bottom" — nil, or
    /// anything else, is the top.
    static func vAlign(of el: Element) -> String {
        el.vAlign == "middle" || el.vAlign == "bottom" ? el.vAlign ?? "top" : "top"
    }

    /// How far down a cell's words sit below its inset top, in a cell
    /// `room` tall inside its inset: none at the top, half the room they
    /// leave in the middle, all of it at the bottom, never less than none.
    static func cellSlack(_ text: Element, room: Double) -> Double {
        let slack = max(0, room - text.h)
        switch vAlign(of: text) {
        case "middle": return slack / 2
        case "bottom": return slack
        default: return 0
        }
    }

    /// Where the words of table `id`'s `cells` ([row, col]; every cell for
    /// nil) sit in their cells, when they share one; nil when they differ.
    static func cellAlignment(_ elements: [Element], id: String, cells: Set<[Int]>?) -> String? {
        let found = Set(DataGraphics.tableMembers(elements, id: id).filter { el in
            guard el.type == .text, let cell = el.table else { return false }
            return cells?.contains([cell.row, cell.col]) ?? true
        }.map { vAlign(of: $0) })
        return found.count == 1 ? found.first : nil
    }

    /// Table `id`'s `cells` — every cell, for nil — with their words set
    /// `align` in the cell ("vAlign" on each text, none for top), and the
    /// table laid out again; nil when nothing changed.
    static func aligned(_ elements: [Element], id: String, cells: Set<[Int]>?, align: String,
                        heightFor: (Element) -> Double) -> [Element]? {
        let kept: String? = align == "middle" || align == "bottom" ? align : nil
        let set = elements.map { el -> Element in
            guard el.type == .text, let cell = el.table, cell.id == id,
                  cells?.contains([cell.row, cell.col]) ?? true, el.vAlign != kept else { return el }
            var out = el
            out.vAlign = kept
            return out
        }
        guard set != elements else { return nil }
        return DataGraphics.relaidTable(set, id: id, heightFor: heightFor)
    }

    // MARK: designs

    /// The design `cells` (a table's members) keep, or nil.
    static func designOf(_ cells: [Element]) -> String? {
        cells.lazy.compactMap { $0.table?.design }.first
    }

    /// A colour as the design writes it on the cells: lower case, a short
    /// "#rgb" spelled out; its alpha, when it has one, kept, so a hairline
    /// stays faint. Anything else as it is.
    static func normalised(_ hex: String) -> String {
        var s = hex.trimmingCharacters(in: .whitespaces).lowercased()
        guard s.hasPrefix("#") else { return hex }
        s.removeFirst()
        guard s.allSatisfy(\.isHexDigit) else { return hex }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        return s.count == 6 || s.count == 8 ? "#" + s : hex
    }

    /// `cells` — a table's members — in `design`'s look, its "accent" and
    /// "accent2" colours `accent` and `accent2`: row 0 the header (filled
    /// headerFill, its words headerInk at headerWeight), the rows below it
    /// bodyFill, or bandFill in even rows when the design bands them (as
    /// tableBodyFill bands), their words ink at 400; every rectangle
    /// stroked border, borderWidth wide, with the design's corner radius;
    /// the words in its font when it names one. The cell's key keeps the
    /// design's id, its borders (none for "all"), its bands (only when the
    /// body is white, as alternating rows stripe with white) and its inset
    /// (pad times the first cell's type, none when it is the default).
    /// Words, spans, column widths and row heights are kept; the caller
    /// lays the table out again.
    static func restyled(_ cells: [Element], design: TableDesigns.TableDesign, accent: String,
                         accent2: String) -> [Element] {
        func c(_ colour: String) -> String { normalised(TableDesigns.resolve(colour, accent: accent, accent2: accent2)) }
        let first = cells.filter { $0.type == .text && $0.table != nil }
            .min { a, b in (a.table?.row ?? 0, a.table?.col ?? 0) < (b.table?.row ?? 0, b.table?.col ?? 0) }
        let size = first?.fontSize ?? 10
        let pad: Double? = abs(design.pad - DataGraphics.tablePad) > 1e-9 ? design.pad * size : nil
        let body = c(design.bodyFill)
        let band = design.bandFill.map(c)
        let bands: String? = body == "#ffffff" ? band : nil
        let styled = cells.map { el -> Element in
            guard var cell = el.table else { return el }
            cell.design = design.id
            cell.borders = design.borders == "all" ? nil : design.borders
            cell.bands = bands
            cell.pad = pad
            var out = el
            out.table = cell
            let header = cell.row == 0
            switch el.type {
            case .shape:
                let fill = header ? c(design.headerFill) : (band != nil && cell.row % 2 == 0 ? band ?? body : body)
                out.fill = .solid(fill)
                out.stroke = c(design.border)
                out.strokeWidth = min(max(design.borderWidth, 0), DataGraphics.tableBorderMax)
                out.radius = design.radius
            case .text:
                out.color = header ? c(design.headerInk) : c(design.ink)
                out.fontWeight = header ? design.headerWeight : 400
                if let font = design.font { out.setFontFamily(font) }
            default:
                break
            }
            return out
        }
        return withSides(styled)
    }

    /// Table `id` in `design` (restyled) and laid out again; nil when
    /// nothing changed.
    static func withDesign(_ elements: [Element], id: String, design: TableDesigns.TableDesign, accent: String,
                           accent2: String, heightFor: (Element) -> Double) -> [Element]? {
        let styled = restyled(DataGraphics.tableMembers(elements, id: id), design: design, accent: accent, accent2: accent2)
        let byId = Dictionary(styled.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let out = DataGraphics.relaidTable(elements.map { byId[$0.id] ?? $0 }, id: id, heightFor: heightFor)
        return out == elements ? nil : out
    }

    /// Every table among `elements` that keeps a design given it again in
    /// `accent` and `accent2` — what a theme or a brand applied does, so the
    /// table's header follows the new colours. A table with a locked cell
    /// stays as it is.
    static func redesigned(_ elements: [Element], accent: String, accent2: String,
                           heightFor: (Element) -> Double) -> [Element] {
        var out = elements
        var seen = Set<String>()
        for id in elements.compactMap({ $0.table?.id }) where seen.insert(id).inserted {
            let members = DataGraphics.tableMembers(out, id: id)
            guard !members.contains(where: \.locked), let design = TableDesigns.design(designOf(members)) else { continue }
            out = withDesign(out, id: id, design: design, accent: accent, accent2: accent2, heightFor: heightFor) ?? out
        }
        return out
    }
}
