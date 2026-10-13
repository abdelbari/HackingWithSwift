// Fonts of your own, as the Android twin's CustomFontsTest has them: the
// key from the file's SHA-1, the checks a file passes before it is added,
// the design's "fonts" record through JSON and kept in step on save, the
// fallback and the words for a missing one, the weight one is drawn at, the
// package carrying the bytes and an import storing them, and the
// uploads.json entry.

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

        let record = CustomFonts.Record(id: CustomFonts.key(sha), name: "Pacifico", file: "\(sha).ttf")
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
        // The record written as a save writes it, so the other phone can name it.
        let packedDesign = try XCTUnwrap(object["design"] as? [String: Any])
        XCTAssertEqual(packedDesign["fonts"] as? [[String: String]],
                       [["id": "custom:\(sha)", "name": "Pacifico", "file": "\(sha).ttf"]])

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
        XCTAssertEqual(FontStore.record(sha), CustomFonts.Record(id: "custom:\(sha)", name: "Sacramento", file: "\(sha).ttf"))

        var d = design("custom:\(sha)")
        d.id = UID.make("doc")
        XCTAssertTrue(DesignLibrary.save(d))
        defer { DesignLibrary.delete(id: d.id) }
        XCTAssertEqual(DesignLibrary.load(id: d.id)?.fonts,
                       [CustomFonts.Record(id: "custom:\(sha)", name: "Sacramento", file: "\(sha).ttf")])
    }

    /// A font of your own is one face, drawn at its own weight whatever the
    /// text asks — the rows of the Android twin's FontLibraryTest: bold
    /// neither thickens it nor swaps it for another face of its family
    /// registered here (Lora's Bold and Italic are bundled), and italic
    /// slants it. A bundled family is drawn at its nearest face, and a
    /// missing font of your own as Modern Sans, bold as the system's is.
    func testAFontOfYourOwnIsDrawnAtItsOwnWeight() throws {
        let bytes = try bundled("lora-400.ttf")
        let sha = CustomFonts.sha12(bytes)
        defer { FontStore.remove(sha) }
        let key = try FontStore.add(bytes).get()
        func font(_ key: String?, _ weight: Int, italic: Bool = false) -> UIFont {
            FontLibrary.uiFont(family: key, size: 40, weight: weight, italic: italic)
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
        // A bold file of your own stays bold at 400.
        let heavy = try bundled("lora-700.ttf")
        defer { FontStore.remove(CustomFonts.sha12(heavy)) }
        XCTAssertEqual(font(try FontStore.add(heavy).get(), 400).fontName, "Lora-Bold")

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
}
