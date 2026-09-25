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

    func testSoundtracksAreGatheredFromEveryDesign() {
        var a = Design(title: "a"); a.motion = MotionSettings(); a.motion?.soundtrack = "audio_a.m4a"
        var b = Design(title: "b"); b.motion = MotionSettings(); b.motion?.soundtrack = "audio_b.mp3"
        var silent = Design(title: "silent"); silent.motion = MotionSettings()
        let still = Design(title: "still")
        XCTAssertEqual(DesignLibrary.soundtracks(in: [a, b, silent, still, a]), ["audio_a.m4a", "audio_b.mp3"])
        XCTAssertTrue(DesignLibrary.soundtracks(in: []).isEmpty)
    }

    /// Removing a soundtrack leaves its file, so the launch sweep has to keep
    /// every one something can still play — a live design, a trashed one, a
    /// saved version — and take only the file nothing names.
    func testTheAudioSweepKeepsWhatAnyDesignVersionOrTrashedDesignPlays() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("song-\(UUID()).m4a")
        try Data([1, 2, 3, 4]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let live = try XCTUnwrap(AudioStore.store(tmp))
        let trashed = try XCTUnwrap(AudioStore.store(tmp))
        let versioned = try XCTUnwrap(AudioStore.store(tmp))
        let orphan = try XCTUnwrap(AudioStore.store(tmp))
        defer { for id in [live, trashed, versioned, orphan] { AudioStore.delete(id) } }

        var playing = Design(title: "sweep: live")
        playing.motion = MotionSettings(); playing.motion?.soundtrack = live
        DesignLibrary.save(playing)
        var binned = Design(title: "sweep: trashed")
        binned.motion = MotionSettings(); binned.motion?.soundtrack = trashed
        DesignLibrary.save(binned)
        DesignLibrary.trash(id: binned.id)
        // The music taken out since, but still in the version kept before.
        var older = Design(title: "sweep: versioned")
        older.motion = MotionSettings(); older.motion?.soundtrack = versioned
        XCTAssertTrue(DesignLibrary.snapshot(older, force: true))
        var now = older; now.motion = nil
        DesignLibrary.save(now)
        defer { for id in [playing.id, binned.id, older.id] { DesignLibrary.delete(id: id) } }

        DesignLibrary.pruneUnusedAudio()

        XCTAssertNotNil(AudioStore.url(for: live), "a live design's music was deleted")
        XCTAssertNotNil(AudioStore.url(for: trashed), "a trashed design's music was deleted")
        XCTAssertNotNil(AudioStore.url(for: versioned), "a saved version's music was deleted")
        XCTAssertNil(AudioStore.url(for: orphan), "music nothing plays was kept forever")
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

    func testTracingKeepsTheInkWhereItWas() throws {
        // A dark block in the top-left quarter stays top-left.
        let img = picture(100, transparent: false) { cg in
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: 5, y: 5, width: 40, height: 40))
        }
        let t = try XCTUnwrap(Tracer.trace(img))
        XCTAssertLessThan(t.bounds.maxY, 0.55, "\(t.bounds)")
        XCTAssertLessThan(t.bounds.maxX, 0.55, "\(t.bounds)")
        XCTAssertLessThan(t.bounds.minY, 0.1, "\(t.bounds)")
    }

    func testBlankPicturesTraceToNothing() {
        XCTAssertNil(Tracer.trace(picture(40, transparent: false) { _ in }))
    }

    func testATracedShapeLiesOverTheInkThroughCropFlipAndTurn() {
        let traced = Tracer.Result(pathData: "M0 0Z", bounds: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), color: "#000000")
        var photo = Element.image("asset:x", w: 400, h: 200)
        photo.x = 100; photo.y = 50
        let size = CGSize(width: 800, height: 400)
        var shape = Tracer.shape(traced, over: photo, imageSize: size)
        XCTAssertEqual(shape.x, 200); XCTAssertEqual(shape.y, 150)
        XCTAssertEqual(shape.w, 200); XCTAssertEqual(shape.h, 50)
        // Mirrored with the photo: the ink's quarter-in from the left is now
        // a quarter-in from the right, which for a centred box is the same.
        photo.flipV = true
        shape = Tracer.shape(traced, over: photo, imageSize: size)
        XCTAssertEqual(shape.y, 100, "the lower band is now the upper one")
        XCTAssertTrue(shape.flipV)
        // Turned half about the photo's centre (300, 150).
        photo.flipV = false
        photo.rotation = 180
        shape = Tracer.shape(traced, over: photo, imageSize: size)
        XCTAssertEqual(shape.x, 200); XCTAssertEqual(shape.y, 100)
        XCTAssertEqual(shape.rotation, 180)
        // Zoomed 2x about the centre: the ink twice the size, still centred
        // across.
        photo.rotation = 0
        photo.cropScale = 2
        shape = Tracer.shape(traced, over: photo, imageSize: size)
        XCTAssertEqual(shape.w, 400); XCTAssertEqual(shape.x, 100)
    }

    func testSimplifyDropsCollinearCellCorners() {
        // Built in four steps: the older compiler cannot type one long
        // concatenation of mapped ranges in reasonable time.
        var square: [CGPoint] = []
        for x in 0...10 { square.append(CGPoint(x: Double(x), y: 0)) }
        for y in 1...10 { square.append(CGPoint(x: 10, y: Double(y))) }
        for x in stride(from: 9, through: 0, by: -1) { square.append(CGPoint(x: Double(x), y: 10)) }
        for y in stride(from: 9, through: 1, by: -1) { square.append(CGPoint(x: 0, y: Double(y))) }
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
