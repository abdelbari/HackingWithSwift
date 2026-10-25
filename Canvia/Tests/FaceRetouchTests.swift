// Face retouch: the faces kept on the photo as the element's `retouchFace`,
// the shared smoothing (Fixtures/face-retouch.json, byte for byte the
// Android twin's: a synthetic face to match within 2 a channel), the eye
// band and kept parts, the surface blur, a face found by its eyes, and the
// Retouch brush, a retouch layer of kind "smooth".

import XCTest
import CoreGraphics
@testable import Canvia

final class FaceRetouchTests: XCTestCase {

    /// The fixture's synthetic face, as its note describes it, 0xAARRGGBB.
    private func synthetic() -> [Int] {
        var px = [Int](repeating: 0, count: 200 * 200)
        for y in 0..<200 {
            for x in 0..<200 {
                var c = 0xff285aa0
                let dx = (Double(x) + 0.5 - 100) / 70, dy = (Double(y) + 0.5 - 100) / 90
                if dx * dx + dy * dy < 1 {
                    let n = (x * 37 + y * 91) % 23 - 11
                    c = (0xff << 24) | ((200 + n) << 16) | ((150 + n) << 8) | (120 + n)
                }
                for ex in [75.0, 125.0] {
                    let ox = Double(x) + 0.5 - ex, oy = Double(y) + 0.5 - 80
                    if ox * ox + oy * oy < 36 { c = 0xff1e1e1e }
                }
                if (80..<120).contains(x) && (140..<150).contains(y) { c = 0xffaa3c46 }
                px[y * 200 + x] = c
            }
        }
        return px
    }

