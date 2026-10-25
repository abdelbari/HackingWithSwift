// Add's Gallery (DeviceGallery), the rows the Android twin's
// DeviceGalleryTest holds: its columns, its chips, the chip each tab opens
// on, and its Add button. The ticks numbered in the order picked are the
// system picker's own here (selectionBehavior .ordered).

import UniformTypeIdentifiers
import XCTest
@testable import Canvia

final class DeviceGalleryTests: XCTestCase {

    func testThreeColumnsOnAPhoneFourOnATablet() {
        XCTAssertEqual(DeviceGallery.columns(smallestWidth: 411), 3)
        XCTAssertEqual(DeviceGallery.columns(smallestWidth: 599), 3)
        XCTAssertEqual(DeviceGallery.columns(smallestWidth: 600), 4)
        XCTAssertEqual(DeviceGallery.columns(smallestWidth: 800), 4)
    }

    func testFavouritesAreOfferedOnlyWhereThePhoneKeepsThemAndEachTabStartsOnItsOwn() {
        XCTAssertEqual(DeviceGallery.filters(favourites: true).map(\.label), ["All", "Photos", "Videos", "Favourites"])
        XCTAssertEqual(DeviceGallery.filters(favourites: false).map(\.label), ["All", "Photos", "Videos"])
        XCTAssertEqual(DeviceGallery.startFilter(videosTab: true), .videos)
        XCTAssertEqual(DeviceGallery.startFilter(videosTab: false), .all)
    }

    func testTheAddButtonSaysHowManyArePicked() {
        XCTAssertEqual(DeviceGallery.addLabel(2), "Add 2")
        XCTAssertEqual(DeviceGallery.addLabel(1), "Add 1")
        XCTAssertEqual(DeviceGallery.maxPicks, 10)
    }

    /// Dragged out of the Gallery onto the page, a clip is taken as a photo
    /// is (CanvasDrop): the page takes movies, before pictures.
    func testThePageTakesAClipDraggedOntoIt() {
        XCTAssertEqual(CanvasDrop.types.first, .movie)
        XCTAssertTrue(CanvasDrop.types.contains(.image))
    }
}
