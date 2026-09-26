// Video clips as elements: the source grammar, looping, and a real clip
// stored, read for its poster and frames, and recognised as animation.

import XCTest
import UIKit
@testable import Canvia

final class VideoElementTests: XCTestCase {

    func testSourceGrammarAndLooping() {
        XCTAssertTrue(VideoStore.isVideo("video:vid-1"))
        XCTAssertFalse(VideoStore.isVideo("media:img-1"))
        XCTAssertFalse(VideoStore.isVideo(nil))
        XCTAssertEqual(VideoStore.split("video:vid-1")?.id, "vid-1")
        XCTAssertNil(VideoStore.split("video:vid-1")?.time)
        let stamped = VideoStore.src("vid-1", at: 1.256)
        XCTAssertEqual(stamped, "video:vid-1@1.26")
        XCTAssertEqual(VideoStore.split(stamped)?.time ?? 0, 1.26, accuracy: 0.0001)
        XCTAssertNil(VideoStore.split("media:x"))
        XCTAssertEqual(VideoStore.loopedTime(7.5, duration: 3), 1.5, accuracy: 0.0001)
        XCTAssertEqual(VideoStore.loopedTime(2, duration: 3), 2, accuracy: 0.0001)
        XCTAssertEqual(VideoStore.loopedTime(5, duration: 0), 0)
    }

