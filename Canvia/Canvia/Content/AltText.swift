// A first draft of alt text, from the picture itself.
//
// Vision's image classifier runs on the device and names what it sees —
// "dog", "beach", "coffee" — which is a better starting point than an empty
// field, and the person can always rewrite it. Only ever a suggestion;
// nothing is stored without being asked.
//
// Where Vision is unsure — and as the "Use: …" chip beside an empty
// description — `suggest` drafts one from what the app already knows, with
// no model at all: the library item it is, its upload's file name, what
// kind of thing it is, or its two main colours. Pure and shared with the
// Android twin's AltText.suggest (Fixtures/alt-suggest.json).

import UIKit
import Vision

enum AltText {

    /// What a screen reader calls `el`: its description, trimmed, else its
    /// name (ElementNames) — the Android twin's AltText.spoken.
    static func spoken(_ el: Element) -> String {
        let alt = (el.altText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return alt.isEmpty ? ElementNames.name(of: el) : alt
    }

    /// "Photo of a dog, grass and sky", from the strongest classifications;
    /// nil when the classifier is unsure of everything.
    static func describe(_ image: UIImage, maxLabels: Int = 3, minConfidence: Float = 0.3) -> String? {
        guard let cg = image.cgImage else { return nil }
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }
        let labels = (request.results ?? [])
            .filter { $0.confidence >= minConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxLabels)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        return sentence(from: Array(labels))
    }

    /// "Photo of a dog", "Photo of a dog and grass", "Photo of a dog, grass and sky".
    static func sentence(from labels: [String]) -> String? {
        guard let first = labels.first else { return nil }
        let article = "aeiou".contains(first.first?.lowercased() ?? "x") ? "an" : "a"
        switch labels.count {
        case 1: return "Photo of \(article) \(first)"
        case 2: return "Photo of \(article) \(first) and \(labels[1])"
        default: return "Photo of \(article) \(first), \(labels.dropFirst().dropLast().joined(separator: ", ")) and \(labels.last!)"
        }
    }

    // MARK: a suggestion

    /// What the phone knows of a picture that its element does not hold:
    /// the name its upload's file had, a clip's length in seconds, and its
    /// leading colours (PhotoPalette.extract, most first).
    struct Hints: Equatable {
        var fileName: String?
        var clipSeconds: Double?
        var colours: [String] = []
    }

    /// A draft description of `el` from what the app already knows, never
    /// stored until a person takes it — the first of:
    /// 1. the library item it is: a graphic's, an icon's or a moving
    ///    picture's name with up to three of its tags the name does not
    ///    already say ("Curved arrow (doodle, pointer, hand drawn)"), a stock
    ///    picture's name, a mockup's scene, a sticker's first word ("Party
    ///    sticker");
    /// 2. its upload's file name, cleaned of a camera's pattern
    ///    (`fromFileName`);
    /// 3. what kind of thing it is: a QR code and where it links, a barcode,
    ///    a chart ("Bar chart of Sales by Month"), a clip and its length;
    /// 4. its two leading colours ("Mostly blue and white photo").
    /// Nil when none of them says anything. In the app's language.
    static func suggest(_ el: Element, hints: Hints = Hints()) -> String? {
        fromLibrary(el) ?? hints.fileName.flatMap(fromFileName) ?? fromKind(el, hints: hints)
            ?? fromColours(el, hints.colours)
    }

    private static func named(_ name: String, tags: [String]) -> String {
        let words = Set(name.lowercased().split(separator: " ").map(String.init))
        var extra: [String] = []
        for tag in tags.map({ $0.trimmingCharacters(in: .whitespaces) })
        where !tag.isEmpty && !words.contains(tag.lowercased()) && !extra.contains(tag) && extra.count < 3 {
            extra.append(tag)
        }
        return extra.isEmpty ? name : tr("%@ (%@)", name, extra.joined(separator: ", "))
    }

    private static func fromLibrary(_ el: Element) -> String? {
        if let graphic = GraphicsLibrary.graphic(of: el) { return named(graphic.name, tags: graphic.tags) }
        if let icon = IconLibrary.icon(of: el) { return named(icon.name, tags: icon.tags) }
        if let src = el.src {
            if let motion = MotionLibrary.split(src).flatMap({ MotionLibrary.def($0.id) }) {
                return named(motion.name, tags: motion.tags)
            }
            if src.hasPrefix("asset:"), let stock = PhotoLibrary.photos.first(where: { "asset:" + $0.id == src }) {
                return stock.name
            }
        }
        if let scene = MockupScenes.scene(el.mockupId) { return tr("%@ mockup", scene.name) }
        if el.type == .sticker {
            guard let word = el.glyph.flatMap({ Stickers.words(for: $0).first }), let first = word.first else { return nil }
            return tr("%@ sticker", first.uppercased() + word.dropFirst())
        }
        return nil
    }

