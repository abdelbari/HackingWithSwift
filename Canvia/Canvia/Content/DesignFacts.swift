// What the Details sheet says about a design — Canva's File ▸ Design
// details — read from the design alone: its type and size, in its unit and
// in pixels, its pages with the hidden ones apart, how long it plays, when
// it was made and last edited, the fonts it sets words in with their
// weights, and the photos, clips and songs of its own it uses. The sheet
// adds what only the phone knows: the room it takes here, the brand kit it
// follows (brandKit) and its last export (lastExports). Read only: nothing
// is written into the design. The Android twin's DesignFacts, rule for
// rule, with the same shared fixture (Tests/Fixtures/design-facts.json).

import Foundation

struct DesignFacts: Equatable {
    /// Its type's id in the size catalogue (DesignLibrary.typeOf), or nil
    /// for a size of its own.
    var typeId: String?
    /// Its type's name, or "Custom size".
    var typeName: String
    /// "210 × 297 mm" in the design's unit, or "1080 × 1080 px".
    var size: String
    /// "2480 × 3508 px" for a design measured on paper; nil for one in
    /// pixels, whose `size` says it already.
    var pixels: String?
    /// The pages shown, and those hidden from Present and export.
    var pages: Int
    var hiddenPages: Int
    /// How long it plays, in seconds — its timeline's length — for a design
    /// that moves or sounds (ExportSuggestion's "mp4"); nil for a still.
    var seconds: Double?
    /// Epoch milliseconds.
    var createdAt: Double
    var updatedAt: Double
    var fonts: [Font]
    /// The photos, clips and songs of its own it uses, each once.
    var photos: Int
    var videos: Int
    var audio: Int

    /// A font the design sets words in: its stored key resolved
    /// (FontLibrary.resolve), its name, the weights its words use, lightest
    /// first, and whether it is a font of your own this phone does not
    /// have — "Not on this phone".
    struct Font: Equatable {
        var key: String
        var name: String
        var weights: [Int]
        var missing: Bool
    }

    /// A design's last export on this phone: when, in epoch milliseconds,
    /// and its type — "png", "pdf", "mp4", "print"… — and, when it failed,
    /// why (ExportFailure.Failure, kept under "failure").
    struct LastExport: Equatable {
        var at: Int64
        var type: String
        var failure: ExportFailure.Failure? = nil
    }

    // MARK: the last export

    /// Where each design's last export is kept on this phone, by id, as the
    /// Android twin keeps it: `{"<designId>": {"at": ms, "type": "png"}}`,
    /// one that failed with `"failure": {"kind": "noSpace", "designIds":
    /// ["<designId>"]}` after its type.
    static let lastExportsKey = "lastExports"

    /// The most designs whose last export is kept: the oldest go first.
    static let maxLastExports = 200

    /// The exports kept, from the preference's JSON: an entry whose "at" is
    /// not a number or whose "type" is not words is passed over.
    static func decodeLastExports(_ text: String?) -> [String: LastExport] {
        guard let data = text?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var out: [String: LastExport] = [:]
        for (id, value) in object {
            guard let entry = value as? [String: Any], let at = entry["at"] as? NSNumber,
                  CFGetTypeID(at) != CFBooleanGetTypeID(), let type = entry["type"] as? String else { continue }
            out[id] = LastExport(at: at.int64Value, type: type, failure: keptFailure(entry["failure"]))
        }
        return out
    }

    /// A kept failure, read leniently as ExportFailure.Failure reads it: a
    /// kind unknown is other, ids not words are left out; none without a
    /// kind in words.
    private static func keptFailure(_ value: Any?) -> ExportFailure.Failure? {
        guard let object = value as? [String: Any], let kind = object["kind"] as? String else { return nil }
        let ids = (object["designIds"] as? [Any])?.compactMap { $0 as? String } ?? []
        return ExportFailure.Failure(kind: ExportFailure.Reason.of(kind), designIds: ids)
    }

