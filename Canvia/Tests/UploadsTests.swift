// Your uploads: the list in uploads.json, what the launch sweep keeps
// because of it, and what deleting one says and does.

import XCTest
import UIKit
@testable import Canvia

final class UploadsTests: XCTestCase {

    private var photos: [String] = []
    private var clips: [String] = []
    private var tracks: [String] = []
    private var designs: [String] = []

    override func tearDown() {
        for id in photos + clips + tracks { Uploads.remove(id) }
        for id in photos { MediaStore.delete(id) }
        for id in clips { VideoStore.delete(id) }
        for id in tracks { AudioStore.delete(id) }
        for id in designs { DesignLibrary.delete(id: id) }
        photos = []; clips = []; tracks = []; designs = []
        super.tearDown()
    }

    // MARK: fixtures

    private func storedPhoto() throws -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let src = try XCTUnwrap(MediaStore.storeOpaque(image))
        let id = String(src.dropFirst("media:".count))
        photos.append(id)
        return id
    }

    private func storedClip() throws -> String {
        let id = try XCTUnwrap(VideoStore.store(Data([0, 0, 0, 24, 102, 116, 121, 112]), ext: "mp4"))
        clips.append(id)
        return id
    }

    private func storedTrack() throws -> String {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("song-\(UUID()).m4a")
        try Data([1, 2, 3, 4]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let id = try XCTUnwrap(AudioStore.store(tmp))
        tracks.append(id)
        return id
    }

    private func saved(_ design: Design) -> Design {
        XCTAssertTrue(DesignLibrary.save(design))
        designs.append(design.id)
        return design
    }

    private func photoExists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: MediaStore.directory.appendingPathComponent("\(id).jpg").path)
    }

    /// The list as written, entry by entry.
    private func rawList() throws -> [[String: Any]] {
        let data = try Data(contentsOf: Uploads.fileURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }

    // MARK: the list

    /// Photos, videos and music, each of its kind, newest first; recorded
    /// twice is listed once.
    func testUploadsAreListedByKindNewestFirst() throws {
        let photo = try storedPhoto(), clip = try storedClip(), track = try storedTrack()
        let later = try storedPhoto()
        Uploads.record(photo, kind: .image, now: at(10))
        Uploads.record(clip, kind: .video, now: at(20))
        Uploads.record(track, kind: .audio, now: at(30))
        Uploads.record(source: "media:\(later)", now: at(40))
        Uploads.record(photo, kind: .image, now: at(50))

        let ours = Uploads.all().filter { [photo, clip, track, later].contains($0.id) }
        XCTAssertEqual(ours.map(\.id), [later, track, clip, photo])
        XCTAssertEqual(ours.map(\.kind), [.image, .audio, .video, .image])
        XCTAssertEqual(Uploads.all(.image).filter { [photo, later].contains($0.id) }.map(\.id), [later, photo])
        XCTAssertEqual(Uploads.all(.video).filter { $0.id == clip }.count, 1)
    }

    /// {"id", "kind", "added"} with the time in epoch milliseconds, as the
    /// Android twin writes it.
    func testTheListIsWrittenAsTheAndroidTwinReadsIt() throws {
        let clip = try storedClip()
        Uploads.record(source: VideoStore.src(clip, at: nil), now: at(0))
        let entry = try XCTUnwrap(try rawList().first { $0["id"] as? String == clip })
        XCTAssertEqual(entry["kind"] as? String, "video")
        XCTAssertEqual((entry["added"] as? NSNumber)?.int64Value, 1_800_000_000_000)
        XCTAssertEqual(Uploads.fileURL.lastPathComponent, "uploads.json")
    }

    /// A key, or a kind, this version does not know is kept as it was.
    func testWhatThisVersionDoesNotKnowIsKept() throws {
        let photo = try storedPhoto()
        var raw = try rawList()
        raw.append(["id": "font_later", "kind": "font", "added": 1])
        raw.append(["id": photo, "kind": "image", "added": 2, "note": "from the future"])
        try JSONSerialization.data(withJSONObject: raw).write(to: Uploads.fileURL)
        defer { Uploads.remove("font_later") }

        let track = try storedTrack()
        Uploads.record(track, kind: .audio)
        let after = try rawList()
        XCTAssertTrue(after.contains { $0["id"] as? String == "font_later" && $0["kind"] as? String == "font" })
        XCTAssertEqual(after.first { $0["id"] as? String == photo }?["note"] as? String, "from the future")
        XCTAssertFalse(Uploads.all().contains { $0.id == "font_later" }, "a kind not known here was offered")
    }

    /// The first launch with the list puts everything already stored on
    /// it, so nothing brought in before is swept; one that no longer reads
    /// is made again the same way.
    func testTheFirstListHoldsEverythingAlreadyStored() throws {
        let before = try? Data(contentsOf: Uploads.fileURL)
        defer {
            if let before { try? before.write(to: Uploads.fileURL) } else { try? FileManager.default.removeItem(at: Uploads.fileURL) }
        }
        try? FileManager.default.removeItem(at: Uploads.fileURL)
        let photo = try storedPhoto(), clip = try storedClip(), track = try storedTrack()
        Uploads.seedIfNeeded()
        let listed = Set(Uploads.all().map(\.id))
        XCTAssertTrue(listed.isSuperset(of: [photo, clip, track]))

        try Data("[{\"id\": ".utf8).write(to: Uploads.fileURL)
        Uploads.seedIfNeeded()
        XCTAssertTrue(Uploads.kept().isSuperset(of: [photo, clip, track]))
    }

    func testTheDeleteQuestionSaysHowManyDesigns() {
        XCTAssertEqual(Uploads.usedInNote(1), "Used in 1 design. It stays in them.")
        XCTAssertEqual(Uploads.usedInNote(4), "Used in 4 designs. It stays in them.")
    }

    // MARK: the sweep

    /// An upload nothing uses stays, as does anything starred; once off the
    /// list and unstarred, it goes.
    func testTheSweepKeepsUploadsAndStarredOnes() throws {
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        let photo = try storedPhoto(), clip = try storedClip(), track = try storedTrack()
        Uploads.record(photo, kind: .image)
        Uploads.record(track, kind: .audio)
        Favorites.toggle("upload", clip)
        defer { if Favorites.isFavorite("upload", clip) { Favorites.toggle("upload", clip) } }

        DesignLibrary.pruneUnusedFiles(pasteboard: board)
        XCTAssertTrue(photoExists(photo), "an upload was swept")
        XCTAssertNotNil(AudioStore.url(for: track), "uploaded music was swept")
        XCTAssertNotNil(VideoStore.url(for: clip), "a starred clip was swept")

        Uploads.remove(photo)
        Uploads.remove(track)
        Favorites.toggle("upload", clip)
        DesignLibrary.pruneUnusedFiles(pasteboard: board)
        XCTAssertFalse(photoExists(photo))
        XCTAssertNil(AudioStore.url(for: track))
        XCTAssertNil(VideoStore.url(for: clip))
    }

    // MARK: deleting one

    /// Designs on the shelf and in Recently deleted count; the one being
    /// edited counts as it stands, and a step Undo can go back to still
    /// holds the file.
    func testDeletingAnUploadCountsTheDesignsThatUseIt() throws {
        let photo = try storedPhoto()
        var shown = Design(title: "uploads: shown")
        shown.pages[0].elements = [Element.image("media:\(photo)", w: 10, h: 10)]
        shown = saved(shown)
        var behind = Design(title: "uploads: behind")
        behind.pages[0].background = .image("media:\(photo)")
        behind = saved(behind)
        DesignLibrary.trash(id: behind.id)
        _ = saved(Design(title: "uploads: neither"))

        XCTAssertEqual(DesignLibrary.use(ofUpload: photo, kind: .image),
                       DesignLibrary.UploadUse(designs: 2, held: true))
        var edited = shown
        edited.pages[0].elements = []
        XCTAssertEqual(DesignLibrary.use(ofUpload: photo, kind: .image, editing: [edited]).designs, 1)

        DesignLibrary.deleteTrashed(id: behind.id)
        XCTAssertEqual(DesignLibrary.use(ofUpload: photo, kind: .image, editing: [edited, shown]),
                       DesignLibrary.UploadUse(designs: 0, held: true), "a step Undo can take back held nothing")
        XCTAssertEqual(DesignLibrary.use(ofUpload: photo, kind: .image, editing: [edited]),
                       DesignLibrary.UploadUse(designs: 0, held: false))
    }

    /// No design uses it, but a version kept of one does: nothing to say,
    /// and the file stays for the version.
    func testAVersionHoldsAnUploadNoDesignUses() throws {
        let clip = try storedClip()
        var older = Design(title: "uploads: versioned")
        older.pages[0].elements = [Element.image(VideoStore.src(clip, at: nil), w: 16, h: 9)]
        XCTAssertTrue(DesignLibrary.snapshot(older, force: true))
        var now = older
        now.pages[0].elements = []
        _ = saved(now)
        XCTAssertEqual(DesignLibrary.use(ofUpload: clip, kind: .video),
                       DesignLibrary.UploadUse(designs: 0, held: true))
    }

    func testMusicIsUsedByTheDesignsItPlaysUnder() throws {
        let track = try storedTrack()
        var playing = Design(title: "uploads: music")
        playing.motion = MotionSettings()
        playing.motion?.soundtrack = track
        _ = saved(playing)
        XCTAssertEqual(DesignLibrary.use(ofUpload: track, kind: .audio).designs, 1)
        XCTAssertFalse(DesignLibrary.uploadKeptOutsideDesigns(track, kind: .audio))
        XCTAssertTrue(DesignLibrary.uses(playing, upload: track, kind: .audio))
        XCTAssertFalse(DesignLibrary.uses(playing, upload: track, kind: .image))
    }
}