    /// The words a camera, a phone or an app names its files with, which
    /// say nothing of what is in them.
    private static let cameraWords: Set<String> = [
        "img", "pxl", "dsc", "dscn", "dscf", "dcim", "vid", "mvimg", "mp", "portrait", "night", "burst", "cover",
        "screenshot", "whatsapp", "image", "photo", "pic", "at", "edited", "copy", "jpg", "jpeg", "png", "heic",
    ]

    /// A file's name as a description: its extension dropped, split at
    /// spaces, dots, underscores and hyphens, every word with a digit in it
    /// and every camera word ("IMG", "PXL", "Screenshot"…) left out, the rest
    /// joined by spaces with the first letter a capital — "beach_sunset.jpg"
    /// is "Beach sunset"; nil when nothing is left, as of "IMG_1234.JPG" or
    /// "PXL_20250101_123456789.jpg".
    static func fromFileName(_ name: String) -> String? {
        var stem = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = stem.lastIndex(of: "."), dot > stem.startIndex { stem = String(stem[..<dot]) }
        let words = stem.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "_" || $0 == "-" })
            .map(String.init)
            .filter { w in !w.contains(where: \.isNumber) && !cameraWords.contains(w.lowercased()) }
        guard let first = words.first?.first else { return nil }
        let joined = words.joined(separator: " ")
        return first.uppercased() + joined.dropFirst()
    }

    private static func fromKind(_ el: Element, hints: Hints) -> String? {
        if let payload = el.src.flatMap(CodeGenerator.payload(from:)) {
            return hostOf(payload).map { tr("QR code linking to %@", $0) } ?? tr("QR code")
        }
        if let barcode = Barcodes.parse(el.src) { return tr("Barcode for %@", barcode.payload) }
        if let spec = el.chart { return chart(spec) }
        if VideoStore.isVideo(el.src) {
            guard let seconds = hints.clipSeconds, seconds > 0 else { return tr("Video clip") }
            let whole = max(1, Int(seconds.rounded()))
            return trn("Video clip, %d second|Video clip, %d seconds", whole)
        }
        return nil
    }

    /// The site a web link goes to, its "www." left off: "example.com" for
    /// "https://www.example.com/menu"; nil for anything else.
    static func hostOf(_ link: String) -> String? {
        let lower = link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let scheme = ["https://", "http://"].first(where: { lower.hasPrefix($0) }) else { return nil }
        var host = String(lower.dropFirst(scheme.count).prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" })
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    /// "Bar chart of Sales by Month": the kind, the series its header names
    /// and the header's first cell — or the axis titles when it has them.
    private static func chart(_ spec: ChartSpec) -> String {
        let kind = DataGraphics.ChartKind(rawValue: spec.kind)?.name ?? spec.kind.capitalized
        let data = DataGraphics.parseChart(spec.data)
        let header = DataGraphics.parseTable(spec.data).first { row in row.contains { !$0.isEmpty } }
        let named = data.names.filter { $0.range(of: #"^Series \d+$"#, options: .regularExpression) == nil }
        let series = spec.yTitle ?? (named.isEmpty ? nil : named.joined(separator: ", "))
        let firstCell = header?.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let by = spec.xTitle ?? (!firstCell.isEmpty && !named.isEmpty ? firstCell : nil)
        if let series, let by { return tr("%@ chart of %@ by %@", kind, series, by) }
        if let series { return tr("%@ chart of %@", kind, series) }
        return tr("%@ chart", kind)
    }

    /// "Mostly blue and white photo": the families of the first two of
    /// `colours` (ElementNames.colourFamily) — one when they are the same.
    private static func fromColours(_ el: Element, _ colours: [String]) -> String? {
        guard el.type == .image else { return nil }
        var families: [String] = []
        for hex in colours.prefix(2) {
            let family = ElementNames.colourFamily(hex)
            if !families.contains(family) { families.append(family) }
        }
        switch families.count {
        case 0: return nil
        case 1: return tr("Mostly %@ photo", tr(families[0]))
        default: return tr("Mostly %@ and %@ photo", tr(families[0]), tr(families[1]))
        }
    }

    /// What this phone knows of `el` besides the design: its upload's file
    /// name (a photo's or a clip's), a clip's length, and — for an upload of
    /// your own, a still picture — its two leading colours. The colours are
    /// read only for a "media:" source, as the Android twin's altSuggestion
    /// reads them: a library, brand or moving picture, a code or a clip has
    /// none. Reads files, so it is best called off the main thread.
    static func hints(for el: Element) -> Hints {
        guard let src = el.src else { return Hints() }
        var hints = Hints()
        if src.hasPrefix("media:") {
            let id = String(src.dropFirst("media:".count))
            hints.fileName = Uploads.all().first { $0.id == id }?.fileName
            if el.type == .image, let image = MediaStore.load(id) {
                hints.colours = PhotoPalette.extract(from: image, count: 2)
            }
        } else if let clip = VideoStore.split(src) {
            hints.fileName = Uploads.all().first { $0.id == clip.id }?.fileName
            hints.clipSeconds = VideoStore.duration(of: clip.id)
        }
        return hints
    }
}
