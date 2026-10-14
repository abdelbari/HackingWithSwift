// What Export remembers: the pages chosen for each design, for as long as
// the app is open, and — with "Remember these settings" on — the last
// export's format, size, quality, background and page choice, kept as JSON
// under @AppStorage "exportLast", the same keys as the Android twin's Prefs
// "export_last". The pages chosen by id are a design's own and never stored.

import Foundation

enum ExportChoices {

    /// The pages ticked in Choose…, by design id, for this session.
    static var chosenByDesign: [String: [String]] = [:]

    /// The pages ticked the first time: every page shown — hidden ones
    /// unticked.
    static func defaultChosen(_ design: Design) -> [String] {
        design.visiblePageIndices.map { design.pages[$0].id }
    }

    /// The pages ticked for `design`: as left this session, without any
    /// page since deleted, in the design's order; else the default.
    static func chosen(for design: Design) -> [String] {
        guard let kept = chosenByDesign[design.id] else { return defaultChosen(design) }
        let picked = Set(kept)
        return design.pages.map(\.id).filter { picked.contains($0) }
    }

    static func remember(_ ids: [String], for design: Design) {
        chosenByDesign[design.id] = ids
    }

    /// One page ticked or unticked, the rest kept in the design's order.
    static func toggled(_ ids: [String], _ id: String, in design: Design) -> [String] {
        var picked = Set(ids)
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        return design.pages.map(\.id).filter { picked.contains($0) }
    }

    /// The range as an export takes it: a one-page design has no Pages row
    /// to change it, so it is that page — even hidden, or with nothing
    /// ticked — as the Android twin's ExportPlan.pagesFor has it.
    static func exportRange(_ range: DesignExporter.PageRange, in design: Design) -> DesignExporter.PageRange {
        design.pages.count == 1 ? .current : range
    }

    /// "3 of 8 pages", as the rows say a choice.
    static func countText(_ chosen: Int, of total: Int) -> String {
        "\(chosen) of \(total) \(total == 1 ? "page" : "pages")"
    }

    // MARK: in the background — the Android twin's ExportPlan words

    /// Asked when the sheet is closed with an export running; Keep is the
    /// default.
    static let keepQuestion = "Keep exporting in the background?"
    static let keep = "Keep"
    static let stop = "Stop"

    /// The pill while an export runs: "Rendering the video 42%".
    static func pillText(label: String, fraction: Double) -> String {
        "\(label) \(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// "1 more waiting", under the progress while others wait their turn.
    static func waitingText(_ count: Int) -> String {
        "\(count) more waiting"
    }

    /// The notifications: done, with Share and Open; failed; paused.
    static let readyTitle = "Your export is ready"
    static let failedTitle = "Export failed"
    static let pausedTitle = "Export paused"
    static let paused = "Paused — return to Canvia to finish"
    static let shareAction = "Share"
    static let openAction = "Open"

    /// "Export failed: <why>", in the sheet or the pill.
    static func failedText(_ reason: String) -> String {
        "Export failed: \(reason)"
    }

    /// Said when a video's music could not be mixed in.
    static let musicLost = "Couldn't add the music, so it has none."
}

/// The last export, as "Remember these settings" keeps it:
/// {"format":"png","scale":2,"longEdge":null,"jpegQuality":0.85,
///  "transparent":false,"pages":"all"}.
struct ExportLast: Codable, Equatable {
    /// "png" | "jpg" | "pdf" | "print" | "svg" | "pptx" | "mp4" | "gif".
    var format: String
    var scale: Double
    /// The long edge typed, in pixels; nil when the scale applies.
    var longEdge: Int?
    var jpegQuality: Double
    var transparent: Bool
    /// "all" | "current" | "chosen".
    var pages: String

    static let key = "exportLast"
    static let formats: Set<String> = ["png", "jpg", "pdf", "print", "svg", "pptx", "mp4", "gif"]
    static let pageChoices: Set<String> = ["all", "current", "chosen"]

    private enum CodingKeys: String, CodingKey {
        case format, scale, longEdge, jpegQuality, transparent, pages
    }

    init(format: String, scale: Double, longEdge: Int?, jpegQuality: Double, transparent: Bool, pages: String) {
        self.format = format
        self.scale = scale
        self.longEdge = longEdge
        self.jpegQuality = jpegQuality
        self.transparent = transparent
        self.pages = pages
    }

    /// Lenient, as a setting from another build may be: what does not read
    /// takes the sheet's own default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let f = (try? c.decode(String.self, forKey: .format)) ?? "png"
        format = Self.formats.contains(f) ? f : "png"
        scale = min(max((try? c.decode(Double.self, forKey: .scale)) ?? 2, 1), 3)
        longEdge = (try? c.decode(Int.self, forKey: .longEdge)).flatMap { $0 >= 16 ? $0 : nil }
        jpegQuality = min(max((try? c.decode(Double.self, forKey: .jpegQuality)) ?? 0.92, 0.3), 1)
        transparent = (try? c.decode(Bool.self, forKey: .transparent)) ?? false
        let p = (try? c.decode(String.self, forKey: .pages)) ?? "all"
        pages = Self.pageChoices.contains(p) ? p : "all"
    }

    /// Every key written, the long edge as null when there is none, in the
    /// order the Android twin writes them.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(scale, forKey: .scale)
        if let longEdge { try c.encode(longEdge, forKey: .longEdge) } else { try c.encodeNil(forKey: .longEdge) }
        try c.encode(jpegQuality, forKey: .jpegQuality)
        try c.encode(transparent, forKey: .transparent)
        try c.encode(pages, forKey: .pages)
    }

    /// As stored; "" when it will not encode.
    var json: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The stored text read back; nil for none, or for text that is not
    /// one.
    static func read(_ text: String) -> ExportLast? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ExportLast.self, from: data)
    }
}
