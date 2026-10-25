// Suggested alt text: the draft made from what the app already knows — a
// library item's name and tags, an upload's file name cleaned of a camera's
// pattern, what kind of thing it is, its main colours — in the shared rows
// (Fixtures/alt-suggest.json, byte for byte the Android twin's).

import XCTest
@testable import Canvia

final class AltTextSuggestTests: XCTestCase {

    func testTheSharedRowsSuggestTheSameOnBothPhones() throws {
        let rows = try XCTUnwrap(try SharedFixture.object("alt-suggest")["rows"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let name = row["name"] as? String ?? ""
            let element = try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(try XCTUnwrap(row["element"])))
            let hints = AltText.Hints(fileName: row["fileName"] as? String, clipSeconds: row["clipSeconds"] as? Double,
                                      colours: row["colours"] as? [String] ?? [])
            XCTAssertEqual(AltText.suggest(element, hints: hints), row["want"] as? String, name)
        }
    }

    func testAFileNameIsCleanedOfACamerasPattern() {
        XCTAssertEqual(AltText.fromFileName("beach_sunset.jpg"), "Beach sunset")
        XCTAssertEqual(AltText.fromFileName("my-dog Rex.HEIC"), "My dog Rex")
        XCTAssertNil(AltText.fromFileName("IMG_1234.JPG"))
        XCTAssertNil(AltText.fromFileName("PXL_20250101_123456789.jpg"))
        XCTAssertNil(AltText.fromFileName("DSC01234.jpg"))
        XCTAssertEqual(AltText.fromFileName("IMG_1234 garden.jpg"), "Garden")
        XCTAssertEqual(AltText.hostOf("HTTPS://WWW.Example.com:8080/a"), "example.com")
        XCTAssertNil(AltText.hostOf("mailto:a@b.c"))
    }

    func testAColoursFamilyLeavesItsDepthOut() {
        XCTAssertEqual(ElementNames.colourFamily("#023e8a"), "blue")
        XCTAssertEqual(ElementNames.colourFamily("#cccccc"), "grey")
        XCTAssertEqual(ElementNames.englishColourName("#023e8a"), "dark blue")
    }

    /// Taken, a suggestion is kept with the picture it was drawn from, so a
    /// Replace takes it away (Crop.replaced); one typed stays.
    func testATakenSuggestionGoesWithItsPicture() {
        var photo = Element.image("media:a")
        photo.altText = "Beach sunset"
        photo.altTextSource = photo.src
        XCTAssertNil(Crop.replaced(photo, src: "media:b").altText)
        photo.altTextSource = nil
        XCTAssertEqual(Crop.replaced(photo, src: "media:b").altText, "Beach sunset")
    }

    /// A Replace drops the mockup scene the old picture was added from, so
    /// the new one is not named after it; the Android twin's
    /// AltTextSuggestTest has the same row.
    func testAReplacedMockupPictureNoLongerNamesItsScene() {
        var photo = Element.image("media:a")
        photo.mockupId = "phone-front"
        XCTAssertNil(Crop.replaced(photo, src: "media:b").mockupId)
    }
}
