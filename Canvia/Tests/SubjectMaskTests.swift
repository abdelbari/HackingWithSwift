// Background removal.
//
// Only one thing here is ours to test. Whether Vision finds a subject in a
// given picture is Apple's model talking, and a synthetic fixture is not a
// photograph, so that question is skipped rather than asserted. What is ours
// is the extent contract: a cutout replaces the picture inside an element
// that already has a position and a size on the page, so it has to come back
// the same size it went in. Passing croppedToInstancesExtent: true instead
// would return a tightly cropped subject, which the element would then
// stretch to its old frame — the picture would visibly jump and distort at
// the moment the background disappeared.

import XCTest
import UIKit
@testable import Canvia

final class SubjectMaskTests: XCTestCase {

    /// A dark blob on a light ground: the closest a drawn fixture gets to
    /// something a foreground segmenter might accept.
    private func fixture(width: Int = 300, height: Int = 200) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.black.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: width / 4, y: height / 4,
                                                 width: width / 2, height: height / 2))
        }
    }

    func testCutoutKeepsTheOriginalExtent() throws {
        let source = fixture()
        guard let cut = try? SubjectMask.cutout(source) else {
            throw XCTSkip("the segmenter found no subject in a drawn fixture")
        }
        XCTAssertEqual(cut.size, source.size)
        XCTAssertEqual(cut.imageOrientation, .up)
        XCTAssertNotNil(cut.cgImage)
    }

    /// Failure has to be a thrown error the toolbar can put in an alert, not a
    /// silent nil that leaves the button spinning.
    func testCutoutThrowsOnAnImageWithNoPixels() {
        XCTAssertThrowsError(try SubjectMask.cutout(UIImage()))
    }
}
