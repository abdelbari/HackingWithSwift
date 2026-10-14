// Exports in the background: one at a time in the order asked, each from a
// snapshot of the design taken as it was asked for, so editing on changes
// nothing it writes.

import XCTest
import CoreGraphics
import UserNotifications
@testable import Canvia

@MainActor
final class ExportQueueTests: XCTestCase {

    /// What the jobs did, in order.
    @MainActor
    private final class Recorder {
        var events: [String] = []
        var running = 0
        var most = 0
    }

    /// Holds a job until opened.
    @MainActor
    private final class Gate {
        var isOpen = false
        func wait() async throws {
            while !isOpen { try await Task.sleep(nanoseconds: 5_000_000) }
        }
    }

    private func job(_ name: String, _ recorder: Recorder, gate: Gate? = nil) -> ExportQueue.Job {
        ExportQueue.Job(label: name, designId: "d") { report in
            recorder.running += 1
            recorder.most = max(recorder.most, recorder.running)
            recorder.events.append("start \(name)")
            defer { recorder.running -= 1 }
            if let gate { try await gate.wait() }
            try await Task.sleep(nanoseconds: 10_000_000)
            report(1)
            recorder.events.append("end \(name)")
            return ExportQueue.Result(urls: [URL(fileURLWithPath: "/tmp/\(name)")])
        }
    }

    private func design(pages: Int) -> Design {
        var d = Design(title: "snapshot", width: 200, height: 120)
        d.pages = (0..<pages).map { _ in Page(elements: [Element.shape("rect", w: 100, h: 60)]) }
        return d
    }

    // MARK: order

