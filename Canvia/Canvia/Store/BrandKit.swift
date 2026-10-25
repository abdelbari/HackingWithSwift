// Brand kits: the colours, faces and logos a person uses in everything.
//
// Several kits, one of them active, kept together in Documents as
// brandkits.json — the same file, key for key, as the Android twin keeps:
//
//   {"activeId": "kit-1",
//    "kits": [{"id": "kit-1", "name": "My brand",
//              "palettes": [{"name": "Colours", "colors": ["#1f2430", …],
//                            "names"?: {"#1F2430": "Ink"}}],
//              "fonts": {"title": {"family", "weight", "size"?, "color"?,
//                                  "letterSpacing"?, "lineHeight"?,
//                                  "uppercase"?, "italic"?},
//                        "subtitle": …, "heading": …, "subheading": …,
//                        "sectionHeader": …, "body": …, "quote": …,
//                        "caption": …},
//              "logos": ["media:…"],
//              "photos": ["media:…"], "graphics": ["media:…" | "svg:…"],
//              "templates": ["<userTemplateId>"]}]}
//
// A role left unset is not written. Photos, graphics and templates are
// written only when the kit has any, and a kit without them — every kit
// of earlier builds — reads with none. A graphic is a picture, or an SVG
// kept as it came among the uploads ("svg:<id>", the file media/<id>.svg)
// and placed through SvgImport as a recolourable graphic; a template is
// the id of one of your own (UserTemplates), and deleting it takes it out
// of every kit. The active kit is offered first in
// every colour picker (its palettes by name), in Add text and the theme
// sheet by its text roles, and as insertable logos — and with its photos
// and graphics, in the Add sheet's Brand tab, its templates leading Home's
// and the Templates panel's in a "From <kit name>" row. Not per design: a
// brand is the thing that is the same across designs.
//
// The single kit of earlier builds (brandkit.json) is read into kit 1, "My
// brand": its colours become the palette "Colours", its heading and body
// faces the roles of those names. The old file is left where it is.

import Foundation

/// A named run of brand colours: "Colours", "Accents", "Autumn" — each
/// colour with a name of its own where it has been given one ("Ocean",
/// "Primary CTA"): `names`, keyed by the colour as upper-case "#RRGGBB",
/// each name at most `BrandPalette.nameLimit` characters, written only when
/// there are some, and only for colours the palette has — the rule both
/// phones keep. A reader that knows nothing of it passes it over.
struct BrandPalette: Codable, Equatable {
    var name: String
    var colors: [String]
    var names: [String: String] = [:]

    // Declared, as both coding directions are written by hand below.
    enum CodingKeys: String, CodingKey { case name, colors, names }

    /// The longest a colour's name may be.
    static let nameLimit = 40

    /// A colour as `names` keys it: "#RRGGBB" in capitals, its alpha left
    /// out; nil for anything that is no colour.
    static func key(_ hex: String) -> String? {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits.prefix(6).uppercased()
    }

    /// A name as kept: trimmed and cut to `nameLimit`; nil for none.
    static func keptName(_ name: String?) -> String? {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(nameLimit))
    }

    /// The name `hex` has here, if it has one — none once `hex` is no
    /// longer one of the palette's colours.
    func name(of hex: String) -> String? {
        guard let key = BrandPalette.key(hex),
              colors.contains(where: { BrandPalette.key($0) == key }) else { return nil }
        return names[key]
    }

    /// `hex` given `name`, or its name taken away with nil or a blank.
    mutating func setName(_ name: String?, of hex: String) {
        guard let key = BrandPalette.key(hex) else { return }
        names[key] = BrandPalette.keptName(name)
    }

    /// The names of the colours it has, each kept: what is written.
    var keptNames: [String: String] {
        let own = Set(colors.compactMap(BrandPalette.key))
        var out: [String: String] = [:]
        for (hex, name) in names {
            guard let key = BrandPalette.key(hex), own.contains(key), let kept = BrandPalette.keptName(name) else { continue }
            out[key] = kept
        }
        return out
    }
}

