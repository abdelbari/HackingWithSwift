// Text inside shapes: the text-safe boxes, the first words' ink and size,
// the shape growing for its words, the file keys, typing as one step, and
// the words reaching find and replace, read aloud, names and the SVG — the
// numbers the same as the Android twin's.

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class ShapeTextTests: XCTestCase {

    // MARK: insets

    func testTheInsetsTableIsTheAndroidTwins() {
        // Every shape, number for number with the Android twin's table.
        let android: [String: ShapeTextInset] = [
            "rect": ShapeTextInset(x: 8, y: 8, w: 84, h: 84),
            "circle": ShapeTextInset(x: 14.6, y: 14.6, w: 70.8, h: 70.8),
            "triangle": ShapeTextInset(x: 27.5, y: 45, w: 45, h: 55),
            "triangle-down": ShapeTextInset(x: 27.5, y: 0, w: 45, h: 55),
            "diamond": ShapeTextInset(x: 25, y: 25, w: 50, h: 50),
            "pentagon": ShapeTextInset(x: 20, y: 30, w: 60, h: 55),
            "hexagon": ShapeTextInset(x: 20, y: 15, w: 60, h: 70),
            "octagon": ShapeTextInset(x: 18, y: 18, w: 64, h: 64),
            "semicircle": ShapeTextInset(x: 20, y: 62, w: 60, h: 32),
            "quarter": ShapeTextInset(x: 5, y: 35, w: 60, h: 60),
            "parallelogram": ShapeTextInset(x: 25, y: 8, w: 50, h: 84),
            "trapezoid": ShapeTextInset(x: 20, y: 8, w: 60, h: 84),
            "star-5": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
            "star-4": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
            "star-6": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
            "star-8": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
            "seal": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
            "burst-16": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
            "arrow-right": ShapeTextInset(x: 8, y: 30, w: 72, h: 40),
            "arrow-left": ShapeTextInset(x: 20, y: 30, w: 72, h: 40),
            "arrow-up": ShapeTextInset(x: 30, y: 20, w: 40, h: 72),
            "arrow-down": ShapeTextInset(x: 30, y: 8, w: 40, h: 72),
            "arrow-double": ShapeTextInset(x: 20, y: 38, w: 60, h: 24),
            "chevron": ShapeTextInset(x: 30, y: 8, w: 40, h: 84),
            "speech": ShapeTextInset(x: 8, y: 8, w: 84, h: 54),
            "thought": ShapeTextInset(x: 14.6, y: 10.2, w: 70.8, h: 49.6),
            "ribbon": ShapeTextInset(x: 15, y: 24, w: 70, h: 52),
            "banner": ShapeTextInset(x: 8, y: 8, w: 84, h: 62),
            "tag": ShapeTextInset(x: 30, y: 20, w: 62, h: 60),
            "plaque": ShapeTextInset(x: 8, y: 22, w: 84, h: 56),
            "heart": ShapeTextInset(x: 20, y: 20, w: 60, h: 40),
            "cross": ShapeTextInset(x: 8, y: 35, w: 84, h: 30),
            "lightning": ShapeTextInset(x: 30, y: 40, w: 40, h: 18),
            "moon": ShapeTextInset(x: 10, y: 30, w: 35, h: 40),
            "drop": ShapeTextInset(x: 15, y: 50, w: 70, h: 35),
            "shield": ShapeTextInset(x: 15, y: 15, w: 70, h: 60),
            "blob-round": ShapeTextInset(x: 15, y: 15, w: 70, h: 70),
            "blob-elongated": ShapeTextInset(x: 15, y: 15, w: 70, h: 70),
            "blob-trilobe": ShapeTextInset(x: 15, y: 15, w: 70, h: 70),
            "blob-bean": ShapeTextInset(x: 15, y: 15, w: 70, h: 70),
            "sparkle-4pt": ShapeTextInset(x: 30, y: 30, w: 40, h: 40),
            "flower-6": ShapeTextInset(x: 25, y: 25, w: 50, h: 50),
            "squircle": ShapeTextInset(x: 12, y: 12, w: 76, h: 76),
            "scallop-12": ShapeTextInset(x: 18, y: 18, w: 64, h: 64),
        ]
        for (id, inset) in android {
            XCTAssertEqual(ShapeTextInsets.inset(for: id), inset, id)
        }
        XCTAssertEqual(ShapeTextInsets.table.count, android.count)
        XCTAssertEqual(ShapeTextInsets.inset(for: nil), ShapeTextInset(x: 8, y: 8, w: 84, h: 84),
                       "no id is the rectangle it is drawn as")
        XCTAssertEqual(ShapeTextInsets.inset(for: "no-such-shape"), ShapeTextInset(x: 15, y: 15, w: 70, h: 70),
                       "a shape this build does not know is 15% in")
        XCTAssertEqual(ShapeTextInsets.inset(for: ""), ShapeTextInsets.fallback)
    }

    func testEveryLibraryShapeHasABoxInsideItsOwn() {
        let library = Set(ContentLibrary.shapes.map(\.id))
        XCTAssertEqual(Set(ShapeTextInsets.table.keys), library, "one box for every shape, and none for a stranger")
        for (id, r) in ShapeTextInsets.table {
            XCTAssertTrue(r.x >= 0 && r.y >= 0 && r.w > 0 && r.h > 0, id)
            XCTAssertLessThanOrEqual(r.x + r.w, 100.0001, id)
            XCTAssertLessThanOrEqual(r.y + r.h, 100.0001, id)
        }
    }

    func testPathDataTakesTheFallbackAndABorderInsetsFurther() {
        var custom = Element.shape("rect", w: 200, h: 100)
        custom.pathData = "M0,0H100V100H0Z"
        XCTAssertEqual(ShapeTextInsets.inset(of: custom), ShapeTextInsets.fallback)
        var rect = Element.shape("rect", w: 200, h: 100)
        XCTAssertEqual(ShapeText.box(for: rect), CGRect(x: 16, y: 8, width: 168, height: 84))
        rect.strokeWidth = 4
        XCTAssertEqual(ShapeText.box(for: rect), CGRect(x: 20, y: 12, width: 160, height: 76),
                       "the stroke width, with or without a stroke colour")
        rect.stroke = "#000000"
        XCTAssertEqual(ShapeText.box(for: rect), CGRect(x: 20, y: 12, width: 160, height: 76))
    }

    func testAFlippedShapeShowsItsWordsInTheMirroredBox() {
        var triangle = Element.shape("triangle", w: 100, h: 100)
        XCTAssertEqual(ShapeText.shownBox(for: triangle).minY, 45, accuracy: 0.001)
        triangle.flipV = true
        XCTAssertEqual(ShapeText.shownBox(for: triangle).minY, 0, accuracy: 0.001, "the wide end is at the top")
    }

    // MARK: the first words

    func testTheDefaultInkContrastsWithTheFill() {
        XCTAssertEqual(ShapeText.defaultInk(for: .solid("#ffe066")), "#1f2430")
        XCTAssertEqual(ShapeText.defaultInk(for: .solid("#1f2430")), "#ffffff")
        XCTAssertEqual(ShapeText.defaultInk(for: nil), "#ffffff", "the default violet is dark")
        XCTAssertEqual(ShapeText.defaultInk(for: Paint(kind: "solid", color: nil, angle: nil, stops: nil)), "#ffffff",
                       "a solid fill with no colour is the default violet")
        let light = Paint(kind: "gradient", color: nil, angle: 90,
                          stops: [GradientStop(offset: 0, color: "#ffffff"), GradientStop(offset: 1, color: "#000000")])
        XCTAssertEqual(ShapeText.defaultInk(for: light), "#1f2430", "a gradient by its first stop")
        let dark = Paint(kind: "gradient", color: nil, angle: 90,
                         stops: [GradientStop(offset: 0, color: "#000000"), GradientStop(offset: 1, color: "#ffffff")])
        XCTAssertEqual(ShapeText.defaultInk(for: dark), "#ffffff")
        XCTAssertEqual(ShapeText.defaultInk(for: .image("asset:beach")), "#1f2430", "a photo fill reads as white")
        XCTAssertEqual(ShapeText.defaultInk(for: .pattern("dots", color: "#000000", secondary: "#000000")), "#1f2430")
    }

    func testTheFirstWordsTakeTheirSizeFromTheShortSide() {
        XCTAssertEqual(ShapeText.defaultFontSize(width: 200, height: 200), 36)
        XCTAssertEqual(ShapeText.defaultFontSize(width: 300, height: 100), 18)
        XCTAssertEqual(ShapeText.defaultFontSize(width: 40, height: 40), 12, "never under 12")
        XCTAssertEqual(ShapeText.defaultFontSize(width: 1000, height: 600), 72, "never over 72")
        XCTAssertEqual(ShapeText.defaultFontSize(width: 250, height: 250), 45, "45 exactly, whole")
        XCTAssertEqual(ShapeText.defaultFontSize(width: 130, height: 130), 23, "23.4 to 23")
    }

    func testStartingKeepsALookChosenBeforeTheWords() {
        var shape = Element.shape("circle", w: 200, h: 200)
        shape.fontFamily = "serif"
        let started = ShapeText.starting(shape)
        XCTAssertEqual(started.fontFamily, "serif")
        XCTAssertEqual(started.fontSize, 36)
        XCTAssertEqual(started.align, "center")
        XCTAssertEqual(started.vAlign, "middle")
        XCTAssertEqual(started.color, "#ffffff")
    }

    // MARK: growing

    func testAShapeGrowsDownJustEnoughForItsWords() {
        // 200 tall keeps 168 for words.
        XCTAssertEqual(ShapeText.grownHeight(height: 200, insetHeight: 84, border: 0, wordsHeight: 100), 200, accuracy: 1e-9,
                       "words that fit leave it be")
        XCTAssertEqual(ShapeText.grownHeight(height: 200, insetHeight: 84, border: 0, wordsHeight: 168), 200, accuracy: 1e-9)
        XCTAssertEqual(ShapeText.grownHeight(height: 200, insetHeight: 84, border: 0, wordsHeight: 210), 250, accuracy: 1e-9)
        // A border of 4 keeps 8 more.
        XCTAssertEqual(ShapeText.grownHeight(height: 200, insetHeight: 84, border: 4, wordsHeight: 160), 200, accuracy: 1e-9)
        XCTAssertEqual(ShapeText.grownHeight(height: 200, insetHeight: 84, border: 4, wordsHeight: 202), 250, accuracy: 1e-9)
        // A circle's words have 70.8 of each hundred.
        XCTAssertEqual(ShapeText.grownHeight(height: 200, insetHeight: ShapeTextInsets.inset(for: "circle").h,
                                             border: 0, wordsHeight: 212.4), 300, accuracy: 1e-9)
        XCTAssertEqual(ShapeText.grownHeight(height: 400, insetHeight: 84, border: 0, wordsHeight: 10), 400, accuracy: 1e-9,
                       "never shrinks")
    }

    // MARK: the file

    func testAShapeWithWordsRoundTripsItsKeys() throws {
        var shape = Element.shape("speech", w: 300, h: 200)
        shape.text = "Hello **there**"
        shape.fontFamily = "serif"
        shape.fontSize = 32
        shape.fontWeight = 700
        shape.italic = true
        shape.underline = true
        shape.uppercase = true
        shape.align = "left"
        shape.lineHeight = 1.4
        shape.letterSpacing = 2
        shape.color = "#ffffff"
        shape.vAlign = "top"
        let data = try JSONEncoder().encode(shape)
        let back = try JSONDecoder().decode(Element.self, from: data)
        XCTAssertEqual(back, shape)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "shape")
        XCTAssertEqual(json["text"] as? String, "Hello **there**")
        XCTAssertEqual(json["vAlign"] as? String, "top")
        XCTAssertEqual(json["color"] as? String, "#ffffff")
        XCTAssertEqual(json["uppercase"] as? Bool, true)
    }

    func testAnOldShapeHasNoWords() throws {
        let old = try JSONDecoder().decode(Element.self, from: Data(##"{"type":"shape","shapeId":"rect","w":100,"h":100}"##.utf8))
        XCTAssertNil(old.text)
        XCTAssertNil(ShapeText.words(of: old))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(old), as: UTF8.self).contains("\"text\""))
    }

    func testWordsOfOnlySpacesReturnsOrMarksAreNone() {
        // The same rows as the Android twin's ShapeTextTest: nothing to draw,
        // so nothing to grow for and no type controls.
        for blank in ["", " ", "   ", "\n\n\n\n", " \n\t ", "****"] {
            var shape = Element.shape("rect")
            shape.text = blank
            XCTAssertNil(ShapeText.words(of: shape), "\"\(blank)\"")
            XCTAssertEqual(ShapeText.grownHeight(for: shape), shape.h, "\"\(blank)\"")
        }
        var worded = Element.shape("rect")
        worded.text = "\nSALE\n"
        XCTAssertNotNil(ShapeText.words(of: worded))
        worded.text = "**SALE**"
        XCTAssertNotNil(ShapeText.words(of: worded))
    }

    func testAVAlignTheAppsDoNotKnowIsMiddled() {
        // As the Android twin's ShapeText.box: top and bottom are kept, and
        // anything else, none included, is the middle.
        var shape = Element.shape("rect")
        shape.text = "SALE"
        for (asked, drawn) in [("top", "top"), ("bottom", "bottom"), ("middle", "middle"), ("center", "middle"), ("", "middle")] {
            shape.vAlign = asked
            XCTAssertEqual(ShapeText.textElement(for: shape).vAlign, drawn, asked)
        }
        shape.vAlign = nil
        XCTAssertEqual(ShapeText.textElement(for: shape).vAlign, "middle")
    }

    // MARK: which shapes

    func testStrokesAndLinesTakeNoWords() {
        XCTAssertTrue(ShapeText.takesText(Element.shape("star-5")))
        var icon = Element.shape("rect")
        icon.pathData = "M0,0L100,50L0,100Z"
        XCTAssertTrue(ShapeText.takesText(icon), "path data drawn filled is a shape")
        var stroke = Element.shape("rect")
        stroke.pathData = "M0,0L100,100"
        stroke.fill = .clear
        stroke.stroke = "#000000"
        XCTAssertFalse(ShapeText.takesText(stroke), "a drawn stroke")
        var chartLine = icon
        chartLine.fill = .solid("#00000000")
        chartLine.stroke = "#ff0000"
        XCTAssertFalse(ShapeText.takesText(chartLine), "a line drawn as a path")
        var frame = Element.shape("star-5")
        frame.fill = .image("asset:beach")
        frame.text = "SALE"
        XCTAssertFalse(ShapeText.takesText(frame), "a photo poured into a shape")
        XCTAssertNil(ShapeText.words(of: frame))
        XCTAssertFalse(ShapeText.takesText(Element.image("asset:x")))
        XCTAssertFalse(ShapeText.takesText(Element.line()))
    }

    // MARK: typing

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "shape text", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    func testStartingTypingAndLeavingAreOneStep() {
        let shape = Element.shape("rect", w: 200, h: 200)
        let s = store([shape])
        s.startTyping(shape.id)
        XCTAssertEqual(s.editingTextId, shape.id)
        XCTAssertEqual(s.element(shape.id)?.color, "#ffffff", "the first words' ink is set as typing starts")
        s.typeWords("S", into: shape.id)
        s.typeWords("SALE", into: shape.id)
        s.endTextEdit()
        XCTAssertEqual(s.element(shape.id)?.text, "SALE")
        XCTAssertEqual(s.element(shape.id)?.fontSize, 36)
        XCTAssertFalse(s.hasPendingChanges)
        s.undo()
        XCTAssertEqual(s.element(shape.id), shape, "one Undo takes back the words and their look")
    }

    func testAShapeLeftWithoutWordsStaysAsItWas() {
        let shape = Element.shape("circle")
        let s = store([shape])
        s.startTyping(shape.id)
        s.typeWords("  ", into: shape.id)
        s.endTextEdit()
        XCTAssertEqual(s.element(shape.id), shape, "not removed, and nothing to undo")
        XCTAssertFalse(s.canUndo)
    }

    func testAShapeStyledThenLeftWithoutWordsKeepsOnlyTheStyle() {
        // Bold pressed with nothing typed closes the step the first words'
        // look began in; leaving still takes that look back, as on Android.
        let shape = Element.shape("rect", w: 200, h: 200)
        let s = store([shape])
        s.startTyping(shape.id)
        s.toggleText(.bold)
        s.endTextEdit()
        let left = s.element(shape.id)
        XCTAssertNil(left?.text)
        XCTAssertEqual(left?.fontWeight, 700, "the bold pressed stays")
        XCTAssertEqual(left?.fontFamily, shape.fontFamily)
        XCTAssertEqual(left?.fontSize, shape.fontSize)
        XCTAssertEqual(left?.align, shape.align)
        XCTAssertEqual(left?.vAlign, shape.vAlign)
        XCTAssertEqual(left?.color, shape.color)
    }

    func testTypingGrowsTheShapeAndRemovingWordsNeverShrinksIt() {
        let shape = Element.shape("rect", w: 200, h: 60)
        let s = store([shape])
        s.startTyping(shape.id)
        s.typeWords("One\nTwo\nThree\nFour", into: shape.id)
        let grown = s.element(shape.id)?.h ?? 0
        XCTAssertGreaterThan(grown, 60, "four lines do not fit 60 high")
        XCTAssertEqual(s.element(shape.id)?.y, shape.y, "grown down: its top stays")
        s.typeWords("One", into: shape.id)
        XCTAssertEqual(s.element(shape.id)?.h, grown)
        s.endTextEdit()
        s.undo()
        XCTAssertEqual(s.element(shape.id)?.h, 60, "the growth is in the typing's step")
    }

    // MARK: where the words are read

    func testFindReplaceReadAloudAndNamesIncludeShapeWords() {
        var shape = Element.shape("circle")
        shape.fill = .solid("#ff0000")
        shape.text = "Big SALE"
        XCTAssertEqual(ElementNames.name(of: shape), "Circle: Big SALE")
        var bubble = Element.shape("speech")
        bubble.text = "Hello\n**there**"
        XCTAssertEqual(ElementNames.name(of: bubble), "Speech bubble: Hello there")
        bubble.text = "  "
        XCTAssertEqual(ElementNames.name(of: bubble), "Purple speech bubble", "blank words name it as before")
        var design = Design(title: "names", width: 1000, height: 1000)
        design.pages[0].elements = [shape]
        XCTAssertEqual(ReadAloud.script(for: design.pages[0], in: design), "Big SALE.")
        let s = DesignStore(design: design)
        XCTAssertEqual(s.matches(for: "sale").count, 1)
        XCTAssertEqual(s.replaceAll("SALE", with: "deal"), 1)
        XCTAssertEqual(s.element(shape.id)?.text, "Big deal")
        XCTAssertEqual(s.element(shape.id)?.h, shape.h, "words that fit leave the shape's size alone")
    }

    // MARK: export

    func testTheSVGOutlinesAShapesWords() {
        var design = Design(title: "svg", width: 400, height: 400)
        var shape = Element.shape("rect", w: 300, h: 200)
        shape.text = "Hi"
        design.pages[0].elements = [shape]
        let svg = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertEqual(svg.components(separatedBy: "<path").count - 1, 2, "the shape, then its words")
        XCTAssertFalse(svg.contains("<text"), "outlines, never <text>")
        design.pages[0].elements[0].flipH = true
        let flipped = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertEqual(flipped.components(separatedBy: "scale(-1 1)").count - 1, 2,
                       "the words are turned back inside the shape's flip")
    }
}