    /// The exports as the preference keeps them: ids in order, each "at"
    /// before its "type", as the Android twin writes them.
    static func encodeLastExports(_ exports: [String: LastExport]) -> String {
        let entries = exports.keys.sorted().map { id -> String in
            let e = exports[id]!
            return "\(quoted(id)):{\"at\":\(e.at),\"type\":\(quoted(e.type))\(failureField(e.failure))}"
        }
        return "{" + entries.joined(separator: ",") + "}"
    }

    /// `,"failure":{"kind":"noSpace","designIds":["d1"]}`, or nothing.
    private static func failureField(_ failure: ExportFailure.Failure?) -> String {
        guard let failure else { return "" }
        let ids = failure.designIds.map { quoted($0) }.joined(separator: ",")
        return ",\"failure\":{\"kind\":\(quoted(failure.kind.rawValue)),\"designIds\":[\(ids)]}"
    }

    /// `text` as a JSON string.
    private static func quoted(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    /// `exports` with `export` as `designId`'s, keeping the latest
    /// maxLastExports.
    static func exported(_ exports: [String: LastExport], designId: String, _ export: LastExport) -> [String: LastExport] {
        var all = exports
        all[designId] = export
        let kept = all.sorted { $0.value.at > $1.value.at }.prefix(maxLastExports)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    /// `exports` with design `designId`'s export at `at` failed as
    /// `failure`: kept as its last export, with the type it had before
    /// (none: ""), as the Android twin keeps it. A later export that works
    /// replaces it.
    static func failedExport(_ exports: [String: LastExport], designId: String,
                             failure: ExportFailure.Failure, at: Int64) -> [String: LastExport] {
        exported(exports, designId: designId, LastExport(at: at, type: exports[designId]?.type ?? "", failure: failure))
    }

    /// The type an export is said as: "PNG", "MP4", "Print".
    static func exportType(_ type: String) -> String {
        type == "print" ? tr("Print") : type.uppercased()
    }

    /// Every design's last export on this phone.
    static func lastExports(_ defaults: UserDefaults = .standard) -> [String: LastExport] {
        decodeLastExports(defaults.string(forKey: lastExportsKey))
    }

    /// Design `designId`'s last export, now, kept.
    static func rememberExport(_ designId: String, type: String, now: Date = Date(),
                               _ defaults: UserDefaults = .standard) {
        let export = LastExport(at: Int64((now.timeIntervalSince1970 * 1000).rounded()), type: type)
        defaults.set(encodeLastExports(exported(lastExports(defaults), designId: designId, export)),
                     forKey: lastExportsKey)
    }

    /// Design `designId`'s export failed as `failure`, now: kept as its last
    /// export (failedExport).
    static func rememberFailedExport(_ designId: String, failure: ExportFailure.Failure, now: Date = Date(),
                                     _ defaults: UserDefaults = .standard) {
        let at = Int64((now.timeIntervalSince1970 * 1000).rounded())
        defaults.set(encodeLastExports(failedExport(lastExports(defaults), designId: designId, failure: failure, at: at)),
                     forKey: lastExportsKey)
    }

    // MARK: the facts

    /// The facts of `design`, its type found among `sizes`. `fontsAvailable`
    /// are the fonts of your own this phone has, by key ("custom:<sha12>");
    /// every family of the library is on every phone.
    static func of(_ design: Design, sizes: [SizePreset] = SizePreset.all,
                   fontsAvailable: Set<String> = []) -> DesignFacts {
        let typeId = DesignLibrary.typeOf(design, presets: sizes)
        let typeName = sizes.first { $0.id == typeId }?.name ?? tr("Custom size")
        let measured = design.physicalUnit != nil
        let shown = design.visiblePageIndices.count
        let moving = ExportSuggestion.suggest(design, presets: sizes) == "mp4"
        let size = measured
            ? "\(Units.readout(design.width, design)) × \(Units.readout(design.height, design))\(Units.suffix(design))"
            : pixels(design)
        return DesignFacts(
            typeId: typeId,
            typeName: typeName,
            size: size,
            pixels: measured ? pixels(design) : nil,
            pages: shown,
            hiddenPages: design.pages.count - shown,
            seconds: moving ? Timeline.pages(of: design).reduce(0) { $0 + $1.hold } : nil,
            createdAt: design.createdAt,
            updatedAt: design.updatedAt,
            fonts: fonts(design, fontsAvailable: fontsAvailable),
            photos: DesignPackage.mediaIDs(in: design).count,
            videos: DesignPackage.videoIDs(in: design).count,
            audio: Set(design.audioTracks.compactMap(\.storedAudioId)).count)
    }

    /// "2480 × 3508 px": whole pixels, cut as a size in pixels is read.
    static func pixels(_ design: Design) -> String {
        Units.dimensions(width: design.width, height: design.height, unit: nil, dpi: nil) + " px"
    }

    /// The fonts of text boxes and shapes with words, and of words with a
    /// font of their own (spans), on every page — hidden ones too, since
    /// they are in the file — in the order first met, page by page, bottom
    /// layer up, a box's face before its words'. A box's weight is its own,
    /// 400 when it has none; words with a font of their own take their own
    /// weight, else the box's.
    static func fonts(_ design: Design, fontsAvailable: Set<String> = []) -> [Font] {
        var order: [String] = []
        var weights: [String: Set<Int>] = [:]
        func use(_ key: String?, _ weight: Int) {
            guard let key, !key.isEmpty else { return }
            let id = FontLibrary.resolve(key)
            if weights[id] == nil { order.append(id) }
            weights[id, default: []].insert(weight)
        }
        for page in design.pages {
            for el in page.elements {
                let own = el.fontWeight ?? 400
                if el.type == .text || ShapeText.words(of: el) != nil { use(el.fontFamily, own) }
                guard el.type == .text else { continue }
                for span in el.liveSpans where span.font != nil { use(span.font, span.weight ?? own) }
            }
        }
        let records = CustomFonts.records(in: design)
        return order.map { key in
            let custom = CustomFonts.isCustom(key)
            let name = custom ? (records.first { $0.id == key }?.name ?? key) : FontLibrary.of(key).name
            return Font(key: key, name: name, weights: (weights[key] ?? []).sorted(),
                        missing: custom && !fontsAvailable.contains(key))
        }
    }

    // MARK: what the sheet says

    /// "Instagram Post · 1080 × 1080 px": the type and size in one line.
    static func subtitle(_ facts: DesignFacts) -> String { "\(facts.typeName) · \(facts.size)" }

    /// "4 pages", or "4 pages, 1 hidden".
    static func pagesLine(_ facts: DesignFacts) -> String {
        let pages = trn("%d page|%d pages", facts.pages)
        return facts.hiddenPages == 0 ? pages : tr("%@, %d hidden", pages, facts.hiddenPages)
    }

    /// "100, 400, 700": a font's weights as numbers.
    static func weightsLine(_ font: Font) -> String {
        font.weights.map(String.init).joined(separator: ", ")
    }

    /// The brand kit `design` follows among `kits`, or nil: the first kit,
    /// in their order, one of whose logos it places; else the first one of
    /// whose faces (any text role's) and one of whose colours it both uses.
    /// A design does not record a kit, so this is read from what it shows —
    /// the simplest rule both phones share. Colours are compared as
    /// "#rrggbb", their alpha aside.
    static func brandKit(_ design: Design, kits: [BrandKit]) -> BrandKit? {
        let elements = design.pages.flatMap(\.elements)
        let sources = Set(elements.compactMap(\.src))
        if let byLogo = kits.first(where: { kit in kit.logos.contains { sources.contains($0) } }) { return byLogo }
        let used = Set(fonts(design).map(\.key))
        let colours = Set(elements.flatMap { ColourSwap.fields(of: $0) }.compactMap { ColourSwap.parse($0)?.rgb })
        return kits.first { kit in
            let faces = BrandFonts.Role.allCases.compactMap { kit.fonts[$0]?.family }.map { FontLibrary.resolve($0) }
            let shared = kit.colors.contains { ColourSwap.parse($0).map { colours.contains($0.rgb) } ?? false }
            return faces.contains { used.contains($0) } && shared
        }
    }
}
