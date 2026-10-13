// Brand kits: the colours, faces and logos a person uses in everything.
//
// Several kits, one of them active, kept together in Documents as
// brandkits.json — the same file, key for key, as the Android twin keeps:
//
//   {"activeId": "kit-1",
//    "kits": [{"id": "kit-1", "name": "My brand",
//              "palettes": [{"name": "Colours", "colors": ["#1f2430", …]}],
//              "fonts": {"title": {"family", "weight", "size"?}, "heading": …,
//                        "subheading": …, "body": …, "quote": …, "caption": …},
//              "logos": ["media:…"]}]}
//
// A role left unset is not written. The active kit is offered first in
// every colour picker (its palettes by name), in Add text and the theme
// sheet by its text roles, and as insertable logos. Not per design: a
// brand is the thing that is the same across designs.
//
// The single kit of earlier builds (brandkit.json) is read into kit 1, "My
// brand": its colours become the palette "Colours", its heading and body
// faces the roles of those names. The old file is left where it is.

import Foundation

/// A named run of brand colours: "Colours", "Accents", "Autumn".
struct BrandPalette: Codable, Equatable {
    var name: String
    var colors: [String]
}

/// A brand face for one text role.
struct BrandFont: Codable, Equatable {
    var family: String
    var weight: Int
    /// The size on a page 1080 wide, scaled with the page as a font
    /// pairing's sizes are; nil leaves the size to whatever uses the role.
    var size: Double?

    init(family: String, weight: Int = 400, size: Double? = nil) {
        self.family = family
        self.weight = weight
        self.size = size
    }
}

/// The kit's faces by text role, each optional.
struct BrandFonts: Codable, Equatable {
    var title: BrandFont?
    var heading: BrandFont?
    var subheading: BrandFont?
    var body: BrandFont?
    var quote: BrandFont?
    var caption: BrandFont?

    /// The roles in the order they are listed, largest type first.
    enum Role: String, CaseIterable, Identifiable {
        case title, heading, subheading, body, quote, caption

        var id: String { rawValue }

        /// "Title", "Heading" …
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        /// What Add text calls a text in this role.
        var addLabel: String {
            switch self {
            case .title: return "Add a title"
            case .heading: return "Add a heading"
            case .subheading: return "Add a subheading"
            case .body: return "Add body text"
            case .quote: return "Add a quote"
            case .caption: return "Add a caption"
            }
        }

        /// Its size as a fraction of the page's width, when the kit gives
        /// none: the three Add text has always had, and the rest beside them
        /// — the Android twin's BrandRoles.share, number for number.
        var widthFraction: Double {
            switch self {
            case .title: return 0.11
            case .heading: return 0.08
            case .subheading: return 0.045
            case .body: return 0.028
            case .quote: return 0.04
            case .caption: return 0.022
            }
        }

        /// Its weight when the kit sets no face for it: a title and a
        /// heading bold, a subheading semibold, the rest regular, as on the
        /// Android twin.
        var defaultWeight: Int {
            switch self {
            case .title, .heading: return 700
            case .subheading: return 600
            default: return 400
            }
        }
    }

    subscript(role: Role) -> BrandFont? {
        get {
            switch role {
            case .title: return title
            case .heading: return heading
            case .subheading: return subheading
            case .body: return body
            case .quote: return quote
            case .caption: return caption
            }
        }
        set {
            switch role {
            case .title: title = newValue
            case .heading: heading = newValue
            case .subheading: subheading = newValue
            case .body: body = newValue
            case .quote: quote = newValue
            case .caption: caption = newValue
            }
        }
    }

    var isEmpty: Bool { Role.allCases.allSatisfy { self[$0] == nil } }

    /// What Add text offers, in role order: a heading, a subheading and body
    /// text always, as it always has, and a title, a quote or a caption
    /// once the kit sets a face for it.
    var addTextRoles: [Role] {
        Role.allCases.filter { [Role.heading, .subheading, .body].contains($0) || self[$0] != nil }
    }

    /// A text in `role` for a page `pageWidth` wide, its words what Add text
    /// calls it: the kit's face for the role, at its size scaled from a page
    /// 1080 wide, else the role's own size and weight in the default face.
    /// Sizes are whole numbers; the box is 72% of the page wide.
    static func element(_ role: Role, face: BrandFont?, pageWidth: Double) -> Element {
        let size = sized(face, pageWidth: pageWidth) ?? (pageWidth * role.widthFraction).rounded()
        var el = Element.text(role.addLabel, fontSize: size, w: (pageWidth * 0.72).rounded())
        el.fontWeight = face?.weight ?? role.defaultWeight
        if let face { el.fontFamily = face.family }
        el.h = FontLibrary.layoutHeight(for: el)
        return el
    }