/// A brand face for one text role, and the rest of its type: a colour, a
/// letter spacing, a line spacing, capitals and a slant, each optional, so
/// a kit from an earlier build reads unchanged.
struct BrandFont: Codable, Equatable {
    var family: String
    var weight: Int
    /// The size on a page 1080 wide, scaled with the page as a font
    /// pairing's sizes are; nil leaves the size to whatever uses the role.
    var size: Double?
    /// "#rrggbb", or one of the kit's colours as "palette:<palette>:<colour>"
    /// (both from 0), which follows the colour when it is changed.
    var color: String?
    /// Letter spacing on a page 1080 wide, scaled with the page as the size
    /// is.
    var letterSpacing: Double?
    /// Line spacing, as a text's lineHeight: a multiple of the type size.
    var lineHeight: Double?
    var uppercase: Bool?
    var italic: Bool?

    init(family: String, weight: Int = 400, size: Double? = nil, color: String? = nil,
         letterSpacing: Double? = nil, lineHeight: Double? = nil, uppercase: Bool? = nil, italic: Bool? = nil) {
        self.family = family
        self.weight = weight
        self.size = size
        self.color = color
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.uppercase = uppercase
        self.italic = italic
    }

    /// What a "palette:<p>:<c>" colour starts with.
    static let paletteRef = "palette:"

    /// `color` as a colour: a hex as it is, a reference to one of
    /// `palettes`' colours as that colour, nil for none or a reference to a
    /// colour the kit no longer has.
    static func resolved(_ color: String?, palettes: [BrandPalette]) -> String? {
        guard let color else { return nil }
        guard color.hasPrefix(paletteRef) else { return color }
        let parts = color.dropFirst(paletteRef.count).split(separator: ":").map { Int($0) }
        guard parts.count == 2, let p = parts[0], let c = parts[1],
              palettes.indices.contains(p), palettes[p].colors.indices.contains(c) else { return nil }
        return palettes[p].colors[c]
    }
}

/// The kit's faces by text role, each optional.
struct BrandFonts: Codable, Equatable {
    var title: BrandFont?
    var subtitle: BrandFont?
    var heading: BrandFont?
    var subheading: BrandFont?
    var sectionHeader: BrandFont?
    var body: BrandFont?
    var quote: BrandFont?
    var caption: BrandFont?

    /// The roles in the order they are listed — Canva's brand kit order, the
    /// Android twin's BrandRoles.ORDER.
    enum Role: String, CaseIterable, Identifiable {
        case title, subtitle, heading, subheading, sectionHeader, body, quote, caption

        var id: String { rawValue }

        /// The roles a theme hands out by size, biggest first — in the
        /// order they are listed, a subtitle between the title and the
        /// heading; a quote or a caption is what a text says, not how big
        /// it is, so neither is a rank. The Android twin's BrandRoles.BY_SIZE.
        static let bySize: [Role] = [.title, .subtitle, .heading, .subheading, .sectionHeader, .body]

        /// "Title", "Heading" …
        var label: String {
            switch self {
            case .title: return tr("Title")
            case .subtitle: return tr("Subtitle")
            case .heading: return tr("Heading")
            case .subheading: return tr("Subheading")
            case .sectionHeader: return tr("Section header")
            case .body: return tr("Body")
            case .quote: return tr("Quote")
            case .caption: return tr("Caption")
            }
        }

        /// What Add text calls a text in this role.
        var addLabel: String {
            switch self {
            case .title: return tr("Add a title")
            case .subtitle: return tr("Add a subtitle")
            case .heading: return tr("Add a heading")
            case .subheading: return tr("Add a subheading")
            case .sectionHeader: return tr("Add a section header")
            case .body: return tr("Add body text")
            case .quote: return tr("Add a quote")
            case .caption: return tr("Add a caption")
            }
        }

