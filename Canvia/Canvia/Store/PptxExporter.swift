// PowerPoint export: a design as a .pptx deck, as Canva's Download ▸
// Microsoft PowerPoint makes one.
//
// Each page shown becomes a slide at the design's size, and each element
// whatever keeps it editable there:
//
//   text               a text box: the family's name, the size in points
//                      (px × 0.75), bold, italic, underline and strike runs
//                      from its inline styles, the colours and sizes on its
//                      words, capitals, its alignment and its rotation
//   squares, circles   preset shapes (prstGeom rect / roundRect / ellipse)
//                      with their fill — solid, none or a linear gradient —
//                      and border
//   straight-edged     the outline the canvas draws (ShapeGeometry):
//   library shapes     PowerPoint's preset where one draws it the same
//   and callouts       (prstGeom with its adj), else a free-form shape
//                      (custGeom), filled and bordered as the squares are
//   lines              a preset line with its dash and arrow or dot ends
//   everything else    a PNG picture at 2×, drawn by the very view the
//                      canvas draws it with, placed over its box — photos,
//                      stickers, icons, drawn and library shapes, charts,
//                      tables, text with effects, anything with a shadow,
//                      a flip or a blend
//
// A page's background is a solid fill, or a picture filling the slide; its
// notes become a notes slide; a link a click on the element. Hidden pages
// are left out by the same page choice the PDF follows.
//
// The writer is pure, and built as the Android twin's PptxWriter is: the
// same design makes the same slide XML on both phones, character for
// character (PptxExporterTests holds the shared vectors). The rules where
// the format left a choice:
//
//   • lengths are EMU, px × 9525 × the deck's slideScale, rounded half away
//     from zero; sizes are hundredths of a point, px × 75 × that scale;
//     angles are 60000ths of a degree, turned into 0..<360 first
//   • an optional attribute is written only when it is not the format's
//     default (no rot="0", no algn="l", no anchor="t", no b="0"); text
//     boxes have no insets and no autofit, fitted type going out at the
//     size the canvas draws it
//   • a run is bold at weight 700 and up, or in **bold**; words that come
//     out the same are one run
//   • shapes are numbered from 2 (1 is the slide's tree) in drawing order
//     and named by the element's id, its alt text, trimmed, as the
//     description
//   • a page's background is the slide's p:bg: its colour, or a gradient or
//     photo as a picture stretched over it — white when it cannot be drawn
//   • a page of a size of its own is fitted whole onto the slide (fit):
//     every length times one factor, centred; its colour still fills the
//     slide, but a gradient or photo behind it is a picture at its place,
//     the first shape on the slide, with white round it
//   • a type size is held to the 1 to 4000 points PowerPoint reads (typeSize)
//   • a word's own font and link go with it: the run names its face, and a
//     linked word, coloured as the canvas draws it, opens on a click
//   • a slide's relationships run rId1 for its layout, then what its XML
//     needs in reading order — the background picture, then each
//     element's link before its picture — and its notes slide last
//   • pictures are ppt/media/imageN.png, a background imageN.jpeg,
//     numbered across the deck as they are drawn; one that cannot be drawn
//     is left out of its slide and takes no number
//   • the file holds the fixed parts first, then for each slide its
//     pictures, the slide and its relationships, then its notes slide and
//     theirs
//   • a slide's transition is the way the slide before it gives way
//     (fade, push or cut; any other kind none), and the first has none

import CoreGraphics
import SwiftUI
import UIKit

enum PptxExporter {

    /// What the file is, for sharing.
    static let mimeType = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    static let fileExtension = "pptx"

    /// Pictures are drawn at twice their size on the page, as the SVG's are.
    static let pictureScale = 2.0

    // MARK: units

    /// English Metric Units in a page pixel: 914400 an inch at 96 px an inch.
    static let emuPerPixel = 9525.0

    /// The sides of a slide PowerPoint opens, in page px: 1 to 56 inches.
    static let minSlidePixels = 96.0
    static let maxSlidePixels = 5376.0

    /// A length on the page in EMU, rounded half away from zero.
    static func emu(_ px: Double) -> Int {
        guard px.isFinite else { return 0 }
        return Int((min(max(px, -1e9), 1e9) * emuPerPixel).rounded())
    }

    /// A type size in hundredths of a point: px × 0.75 pt, × 100.
    static func fontSize(_ px: Double) -> Int {
        guard px.isFinite else { return 0 }
        return Int((min(max(px, 0), 1e6) * 75).rounded())
    }

    /// A run's type size: fontSize held to the 100 to 400000 (1 to 4000 pt)
    /// a deck may give it — not its spacing, which may be any.
    static func typeSize(_ px: Double) -> Int {
        min(max(fontSize(px), 100), 400_000)
    }

    /// An angle in 60000ths of a degree, clockwise, within 0..<360°.
    static func angle(_ degrees: Double) -> Int {
        guard degrees.isFinite else { return 0 }
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        let a = Int((d * 60000).rounded())
        return a >= 21_600_000 ? 0 : a
    }

    /// What every length on the deck is multiplied by: 1, unless a side of
    /// the design falls outside the 96 to 5376 px PowerPoint opens — then
    /// the one factor that brings the shorter side up to 96 or, winning
    /// over it, the longer down to 5376, so the whole design stays on the
    /// slide in its proportions.
    static func slideScale(width: Double, height: Double) -> Double {
        let short = min(width, height)
        let long = max(width, height)
        guard short > 0, long.isFinite else { return 1 }
        var scale = short < minSlidePixels ? minSlidePixels / short : 1
        if long * scale > maxSlidePixels { scale = maxSlidePixels / long }
        return scale
    }

    /// A slide's side in EMU at `scale`, kept within what PowerPoint opens
    /// — which only a design far longer than it is wide still needs.
    static func slideEdge(_ px: Double, scale: Double) -> Int {
        min(max(emu(px * scale), 914_400), 51_206_400)
    }

    /// Where a page sits on the deck's slide, in the design's pixels: times
    /// `factor`, `dx` in from the left and `dy` down from the top.
    struct PageFit: Equatable {
        var factor: Double
        var dx: Double
        var dy: Double

        /// Whether the page covers the whole slide — within half a pixel —
        /// so that its background can be the slide's.
        var fills: Bool { dx < 0.5 && dy < 0.5 }
    }

    /// Where `page` sits on a slide at the design's size: one with no size
    /// of its own fills it; one with its own is fitted whole into it — the
    /// one factor that fits both sides, min(W/w, H/h) — and centred.
    static func fit(design: Design, page: Page) -> PageFit {
        let w = page.width ?? design.width
        let h = page.height ?? design.height
        let whole = PageFit(factor: 1, dx: 0, dy: 0)
        if w == design.width && h == design.height { return whole }
        let factor = min(design.width / w, design.height / h)
        guard factor > 0, factor.isFinite else { return whole }
        return PageFit(factor: factor, dx: (design.width - w * factor) / 2, dy: (design.height - h * factor) / 2)
    }

    /// How a page's lengths go onto its slide: times `unit` — the deck's
    /// scale and the page's fit together — then `dx` and `dy` along, in
    /// the slide's pixels.
    struct Frame {
        var unit: Double
        var dx: Double = 0
        var dy: Double = 0
    }

    // MARK: what each element becomes

    enum Form: Equatable {
        case text
        /// A preset shape: "rect", "roundRect" or "ellipse".
        case shape(String)
        /// A library shape rounded or shaped (ShapeGeometry): its outline
        /// as a free-form shape.
        case geometry
        case line
        case picture
        /// A QR code drawn in its colours alone (CodeGenerator.vector):
        /// its background and its modules, free-form rectangles.
        case code
        /// Warped words (TextWarp): their bent outlines, a free-form shape
        /// for each colour — a word's own, the text's for the rest.
        case warped
    }

    /// The effects styled text carries over as DrawingML; the rest —
    /// splice, echo, glitch — stay pictures.
    static let styledEffects: Set<TextEffect> = [.none, .shadow, .lift, .outline, .outlined, .neon, .highlight]

    /// What `el` becomes, by the rule the Android twin's kindOf follows:
    /// anything blended with what is under it, and any cell of a table or
    /// part of a chart, is a picture, and so is anything but styled text
    /// with a shadow; text is a text box when it is not flipped and — with
    /// `styled` text, the "Styled text: Editable" setting — has an effect
    /// carried over (styledEffects), a curve or a column but not a path,
    /// whatever its gradient letters, drop cap or shadow; else when it has
    /// no effect, no curve, path or column, no gradient letters, no drop
    /// cap and no shadow.
    static func form(of el: Element, styled: Bool = true) -> Form {
        // A table's cells and a chart and its parts come through as
        // pictures, and so does anything blended with what is under it,
        // which no preset carries, or casting a shadow — but styled text.
        if el.table != nil || el.chart != nil || el.chartPart != nil || BlendModes.mode(el.blendMode).id != "normal" {
            return .picture
        }
        // A cropped graphic (GraphicClip) as the picture of what shows: a
        // preset or path has no crop of its own.
        if GraphicClip.ownRect(el) != nil { return .picture }
        if el.shadow != nil && !(styled && el.type == .text) { return .picture }
        let flipped = el.flipH || el.flipV
        switch el.type {
        case .text:
            if flipped { return .picture }
            // Bent letters as the vectors they are drawn as, unless they
            // are painted with a gradient or a photo, or have an effect.
            if TextWarp.isWarped(el) {
                let plain = el.textFill == nil && TextEffect.from(el.effect) == .none && el.shadow == nil
                return plain ? .warped : .picture
            }
            if styled { return isStyledText(el) ? .text : .picture }
            let gradient = el.textFill?.kind == "gradient" && !(el.textFill?.stops ?? []).isEmpty
            if gradient || TextEffect.from(el.effect) != .none || TextOutliner.followsAPath(el)
                || FontLibrary.dropCapLayout(for: el) != nil {
                return .picture
            }
            return .text
        case .shape:
            guard !flipped, el.pathData?.isEmpty ?? true, el.iconId == nil, ShapeText.words(of: el) == nil,
                  !(el.corners ?? []).contains(where: { $0 > 0 }), presetFill(el.fill) else { return .picture }
            switch ContentLibrary.shape(for: el).id {
            case "circle":
                return .shape("ellipse")
            case "rect":
                return (el.radius ?? 0) > 0 && min(el.w, el.h) > 0 ? .shape("roundRect") : .shape("rect")
            default:
                return ShapeGeometry.outline(el) != nil ? .geometry : .picture
            }
        case .line:
            // A flip turns its ends round (lineXML).
            return .line
        case .image:
            // A code drawn in its colours alone, and not flipped, goes out
            // as rectangles — a barcode with its words — and a QR code with
            // a logo as the picture the canvas draws, the logo in it, as on
            // the Android twin; any other photo as its picture.
            if flipped { return .picture }
            if Barcodes.vector(el) != nil { return .code }
            if let code = CodeGenerator.vector(el), code.logoPad == nil { return .code }
            return .picture
        case .sticker:
            return .picture
        }
    }