    @MainActor
    func testAStoredClipHasAPosterFramesAndALength() async throws {
        // Make a real clip: a one-page design as a short MP4.
        var d = Design(title: "clip", width: 320, height: 240)
        d.pages[0].background = .color("#2040ff")
        var m = MotionSettings(); m.secondsPerPage = 1; m.fps = 24; m.movement = false; m.crossfade = false
        d.motion = m
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID()).mp4")
        try await MovieExporter.exportMP4(design: d, settings: MovieExporter.Settings(d.motion), to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let id = try XCTUnwrap(VideoStore.store(data, ext: "mp4"))
        defer { VideoStore.delete(id) }
        XCTAssertNotNil(VideoStore.url(for: id))
        XCTAssertTrue(VideoStore.all().contains(id))
        XCTAssertEqual(try XCTUnwrap(VideoStore.duration(of: id)), 1, accuracy: 0.15)

        let poster = try XCTUnwrap(VideoStore.poster(id))
        XCTAssertEqual(poster.size.width / poster.size.height, 320.0 / 240.0, accuracy: 0.02)
        XCTAssertNotNil(VideoStore.frame(id, at: 0.5))
        XCTAssertNotNil(VideoStore.resolve(VideoStore.src(id, at: 2.4)), "past the end loops round")
        XCTAssertNotNil(PhotoLibrary.resolve(VideoStore.src(id, at: nil)), "an element source resolves to the poster")

        var page = Page()
        page.elements = [Element.image(VideoStore.src(id, at: nil), w: 160, h: 120)]
        XCTAssertTrue(MovieExporter.isAnimated(page, in: d), "a page with a clip renders frame by frame")
        XCTAssertFalse(MovieExporter.isAnimated(Page(elements: [Element.image("media:x", w: 10, h: 10)]), in: d))

        // Played live, a frame is never waited for: something stands in at
        // once, and the frame asked for arrives from the worker, drawing
        // again through the version.
        let rest = try XCTUnwrap(VideoStore.peek(VideoStore.src(id, at: nil)), "the poster is already decoded")
        XCTAssertEqual(rest.key, VideoStore.src(id, at: nil))
        let before = VideoStore.live.version
        let stamped = VideoStore.src(id, at: 0.73)
        XCTAssertNotNil(VideoStore.peek(stamped), "the poster stands in while the frame is decoded")
        var landed: String?
        for _ in 0..<150 where landed == nil {
            try await Task.sleep(for: .milliseconds(20))
            if let shown = VideoStore.peek(stamped), shown.key == stamped { landed = shown.key }
        }
        XCTAssertEqual(landed, stamped, "the frame asked for never arrived")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertGreaterThan(VideoStore.live.version, before, "nothing was told to draw again")
        // Past the end, live as in an export, the clip loops round.
        let length = try XCTUnwrap(VideoStore.duration(of: id))
        let late = 0.73 + 2 * length
        let looped = VideoStore.src(id, at: VideoStore.loopedTime(late, duration: length))
        var tries = 0
        while VideoStore.peek(VideoStore.src(id, at: late))?.key != looped && tries < 150 {
            tries += 1
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(VideoStore.peek(VideoStore.src(id, at: late))?.key, looped, "past the end, the live clip did not loop")

        VideoStore.delete(id)
        XCTAssertNil(VideoStore.url(for: id))
    }

    /// A clip, or anything else moving, on the master page plays through
    /// every page that shows the master: in the video, and as Play in the
    /// editor — as Present and the Android twin already had it.
    func testTheMastersMotionCountsOnEveryPageThatShowsIt() {
        var d = Design(title: "master", width: 320, height: 240)
        d.pages = [Page(elements: [Element.image(VideoStore.src("vid_master", at: nil), w: 160, h: 120)]),
                   Page(elements: [Element.shape("rect", w: 40, h: 40)]), Page()]
        XCTAssertFalse(MovieExporter.isAnimated(d.pages[1], in: d), "no master yet")
        d.masterPageId = d.pages[0].id
        XCTAssertTrue(MovieExporter.isAnimated(d.pages[1], in: d), "the master's clip plays behind page 2")
        d.pages[2].usesMaster = false
        XCTAssertFalse(MovieExporter.isAnimated(d.pages[2], in: d), "a page that opted out has nothing moving")

        let store = DesignStore(design: d)
        store.setPage(1)
        XCTAssertTrue(store.pageIsAnimated, "Play is offered where the only motion is the master's")
        store.setPage(2)
        XCTAssertFalse(store.pageIsAnimated)
    }

    /// The preview keeps to the clock, not to how many passes it managed —
    /// a pass held up plays on from the right moment rather than in slow
    /// motion — and it is over once another page is on screen.
    @MainActor
    func testThePreviewKeepsTimeAndEndsWithItsPage() async throws {
        var d = Design(title: "preview", width: 320, height: 240)
        var moving = Element.shape("rect", w: 100, h: 100)
        moving.animation = ElementAnimation(kind: "fade", delay: 0, duration: 1)
        d.pages = [Page(elements: [moving]), Page(elements: [moving]), Page()]
        d.pages[0].holdSeconds = 10
        d.pages[1].holdSeconds = 10
        let store = DesignStore(design: d)
        store.playPreview()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(store.previewTime, "the preview is playing")
        // A pass that runs long: the main thread busy for 0.4 s.
        let busy = Date()
        while Date().timeIntervalSince(busy) < 0.4 {}
        try await Task.sleep(for: .milliseconds(100))
        let t = try XCTUnwrap(store.previewTime)
        XCTAssertGreaterThan(t, 0.4, "the preview fell behind the clock: \(t)")

        store.setPage(1)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(store.previewTime, "another page picked, the preview played on at the old page's clock")

        store.playPreview()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(store.previewTime)
        store.deletePage()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(store.previewTime, "the page played was deleted, and the preview played on")
    }

    /// The launch sweep lets go of clips nothing shows, and keeps one cut
    /// and waiting on the pasteboard.
    func testTheSweepKeepsOnlyClipsSomethingShows() throws {
        let bytes = Data([0, 0, 0, 24, 102, 116, 121, 112])
        let kept = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        let orphan = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        defer { VideoStore.delete(kept); VideoStore.delete(orphan) }
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        ElementClipboard.write([Element.image(VideoStore.src(kept, at: nil), w: 160, h: 90)], to: board)
        DesignLibrary.pruneUnusedVideos(pasteboard: board)
        XCTAssertNotNil(VideoStore.url(for: kept), "a clip waiting on the pasteboard was deleted")
        XCTAssertNil(VideoStore.url(for: orphan), "a clip nothing shows was kept")
    }

    /// A clip that only fills a shape, or is only a brand logo, is still
    /// shown — the sweep keeps it, as it keeps such photos, and as the
    /// Android twin keeps both.
    func testTheSweepKeepsClipsFillingShapesAndBrandLogos() throws {
        let bytes = Data([0, 0, 0, 24, 102, 116, 121, 112])
        let filling = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        let logo = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        let behind = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        let orphan = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        defer { for id in [filling, logo, behind, orphan] { VideoStore.delete(id) } }

        var design = Design(title: "sweep: clip fill")
        var shape = Element.shape("rect", w: 100, h: 100)
        shape.fill = .image(VideoStore.src(filling, at: nil))
        design.pages[0].elements = [shape]
        // A page behind a clip, as a design from the Android twin can have.
        design.pages[0].background = .image(VideoStore.src(behind, at: nil))
        DesignLibrary.save(design)
        defer { DesignLibrary.delete(id: design.id) }
        let kit = BrandKit.load()
        defer { kit.save() }
        var withLogo = kit
        withLogo.logos.append(VideoStore.src(logo, at: nil))
        withLogo.save()
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }

        DesignLibrary.pruneUnusedVideos(pasteboard: board)

        XCTAssertNotNil(VideoStore.url(for: filling), "a clip filling a shape was deleted")
        XCTAssertNotNil(VideoStore.url(for: logo), "a brand logo's clip was deleted")
        XCTAssertNotNil(VideoStore.url(for: behind), "a clip behind a page was deleted")
        XCTAssertNil(VideoStore.url(for: orphan), "a clip nothing shows was kept")
    }