        /// Its size as a fraction of the page's width, when the kit gives
        /// none: the three Add text has always had, and the rest beside them
        /// — the Android twin's BrandRoles.share, number for number.
        var widthFraction: Double {
            switch self {
            case .title: return 0.11
            case .subtitle: return 0.05
            case .heading: return 0.08
            case .subheading: return 0.045
            case .sectionHeader: return 0.035
            case .body: return 0.028
            case .quote: return 0.04
            case .caption: return 0.022
            }
        }

        /// Its weight when the kit sets no face for it: a title and a
        /// heading bold, a subheading and a section header semibold, a
        /// subtitle medium, the rest regular, as on the Android twin.
        var defaultWeight: Int {
            switch self {
            case .title, .heading: return 700
            case .subheading, .sectionHeader: return 600
            case .subtitle: return 500
            default: return 400
            }
        }

        /// Whether it is in capitals when its face does not say: a section
        /// header is.
        var defaultUppercase: Bool { self == .sectionHeader }

        /// Its letter spacing in ems of its size when its face sets none: a
        /// section header's 0.08, the rest none.
        var defaultSpacingEm: Double { self == .sectionHeader ? 0.08 : 0 }
    }

    subscript(role: Role) -> BrandFont? {
        get {
            switch role {
            case .title: return title
            case .subtitle: return subtitle
            case .heading: return heading
            case .subheading: return subheading
            case .sectionHeader: return sectionHeader
            case .body: return body
            case .quote: return quote
            case .caption: return caption
            }
        }
        set {
            switch role {
            case .title: title = newValue
            case .subtitle: subtitle = newValue
            case .heading: heading = newValue
            case .subheading: subheading = newValue
            case .sectionHeader: sectionHeader = newValue
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
    /// 1080 wide, else the role's own size and weight in the default face —
    /// and every other thing the face sets (typeSettings), its colour from
    /// `palettes` where it names one of the kit's. Sizes are whole numbers;
    /// the box is 72% of the page wide.
    static func element(_ role: Role, face: BrandFont?, pageWidth: Double,
                        palettes: [BrandPalette] = []) -> Element {
        let size = sized(face, pageWidth: pageWidth) ?? (pageWidth * role.widthFraction).rounded()
        var el = Element.text(role.addLabel, fontSize: size, w: (pageWidth * 0.72).rounded())
        el.fontWeight = face?.weight ?? role.defaultWeight
        if let face { el.fontFamily = face.family }
        typeSettings(face, role: role, to: &el, pageWidth: pageWidth, palettes: palettes)
        el.h = FontLibrary.layoutHeight(for: el)
        return el
    }

    /// The rest of a face's type on `el`, each only when set: its colour
    /// (resolved against `palettes`), its letter spacing scaled from a page
    /// 1080 wide as the size is, its line spacing, capitals and slant. A
    /// section header's face that says nothing of capitals or spacing is in
    /// capitals, 0.08 em apart (Role.defaultUppercase, defaultSpacingEm) —
    /// the rule both phones share. `role` nil applies the face alone.
    static func typeSettings(_ face: BrandFont?, role: Role?, to el: inout Element, pageWidth: Double,
                             palettes: [BrandPalette]) {
        if let color = BrandFont.resolved(face?.color, palettes: palettes) { el.color = color }
        // To the hundredth, as the Android twin's BrandRoles.spacing has it.
        if let spacing = face?.letterSpacing {
            el.letterSpacing = (spacing * pageWidth / 1080 * 100).rounded() / 100
        } else if let role, role.defaultSpacingEm > 0 {
            el.letterSpacing = (role.defaultSpacingEm * (el.fontSize ?? 42) * 100).rounded() / 100
        }
        if let line = face?.lineHeight { el.lineHeight = line }
        if let caps = face?.uppercase {
            el.uppercase = caps ? true : nil
        } else if let role, role.defaultUppercase {
            el.uppercase = true
        }
        if let italic = face?.italic { el.italic = italic }
    }

    /// The kit's size for a role, set on a page 1080 wide, on a page
    /// `pageWidth` wide, whole; nil when the kit sets none.
    static func sized(_ face: BrandFont?, pageWidth: Double) -> Double? {
        face?.size.map { ($0 * pageWidth / 1080).rounded() }
    }

    /// A text set in a role's face — the Styles list's brand rows: its
    /// family and weight, and the kit's size for the role, scaled as
    /// `element` scales it, when it sets one, and the rest of its type as
    /// `element` sets it for `role`. Anything but text is left alone; the
    /// caller measures the height again.
    static func apply(_ face: BrandFont, to el: inout Element, pageWidth: Double) {
        apply(face, to: &el, pageWidth: pageWidth, role: nil, palettes: [])
    }

    /// The same, the face's type set as `role` sets it, its colour from
    /// `palettes` where it names one of the kit's.
    static func apply(_ face: BrandFont, to el: inout Element, pageWidth: Double,
                      role: BrandFonts.Role?, palettes: [BrandPalette]) {
        guard el.type == .text else { return }
        el.fontFamily = face.family
        el.fontWeight = face.weight
        if let size = sized(face, pageWidth: pageWidth) { el.fontSize = size }
        typeSettings(face, role: role, to: &el, pageWidth: pageWidth, palettes: palettes)
    }

    /// The face a role is set in: its own, or — when the kit leaves it out —
    /// a title's and a subheading's the heading's, a quote's and a
    /// caption's the body's, and the heading and the body each other's. Nil
    /// when the kit has neither. The Android twin's BrandRoles.fontFor.
    func fontFor(_ role: Role) -> BrandFont? {
        if let own = self[role] { return own }
        switch role {
        case .title, .subtitle, .subheading, .sectionHeader, .heading: return heading ?? body
        case .body, .quote, .caption: return body ?? heading
        }
    }

    /// The roles a theme sets by size rank, largest first: those with a face
    /// among Role.bySize. A quote or a caption is not a rank — it is what a
    /// text says, not how big it is — so the theme leaves them to Add text.
    var rankedRoles: [Role] {
        Role.bySize.filter { self[$0] != nil }
    }
}

struct BrandKit: Codable, Equatable, Identifiable {
    var id: String = UID.make("kit")
    var name: String = BrandKit.firstName
    var palettes: [BrandPalette] = []
    var fonts = BrandFonts()
    /// Media or asset sources of logos.
    var logos: [String] = []
    /// Media or asset sources of brand photos.
    var photos: [String] = []
    /// Media or asset sources of brand graphics, or "svg:<id>" for an SVG.
    var graphics: [String] = []
    /// The ids of templates of your own.
    var templates: [String] = []
    /// Gradients saved from the colour sheet's editor (GradientEditing).
    var gradients: [Paint] = []

    enum CodingKeys: String, CodingKey {
        case id, name, palettes, fonts, logos, photos, graphics, templates, gradients
    }

    /// What the first kit, and the one an earlier build's kit becomes, is
    /// called, and its id.
    static let firstName = tr("My brand")
    static let firstId = "kit-1"
    /// What a palette of colours with no other name is called.
    static let firstPaletteName = tr("Colours")
    /// The most colours a palette holds.
    static let limit = 12

    /// The name `hex` has in this kit: the first palette's to name it.
    func colourName(_ hex: String) -> String? {
        palettes.lazy.compactMap { $0.name(of: hex) }.first
    }

    /// `hex` as a person reads it here: its brand name, else its hue name
    /// (ElementNames.spokenColour).
    func spokenColour(_ hex: String) -> String {
        colourName(hex) ?? ElementNames.spokenColour(hex)
    }

    /// What a screen reader says of one of the kit's swatches: "Ocean,
    /// brand colour", the hue's name for a colour with none.
    func brandColourLabel(_ hex: String) -> String {
        tr("%@, brand colour", spokenColour(hex))
    }

    /// A swap as Change all and Colours in selection say it: "Ocean →
    /// Sand", each colour by its brand name, else its hue's ("Dark blue"),
    /// as the Android twin's BrandKit.spokenColour says them.
    func swapLabel(from: String, to: String) -> String {
        tr("%@ → %@", spokenColour(from), spokenColour(to))
    }

    /// A gradient by its stops, each by its brand name, else its hue's —
    /// "Ocean, Sand" — as the Android twin's brand gradient tiles say it;
    /// nil for one with no stops.
    func gradientName(_ paint: Paint) -> String? {
        let stops = paint.stops ?? []
        guard !stops.isEmpty else { return nil }
        return stops.map { spokenColour($0.color) }.joined(separator: ", ")
    }

    /// Every colour of every palette, once each, in palette order.
    var colors: [String] {
        var seen = Set<String>()
        return palettes.flatMap(\.colors).filter { seen.insert($0.lowercased()).inserted }
    }

    var isEmpty: Bool {
        colors.isEmpty && fonts.isEmpty && logos.isEmpty && photos.isEmpty && graphics.isEmpty && templates.isEmpty
            && gradients.isEmpty
    }

    /// Whether the Add sheet shows a Brand tab for this kit: it has a logo,
    /// a photo, a graphic, a colour or a face for a text role — all the tab
    /// lists. Templates alone lead the Templates panel instead.
    var showsBrandTab: Bool {
        !logos.isEmpty || !photos.isEmpty || !graphics.isEmpty || !colors.isEmpty || !fonts.isEmpty
    }

    /// What the row of the kit's templates is headed: "From My brand".
    var templatesTitle: String { tr("From %@", name) }

    /// The kit's templates among `entries` (your own, as listed), in the
    /// kit's order; an id with no template here is passed over.
    func templateEntries(_ entries: [UserTemplate]) -> [UserTemplate] {
        templates.compactMap { id in entries.first { $0.id == id } }
    }

    /// The rest of `entries`, as they were: what "Your templates" lists
    /// under the kit's row, so none is shown twice — the Android twin's
    /// BrandKit.leading.
    func otherEntries(_ entries: [UserTemplate]) -> [UserTemplate] {
        entries.filter { !templates.contains($0.id) }
    }

    /// The source of an SVG graphic kept as media/<id>.svg.
    static func svgSource(_ id: String) -> String { "svg:\(id)" }

    /// The upload an SVG graphic names, or nil when it is a picture.
    static func svgID(_ src: String) -> String? {
        guard src.hasPrefix("svg:") else { return nil }
        let id = String(src.dropFirst(4))
        return id.isEmpty ? nil : id
    }

    /// What a graphic is kept as on this phone: an SVG as the media file it
    /// is ("media:<id>"), so the sweep, a backup and a kit file carry it as
    /// they carry a photo; a picture as itself.
    static func mediaSource(_ src: String) -> String {
        svgID(src).map { "media:\($0)" } ?? src
    }

    /// The picture a photo or a graphic is added from, when "Add from this
    /// design" is asked with `element` selected: a picture's source — not
    /// an empty frame, a clip, an animated picture or a code.
    static func picture(of element: Element) -> String? {
        guard element.type == .image, let src = element.src, !src.isEmpty,
              VideoStore.split(src) == nil, AnimStore.split(src) == nil,
              !CodeGenerator.isCode(src) else { return nil }
        return src
    }

    /// A gradient saved to the kit, last and once (GradientPreset.same: a
    /// gradient already there moves to the end), the oldest dropped past
    /// `limit` — as on the Android twin. Whether it is in the kit now.
    @discardableResult
    mutating func addGradient(_ paint: Paint) -> Bool {
        guard paint.kind == "gradient", (paint.stops?.count ?? 0) >= GradientEditing.minStops else { return false }
        let others = gradients.filter { !GradientPreset.same($0, paint) }
        gradients = Array((others + [paint]).suffix(BrandKit.limit))
        return true
    }

    /// A source added to the end of one of the kit's lists, once.
    mutating func add(_ src: String, to list: WritableKeyPath<BrandKit, [String]>) {
        guard !self[keyPath: list].contains(src) else { return }
        self[keyPath: list].append(src)
    }

    /// The kit's palettes as the theme sheet maps a design onto them, in
    /// kit order — first there, as on the Android twin — each once it has
    /// two colours.
    var themePalettes: [Palette] {
        palettes.enumerated().compactMap { index, palette in
            palette.colors.count >= 2
                ? Palette(id: "brand-kit-\(index)", name: palette.name, colors: palette.colors) : nil
        }
    }

    /// Whether "Start with my brand" has a look to give: a palette of two
    /// colours or more, or a face for a text role.
    var canStartWith: Bool { !themePalettes.isEmpty || !fonts.rankedRoles.isEmpty }

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
            .filter { !CodeGenerator.isCode($0) }
        var seen = Set<String>()
        return (openedWith + pictures + current).filter { seen.insert($0).inserted }
    }

    /// A colour added to the palette at `palette`, newest first, once, at
    /// most `limit` of them — a colour pushed out takes its name with it.
    /// With no palettes yet, it starts "Colours".
    mutating func addColor(_ hex: String, palette index: Int = 0) {
        if palettes.isEmpty { palettes = [BrandPalette(name: Self.firstPaletteName, colors: [])] }
        guard palettes.indices.contains(index) else { return }
        let h = RecentColors.normalise(hex)
        palettes[index].colors.removeAll { $0 == h }
        palettes[index].colors.insert(h, at: 0)
        palettes[index].colors = Array(palettes[index].colors.prefix(Self.limit))
        palettes[index].names = palettes[index].keptNames
    }

    /// `hex` taken out of the palette at `palette`, and its name with it,
    /// so the colour added back has none — as on the Android twin.
    mutating func removeColor(_ hex: String, palette index: Int) {
        guard palettes.indices.contains(index) else { return }
        palettes[index].colors.removeAll { $0.lowercased() == hex.lowercased() }
        palettes[index].setName(nil, of: hex)
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

    /// Every kit's logos, photos and graphics, an SVG graphic as the media
    /// file it is: what the launch sweep and a backup keep.
    var allAssets: [String] {
        kits.flatMap { $0.logos + $0.photos + $0.graphics.map(BrandKit.mediaSource) }
    }

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
    mutating func addKit(named name: String = tr("Brand kit")) -> BrandKit {
        let kit = BrandKit(name: Titles.unique(name, taken: kits.map(\.name)))
        kits.append(kit)
        activeId = kit.id
        return kit
    }

    /// A template of your own taken out of every kit, as deleting it does.
    /// Whether any kit had it.
    @discardableResult
    mutating func removeTemplate(_ id: String) -> Bool {
        var changed = false
        for i in kits.indices where kits[i].templates.contains(id) {
            kits[i].templates.removeAll { $0 == id }
            changed = true
        }
        return changed
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
        // Names one at a time: one that is no text is passed over.
        let raw = (try? c.decode([String: Lossy<String>].self, forKey: .names)) ?? [:]
        names = raw.compactMapValues(\.value)
        names = keptNames
    }

    /// The names only when there are some, so a palette without them is
    /// written as earlier builds wrote it.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(colors, forKey: .colors)
        let kept = keptNames
        if !kept.isEmpty { try c.encode(kept, forKey: .names) }
    }
}

extension BrandFont {
    /// A face with no family is no face, and the role reads as unset.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = try c.decode(String.self, forKey: .family)
        weight = (try? c.decode(Int.self, forKey: .weight)) ?? 400
        size = try? c.decode(Double.self, forKey: .size)
        color = try? c.decode(String.self, forKey: .color)
        letterSpacing = try? c.decode(Double.self, forKey: .letterSpacing)
        lineHeight = try? c.decode(Double.self, forKey: .lineHeight)
        uppercase = try? c.decode(Bool.self, forKey: .uppercase)
        italic = try? c.decode(Bool.self, forKey: .italic)
    }
}

extension BrandFonts {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decode(BrandFont.self, forKey: .title)
        subtitle = try? c.decode(BrandFont.self, forKey: .subtitle)
        heading = try? c.decode(BrandFont.self, forKey: .heading)
        subheading = try? c.decode(BrandFont.self, forKey: .subheading)
        sectionHeader = try? c.decode(BrandFont.self, forKey: .sectionHeader)
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
        photos = (try? c.decode([String].self, forKey: .photos)) ?? []
        graphics = (try? c.decode([String].self, forKey: .graphics)) ?? []
        templates = (try? c.decode([String].self, forKey: .templates)) ?? []
        // One at a time, so a gradient that cannot be read — or is not one
        // of two stops or more — is left out rather than losing the rest,
        // as on the Android twin.
        gradients = ((try? c.decode([Lossy<Paint>].self, forKey: .gradients)) ?? []).compactMap(\.value)
            .filter { $0.kind == "gradient" && ($0.stops?.count ?? 0) >= GradientEditing.minStops }
    }

