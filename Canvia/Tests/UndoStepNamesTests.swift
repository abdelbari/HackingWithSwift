// What Undo and Redo say they will take back or make again: History.label
// over the shared vectors in Fixtures/history-labels.json, run by the
// Android twin's suite too, and the toolbar's names for the buttons.

import XCTest
@testable import Canvia

final class UndoStepNamesTests: XCTestCase {

    private struct StepVector: Decodable {
        var name: String
        var label: String
        var before: Design
        var after: Design
    }

    private struct StepVectors: Decodable {
        var vectors: [StepVector]
    }

    /// A fixture's JSON: from the test bundle, or beside this file.
    private func fixture(_ name: String, file: StaticString = #filePath) throws -> Data {
        if let url = Bundle(for: UndoStepNamesTests.self).url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).json"))
    }

    func testTheSharedVectors() throws {
        let vectors = try JSONDecoder().decode(StepVectors.self, from: fixture("history-labels")).vectors
        XCTAssertEqual(vectors.count, 17)
        for c in vectors {
            XCTAssertEqual(History.label(before: c.before, after: c.after), c.label, c.name)
        }
    }

    func testTheButtonsNameTheStep() {
        XCTAssertEqual(History.undoTitle("Move"), "Undo Move")
        XCTAssertEqual(History.redoTitle("Delete page"), "Redo Delete page")
        XCTAssertEqual(History.undoTitle(nil), "Undo")
        XCTAssertEqual(History.redoTitle(nil), "Redo")
    }

    @MainActor
    func testTheStoreNamesWhatUndoAndRedoWouldDo() {
        var d = Design(title: "steps", width: 1080, height: 1080)
        var box = Element.shape("rect")
        box.id = "a"
        d.pages = [Page(elements: [box])]
        let s = DesignStore(design: d)
        s.select("a")
        s.nudgeSelected(dx: 10, dy: 0)
        XCTAssertEqual(s.undoLabel, "Move")
        s.undo()
        XCTAssertEqual(s.redoLabel, "Move")
        XCTAssertNil(s.undoLabel)
    }
}