    /// The kit's size for a role, set on a page 1080 wide, on a page
    /// `pageWidth` wide, whole; nil when the kit sets none.
    static func sized(_ face: BrandFont?, pageWidth: Double) -> Double? {
        face?.size.map { ($0 * pageWidth / 1080).rounded() }
    }

    /// A text set in a role's face — the Styles list's brand rows: its
    /// family and weight, and the kit's size for the role, scaled as
    /// `element` scales it, when it sets one. Anything but text is left
    /// alone; the caller measures the height again.
    static func apply(_ face: BrandFont, to el: inout Element, pageWidth: Double) {
        guard el.type == .text else { return }
        el.fontFamily = face.family
        el.fontWeight = face.weight
        if let size = sized(face, pageWidth: pageWidth) { el.fontSize = size }
    }

    /// The roles a theme sets by size rank, largest first: those with a face
    /// among title, heading, subheading and body. A quote or a caption is
    /// not a rank — it is what a text says, not how big it is — so the theme
    /// leaves them to Add text.
    var rankedRoles: [Role] {
        [Role.title, .heading, .subheading, .body].filter { self[$0] != nil }
    }
}

struct BrandKit: Codable, Equatable, Identifiable {
    var id: String = UID.make("kit")
    var name: String = BrandKit.firstName
    var palettes: [BrandPalette] = []
    var fonts = BrandFonts()
    /// Media or asset sources of logos.
    var logos: [String] = []

    /// What the first kit, and the one an earlier build's kit becomes, is
    /// called, and its id.
    static let firstName = "My brand"
    static let firstId = "kit-1"
    /// What a palette of colours with no other name is called.
    static let firstPaletteName = "Colours"
    /// The most colours a palette holds.
    static let limit = 12

    /// Every colour of every palette, once each, in palette order.
    var colors: [String] {
        var seen = Set<String>()
        return palettes.flatMap(\.colors).filter { seen.insert($0.lowercased()).inserted }
    }

    var isEmpty: Bool { colors.isEmpty && fonts.isEmpty && logos.isEmpty }

    /// The kit's palettes as the theme sheet maps a design onto them, in
    /// kit order — first there, as on the Android twin — each once it has
    /// two colours.
    var themePalettes: [Palette] {
        palettes.enumerated().compactMap { index, palette in
            palette.colors.count >= 2
                ? Palette(id: "brand-kit-\(index)", name: palette.name, colors: palette.colors) : nil
        }
    }

    /// A palette as the colour pickers head it: "My brand · Colours".
    func title(of palette: BrandPalette) -> String { "\(name) · \(palette.name)" }

    /// Whether a theme palette is one of a brand kit's.
    static func isBrandPalette(_ palette: Palette) -> Bool { palette.id.hasPrefix("brand-kit") }

    /// The active kit.
    static func load() -> BrandKit { BrandKits.load().active }

    /// This kit written back among the others: in its place, or added, and
    /// made the active one when it is new.
    func save() {
        var all = BrandKits.load()
        all.update(self)
        all.save()
    }

    /// The pictures the Logos list offers, once each: the logos the sheet
    /// opened with — kept listed when switched off, so a slip can be taken
    /// back — then this design's pictures, then any other logo since added.
    /// A picture switched on stays where it was, so the next tap in the same
    /// place never lands on another. Codes are not logos. As the Android
    /// twin lists them.
    static func logoCandidates(openedWith: [String], current: [String], design: Design) -> [String] {
        let pictures = design.pages.flatMap(\.elements)
            .filter { $0.type == .image }
            .compactMap(\.src)
            .filter { CodeGenerator.payload(from: $0) == nil }
        var seen = Set<String>()
        return (openedWith + pictures + current).filter { seen.insert($0).inserted }
    }

    /// A colour added to the palette at `palette`, newest first, once, at
    /// most `limit` of them. With no palettes yet, it starts "Colours".
    mutating func addColor(_ hex: String, palette index: Int = 0) {
        if palettes.isEmpty { palettes = [BrandPalette(name: Self.firstPaletteName, colors: [])] }
        guard palettes.indices.contains(index) else { return }
        let h = RecentColors.normalise(hex)
        palettes[index].colors.removeAll { $0 == h }
        palettes[index].colors.insert(h, at: 0)
        palettes[index].colors = Array(palettes[index].colors.prefix(Self.limit))
    }
}

/// Every kit, and which one is in use: brandkits.json.
struct BrandKits: Codable, Equatable {
    var activeId: String?
    var kits: [BrandKit]

