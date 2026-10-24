// Fonts of your own: a .ttf, .otf or .woff added from the font picker, kept
// on this phone as fonts/<sha12>.<ext> — the first twelve hex digits of the
// file's SHA-1, so the same file added twice, or arriving in a design, is
// one font — and listed in uploads.json with kind "font" and the family
// name read from the file (see Uploads and FontStore). A WOFF is unpacked
// into the TrueType or OpenType font it wraps first (sfnt), and that is
// what is kept and hashed, as .ttf; a WOFF2 is unpacked by the decoder both
// phones share (Woff2, Brotli), so its bytes and hash are the same on each
// — CoreText reads only one that decoder cannot (woff2Font), and one
// neither reads is refused.
//
// Several can be added at once, and a whole family: a picked .zip gives up
// its .ttf, .otf and .woff faces, and a .ttc or .otc collection is split
// into its fonts (expand), each then added as one file is; the picker says
// what came of them all in one line (importSummary).
//
// A text set in one stores fontFamily "custom:<sha12>", and the design
// records the fonts its texts use under the top-level key "fonts":
// [{"id": "custom:<sha12>", "name": "Acme Sans", "file": "<sha12>.ttf"}],
// written only when one is used and brought up to date on every save
// (synced), so a phone without the file can still say which font is
// missing. Such a text draws in Modern Sans, and the text controls say
// "Font missing: <name>". A .canvia.json package carries each font's bytes
// (see DesignPackage), up to maxBytes each. The Android twin's CustomFonts,
// rule for rule.
//
// Fonts of your own are grouped into families. Adding one also reads its
// face (describe): the subfamily (name 17, else 2), the OS/2 weight class
// and italic bit (else 400 and upright), and a variable font's wght axis.
// uploads.json keeps them as "family", "weight", "italic" and "axes":
// {"wght": [min, max]}, and the design's record as "family", "weight" and
// "italic" — every face of each family a text uses — so the other phone
// knows the grouping before it has the files. A text keeps the key of the
// face it was set in — the family's Regular, as the picker sets it — and is
// drawn from the face of that family nearest its weight and italic
// (drawnFace), so fontWeight 700 draws from the Bold file. A variable font
// offers each hundred from 100 to 900 inside its axis.

import Foundation
import CoreText
import CryptoKit

enum CustomFonts {

    static let prefix = "custom:"

    /// The largest font that can be added, or that travels in a package.
    static let maxBytes = 10 * 1024 * 1024

    /// What the font picker's row for adding one says.
    static let addTitle = tr("Add a font…")

    /// A font a design uses, as it records it.
    struct Record: Codable, Equatable, Hashable, Sendable {
        var id: String
        var name: String
        var file: String
        /// The face's family, weight and italic, as uploads.json keeps them;
        /// nil in a record an earlier build wrote.
        var family: String?
        var weight: Int?
        var italic: Bool?

        var sha: String { String(id.dropFirst(CustomFonts.prefix.count)) }

        init(id: String, name: String, file: String, family: String? = nil, weight: Int? = nil, italic: Bool? = nil) {
            self.id = id
            self.name = name
            self.file = file
            self.family = family
            self.weight = weight
            self.italic = italic
        }

