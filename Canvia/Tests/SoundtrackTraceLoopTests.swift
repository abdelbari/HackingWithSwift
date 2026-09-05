// Soundtrack plans and the audio store, right-to-left text, tracing a
// bitmap into a path, and looping animations.

import XCTest
import UIKit
@testable import Canvia

final class SoundtrackTraceLoopTests: XCTestCase {

    // MARK: soundtrack

    func testShortAudioLoopsAndLongAudioTrims() {
        let looped = Soundtrack.plan(audioDuration: 4, videoDuration: 10)
        XCTAssertEqual(looped.segments.map(\.at), [0, 4, 8])
        XCTAssertEqual(looped.segments.map(\.duration), [4, 4, 2])
        XCTAssertEqual(looped.fadeOut, 9...10)
        let trimmed = Soundtrack.plan(audioDuration: 30, videoDuration: 5)
        XCTAssertEqual(trimmed.segments, [Soundtrack.Segment(sourceStart: 0, at: 0, duration: 5)])
        XCTAssertEqual(trimmed.fadeOut, 4...5)
        // Too short a video to fade; nothing to plan without audio.
        XCTAssertNil(Soundtrack.plan(audioDuration: 3, videoDuration: 1.5).fadeOut)
        XCTAssertTrue(Soundtrack.plan(audioDuration: 0, videoDuration: 5).segments.isEmpty)
    }

    func testAudioStoreKeepsAFileByIdAndForgetsIt() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("song-\(UUID()).m4a")
        try Data([1, 2, 3, 4]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let id = try XCTUnwrap(AudioStore.store(tmp))
        XCTAssertTrue(id.hasSuffix(".m4a"))
        XCTAssertNotNil(AudioStore.url(for: id))
        XCTAssertTrue(AudioStore.all().contains(id))
        XCTAssertEqual(AudioStore.label(for: id), "Audio (M4A)")
        AudioStore.delete(id)
        XCTAssertNil(AudioStore.url(for: id))
        XCTAssertNil(AudioStore.url(for: nil))
        XCTAssertNil(AudioStore.url(for: ""))
    }

    func testSoundtrackTravelsThroughMotionSettings() throws {
        var m = MotionSettings()
        m.soundtrack = "audio-1.mp3"; m.soundVolume = 0.4
        let back = try JSONDecoder().decode(MotionSettings.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back.soundtrack, "audio-1.mp3")
        let settings = MovieExporter.Settings(back)
        XCTAssertEqual(settings.soundtrack, "audio-1.mp3")
        XCTAssertEqual(settings.soundVolume, 0.4)
        XCTAssertEqual(MovieExporter.Settings(MotionSettings()).soundVolume, 1)
        let old = try JSONDecoder().decode(MotionSettings.self, from: Data(#"{"secondsPerPage":2,"fps":30,"movement":true,"crossfade":false}"#.utf8))
        XCTAssertNil(old.soundtrack)
    }

    // MARK: right to left

    func testRightToLeftIsDecidedByTheFirstLetter() {
        XCTAssertTrue(FontLibrary.isRightToLeft("שלום עולם"))
        XCTAssertTrue(FontLibrary.isRightToLeft("مرحبا"))
        XCTAssertTrue(FontLibrary.isRightToLeft("2024 — مرحبا"))
        XCTAssertFalse(FontLibrary.isRightToLeft("Hello שלום"))
        XCTAssertFalse(FontLibrary.isRightToLeft("123"))
        XCTAssertFalse(FontLibrary.isRightToLeft(""))
    }

    @MainActor
    func testRightToLeftTextGetsARightToLeftParagraph() {
        let style = FontLibrary.attributes(for: Element.text("שלום"))[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(style?.baseWritingDirection, .rightToLeft)
        let latin = FontLibrary.attributes(for: Element.text("Hello"))[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(latin?.baseWritingDirection, .natural)
    }

    // MARK: tracing

    private func picture(_ size: Int, transparent: Bool, draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = !transparent
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            if !transparent { UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }
            draw(ctx.cgContext)
        }
    }

    func testADarkDiscTracesToOneLoopWhereTheDiscIs() throws {
        let img = picture(100, transparent: false) { cg in
            cg.setFillColor(UIColor(red: 0.1, green: 0.1, blue: 0.5, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: 20, y: 20, width: 60, height: 60))
        }
        let t = try XCTUnwrap(Tracer.trace(img))
        XCTAssertEqual(t.pathData.components(separatedBy: "M").count - 1, 1, "one loop")
        XCTAssertTrue(t.pathData.hasSuffix("Z"))
        XCTAssertEqual(t.bounds.minX, 0.2, accuracy: 0.04)
        XCTAssertEqual(t.bounds.maxX, 0.8, accuracy: 0.04)
        XCTAssertEqual(t.bounds.minY, 0.2, accuracy: 0.04)
        XCTAssertEqual(t.bounds.maxY, 0.8, accuracy: 0.04)
        // The colour is the disc's, not the white around it.
        let c = UIColor(hex: t.color).srgbComponents
        XCTAssertLessThan(c.r, 0.3); XCTAssertGreaterThan(c.b, 0.35)
        // The path fills most of its box, as a disc does (π/4 ≈ 0.785).
        let path = SVGPath.scaledPath(t.pathData, to: CGSize(width: 100, height: 100))
        XCTAssertEqual(path.boundingBoxOfPath.width, 100, accuracy: 3)
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 50)))
        XCTAssertFalse(path.contains(CGPoint(x: 3, y: 3)))
    }