    static let fileName = "brandkits.json"
    static let legacyFileName = "brandkit.json"

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    static var legacyURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(legacyFileName)
    }

    /// One empty kit, "My brand": what there is before anything is saved.
    static var fresh: BrandKits {
        BrandKits(activeId: BrandKit.firstId, kits: [BrandKit(id: BrandKit.firstId)])
    }

    /// The kit in use: the one `activeId` names, else the first.
    var active: BrandKit {
        kits.first { $0.id == activeId } ?? kits.first ?? BrandKit(id: BrandKit.firstId)
    }

    /// Every kit's logos, which the launch sweep keeps.
    var allLogos: [String] { kits.flatMap(\.logos) }

    /// The kits as saved; else an earlier build's single kit, migrated;
    /// else one empty kit. Never empty.
    static func load(from url: URL = fileURL, legacy: URL = legacyURL) -> BrandKits {
        if let data = try? Data(contentsOf: url), let kits = read(data) { return kits }
        if let data = try? Data(contentsOf: legacy), let kits = migrated(data) { return kits }
        return fresh
    }

    func save(to url: URL = BrandKits.fileURL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(self) { try? data.write(to: url, options: .atomic) }
    }

    /// brandkits.json read leniently: a kit that does not read is passed
    /// over, and none left reads as one empty kit. Nil when it is not the
    /// file at all.
    static func read(_ data: Data) -> BrandKits? {
        guard var kits = try? JSONDecoder().decode(BrandKits.self, from: data) else { return nil }
        if kits.kits.isEmpty { kits = fresh }
        if !kits.kits.contains(where: { $0.id == kits.activeId }) { kits.activeId = kits.kits.first?.id }
        return kits
    }

    /// An earlier build's brandkit.json as kit 1, "My brand", active: its
    /// colours the palette "Colours" (no palette when it had none) — each
    /// written one way, lower case, once, at most `limit`, as the Android
    /// twin migrates them — its heading and body faces those roles at the
    /// weights it kept, and its logos. Nil when the data is not that file.
    static func migrated(_ data: Data) -> BrandKits? {
        guard let old = try? JSONDecoder().decode(LegacyKit.self, from: data) else { return nil }
        var kit = BrandKit(id: BrandKit.firstId, name: BrandKit.firstName)
        var seen = Set<String>()
        let colors = (old.colors ?? []).map(RecentColors.normalise)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(BrandKit.limit)
        if !colors.isEmpty { kit.palettes = [BrandPalette(name: BrandKit.firstPaletteName, colors: Array(colors))] }
        kit.fonts.heading = old.headingFamily.map { BrandFont(family: $0, weight: old.headingWeight ?? 700) }
        kit.fonts.body = old.bodyFamily.map { BrandFont(family: $0, weight: old.bodyWeight ?? 400) }
        kit.logos = old.logos ?? []
        return BrandKits(activeId: kit.id, kits: [kit])
    }

    /// The single kit earlier builds kept.
    private struct LegacyKit: Decodable {
        var colors: [String]?
        var headingFamily: String?
        var headingWeight: Int?
        var bodyFamily: String?
        var bodyWeight: Int?
        var logos: [String]?
    }

    /// `kit` in its place, or added and made active when it is new.
    mutating func update(_ kit: BrandKit) {
        if let i = kits.firstIndex(where: { $0.id == kit.id }) {
            kits[i] = kit
        } else {
            kits.append(kit)
            activeId = kit.id
        }
    }

    /// A new empty kit, "Brand kit 2" or the like, made active.
    @discardableResult
    mutating func addKit(named name: String = "Brand kit") -> BrandKit {
        let kit = BrandKit(name: Titles.unique(name, taken: kits.map(\.name)))
        kits.append(kit)
        activeId = kit.id
        return kit
    }

    /// A kit taken away, never the last; the first left becomes active when
    /// it was.
    mutating func removeKit(_ id: String) {
        guard kits.count > 1 else { return }
        kits.removeAll { $0.id == id }
        if !kits.contains(where: { $0.id == activeId }) { activeId = kits.first?.id }
    }
}

// Lenient reading, in extensions so the memberwise initialisers stay: a key
// missing, or of a type this build does not expect, takes its default, as
// files from another build or the other phone may have them.

extension BrandPalette {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? BrandKit.firstPaletteName
        colors = (try? c.decode([String].self, forKey: .colors)) ?? []
    }
}

extension BrandFont {
    /// A face with no family is no face, and the role reads as unset.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = try c.decode(String.self, forKey: .family)
        weight = (try? c.decode(Int.self, forKey: .weight)) ?? 400
        size = try? c.decode(Double.self, forKey: .size)
    }
}

extension BrandFonts {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decode(BrandFont.self, forKey: .title)
        heading = try? c.decode(BrandFont.self, forKey: .heading)
        subheading = try? c.decode(BrandFont.self, forKey: .subheading)
        body = try? c.decode(BrandFont.self, forKey: .body)
        quote = try? c.decode(BrandFont.self, forKey: .quote)
        caption = try? c.decode(BrandFont.self, forKey: .caption)
    }
}