    /// Photos, graphics, templates and gradients only when there are some, so a kit
    /// without them is written as earlier builds wrote it — the rule both
    /// phones keep.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(palettes, forKey: .palettes)
        try c.encode(fonts, forKey: .fonts)
        try c.encode(logos, forKey: .logos)
        if !photos.isEmpty { try c.encode(photos, forKey: .photos) }
        if !graphics.isEmpty { try c.encode(graphics, forKey: .graphics) }
        if !templates.isEmpty { try c.encode(templates, forKey: .templates) }
        if !gradients.isEmpty { try c.encode(gradients, forKey: .gradients) }
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
/// photo logos, photos and graphics travel inlined as a design package
/// carries its photos — the same {"ext", "data"} entries, under the ids the
/// kit's lists name, an SVG graphic's with "ext" "svg" under the id after
/// "svg:" — and arrive under fresh ids, in a kit of its own. Its templates
/// travel as their ids, kept as they are: a template of that id arrives
/// with a backup, and until then the kit's row passes it over. A clip logo
/// travels as its name only, and is left out where it arrives, on either
/// phone: the Android twin's kit file carries photos alone, and a "videos"
/// entry from an earlier build is passed over by both.
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

    /// The pictures as a design's, one each, in order, so a package's
    /// packing and reading carry them.
    private static func carrier(_ pictures: [String]) -> Design {
        var design = Design(title: "Logos", width: 1000, height: 1000)
        design.pages = [Page(elements: pictures.map { Element.image($0) })]
        return design
    }

