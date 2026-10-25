// The design's soundtrack on its own, as an M4A — the Android twin's
// AudioDownloadTest, with the shared fixture Fixtures/audio-download.json —
// and an export that keeps going once Canvia is left (ContinuedExport), as
// the queue runs it with a host that stands in for iOS 26's.

import XCTest
@testable import Canvia

final class AudioDownloadTests: XCTestCase {

    /// Shared: Fixtures/audio-download.json — with both switches on, the
    /// audio is the MP4's own mix, segment for segment; each switch takes
    /// its sources out.
    func testTheAudioDownloadPlansWhatTheMP4PlansLessWhatIsSwitchedOff() throws {
        let cases = try XCTUnwrap(try SharedFixture.object("audio-download")["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 3)
        for row in cases {
            let name = try XCTUnwrap(row["name"] as? String)
            let design = try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(row["design"])))
            let pages = design.visiblePageIndices
            let settings = MovieExporter.Settings(design.motion)
            let clips = try XCTUnwrap(row["clipDurations"] as? [String: Double])
            let tracks = try XCTUnwrap(row["trackDurations"] as? [String: Double])
            let film = AudioMix.filmPlan(design: design, pages: pages, settings: settings,
                                         clipDurations: clips, trackDurations: tracks)
            XCTAssertEqual(AudioMix.seconds(design: design, pages: pages, settings: settings),
                           try XCTUnwrap(row["seconds"] as? Double), accuracy: 1e-9, name)
            for plan in try XCTUnwrap(row["plans"] as? [[String: Any]]) {
                let voice = try XCTUnwrap(plan["voice"] as? Bool)
                let clipSound = try XCTUnwrap(plan["clips"] as? Bool)
                let audio = AudioMix.audioPlan(design: design, pages: pages, settings: settings,
                                               clipDurations: clips, trackDurations: tracks,
                                               voice: voice, clipSound: clipSound)
                let place = "\(name), voice \(voice), clips \(clipSound)"
                XCTAssertEqual(Array(Set(audio.map(\.source))).sorted(),
                               try XCTUnwrap(plan["sources"] as? [String]), place)
                XCTAssertEqual(AudioMix.audible(audio), try XCTUnwrap(plan["audible"] as? Bool), place)
                if voice && clipSound { XCTAssertEqual(audio, film, place) }
                // Whatever is left is laid exactly as the film lays it.
                XCTAssertTrue(audio.allSatisfy { film.contains($0) }, place)
            }
        }
    }

    func testAVoiceOverIsATrackNamedAsARecordingIs() {
        XCTAssertTrue(AudioMix.isVoiceOver(AudioTrack(src: "audio:a", name: "Voice-over")))
        XCTAssertTrue(AudioMix.isVoiceOver(AudioTrack(src: "audio:a", name: "Voice-over 3")))
        XCTAssertTrue(AudioMix.isVoiceOver(AudioTrack(src: "audio:a", name: "Voz en off 2")))
        XCTAssertTrue(AudioMix.isVoiceOver(AudioTrack(src: "audio:a", name: "ナレーション")))
        XCTAssertTrue(AudioMix.isVoiceOver(AudioTrack(src: "audio:a", name: AudioTracks.voiceOverName(after: []))))
        XCTAssertFalse(AudioMix.isVoiceOver(AudioTrack(src: "audio:a", name: "Theme")))
        XCTAssertFalse(AudioMix.isVoiceOver(AudioTrack(src: "video:c", name: AudioTracks.clipSoundName)))
        // One rule with the captions check (AudioTracks.isVoiceOverName): a
        // name Record gives, a number at most after it — a track renamed
        // "Voice-over take" is music to both.
        XCTAssertFalse(AudioMix.isVoiceOver(AudioTrack(src: "audio:a", name: "Voice-over take")))
        XCTAssertFalse(AudioTracks.isVoiceOverName("Voice-over take"))
        for name in ["Voice-over", "Voice-over 12", "Voix off", "ナレーション 2", "Theme", "Voice-overs"] {
            XCTAssertEqual(AudioTracks.isVoiceOverName(name), AudioMix.isVoiceOver(AudioTrack(src: "audio:a", name: name)), name)
        }
    }