    /// Launch sweeps photos, soundtracks and clips over one read of the
    /// library, and each keeps what it kept on its own.
    func testTheLaunchSweepTakesEachKindOfOrphanAndKeepsTheRest() throws {
        let bytes = Data([0, 0, 0, 24, 102, 116, 121, 112])
        let clip = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        let strayClip = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        defer { for id in [clip, strayClip] { VideoStore.delete(id) } }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let photo = try XCTUnwrap(MediaStore.storeOpaque(image))
        let strayPhoto = try XCTUnwrap(MediaStore.storeOpaque(image))
        let photoID = String(photo.dropFirst(6)), strayPhotoID = String(strayPhoto.dropFirst(6))
        defer { for id in [photoID, strayPhotoID] { MediaStore.delete(id) } }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("song-\(UUID()).m4a")
        try Data([1, 2, 3, 4]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let track = try XCTUnwrap(AudioStore.store(tmp))
        let strayTrack = try XCTUnwrap(AudioStore.store(tmp))
        defer { for id in [track, strayTrack] { AudioStore.delete(id) } }

        var design = Design(title: "sweep: all three")
        design.pages[0].elements = [Element.image(photo, w: 100, h: 100),
                                    Element.image(VideoStore.src(clip, at: nil), w: 160, h: 90)]
        design.motion = MotionSettings(); design.motion?.soundtrack = track
        DesignLibrary.save(design)
        defer { DesignLibrary.delete(id: design.id) }
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }

        DesignLibrary.pruneUnusedFiles(pasteboard: board)

        XCTAssertNotNil(VideoStore.url(for: clip), "a clip in use was deleted")
        XCTAssertNil(VideoStore.url(for: strayClip), "a clip nothing shows was kept")
        func photoExists(_ id: String) -> Bool {
            FileManager.default.fileExists(atPath: MediaStore.directory.appendingPathComponent("\(id).jpg").path)
        }
        XCTAssertTrue(photoExists(photoID), "a photo in use was deleted")
        XCTAssertFalse(photoExists(strayPhotoID), "a photo nothing shows was kept")
        XCTAssertNotNil(AudioStore.url(for: track), "a soundtrack in use was deleted")
        XCTAssertNil(AudioStore.url(for: strayTrack), "a soundtrack nothing plays was kept")
    }

