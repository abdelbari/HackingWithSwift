// The later photo fx kinds — screen, posterize (with ColorMix's colours),
// mosaic and kaleido — a pixel at a time (PhotoLook.fx), over the shared
// rows of Fixtures/photo-fx-more.json: each drawn on the same 32 × 32
// picture to the same hash as on the Android twin, pixel for pixel.

import XCTest
@testable import Canvia

final class PhotoFxMoreTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("photo-fx-more") }

    /// The shared picture: red 40 a column, green 60 a row, blue 20 a step
    /// of either, opaque.
    private func ramp(_ w: Int, _ h: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        for y in 0..<h {
            for x in 0..<w {
                bytes += [UInt8((x * 40) & 0xff), UInt8((y * 60) & 0xff), UInt8(((x + y) * 20) & 0xff), 255]
            }
        }
        return bytes
    }

    /// FNV-1a, 32 bits, as lower-case hex.
    private func hash(_ bytes: [UInt8]) -> String {
        var h: UInt32 = 0x811c9dc5
        for b in bytes {
            h ^= UInt32(b)
            h = h &* 0x01000193
        }
        return String(format: "%08x", h)
    }

    private func words(_ bytes: [UInt8]) -> [String] {
        stride(from: 0, to: bytes.count, by: 4).map { i in
            String(format: "%02x%02x%02x%02x", bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
        }
    }

    private func drawn(_ w: Int, _ h: Int, _ fx: PhotoFx) -> [UInt8] {
        var bytes = ramp(w, h)
        PhotoLook.fx(&bytes, width: w, height: h, fx: fx)
        return bytes
    }

    func testEveryRowDrawsToTheSharedHash() throws {
        let f = try fixture()
        let w = try XCTUnwrap(f["width"] as? Int), h = try XCTUnwrap(f["height"] as? Int)
        XCTAssertEqual(hash(ramp(w, h)), f["picture"] as? String, "the same picture to start from")
        let rows = try XCTUnwrap(f["rows"] as? [[Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 12)
        for row in rows {
            let kind = try XCTUnwrap(row[0] as? String)
            let amount = try XCTUnwrap(row[1] as? Double)
            let seed = try XCTUnwrap(row[2] as? Int)
            let colours = row[3] as? [String]
            let fx = PhotoFx(kind: kind, amount: amount, seed: seed, colours: colours)
            XCTAssertEqual(hash(drawn(w, h, fx)), row[4] as? String, "\(kind) \(amount) \(seed)")
        }
    }

    func testTheSmallPicturesPixelForPixel() throws {
        let small = try XCTUnwrap(try fixture()["small"] as? [String: Any])
        XCTAssertEqual(words(drawn(6, 4, PhotoFx(kind: "mosaic", amount: 1, seed: 5))), small["mosaic"] as? [String])
        XCTAssertEqual(words(drawn(4, 4, PhotoFx(kind: "kaleido", amount: 0.01))), small["kaleido"] as? [String])
        XCTAssertEqual(words(drawn(4, 4, PhotoFx(kind: "kaleido", amount: 0.125))), small["kaleido5"] as? [String],
                       "five wedges, each folded about its middle")
    }

    func testTheKindsAreOfferedInOrderAndReadForgivingly() throws {
        XCTAssertEqual(PhotoFx.kinds, ["glitch", "slice", "halftone", "grain", "screen", "posterize", "mosaic", "kaleido"])
        XCTAssertEqual(PhotoFx.seeded, ["glitch", "slice", "grain", "mosaic"])
        func read(_ json: String) -> PhotoFx? { try? JSONDecoder().decode(PhotoFx.self, from: Data(json.utf8)) }
        XCTAssertEqual(read(##"{"kind": "posterize", "amount": 0.4, "colours": ["#ff0000", "nope", "00f"]}"##),
                       PhotoFx(kind: "posterize", amount: 0.4, colours: ["#ff0000", "00f"]))
        XCTAssertNil(read(##"{"kind": "mosaic", "colours": ["#ff0000"]}"##)?.colours, "only posterize keeps colours")
        XCTAssertNil(read(#"{"kind": "posterize", "colours": []}"#)?.colours)
        XCTAssertNil(read(#"{"kind": "liquify"}"#), "an unknown kind is still no fx")
        let twenty = (0..<20).map { String(format: "\"#%06lx\"", $0 * 0x0b0b0b) }.joined(separator: ", ")
        XCTAssertEqual(read(#"{"kind": "posterize", "colours": [\#(twenty)]}"#)?.colours?.count, PhotoFx.maxColours,
                       "a palette keeps 16 colours at most, as on the Android twin")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let written = String(decoding: try encoder.encode(PhotoFx(kind: "kaleido", amount: 1, seed: 0)), as: UTF8.self)
        XCTAssertEqual(written, #"{"amount":1,"kind":"kaleido","seed":0}"#)
        XCTAssertEqual(PhotoFx.rgb("#a8dadc"), [168, 218, 220])
        XCTAssertEqual(PhotoFx.rgb("fff"), [255, 255, 255])
        XCTAssertNil(PhotoFx.rgb("#12345"))
    }

    func testTheNumbersEachKindIsDrawnBy() {
        // Posterize's levels: round(8 − 6 × amount), at least 2.
        let flat: [UInt8] = [100, 150, 200, 255]
        var two = flat
        PhotoLook.posterize(&two, width: 1, height: 1, amount: 1, colours: nil)
        XCTAssertEqual(two, [0, 255, 255, 255])
        var mixed = flat
        PhotoLook.posterize(&mixed, width: 1, height: 1, amount: 1, colours: PhotoFx.colourMix)
        XCTAssertEqual(mixed, [168, 218, 220, 255], "the nearest of the ColorMix colours")
        // A clear pixel stays as it is.
        var clear: [UInt8] = [0, 0, 0, 0]
        PhotoLook.posterize(&clear, width: 1, height: 1, amount: 0.5, colours: nil)
        XCTAssertEqual(clear, [0, 0, 0, 0])
        // An fx of nothing changes nothing, whatever its kind.
        for kind in ["screen", "posterize", "mosaic", "kaleido"] {
            XCTAssertEqual(drawn(5, 3, PhotoFx(kind: kind, amount: 0.0)), ramp(5, 3), kind)
        }
    }

    func testTheSheetNamesEachKind() {
        XCTAssertEqual(PhotoFx.name("kaleido"), "Kaleidoscope")
        XCTAssertEqual(PhotoFx.name("posterize"), "Posterize")
        XCTAssertEqual(PhotoFx.name("screen"), "Screen")
        XCTAssertEqual(PhotoFx.name("glitch"), "Glitch")
    }
}