    @MainActor
    func testM4AIsAFormatTheSettingsKeepWithBothSwitchesOnUnlessTurnedOff() throws {
        XCTAssertTrue(ExportLast.formats.contains("m4a"))
        XCTAssertEqual(ExportLast.fileTypes.last, "m4a")
        let off = ExportLast(format: "m4a", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                             pages: "all", audioVoice: false)
        XCTAssertEqual(ExportLast.read(off.json), off)
        XCTAssertTrue(off.json.hasSuffix(#""audioVoice":false,"audioClips":true,"split":true}"#))
        let older = try XCTUnwrap(ExportLast.read(#"{"format":"m4a"}"#))
        XCTAssertTrue(older.audioVoice && older.audioClips && older.split)
        XCTAssertEqual(older.format, "m4a")
        XCTAssertEqual(ExportSheet.formatName("m4a"), "Audio (M4A)")
        XCTAssertEqual(ExportSheet.shareLabel("m4a", count: 1), "Share audio")
    }

    /// Sound over pages that never change is the sound: the audio alone;
    /// one still page under a song is still a video to post.
    func testSoundOverPagesThatNeverChangeSuggestsTheAudio() {
        var design = Design(title: "Podcast", width: 1920, height: 1080)
        var first = Element.text("Ep 1")
        first.id = "x"
        var second = first
        second.id = "y"
        design.pages = [Page(id: "a", elements: [first]), Page(id: "b", elements: [second])]
        design.audioTracks = [AudioTrack(src: "audio:song-1")]
        XCTAssertEqual(ExportSuggestion.suggest(design), "m4a")
        var one = design
        one.pages = [design.pages[0]]
        XCTAssertEqual(ExportSuggestion.suggest(one), "mp4")
        var blank = design
        blank.pages = [Page(id: "a"), Page(id: "b")]
        XCTAssertEqual(ExportSuggestion.suggest(blank), "mp4", "blank pages are a deck not yet made")
        var changing = design
        changing.pages[1].elements[0].text = "Ep 2"
        XCTAssertEqual(ExportSuggestion.suggest(changing), "mp4")
    }

    // MARK: keeping going out of the app

    /// What the stand-in for iOS 26's task heard.
    @MainActor
    private final class Heard {
        var asked: [(job: UUID, title: String, subtitle: String)] = []
        var reports: [(Int64, Int64)] = []
        var finished: [Bool] = []
        var expire: (() -> Void)?
        var notes: [String] = []
    }

    @MainActor
    private func host(_ heard: Heard, grants: Bool) -> ExportQueue.Host {
        var host = ExportQueue.Host.none
        host.beginContinued = { job, title, subtitle in
            heard.asked.append((job, title, subtitle))
            return grants
        }
        host.notify = { _, _, body, _ in heard.notes.append(body) }
        return host
    }

    @MainActor
    private func handle(_ heard: Heard) -> ContinuedExport.Handle {
        ContinuedExport.Handle(report: { done, total in heard.reports.append((done, total)) },
                               finish: { heard.finished.append($0) },
                               onExpiry: { heard.expire = $0 })
    }

    /// Below iOS 26, and in a test, nothing is asked: the queue's own
    /// background task is all there is.
    @MainActor
    func testNoHostAsksForNothingAndThePillSaysSo() async {
        let queue = ExportQueue(host: .none)
        queue.enqueue(ExportQueue.Job(label: "Rendering the video", designId: "d") { _ in ExportQueue.Result() })
        await queue.waitUntilIdle()
        XCTAssertNil(queue.continuedTask)
        XCTAssertFalse(queue.keepsGoing)
        XCTAssertEqual(ExportChoices.keepsGoing(false), "Keep Canvia open to finish")
        XCTAssertEqual(ExportChoices.keepsGoing(true), "Keeps going if you leave Canvia")
        XCTAssertEqual(ContinuedExport.job(of: ContinuedExport.identifier(job: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)),
                       UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        XCTAssertNil(ContinuedExport.job(of: "com.canvia.backup"))
    }

    /// Asked for as it starts, under "Exporting <title>" and what it makes;
    /// once the system starts the task, how far along is reported to it in
    /// the job's frames, and it ends as the export does.
    @MainActor
    func testAnExportReportsToItsTaskAndEndsIt() async throws {
        let heard = Heard()
        let queue = ExportQueue(host: host(heard, grants: true))
        var opened = false
        let job = ExportQueue.Job(label: "Rendering the video", designId: "d", title: "Lisbon", detail: "MP4 · 3 pages",
                                  units: 300, work: { report in
            report(0.5)
            while !opened { try await Task.sleep(nanoseconds: 5_000_000) }
            return ExportQueue.Result(urls: [URL(fileURLWithPath: "/tmp/lisbon.mp4")])
        })
        queue.enqueue(job)
        while queue.progress == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(heard.asked.map { $0.title }, ["Exporting Lisbon"])
        XCTAssertEqual(heard.asked.map { $0.subtitle }, ["MP4 · 3 pages"])
        XCTAssertEqual(heard.asked.first?.job, job.id)
        XCTAssertTrue(queue.keepsGoing, "granted, the pill says it keeps going")
        queue.left()
        XCTAssertEqual(heard.asked.count, 1, "asked once")
        queue.continued(handle(heard), job: job.id)
        XCTAssertEqual(heard.reports.last?.0, 150)
        XCTAssertEqual(heard.reports.last?.1, 300)
        opened = true
        await queue.waitUntilIdle()
        XCTAssertEqual(heard.finished, [true])
        XCTAssertNil(queue.continuedTask)
    }

    /// Stopped by the system, the export is cancelled cleanly and says to
    /// open Canvia to finish; a task for an export already over ends at
    /// once.
    @MainActor
    func testATaskTheSystemStopsCancelsTheExportAndSaysSo() async throws {
        let heard = Heard()
        let queue = ExportQueue(host: host(heard, grants: true))
        let job = ExportQueue.Job(label: "Rendering the video", designId: "d", work: { report in
            report(0.1)
            while true { try await Task.sleep(nanoseconds: 5_000_000) }
        })
        queue.enqueue(job)
        while queue.progress == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        queue.continued(handle(heard), job: job.id)
        XCTAssertEqual(heard.reports.last?.1, 100, "a job that does not say counts in hundredths")
        queue.continuedExpired(job.id)
        await queue.waitUntilIdle()
        XCTAssertEqual(heard.finished, [false])
        XCTAssertEqual(heard.notes, ["Export stopped — open Canvia to finish"])
        XCTAssertTrue(queue.finished.isEmpty, "a stopped export hands nothing on")
        queue.continued(handle(heard), job: job.id)
        XCTAssertEqual(heard.finished, [false, false])
    }

    /// Each design of a batch (Home's Select ▸ Share) has its own task,
    /// ended as succeeded once its part is made — though the files are
    /// handed over together only after the last.
    @MainActor
    func testEachPartOfABatchEndsItsTaskAsSucceeded() async throws {
        let heard = Heard()
        let queue = ExportQueue(host: host(heard, grants: true))
        let batch = UUID()
        var released = 0
        let jobs = (0..<2).map { index in
            ExportQueue.Job(label: HomeExports.label(index: index, total: 2), designId: "d\(index)",
                            batch: ExportQueue.Batch(id: batch, index: index, total: 2)) { report in
                report(0.5)
                while released <= index { try await Task.sleep(nanoseconds: 5_000_000) }
                return ExportQueue.Result(urls: [URL(fileURLWithPath: "/tmp/d\(index).pdf")])
            }
        }
        for job in jobs { queue.enqueue(job) }
        for (index, job) in jobs.enumerated() {
            while queue.current?.id != job.id || queue.progress == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
            queue.continued(handle(heard), job: job.id)
            released = index + 1
        }
        await queue.waitUntilIdle()
        XCTAssertEqual(heard.finished, [true, true])
        XCTAssertEqual(queue.finished.map(\.id), [batch], "handed over together")
    }
}