        /// Only an entry with a key of your own and a name reads; one with
        /// no file is taken to be a .ttf, as the Android twin reads it.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = try c.decode(String.self, forKey: .id)
            guard let sha = CustomFonts.sha(id) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "not a font of your own")
            }
            self.id = id
            name = try c.decode(String.self, forKey: .name)
            file = (try? c.decode(String.self, forKey: .file)) ?? "\(sha).ttf"
            family = try? c.decodeIfPresent(String.self, forKey: .family)
            weight = try? c.decodeIfPresent(Int.self, forKey: .weight)
            italic = try? c.decodeIfPresent(Bool.self, forKey: .italic)
        }

        private enum CodingKeys: String, CodingKey { case id, name, file, family, weight, italic }
    }

    /// One entry of a design's record that may not read: those that do not
    /// are passed over rather than losing the design's others.
    struct Lenient: Decodable {
        var record: Record?

        init(from decoder: Decoder) throws {
            record = try? Record(from: decoder)
        }
    }

    static func isCustom(_ key: String?) -> Bool {
        key?.hasPrefix(prefix) == true
    }

    /// The file hash a key names, or nil when it is not a font of your own.
    static func sha(_ key: String?) -> String? {
        guard let key, isCustom(key) else { return nil }
        let sha = String(key.dropFirst(prefix.count))
        guard sha.count == 12, sha.allSatisfy({ $0.isASCII && $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return sha
    }

    static func key(_ sha: String) -> String { prefix + sha }

    /// The first twelve hex digits of the bytes' SHA-1: the font's name on
    /// disk and in every design.
    static func sha12(_ data: Data) -> String {
        String(Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(12))
    }

    /// What the text controls say for a font that is not on this phone.
    static func missing(_ name: String) -> String { tr("Font missing: %@", name) }

    // MARK: the design's record

    /// The fonts of your own the design records.
    static func records(in design: Design) -> [Record] {
        design.fonts ?? []
    }

    /// The design recording `records`; none takes the key out.
    static func with(_ design: Design, _ records: [Record]) -> Design {
        var out = design
        out.fonts = records.isEmpty ? nil : records
        return out
    }

    /// The hashes of the fonts of your own the design's texts are set in —
    /// a box's words' too — each once, in page order, each followed by the
    /// other faces of its family among `faces` (this phone's, FontStore.faces),
    /// lowest hash first: a bold word draws from the Bold file, so it travels
    /// and is recorded with the Regular a text is set in. The Android twin's
    /// CustomFonts.used, hash for hash.
    static func used(in design: Design, faces: [Uploads.FontEntry] = []) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for page in design.pages {
            for el in page.elements {
                for key in el.fontKeys {
                    guard let sha = sha(key) else { continue }
                    let family = siblings(of: sha, among: faces).map(\.id).sorted()
                    for one in [sha] + family {
                        if seen.insert(one).inserted { out.append(one) }
                    }
                }
            }
        }
        return out
    }

    /// The design with its record of fonts brought up to date, as every save
    /// writes it: one entry for each font of your own still used — with the
    /// other faces of its family among `faces` (used(in:faces:)) — in that
    /// order, the entry it had kept as it was, and a new one made from
    /// `installed` — this phone's font of that hash, if it has it. An entry
    /// an earlier build wrote, with no family, weight or italic, gains this
    /// phone's (withFace), so the other phone groups its faces too — its
    /// texts first given their face's weight and italic (keptFaces), as
    /// that missing family is the only sign they were set before families.
    /// Opening a design does the same, so what shows is what is saved.
    static func synced(_ design: Design, installed: (String) -> Record?,
                       faces: [Uploads.FontEntry] = []) -> Design {
        syncedKept(keptFaces(design, faces: faces), installed: installed, faces: faces)
    }

    private static func syncedKept(_ design: Design, installed: (String) -> Record?,
                                   faces: [Uploads.FontEntry]) -> Design {
        let had = records(in: design)
        var byID: [String: Record] = [:]
        for record in had where byID[record.id] == nil { byID[record.id] = record }
        let now = used(in: design, faces: faces).compactMap { sha -> Record? in
            guard let kept = byID[key(sha)] else { return installed(sha) }
            return withFace(kept, installed: installed)
        }
        // Unchanged, the design is left as it was — unless it holds an empty
        // list, which is no record at all.
        if now == had && design.fonts?.isEmpty != true { return design }
        return with(design, now)
    }

    /// `record` with the family, weight and italic it lacks taken from
    /// `installed`'s entry for its hash, its id, name and file kept; itself
    /// when it lacks none or this phone has no such font. The Android
    /// twin's rule.
    private static func withFace(_ record: Record, installed: (String) -> Record?) -> Record {
        if record.family != nil && record.weight != nil && record.italic != nil { return record }
        guard let here = installed(record.sha) else { return record }
        var out = record
        out.family = record.family ?? here.family
        out.weight = record.weight ?? here.weight
        out.italic = record.italic ?? here.italic
        return out
    }

    /// The design with each element an earlier build set in a face of your
    /// own that is not a Regular — a Bold, Light or Italic file — given that
    /// face's weight, and its italic when it is one. Before faces were
    /// grouped into families each file was its own font, drawn at its own
    /// weight and slant whatever the text asked, and the picker left the
    /// text's weight (400) as it was; now the face nearest that weight would
    /// be drawn, the family's Regular. Only for a font the design records
    /// with no family — the mark of an earlier build's record, which a save
    /// then fills in (synced) — and that is among `faces`. A word's own font
    /// is left as it is: words hold no weight of their own. Unchanged when
    /// nothing changes. The Android twin's CustomFonts.keptFaces.
    static func keptFaces(_ design: Design, faces: [Uploads.FontEntry]) -> Design {
        let earlier = Set(records(in: design).filter { $0.family == nil }.map(\.id))
        if earlier.isEmpty || faces.isEmpty { return design }
        var out = design
        for p in out.pages.indices {
            for e in out.pages[p].elements.indices {
                if let kept = keptFace(out.pages[p].elements[e], earlier: earlier, faces: faces) {
                    out.pages[p].elements[e] = kept
                }
            }
        }
        return out
    }

    /// The element at its own face's weight and italic (keptFaces' rule),
    /// or nil when it keeps its own.
    private static func keptFace(_ el: Element, earlier: Set<String>, faces: [Uploads.FontEntry]) -> Element? {
        guard let key = el.fontFamily, earlier.contains(key), let sha = sha(key),
              let face = faces.first(where: { $0.id == sha }) else { return nil }
        if face.weight == 400 && !face.italic { return nil }
        let italic: Bool? = face.italic ? true : el.italic
        if el.fontWeight == face.weight && el.italic == italic { return nil }
        var out = el
        out.fontWeight = face.weight
        out.italic = italic
        return out
    }

    /// The entries the design records for the fonts of your own `elements`
    /// are set in, each once, in their order: what a copy of them carries,
    /// so a paste into another design still names a font this phone does
    /// not have.
    static func carried(_ elements: [Element], from design: Design) -> [Record] {
        let had = records(in: design)
        var seen = Set<String>()
        return elements.flatMap(\.fontKeys).compactMap { family -> Record? in
            guard let found = sha(family), seen.insert(found).inserted else { return nil }
            return had.first { $0.id == key(found) }
        }
    }

    /// The design recording, after its own, each of `brought` it has no
    /// entry for: what a paste brings with it. Unchanged when it lacks none.
    static func adopting(_ brought: [Record], into design: Design) -> Design {
        let had = records(in: design)
        var ids = Set(had.map(\.id))
        let more = brought.filter { ids.insert($0.id).inserted }
        return more.isEmpty ? design : with(design, had + more)
    }

    /// The name the design records for `key`, if it records one.
    static func name(in design: Design, of key: String?) -> String? {
        records(in: design).first { $0.id == key }?.name
    }

    // MARK: the file

    /// A font file that can be added: its extension, and its family's name.
    struct Checked: Equatable {
        var ext: String
        var name: String
    }

    /// Why a file cannot be added, in the words the picker says it in.
    enum Problem: String, Error, LocalizedError {
        case tooBig = "That font is over 10 MB. Choose a smaller one."
        case collection = "That is a font collection. Choose a single .ttf or .otf font."
        case notAFont = "That file is not a font Canvia can use."
        case woff2 = "WOFF2 fonts aren't supported yet. Convert it to .ttf or .otf first."

        var message: String { tr(rawValue) }
        var errorDescription: String? { tr(rawValue) }
    }

    /// The bytes as a font to add, or what is wrong with them: a collection
    /// (.ttc), something past maxBytes, a WOFF2, or no TrueType or OpenType
    /// font with a family name. A WOFF is checked as the font it unpacks to
    /// (sfnt), which is kept as .ttf. Whether the phone can draw it is the
    /// app's to find out, by loading it (FontStore).
    static func check(_ data: Data) -> Result<Checked, Problem> {
        unpacked(data).map { $0.checked }
    }

    /// check, with the bytes the add flow keeps: the file's own, or for a
    /// WOFF the font it wraps.
    static func unpacked(_ data: Data) -> Result<(checked: Checked, font: Data), Problem> {
        let font: Data
        switch sfnt(data) {
        case .success(let bytes): font = bytes
        case .failure(let problem): return .failure(problem)
        }
        let ext: String
        switch tag(font) {
        case 0x0001_0000, trueTag: ext = "ttf"
        case ottoTag: ext = font.count == data.count && font == data ? "otf" : "ttf"
        case ttcfTag: return .failure(.collection)
        default: return .failure(.notAFont)
        }
        guard let name = familyName(font) else { return .failure(.notAFont) }
        return .success((Checked(ext: ext, name: name), font))
    }

    /// "true", an old Mac TrueType.
    private static let trueTag: UInt32 = 0x7472_7565
    /// "OTTO", OpenType with CFF outlines.
    private static let ottoTag: UInt32 = 0x4F54_544F
    /// "ttcf", a collection.
    private static let ttcfTag: UInt32 = 0x7474_6366
    /// "wOFF", a web font wrapping an sfnt.
    private static let woffTag: UInt32 = 0x774F_4646
    /// "wOF2", a web font Brotli-compressed (Woff2).
    private static let woff2Tag: UInt32 = 0x774F_4632

    /// The TrueType or OpenType font `data` holds, as the add flow stores
    /// it: the bytes themselves, or for a WOFF the sfnt it wraps
    /// (unpackWoff), or for a WOFF2 the font it holds (Woff2) — the same
    /// bytes on both phones. Past maxBytes either way, or a web font that
    /// does not unpack, is refused.
    static func sfnt(_ data: Data) -> Result<Data, Problem> {
        if data.count > maxBytes { return .failure(.tooBig) }
        switch tag(data) {
        case woff2Tag:
            // Past maxBytes by the size it says it unpacks to: refused
            // before anything is unpacked. Then the shared decoder (Woff2),
            // so the bytes kept, and their hash, are the Android twin's;
            // CoreText only for one the decoder cannot read.
            if let declared = Sfnt([UInt8](data.prefix(20))).u32(16), declared > maxBytes { return .failure(.tooBig) }
            guard let font = Woff2.unpack(data, limit: maxBytes) ?? woff2Font(data) else { return .failure(.notAFont) }
            return font.count > maxBytes ? .failure(.tooBig) : .success(font)
        case woffTag:
            // Past maxBytes by the size it says it unpacks to: refused
            // before anything is unpacked.
            if let declared = Sfnt([UInt8](data.prefix(20))).u32(16), declared > maxBytes { return .failure(.tooBig) }
            guard let font = unpackWoff(data) else { return .failure(.notAFont) }
            return font.count > maxBytes ? .failure(.tooBig) : .success(font)
        default:
            return .success(data)
        }
    }

    /// A WOFF's sfnt, unpacked in pure code, the rule both phones share: the
    /// table directory read (tag, offset, compressed and original lengths,
    /// checksum, 20 bytes a table after the 44-byte header), each table
    /// inflated where its compressed length is under its original (a zlib
    /// stream: ZipStore's inflate over what follows its 2-byte header), and
    /// an sfnt written in the directory's order — the WOFF's flavour, the
    /// table count with its search fields, 16-byte records with the
    /// original checksums and recomputed offsets, each table padded to 4
    /// bytes. Nil when the file does not read as one.
    static func unpackWoff(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        let woff = Sfnt(bytes)
        guard bytes.count >= 44, tag(data) == woffTag, let flavor = woff.u32(4), let count = woff.u16(12),
              count > 0, 44 + 20 * count <= bytes.count else { return nil }
        var tables: [(tag: Int, checksum: Int, data: Data)] = []
        // The sfnt's size so far, from the directory's own lengths: past
        // maxBytes, a table is never inflated, so a file that claims more
        // than it can hold never asks for the memory.
        var total = 12 + 16 * count
        for i in 0..<count {
            let at = 44 + 20 * i
            guard let tag = woff.u32(at), let offset = woff.u32(at + 4), let compLength = woff.u32(at + 8),
                  let origLength = woff.u32(at + 12), let checksum = woff.u32(at + 16),
                  offset + compLength <= bytes.count else { return nil }
            total += (origLength + 3) & ~3
            guard total <= maxBytes else { return nil }
            let packed = Data(bytes[offset..<(offset + compLength)])
            let table: Data
            if compLength < origLength {
                guard let inflated = inflated(packed, length: origLength) else { return nil }
                table = inflated
            } else {
                table = packed
            }
            guard table.count == origLength else { return nil }
            tables.append((tag, checksum, table))
        }
        return written(flavor: flavor, tables)
    }

    /// An sfnt of `tables`, in their order: the flavour, the table count
    /// with its search fields, 16-byte records with the given checksums and
    /// offsets worked out, each table padded to 4 bytes.
    private static func written(flavor: Int, _ tables: [(tag: Int, checksum: Int, data: Data)]) -> Data {
        let count = tables.count
        var searchRange = 1
        var entrySelector = 0
        while searchRange * 2 <= count {
            searchRange *= 2
            entrySelector += 1
        }
        searchRange *= 16
        var out = Data()
        func u32(_ v: Int) {
            for shift in [24, 16, 8, 0] { out.append(UInt8((v >> shift) & 0xFF)) }
        }
        func u16(_ v: Int) {
            out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8(v & 0xFF))
        }
        u32(flavor); u16(count); u16(searchRange); u16(entrySelector); u16(count * 16 - searchRange)
        var offset = 12 + 16 * count
        for table in tables {
            u32(table.tag); u32(table.checksum); u32(offset); u32(table.data.count)
            offset += (table.data.count + 3) & ~3
        }
        for table in tables {
            out.append(table.data)
            let padded = (table.data.count + 3) & ~3
            if padded > table.data.count { out.append(Data(count: padded - table.data.count)) }
        }
        return out
    }

    /// `packed`, a zlib stream — its 2-byte header, the deflated bytes, its
    /// check — inflated to `length` bytes; nil when it is not one, or is
    /// not that long.
    private static func inflated(_ packed: Data, length: Int) -> Data? {
        guard packed.count > 2 else { return nil }
        return ZipStore.inflate(packed.dropFirst(2), size: length)
    }

    /// The file's first four bytes, as a tag; nought for a shorter one.
    private static func tag(_ data: Data) -> UInt32 {
        guard data.count >= 4 else { return 0 }
        return data.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    /// The family a font file names itself: the typographic family (name 16)
    /// when it has one, else the family (name 1) — Windows English first,
    /// then the Mac's, then Unicode's. Nil when there is no name table that
    /// reads.
    static func familyName(_ data: Data) -> String? {
        guard let names = Sfnt([UInt8](data)).names() else { return nil }
        let family = (names[16] ?? names[1])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let family, !family.isEmpty else { return nil }
        return family
    }

    // MARK: several at once

    /// The largest file the picker reads: a family's .zip holds many faces,
    /// each still no more than maxBytes.
    static let maxPickedBytes = 64 * 1024 * 1024

    /// The most fonts one picked file — a family's .zip, a collection —
    /// brings in.
    static let maxFaces = 64

    /// The fonts a picked file holds, each with its file's name, the rule
    /// both phones share: a .zip's entries ending .ttf, .otf or .woff (any
    /// case), in the order of their paths (as strings, so the archive's own
    /// order does not matter), none under __MACOSX nor a hidden "." file —
    /// only those in a "static" folder when it has any, as a family
    /// downloaded from Google Fonts keeps its static faces beside the
    /// variable file; a .ttc or .otc collection's fonts each on its own
    /// (split), "<name>-1.ttf", "<name>-2.ttf"…; any other file, or a
    /// collection that does not split, as it is. At most maxFaces.
    static func expand(_ data: Data, name: String) -> [(name: String, data: Data)] {
        let out: [(name: String, data: Data)]
        if tag(data) == ttcfTag {
            out = split(data, name: name) ?? [(name, data)]
        } else if tag(data) == zipTag {
            out = unzipped(data)
        } else {
            out = [(name, data)]
        }
        return Array(out.prefix(maxFaces))
    }

    /// "PK\3\4", a ZIP's first entry.
    private static let zipTag: UInt32 = 0x504B_0304

    private static func unzipped(_ data: Data) -> [(name: String, data: Data)] {
        guard let reader = try? ZipStore.Reader(data: data, inflating: true) else { return [] }
        let fonts = reader.entries.keys.filter { path in
            let parts = path.split(separator: "/")
            guard let file = parts.last, !file.hasPrefix("."),
                  !parts.dropLast().contains("__MACOSX") else { return false }
            let lower = file.lowercased()
            return lower.hasSuffix(".ttf") || lower.hasSuffix(".otf") || lower.hasSuffix(".woff")
        }.sorted()
        let statics = fonts.filter { $0.split(separator: "/").dropLast().contains("static") }
        return (statics.isEmpty ? fonts : statics).compactMap { path -> (name: String, data: Data)? in
            guard let bytes = reader.file(path) else { return nil }
            return (String(path.split(separator: "/").last ?? Substring(path)), bytes)
        }
    }

    /// A collection's fonts, each on its own (standalone); nil when it is
    /// not one that reads, or holds more than maxFaces.
    private static func split(_ data: Data, name: String) -> [(name: String, data: Data)]? {
        let file = Sfnt([UInt8](data))
        guard let count = file.u32(8), count > 0, count <= maxFaces, 12 + 4 * count <= file.b.count else { return nil }
        let base = (name as NSString).deletingPathExtension
        var out: [(name: String, data: Data)] = []
        for i in 0..<count {
            guard let at = file.u32(12 + 4 * i), let font = standalone(file, at: at) else { return nil }
            out.append(("\(base)-\(i + 1).ttf", font))
        }
        return out
    }

    /// The font whose offset table is at `at` in a collection, as a file of
    /// its own — the rule both phones share (the Android twin's
    /// CustomFonts.split): its flavour, then its tables in its records'
    /// order, each with its checksum as it is, written as every font put
    /// together here is (written). Nil when it does not read.
    private static func standalone(_ file: Sfnt, at: Int) -> Data? {
        guard let flavor = file.u32(at), let count = file.u16(at + 4), count > 0,
              at + 12 + 16 * count <= file.b.count else { return nil }
        var tables: [(tag: Int, checksum: Int, data: Data)] = []
        for i in 0..<count {
            let r = at + 12 + 16 * i
            guard let tag = file.u32(r), let checksum = file.u32(r + 4), let from = file.u32(r + 8),
                  let length = file.u32(r + 12), from + length <= file.b.count else { return nil }
            tables.append((tag, checksum, Data(file.b[from..<(from + length)])))
        }
        return written(flavor: flavor, tables)
    }

    /// A WOFF2's font as CoreText reads it — for one the shared decoder
    /// (Woff2) cannot — each table CoreText gives written by the decoder's
    /// own rule (Woff2.font): sorted by tag, each checksum worked out, and
    /// head's checksum adjustment set last; CFF outlines are OpenType. Nil
    /// when CoreText cannot read it either.
    static func woff2Font(_ data: Data) -> Data? {
        guard let descriptor = (CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor])?.first
        else { return nil }
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        guard let available = CTFontCopyAvailableTables(font, []) else { return nil }
        var tables: [(tag: Int, data: [UInt8])] = []
        for i in 0..<CFArrayGetCount(available) {
            let tag = Int(UInt(bitPattern: CFArrayGetValueAtIndex(available, i)))
            guard let table = CTFontCopyTable(font, CTFontTableTag(truncatingIfNeeded: tag), []) as Data? else { return nil }
            tables.append((tag, [UInt8](table)))
        }
        guard !tables.isEmpty else { return nil }
        let flavor = tables.contains { $0.tag == 0x4346_4620 } ? Int(ottoTag) : 0x0001_0000 // "CFF "
        return Woff2.font(flavor: flavor, tables: tables, limit: maxBytes).map { Data($0) }
    }

    /// What adding several fonts came to, in one line: "Added Inter: 9
    /// styles", with "; skipped 2 files" after it when some were not added
    /// — or "Skipped 2 files" alone. `families` are the families added, in
    /// order, each once; `styles` how many faces went in.
    static func importSummary(families: [String], styles: Int, skipped: Int) -> String {
        let skippedPart = trn("skipped %d file|skipped %d files", skipped)
        guard styles > 0 else { return trn("Skipped %d file|Skipped %d files", skipped) }
        let added = tr("Added %@: %@", families.joined(separator: ", "), trn("%d style|%d styles", styles))
        return skipped > 0 ? added + "; " + skippedPart : added
    }

    /// One file left out, and why: "Bold.ttf: That file is not a font
    /// Canvia can use."
    static func skippedLine(_ name: String, _ problem: Problem) -> String {
        tr("%@: %@", name, problem.message)
    }

    // MARK: faces and families

    /// A variable font's wght axis: its least, greatest and default weight.
    struct Axis: Equatable, Sendable {
        var min: Double
        var max: Double
        var defaultValue: Double
    }

    /// What a font file says of its face.
    struct Face: Equatable, Sendable {
        var family: String
        /// "Bold Italic": the typographic subfamily (name 17), else name 2.
        var subfamily: String?
        var weight: Int
        var italic: Bool
        var wght: Axis?
        /// The scripts it covers (FontLibrary.scriptKeys), from its cmap;
        /// nil for a font with no cmap.
        var scripts: [String]? = nil
    }

    /// The face a font file is, by the rule both phones keep (the Android
    /// twin's CustomFonts.style): its family as familyName reads it, its
    /// subfamily (name 17, else 2) as it is written; its weight the OS/2
    /// weight class, else 400 — a variable font's too, whatever its axis's
    /// default — and italic the OS/2 italic bit (fsSelection bit 0), else
    /// upright. The subfamily's words decide neither. Nil when it names no
    /// family.
    static func describe(_ data: Data) -> Face? {
        let sfnt = Sfnt([UInt8](data))
        guard let names = sfnt.names() else { return nil }
        let family = (names[16] ?? names[1])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let family, !family.isEmpty else { return nil }
        let subfamily = (names[17] ?? names[2])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let os2 = sfnt.table(0x4F53_2F32) // "OS/2"
        let weightClass = os2.flatMap { sfnt.u16($0 + 4) }.flatMap { (1...1000).contains($0) ? $0 : nil }
        let selection = os2.flatMap { sfnt.u16($0 + 62) }
        let italic = selection.map { $0 & 1 == 1 } ?? false
        let scripts = sfnt.table(0x636D_6170) == nil ? nil : FontLibrary.scriptsCovered(sfnt.codePoints()) // "cmap"
        return Face(family: family, subfamily: subfamily, weight: weightClass ?? 400, italic: italic,
                    wght: sfnt.wghtAxis(), scripts: scripts)
    }

    /// The scripts a face covers (FontLibrary.scriptsCovered), from its
    /// cmap (codePoints) — what the generator writes for the bundled
    /// families, by the same rule.
    static func scripts(_ data: Data) -> [String] {
        FontLibrary.scriptsCovered(codePoints(data))
    }

    /// The code points a face's cmap maps to a glyph other than .notdef:
    /// its best Unicode subtable — (3,10), (0,4), (3,1), then (0,3) — of
    /// format 4 or 12, as the Android twin's tools/generate_fonts.py reads
    /// it. None when it has neither.
    static func codePoints(_ data: Data) -> Set<UInt32> {
        Sfnt([UInt8](data)).codePoints()
    }

    /// The weights a variable font offers: each hundred from 100 to 900
    /// inside its axis.
    static func variableWeights(_ axis: ClosedRange<Double>) -> [Int] {
        stride(from: 100, through: 900, by: 100).filter { axis.contains(Double($0)) }
    }

    /// The weights one face offers: a variable font's hundreds, or — a
    /// static face, or an axis narrower than any hundred — its own.
    static func offered(_ face: Uploads.FontEntry) -> [Int] {
        let variable = face.wght.map(variableWeights) ?? []
        return variable.isEmpty ? [face.weight] : variable
    }

    /// The faces of the family the font `sha` is in, itself among them;
    /// none when it is not among `faces`.
    static func siblings(of sha: String, among faces: [Uploads.FontEntry]) -> [Uploads.FontEntry] {
        guard let own = faces.first(where: { $0.id == sha }) else { return [] }
        return faces.filter { $0.family == own.family }
    }

    /// The weights the family of the font `sha` offers, lightest first: its
    /// upright faces', or every face's when it has no upright one. None
    /// when the font is not among `faces`.
    static func weights(of sha: String, among faces: [Uploads.FontEntry]) -> [Int] {
        let family = siblings(of: sha, among: faces)
        let upright = family.filter { !$0.italic }
        return Array(Set((upright.isEmpty ? family : upright).flatMap(offered))).sorted()
    }

    /// The weight of the font `key`'s own face, or nil when it is not among
    /// `faces`: what a text set in it with no weight of its own is drawn at
    /// (FontLibrary.weight(of:in:)). Before faces were grouped into
    /// families each file was its own font, and a text set in the Bold file
    /// kept no weight; it still draws bold. The Android twin's
    /// CustomFonts.ownWeight.
    static func ownWeight(_ key: String?, among faces: [Uploads.FontEntry]) -> Int? {
        guard let sha = sha(key) else { return nil }
        return faces.first { $0.id == sha }?.weight
    }

    /// Whether the font `key`'s own face is an italic, or nil when it is
    /// not among `faces`: what a text set in it with no slant of its own is
    /// drawn in (ownWeight's rule).
    static func ownItalic(_ key: String?, among faces: [Uploads.FontEntry]) -> Bool? {
        guard let sha = sha(key) else { return nil }
        return faces.first { $0.id == sha }?.italic
    }

    /// The face a text set in the font `sha` at `weight` and `italic` is
    /// drawn from, and the weight it draws at: among the family's faces of
    /// that slant (all of them when it has none), the weight nearest the
    /// one asked, ties to the heavier — FontLibrary's rule — then the
    /// text's own face, then the lowest hash. Nil when the font is not
    /// among `faces`. A variable face draws at the weight chosen; a static
    /// one at its own.
    static func drawnFace(for sha: String, weight: Int, italic: Bool,
                          among faces: [Uploads.FontEntry]) -> (face: Uploads.FontEntry, weight: Int)? {
        let family = siblings(of: sha, among: faces)
        let slanted = family.filter { $0.italic == italic }
        let pool = slanted.isEmpty ? family : slanted
        let choices = pool.flatMap { face in offered(face).map { (face: face, weight: $0) } }
        return choices.min { a, b in
            let da = abs(a.weight - weight), db = abs(b.weight - weight)
            if da != db { return da < db }
            if a.weight != b.weight { return a.weight > b.weight }
            if (a.face.id == sha) != (b.face.id == sha) { return a.face.id == sha }
            return a.face.id < b.face.id
        }
    }

    /// Your fonts as the picker lists them: one family a row, named by it
    /// and keyed by its Regular face — the upright face nearest 400, ties
    /// to the heavier, then the lowest hash — with the weights it offers.
    /// In the order `faces` lists them, by each family's first face.
    struct Family: Equatable, Identifiable {
        var name: String
        var key: String
        var weights: [Int]

        var id: String { key }
    }

    static func families(_ faces: [Uploads.FontEntry]) -> [Family] {
        var seen = Set<String>()
        return faces.compactMap { face -> Family? in
            guard seen.insert(face.family).inserted else { return nil }
            let family = faces.filter { $0.family == face.family }
            let upright = family.filter { !$0.italic }
            let lead = (upright.isEmpty ? family : upright).min { a, b in
                let da = abs(a.weight - 400), db = abs(b.weight - 400)
                if da != db { return da < db }
                if a.weight != b.weight { return a.weight > b.weight }
                return a.id < b.id
            } ?? face
            return Family(name: face.family, key: lead.key, weights: weights(of: lead.id, among: faces))
        }
    }

    /// "3 weights", "1 weight": what a family's row says beside its name.
    static func weightCount(_ count: Int) -> String {
        trn("%d weight|%d weights", count)
    }

    /// The key of the Regular face of the family a design records the font
    /// `key` in — the record of that family nearest 400 upright, as
    /// families(_:) chooses — so a phone without the files still groups
    /// them — a record with no family by its name, as the Android twin's
    /// Record.face groups it; `key` itself when the design has no record of it.
    static func familyKey(_ key: String, in design: Design) -> String {
        let had = records(in: design)
        guard let own = had.first(where: { $0.id == key }) else { return key }
        let name = own.family ?? own.name
        let family = had.filter { ($0.family ?? $0.name) == name }
        let upright = family.filter { $0.italic != true }
        return (upright.isEmpty ? family : upright).min { a, b in
            let da = abs((a.weight ?? 400) - 400), db = abs((b.weight ?? 400) - 400)
            if da != db { return da < db }
            if (a.weight ?? 400) != (b.weight ?? 400) { return (a.weight ?? 400) > (b.weight ?? 400) }
            return a.id < b.id
        }?.id ?? key
    }

    // MARK: reading a font file

    /// A font file's bytes, read big-endian as sfnt is.
    private struct Sfnt {
        let b: [UInt8]

        init(_ bytes: [UInt8]) { b = bytes }

        func u16(_ at: Int) -> Int? {
            guard at >= 0, at + 2 <= b.count else { return nil }
            return Int(b[at]) << 8 | Int(b[at + 1])
        }

        func u32(_ at: Int) -> Int? {
            guard let high = u16(at), let low = u16(at + 2) else { return nil }
            return high << 16 | low
        }

        /// A 16.16 fixed-point number.
        func fixed(_ at: Int) -> Double? {
            u32(at).map { Double(Int32(bitPattern: UInt32($0))) / 65536 }
        }

        /// Where the table `tag` starts; nil when the file has none.
        func table(_ tag: Int) -> Int? {
            guard let tables = u16(4) else { return nil }
            var found: Int?
            for i in 0..<tables {
                let at = 12 + 16 * i
                if u32(at) == tag { found = u32(at + 8) }
            }
            return found
        }

        /// The family and subfamily names (ids 1, 2, 16 and 17), each the
        /// best it has — Windows English, then the Mac's, then Unicode's.
        /// Nil when there is no name table that reads.
        func names() -> [Int: String]? {
            guard let table = table(0x6E61_6D65), // "name"
                  let count = u16(table + 2), let base = u16(table + 4) else { return nil }
            let strings = table + base
            // Best rank by name id: 0 Windows English, 1 Mac Roman, 2 Unicode.
            var found: [Int: (rank: Int, text: String)] = [:]
            for i in 0..<count {
                let at = table + 6 + 12 * i
                guard let platform = u16(at), let encoding = u16(at + 2), let language = u16(at + 4),
                      let id = u16(at + 6), let length = u16(at + 8), let offset = u16(at + 10) else { return nil }
                guard [1, 2, 16, 17].contains(id) else { continue }
                let start = strings + offset
                guard start + length <= b.count else { return nil }
                let raw = Data(b[start..<(start + length)])
                let rank: Int
                let text: String?
                if platform == 3 && language == 0x409 {
                    rank = 0
                    text = String(data: raw, encoding: .utf16BigEndian)
                } else if platform == 1 && encoding == 0 {
                    rank = 1
                    text = String(data: raw, encoding: .isoLatin1)
                } else if platform == 0 {
                    rank = 2
                    text = String(data: raw, encoding: .utf16BigEndian)
                } else {
                    continue
                }
                guard let text else { continue }
                if (found[id]?.rank ?? Int.max) > rank { found[id] = (rank: rank, text: text) }
            }
            return found.mapValues { $0.text }
        }

        /// The code points the best Unicode cmap subtable maps to a glyph
        /// (CustomFonts.codePoints).
        func codePoints() -> Set<UInt32> {
            guard let cmap = table(0x636D_6170), let count = u16(cmap + 2) else { return [] }
            var best: (rank: Int, at: Int, format: Int)?
            for i in 0..<count {
                let at = cmap + 4 + 8 * i
                guard let platform = u16(at), let encoding = u16(at + 2), let offset = u32(at + 4) else { return [] }
                let ranks: [Int: Int] = [3 << 16 | 10: 0, 0 << 16 | 4: 1, 3 << 16 | 1: 2, 0 << 16 | 3: 3]
                guard let rank = ranks[platform << 16 | encoding], let format = u16(cmap + offset),
                      format == 4 || format == 12 else { continue }
                if best == nil || rank < best!.rank { best = (rank, cmap + offset, format) }
            }
            guard let found = best else { return [] }
            return found.format == 4 ? format4(found.at) : format12(found.at)
        }

        /// A format 4 subtable's code points: each segment's characters
        /// whose glyph, by its delta or its glyph array, is not .notdef.
        private func format4(_ at: Int) -> Set<UInt32> {
            guard let seg2 = u16(at + 6) else { return [] }
            let ends = at + 14, starts = ends + seg2 + 2, deltas = starts + seg2, ranges = deltas + seg2
            var out = Set<UInt32>()
            for k in 0..<(seg2 / 2) {
                guard let start = u16(starts + 2 * k), let end = u16(ends + 2 * k), let delta = u16(deltas + 2 * k),
                      let range = u16(ranges + 2 * k), start <= end else { continue }
                for c in start...end where c != 0xFFFF {
                    let glyph: Int
                    if range == 0 {
                        glyph = (c + delta) & 0xFFFF
                    } else {
                        let raw = u16(ranges + 2 * k + range + 2 * (c - start)) ?? 0
                        glyph = raw == 0 ? 0 : (raw + delta) & 0xFFFF
                    }
                    if glyph != 0 { out.insert(UInt32(c)) }
                }
            }
            return out
        }

        /// A format 12 subtable's code points: each group's characters
        /// whose glyph is not .notdef.
        private func format12(_ at: Int) -> Set<UInt32> {
            guard let groups = u32(at + 12), groups <= (b.count - at) / 12 else { return [] }
            var out = Set<UInt32>()
            for k in 0..<groups {
                let g = at + 16 + 12 * k
                guard let start = u32(g), let end = u32(g + 4), let glyph = u32(g + 8),
                      start <= end, end <= 0x10FFFF else { continue }
                for c in start...end where glyph + (c - start) != 0 { out.insert(UInt32(c)) }
            }
            return out
        }

        /// The fvar table's wght axis, when the font is variable in weight.
        func wghtAxis() -> Axis? {
            guard let fvar = table(0x6676_6172), // "fvar"
                  let axes = u16(fvar + 4), let count = u16(fvar + 8), let size = u16(fvar + 10) else { return nil }
            for i in 0..<count {
                let at = fvar + axes + i * size
                guard u32(at) == 0x7767_6874, // "wght"
                      let low = fixed(at + 4), let value = fixed(at + 8), let high = fixed(at + 12),
                      low <= high else { continue }
                return Axis(min: low, max: high, defaultValue: value)
            }
            return nil
        }
    }
}
