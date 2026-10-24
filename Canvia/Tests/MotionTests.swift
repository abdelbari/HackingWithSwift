// Round 32's motion, as the Android twin's tests have it: the timeline's
// lanes (Timeline.movedTrack, AudioTracks.split) and a motion path's
// interpolation (ElementAnimation.pathState) and a draw-on's reveal
// fractions (ElementAnimation.drawn) row for row from the shared fixture
// motion.json; then a recorded path, the new entrances and photo motion,
// page animations, a clip behind the page, the graphics that move and how
// PowerPoint is told of them.

import XCTest
@testable import Canvia

final class MotionTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("motion") }

    private func track(_ value: Any) throws -> AudioTrack {
        try JSONDecoder().decode(AudioTrack.self, from: SharedFixture.encoded(value))
    }

    private func assertSame(_ a: AudioTrack, _ b: AudioTrack, _ note: String, line: UInt = #line) {
        XCTAssertEqual(a.src, b.src, note, line: line)
        XCTAssertEqual(a.start, b.start, accuracy: 1e-9, note, line: line)
        XCTAssertEqual(a.trimStart, b.trimStart, accuracy: 1e-9, note, line: line)
        XCTAssertEqual(a.trimEnd ?? -1, b.trimEnd ?? -1, accuracy: 1e-9, note, line: line)
        XCTAssertEqual(a.volume, b.volume, accuracy: 1e-9, note, line: line)
        XCTAssertEqual(a.fadeIn, b.fadeIn, accuracy: 1e-9, note, line: line)
        XCTAssertEqual(a.fadeOut, b.fadeOut, accuracy: 1e-9, note, line: line)
        XCTAssertEqual(a.loop, b.loop, note, line: line)
        XCTAssertEqual(a.name, b.name, note, line: line)
    }

    // MARK: lanes (shared rows)

    func testMovedTrackRowsFromTheSharedFixture() throws {
        let rows = try XCTUnwrap(try fixture()["moveTrack"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for (i, row) in rows.enumerated() {
            let t = try track(try XCTUnwrap(row["track"]))
            let moved = Timeline.movedTrack(t, dx: try XCTUnwrap(row["dx"] as? Double), scale: try XCTUnwrap(row["scale"] as? Double),
                                            film: try XCTUnwrap(row["film"] as? Double),
                                            beats: (row["beats"] as? [Double]) ?? [])
            XCTAssertEqual(moved.start, try XCTUnwrap(row["start"] as? Double), accuracy: 1e-9, "row \(i)")
            XCTAssertEqual(moved.trimStart, t.trimStart, "row \(i): only the start moves")
        }
    }

    func testSplitTrackRowsFromTheSharedFixture() throws {
        let rows = try XCTUnwrap(try fixture()["splitTrack"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for (i, row) in rows.enumerated() {
            let t = try track(try XCTUnwrap(row["track"]))
            var design = Design(title: "split")
            design.audioTracks = [t]
            let out = AudioTracks.split(design, trackId: t.id, at: try XCTUnwrap(row["t"] as? Double),
                                        duration: row["duration"] as? Double)
            guard let expected = row["tracks"] as? [Any] else {
                XCTAssertNil(out, "row \(i) is refused")
                continue
            }
            let tracks = try XCTUnwrap(out, "row \(i)").audioTracks
            XCTAssertEqual(tracks.count, 2, "row \(i)")
            assertSame(tracks[0], try track(expected[0]), "row \(i) first")
            XCTAssertEqual(tracks[0].id, t.id, "row \(i): the first keeps its id")
            assertSame(tracks[1], try track(expected[1]), "row \(i) second")
            XCTAssertNotEqual(tracks[1].id, t.id, "row \(i): the second has a new id")
        }
    }

    // MARK: motion paths (shared rows)

    func testPathStateRowsFromTheSharedFixture() throws {
        let rows = try XCTUnwrap(try fixture()["pathState"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for (i, row) in rows.enumerated() {
            let raw = try XCTUnwrap(row["path"] as? [[Double]])
            var anim = ElementAnimation(kind: ElementAnimation.pathKind, delay: 0, duration: 1)
            anim.path = raw.map { MotionPath.Point(dx: $0[0], dy: $0[1], t: $0[2]) }
            anim.smooth = try XCTUnwrap(row["smooth"] as? Bool)
            anim.orient = try XCTUnwrap(row["orient"] as? Bool)
            let want = try XCTUnwrap(row["state"] as? [Double])
            let s = ElementAnimation.pathState(anim, try XCTUnwrap(row["p"] as? Double))
            XCTAssertEqual(Double(s.offset.width), want[0], accuracy: 1e-5, "row \(i) dx")
            XCTAssertEqual(Double(s.offset.height), want[1], accuracy: 1e-5, "row \(i) dy")
            XCTAssertEqual(s.rotation, want[2], accuracy: 1e-5, "row \(i) rotation")
        }
    }

    func testDrawnRevealFractionRowsFromTheSharedFixture() throws {
        let rows = try XCTUnwrap(try fixture()["drawn"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for (i, row) in rows.enumerated() {
            let lengths = try XCTUnwrap(row["lengths"] as? [Double])
            let want = try XCTUnwrap(row["drawn"] as? [Double])
            let got = ElementAnimation.drawn(lengths, p: try XCTUnwrap(row["p"] as? Double))
            XCTAssertEqual(got.count, want.count, "row \(i)")
            for (g, w) in zip(got, want) { XCTAssertEqual(g, w, accuracy: 1e-9, "row \(i)") }
        }
    }

    // MARK: lanes

    func testATrimPullsOneEndAndKeepsTheRestWhereItPlays() {
        let song = AudioTrack(src: "audio:s", start: 2, trimStart: 1, trimEnd: 9, name: "Song")
        // The end pulled 2 s back at 10 points a second.
        let shorter = Timeline.trimmedTrack(song, edge: .end, dx: -20, scale: 10, duration: 12)
        XCTAssertEqual(shorter.trimEnd ?? 0, 7, accuracy: 1e-9)
        XCTAssertEqual(shorter.start, 2)
        // Pulled to the file's end it has no end of its own.
        XCTAssertNil(Timeline.trimmedTrack(song, edge: .end, dx: 100, scale: 10, duration: 12).trimEnd)
        // The start pulled 1.5 s on: the trim and the lane's start move with it.
        let later = Timeline.trimmedTrack(song, edge: .start, dx: 15, scale: 10, duration: 12)
        XCTAssertEqual(later.trimStart, 2.5, accuracy: 1e-9)
        XCTAssertEqual(later.start, 3.5, accuracy: 1e-9)
        // Never before the film's start, nor the file's.
        let early = Timeline.trimmedTrack(song, edge: .start, dx: -100, scale: 10, duration: 12)
        XCTAssertEqual(early.trimStart, 0, accuracy: 1e-9)
        XCTAssertEqual(early.start, 1, accuracy: 1e-9)
        // At least a tenth played.
        let least = Timeline.trimmedTrack(song, edge: .end, dx: -500, scale: 10, duration: 12)
        XCTAssertEqual((least.trimEnd ?? 0) - least.trimStart, AudioTrack.minLength, accuracy: 1e-9)
    }

    func testAnElementBarMovesWithinItsPageAndItsEndsTrim() {
        let timing = ElementTiming(start: 1, end: 2)
        let moved = Timeline.movedTiming(timing, dx: 5, scale: 10, hold: 5)
        XCTAssertEqual(moved, ElementTiming(start: 1.5, end: 2.5))
        // Kept within the page, its length kept; at the page's end it has none.
        XCTAssertEqual(Timeline.movedTiming(timing, dx: 100, scale: 10, hold: 5), ElementTiming(start: 4, end: nil))
        // Its length kept: from the page's end, back to the start.
        XCTAssertEqual(Timeline.movedTiming(ElementTiming(start: 0.5, end: nil), dx: -10, scale: 10, hold: 5),
                       ElementTiming(start: 0, end: 4.5))
        // The whole page, moved, is still the whole page: no timing at all.
        XCTAssertNil(Timeline.movedTiming(nil, dx: 10, scale: 10, hold: 5))
        XCTAssertEqual(Timeline.trimmedTiming(timing, edge: .start, dx: 30, scale: 10, hold: 5),
                       ElementTiming(start: 1.9, end: 2), "a tenth at least")
        XCTAssertEqual(Timeline.trimmedTiming(timing, edge: .end, dx: 10, scale: 10, hold: 5),
                       ElementTiming(start: 1, end: 3))
        XCTAssertEqual(Timeline.trimmedTiming(nil, edge: .end, dx: -20, scale: 10, hold: 5),
                       ElementTiming(start: 0, end: 3))
    }

    func testAPinchKeepsWithinItsScalesAndThePlayheadWhereItWas() {
        XCTAssertEqual(Timeline.pinched(40, factor: 2, minScale: 30), 80)
        XCTAssertEqual(Timeline.pinched(40, factor: 0.1, minScale: 30), 30)
        XCTAssertEqual(Timeline.pinched(150, factor: 4, minScale: 30), Timeline.maxScale)
        XCTAssertEqual(Timeline.maxScale, 200)
        // The playhead at 3 s, 20 points from the strip's left at 40 a second.
        XCTAssertEqual(Timeline.anchoredScroll(playhead: 3, scroll: 100, from: 40, to: 80), 220)
        XCTAssertEqual(Timeline.anchoredScroll(playhead: 1, scroll: 0, from: 40, to: 20), 0)
    }

    func testALaneIsReadAsItsNameAndWhenItPlays() {
        XCTAssertEqual(AudioTracks.spoken("Song", from: 3, to: 18), "Song, 0:03 to 0:18")
        XCTAssertEqual(AudioTracks.wholeClock(62.5), "1:03")
        XCTAssertEqual(AudioTracks.wholeClock(-1), "0:00")
    }

    func testDuplicatingATrackPutsACopyAfterIt() throws {
        var design = Design(title: "dup")
        design.audioTracks = [AudioTrack(id: "a", src: "audio:x", start: 1, name: "A"),
                              AudioTrack(id: "b", src: "audio:y", name: "B")]
        let out = try XCTUnwrap(AudioTracks.duplicating(design, trackId: "a")).audioTracks
        XCTAssertEqual(out.map(\.name), ["A", "A", "B"])
        XCTAssertNotEqual(out[1].id, "a")
        XCTAssertEqual(out[1].start, 1)
        XCTAssertNil(AudioTracks.duplicating(design, trackId: "none"))
    }

    func testALaneDraggedIsOneStepCalledMoveAudioOrTrimAudio() {
        var before = Design(title: "lanes")
        before.audioTracks = [AudioTrack(id: "a", src: "audio:x", start: 1, trimStart: 0, trimEnd: 5, name: "A")]
        var moved = before
        moved.audioTracks[0].start = 2
        XCTAssertEqual(History.label(before: before, after: moved), "Move audio")
        var trimmed = before
        trimmed.audioTracks[0].trimStart = 1
        trimmed.audioTracks[0].start = 2
        XCTAssertEqual(History.label(before: before, after: trimmed), "Trim audio")
        var louder = before
        louder.audioTracks[0].volume = 0.5
        XCTAssertEqual(History.label(before: before, after: louder), "Edit")
    }

    // MARK: recording a path

    func testARecordedDragIsThinnedAndTimedFromWhereItRests() {
        let samples = [
            MotionPath.Sample(x: 0, y: 0, time: 0),
            MotionPath.Sample(x: 1, y: 0, time: 0.1),
            MotionPath.Sample(x: 10, y: 0, time: 0.5),
            MotionPath.Sample(x: 10.5, y: 0, time: 0.6),
            MotionPath.Sample(x: 20, y: 0, time: 1),
        ]
        let path = MotionPath.recorded(samples)
        XCTAssertEqual(path, [MotionPath.Point(dx: -20, dy: 0, t: 0), MotionPath.Point(dx: -10, dy: 0, t: 0.5),
                              MotionPath.Point(dx: 0, dy: 0, t: 1)])
        XCTAssertEqual(MotionPath.seconds(samples), 1)
        XCTAssertTrue(MotionPath.travels(path))
        // Nowhere much: no path.
        XCTAssertEqual(MotionPath.recorded([MotionPath.Sample(x: 0, y: 0, time: 0), MotionPath.Sample(x: 1, y: 1, time: 1)]), [])
        // At most 200 points, the first and the last kept.
        let long = (0..<1000).map { MotionPath.Sample(x: Double($0) * 3, y: 0, time: Double($0) / 100) }
        let kept = MotionPath.recorded(long)
        XCTAssertEqual(kept.count, MotionPath.maxPoints)
        XCTAssertEqual(kept.first?.t, 0)
        XCTAssertEqual(kept.last, MotionPath.Point(dx: 0, dy: 0, t: 1))
        XCTAssertEqual(MotionPath.seconds(long), MotionPath.maxSeconds)
        XCTAssertEqual(MotionPath.speed(0.1), 0.25)
        XCTAssertEqual(MotionPath.speed(1.13), 1.25)
        XCTAssertEqual(MotionPath.speed(9), 4)
        XCTAssertEqual(MotionPath.speedLabel(0.25), "0.25x")
        XCTAssertEqual(MotionPath.speedLabel(2), "2x")
    }

    func testAPathIsWrittenWholeOnAPathAndReadByAnyBuild() throws {
        var anim = ElementAnimation(kind: ElementAnimation.pathKind, delay: 0.5, duration: 2)
        anim.path = [MotionPath.Point(dx: -100, dy: 0, t: 0), MotionPath.Point(dx: 0, dy: 0, t: 1)]
        anim.orient = true
        anim.speed = 2
        let data = try JSONEncoder().encode(anim)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "path")
        XCTAssertEqual(object["path"] as? [[Double]], [[-100, 0, 0], [0, 0, 1]])
        XCTAssertEqual(object["smooth"] as? Bool, true)
        XCTAssertEqual(object["orient"] as? Bool, true)
        XCTAssertEqual(object["speed"] as? Double, 2)
        XCTAssertEqual(try JSONDecoder().decode(ElementAnimation.self, from: data), anim)
        // Any other kind writes only its three.
        let fade = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(ElementAnimation())) as? [String: Any])
        XCTAssertEqual(Set(fade.keys), ["kind", "delay", "duration"])
        // A point that is not three numbers is passed over.
        let odd = #"{"kind":"path","delay":0,"duration":1,"path":[[0,0,0],[1,"x",0.5],[5,5,2]]}"#
        let read = try JSONDecoder().decode(ElementAnimation.self, from: Data(odd.utf8))
        XCTAssertEqual(read.path, [MotionPath.Point(dx: 0, dy: 0, t: 0), MotionPath.Point(dx: 5, dy: 5, t: 1)])
        // Played at its speed: 2 s at twice the speed is over in 1 s, after its delay.
        XCTAssertEqual(anim.end, 1.5, accuracy: 1e-9)
        XCTAssertEqual(anim.state(at: 0.5).offset.width, -100, accuracy: 1e-9)
        XCTAssertEqual(anim.state(at: 1.5), .settled)
        // A path with no points fades in, as a build that does not know it does.
        let bare = ElementAnimation(kind: ElementAnimation.pathKind, delay: 0, duration: 1)
        XCTAssertEqual(bare.state(at: 0).opacity, 0, accuracy: 1e-9)
    }

    func testAPathGoesWhereItWasDrawnWhateverTheElementsTurn() {
        var el = Element.shape("rect", w: 100, h: 100)
        el.rotation = 90
        var s = ElementAnimation.State()
        s.offset = CGSize(width: 10, height: 0)
        let own = ElementAnimation.inOwnSpace(s, el)
        XCTAssertEqual(Double(own.offset.width), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(own.offset.height), -10, accuracy: 1e-9)
        el.rotation = 0
        el.flipH = true
        XCTAssertEqual(Double(ElementAnimation.inOwnSpace(s, el).offset.width), -10, accuracy: 1e-9)
    }

    // MARK: new entrances and photo motion

    func testTheNewEntrancesHalfwayIn() {
        func half(_ kind: String, el: Element? = nil) -> ElementAnimation.State {
            // Eased: progress at the half way is 1 - 0.5³.
            ElementAnimation(kind: kind, delay: 0, duration: 1).state(at: 0.5, size: 100, el: el)
        }
        let p = 1 - pow(0.5, 3)
        XCTAssertEqual(half("wipe").reveal, p, accuracy: 1e-9)
        XCTAssertEqual(half("breathe").scale, 0.9 + 0.1 * p, accuracy: 1e-9)
        XCTAssertEqual(half("breathe").opacity, p, accuracy: 1e-9)
        XCTAssertEqual(Double(half("drift").offset.width), (1 - p) * 20, accuracy: 1e-9)
        XCTAssertEqual(half("tumble").rotation, -90 * (1 - p), accuracy: 1e-9)
        XCTAssertEqual(half("tumble").scale, 0.5 + 0.5 * p, accuracy: 1e-9)
        var text = Element.text("Hello")
        text.h = 60
        let base = half("baseline", el: text)
        XCTAssertTrue(base.clipped)
        XCTAssertEqual(Double(base.offset.height), (1 - p) * 60, accuracy: 1e-9)
        XCTAssertEqual(ElementAnimation.applied([Element.shape("rect")], kind: "baseline")[0].animation, nil,
                       "baseline is a text's")
    }

    func testAPhotosMotionMovesItsCropOverTheHoldNotItsFrame() {
        let photo = Element.image("asset:p")
        let zoom = ElementAnimation(kind: ElementAnimation.photoZoom, delay: 0, duration: 0.6)
        XCTAssertEqual(zoom.state(at: 2, el: photo, hold: 4).cropZoom, 1.075, accuracy: 1e-9)
        XCTAssertEqual(zoom.state(at: 4, el: photo, hold: 4).cropZoom, 1.15, accuracy: 1e-9)
        XCTAssertEqual(zoom.state(at: 2, el: photo, hold: 4).offset, .zero)
        let pan = ElementAnimation(kind: ElementAnimation.photoPan, delay: 0, duration: 0.6)
        XCTAssertEqual(pan.state(at: 1, el: photo, hold: 4).cropX ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertEqual(pan.state(at: 1, el: photo, hold: 4).cropZoom, 1.1, accuracy: 1e-9)
        XCTAssertTrue(zoom.drifts)
        // Only a photo or a clip moves; anything else stays still.
        XCTAssertEqual(zoom.state(at: 2, el: Element.shape("rect"), hold: 4), .settled)
        let chosen = ElementAnimation.applied([Element.shape("rect"), photo], kind: ElementAnimation.photoPan)
        XCTAssertNil(chosen[0].animation)
        XCTAssertEqual(chosen[1].animation?.kind, ElementAnimation.photoPan)
    }

    func testTwinkleLoopsAndDrawDrawsOnAtAnEvenPace() {
        let twinkle = ElementAnimation(kind: ElementAnimation.twinkle, delay: 0, duration: 0.6)
        XCTAssertTrue(twinkle.loops)
        XCTAssertEqual(twinkle.state(at: ElementAnimation.loopPeriod / 4).scale, 1.15, accuracy: 1e-9)
        let draw = ElementAnimation(kind: ElementAnimation.draw, delay: 0, duration: 2)
        XCTAssertEqual(draw.state(at: 0.5).draw, 0.25, accuracy: 1e-9)
        XCTAssertEqual(draw.state(at: 2), .settled)
        let spans = ElementAnimation.drawSpans([100, 50, 50], total: 1.2)
        XCTAssertEqual(spans.map(\.delay), [0, 0.6, 0.9])
        XCTAssertEqual(spans.map(\.duration), [0.6, 0.3, 0.3])
        XCTAssertEqual(ElementAnimation.drawSpans([0, 0], total: 1).map(\.delay), [0, 0.5])
    }

    // MARK: page animations

    func testAPageAnimationPlaysIntoItsElementsInLayerOrder() throws {
        var own = Element.shape("rect")
        own.animation = ElementAnimation(kind: "pop", delay: 1, duration: 1)
        let elements = [Element.shape("rect"), own, Element.text("Hi")]
        let played = PageAnimation.resolved(elements, PageAnimation(kind: "pan", mode: PageAnimation.both))
        XCTAssertEqual(played[0].animation, ElementAnimation(kind: "slideLeft", delay: 0, duration: 0.6))
        XCTAssertEqual(played[1].animation?.kind, "pop", "its own kept")
        XCTAssertEqual(played[2].animation?.delay ?? 0, 0.16, accuracy: 1e-9)
        XCTAssertEqual(played[2].exitAnimation?.delay ?? 0, 0.16, accuracy: 1e-9)
        XCTAssertEqual(played[1].exitAnimation?.kind, "slideLeft")
        let enters = PageAnimation.resolved(elements, PageAnimation(kind: "stomp", mode: PageAnimation.enter))
        XCTAssertNil(enters[0].exitAnimation)
        XCTAssertEqual(enters[0].animation?.kind, "pop")
        XCTAssertEqual(PageAnimation.elementKind("neon"), "fade", "a kind from a newer build fades")
        XCTAssertEqual(PageAnimation.resolved(elements, nil), elements)
    }

    func testAPagesAnimationIsItsOwnKeyAndReadLeniently() throws {
        var page = Page()
        page.pageAnimation = PageAnimation(kind: "rise", mode: PageAnimation.exit)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
        let written = try XCTUnwrap(object["pageAnimation"] as? [String: Any])
        XCTAssertEqual(written["kind"] as? String, "rise")
        XCTAssertEqual(written["mode"] as? String, "exit")
        XCTAssertEqual(try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page)).pageAnimation, page.pageAnimation)
        let odd = ##"{"id":"p","background":{"type":"color","value":"#ffffff"},"elements":[],"pageAnimation":{"kind":"tumble","mode":"sideways"}}"##
        XCTAssertEqual(try JSONDecoder().decode(Page.self, from: Data(odd.utf8)).pageAnimation,
                       PageAnimation(kind: "tumble", mode: PageAnimation.enter))
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Page())) as? [String: Any])
        XCTAssertNil(plain["pageAnimation"], "no key without one")
    }

    // MARK: a clip behind the page

    func testAClipBecomesTheBackgroundAndComesBack() throws {
        var clip = Element.image("video:abc", w: 400, h: 300)
        clip.clip = ClipPlayback(start: 1, end: 4, speed: 2, volume: 0.5)
        clip.cropX = 0.3
        var page = Page()
        page.elements = [clip, Element.text("Hi")]
        XCTAssertTrue(DesignStore.canBecomeBackground(clip))
        let used = try XCTUnwrap(PageBackgrounds.usedClip(page, clip))
        XCTAssertEqual(used.elements.count, 1)
        XCTAssertEqual(used.background, .image("video:abc"))
        XCTAssertEqual(used.backgroundClip?.playback, clip.clip)
        XCTAssertEqual(used.backgroundClip?.cropX, 0.3)
        // Written beside its first frame, which any reader shows.
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(used)) as? [String: Any])
        let bg = try XCTUnwrap(object["background"] as? [String: Any])
        XCTAssertEqual(bg["type"] as? String, "image")
        XCTAssertEqual(bg["value"] as? String, "video:abc")
        let written = try XCTUnwrap(bg["clip"] as? [String: Any])
        XCTAssertEqual(written["src"] as? String, "video:abc")
        let playback = try XCTUnwrap(written["playback"] as? [String: Any])
        XCTAssertEqual(Set(playback.keys), ["start", "end", "speed", "loop", "volume", "muted", "fadeIn", "fadeOut"])
        let read = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(used))
        XCTAssertEqual(read.backgroundClip, used.backgroundClip)
        XCTAssertEqual(read.background, used.background)
        // A background changed to anything else leaves the clip behind.
        var changed = used
        changed.background = .color("#000000")
        XCTAssertNil(changed.backgroundClip)
        // Laid as the background lays a picture, playing as it did.
        let behind = try XCTUnwrap(PageBackgrounds.clipElement(used, size: CGSize(width: 100, height: 50), cover: 5))
        XCTAssertEqual(behind.x, -5)
        XCTAssertEqual(behind.w, 110)
        XCTAssertEqual(behind.clip, clip.clip)
        XCTAssertEqual(behind.cropX, 0.3)
        // Its sound is heard under the page, and the page plays.
        var design = Design(title: "bg")
        design.pages = [used]
        XCTAssertEqual(AudioMix.clips(design: design, page: used).first?.source, "abc")
        XCTAssertTrue(MovieExporter.isAnimated(used, in: design))
        // A clip on a locked page stays as it is.
        XCTAssertFalse(PageLocks.allows({ var p = used; p.locked = true; return p }(),
                                        becoming: { var p = used; p.locked = true; p.backgroundClip?.playback.muted = true; return p }()))
    }

    // MARK: graphics that move

    func testAboutSixtyGraphicsMoveAndGoOnAnimated() throws {
        let moving = GraphicsLibrary.moving
        XCTAssertEqual(moving.count, 68)
        XCTAssertEqual(Set(moving.compactMap(\.motion)), ["draw", "twinkle"])
        XCTAssertEqual(GraphicsLibrary.inCategory(GraphicsLibrary.animated).count, 68)
        XCTAssertEqual(GraphicsLibrary.search("animated").count, 68)
        let arrow = try XCTUnwrap(GraphicsLibrary.graphic("arrow-01"))
        XCTAssertEqual(arrow.motion, "draw")
        let parts = GraphicsLibrary.elements(arrow, pageWidth: 1080, pageHeight: 1080)
        XCTAssertTrue(parts.allSatisfy { $0.animation?.kind == ElementAnimation.draw })
        // Its paths drawn in turn, all within the draw-on's time.
        let last = try XCTUnwrap(parts.last?.animation)
        XCTAssertEqual(last.delay + last.duration, ElementAnimation.drawDuration, accuracy: 0.011)
        XCTAssertEqual(parts.first?.animation?.delay, 0)
        let sparkle = GraphicsLibrary.elements(try XCTUnwrap(GraphicsLibrary.graphic("sparkle-03")), pageWidth: 1080, pageHeight: 1080)
        XCTAssertEqual(sparkle.map { $0.animation?.delay ?? -1 }, [0, 0.15, 0.3])
        XCTAssertNil(GraphicsLibrary.graphic("blob-01")?.motion)
    }

    func testAPathsLengthIsMeasuredOneSubpathAtATime() {
        XCTAssertEqual(SVGPath.subpathLengths("M0 0L10 0M0 0L0 5Z"), [10, 10])
        let square = Element.shape("rect", w: 100, h: 50)
        XCTAssertEqual(ElementAnimation.lengthOf(square), 300)
    }

    func testAWebPageDrawsAGraphicOnWhereAStillShowsItFinished() {
        var line = Element.shape("rect")
        line.animation = ElementAnimation(kind: ElementAnimation.draw, delay: 0.3, duration: 0.6)
        XCTAssertEqual(SVGExporter.moving("<path/>", line),
                       "<g style=\"animation:cv-draw 0.6s linear 0.3s both\"><path/></g>")
        var star = Element.shape("rect")
        star.animation = ElementAnimation(kind: ElementAnimation.twinkle, delay: 0.15, duration: 0.6)
        XCTAssertTrue(SVGExporter.moving("<path/>", star).contains("animation:cv-twinkle 1.2s ease-in-out 0.15s infinite"))
        XCTAssertEqual(SVGExporter.moving("<path/>", Element.shape("rect")), "<path/>")
        // At rest — a still export, a thumbnail — the drawing is finished.
        XCTAssertEqual(line.animation?.state(at: 0.9), .settled)
        var design = Design(title: "web")
        design.pages[0].elements = [line]
        XCTAssertTrue(SVGExporter.moves(design, page: design.pages[0]))
    }

    // MARK: PowerPoint

    func testPowerPointIsGivenTheNearestEffectAndAPathAsItsOwn() {
        XCTAssertEqual(PptxAnimations.effect("wipe"), PptxAnimations.Effect(preset: 22, subtype: 8, filter: "wipe(right)"))
        XCTAssertEqual(PptxAnimations.effect("draw")?.preset, 10)
        XCTAssertNil(PptxAnimations.effect("pulse"))
        let points = [MotionPath.Point(dx: -100, dy: 50, t: 0), MotionPath.Point(dx: 0, dy: 0, t: 1)]
        XCTAssertEqual(PptxAnimations.motion(points, slideW: 1000, slideH: 500), "M -0.1 0.1 L 0 0 E")
        var el = Element.shape("rect")
        var anim = ElementAnimation(kind: ElementAnimation.pathKind, delay: 0, duration: 1)
        anim.path = points
        el.animation = anim
        let xml = PptxAnimations.timing([(id: 3, el: el)], slideW: 1000, slideH: 500)
        XCTAssertTrue(xml.contains("<p:animMotion origin=\"layout\" path=\"M -0.1 0.1 L 0 0 E\""))
        XCTAssertTrue(xml.contains("<p:spTgt spid=\"3\"/>"))
        XCTAssertEqual(PptxAnimations.timing([(id: 3, el: Element.shape("rect"))], slideW: 1000, slideH: 500), "")
    }
}