    /// Which clips a design file carries whole — the rule the Android twin
    /// follows too, so either phone packs a design the same: in id order,
    /// each within the single limit and of a type both phones play, while
    /// the running total stays within the budget; the rest go as stills.
    func testClipsArePackedInIdOrderWithinTheTotal() {
        let mb = 1024 * 1024
        let clips: [String: (bytes: Int, ext: String)] = [
            "vid_h": (bytes: 31 * mb, ext: "mp4"),
            "vid_g": (bytes: 1 * mb, ext: "webm"),
            "vid_f": (bytes: 5 * mb, ext: "3gp"),
            "vid_e": (bytes: 10 * mb, ext: "mp4"),
            "vid_d": (bytes: 20 * mb, ext: "MOV"),
            "vid_c": (bytes: 25 * mb, ext: "m4v"),
            "vid_b": (bytes: 25 * mb, ext: "mov"),
            "vid_a": (bytes: 25 * mb, ext: "mp4"),
        ]
        // a, b, c and d come to 95 MB; e would take it past 100, f just
        // fits; g is a WebM, h is too long on its own.
        XCTAssertEqual(DesignPackage.packedVideoIDs(clips), ["vid_a", "vid_b", "vid_c", "vid_d", "vid_f"])
        XCTAssertEqual(DesignPackage.packedVideoIDs(["vid_x": (bytes: 30 * mb, ext: "mp4")]), ["vid_x"])
        XCTAssertTrue(DesignPackage.packedVideoIDs(["vid_x": (bytes: 30 * mb + 1, ext: "mp4")]).isEmpty)
        XCTAssertTrue(DesignPackage.packedVideoIDs(["vid_x": (bytes: 1, ext: "mkv")]).isEmpty)
        XCTAssertTrue(DesignPackage.packedVideoIDs([:]).isEmpty)
    }

    /// A clip that only fills a shape travels too, and the fill comes back
    /// pointing at the imported clip.
    func testAClipFillingAShapeTravelsInADesignFile() throws {
        let bytes = Data([0, 0, 0, 24, 102, 116, 121, 112])
        let id = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        defer { VideoStore.delete(id) }
        var design = Design(title: "clip fill", width: 320, height: 240)
        var shape = Element.shape("rect", w: 100, h: 100)
        shape.fill = .image(VideoStore.src(id, at: nil))
        design.pages[0].elements = [shape]
        XCTAssertEqual(DesignPackage.videoIDs(in: design), [id])
        let data = try DesignPackage.export(design)
        let package = try JSONDecoder().decode(DesignPackage.Package.self, from: data)
        XCTAssertEqual(package.videos?[id]?.data, bytes)

        let imported = try DesignPackage.import(data)
        let fill = try XCTUnwrap(imported.pages[0].elements[0].fill?.src)
        let fresh = try XCTUnwrap(VideoStore.split(fill)?.id)
        defer { VideoStore.delete(fresh) }
        XCTAssertNotEqual(fresh, id)
        XCTAssertNotNil(VideoStore.url(for: fresh))
    }

    /// A clip travels in a design file, under "videos", and comes back as a
    /// clip of its own under a fresh id, its moments kept — as the Android
    /// twin writes and reads it.
    func testAClipTravelsInADesignFile() throws {
        let bytes = Data([0, 0, 0, 24, 102, 116, 121, 112])
        let id = try XCTUnwrap(VideoStore.store(bytes, ext: "mp4"))
        defer { VideoStore.delete(id) }
        var design = Design(title: "clip", width: 320, height: 240)
        design.pages[0].elements = [Element.image(VideoStore.src(id, at: nil), w: 160, h: 120),
                                    Element.image(VideoStore.src(id, at: 1.25), w: 160, h: 120)]
        let data = try DesignPackage.export(design)
        let package = try JSONDecoder().decode(DesignPackage.Package.self, from: data)
        XCTAssertEqual(package.videos?[id]?.data, bytes)
        XCTAssertEqual(package.videos?[id]?.ext, "mp4")

        let imported = try DesignPackage.import(data)
        let sources = imported.pages[0].elements.compactMap(\.src)
        let fresh = try XCTUnwrap(VideoStore.split(sources[0])?.id)
        defer { VideoStore.delete(fresh) }
        XCTAssertNotEqual(fresh, id)
        XCTAssertEqual(sources, [VideoStore.src(fresh, at: nil), VideoStore.src(fresh, at: 1.25)])
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(VideoStore.url(for: fresh))), bytes)

        // A design with no clips writes no "videos" at all.
        let plain = try DesignPackage.export(Design(title: "plain", width: 100, height: 100))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("\"videos\""))
    }
}