    /// Whether styled text stays a text box: its effect one of
    /// styledEffects, and not set along a path.
    private static func isStyledText(_ el: Element) -> Bool {
        styledEffects.contains(TextEffect.from(el.effect)) && (el.textPath ?? "").isEmpty
    }

    /// Whether a preset shape can be filled as the canvas fills it: a
    /// colour, nothing, or a linear gradient of two stops or more.
    static func presetFill(_ fill: Paint?) -> Bool {
        guard let fill else { return true }
        switch fill.kind {
        case "solid", "none": return true
        case "gradient":
            return (fill.gradientKind ?? "linear") == "linear" && (fill.stops?.count ?? 0) >= 2
        default: return false
        }
    }

    /// How far past its box a picture reaches, in page px: the SVG's
    /// overflow (a border, a leaning outline, a photo's edge), a shadow's
    /// blur and a half and its longer offset (the SVG shadow's room), a
    /// text effect's reach at the size the text is drawn, and a line's
    /// arrowhead, which covers a dot and half the line.
    static func margin(_ el: Element) -> Double {
        var reach = SVGExporter.overflow(el)
        if let shadow = ShadowShapes.cast(el) {
            reach += shadow.blur * 1.5 + max(abs(shadow.offsetX), abs(shadow.offsetY))
                + ShadowShapes.reach(of: shadow, w: el.w, h: el.h)
        }
        if el.type == .text, TextEffect.from(el.effect) != .none {
            let size = FontLibrary.effectiveFontSize(for: el)
            reach += TextEffect.resolve(el.effect, fontSize: size, ink: el.color ?? "#1f2430").reach
        }
        if el.type == .line { reach += LineEnds.reach(el) + LineRoutes.bow(el) }
        return reach
    }

    // MARK: a slide

    /// A picture a slide needs drawn — or, for letters full of a photo,
    /// the photo as it is stored, which the runs' blipFill points to.
    struct MediaPart: Equatable {
        enum Source: Equatable {
            case element(Element)
            case background
            case photo(String)
        }

        /// Its file under ppt/media: "image3.png".
        var name: String
        var source: Source
    }

    /// One slide: its XML, its relationships, the pictures they name, and
    /// its notes slide when the page has notes.
    struct SlideParts: Equatable {
        var xml: String
        var rels: String
        var media: [MediaPart]
        var notes: String?
    }

    /// A part's relationships, numbered rId1, rId2… as they are added.
    struct Relationships {
        private(set) var entries: [String] = []

        @discardableResult
        mutating func add(_ type: String, _ target: String, external: Bool = false) -> String {
            let id = "rId\(entries.count + 1)"
            let mode = external ? " TargetMode=\"External\"" : ""
            let target = SVGExporter.escape(target)
            entries.append("<Relationship Id=\"\(id)\" Type=\"\(PptxExporter.relationshipBase)\(type)\" Target=\"\(target)\"\(mode)/>")
            return id
        }

        var xml: String {
            PptxExporter.declaration + "<Relationships xmlns=\"\(PptxExporter.packageNS)\">"
                + entries.joined() + "</Relationships>"
        }
    }

