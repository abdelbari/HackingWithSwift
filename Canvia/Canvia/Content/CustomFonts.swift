// Fonts of your own: a .ttf or .otf added from the font picker, kept on this
// phone as fonts/<sha12>.<ext> — the first twelve hex digits of the file's
// SHA-1, so the same file added twice, or arriving in a design, is one font —
// and listed in uploads.json with kind "font" and the family name read from
// the file (see Uploads and FontStore).
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

import Foundation
import CryptoKit

enum CustomFonts {

    static let prefix = "custom:"

    /// The largest font that can be added, or that travels in a package.
    static let maxBytes = 10 * 1024 * 1024

    /// What the font picker's row for adding one says.
    static let addTitle = "Add a font…"

    /// A font a design uses, as it records it.
    struct Record: Codable, Equatable, Hashable, Sendable {
        var id: String
        var name: String
        var file: String

        var sha: String { String(id.dropFirst(CustomFonts.prefix.count)) }

        init(id: String, name: String, file: String) {
            self.id = id
            self.name = name
            self.file = file
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
        }

        private enum CodingKeys: String, CodingKey { case id, name, file }
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
    static func missing(_ name: String) -> String { "Font missing: \(name)" }

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

    /// The hashes of the fonts of your own the design's texts are set in,
    /// each once, in page order.
    static func used(in design: Design) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for page in design.pages {
            for el in page.elements {
                if let sha = sha(el.fontFamily), seen.insert(sha).inserted { out.append(sha) }
            }
        }
        return out
    }

    /// The design with its record of fonts brought up to date, as every save
    /// writes it: one entry for each font of your own still used, in
    /// used(in:)'s order, the entry it had kept as it was, and a new one made
    /// from `installed` — this phone's font of that hash, if it has it.
    static func synced(_ design: Design, installed: (String) -> Record?) -> Design {
        let had = records(in: design)
        var byID: [String: Record] = [:]
        for record in had where byID[record.id] == nil { byID[record.id] = record }
        let now = used(in: design).compactMap { sha in byID[key(sha)] ?? installed(sha) }
        // Unchanged, the design is left as it was — unless it holds an empty
        // list, which is no record at all.
        if now == had && design.fonts?.isEmpty != true { return design }
        return with(design, now)
    }

    /// The entries the design records for the fonts of your own `elements`
    /// are set in, each once, in their order: what a copy of them carries,
    /// so a paste into another design still names a font this phone does
    /// not have.
    static func carried(_ elements: [Element], from design: Design) -> [Record] {
        let had = records(in: design)
        var seen = Set<String>()
        return elements.compactMap { el -> Record? in
            guard let found = sha(el.fontFamily), seen.insert(found).inserted else { return nil }
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

        var message: String { rawValue }
        var errorDescription: String? { rawValue }
    }

    /// The bytes as a font to add, or what is wrong with them: a collection
    /// (.ttc), something past maxBytes, or no TrueType or OpenType font with
    /// a family name. Whether the phone can draw it is the app's to find
    /// out, by loading it (FontStore).
    static func check(_ data: Data) -> Result<Checked, Problem> {
        if data.count > maxBytes { return .failure(.tooBig) }
        let ext: String
        switch tag(data) {
        case 0x0001_0000, trueTag: ext = "ttf"
        case ottoTag: ext = "otf"
        case ttcfTag: return .failure(.collection)
        default: return .failure(.notAFont)
        }
        guard let name = familyName(data) else { return .failure(.notAFont) }
        return .success(Checked(ext: ext, name: name))
    }

    /// "true", an old Mac TrueType.
    private static let trueTag: UInt32 = 0x7472_7565
    /// "OTTO", OpenType with CFF outlines.
    private static let ottoTag: UInt32 = 0x4F54_544F
    /// "ttcf", a collection.
    private static let ttcfTag: UInt32 = 0x7474_6366

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
        let b = [UInt8](data)
        func u16(_ at: Int) -> Int? {
            guard at >= 0, at + 2 <= b.count else { return nil }
            return Int(b[at]) << 8 | Int(b[at + 1])
        }
        func u32(_ at: Int) -> Int? {
            guard let high = u16(at), let low = u16(at + 2) else { return nil }
            return high << 16 | low
        }
        guard let tables = u16(4) else { return nil }
        var table: Int?
        for i in 0..<tables {
            let at = 12 + 16 * i
            if u32(at) == 0x6E61_6D65 { table = u32(at + 8) } // "name"
        }
        guard let table, let count = u16(table + 2), let base = u16(table + 4) else { return nil }
        let strings = table + base
        // Best rank by name id: 0 Windows English, 1 Mac Roman, 2 Unicode.
        var found: [Int: (rank: Int, text: String)] = [:]
        for i in 0..<count {
            let at = table + 6 + 12 * i
            guard let platform = u16(at), let encoding = u16(at + 2), let language = u16(at + 4),
                  let id = u16(at + 6), let length = u16(at + 8), let offset = u16(at + 10) else { return nil }
            guard id == 1 || id == 16 else { continue }
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
        let family = (found[16] ?? found[1])?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let family, !family.isEmpty else { return nil }
        return family
    }
}