    /// What a source travels as in the carrier: an SVG graphic as the media
    /// file it is, a still picture as itself, and nil for a clip or an
    /// animated picture, which no kit file carries.
    private static func travelling(_ src: String) -> String? {
        if BrandKit.svgID(src) != nil { return BrandKit.mediaSource(src) }
        return isStill(src) ? src : nil
    }

    /// The kit's file: its photo logos, photos and graphics inlined and
    /// library pictures drawn, as a design file does. A clip or animated
    /// logo stays as it is — neither it nor a still of it goes in — as the
    /// Android twin writes it.
    static func contents(of kit: BrandKit, mediaDirectory: URL = MediaStore.directory) -> Contents {
        let lists = [kit.logos, kit.photos, kit.graphics]
        let pictures = lists.flatMap { $0.compactMap(travelling) }
        let package = DesignPackage.contents(of: carrier(pictures), mediaDirectory: mediaDirectory)
        let packedPictures = package.design.pages.first?.elements.compactMap(\.src) ?? pictures
        var drawn = packedPictures.makeIterator()
        // Each list in the carrier's order: logos, photos, then graphics.
        let packedLists = lists.map { list in
            list.map { src -> String in
                guard let travels = travelling(src) else { return src }
                let packedSrc = drawn.next() ?? travels
                guard BrandKit.svgID(src) != nil, packedSrc.hasPrefix("media:") else { return packedSrc }
                return BrandKit.svgSource(String(packedSrc.dropFirst(6)))
            }
        }
        var packed = kit
        packed.logos = packedLists[0]
        packed.photos = packedLists[1]
        packed.graphics = packedLists[2]
        return Contents(kit: packed, media: package.media)
    }

