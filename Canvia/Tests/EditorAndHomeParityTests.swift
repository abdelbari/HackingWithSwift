// The editor's chrome and Home, as the Android twin has them: the size and
// page line under the name, a name that cannot be emptied, toasts that
// wait for VoiceOver, help that opens what it describes, and a link no app
// takes that says so.

import XCTest
@testable import Canvia

final class EditorAndHomeParityTests: XCTestCase {

    // MARK: top bar

    func testTheCaptionGivesThePageSizeAndPlace() {
        XCTAssertEqual(EditorCaption.text(width: 1080, height: 1920, page: 1, of: 5), "1080 × 1920 · Page 2 of 5")
        XCTAssertEqual(EditorCaption.text(width: 1080.6, height: 1080, page: 0, of: 1), "1080 × 1080 · Page 1 of 1")
    }

    func testARenameIsTrimmed() {
        XCTAssertEqual(EditorCaption.renamed("  Bake sale  ", was: "Poster"), "Bake sale")
    }

    func testAnEmptiedNameKeepsTheOldOne() {
        XCTAssertNil(EditorCaption.renamed("", was: "Poster"))
        XCTAssertNil(EditorCaption.renamed("   \n", was: "Poster"))
    }

    func testAnUnchangedNameRecordsNothing() {
        XCTAssertNil(EditorCaption.renamed("Poster ", was: "Poster"))
    }

    // MARK: toasts and tips

    func testAnUndoToastWaitsForVoiceOver() {
        XCTAssertEqual(ToastTiming.undoToast(voiceOver: false), 4)
        XCTAssertNil(ToastTiming.undoToast(voiceOver: true))
    }

    func testATipStaysLongerWithVoiceOver() {
        XCTAssertEqual(ToastTiming.tip(voiceOver: false), 9)
        XCTAssertGreaterThan(ToastTiming.tip(voiceOver: true), ToastTiming.tip(voiceOver: false))
    }

    // MARK: help

    func testPagesAndSnappingHaveShowMe() {
        let topics = Dictionary(uniqueKeysWithValues: HelpTopics.all.map { ($0.id, $0) })
        XCTAssertEqual(topics["pages"]?.opens, .pages)
        XCTAssertEqual(topics["snap"]?.opens, .snapping)
    }

    func testResizeHelpDescribesReflowScaleAndOnePage() throws {
        let resize = try XCTUnwrap(HelpTopics.all.first { $0.id == "resize" })
        XCTAssertTrue(resize.body.contains("Reflow"))
        XCTAssertTrue(resize.body.contains("Scale"))
        XCTAssertTrue(resize.body.contains("this page"))
        XCTAssertEqual(resize.opens, .resize)
    }

    // MARK: present

    @MainActor
    func testALinkNoAppOpensSaysSo() {
        XCTAssertEqual(PresentationView.refusedText("https://canvia.app/menu/"), "No app here opens canvia.app/menu")
    }

    // MARK: thumbnails

    func testAThumbnailIsAboutThreeHundredPointsWide() {
        XCTAssertEqual(DesignLibrary.thumbnailScale(pageWidth: 1080) * 1080, 300, accuracy: 0.001)
        XCTAssertEqual(DesignLibrary.thumbnailScale(pageWidth: 0), 300, accuracy: 0.001)
    }

    // MARK: import

    /// The background import leaves the text boxes to be measured on the
    /// main actor; the package itself comes in the same either way.
    func testAnImportCanLeaveTheMeasuringForLater() throws {
        var design = Design(title: "Package", width: 400, height: 300)
        var text = Element.text("Hello")
        text.h = 1
        design.pages = [Page(elements: [text])]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try DesignPackage.export(design, mediaDirectory: directory)
        let raw = try DesignPackage.import(data, mediaDirectory: directory, normalize: false)
        XCTAssertEqual(raw.pages[0].elements[0].h, 1)
        XCTAssertEqual(raw.title, "Package")
    }
}