    func testARingTracesWithAHole() throws {
        let img = picture(100, transparent: true) { cg in
            cg.setFillColor(UIColor.black.cgColor)
            cg.fillEllipse(in: CGRect(x: 10, y: 10, width: 80, height: 80))
            cg.setBlendMode(.clear)
            cg.fillEllipse(in: CGRect(x: 35, y: 35, width: 30, height: 30))
        }
        let t = try XCTUnwrap(Tracer.trace(img))
        XCTAssertEqual(t.pathData.components(separatedBy: "M").count - 1, 2, "outer loop and hole")
        let path = SVGPath.scaledPath(t.pathData, to: CGSize(width: 100, height: 100))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 12), using: .winding))
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 50), using: .winding), "the hole stays open under a nonzero fill")
    }

    func testBlankPicturesTraceToNothing() {
        XCTAssertNil(Tracer.trace(picture(40, transparent: false) { _ in }))
    }

    func testSimplifyDropsCollinearCellCorners() {
        let square: [CGPoint] = (0...10).map { CGPoint(x: Double($0), y: 0) } + (1...10).map { CGPoint(x: 10, y: Double($0)) }
            + (0..<10).reversed().map { CGPoint(x: Double($0), y: 10) } + (1..<10).reversed().map { CGPoint(x: 0, y: Double($0)) }
        let s = Tracer.simplify(square, tolerance: 0.5)
        XCTAssertEqual(s.count, 4, "\(s)")
    }

    // MARK: loops

    func testLoopsKeepMovingAndEntrancesSettle() {
        let pulse = ElementAnimation(kind: "pulse", delay: 0, duration: 0.6)
        XCTAssertNotEqual(pulse.state(at: 0.3).scale, 1)
        XCTAssertNotEqual(pulse.state(at: 100.3).scale, 1, "a loop never settles")
        XCTAssertEqual(pulse.end, .infinity)
        let spin = ElementAnimation(kind: "spin", delay: 0, duration: 0.6)
        XCTAssertEqual(spin.state(at: ElementAnimation.loopPeriod / 4).rotation, 90, accuracy: 0.001)
        XCTAssertEqual(spin.state(at: ElementAnimation.loopPeriod).rotation, 0, accuracy: 0.001)
        let bounce = ElementAnimation(kind: "bounce", delay: 1, duration: 0.6)
        XCTAssertEqual(bounce.state(at: 0.5), .settled, "at rest before its delay")
        XCTAssertLessThan(bounce.state(at: 1.3).offset.height, 0)
        let fade = ElementAnimation(kind: "fade", delay: 0, duration: 0.6)
        XCTAssertEqual(fade.state(at: 2), .settled)
        XCTAssertFalse(fade.loops)
        XCTAssertTrue(ElementAnimation.loopKinds.isSubset(of: ElementAnimation.kinds))
    }
}