    func testExportsRunOneAtATimeInTheOrderAsked() async {
        let queue = ExportQueue(host: .none)
        let recorder = Recorder()
        queue.enqueue(job("a", recorder))
        queue.enqueue(job("b", recorder))
        queue.enqueue(job("c", recorder))
        XCTAssertEqual(queue.waiting.map(\.label), ["a", "b", "c"])
        XCTAssertTrue(queue.isBusy)
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.events, ["start a", "end a", "start b", "end b", "start c", "end c"])
        XCTAssertEqual(recorder.most, 1, "two ran at once")
        XCTAssertFalse(queue.isBusy)
        XCTAssertNil(queue.current)
        // Each one done is kept until taken, oldest first: one finishing
        // while the app is away does not replace the one before.
        XCTAssertEqual(queue.finished.map(\.label), ["a", "b", "c"])
        XCTAssertEqual(queue.takeFinished()?.label, "a")
        XCTAssertEqual(queue.takeFinished()?.label, "b")
        XCTAssertEqual(queue.takeFinished()?.label, "c")
        XCTAssertNil(queue.takeFinished())
        XCTAssertTrue(queue.finished.isEmpty)
    }

    /// The rows the Android twin's ExportsReadyTest checks: oldest first;
    /// a notification tapped takes its own export, the rest left in order;
    /// a tap for one delivered already is let go, the oldest delivered as
    /// it would have been.
    func testATappedNotificationTakesItsOwnExport() async {
        let queue = ExportQueue(host: .none)
        let recorder = Recorder()
        let jobs = ["a", "b", "c"].map { job($0, recorder) }
        for j in jobs { queue.enqueue(j) }
        await queue.waitUntilIdle()

        queue.requested = .open
        queue.requestedJob = jobs[1].id
        let tapped = queue.takeRequested()
        XCTAssertEqual(tapped?.finished.label, "b")
        XCTAssertEqual(tapped?.request, .open)
        XCTAssertNil(queue.requested)
        XCTAssertNil(queue.requestedJob)

        queue.requested = .share
        queue.requestedJob = jobs[1].id
        let stale = queue.takeRequested()
        XCTAssertEqual(stale?.finished.label, "a")
        XCTAssertNil(stale?.request, "a tap for one gone already")
        XCTAssertNil(queue.requested)

        XCTAssertEqual(queue.takeRequested()?.finished.label, "c")
        queue.requested = .open
        queue.requestedJob = jobs[0].id
        XCTAssertNil(queue.takeRequested())
        XCTAssertNil(queue.requested, "a tap with nothing waiting is used up")
    }

    /// The row the Android twin's ExportsReadyTest checks: a tap on b's
    /// notification itself, with a waiting, leaves them in turn — a first;
    /// its Share or Open takes b first, as asked.
    func testATapOnTheNotificationItselfLeavesThemInTurn() async {
        let queue = ExportQueue(host: .none)
        let recorder = Recorder()
        let jobs = ["a", "b", "c"].map { job($0, recorder) }
        for j in jobs { queue.enqueue(j) }
        await queue.waitUntilIdle()

        XCTAssertNil(ExportNotifications.request(for: UNNotificationDefaultActionIdentifier))
        XCTAssertEqual(ExportNotifications.request(for: ExportNotifications.shareAction), .share)
        XCTAssertEqual(ExportNotifications.request(for: ExportNotifications.openAction), .open)

        queue.tapped(nil, job: jobs[1].id)
        XCTAssertNil(queue.requested)
        XCTAssertNil(queue.requestedJob)
        XCTAssertEqual(queue.takeRequested()?.finished.label, "a")

        queue.tapped(.open, job: jobs[2].id)
        let opened = queue.takeRequested()
        XCTAssertEqual(opened?.finished.label, "c")
        XCTAssertEqual(opened?.request, .open)
        XCTAssertEqual(queue.takeRequested()?.finished.label, "b")
    }

    /// One asked for while another runs waits its turn; taken out of the
    /// line, it never runs; the one running, stopped, finishes nothing.
    func testAWaitingExportCanBeTakenOutAndTheRunningOneStopped() async throws {
        let queue = ExportQueue(host: .none)
        let recorder = Recorder()
        let gate = Gate()
        let first = job("first", recorder, gate: gate)
        let second = job("second", recorder)
        let third = job("third", recorder)
        queue.enqueue(first)
        queue.enqueue(second)
        queue.enqueue(third)
        while recorder.events.isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(queue.current?.label, "first")
        XCTAssertEqual(queue.waiting.map(\.label), ["second", "third"])
        queue.cancel(second.id)
        XCTAssertEqual(queue.waiting.map(\.label), ["third"])
        queue.cancelCurrent()
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.events, ["start first", "start third", "end third"])
        XCTAssertEqual(queue.finished.map(\.label), ["third"])
        XCTAssertNil(queue.finished.first?.result.failed)
    }

    /// Stop stops them all: the one running, and none waiting starts after.
    func testStoppingAllLeavesNoneWaiting() async throws {
        let queue = ExportQueue(host: .none)
        let recorder = Recorder()
        let gate = Gate()
        queue.enqueue(job("pdf", recorder, gate: gate))
        queue.enqueue(job("video", recorder))
        while recorder.events.isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
        queue.cancelAll()
        XCTAssertTrue(queue.waiting.isEmpty)
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.events, ["start pdf"])
        XCTAssertTrue(queue.finished.isEmpty)
        XCTAssertFalse(queue.isBusy)
    }

    func testAFailureIsSaidInTheTwinsWords() async {
        struct Broken: LocalizedError { var errorDescription: String? { "the disk is full" } }
        let queue = ExportQueue(host: .none)
        queue.enqueue(ExportQueue.Job(label: "Making the PDF", designId: "d") { _ in throw Broken() })
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.finished.map(\.result.failed), ["Export failed: the disk is full"])
        XCTAssertTrue(queue.finished.first?.result.isOnlySaid ?? false)
    }

    /// The row the Android twin's ExportsReadyTest checks: two failing
    /// jobs leave two messages, oldest first — the second does not replace
    /// the first.
    func testTwoFailuresLeaveTwoMessagesOldestFirst() async {
        struct Broken: LocalizedError {
            let why: String
            var errorDescription: String? { why }
        }
        let queue = ExportQueue(host: .none)
        queue.enqueue(ExportQueue.Job(label: "Making the PDF", designId: "d") { _ in throw Broken(why: "the disk is full") })
        queue.enqueue(ExportQueue.Job(label: "Rendering the video", designId: "d") { _ in throw Broken(why: "no room") })
        await queue.waitUntilIdle()
        XCTAssertTrue(queue.nextIsOnlySaid)
        XCTAssertEqual(queue.takeRequested()?.finished.result.failed, "Export failed: the disk is full")
        XCTAssertEqual(queue.takeRequested()?.finished.result.failed, "Export failed: no room")
        XCTAssertNil(queue.takeRequested())
        XCTAssertFalse(queue.nextIsOnlySaid)
    }

    /// Reported progress lands on the job running, from any thread.
    func testProgressIsReportedForTheJobRunning() async throws {
        let queue = ExportQueue(host: .none)
        let gate = Gate()
        queue.enqueue(ExportQueue.Job(label: "Rendering the video", designId: "d") { report in
            report(0.42)
            try await gate.wait()
            return ExportQueue.Result()
        })
        while queue.progress == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(queue.pillText, "Rendering the video 42%")
        gate.isOpen = true
        await queue.waitUntilIdle()
        XCTAssertNil(queue.pillText)
    }

    // MARK: snapshots

    /// The PDF asked for while another export runs is written from the
    /// design as it was asked for: a page added, a page hidden and the
    /// title changed afterwards change nothing in it.
    func testAnEditAfterTheStartDoesNotChangeTheOutput() async throws {
        let store = DesignStore(design: design(pages: 2))
        let queue = ExportQueue(host: .none)
        let gate = Gate()
        queue.enqueue(job("ahead", Recorder(), gate: gate))
        let snapshot = ExportSnapshot(store.design, range: .all, current: 0)
        queue.enqueue(ExportQueue.Job(label: "Making the PDF", designId: store.design.id,
                                      work: ExportJobs.pdf(snapshot, flatten: false)))

        store.addPage()
        store.apply {
            $0.pages[1].hidden = true
            $0.title = "renamed"
        }
        gate.isOpen = true
        await queue.waitUntilIdle()

        let url = try XCTUnwrap(queue.finished.last?.result.urls.first)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "snapshot.pdf")
        XCTAssertEqual(CGPDFDocument(url as CFURL)?.numberOfPages, 2)
        XCTAssertEqual(store.design.pages.count, 3)
    }

    /// The pages are fixed as the export starts — hidden ones left out of
    /// All pages — and the range given the exporters is exactly those.
    func testTheSnapshotFixesThePageList() {
        var d = design(pages: 3)
        d.pages[1].hidden = true
        let all = ExportSnapshot(d, range: .all, current: 0)
        XCTAssertEqual(all.pages, [0, 2])
        XCTAssertEqual(all.range.indices(in: all.design, current: 0), [0, 2])
        let current = ExportSnapshot(d, range: .current, current: 1)
        XCTAssertEqual(current.pages, [1])
        XCTAssertEqual(current.range.indices(in: current.design, current: 0), [1], "the hidden page asked for")
    }

    // MARK: words

    func testTheWordsBothPhonesUse() {
        XCTAssertEqual(ExportChoices.pillText(label: "Rendering the video", fraction: 0.424), "Rendering the video 42%")
        XCTAssertEqual(ExportChoices.pillText(label: "Making the PDF", fraction: 1.2), "Making the PDF 100%")
        XCTAssertEqual(ExportChoices.keepQuestion, "Keep exporting in the background?")
        XCTAssertEqual([ExportChoices.keep, ExportChoices.stop], ["Keep", "Stop"])
        XCTAssertEqual(ExportChoices.paused, "Paused — return to Canvia to finish")
        XCTAssertEqual([ExportChoices.shareAction, ExportChoices.openAction], ["Share", "Open"])
        XCTAssertEqual(ExportChoices.failedText("no room"), "Export failed: no room")
    }
}