    private func hex(_ s: String) -> [Int] {
        let v = Int(s.dropFirst(), radix: 16) ?? 0
        return [(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]
    }

    /// Shared: the synthetic face, retouched as each case says, matches at
    /// its samples within 2 a channel.
    func testTheSharedSyntheticFaceComesOutTheSameOnBothPhones() throws {
        let cases = try XCTUnwrap(try SharedFixture.object("face-retouch")["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for row in cases {
            let amount = try XCTUnwrap(row["amount"] as? Double)
            let faces = try XCTUnwrap(row["faces"] as? [[String: Double]]).map { b in
                FaceRetouch.Face(x: b["x"] ?? 0, y: b["y"] ?? 0, w: b["w"] ?? 0, h: b["h"] ?? 0)
            }
            var px = synthetic()
            FaceRetouch.applyPixels(&px, width: 200, height: 200, retouch: FaceRetouch(amount: amount, faces: faces))
            for sample in try XCTUnwrap(row["samples"] as? [[Any]]) {
                let x = try XCTUnwrap(sample[0] as? Int), y = try XCTUnwrap(sample[1] as? Int)
                let want = hex(try XCTUnwrap(sample[2] as? String))
                let got = px[y * 200 + x]
                for (i, shift) in [16, 8, 0].enumerated() {
                    XCTAssertLessThanOrEqual(abs(((got >> shift) & 0xff) - want[i]), 2, "amount \(amount) at \(x),\(y)")
                }
                XCTAssertEqual((got >> 24) & 0xff, 0xff)
            }
        }
    }

    func testSkinIsToldByItsChromaAndTheEyesAndLipsAreKept() {
        XCTAssertTrue(FaceRetouch.isSkin(0xc89678))
        XCTAssertFalse(FaceRetouch.isSkin(0x285aa0))
        XCTAssertFalse(FaceRetouch.isSkin(0xaa3c46))
        XCTAssertFalse(FaceRetouch.isSkin(0x808080), "grey has no chroma")
        let face = FaceRetouch.Face(x: 0, y: 0, w: 1, h: 1)
        // The eye band: a quarter to half way down, the middle eight tenths across.
        XCTAssertTrue(FaceRetouch.kept(face, u: 0.5, v: 0.3))
        XCTAssertFalse(FaceRetouch.kept(face, u: 0.5, v: 0.6))
        XCTAssertFalse(FaceRetouch.kept(face, u: 0.05, v: 0.3))
        // A face with its own kept parts keeps those, and no band.
        let lips = FaceRetouch.Face(x: 0, y: 0, w: 1, h: 1, keep: [[CGPoint(x: 0.4, y: 0.7), CGPoint(x: 0.6, y: 0.7),
                                                                     CGPoint(x: 0.6, y: 0.8), CGPoint(x: 0.4, y: 0.8)]])
        XCTAssertTrue(FaceRetouch.kept(lips, u: 0.5, v: 0.75))
        XCTAssertFalse(FaceRetouch.kept(lips, u: 0.5, v: 0.3))
        // Full weight in the middle, fading over the outer fifth, none outside.
        XCTAssertEqual(FaceRetouch.weight(face, x: 50, y: 80, w: 100, h: 100), 1, accuracy: 1e-9)
        XCTAssertEqual(FaceRetouch.weight(face, x: 0, y: 0, w: 100, h: 100), 0, accuracy: 1e-9)
        let edge = FaceRetouch.weight(face, x: 93, y: 49, w: 100, h: 100)
        XCTAssertTrue(edge > 0 && edge < 1)
    }

    func testTheSurfaceBlurKeepsAnEdgeAndSmoothsARipple() {
        // A ripple of ±6 goes towards its mean; a jump of 100 stays.
        let w = 20
        let px = (0..<(w * w)).map { i -> Int in
            let v = i % w < 10 ? 120 + (i % 2 == 0 ? 6 : -6) : 220
            return (0xff << 24) | (v << 16) | (v << 8) | v
        }
        let smooth = FaceRetouch.surfaceBlur(px, width: w, height: w, x: 4, y: 10, radius: 3)
        XCTAssertLessThan(abs(((smooth >> 16) & 0xff) - 120), 6)
        let kept = FaceRetouch.surfaceBlur(px, width: w, height: w, x: 12, y: 10, radius: 3)
        XCTAssertEqual((kept >> 16) & 0xff, 220)
        // Below a pixel's radius nothing moves.
        XCTAssertEqual(FaceRetouch.surfaceBlur(px, width: w, height: w, x: 10, y: 2, radius: 0.4), px[50])
    }

    func testAFaceFoundByItsEyesIsABox22EyeDistancesWideAnd26Tall() throws {
        let face = try XCTUnwrap(FaceRetouch.fromEyes(midX: 500, midY: 400, eyes: 100, pictureW: 1000, pictureH: 1000))
        XCTAssertEqual(face, FaceRetouch.Face(x: 0.39, y: 0.296, w: 0.22, h: 0.26))
        // Cut to the picture.
        let corner = try XCTUnwrap(FaceRetouch.fromEyes(midX: 50, midY: 50, eyes: 100, pictureW: 1000, pictureH: 1000))
        XCTAssertEqual(corner.x, 0)
        XCTAssertEqual(corner.y, 0)
        XCTAssertEqual(corner.w, 0.16, accuracy: 1e-9)
        XCTAssertNil(FaceRetouch.fromEyes(midX: 50, midY: 50, eyes: 0, pictureW: 1000, pictureH: 1000))
    }

    private func photo(_ face: String?) throws -> Element {
        let key = face.map { ",\"retouchFace\":\($0)" } ?? ""
        let json = "{\"id\":\"e\",\"type\":\"image\",\"x\":0,\"y\":0,\"w\":10,\"h\":10,\"src\":\"media:ph\"\(key)}"
        return try JSONDecoder().decode(Element.self, from: Data(json.utf8))
    }

    func testTheFacesAreTheElementsRetouchFaceKeptAsTheyCame() throws {
        let read = try photo(#"{"amount":0.7,"faces":[{"x":0.2,"y":0.1,"w":0.3,"h":0.4,"keep":[[{"x":0.3,"y":0.2},{"x":0.4,"y":0.2},{"x":0.35,"y":0.25}]]},{"x":"no"}]}"#)
        let retouch = try XCTUnwrap(read.retouchFace)
        XCTAssertEqual(retouch.amount, 0.7)
        XCTAssertEqual(retouch.faces.count, 1, "a face that does not read is left out")
        XCTAssertEqual(retouch.faces[0].keep.count, 1)
        // Written and read back the same.
        let again = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(read))
        XCTAssertEqual(again.retouchFace, retouch)
        // The amount moves; the faces, keep and all, stay as they came.
        let moved = FaceRetouch.withAmount(read, 0.3)
        XCTAssertEqual(moved.retouchFace?.amount, 0.3)
        XCTAssertEqual(moved.retouchFace?.faces, retouch.faces)
        // A build without the key draws the plain photo: no faces is none.
        XCTAssertNil(try photo(#"{"amount":0.5,"faces":[]}"#).retouchFace)
        XCTAssertNil(try photo(nil).retouchFace)
        // Written with the amount and the faces, keep only where there is some.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let plain = FaceRetouch(amount: 0.5, faces: [FaceRetouch.Face(x: 0.1, y: 0.2, w: 0.3, h: 0.4)])
        XCTAssertEqual(String(decoding: try encoder.encode(plain), as: UTF8.self),
                       #"{"amount":0.5,"faces":[{"h":0.4,"w":0.3,"x":0.1,"y":0.2}]}"#)
        // Drawn in the engine's pass; a look, so a background bakes it;
        // Reset photo edits and Replace drop it.
        var on = Element.image("media:1")
        on.retouchFace = plain
        XCTAssertNotNil(PhotoEffects.plan(on, picture: CGSize(width: 100, height: 100)).faces)
        XCTAssertTrue(ImageFilterEngine.makesLater(on))
        XCTAssertTrue(PhotoEdits.any(on))
        XCTAssertTrue(DesignStore.hasLook(on))
        var reset = on
        PhotoEdits.reset(&reset)
        XCTAssertNil(reset.retouchFace)
        XCTAssertNil(Crop.replaced(on, src: "media:2").retouchFace)
        // None of it on a code, which stays crisp.
        on.src = "qr:hello"
        XCTAssertFalse(ImageFilterEngine.makesLater(on))
        XCTAssertFalse(DesignStore.isStillPhoto(on))
    }

    func testTheSmoothingBrushIsARetouchLayerOfKindSmooth() throws {
        let layer = RetouchLayer(kind: RetouchLayer.smooth, amount: 1,
                                 strokes: [RetouchStroke(w: 0.5, points: [CGPoint(x: 0.5, y: 0.5)])])
        let read = try JSONDecoder().decode(RetouchLayer.self, from: JSONEncoder().encode(layer))
        XCTAssertEqual(read.kind, RetouchLayer.smooth)
        // A ripple under the brush is smoothed; the picture beyond it is not.
        let w = 100
        var bytes = [UInt8](repeating: 255, count: w * w * 4)
        for i in 0..<(w * w) {
            let v = UInt8(120 + ((i % w + i / w) % 2 == 0 ? 8 : -8))
            bytes[i * 4] = v
            bytes[i * 4 + 1] = v
            bytes[i * 4 + 2] = v
        }
        let before = bytes
        FaceRetouch.smoothed(&bytes, width: w, height: w, layer: layer)
        XCTAssertLessThan(abs(Int(bytes[(50 * w + 50) * 4]) - 120), 8)
        XCTAssertEqual(bytes[0], before[0])
        XCTAssertEqual(BrushSession(id: "p", kind: .smooth, imageSize: .zero).layerKind, RetouchLayer.smooth)
    }
}