extension BrandKit {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UID.make("kit")
        name = (try? c.decode(String.self, forKey: .name)) ?? BrandKit.firstName
        palettes = (try? c.decode([BrandPalette].self, forKey: .palettes)) ?? []
        fonts = (try? c.decode(BrandFonts.self, forKey: .fonts)) ?? BrandFonts()
        logos = (try? c.decode([String].self, forKey: .logos)) ?? []
    }
}

extension BrandKits {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeId = try? c.decode(String.self, forKey: .activeId)
        kits = try c.decode([OneKit].self, forKey: .kits).compactMap(\.kit)
    }

    /// One kit of the list, or nil when it does not read.
    private struct OneKit: Decodable {
        var kit: BrandKit?
        init(from decoder: Decoder) throws { kit = try? BrandKit(from: decoder) }
    }
}

// MARK: - a kit as a file

/// A kit as one file, .canvia-brand.json, to move it between phones:
/// {"format": "canvia-brand", "version": 1, "kit": {…}, "media": {…}}. Its
/// photo logos travel inlined as a design package carries its photos — the
/// same {"ext", "data"} entries, under the ids the kit's logos name — and
/// arrive under fresh ids, in a kit of its own. A clip logo travels as its
/// name only, and is left out where it arrives, on either phone: the
/// Android twin's kit file carries photos alone, and a "videos" entry from
/// an earlier build is passed over by both.
enum BrandKitFile {

    static let format = "canvia-brand"
    static let version = 1
    static let ext = "canvia-brand.json"

    struct Contents: Codable {
        var format: String = BrandKitFile.format
        var version: Int = BrandKitFile.version
        var kit: BrandKit
        var media: [String: DesignPackage.Media]
    }

    /// The logos as a design's pictures, one each, in order, so a package's
    /// packing and reading carry them.
    private static func carrier(_ logos: [String]) -> Design {
        var design = Design(title: "Logos", width: 1000, height: 1000)
        design.pages = [Page(elements: logos.map { Element.image($0) })]
        return design
    }

    /// The kit's file: its photo logos inlined and library pictures drawn,
    /// as a design file does. A clip logo stays as it is — neither the clip
    /// nor a still of it goes in — as the Android twin writes it.
    static func contents(of kit: BrandKit, mediaDirectory: URL = MediaStore.directory) -> Contents {
        let pictures = kit.logos.filter { VideoStore.split($0) == nil }
        let package = DesignPackage.contents(of: carrier(pictures), mediaDirectory: mediaDirectory)
        let packedPictures = package.design.pages.first?.elements.compactMap(\.src) ?? pictures
        var drawn = packedPictures.makeIterator()
        var packed = kit
        packed.logos = kit.logos.map { src in VideoStore.split(src) == nil ? (drawn.next() ?? src) : src }
        return Contents(kit: packed, media: package.media)
    }

    static func export(_ kit: BrandKit, mediaDirectory: URL = MediaStore.directory) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(contents(of: kit, mediaDirectory: mediaDirectory))
    }

    enum KitFileError: LocalizedError {
        case notAKit
        var errorDescription: String? { "This file is not a Canvia brand kit." }
    }

    /// The file's logos that arrive: a photo logo whose file it does not
    /// carry is left out, and so is every clip logo, as no kit file carries
    /// a clip; any other — a library picture — is kept as it is, as the
    /// Android twin's BrandKitPackage.relinked keeps them.
    static func carried(_ contents: Contents) -> [String] {
        contents.kit.logos.filter { src in
            if src.hasPrefix("media:") { return contents.media[String(src.dropFirst(6))] != nil }
            return VideoStore.split(src) == nil
        }
    }

    /// The kit inside, with its logos stored under fresh ids, a fresh id of
    /// its own and a name no kit here has ("My brand 2"), added to `kits`
    /// and made active.
    @discardableResult
    static func `import`(_ data: Data, into kits: inout BrandKits,
                         mediaDirectory: URL = MediaStore.directory) throws -> BrandKit {
        guard let contents = try? JSONDecoder().decode(Contents.self, from: data),
              contents.format == format else { throw KitFileError.notAKit }
        let package = DesignPackage.Package(design: carrier(carried(contents)), media: contents.media)
        let stored = try DesignPackage.import(DesignPackage.encode(package), mediaDirectory: mediaDirectory,
                                              normalize: false)
        var kit = contents.kit
        kit.id = UID.make("kit")
        kit.name = Titles.unique(kit.name, taken: kits.kits.map(\.name))
        kit.logos = stored.pages.first?.elements.compactMap(\.src) ?? []
        kits.kits.append(kit)
        kits.activeId = kit.id
        return kit
    }
}