    static func export(_ kit: BrandKit, mediaDirectory: URL = MediaStore.directory) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(contents(of: kit, mediaDirectory: mediaDirectory))
    }

    enum KitFileError: LocalizedError {
        case notAKit
        var errorDescription: String? { tr("This file is not a Canvia brand kit.") }
    }

    /// The file's logos that arrive (see carried(_:media:)).
    static func carried(_ contents: Contents) -> [String] {
        carried(contents.kit.logos, media: contents.media)
    }

    /// The sources of one of the file's lists that arrive: a photo whose
    /// file it does not carry is left out, and so is an SVG graphic whose
    /// file it does not carry as an SVG, and every clip or animated logo,
    /// as no kit file carries one; any other — a library picture — is kept
    /// as it is, as the Android twin's BrandKitPackage.relinked keeps them.
    static func carried(_ list: [String], media: [String: DesignPackage.Media]) -> [String] {
        list.filter { src in
            if let id = BrandKit.svgID(src) { return media[id]?.ext.lowercased() == MediaStore.graphicExtension }
            if src.hasPrefix("media:") { return media[String(src.dropFirst(6))] != nil }
            return isStill(src)
        }
    }

    /// Whether a logo is a picture a kit file carries: not a clip, nor an
    /// animated picture.
    private static func isStill(_ src: String) -> Bool {
        VideoStore.split(src) == nil && AnimStore.split(src) == nil
    }

    /// The kit inside, with its logos, photos and graphics stored under
    /// fresh ids, a fresh id of its own and a name no kit here has ("My
    /// brand 2"), added to `kits` and made active.
    @discardableResult
    static func `import`(_ data: Data, into kits: inout BrandKits,
                         mediaDirectory: URL = MediaStore.directory) throws -> BrandKit {
        guard let contents = try? JSONDecoder().decode(Contents.self, from: data),
              contents.format == format else { throw KitFileError.notAKit }
        let lists = [contents.kit.logos, contents.kit.photos, contents.kit.graphics]
            .map { carried($0, media: contents.media) }
        let pictures = lists.flatMap { $0.map(BrandKit.mediaSource) }
        let package = DesignPackage.Package(design: carrier(pictures), media: contents.media)
        let stored = try DesignPackage.import(DesignPackage.encode(package), mediaDirectory: mediaDirectory,
                                              normalize: false)
        var arrived = (stored.pages.first?.elements.compactMap(\.src) ?? []).makeIterator()
        let storedLists = lists.map { list in
            list.compactMap { src -> String? in
                guard let storedSrc = arrived.next() else { return nil }
                guard BrandKit.svgID(src) != nil, storedSrc.hasPrefix("media:") else { return storedSrc }
                return BrandKit.svgSource(String(storedSrc.dropFirst(6)))
            }
        }
        var kit = contents.kit
        kit.id = UID.make("kit")
        kit.name = Titles.unique(kit.name, taken: kits.kits.map(\.name))
        kit.logos = storedLists[0]
        kit.photos = storedLists[1]
        kit.graphics = storedLists[2]
        kits.kits.append(kit)
        kits.activeId = kit.id
        return kit
    }
}

/// "Start with my brand", asked in the Start sheet: the design made there,
/// by id, which the editor gives the kit's look as it opens — its first
/// step, which Undo takes back (DesignStore.applyBrandKit).
enum BrandStart {
    static var designId: String?

    /// Whether `id` is the design asked for; asked once.
    static func take(_ id: String) -> Bool {
        guard designId == id else { return false }
        designId = nil
        return true
    }
}
