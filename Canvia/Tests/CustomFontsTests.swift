// Fonts of your own, as the Android twin's CustomFontsTest has them: the
// key from the file's SHA-1, the checks a file passes before it is added,
// the design's "fonts" record through JSON and kept in step on save, the
// fallback and the words for a missing one, the weight one is drawn at, the
// package carrying the bytes and an import storing them, and the
// uploads.json entry — and fonts grouped into families: the face a file
// says it is (Lora's Regular, Bold and Italic, bundled on both phones),
// the face a text is drawn from, and a variable font's weights.

import XCTest
import CoreText
import UIKit
@testable import Canvia

final class CustomFontsTests: XCTestCase {

    private let acme = CustomFonts.Record(id: "custom:ab12cd34ef56", name: "Acme Sans", file: "ab12cd34ef56.ttf")

    private func design(_ families: String?...) -> Design {
        var d = Design(title: "Fonts")
        d.id = "doc-f"
        d.pages = [Page(id: "p1", elements: families.enumerated().map { pair -> Element in
            var el = Element.text("T\(pair.offset)")
            el.id = "t\(pair.offset)"
            el.fontFamily = pair.element
            return el
        })]
        return d
    }

    private func bundled(_ file: String) throws -> Data {
        try Data(contentsOf: try XCTUnwrap(FontLibrary.bundledURL(file)))
    }

    /// A smallest sfnt: `tag`, then a name table holding `names` (name id
    /// and text), each for Windows English.
    private func font(tag: UInt32, names: [(Int, String)]) -> Data {
        func short(_ value: Int, _ data: inout Data) {
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
        func long(_ value: UInt32, _ data: inout Data) {
            for shift: UInt32 in [24, 16, 8, 0] { data.append(UInt8((value >> shift) & 0xFF)) }
        }
        let strings = names.map { entry in Data(entry.1.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }) }
        var table = Data()
        short(0, &table)
        short(names.count, &table)
        short(6 + 12 * names.count, &table)
        var offset = 0
        for (i, entry) in names.enumerated() {
            for value in [3, 1, 0x409, entry.0, strings[i].count, offset] { short(value, &table) }
            offset += strings[i].count
        }
        for string in strings { table.append(string) }
        var out = Data()
        long(tag, &out)
        short(1, &out); short(16, &out); short(0, &out); short(0, &out)
        long(0x6E61_6D65, &out); long(0, &out); long(28, &out); long(UInt32(table.count), &out)
        out.append(table)
        return out
    }

    func testAFontsKeyIsCustomAndTheFirstTwelveHexOfItsSHA1() {
        // SHA-1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d
        XCTAssertEqual(CustomFonts.sha12(Data("abc".utf8)), "a9993e364706")
        XCTAssertEqual(CustomFonts.key("a9993e364706"), "custom:a9993e364706")
        XCTAssertEqual(CustomFonts.sha("custom:a9993e364706"), "a9993e364706")
        XCTAssertNil(CustomFonts.sha("custom:nope"))
        XCTAssertNil(CustomFonts.sha("lora"))
        XCTAssertTrue(CustomFonts.isCustom("custom:a9993e364706"))
    }

    func testAFileIsCheckedBeforeItIsAdded() throws {
        let ttf = try bundled("lora-400.ttf")
        XCTAssertEqual(try CustomFonts.check(ttf).get(), CustomFonts.Checked(ext: "ttf", name: "Lora"))
        // The typographic family wins over the style-linked one.
        let otf = font(tag: 0x4F54_544F, names: [(1, "Acme Sans Light"), (16, "Acme Sans")])
        XCTAssertEqual(try CustomFonts.check(otf).get(), CustomFonts.Checked(ext: "otf", name: "Acme Sans"))
        XCTAssertEqual(try CustomFonts.check(font(tag: 0x0001_0000, names: [(1, "Acme")])).get(),
                       CustomFonts.Checked(ext: "ttf", name: "Acme"))

        func problem(_ data: Data) -> CustomFonts.Problem? {
            if case .failure(let refusal) = CustomFonts.check(data) { return refusal }
            return nil
        }
        XCTAssertEqual(problem(font(tag: 0x7474_6366, names: [(1, "Acme")])), .collection)
        XCTAssertEqual(problem(Data("<svg/>".utf8)), .notAFont)
        XCTAssertEqual(problem(font(tag: 0x0001_0000, names: [(2, "Regular")])), .notAFont)
        XCTAssertEqual(problem(Data(count: 3)), .notAFont)
        XCTAssertEqual(problem(Data(count: CustomFonts.maxBytes + 1)), .tooBig)
        XCTAssertEqual(CustomFonts.Problem.tooBig.message, "That font is over 10 MB. Choose a smaller one.")
        XCTAssertEqual(CustomFonts.Problem.collection.message, "That is a font collection. Choose a single .ttf or .otf font.")
        XCTAssertEqual(CustomFonts.Problem.notAFont.message, "That file is not a font Canvia can use.")
        // A real font loads as a face, which is the last check before it is kept.
        XCTAssertTrue(FontStore.loads(ttf))
    }