    /// Whether a page has notes to carry: any that are not only spaces.
    static func hasNotes(_ page: Page) -> Bool {
        !(page.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What a page's notes slide says: its own notes, then the words of
    /// each text that goes out warped (Form.warped) — which the slide has
    /// only as outlines — a line each, so they can still be copied and
    /// edited; nil when there is nothing to say. The Android twin's
    /// PptxWriter.notesOf.
    static func notesText(design: Design, page: Page, styled: Bool = true) -> String? {
        let warped = drawnElements(design: design, page: page).filter { form(of: $0, styled: styled) == .warped }
            .map { RichText.strip($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let lines = (hasNotes(page) ? [page.notes ?? ""] : []) + warped
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// What a page draws, bottom up — the master's elements behind its
    /// own, the hidden ones left out — with its page numbers filled in, each
    /// arriving as the page's own animation has it, as Present plays it.
    static func drawnElements(design: Design, page: Page) -> [Element] {
        let pageNumber = (design.pages.firstIndex { $0.id == page.id } ?? 0) + 1
        return design.drawnElements(on: PageAnimation.playing(page)).map { el in
            var resolved = el
            if ShapeText.carriesWords(el) {
                resolved.fillPageTokens(number: pageNumber, count: design.pages.count)
            }
            return resolved
        }
    }

    /// What a photo in letters needs known of the picture without drawing
    /// it: its pixels, its average colour and its file's type — this
    /// phone's stored pictures, or a test's stand-ins.
    struct PhotoLookup {
        var size: (String) -> CGSize?
        var average: (String) -> String?
        var type: (String) -> String

        static let stored = PhotoLookup(size: { ExportChoices.photoPixelSize($0) },
                                        average: { PhotoPalette.averageColour($0) },
                                        type: { PhotoFills.storedType($0) })
    }

    /// A picture's file name, by its number in the deck: a JPEG for the
    /// page's background, a PNG for an element, a photo in letters as it
    /// is stored.
    static func fileName(_ number: Int, for source: MediaPart.Source, photos: PhotoLookup = .stored) -> String {
        switch source {
        case .background: return "image\(number).jpeg"
        case .element: return "image\(number).png"
        case .photo(let src): return "image\(number).\(photos.type(src))"
        }
    }

    /// The photo `el`'s letters are full of, when the effect lets it
    /// through (TextEffect.takesPhoto) and the box goes out as text.
    static func pouredPhoto(_ el: Element) -> String? {
        guard el.type == .text, let fill = el.textFill, fill.isPhoto, TextEffect.from(el.effect).takesPhoto else { return nil }
        return fill.src
    }

    /// The pictures `page` needs drawn, in the order its slide meets them —
    /// a gradient or photo behind it first, then the photos letters are
    /// full of, then each element that comes through as a picture — named
    /// from `firstImage` as if each one draws.
    static func media(design: Design, page: Page, firstImage: Int, styled: Bool = true,
                      photos: PhotoLookup = .stored) -> [MediaPart] {
        var parts: [MediaPart] = []
        func add(_ source: MediaPart.Source) {
            parts.append(MediaPart(name: fileName(firstImage + parts.count, for: source, photos: photos), source: source))
        }
        if case .color(_) = page.background {} else { add(.background) }
        let drawn = drawnElements(design: design, page: page)
        for el in drawn where form(of: el, styled: styled) == .text {
            if let src = pouredPhoto(el) { add(.photo(src)) }
        }
        for el in drawn where form(of: el, styled: styled) == .picture && el.w > 0 && el.h > 0 {
            add(.element(el))
        }
        return parts
    }

    /// Every slide of the pages at `indices`, in order, as it is when every
    /// picture draws.
    static func deck(design: Design, indices: [Int], styled: Bool = true, photos: PhotoLookup = .stored) -> [SlideParts] {
        var slides: [SlideParts] = []
        var image = 1
        let numbers = slideNumbers(design: design, indices: indices)
        for (n, index) in indices.enumerated() {
            let previous = n > 0 ? design.pages[indices[n - 1]] : nil
            let parts = slide(design: design, page: design.pages[index], number: n + 1,
                              previous: previous, firstImage: image, styled: styled, photos: photos, slides: numbers)
            image += parts.media.count
            slides.append(parts)
        }
        return slides
    }

    /// Slide `number` of the deck, showing `page`, after `previous`, as it
    /// is when every picture draws; its pictures numbered from `firstImage`.
    static func slide(design: Design, page: Page, number: Int, previous: Page?, firstImage: Int,
                      styled: Bool = true, photos: PhotoLookup = .stored, slides: [String: Int] = [:]) -> SlideParts {
        slide(design: design, page: page, number: number, previous: previous,
              drawn: media(design: design, page: page, firstImage: firstImage, styled: styled, photos: photos),
              styled: styled, photos: photos, slides: slides)
    }

    /// Which slide of a deck of the pages at `indices` shows each page, by
    /// page id: what a link to a page jumps to.
    static func slideNumbers(design: Design, indices: [Int]) -> [String: Int] {
        var numbers: [String: Int] = [:]
        for (n, index) in indices.enumerated() where numbers[design.pages[index].id] == nil {
            numbers[design.pages[index].id] = n + 1
        }
        return numbers
    }

    /// What a shape's or a word's hlinkClick says for `link`, its
    /// relationship added to `rels`: out to an address, or — a link to a
    /// page of the deck (`slides`, by page id) — a jump to that page's
    /// slide, ppaction://hlinksldjump, as PowerPoint writes one. Nil for no
    /// link, one to a page not in the deck, or one dangling.
    static func clickAttributes(_ link: String?, design: Design, slides: [String: Int],
                                rels: inout Relationships) -> String? {
        if let url = Links.followable(link) { return "r:id=\"\(rels.add("hyperlink", url, external: true))\"" }
        guard Links.pageIndex(link, in: design) != nil, let id = Links.pageId(link), let number = slides[id] else { return nil }
        return "r:id=\"\(rels.add("slide", "slide\(number).xml"))\" action=\"ppaction://hlinksldjump\""
    }

    /// Slide `number` of the deck, showing `page`, after `previous`, with
    /// the pictures `drawn` — those that were: an element whose picture is
    /// not among them is left out, and a background that is not is white.
    /// `styled` text goes out editable, as its closest match (the
    /// "pptxStyledText" setting's "editable"); else as the picture of its
    /// exact look. A link to a page jumps to its slide among `slides`.
    static func slide(design: Design, page: Page, number: Int, previous: Page?, drawn: [MediaPart],
                      styled: Bool = true, photos: PhotoLookup = .stored, slides: [String: Int] = [:]) -> SlideParts {
        let scale = slideScale(width: design.width, height: design.height)
        let placed = fit(design: design, page: page)
        let frame = Frame(unit: scale * placed.factor, dx: placed.dx * scale, dy: placed.dy * scale)
        var rels = Relationships()
        rels.add("slideLayout", "../slideLayouts/slideLayout1.xml")
        var remaining = drawn
        /// The drawn picture of `source`, taken off the list so a second
        /// element just like it finds its own.
        func take(_ source: MediaPart.Source) -> MediaPart? {
            guard let at = remaining.firstIndex(where: { $0.source == source }) else { return nil }
            return remaining.remove(at: at)
        }

        var fill = "<a:solidFill>\(color("#ffffff"))</a:solidFill>"
        var backdrop: String?
        if case .color(let hex) = page.background {
            fill = "<a:solidFill>\(color(hex))</a:solidFill>"
        } else if let picture = take(.background) {
            // A gradient or a photo behind the page: the pixels the canvas
            // draws, stretched over the slide — or, round a page of another
            // shape, white with the picture at the page's place.
            let embed = rels.add("image", "../media/\(picture.name)")
            if placed.fills {
                fill = "<a:blipFill><a:blip r:embed=\"\(embed)\"/><a:stretch><a:fillRect/></a:stretch></a:blipFill>"
            } else {
                backdrop = embed
            }
        }
        let background = "<p:bg><p:bgPr>\(fill)<a:effectLst/></p:bgPr></p:bg>"

        var shapes: [String] = []
        // Whose each shape is, so groups go out as grpSp (Groups.nested).
        var owners: [Element?] = []
        var nextId = 2
        // Each element's shape id, for its entrance in the slide's timing.
        var timed: [(id: Int, el: Element)] = []
        if let backdrop {
            let size = design.size(for: page)
            let box = xfrm(x: 0, y: 0, w: Double(size.width), h: Double(size.height), rotation: 0, frame: frame)
            let properties = "<p:nvPicPr><p:cNvPr id=\"\(nextId)\" name=\"Background\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>"
            let picture = "<p:blipFill><a:blip r:embed=\"\(backdrop)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>"
            shapes.append("<p:pic>\(properties)\(picture)<p:spPr>\(box)\(geometry("rect"))</p:spPr></p:pic>")
            owners.append(nil)
            nextId += 1
        }
        for el in drawnElements(design: design, page: page) {
            defer { while owners.count < shapes.count { owners.append(el) } }
            let kind = form(of: el, styled: styled)
            var picture: MediaPart?
            if kind == .picture {
                picture = take(.element(el))
                if picture == nil { continue }
            }
            let id = nextId
            nextId += 1
            timed.append((id: id, el: el))
            let link = clickAttributes(el.link, design: design, slides: slides, rels: &rels)
            switch kind {
            case .text:
                // Letters full of a photo: the picture, cropped to the
                // window, as the runs' fill; where the effect cannot hold
                // it, the letters in the photo's average colour.
                var poured: PouredPhoto?
                if let src = pouredPhoto(el), let part = take(.photo(src)), let size = photos.size(src) {
                    poured = PouredPhoto(embed: rels.add("image", "../media/\(part.name)"), size: size)
                }
                let average = el.textFill?.isPhoto == true ? el.textFill?.src.flatMap(photos.average) : nil
                shapes.append(textXML(el, id: id, link: link, design: design, slides: slides, frame: frame, rels: &rels,
                                      photo: poured, ink: average))
            case .shape(let preset):
                shapes.append(shapeXML(el, preset: preset, id: id, link: link, frame: frame))
            case .geometry:
                shapes.append(shapeXML(el, preset: "rect", id: id, link: link, frame: frame,
                                       outline: builtGeometry(el, frame: frame)))
            case .warped:
                // A shape a colour: each word's own, the text's for the
                // rest; the first carries the element's name and link, as
                // the Android twin writes them.
                if let inked = TextOutliner.inkedPaths(for: el) {
                    shapes.append(contentsOf: warpedXML(el, parts: inked.parts, id: id, nextId: &nextId,
                                                        link: link, frame: frame))
                }
            case .line:
                shapes.append(lineXML(el, id: id, link: link, frame: frame))
            case .code:
                if let bars = Barcodes.vector(el) {
                    shapes.append(contentsOf: barcodeXML(el, bars, id: id, nextId: &nextId, link: link, design: design,
                                                         frame: frame, rels: &rels))
                    continue
                }
                guard let code = CodeGenerator.vector(el) else { continue }
                // Its background first, a shape of its own under the
                // modules, which carry the element's name and link.
                var modulesId = id
                if let paper = code.style.background, let box = code.background {
                    let properties = "<p:cNvPr id=\"\(id)\" name=\"\(SVGExporter.escape(el.id)) background\"/>"
                    shapes.append(rectanglesXML(el, properties: properties, rects: [box], colour: paper, frame: frame))
                    modulesId = nextId
                    nextId += 1
                }
                if !code.modules.isEmpty {
                    shapes.append(rectanglesXML(el, properties: cNvPr(el, id: modulesId, link: link),
                                                rects: code.modules, colour: code.style.color, frame: frame))
                }
                if !code.marks.isEmpty {
                    shapes.append(outlineXML(el, properties: cNvPr(el, id: modulesId, link: link),
                                             steps: code.marks, colour: code.style.color, frame: frame))
                }
            case .picture:
                let embed = rels.add("image", "../media/\(picture?.name ?? "")")
                let pad = margin(el)
                let box = xfrm(x: el.x - pad, y: el.y - pad, w: el.w + 2 * pad, h: el.h + 2 * pad,
                               rotation: el.rotation, frame: frame)
                shapes.append(pictureXML(el, id: id, link: link, embed: embed, box: box))
            }
        }

        var notes: String?
        if let text = notesText(design: design, page: page, styled: styled) {
            rels.add("notesSlide", "../notesSlides/notesSlide\(number).xml")
            notes = notesXML(text)
        }

        let pieces: [(el: Element?, part: String)] = zip(owners, shapes).map { ($0, $1) }
        let grouped = Groups.nested(pieces) { group, members, inner in
            let id = nextId
            nextId += 1
            return groupXML(group, id: id, members: members, frame: frame) + inner.joined() + "</p:grpSp>"
        }
        let tree = "<p:spTree>\(groupHeader)\(grouped.joined())</p:spTree>"
        // A motion path's moves are shares of the slide, in the page's units
        // as it is fitted onto the slide.
        let timing = PptxAnimations.timing(timed, slideW: design.width / placed.factor,
                                           slideH: design.height / placed.factor)
        let xml = [declaration, "<p:sld \(namespaces)>", "<p:cSld>", background, tree, "</p:cSld>",
                   masterColours, transitionXML(after: previous, in: design), timing, "</p:sld>"].joined()
        return SlideParts(xml: xml, rels: rels.xml, media: drawn, notes: notes)
    }

    /// How the slide comes in: the way the page before it gives way.
    static func transitionXML(after previous: Page?, in design: Design) -> String {
        guard let previous else { return "" }
        switch PageTransitions.transitionKind(after: previous, in: design) {
        case "fade": return "<p:transition><p:fade/></p:transition>"
        case "push": return "<p:transition><p:push/></p:transition>"
        case "cut": return "<p:transition><p:cut/></p:transition>"
        default: return ""
        }
    }

    // MARK: elements

    /// The box's place, size and turn about its centre, on the slide as
    /// `frame` puts the page.
    static func xfrm(x: Double, y: Double, w: Double, h: Double, rotation: Double, frame: Frame) -> String {
        let rot = angle(rotation)
        let turned = rot == 0 ? "" : " rot=\"\(rot)\""
        let offset = "<a:off x=\"\(emu(x * frame.unit + frame.dx))\" y=\"\(emu(y * frame.unit + frame.dy))\"/>"
        let extent = "<a:ext cx=\"\(max(0, emu(w * frame.unit)))\" cy=\"\(max(0, emu(h * frame.unit)))\"/>"
        return "<a:xfrm\(turned)>\(offset)\(extent)</a:xfrm>"
    }

    /// A group's opening, its members to follow: the box round their turned
    /// bounds, its children's frame the same box, so they keep their places
    /// as they are — and are read back where they were (PptxReader).
    private static func groupXML(_ group: String, id: Int, members: [Element], frame: Frame) -> String {
        let box = Geometry.union(members.map(Geometry.aabb))
        let x = emu(Double(box.minX) * frame.unit + frame.dx), y = emu(Double(box.minY) * frame.unit + frame.dy)
        let cx = max(0, emu(Double(box.width) * frame.unit)), cy = max(0, emu(Double(box.height) * frame.unit))
        let properties = "<p:nvGrpSpPr><p:cNvPr id=\"\(id)\" name=\"\(SVGExporter.escape(group))\"/>"
            + "<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
        let offset = "<a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/>"
        let children = "<a:chOff x=\"\(x)\" y=\"\(y)\"/><a:chExt cx=\"\(cx)\" cy=\"\(cy)\"/>"
        return "<p:grpSp>" + properties + "<p:grpSpPr><a:xfrm>" + offset + children + "</a:xfrm></p:grpSpPr>"
    }

    private static func elementBox(_ el: Element, frame: Frame) -> String {
        xfrm(x: el.x, y: el.y, w: el.w, h: el.h, rotation: el.rotation, frame: frame)
    }

    private static func geometry(_ preset: String) -> String {
        "<a:prstGeom prst=\"\(preset)\"><a:avLst/></a:prstGeom>"
    }

    /// The shape's own properties: its number, its name (the element's
    /// id), its alt text and its link.
    private static func cNvPr(_ el: Element, id: Int, link: String?) -> String {
        var attributes = "id=\"\(id)\" name=\"\(SVGExporter.escape(el.id))\""
        if let alt = el.altText?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
            attributes += " descr=\"\(SVGExporter.escape(alt))\""
        }
        guard let link else { return "<p:cNvPr \(attributes)/>" }
        return "<p:cNvPr \(attributes)><a:hlinkClick \(link)/></p:cNvPr>"
    }

    private static func pictureXML(_ el: Element, id: Int, link: String?, embed: String, box: String) -> String {
        let properties = "<p:nvPicPr>\(cNvPr(el, id: id, link: link))<p:cNvPicPr/><p:nvPr/></p:nvPicPr>"
        let fill = "<p:blipFill><a:blip r:embed=\"\(embed)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>"
        return "<p:pic>\(properties)\(fill)<p:spPr>\(box)\(geometry("rect"))</p:spPr></p:pic>"
    }

    /// A rectangle, rounded or not, or an oval, filled and bordered as the
    /// element is. A rounded one's corner is a share of its shorter side,
    /// clamped to half of it as the canvas clamps it.
    private static func shapeXML(_ el: Element, preset: String, id: Int, link: String?, frame: Frame,
                                 outline custom: String? = nil) -> String {
        var outline = custom ?? geometry(preset)
        if custom == nil, preset == "roundRect" {
            let short = min(el.w, el.h)
            let adj = Int((min(el.radius ?? 0, short / 2) / short * 100_000).rounded())
            outline = "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val \(adj)\"/></a:avLst></a:prstGeom>"
        }
        var border = ""
        if let stroke = el.stroke, let width = el.strokeWidth, width > 0 {
            let paint = "<a:solidFill>\(color(stroke, opacity: el.opacity))</a:solidFill>"
            // Dots with round ends, as the canvas draws them and the line
            // rule writes them, on both phones.
            let cap = BorderDash.kept(el.dash) == "dotted" ? " cap=\"rnd\"" : ""
            border = "<a:ln w=\"\(emu(width * frame.unit))\"\(cap)>\(paint)\(dashXML(el.dash))</a:ln>"
        }
        let properties = "<p:nvSpPr>\(cNvPr(el, id: id, link: link))<p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
        let look = [elementBox(el, frame: frame), outline, fillXML(el.fill, opacity: el.opacity), border].joined()
        return "<p:sp>\(properties)<p:spPr>\(look)</p:spPr></p:sp>"
    }

    /// A built library shape's outline (ShapeGeometry): PowerPoint's preset
    /// where one draws it the same (presetGeometry), else in its own space
    /// as a free-form geometry on its box — the path the canvas draws, its
    /// arcs as cubics. A plain rectangle where it has none.
    static func builtGeometry(_ el: Element, frame: Frame) -> String {
        if let preset = presetGeometry(el) { return preset }
        guard let d = ShapeGeometry.outline(el) else { return geometry("rect") }
        let w = max(1, emu(el.w * frame.unit))
        let h = max(1, emu(el.h * frame.unit))
        func pt(_ p: CGPoint) -> String {
            "<a:pt x=\"\(emu(Double(p.x) * frame.unit))\" y=\"\(emu(Double(p.y) * frame.unit))\"/>"
        }
        var path = "<a:path w=\"\(w)\" h=\"\(h)\">"
        for step in steps(of: SVGPath.parse(d)) {
            switch step {
            case .move(let p): path += "<a:moveTo>\(pt(p))</a:moveTo>"
            case .line(let p): path += "<a:lnTo>\(pt(p))</a:lnTo>"
            case .cubic(let a, let b, let p): path += "<a:cubicBezTo>\(pt(a))\(pt(b))\(pt(p))</a:cubicBezTo>"
            case .close: path += "<a:close/>"
            }
        }
        path += "</a:path>"
        return "<a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l=\"0\" t=\"0\" r=\"r\" b=\"b\"/>" +
            "<a:pathLst>\(path)</a:pathLst></a:custGeom>"
    }

    /// PowerPoint's preset for a built shape that draws exactly as it, with
    /// no corners rounded, as the Android twin's presetOf: the triangle and
    /// the diamond as they are; the parallelogram, the trapezoid and the
    /// chevron with their adj, the slant or point as a share of the shorter
    /// side, × 100000. Nil for every other shape.
    static func presetGeometry(_ el: Element) -> String? {
        guard !((el.radius ?? 0) > 0), let id = el.shapeId else { return nil }
        let short = min(el.w, el.h)
        func adjusted(_ prst: String, _ share: Double) -> String? {
            guard short > 0 else { return nil }
            let adj = Int((share * el.w / short * 100_000).rounded())
            return "<a:prstGeom prst=\"\(prst)\"><a:avLst><a:gd name=\"adj\" fmla=\"val \(adj)\"/></a:avLst></a:prstGeom>"
        }
        switch id {
        case "triangle", "diamond": return geometry(id)
        case "parallelogram": return adjusted("parallelogram", 0.25)
        case "trapezoid": return adjusted("trapezoid", 0.2)
        case "chevron": return adjusted("chevron", ShapeGeometry.value(id, el.shapeParams, "notch"))
        default: return nil
        }
    }

    /// `rects`, in `el`'s own space, as one free-form shape on its box,
    /// turned with it, filled with `colour` at its opacity and unbordered:
    /// a QR code's background, or its modules a rectangle a run — as the
    /// Android twin writes them.
    private static func rectanglesXML(_ el: Element, properties: String, rects: [CGRect], colour: String,
                                      frame: Frame) -> String {
        let w = max(1, emu(el.w * frame.unit))
        let h = max(1, emu(el.h * frame.unit))
        func pt(_ x: Double, _ y: Double) -> String {
            "<a:pt x=\"\(emu(x * frame.unit))\" y=\"\(emu(y * frame.unit))\"/>"
        }
        var path = "<a:path w=\"\(w)\" h=\"\(h)\">"
        for r in rects {
            let x0 = Double(r.minX), y0 = Double(r.minY), x1 = Double(r.maxX), y1 = Double(r.maxY)
            path += "<a:moveTo>\(pt(x0, y0))</a:moveTo>"
            path += "<a:lnTo>\(pt(x1, y0))</a:lnTo><a:lnTo>\(pt(x1, y1))</a:lnTo><a:lnTo>\(pt(x0, y1))</a:lnTo>"
            path += "<a:close/>"
        }
        path += "</a:path>"
        let geometry = "<a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l=\"0\" t=\"0\" r=\"r\" b=\"b\"/>" +
            "<a:pathLst>\(path)</a:pathLst></a:custGeom>"
        let paint = "<a:solidFill>\(color(colour, opacity: el.opacity))</a:solidFill><a:ln><a:noFill/></a:ln>"
        let shape = "<p:nvSpPr>\(properties)<p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
        return "<p:sp>\(shape)<p:spPr>\(elementBox(el, frame: frame))\(geometry)\(paint)</p:spPr></p:sp>"
    }

    /// A barcode's shapes: its background, a shape of its own under the
    /// bars, the bars, which carry the element's name and link, and its
    /// words, a text box of their own turned with it — as the Android twin
    /// writes them.
    private static func barcodeXML(_ el: Element, _ bars: Barcodes.Drawing, id: Int, nextId: inout Int, link: String?,
                                   design: Design, frame: Frame, rels: inout Relationships) -> [String] {
        var out: [String] = []
        var barsId = id
        if let paper = bars.style.background, let box = bars.background {
            let properties = "<p:cNvPr id=\"\(id)\" name=\"\(SVGExporter.escape(el.id)) background\"/>"
            out.append(rectanglesXML(el, properties: properties, rects: [box], colour: paper, frame: frame))
            barsId = nextId
            nextId += 1
        }
        if !bars.bars.isEmpty {
            out.append(rectanglesXML(el, properties: cNvPr(el, id: barsId, link: link), rects: bars.bars,
                                     colour: bars.style.color, frame: frame))
        }
        if let words = Barcodes.captionElement(el, bars, onPage: true) {
            out.append(textXML(words, id: nextId, link: nil, design: design, slides: [:], frame: frame, rels: &rels))
            nextId += 1
        }
        return out
    }

    /// Warped words as their outlines, a shape for each colour piece
    /// (`parts`, nil the text's own): the first with `id` and the element's
    /// name and link, each after it with the next id and the name with its
    /// place among the pieces.
    private static func warpedXML(_ el: Element, parts: [TextOutliner.InkedPath], id: Int, nextId: inout Int,
                                  link: String?, frame: Frame) -> [String] {
        let ink = el.color ?? "#1f2430"
        var out: [String] = []
        for (k, part) in parts.enumerated() {
            let pieceSteps = steps(of: part.path)
            if pieceSteps.isEmpty { continue }
            var properties = cNvPr(el, id: id, link: link)
            if !out.isEmpty {
                properties = "<p:cNvPr id=\"\(nextId)\" name=\"\(SVGExporter.escape(el.id)) \(k)\"/>"
                nextId += 1
            }
            out.append(outlineXML(el, properties: properties, steps: pieceSteps, colour: part.color ?? ink, frame: frame))
        }
        return out
    }

    /// `steps` (CodeGenerator.outline), in `el`'s own space, as one
    /// free-form shape on its box as rectanglesXML writes one: a styled QR
    /// code's dots and eyes, curves as cubics, each eye's hole wound against
    /// its ring.
    private static func outlineXML(_ el: Element, properties: String, steps: [CodeGenerator.Step], colour: String,
                                   frame: Frame) -> String {
        let w = max(1, emu(el.w * frame.unit))
        let h = max(1, emu(el.h * frame.unit))
        func pt(_ p: CGPoint) -> String {
            "<a:pt x=\"\(emu(Double(p.x) * frame.unit))\" y=\"\(emu(Double(p.y) * frame.unit))\"/>"
        }
        var path = "<a:path w=\"\(w)\" h=\"\(h)\">"
        for step in steps {
            switch step {
            case .move(let p): path += "<a:moveTo>\(pt(p))</a:moveTo>"
            case .line(let p): path += "<a:lnTo>\(pt(p))</a:lnTo>"
            case .cubic(let a, let b, let p): path += "<a:cubicBezTo>\(pt(a))\(pt(b))\(pt(p))</a:cubicBezTo>"
            case .close: path += "<a:close/>"
            }
        }
        path += "</a:path>"
        let geometry = "<a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l=\"0\" t=\"0\" r=\"r\" b=\"b\"/>" +
            "<a:pathLst>\(path)</a:pathLst></a:custGeom>"
        let paint = "<a:solidFill>\(color(colour, opacity: el.opacity))</a:solidFill><a:ln><a:noFill/></a:ln>"
        let shape = "<p:nvSpPr>\(properties)<p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
        return "<p:sp>\(shape)<p:spPr>\(elementBox(el, frame: frame))\(geometry)\(paint)</p:spPr></p:sp>"
    }

    /// `path` as the steps outlineXML writes: its lines, its curves as
    /// cubics (a quadratic raised to one), its closes.
    /// Two thirds of the way from `from` toward `control`: a quadratic's
    /// control point as one of the matching cubic's.
    private static func twoThirds(_ from: CGPoint, toward control: CGPoint) -> CGPoint {
        let x: CGFloat = from.x + (control.x - from.x) * 2 / 3
        let y: CGFloat = from.y + (control.y - from.y) * 2 / 3
        return CGPoint(x: x, y: y)
    }

    static func steps(of path: CGPath) -> [CodeGenerator.Step] {
        var out: [CodeGenerator.Step] = []
        var current = CGPoint.zero
        path.applyWithBlock { (element: UnsafePointer<CGPathElement>) in
            let e: CGPathElement = element.pointee
            switch e.type {
            case .moveToPoint:
                current = e.points[0]
                out.append(.move(current))
            case .addLineToPoint:
                current = e.points[0]
                out.append(.line(current))
            case .addQuadCurveToPoint:
                let c: CGPoint = e.points[0], p: CGPoint = e.points[1]
                out.append(.cubic(twoThirds(current, toward: c), twoThirds(p, toward: c), p))
                current = p
            case .addCurveToPoint:
                current = e.points[2]
                out.append(.cubic(e.points[0], e.points[1], current))
            case .closeSubpath:
                out.append(.close)
            @unknown default:
                break
            }
        }
        return out
    }

    /// A preset line across the middle of the element's box, with its
    /// ends — swapped when the line is flipped across.
    private static func lineXML(_ el: Element, id: Int, link: String?, frame: Frame) -> String {
        let thickness = max(el.thickness ?? 4, 0.5)
        if LineRoutes.keepsLevel(el) {
            let caps = "\(lineEnd("headEnd", el.startCap, scale: el.capScale))\(lineEnd("tailEnd", el.endCap, scale: el.capScale))"
            return connectorXML(el, id: id, link: link, frame: frame, caps: caps, thickness: thickness)
        }
        var ends = [el.startCap, el.endCap]
        if el.flipH { ends.reverse() }
        let dash = dashXML(el.dash)
        let paint = "<a:solidFill>\(color(el.color ?? "#1f2430", opacity: el.opacity))</a:solidFill>"
        let capped = "\(lineEnd("headEnd", ends[0], scale: el.capScale))\(lineEnd("tailEnd", ends[1], scale: el.capScale))"
        let stroke = "<a:ln w=\"\(emu(thickness * frame.unit))\" cap=\"rnd\">\(paint)\(dash)\(capped)</a:ln>"
        let box = xfrm(x: el.x, y: el.y + el.h / 2, w: el.w, h: 0, rotation: el.rotation, frame: frame)
        let properties = "<p:nvSpPr>\(cNvPr(el, id: id, link: link))<p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
        return "<p:sp>\(properties)<p:spPr>\(box)\(geometry("line"))\(stroke)</p:spPr></p:sp>"
    }

    /// An elbowed or curved line as PowerPoint's connector between its two
    /// ends on the slide: bentConnector3, its corner where the bend puts it
    /// (adj1, from the start), or curvedConnector3 — PowerPoint's S-curve
    /// between the ends, which has no bow of its own to set. Flipped so it
    /// runs from the start to the end, with the line's dashes and its ends
    /// (`caps`) as a straight line has them. As the Android twin writes it.
    private static func connectorXML(_ el: Element, id: Int, link: String?, frame: Frame,
                                     caps: String, thickness: Double) -> String {
        let ends = LineRoutes.ends(of: el)
        let start = ends.start, end = ends.end
        let x = Double(min(start.x, end.x)), y = Double(min(start.y, end.y))
        var flips = ""
        if end.x < start.x { flips += " flipH=\"1\"" }
        if end.y < start.y { flips += " flipV=\"1\"" }
        let off = "<a:off x=\"\(emu(x * frame.unit + frame.dx))\" y=\"\(emu(y * frame.unit + frame.dy))\"/>"
        let cx = max(0, emu(abs(Double(end.x - start.x)) * frame.unit))
        let cy = max(0, emu(abs(Double(end.y - start.y)) * frame.unit))
        let box = "<a:xfrm\(flips)>\(off)<a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm>"
        var geometry = "<a:prstGeom prst=\"curvedConnector3\"><a:avLst/></a:prstGeom>"
        if LineRoutes.routeType(of: el) == .elbow {
            let adj = Int(((1 + LineRoutes.bend(of: el)) / 2 * 100_000).rounded())
            geometry = "<a:prstGeom prst=\"bentConnector3\"><a:avLst><a:gd name=\"adj1\" fmla=\"val \(adj)\"/></a:avLst></a:prstGeom>"
        }
        let paint = "<a:solidFill>\(color(el.color ?? "#1f2430", opacity: el.opacity))</a:solidFill>"
        let stroke = "<a:ln w=\"\(emu(thickness * frame.unit))\" cap=\"rnd\">\(paint)\(dashXML(el.dash))\(caps)</a:ln>"
        let properties = "<p:nvCxnSpPr>\(cNvPr(el, id: id, link: link))<p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>"
        return "<p:cxnSp>\(properties)<p:spPr>\(box)\(geometry)\(stroke)</p:spPr></p:cxnSp>"
    }

    /// A line's or a border's dash as PowerPoint's preset: dashed is
    /// "dash", dotted "sysDot", and solid nothing.
    static func dashXML(_ dash: String?) -> String {
        switch dash {
        case "dashed": return "<a:prstDash val=\"dash\"/>"
        case "dotted": return "<a:prstDash val=\"sysDot\"/>"
        default: return ""
        }
    }

    /// A line's end as PowerPoint's nearest (LineEnds.pptxType), sized
    /// by its capScale (LineEnds.pptxSize) when that is not 1.
    private static func lineEnd(_ tag: String, _ cap: String?, scale: Double?) -> String {
        guard let type = LineEnds.pptxType(LineEnds.kind(cap)) else { return "" }
        guard let size = LineEnds.pptxSize(LineEnds.scale(scale)) else { return "<a:\(tag) type=\"\(type)\"/>" }
        return "<a:\(tag) type=\"\(type)\" w=\"\(size)\" len=\"\(size)\"/>"
    }

    // MARK: text

    /// A stretch of one paragraph in one style.
    struct TextRun: Equatable {
        var text: String
        /// Its style: the box's own (bold at weight 700 and up) and its
        /// words' together.
        var style = RichText.Style()
        /// A colour of its own ("#rrggbb"); nil is the box's.
        var color: String?
        /// The box's type size times this; nil is the box's own.
        var scale: Double?
        /// A font key of its own; nil is the box's face.
        var font: String? = nil
        /// A link a reader may follow (Links.followable), or one to a page
        /// (Links.pageLink), which the slide resolves; nil is none.
        var link: String? = nil
        /// A weight of its own (Spans); nil is the box's.
        var weight: Int? = nil
        /// A marker behind its words (Spans); nil is none.
        var highlight: String? = nil
        /// Raised or lowered (Spans' script); nil is on the line.
        var script: String? = nil
    }

    /// The a:rPr baseline a script is written with: raised 30%, lowered
    /// 25%, as PowerPoint's own superscript and subscript.
    static func baseline(_ script: String?) -> String? {
        if script == Spans.raised { return "30000" }
        if script == Spans.lowered { return "-25000" }
        return nil
    }

    /// The words as typed — page numbers filled in, the inline style marks
    /// read, before any capitals, and without a list's markers, which
    /// PowerPoint draws for each paragraph itself (paragraphProperties) — as
    /// paragraphs of runs: cut at every line break and every change of
    /// style, colour, size, font, weight or link, and joined again where
    /// neighbours turn out the same. A linked word with no colour of its
    /// own is in the link colour, as the canvas draws it. A word with a
    /// weight of its own (Spans) is bold from 600, and its run names its
    /// cut (typeface(_:in:weight:)); a word with a slant of its own is
    /// italic by it — the rule both phones share.
    static func paragraphs(of el: Element) -> [[TextRun]] {
        var unlisted = el
        if TextLists.isList(el) {
            unlisted.setLines(TextLists.lines(el).map { TextParagraph(level: $0.level, align: $0.align) })
        }
        let marked = FontLibrary.markedDisplayText(for: unlisted, pageNumber: nil, pageCount: nil)
        let parsed = RichText.parse(marked)
        let spans = FontLibrary.displaySpans(for: unlisted, marked: marked)
        // At the weight and italic the box is drawn at: a text an earlier
        // build set in a Bold or Italic file is bold or italic here too
        // (FontLibrary.weight(of:)), as on the Android twin.
        let box = RichText.Style(bold: FontLibrary.weight(of: el) >= 700, italic: FontLibrary.isItalic(el),
                                 underline: el.underline == true)
        let ns = parsed.plain as NSString
        let length = ns.length
        var cuts: Set<Int> = [0, length]
        for run in parsed.runs {
            cuts.insert(run.range.location)
            cuts.insert(NSMaxRange(run.range))
        }
        for span in spans {
            cuts.insert(min(max(span.start, 0), length))
            cuts.insert(min(max(span.end, 0), length))
        }
        for index in 0..<length where ns.character(at: index) == 0x0A {
            cuts.insert(index)
            cuts.insert(index + 1)
        }
        let sorted = cuts.filter { $0 >= 0 && $0 <= length }.sorted()
        var paragraphs: [[TextRun]] = [[]]
        for (from, to) in zip(sorted, sorted.dropFirst()) where to > from {
            let piece = ns.substring(with: NSRange(location: from, length: to - from))
            if piece == "\n" {
                paragraphs.append([])
                continue
            }
            let own = parsed.runs.first { NSLocationInRange(from, $0.range) }?.style ?? RichText.Style()
            let span = spans.first { $0.start <= from && from < $0.end }
            let bold = span?.weight.map { $0 >= 600 } ?? box.bold
            let italic = span?.italic ?? box.italic
            let style = RichText.Style(bold: bold || own.bold, italic: italic || own.italic,
                                       underline: box.underline || own.underline, strike: own.strike)
            let linked = span?.link != nil ? Spans.linkColour : nil
            let run = TextRun(text: piece, style: style, color: span?.color ?? linked, scale: span?.scale,
                              font: span?.font, link: Links.followable(span?.link) ?? Links.pageId(span?.link).map(Links.pageLink),
                              weight: span?.weight, highlight: span?.highlight, script: span?.script)
            let last = paragraphs.count - 1
            if var before = paragraphs[last].last, before.style == run.style, before.color == run.color,
               before.scale == run.scale, before.font == run.font, before.link == run.link,
               before.weight == run.weight, before.highlight == run.highlight, before.script == run.script {
                before.text += piece
                paragraphs[last][paragraphs[last].count - 1] = before
            } else {
                paragraphs[last].append(run)
            }
        }
        return paragraphs
    }

    /// The name of the family a text is set in: a font of your own by the
    /// name the design records for it, any other by the picker's name.
    static func typeface(_ key: String?, in design: Design) -> String {
        if CustomFonts.isCustom(key), let name = CustomFonts.name(in: design, of: key) { return name }
        return FontLibrary.of(key).name
    }

    /// The face a word with a `weight` of its own names: its family's name
    /// and the cut's English name ("Montserrat Light", "Montserrat Black";
    /// a weight with no name by its number) — a Regular, or no weight of
    /// its own, the family's name alone. Both phones' rule.
    static func typeface(_ key: String?, in design: Design, weight: Int?) -> String {
        let family = typeface(key, in: design)
        guard let weight, weight != 400 else { return family }
        return "\(family) \(FontLibrary.englishWeightNames[weight] ?? String(weight))"
    }

    /// The photo a text's letters are full of, as its slide holds it: its
    /// media's relationship id, and its pixels for the window.
    struct PouredPhoto {
        var embed: String
        var size: CGSize
    }

    /// A text box, its words' links going into `rels` run by run; its
    /// letters full of `photo`, or in `ink` (the photo's average colour)
    /// where the effect cannot hold it.
    private static func textXML(_ el: Element, id: Int, link: String?, design: Design, slides: [String: Int],
                                frame: Frame, rels: inout Relationships, photo: PouredPhoto? = nil,
                                ink: String? = nil) -> String {
        // The size the canvas draws it at: fitted type at the size that fits.
        let size = FontLibrary.effectiveFontSize(for: el)
        var anchor = ""
        switch el.vAlign {
        case "middle": anchor = " anchor=\"ctr\""
        case "bottom": anchor = " anchor=\"b\""
        default: anchor = ""
        }
        var body = ""
        let properties = paragraphProperties(el, em: size * frame.unit)
        // What the effect, the shadow, the gradient letters and the drop cap
        // put in every run, the box's own warp and column in its body.
        let style = styledParts(el, size: size, frame: frame, photo: photo, average: ink)
        let cap: Double? = FontLibrary.dropCapLayout(for: el) != nil ? FontLibrary.dropCapLines : nil
        for (line, runs) in paragraphs(of: el).enumerated() {
            var content = runs.isEmpty ? "<a:endParaRPr sz=\"\(typeSize(size * frame.unit))\"/>" : ""
            for (k, run) in runs.enumerated() {
                let face = typeface(run.font ?? el.fontFamily, in: design, weight: run.weight)
                let onClick = clickAttributes(run.link, design: design, slides: slides, rels: &rels)
                // A drop cap: the first letter a run of its own, three
                // times the size.
                if let cap, line == 0, k == 0, let first = run.text.first {
                    var letter = run
                    letter.text = String(first)
                    content += runXML(letter, el: el, size: size * cap, face: face, link: onClick, unit: frame.unit,
                                      style: style, ink: ink)
                    var rest = run
                    rest.text = String(run.text.dropFirst())
                    if rest.text.isEmpty { continue }
                    content += runXML(rest, el: el, size: size, face: face, link: onClick, unit: frame.unit,
                                      style: style, ink: ink)
                    continue
                }
                content += runXML(run, el: el, size: size, face: face, link: onClick, unit: frame.unit,
                                  style: style, ink: ink)
            }
            let pPr = line < properties.count ? properties[line] : ""
            body += "<a:p>\(pPr)\(content)</a:p>"
        }
        let shape = "<p:nvSpPr>\(cNvPr(el, id: id, link: link))<p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>"
        let look = "<p:spPr>\(elementBox(el, frame: frame))\(geometry("rect"))<a:noFill/></p:spPr>"
        let bodyAttributes = "lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"\(anchor)\(style.vert)"
        let bodyProperties = style.warp.isEmpty
            ? "<a:bodyPr \(bodyAttributes)/><a:lstStyle/>"
            : "<a:bodyPr \(bodyAttributes)>\(style.warp)</a:bodyPr><a:lstStyle/>"
        return "<p:sp>\(shape)\(look)<p:txBody>\(bodyProperties)\(body)</p:txBody></p:sp>"
    }

    /// What styled text puts in its runs and its body (styledParts): an
    /// a:ln before the fill, a fill of its own (gradient letters, or
    /// Hollow's none), the effectLst and highlight after it, and the body's
    /// vert and warp.
    struct Styled: Equatable {
        var line = ""
        var fill: String?
        var effects = ""
        var vert = ""
        var warp = ""
    }

    /// The closest DrawingML has to `el`'s styling, for type drawn `size`
    /// high — the mapping both phones share, over the same test rows:
    ///
    ///  - Shadow: effectLst outerShdw, blurRad the cast's blur, dist and dir
    ///    its offset's length and heading, algn ctr, its colour at its alpha
    ///  - an element's shadow the same, where the effect casts none
    ///  - Lift: a soft outerShdw straight down (dir 90°)
    ///  - Outline ("outlined"): a:ln of the stroke's width and colour, and
    ///    the normal fill
    ///  - Hollow ("outline"): a:ln in the ink, and noFill
    ///  - Neon: effectLst glow, rad the blur, the ink at 85%
    ///  - Highlight: a:highlight in the bar's colour, on each run
    ///  - gradient letters: gradFill, where the effect takes a gradient
    ///  - a curve: prstTxWarp textArchUp, textArchDown when negative, adj
    ///    the arc's degrees in 60000ths; past half a ring, WordArt's
    ///    textCircle, as it comes — the words still editable
    ///  - vertical: vert eaVert for CJK words, else wordArtVert
    ///  - letters full of a photo (`photo`, its media's relationship id and
    ///    pixels): a blipFill, srcRect cropping it to the window PhotoFills
    ///    gives (in 1000ths of a percent off each side), stretched to the
    ///    box — where the effect takes a photo; else the letters in the
    ///    photo's `average` colour, which is also the ink the effect draws in
    static func styledParts(_ el: Element, size: Double, frame: Frame, photo: PouredPhoto? = nil,
                            average: String? = nil) -> Styled {
        let ink = average ?? el.color ?? "#1f2430"
        let effect = TextEffect.from(el.effect)
        let fx = TextEffect.resolve(el.effect, fontSize: size, ink: ink)
        let unit = frame.unit
        var out = Styled()
        if effect == .outlined, fx.stroke > 0 {
            out.line = "<a:ln w=\"\(emu(fx.stroke * unit))\"><a:solidFill>\(color(fx.color, opacity: el.opacity))</a:solidFill></a:ln>"
        }
        if effect == .outline {
            out.line = "<a:ln w=\"\(emu(fx.stroke * unit))\"><a:solidFill>\(color(ink, opacity: el.opacity))</a:solidFill></a:ln>"
            out.fill = "<a:noFill/>"
        }
        if let paint = el.textFill, paint.kind == "gradient", let stops = paint.stops, !stops.isEmpty,
           effect.takesGradient, out.fill == nil {
            out.fill = gradientFill(paint, opacity: el.opacity)
        }
        if let paint = el.textFill, paint.isPhoto, effect.takesPhoto, let photo, out.fill == nil {
            out.fill = blipFill(photo.embed, size: photo.size, paint: paint, w: el.w, h: el.h)
        }
        var effects = ""
        if effect == .neon, fx.casts {
            effects += "<a:glow rad=\"\(emu(fx.blur * unit))\">\(color(fx.color, opacity: fx.alpha))</a:glow>"
        } else if fx.casts {
            effects += outerShadow(blur: fx.blur, dx: fx.dx, dy: fx.dy, colour: fx.color, alpha: fx.alpha, unit: unit)
        } else if let shadow = el.shadow {
            effects += outerShadow(blur: shadow.blur, dx: shadow.offsetX, dy: shadow.offsetY,
                                   colour: shadow.color, alpha: shadow.opacity, unit: unit)
        }
        out.effects = effects.isEmpty ? "" : "<a:effectLst>\(effects)</a:effectLst>"
        if effect == .highlight {
            out.effects += "<a:highlight>\(color(fx.color, opacity: fx.alpha))</a:highlight>"
        }
        if let curve = el.curve, abs(curve) > TextPaths.halfCurve {
            out.warp = "<a:prstTxWarp prst=\"textCircle\"><a:avLst/></a:prstTxWarp>"
        } else if let curve = el.curve, abs(curve) >= TextOutliner.straightBelowDegrees {
            let preset = curve < 0 ? "textArchDown" : "textArchUp"
            let adj = Int((abs(curve) * 60000).rounded())
            out.warp = "<a:prstTxWarp prst=\"\(preset)\"><a:avLst><a:gd name=\"adj\" fmla=\"val \(adj)\"/></a:avLst></a:prstTxWarp>"
        }
        if el.vertical == true {
            let column = TextOutliner.hasCJK(RichText.strip(el.text ?? "")) ? "eaVert" : "wordArtVert"
            out.vert = " vert=\"\(column)\""
        }
        return out
    }

    /// A photo as a run's fill: the media `embed`, cropped by srcRect to the
    /// part of it the window shows over a `w` × `h` box (PhotoFills.window)
    /// — each side's share cut away, in 1000ths of a percent, written only
    /// when something is — stretched to the letters.
    static func blipFill(_ embed: String, size: CGSize, paint: Paint, w: Double, h: Double) -> String {
        let window = PhotoFills.window(imageW: Double(size.width), imageH: Double(size.height), boxW: w, boxH: h, paint: paint)
        func share(_ cut: Double, _ whole: Double) -> Int {
            whole > 0 ? max(0, Int((cut / whole * 100_000).rounded())) : 0
        }
        let cuts: [(String, Int)] = [
            ("l", share(-Double(window.minX), Double(window.width))), ("t", share(-Double(window.minY), Double(window.height))),
            ("r", share(Double(window.maxX) - w, Double(window.width))), ("b", share(Double(window.maxY) - h, Double(window.height))),
        ].filter { $0.1 > 0 }
        let srcRect = cuts.isEmpty ? "" : "<a:srcRect" + cuts.map { " \($0.0)=\"\($0.1)\"" }.joined() + "/>"
        return "<a:blipFill><a:blip r:embed=\"\(embed)\"/>\(srcRect)<a:stretch><a:fillRect/></a:stretch></a:blipFill>"
    }

    /// A gradient over the letters: every stop, along the CSS angle the
    /// model stores less 90, as fillXML lays a shape's.
    private static func gradientFill(_ paint: Paint, opacity: Double) -> String {
        let stops = (paint.stops ?? []).map { stop -> String in
            let at = Int((min(max(stop.offset, 0), 1) * 100_000).rounded())
            return "<a:gs pos=\"\(at)\">\(color(stop.color, opacity: opacity))</a:gs>"
        }.joined()
        return "<a:gradFill><a:gsLst>\(stops)</a:gsLst><a:lin ang=\"\(angle((paint.angle ?? 0) - 90))\"/></a:gradFill>"
    }

    /// An outer shadow `blur` soft, cast `dx` across and `dy` down (its
    /// length and heading, clockwise from the right, as the direction
    /// setting and DrawingML both turn), in `colour` at `alpha`, at `unit`.
    private static func outerShadow(blur: Double, dx: Double, dy: Double, colour: String, alpha: Double,
                                    unit: Double) -> String {
        let distance = (dx * dx + dy * dy).squareRoot()
        let degrees = atan2(dy, dx) * 180 / .pi
        return "<a:outerShdw blurRad=\"\(emu(blur * unit))\" dist=\"\(emu(distance * unit))\" dir=\"\(angle(degrees))\" algn=\"ctr\">"
            + "\(color(colour, opacity: alpha))</a:outerShdw>"
    }

    /// Each line's paragraph properties: aligned as the line is
    /// (TextLists.alignOf — the box's, unless it has its own), at its list
    /// level, pushed in a level's ems (`em` a type size on the slide) and
    /// its item's bullet or number hanging in the marker's room before its
    /// words, as PowerPoint's own — a bullet by its character, a number,
    /// letter or numeral counted on from the item's place. Empty for a
    /// left-aligned plain line. The Android twin's PptxWriter, attribute
    /// for attribute.
    static func paragraphProperties(_ el: Element, em: Double) -> [String] {
        func algn(_ align: String) -> String {
            switch align {
            case "left": return ""
            case "right": return " algn=\"r\""
            case "justify": return " algn=\"just\""
            default: return " algn=\"ctr\""
            }
        }
        let items = TextLists.items(el)
        return TextLists.lines(el).enumerated().map { line, paragraph -> String in
            let indent = Double(paragraph.level) * FontLibrary.indentEm * em
            let hang = paragraph.isListed ? FontLibrary.markerEm * em : 0
            var attributes = algn(TextLists.alignOf(el, line))
            if paragraph.level > 0 { attributes += " lvl=\"\(paragraph.level)\"" }
            if indent + hang > 0 { attributes += " marL=\"\(emu(indent + hang))\"" }
            if hang > 0 { attributes += " indent=\"\(emu(-hang))\"" }
            let bullet = line < items.count ? items[line].map(bulletXML) ?? "" : ""
            if !bullet.isEmpty { return "<a:pPr\(attributes)>\(bullet)</a:pPr>" }
            return attributes.isEmpty ? "" : "<a:pPr\(attributes)/>"
        }
    }

    /// A list item's bullet or number as PowerPoint draws it.
    private static func bulletXML(_ item: TextLists.Item) -> String {
        guard item.list != "bullet" else {
            let char = SVGExporter.escape(item.marker.trimmingCharacters(in: .whitespaces))
            return "<a:buFont typeface=\"Arial\"/><a:buChar char=\"\(char)\"/>"
        }
        let scheme: String
        switch TextLists.counting(item.list, level: item.depth) {
        case 0: scheme = "arabicPeriod"
        case 1: scheme = "alphaLcPeriod"
        default: scheme = "romanLcPeriod"
        }
        return "<a:buAutoNum type=\"\(scheme)\" startAt=\"\(item.index)\"/>"
    }

    /// One run: bold, italic, underlined or struck as its style is, in
    /// capitals with the box, its letter spacing as spc (px × 75), its
    /// colour — its own or the box's — faded by the element's opacity, its
    /// face, and its link (`link`, a relationship id) on a click; the
    /// styling's line before the fill, its own fill in place of the
    /// colour, and its effects after (`style`).
    private static func runXML(_ run: TextRun, el: Element, size: Double, face: String, link: String?,
                               unit: Double, style: Styled = Styled(), ink: String? = nil) -> String {
        var attributes = " sz=\"\(typeSize(size * (run.scale ?? 1) * unit))\""
        if run.style.bold { attributes += " b=\"1\"" }
        if run.style.italic { attributes += " i=\"1\"" }
        if run.style.underline { attributes += " u=\"sng\"" }
        if run.style.strike { attributes += " strike=\"sngStrike\"" }
        if let shift = baseline(run.script) { attributes += " baseline=\"\(shift)\"" }
        if el.uppercase == true { attributes += " cap=\"all\"" }
        let tracking = (el.letterSpacing ?? 0) * unit
        let spacing = tracking.isFinite ? Int((min(max(tracking, -1000), 1000) * 75).rounded()) : 0
        if spacing != 0 { attributes += " spc=\"\(spacing)\"" }
        // Under a photo a word's own colour is not drawn: the letters are
        // the photo's, or its average where the effect cannot hold it.
        let own = ink == nil ? run.color : nil
        let paint = style.fill ?? "<a:solidFill>\(color(own ?? ink ?? el.color ?? "#1f2430", opacity: el.opacity))</a:solidFill>"
        var font = "<a:latin typeface=\"\(SVGExporter.escape(face))\"/>"
        if let link { font += "<a:hlinkClick \(link)/>" }
        // A word's own marker in place of the box's Highlight, which is
        // the last of the effects (styledParts): PowerPoint takes one
        // a:highlight a run.
        var effects = style.effects
        if let mark = run.highlight {
            if let box = effects.range(of: "<a:highlight>") { effects = String(effects[..<box.lowerBound]) }
            effects += "<a:highlight>\(color(mark))</a:highlight>"
        }
        let look = style.line + paint + effects
        return "<a:r><a:rPr\(attributes)>\(look)\(font)</a:rPr><a:t>\(SVGExporter.escape(run.text))</a:t></a:r>"
    }

    // MARK: colour

    /// "#rgb", "#rrggbb" or "#rrggbbaa" as an upper-case RGB and an alpha;
    /// anything else is black.
    static func rgba(_ hex: String) -> (rgb: String, alpha: Double) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, s.allSatisfy(\.isHexDigit) else { return ("000000", 1) }
        let rgb = String(s.prefix(6)).uppercased()
        guard s.count == 8, let a = UInt8(s.suffix(2), radix: 16) else { return (rgb, 1) }
        return (rgb, Double(a) / 255)
    }

    /// A colour, with an alpha (in 1000ths of a percent) only when it is
    /// see-through: its own alpha times `opacity`.
    static func color(_ hex: String, opacity: Double = 1) -> String {
        let parts = rgba(hex)
        let alpha = Int((min(max(parts.alpha * opacity, 0), 1) * 100_000).rounded())
        guard alpha < 100_000 else { return "<a:srgbClr val=\"\(parts.rgb)\"/>" }
        return "<a:srgbClr val=\"\(parts.rgb)\"><a:alpha val=\"\(alpha)\"/></a:srgbClr>"
    }

    /// A preset shape's fill: none, a colour (the library's violet when it
    /// has none, as the canvas fills it), or a linear gradient along the
    /// CSS angle the model stores — 0° up — which DrawingML measures from
    /// the right, so 90° less.
    static func fillXML(_ fill: Paint?, opacity: Double) -> String {
        let paint = fill ?? .solid("#8b5cf6")
        switch paint.kind {
        case "none":
            return "<a:noFill/>"
        case "gradient" where (paint.stops?.count ?? 0) >= 2:
            let stops = (paint.stops ?? []).map { stop -> String in
                let at = Int((min(max(stop.offset, 0), 1) * 100_000).rounded())
                return "<a:gs pos=\"\(at)\">\(color(stop.color, opacity: opacity))</a:gs>"
            }.joined()
            return "<a:gradFill><a:gsLst>\(stops)</a:gsLst><a:lin ang=\"\(angle((paint.angle ?? 0) - 90))\"/></a:gradFill>"
        default:
            return "<a:solidFill>\(color(paint.color ?? "#8b5cf6", opacity: opacity))</a:solidFill>"
        }
    }

    // MARK: notes

    /// A notes slide of the notes as they were typed, a paragraph a line,
    /// in the notes master's body.
    static func notesXML(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            line.isEmpty ? "<a:p/>" : "<a:p><a:r><a:t>\(SVGExporter.escape(line))</a:t></a:r></a:p>"
        }.joined()
        let body = "<p:sp>\(notesPlaceholder)<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(lines)</p:txBody></p:sp>"
        return [declaration, "<p:notes \(namespaces)>", "<p:cSld><p:spTree>", groupHeader, body,
                "</p:spTree></p:cSld>", masterColours, "</p:notes>"].joined()
    }

    static func notesRels(slide number: Int) -> String {
        var rels = Relationships()
        rels.add("notesMaster", "../notesMasters/notesMaster1.xml")
        rels.add("slide", "../slides/slide\(number).xml")
        return rels.xml
    }

    // MARK: the package

    /// A file inside the deck.
    struct Part: Equatable {
        var name: String
        var xml: String
    }

    /// The parts every deck has, in the order the file holds them, before
    /// its slides: the content types first, as readers expect, then the
    /// presentation and its properties, theme, master and layout — and the
    /// notes master, with a theme of its own, when a slide has notes.
    /// `noted` says, slide by slide, which have notes.
    static func packageParts(design: Design, noted: [Bool]) -> [Part] {
        let notes = noted.contains(true)
        let presentation = presentationXML(width: design.width, height: design.height, slides: noted.count, notes: notes)
        var parts = [
            Part(name: "[Content_Types].xml", xml: contentTypes(noted: noted)),
            Part(name: "_rels/.rels", xml: rootRels),
            Part(name: "ppt/presentation.xml", xml: presentation),
            Part(name: "ppt/_rels/presentation.xml.rels", xml: presentationRels(slides: noted.count, notes: notes)),
            Part(name: "ppt/presProps.xml", xml: declaration + "<p:presentationPr \(namespaces)/>"),
            Part(name: "ppt/viewProps.xml", xml: declaration + "<p:viewPr \(namespaces)/>"),
            Part(name: "ppt/tableStyles.xml", xml: tableStyles),
            Part(name: "ppt/theme/theme1.xml", xml: theme),
            Part(name: "ppt/slideMasters/slideMaster1.xml", xml: slideMaster),
            Part(name: "ppt/slideMasters/_rels/slideMaster1.xml.rels", xml: slideMasterRels),
            Part(name: "ppt/slideLayouts/slideLayout1.xml", xml: slideLayout),
            Part(name: "ppt/slideLayouts/_rels/slideLayout1.xml.rels", xml: slideLayoutRels),
        ]
        if notes {
            parts.append(Part(name: "ppt/notesMasters/notesMaster1.xml", xml: notesMaster))
            parts.append(Part(name: "ppt/notesMasters/_rels/notesMaster1.xml.rels", xml: notesMasterRels))
            parts.append(Part(name: "ppt/theme/theme2.xml", xml: theme))
        }
        return parts
    }

    /// Every entry's name in the order the file holds them when every
    /// picture draws: the package's parts, then each slide's pictures, the
    /// slide with its relationships, and its notes slide.
    static func entryNames(design: Design, indices: [Int], styled: Bool = true,
                           photos: PhotoLookup = .stored) -> [String] {
        let pages = indices.map { design.pages[$0] }
        let noted = pages.map { notesText(design: design, page: $0, styled: styled) != nil }
        var names = packageParts(design: design, noted: noted).map(\.name)
        var image = 1
        for (n, page) in pages.enumerated() {
            let pictures = media(design: design, page: page, firstImage: image, styled: styled, photos: photos)
            image += pictures.count
            names += pictures.map { "ppt/media/\($0.name)" }
            names += slideEntryNames(number: n + 1, notes: noted[n])
        }
        return names
    }

    static func slideEntryNames(number: Int, notes: Bool) -> [String] {
        let names = ["ppt/slides/slide\(number).xml", "ppt/slides/_rels/slide\(number).xml.rels"]
        guard notes else { return names }
        return names + ["ppt/notesSlides/notesSlide\(number).xml", "ppt/notesSlides/_rels/notesSlide\(number).xml.rels"]
    }

    /// The parts' types: the presentation's own parts, the notes master's
    /// when there are notes, then each slide followed by its notes slide.
    static func contentTypes(noted: [Bool]) -> String {
        let main = "application/vnd.openxmlformats-officedocument.presentationml"
        func part(_ name: String, _ type: String) -> String {
            "<Override PartName=\"/\(name)\" ContentType=\"\(type)\"/>"
        }
        var entries = [
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>",
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>",
            "<Default Extension=\"png\" ContentType=\"image/png\"/>",
            "<Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>",
            part("ppt/presentation.xml", "\(main).presentation.main+xml"),
            part("ppt/presProps.xml", "\(main).presProps+xml"),
            part("ppt/viewProps.xml", "\(main).viewProps+xml"),
            part("ppt/tableStyles.xml", "\(main).tableStyles+xml"),
            part("ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
            part("ppt/slideMasters/slideMaster1.xml", "\(main).slideMaster+xml"),
            part("ppt/slideLayouts/slideLayout1.xml", "\(main).slideLayout+xml"),
        ]
        if noted.contains(true) {
            entries.append(part("ppt/notesMasters/notesMaster1.xml", "\(main).notesMaster+xml"))
            entries.append(part("ppt/theme/theme2.xml", "application/vnd.openxmlformats-officedocument.theme+xml"))
        }
        for (n, notes) in noted.enumerated() {
            entries.append(part("ppt/slides/slide\(n + 1).xml", "\(main).slide+xml"))
            if notes {
                entries.append(part("ppt/notesSlides/notesSlide\(n + 1).xml", "\(main).notesSlide+xml"))
            }
        }
        return declaration + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + entries.joined() + "</Types>"
    }

    static var rootRels: String {
        var rels = Relationships()
        rels.add("officeDocument", "ppt/presentation.xml")
        return rels.xml
    }

    /// The presentation: its master as rId1, its slides rId2 onwards, then
    /// the notes master when there is one; slides at the design's size,
    /// scaled into what PowerPoint opens (slideScale).
    static func presentationXML(width: Double, height: Double, slides: Int, notes: Bool) -> String {
        let scale = slideScale(width: width, height: height)
        let ids = (0..<slides).map { "<p:sldId id=\"\(256 + $0)\" r:id=\"rId\($0 + 2)\"/>" }.joined()
        let notesList = notes ? "<p:notesMasterIdLst><p:notesMasterId r:id=\"rId\(slides + 2)\"/></p:notesMasterIdLst>" : ""
        let edges = "cx=\"\(slideEdge(width, scale: scale))\" cy=\"\(slideEdge(height, scale: scale))\""
        let size = "<p:sldSz \(edges)/><p:notesSz cx=\"6858000\" cy=\"9144000\"/>"
        return [declaration, "<p:presentation \(namespaces)>",
                "<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst>",
                notesList, "<p:sldIdLst>\(ids)</p:sldIdLst>", size, "</p:presentation>"].joined()
    }

    static func presentationRels(slides: Int, notes: Bool) -> String {
        var rels = Relationships()
        rels.add("slideMaster", "slideMasters/slideMaster1.xml")
        for n in 0..<slides { rels.add("slide", "slides/slide\(n + 1).xml") }
        if notes { rels.add("notesMaster", "notesMasters/notesMaster1.xml") }
        rels.add("presProps", "presProps.xml")
        rels.add("viewProps", "viewProps.xml")
        rels.add("theme", "theme/theme1.xml")
        rels.add("tableStyles", "tableStyles.xml")
        return rels.xml
    }

    // MARK: fixed parts

    static let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    static let packageNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let relationshipBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
    static let drawingNS = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let namespaces = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
        + "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""

    /// The tree's own properties, which every slide, layout and master
    /// opens with.
    static let groupHeader = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>"

    static let masterColours = "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"

    /// The body placeholder each notes slide's words go in.
    static let notesPlaceholder = "<p:nvSpPr><p:cNvPr id=\"2\" name=\"Notes\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>"
        + "<p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr>"

    private static let colourMap = "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" "
        + "accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" "
        + "hlink=\"hlink\" folHlink=\"folHlink\"/>"

    private static let masterBackground = "<p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>"

    static var slideMaster: String {
        let layouts = "<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst>"
        let styles = "<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>"
        return [declaration, "<p:sldMaster \(namespaces)>", "<p:cSld>", masterBackground,
                "<p:spTree>", groupHeader, "</p:spTree></p:cSld>", colourMap, layouts, styles,
                "</p:sldMaster>"].joined()
    }

    static var slideMasterRels: String {
        var rels = Relationships()
        rels.add("slideLayout", "../slideLayouts/slideLayout1.xml")
        rels.add("theme", "../theme/theme1.xml")
        return rels.xml
    }

    static var slideLayout: String {
        [declaration, "<p:sldLayout \(namespaces) type=\"blank\" preserve=\"1\">",
         "<p:cSld name=\"Blank\"><p:spTree>", groupHeader, "</p:spTree></p:cSld>",
         masterColours, "</p:sldLayout>"].joined()
    }

    static var slideLayoutRels: String {
        var rels = Relationships()
        rels.add("slideMaster", "../slideMasters/slideMaster1.xml")
        return rels.xml
    }

    /// The notes pages' master: one body placeholder, where each notes
    /// slide's words go, on a portrait page.
    static var notesMaster: String {
        let box = "<p:spPr><a:xfrm><a:off x=\"685800\" y=\"4400550\"/><a:ext cx=\"5486400\" cy=\"3600450\"/></a:xfrm>"
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr>"
        let body = "<p:sp>\(notesPlaceholder)\(box)<p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>"
        return [declaration, "<p:notesMaster \(namespaces)>", "<p:cSld>", masterBackground,
                "<p:spTree>", groupHeader, body, "</p:spTree></p:cSld>", colourMap,
                "</p:notesMaster>"].joined()
    }

    static var notesMasterRels: String {
        var rels = Relationships()
        rels.add("theme", "../theme/theme2.xml")
        return rels.xml
    }

    static let tableStyles = declaration
        + "<a:tblStyleLst xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        + "def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>"

    /// The smallest whole theme: twelve colours, a font for headings and
    /// body, and three of each fill, line, effect and background style.
    static var theme: String {
        let colours = [("dk1", "000000"), ("lt1", "FFFFFF"), ("dk2", "1F2430"), ("lt2", "F4F4F6"),
                       ("accent1", "8B5CF6"), ("accent2", "EC4899"), ("accent3", "F59E0B"),
                       ("accent4", "10B981"), ("accent5", "3B82F6"), ("accent6", "EF4444"),
                       ("hlink", "2563EB"), ("folHlink", "7C3AED")]
            .map { "<a:\($0.0)><a:srgbClr val=\"\($0.1)\"/></a:\($0.0)>" }.joined()
        let face = "<a:latin typeface=\"Calibri\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>"
        let fonts = "<a:fontScheme name=\"Canvia\"><a:majorFont>\(face)</a:majorFont><a:minorFont>\(face)</a:minorFont></a:fontScheme>"
        let solid = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let fills = String(repeating: solid, count: 3)
        let lines = String(repeating: "<a:ln w=\"6350\">\(solid)</a:ln>", count: 3)
        let effects = String(repeating: "<a:effectStyle><a:effectLst/></a:effectStyle>", count: 3)
        let format = "<a:fmtScheme name=\"Canvia\"><a:fillStyleLst>\(fills)</a:fillStyleLst>"
            + "<a:lnStyleLst>\(lines)</a:lnStyleLst><a:effectStyleLst>\(effects)</a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(fills)</a:bgFillStyleLst></a:fmtScheme>"
        return [declaration, "<a:theme xmlns:a=\"\(drawingNS)\" name=\"Canvia\"><a:themeElements>",
                "<a:clrScheme name=\"Canvia\">\(colours)</a:clrScheme>", fonts, format,
                "</a:themeElements></a:theme>"].joined()
    }

    // MARK: writing the file

    /// The deck of the pages `range` picks — the PDF's page choice, hidden
    /// pages left out of "All pages" — written to `url` a slide at a time:
    /// each slide's pictures drawn and written first, then the slide that
    /// names those that drew. `progress` comes after each slide, with a
    /// pause between them, so a long deck can be watched and cancelled. A
    /// cancelled deck is deleted. `styled` text goes out editable, as its
    /// closest match; else as the picture of its exact look.
    @MainActor
    static func export(design: Design, range: DesignExporter.PageRange = .all, current: Int = 0,
                       to url: URL, styled: Bool = true, progress: ((Double) -> Void)? = nil) async throws {
        let indices = range.indices(in: design, current: current)
        guard !indices.isEmpty else { throw DesignExporter.ExportError.renderFailed }
        let pages = indices.map { design.pages[$0] }
        let numbers = slideNumbers(design: design, indices: indices)
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else {
            try? FileManager.default.removeItem(at: url)
            throw DesignExporter.ExportError.encodeFailed
        }
        let zip = ZipWriter { try handle.write(contentsOf: $0) }
        var pacer = DesignExporter.Pacer()
        do {
            let noted = pages.map { notesText(design: design, page: $0, styled: styled) != nil }
            for part in packageParts(design: design, noted: noted) {
                try zip.add(part.name, Data(part.xml.utf8))
            }
            var image = 1
            for (n, page) in pages.enumerated() {
                try await pacer.breathe()
                let number = n + 1
                var drawn: [MediaPart] = []
                for planned in media(design: design, page: page, firstImage: image, styled: styled) {
                    try autoreleasepool {
                        // One that will not draw is left out, and takes no number.
                        guard let data = render(planned.source, design: design, page: page) else { return }
                        let part = MediaPart(name: fileName(image, for: planned.source), source: planned.source)
                        try zip.add("ppt/media/\(part.name)", data)
                        drawn.append(part)
                        image += 1
                    }
                }
                let previous = n > 0 ? pages[n - 1] : nil
                let parts = slide(design: design, page: page, number: number, previous: previous, drawn: drawn,
                                  styled: styled, slides: numbers)
                try zip.add("ppt/slides/slide\(number).xml", Data(parts.xml.utf8))
                try zip.add("ppt/slides/_rels/slide\(number).xml.rels", Data(parts.rels.utf8))
                if let notes = parts.notes {
                    try zip.add("ppt/notesSlides/notesSlide\(number).xml", Data(notes.utf8))
                    try zip.add("ppt/notesSlides/_rels/notesSlide\(number).xml.rels", Data(notesRels(slide: number).utf8))
                }
                progress?(Double(number) / Double(pages.count))
            }
            try await pacer.finish()
            try zip.finish()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// A picture a slide names, drawn: the page's background as a JPEG, or
    /// an element upright — the slide turns it — with its flip, opacity and
    /// shadow, at twice its size within the pixel budget, as a PNG with
    /// room round it for what reaches past its box; a photo in letters as
    /// it is stored. Nil when it will not draw, and the slide goes without
    /// it.
    @MainActor
    static func render(_ source: MediaPart.Source, design: Design, page: Page) -> Data? {
        switch source {
        case .photo(let src):
            return PhotoFills.stored(src)?.data
        case .background:
            let size = design.size(for: page)
            let renderer = ImageRenderer(content: PageBackgroundView(design: design, page: page))
            renderer.scale = CGFloat(DesignExporter.effectiveScale(size: size, requested: pictureScale))
            renderer.isOpaque = true
            return renderer.uiImage?.jpegData(compressionQuality: 0.9)
        case .element(let el):
            guard el.w > 0, el.h > 0 else { return nil }
            var upright = el
            upright.rotation = 0
            upright.blendMode = nil
            upright.x = 0
            upright.y = 0
            let pad = margin(el)
            let size = CGSize(width: el.w + 2 * pad, height: el.h + 2 * pad)
            let renderer = ImageRenderer(content: ElementView(element: upright).padding(CGFloat(pad)))
            renderer.scale = CGFloat(DesignExporter.effectiveScale(size: size, requested: pictureScale))
            renderer.isOpaque = false
            return renderer.uiImage?.pngData()
        }
    }
}