    func testTheDesignsFontsRecordRoundTripsThroughJSONInTheShapeBothPhonesWrite() throws {
        let d = CustomFonts.with(design("custom:ab12cd34ef56"), [acme])
        let data = try JSONEncoder().encode(d)
        XCTAssertEqual(CustomFonts.records(in: try JSONDecoder().decode(Design.self, from: data)), [acme])
        // Top-level "fonts", as the spec writes it.
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fonts = try XCTUnwrap(object["fonts"] as? [[String: String]])
        XCTAssertEqual(fonts, [["id": "custom:ab12cd34ef56", "name": "Acme Sans", "file": "ab12cd34ef56.ttf"]])
        // As the Android twin writes it, an entry that does not read passed over.
        let android = #"{"id":"doc-a","title":"A","width":1080,"height":1080,"pages":[],"fonts":[{"id":"custom:ab12cd34ef56","name":"Acme Sans","file":"ab12cd34ef56.ttf"},{"id":"lora","name":"Lora"},{"id":"custom:0123456789ab","name":"Brand Serif"}]}"#
        let read = try JSONDecoder().decode(Design.self, from: Data(android.utf8))
        XCTAssertEqual(CustomFonts.records(in: read),
                       [acme, CustomFonts.Record(id: "custom:0123456789ab", name: "Brand Serif", file: "0123456789ab.ttf")])
        // None recorded: no key at all.
        let none = try JSONEncoder().encode(CustomFonts.with(d, []))
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: none) as? [String: Any])
        XCTAssertNil(plain["fonts"])
    }

    func testASaveKeepsTheRecordToTheFontsStillUsed() {
        let brand = CustomFonts.Record(id: "custom:0123456789ab", name: "Brand Serif", file: "0123456789ab.otf")
        let installed = ["0123456789ab": brand]
        let start = design("lora", "custom:0123456789ab")
        // A font just chosen is recorded from this phone's copy.
        let saved = CustomFonts.synced(start) { installed[$0] }
        XCTAssertEqual(CustomFonts.records(in: saved), [brand])
        // One no longer used goes; one kept keeps the name it was recorded
        // with, even on a phone without it.
        let other = CustomFonts.with(design("custom:ab12cd34ef56"), [acme, brand])
        XCTAssertEqual(CustomFonts.records(in: CustomFonts.synced(other) { _ in nil }), [acme])
        // No font of your own: nothing written, and a design without one is untouched.
        XCTAssertNil(CustomFonts.synced(CustomFonts.with(design("lora"), [acme])) { _ in nil }.fonts)
        let plain = design("lora")
        XCTAssertEqual(CustomFonts.synced(plain) { _ in nil }, plain)
        XCTAssertEqual(CustomFonts.synced(saved) { _ in nil }, saved)
        XCTAssertEqual(CustomFonts.used(in: design("custom:ab12cd34ef56", "lora", "custom:ab12cd34ef56")), ["ab12cd34ef56"])
    }

    func testACopyCarriesTheRecordsOfItsFontsAndAPasteAddsThoseTheDesignLacks() {
        let brand = CustomFonts.Record(id: "custom:0123456789ab", name: "Brand Serif", file: "0123456789ab.otf")
        let source = CustomFonts.with(
            design("custom:0123456789ab", "lora", "custom:ab12cd34ef56", "custom:0123456789ab", "custom:ffffffffffff"),
            [acme, brand])
        // Each once, in the elements' order; one the design has no entry for brings none.
        XCTAssertEqual(CustomFonts.carried(source.pages[0].elements, from: source), [brand, acme])
        XCTAssertEqual(CustomFonts.carried([Element.text("plain")], from: source), [])
        // The design's own entries first and kept as they are, then those it lacked, each once.
        let target = CustomFonts.with(design("custom:ab12cd34ef56"), [acme])
        var renamed = acme
        renamed.name = "Other"
        XCTAssertEqual(CustomFonts.records(in: CustomFonts.adopting([brand, renamed, brand], into: target)), [acme, brand])
        XCTAssertEqual(CustomFonts.adopting([acme], into: target), target)
        XCTAssertEqual(CustomFonts.adopting([], into: target), target)
    }

    @MainActor
    func testAPastedTextOrPageBringsItsFontsRecordInTheSameStep() throws {
        let s = DesignStore(design: CustomFonts.with(design("custom:ab12cd34ef56"), [acme]))
        s.selection = ["t0"]
        s.copySelected()
        // Into a design with no entry for it, as on another phone.
        s.apply { $0 = CustomFonts.with($0, []) }
        s.paste()
        XCTAssertEqual(CustomFonts.records(in: s.design), [acme])
        XCTAssertEqual(CustomFonts.name(in: s.design, of: "custom:ab12cd34ef56"), "Acme Sans")
        s.undo()
        XCTAssertEqual(CustomFonts.records(in: s.design), [])
        XCTAssertEqual(s.page.elements.count, 1)

        // Across the pasteboard, beside the elements and the page.
        let board = UIPasteboard.withUniqueName()
        ElementClipboard.write(s.page.elements, sourcePage: "p1", fonts: [acme], to: board)
        XCTAssertEqual(ElementClipboard.fonts(from: board), [acme])
        ElementClipboard.write(s.page.elements, to: board)
        XCTAssertEqual(ElementClipboard.fonts(from: board), [])
        PageClipboard.copy(s.page, width: 1080, height: 1080, fonts: [acme], to: board)
        XCTAssertEqual(try XCTUnwrap(PageClipboard.paste(from: board)).fonts, [acme])
        PageClipboard.copy(s.page, width: 1080, height: 1080, to: board)
        XCTAssertNil(try XCTUnwrap(PageClipboard.paste(from: board)).fonts)
    }

    func testAMissingFontDrawsAsSansAndIsNamedInTheTextControls() {
        let d = CustomFonts.with(design("custom:ab12cd34ef56"), [acme])
        let el = d.pages[0].elements[0]
        XCTAssertEqual(FontLibrary.of(el.fontFamily).id, "sans")
        XCTAssertEqual(FontLibrary.uiFont(family: el.fontFamily, size: 40, weight: 400, italic: false).fontName,
                       FontLibrary.uiFont(family: "sans", size: 40, weight: 400, italic: false).fontName)
        XCTAssertEqual(CustomFonts.name(in: d, of: el.fontFamily), "Acme Sans")
        XCTAssertEqual(CustomFonts.missing("Acme Sans"), "Font missing: Acme Sans")
        XCTAssertEqual(FontStore.missingNote(el.fontFamily, in: d), "Font missing: Acme Sans")
        XCTAssertEqual(FontStore.displayName(el.fontFamily, in: d), "Acme Sans")
        // Not recorded either: named by its hash.
        XCTAssertNil(CustomFonts.name(in: d, of: "custom:000000000000"))
        XCTAssertEqual(FontStore.missingNote("custom:000000000000", in: d), "Font missing: 000000000000")
        // A family of the library is never missing.
        XCTAssertNil(FontStore.missingNote("lora", in: d))
        XCTAssertEqual(FontStore.displayName("didone", in: d), "Playfair Display")
    }

    func testAFontOfYourOwnTravelsInsideThePackageAndComesBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = try bundled("pacifico-400.ttf")
        let sha = CustomFonts.sha12(bytes)
        defer { FontStore.remove(sha) }

        // Added, it draws in its own face and is listed as an upload.
        XCTAssertEqual(try FontStore.add(bytes).get(), "custom:\(sha)")
        XCTAssertNotNil(FontStore.url(for: sha))
        XCTAssertTrue(FontStore.installed().contains { $0.id == sha && $0.name == "Pacifico" && $0.file == "\(sha).ttf" })
        XCTAssertEqual(FontLibrary.uiFont(family: "custom:\(sha)", size: 40, weight: 400, italic: false).fontName,
                       "Pacifico-Regular")
        XCTAssertNil(FontStore.missingNote("custom:\(sha)", in: nil))

        let record = CustomFonts.Record(id: CustomFonts.key(sha), name: "Pacifico", file: "\(sha).ttf",
                                        family: "Pacifico", weight: 400, italic: false)
        let d = design("custom:\(sha)", "lora")
        let data = try DesignPackage.export(d, mediaDirectory: dir)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        // Sorted with the rest of the keys: {"<sha12>": {"data", "ext"}}.
        let at = { (key: String) in text.range(of: key)?.lowerBound }
        XCTAssertLessThan(try XCTUnwrap(at(#""design":{"#)), try XCTUnwrap(at(#""fonts":{"#)))
        XCTAssertLessThan(try XCTUnwrap(at(#""fonts":{"#)), try XCTUnwrap(at(#""format":"canvia-package""#)))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let packed = try XCTUnwrap((object["fonts"] as? [String: Any])?[sha] as? [String: Any])
        XCTAssertEqual(packed["ext"] as? String, "ttf")
        XCTAssertEqual((packed["data"] as? String).flatMap { Data(base64Encoded: $0) }, bytes)
        // The record written as a save writes it, so the other phone can name
        // it, and group it with its family before it has the file.
        let packedDesign = try XCTUnwrap(object["design"] as? [String: Any])
        let packedFonts = try XCTUnwrap(packedDesign["fonts"] as? [[String: Any]])
        XCTAssertEqual(packedFonts.count, 1)
        XCTAssertEqual(packedFonts.first?["id"] as? String, "custom:\(sha)")
        XCTAssertEqual(packedFonts.first?["name"] as? String, "Pacifico")
        XCTAssertEqual(packedFonts.first?["file"] as? String, "\(sha).ttf")
        XCTAssertEqual(packedFonts.first?["family"] as? String, "Pacifico")
        XCTAssertEqual(packedFonts.first?["weight"] as? Int, 400)
        XCTAssertEqual(packedFonts.first?["italic"] as? Bool, false)

        // Gone from this phone, an import stores it again, under its own key.
        FontStore.remove(sha)
        XCTAssertNotNil(FontStore.missingNote("custom:\(sha)", in: nil))
        let back = try DesignPackage.import(data, mediaDirectory: dir)
        XCTAssertEqual(back.pages[0].elements[0].fontFamily, "custom:\(sha)")
        XCTAssertEqual(CustomFonts.records(in: back), [record])
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(FontStore.url(for: sha))), bytes)
        XCTAssertEqual(FontLibrary.uiFont(family: "custom:\(sha)", size: 40, weight: 400, italic: false).fontName,
                       "Pacifico-Regular")

        // Bytes that are not the file the key names are not stored.
        FontStore.remove(sha)
        var forged = object
        forged["fonts"] = [sha: ["ext": "ttf", "data": try bundled("lora-400.ttf").base64EncodedString()]]
        _ = try DesignPackage.import(try JSONSerialization.data(withJSONObject: forged), mediaDirectory: dir)
        XCTAssertNil(FontStore.url(for: sha))

        // No fonts, no key; ten megabytes each at most.
        let plain = try JSONSerialization.jsonObject(with: DesignPackage.export(design("lora"), mediaDirectory: dir)) as? [String: Any]
        XCTAssertNil(plain?["fonts"])
        XCTAssertTrue(DesignPackage.packsFont(bytes: CustomFonts.maxBytes))
        XCTAssertFalse(DesignPackage.packsFont(bytes: CustomFonts.maxBytes + 1))
        XCTAssertFalse(DesignPackage.packsFont(bytes: 0))
    }

    /// A save brings the record up to date from this phone's fonts.
    func testASaveRecordsAFontOfYourOwnFromThisPhone() throws {
        let bytes = try bundled("sacramento-400.ttf")
        let sha = CustomFonts.sha12(bytes)
        defer { FontStore.remove(sha) }
        XCTAssertEqual(try FontStore.add(bytes).get(), "custom:\(sha)")
        let record = CustomFonts.Record(id: "custom:\(sha)", name: "Sacramento", file: "\(sha).ttf",
                                        family: "Sacramento", weight: 400, italic: false)
        XCTAssertEqual(FontStore.record(sha), record)

        var d = design("custom:\(sha)")
        d.id = UID.make("doc")
        XCTAssertTrue(DesignLibrary.save(d))
        defer { DesignLibrary.delete(id: d.id) }
        XCTAssertEqual(DesignLibrary.load(id: d.id)?.fonts, [record])
    }

    /// A font of your own of one face is drawn at its own weight whatever
    /// the text asks — the rows of the Android twin's FontLibraryTest: bold
    /// neither thickens it nor swaps it for a bundled face of the same name
    /// (Lora's Bold and Italic are bundled), and italic slants it. Once its
    /// family's Bold and Italic are added too, a text keyed to the Regular
    /// draws from them. A bundled family is drawn at its nearest face, and a
    /// missing font of your own as Modern Sans, bold as the system's is.
    func testAFontOfYourOwnIsDrawnAtItsOwnWeight() throws {
        let bytes = try bundled("lora-400.ttf")
        let sha = CustomFonts.sha12(bytes)
        defer { FontStore.remove(sha) }
        let key = try FontStore.add(bytes).get()
        func font(_ key: String?, _ weight: Int, italic: Bool = false) -> UIFont {
            FontLibrary.uiFont(family: key, size: 40, weight: weight, italic: italic)
        }
        func text(in key: String) -> Element {
            var el = Element.text("T")
            el.fontFamily = key
            return el
        }
        XCTAssertEqual(font("lora", 700).fontName, "Lora-Bold")
        XCTAssertEqual(font("lora", 900).fontName, "Lora-Bold")
        XCTAssertEqual(font("impact", 900).fontName, "Anton-Regular")
        XCTAssertEqual(font("condensed", 700, italic: true).fontName, "Oswald-Bold")

        XCTAssertEqual(font(key, 400).fontName, "Lora-Regular")
        XCTAssertEqual(font(key, 700).fontName, "Lora-Regular")
        XCTAssertFalse(font(key, 700).fontDescriptor.symbolicTraits.contains(.traitBold))
        let leaning = font(key, 700, italic: true)
        XCTAssertEqual(leaning.fontName, "Lora-Regular")
        XCTAssertEqual(CTFontGetMatrix(leaning as CTFont).c, CGFloat(FontLibrary.slant), accuracy: 0.001)
        XCTAssertEqual(FontLibrary.weights(key), [400], "one face, one weight")
        XCTAssertFalse(TypeReadouts.isWeighable(text(in: key)))

        // Its Bold and Italic added, the text keeps its key and draws from
        // the face of the family nearest what it asks.
        let heavy = try bundled("lora-700.ttf")
        let slanted = try bundled("lora-400i.ttf")
        defer {
            FontStore.remove(CustomFonts.sha12(heavy))
            FontStore.remove(CustomFonts.sha12(slanted))
        }
        let heavyKey = try FontStore.add(heavy).get()
        _ = try FontStore.add(slanted).get()
        XCTAssertEqual(font(key, 700).fontName, "Lora-Bold")
        XCTAssertEqual(font(key, 900).fontName, "Lora-Bold")
        XCTAssertEqual(font(key, 400).fontName, "Lora-Regular")
        XCTAssertEqual(font(heavyKey, 400).fontName, "Lora-Regular", "the family's nearest face, whichever key")
        let italic = font(key, 400, italic: true)
        XCTAssertEqual(italic.fontName, "Lora-Italic")
        XCTAssertEqual(CTFontGetMatrix(italic as CTFont).c, 0, accuracy: 0.001, "a true italic, not slanted")
        XCTAssertEqual(font(key, 700, italic: true).fontName, "Lora-Italic", "the only italic there is")
        XCTAssertEqual(FontLibrary.weights(key), [400, 700])
        XCTAssertEqual(FontLibrary.resolveWeight(key, 600), 700)
        XCTAssertTrue(TypeReadouts.isWeighable(text(in: key)))
        let families = CustomFonts.families(FontStore.installed()).filter { $0.name == "Lora" }
        XCTAssertEqual(families, [CustomFonts.Family(name: "Lora", key: key, weights: [400, 700])],
                       "one row, keyed by the Regular")
        let packed = try XCTUnwrap(DesignPackage.packedFonts(of: design(key)))
        XCTAssertEqual(Set(packed.keys), [sha, CustomFonts.sha12(heavy), CustomFonts.sha12(slanted)],
                       "the family's Bold and Italic travel with the Regular")
        XCTAssertEqual(FontStore.familyKey(heavyKey, in: nil), key)

        let missing = font("custom:0123456789ab", 700)
        XCTAssertEqual(missing.fontName, font("sans", 700).fontName)
        XCTAssertTrue(missing.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testAFontIsAnUploadOfKindFontWithItsNameAndFile() throws {
        let sha = "ab12cd34ef56"
        defer { Uploads.remove(sha) }
        Uploads.recordFont(sha, name: "Acme Sans", file: "\(sha).ttf", now: Date(timeIntervalSince1970: 1_800_000_000))
        Uploads.recordFont(sha, name: "Again", file: "\(sha).ttf", now: Date(timeIntervalSince1970: 1_800_000_001))
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: Uploads.fileURL)) as? [[String: Any]])
        let entries = raw.filter { $0["id"] as? String == sha }
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry["kind"] as? String, "font")
        XCTAssertEqual(entry["name"] as? String, "Acme Sans")
        XCTAssertEqual(entry["file"] as? String, "\(sha).ttf")
        XCTAssertEqual((entry["added"] as? NSNumber)?.int64Value, 1_800_000_000_000)

        let listed = try XCTUnwrap(Uploads.fonts().first { $0.id == sha })
        XCTAssertEqual(listed.name, "Acme Sans")
        XCTAssertEqual(listed.key, "custom:ab12cd34ef56")
        // Not among the photos, clips and music the Add sheet offers, and,
        // with no file here, not among the fonts installed.
        XCTAssertFalse(Uploads.all().contains { $0.id == sha })
        XCTAssertFalse(FontStore.installed().contains { $0.id == sha })
    }

    // MARK: families

    /// An sfnt of `tables`, each tag with its bytes, laid end to end.
    private func sfnt(_ tables: [(UInt32, Data)]) -> Data {
        func short(_ value: Int, _ data: inout Data) {
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
        func long(_ value: UInt32, _ data: inout Data) {
            for shift: UInt32 in [24, 16, 8, 0] { data.append(UInt8((value >> shift) & 0xFF)) }
        }
        var out = Data()
        long(0x0001_0000, &out)
        short(tables.count, &out); short(16, &out); short(0, &out); short(0, &out)
        var offset = 12 + 16 * tables.count
        for (tag, bytes) in tables {
            long(tag, &out); long(0, &out); long(UInt32(offset), &out); long(UInt32(bytes.count), &out)
            offset += bytes.count
        }
        for (_, bytes) in tables { out.append(bytes) }
        return out
    }

    /// A name table of Windows English names, as font(tag:names:) writes one.
    private func nameTable(_ names: [(Int, String)]) -> Data {
        font(tag: 0x0001_0000, names: names).dropFirst(28)
    }

    /// An OS/2 table's first 64 bytes: the weight class and fsSelection set.
    private func os2(weight: Int, selection: Int) -> Data {
        var table = Data(count: 64)
        table[4] = UInt8(weight >> 8); table[5] = UInt8(weight & 0xFF)
        table[62] = UInt8(selection >> 8); table[63] = UInt8(selection & 0xFF)
        return table
    }

    /// An fvar table with one wght axis from `min` to `max`, default `value`.
    private func fvar(min: Int, value: Int, max: Int) -> Data {
        var table = Data()
        for v in [1, 0, 16, 2, 1, 20, 0, 0] {
            table.append(UInt8(v >> 8)); table.append(UInt8(v & 0xFF))
        }
        for word in [0x7767_6874, min << 16, value << 16, max << 16] {
            for shift in [24, 16, 8, 0] { table.append(UInt8((word >> shift) & 0xFF)) }
        }
        table.append(contentsOf: [0, 0, 1, 0])
        return table
    }

    /// The rows both phones check: Lora's Regular, Bold and Italic — the
    /// bundled files — say their family, weight and italic. The weight is
    /// the OS/2 weight class, else 400, and the italic its fsSelection bit,
    /// else upright — a file with no OS/2 table is 400 and upright whatever
    /// its subfamily says, and a variable font's weight is its weight class,
    /// not its axis's default — as the Android twin's CustomFonts.style
    /// reads them. A variable font offers each hundred inside its axis.
    func testAFontFileSaysItsFamilyWeightAndItalic() throws {
        let rows: [(file: String, subfamily: String, weight: Int, italic: Bool)] = [
            ("lora-400.ttf", "Regular", 400, false),
            ("lora-700.ttf", "Bold", 700, false),
            ("lora-400i.ttf", "Italic", 400, true),
            ("lora-700i.ttf", "Bold Italic", 700, true),
        ]
        for row in rows {
            let face = try XCTUnwrap(CustomFonts.describe(try bundled(row.file)), row.file)
            XCTAssertEqual(face, CustomFonts.Face(family: "Lora", subfamily: row.subfamily, weight: row.weight,
                                                  italic: row.italic, wght: nil), row.file)
        }

        let named = sfnt([(0x6E61_6D65, nameTable([(1, "Acme Sans SemiBold"), (2, "Italic"),
                                                     (16, "Acme Sans"), (17, "SemiBold Italic")]))])
        XCTAssertEqual(CustomFonts.describe(named),
                       CustomFonts.Face(family: "Acme Sans", subfamily: "SemiBold Italic", weight: 400, italic: false, wght: nil))
        let unclassed = sfnt([(0x6E61_6D65, nameTable([(1, "Acme Sans"), (2, "Bold Italic")]))])
        XCTAssertEqual(CustomFonts.describe(unclassed),
                       CustomFonts.Face(family: "Acme Sans", subfamily: "Bold Italic", weight: 400, italic: false, wght: nil))

        // OS/2 wins over the names: a weight class of 300 and the italic bit
        // clear, whatever the subfamily says.
        let classed = sfnt([(0x4F53_2F32, os2(weight: 300, selection: 0x40)),
                            (0x6E61_6D65, nameTable([(1, "Acme Sans"), (2, "Bold Italic")]))])
        XCTAssertEqual(CustomFonts.describe(classed)?.weight, 300)
        XCTAssertEqual(CustomFonts.describe(classed)?.italic, false)

        let variable = sfnt([(0x4F53_2F32, os2(weight: 400, selection: 0x40)),
                             (0x6661_7672, fvar(min: 250, value: 450, max: 820)),
                             (0x6E61_6D65, nameTable([(1, "Acme Flex")]))])
        let flex = try XCTUnwrap(CustomFonts.describe(variable))
        XCTAssertEqual(flex.weight, 400, "the weight class, not the axis's default")
        XCTAssertEqual(flex.wght, CustomFonts.Axis(min: 250, max: 820, defaultValue: 450))
        XCTAssertEqual(CustomFonts.variableWeights(250...820), [300, 400, 500, 600, 700, 800])
        XCTAssertEqual(CustomFonts.variableWeights(100...900), [100, 200, 300, 400, 500, 600, 700, 800, 900])
        XCTAssertNil(CustomFonts.describe(sfnt([(0x6E61_6D65, nameTable([(2, "Bold")]))])), "no family, no face")
    }

    private func face(_ id: String, _ family: String, _ weight: Int, italic: Bool = false,
                      wght: ClosedRange<Double>? = nil) -> Uploads.FontEntry {
        Uploads.FontEntry(id: id, name: family, file: "\(id).ttf", added: 0, family: family, weight: weight,
                          italic: italic, wght: wght)
    }

    /// The rule both phones keep: the family's face of the slant asked
    /// (any, when it has none of it) nearest the weight asked, ties to the
    /// heavier, then the text's own face, then the lowest hash.
    func testATextIsDrawnFromTheFaceOfItsFamilyNearestItsWeightAndItalic() throws {
        let faces = [face("aaaaaaaaaa01", "Acme Sans", 700), face("aaaaaaaaaa00", "Acme Sans", 400),
                     face("aaaaaaaaaa02", "Acme Sans", 400, italic: true), face("bbbbbbbbbb00", "Other", 300)]
        let rows: [(key: String, weight: Int, italic: Bool, face: String, drawn: Int)] = [
            ("aaaaaaaaaa00", 400, false, "aaaaaaaaaa00", 400),
            ("aaaaaaaaaa00", 700, false, "aaaaaaaaaa01", 700),
            ("aaaaaaaaaa00", 550, false, "aaaaaaaaaa01", 700),
            ("aaaaaaaaaa01", 300, false, "aaaaaaaaaa00", 400),
            ("aaaaaaaaaa00", 400, true, "aaaaaaaaaa02", 400),
            ("aaaaaaaaaa00", 700, true, "aaaaaaaaaa02", 400),
            ("bbbbbbbbbb00", 700, true, "bbbbbbbbbb00", 300),
        ]
        for row in rows {
            let drawn = try XCTUnwrap(CustomFonts.drawnFace(for: row.key, weight: row.weight, italic: row.italic,
                                                            among: faces))
            XCTAssertEqual(drawn.face.id, row.face, "\(row)")
            XCTAssertEqual(drawn.weight, row.drawn, "\(row)")
        }
        XCTAssertNil(CustomFonts.drawnFace(for: "cccccccccc00", weight: 400, italic: false, among: faces))
        XCTAssertEqual(CustomFonts.weights(of: "aaaaaaaaaa02", among: faces), [400, 700], "upright weights")
        XCTAssertEqual(CustomFonts.weights(of: "cccccccccc00", among: faces), [])

        // The picker: a family a row, keyed by its Regular, in the order listed.
        XCTAssertEqual(CustomFonts.families(faces), [
            CustomFonts.Family(name: "Acme Sans", key: "custom:aaaaaaaaaa00", weights: [400, 700]),
            CustomFonts.Family(name: "Other", key: "custom:bbbbbbbbbb00", weights: [300]),
        ])
        XCTAssertEqual(CustomFonts.weightCount(2), "2 weights")
        XCTAssertEqual(CustomFonts.weightCount(1), "1 weight")

        // A variable face draws at the hundred nearest, inside its axis.
        let flex = [face("dddddddddd00", "Flex", 400, wght: 250...820)]
        XCTAssertEqual(CustomFonts.drawnFace(for: "dddddddddd00", weight: 650, italic: false, among: flex)?.weight, 700)
        XCTAssertEqual(CustomFonts.drawnFace(for: "dddddddddd00", weight: 900, italic: false, among: flex)?.weight, 800)
        XCTAssertEqual(CustomFonts.families(flex).first?.weights, [300, 400, 500, 600, 700, 800])
    }

    /// The rows of the Android twin's "a family's weights are its upright
    /// faces'": Acme Regular and Acme Light Italic offer the Regular's
    /// weight alone — an upright text at 300 would draw the Regular anyway,
    /// as the slant is taken first — and a design carries the family's
    /// other faces, lowest hash first.
    func testAFamilysWeightsAreItsUprightFacesOrEveryFacesWhenItHasNone() {
        let regular = face("eeeeeeeeee00", "Acme", 400)
        let lightItalic = face("eeeeeeeeee01", "Acme", 300, italic: true)
        let acme = [regular, lightItalic]
        XCTAssertEqual(CustomFonts.weights(of: "eeeeeeeeee00", among: acme), [400])
        XCTAssertEqual(CustomFonts.weights(of: "eeeeeeeeee01", among: acme), [400])
        XCTAssertEqual(CustomFonts.families(acme),
                       [CustomFonts.Family(name: "Acme", key: "custom:eeeeeeeeee00", weights: [400])])
        XCTAssertEqual(CustomFonts.drawnFace(for: "eeeeeeeeee00", weight: 300, italic: false, among: acme)?.face.id,
                       "eeeeeeeeee00")
        let italics = [lightItalic, face("eeeeeeeeee02", "Acme", 700, italic: true)]
        XCTAssertEqual(CustomFonts.weights(of: "eeeeeeeeee01", among: italics), [300, 700], "italics alone: theirs")
        XCTAssertEqual(CustomFonts.used(in: design("custom:eeeeeeeeee01"), faces: acme), ["eeeeeeeeee01", "eeeeeeeeee00"])
    }

    /// A text set in a family's Regular, with a bold word drawn from its
    /// Bold, records and carries both faces: a save keeps the Bold's record,
    /// and one the other phone wrote for it stays while this phone has the
    /// family.
    func testASaveRecordsEveryFaceOfAFamilyInUse() throws {
        let faces = [face("aaaaaaaaaa01", "Acme Sans", 700), face("aaaaaaaaaa00", "Acme Sans", 400),
                     face("bbbbbbbbbb00", "Other", 400)]
        var records: [String: CustomFonts.Record] = [:]
        for f in faces {
            records[f.id] = CustomFonts.Record(id: f.key, name: f.name, file: f.file, family: f.family,
                                               weight: f.weight, italic: f.italic)
        }
        let d = design("custom:aaaaaaaaaa00")
        XCTAssertEqual(CustomFonts.used(in: d, faces: faces), ["aaaaaaaaaa00", "aaaaaaaaaa01"])
        XCTAssertEqual(CustomFonts.used(in: d), ["aaaaaaaaaa00"], "a family not known here: the face alone")
        let saved = CustomFonts.synced(d, installed: { records[$0] }, faces: faces)
        XCTAssertEqual(CustomFonts.records(in: saved).map(\.id), ["custom:aaaaaaaaaa00", "custom:aaaaaaaaaa01"])
        let other = CustomFonts.with(d, [try XCTUnwrap(records["aaaaaaaaaa00"]), try XCTUnwrap(records["aaaaaaaaaa01"])])
        XCTAssertEqual(CustomFonts.synced(other, installed: { _ in nil }, faces: faces), other)
    }

    /// The design's record carries the face, so a phone without the files
    /// still groups them; an earlier build's record reads without it.
    func testTheRecordCarriesTheFamilyWeightAndItalic() throws {
        let bold = CustomFonts.Record(id: "custom:aaaaaaaaaa01", name: "Acme Sans", file: "aaaaaaaaaa01.otf",
                                      family: "Acme Sans", weight: 700, italic: false)
        let regular = CustomFonts.Record(id: "custom:aaaaaaaaaa00", name: "Acme Sans", file: "aaaaaaaaaa00.otf",
                                         family: "Acme Sans", weight: 400, italic: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(bold), as: UTF8.self),
                       #"{"family":"Acme Sans","file":"aaaaaaaaaa01.otf","id":"custom:aaaaaaaaaa01","italic":false,"name":"Acme Sans","weight":700}"#)
        let older = try JSONDecoder().decode(CustomFonts.Record.self,
                                             from: Data(#"{"id":"custom:ab12cd34ef56","name":"Acme Sans","file":"ab12cd34ef56.ttf"}"#.utf8))
        XCTAssertEqual(older, acme)
        XCTAssertNil(older.family)

        let d = CustomFonts.with(design("custom:aaaaaaaaaa01", "custom:aaaaaaaaaa00"), [bold, regular, acme])
        XCTAssertEqual(CustomFonts.familyKey("custom:aaaaaaaaaa01", in: d), "custom:aaaaaaaaaa00")
        XCTAssertEqual(CustomFonts.familyKey("custom:ab12cd34ef56", in: d), "custom:ab12cd34ef56", "no family recorded")
        XCTAssertEqual(FontChoices.families(["lora", "custom:aaaaaaaaaa01", "custom:aaaaaaaaaa00"], design: d),
                       ["lora", "custom:aaaaaaaaaa00"], "In this design, a family a row")
    }

    /// uploads.json's entry gains the face; one an earlier build wrote reads
    /// as its name's family, 400, upright, and not yet described.
    func testAFontUploadKeepsItsFace() throws {
        let sha = "ab12cd34ef57"
        let older = "ab12cd34ef58"
        defer {
            Uploads.remove(sha)
            Uploads.remove(older)
        }
        let face = CustomFonts.Face(family: "Acme Flex", subfamily: "Regular", weight: 450, italic: false,
                                    wght: CustomFonts.Axis(min: 250, max: 820, defaultValue: 450))
        Uploads.recordFont(sha, name: "Acme Flex", file: "\(sha).ttf")
        Uploads.describeFont(sha, face)
        Uploads.recordFont(older, name: "Acme Old", file: "\(older).ttf")
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: Uploads.fileURL)) as? [[String: Any]])
        let entry = try XCTUnwrap(raw.first { $0["id"] as? String == sha })
        XCTAssertEqual(entry["family"] as? String, "Acme Flex")
        XCTAssertEqual(entry["weight"] as? Int, 450)
        XCTAssertEqual(entry["italic"] as? Bool, false)
        XCTAssertEqual((entry["axes"] as? [String: Any])?["wght"] as? [Double], [250, 820])

        let listed = try XCTUnwrap(Uploads.fonts().first { $0.id == sha })
        XCTAssertEqual(listed.family, "Acme Flex")
        XCTAssertEqual(listed.weight, 450)
        XCTAssertEqual(listed.wght, 250...820)
        XCTAssertTrue(listed.described)
        let old = try XCTUnwrap(Uploads.fonts().first { $0.id == older })
        XCTAssertEqual(old.family, "Acme Old")
        XCTAssertEqual(old.weight, 400)
        XCTAssertFalse(old.italic)
        XCTAssertFalse(old.described)
        Uploads.describeFont(older, CustomFonts.Face(family: "Acme", subfamily: "Bold", weight: 700, italic: false, wght: nil))
        XCTAssertEqual(Uploads.fonts().first { $0.id == older }?.weight, 700)
        XCTAssertEqual(Uploads.fonts().first { $0.id == older }?.family, "Acme")
    }
}
