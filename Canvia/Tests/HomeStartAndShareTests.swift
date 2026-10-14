// Start, share and preview from Home: Import's rows, the photo start on a
// shelf of samples, several designs shared at once on the export queue, and
// "Start with my brand".

import XCTest
@testable import Canvia

@MainActor
final class HomeStartAndShareTests: XCTestCase {

    // MARK: import

    /// The rows both phones show, in order, under one heading.
    func testImportOffersFourRowsInOrder() {
        XCTAssertEqual(ImportChoice.groupTitle, "Import")
        XCTAssertEqual(ImportChoice.allCases.map(\.title),
                       ["Photo or video…", "PDF…", "PowerPoint…", "Canvia design file…"])
    }

    /// A shelf of only the two samples — or nothing — offers "Start from a
    /// photo"; one design of your own and it goes.
    func testThePhotoStartShowsWhileOnlyTheSamplesAreThere() {
        let templates = Array(ContentLibrary.templates.prefix(2))
        func recent(_ title: String) -> RecentDesign {
            RecentDesign(id: UID.make("doc"), title: title, width: 100, height: 100, pages: 1, updatedAt: 0)
        }
        let samples = templates.map { recent(tr("Sample: %@", $0.name)) }
        XCTAssertTrue(DesignLibrary.onlySamples([], templates: templates))
        XCTAssertTrue(DesignLibrary.onlySamples(samples, templates: templates))
        XCTAssertTrue(DesignLibrary.onlySamples([samples[0]], templates: templates))
        XCTAssertFalse(DesignLibrary.onlySamples(samples + [recent("Poster")], templates: templates))
    }

    // MARK: sharing several designs

    /// "Exporting 2 of 5 designs 40%": the second of five, done.
    func testThePillCountsTheDesignsAndTheWhole() {
        XCTAssertEqual(HomeExports.label(index: 1, total: 5), "Exporting 2 of 5 designs")
        XCTAssertEqual(HomeExports.label(index: 0, total: 1), "Exporting")
        XCTAssertEqual(HomeExports.overall(1, index: 1, total: 5), 0.4, accuracy: 1e-9)
        XCTAssertEqual(HomeExports.overall(0, index: 0, total: 5), 0, accuracy: 1e-9)
        XCTAssertEqual(HomeExports.overall(0.5, index: 2, total: 4), 0.625, accuracy: 1e-9)
        XCTAssertEqual(HomeExports.overall(7, index: 4, total: 5), 1, accuracy: 1e-9)
        XCTAssertEqual(ExportChoices.pillText(label: HomeExports.label(index: 1, total: 5),
                                              fraction: HomeExports.overall(1, index: 1, total: 5)),
                       "Exporting 2 of 5 designs 40%")
    }

    func testWhatCouldNotBeExportedIsSaid() {
        XCTAssertEqual(HomeExports.failureText(failed: 1, total: 5), "Couldn't export 1 of 5")
        XCTAssertNil(HomeExports.failureText(failed: 0, total: 5))
    }

    /// The last export's settings, or the sheet's own defaults.
    func testTheLastExportsSettingsAreUsed() {
        let fresh = HomeExports.settings("")
        XCTAssertEqual(fresh.scale, 2)
        XCTAssertNil(fresh.longEdge)
        XCTAssertFalse(fresh.transparent)
        XCTAssertFalse(fresh.pdfNotes)
        let kept = HomeExports.settings(#"{"format":"pdf","scale":3.0,"longEdge":1080,"jpegQuality":0.8,"transparent":true,"pages":"all","pdfNotes":true,"pdfCompress":true}"#)
        XCTAssertEqual(kept.scale, 3)
        XCTAssertEqual(kept.longEdge, 1080)
        XCTAssertTrue(kept.transparent)
        XCTAssertTrue(kept.pdfNotes)
        XCTAssertTrue(kept.pdfCompress)
    }

    private func part(_ name: String, of batch: UUID, _ index: Int, _ total: Int, fails: Bool = false) -> ExportQueue.Job {
        ExportQueue.Job(label: HomeExports.label(index: index, total: total), designId: name,
                        batch: ExportQueue.Batch(id: batch, index: index, total: total)) { report in
            try await Task.sleep(nanoseconds: 5_000_000)
            if fails { throw DesignExporter.ExportError.renderFailed }
            report(1)
            return ExportQueue.Result(urls: [URL(fileURLWithPath: "/tmp/\(name).pdf")])
        }
    }

    /// One job a design, in turn; every file handed over once, after the
    /// last, with the one that failed said beside them.
    func testABatchIsHandedOverOnceWithWhatFailedSaid() async {
        let queue = ExportQueue(host: .none)
        let batch = UUID()
        queue.enqueue(part("a", of: batch, 0, 3))
        queue.enqueue(part("b", of: batch, 1, 3, fails: true))
        queue.enqueue(part("c", of: batch, 2, 3))
        XCTAssertEqual(queue.waiting.map(\.label), ["Exporting 1 of 3 designs", "Exporting 2 of 3 designs",
                                                    "Exporting 3 of 3 designs"])
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.finished.count, 1)
        let done = queue.takeFinished()
        XCTAssertEqual(done?.id, batch)
        XCTAssertEqual(done?.result.urls.map(\.lastPathComponent), ["a.pdf", "c.pdf"])
        XCTAssertEqual(done?.result.skipped, "Couldn't export 1 of 3")
        XCTAssertNil(done?.result.failed)
    }

    /// None made: only said.
    func testABatchWithNothingMadeIsOnlySaid() async {
        let queue = ExportQueue(host: .none)
        let batch = UUID()
        queue.enqueue(part("a", of: batch, 0, 2, fails: true))
        queue.enqueue(part("b", of: batch, 1, 2, fails: true))
        await queue.waitUntilIdle()
        let done = queue.takeFinished()
        XCTAssertEqual(done?.result.failed, "Couldn't export 2 of 2")
        XCTAssertEqual(done?.result.isOnlySaid, true)
    }

    /// A part taken out of the line is left out, not counted as failed;
    /// the rest are still handed over together.
    func testAPartTakenOutIsLeftOut() async {
        let queue = ExportQueue(host: .none)
        let batch = UUID()
        let first = part("a", of: batch, 0, 3)
        let second = part("b", of: batch, 1, 3)
        queue.enqueue(first)
        queue.enqueue(second)
        queue.enqueue(part("c", of: batch, 2, 3))
        queue.cancel(second.id)
        await queue.waitUntilIdle()
        let done = queue.takeFinished()
        XCTAssertEqual(done?.result.urls.map(\.lastPathComponent), ["a.pdf", "c.pdf"])
        XCTAssertNil(done?.result.skipped)
        XCTAssertNil(queue.takeFinished())
    }

    /// A design that no longer reads is passed over and said.
    func testADesignThatDoesNotReadIsSkipped() async {
        let queue = ExportQueue(host: .none)
        HomeExports.enqueue(["no-such-design-\(UUID().uuidString)"], as: .png,
                            settings: HomeExports.settings(""), queue: queue)
        await queue.waitUntilIdle()
        XCTAssertEqual(queue.takeFinished()?.result.failed, "Couldn't export 1 of 1")
    }

    // MARK: start with my brand

    private func brandedKit() -> BrandKit {
        var kit = BrandKit()
        kit.palettes = [BrandPalette(name: "Colours", colors: ["#0a2540", "#f6c90e"])]
        kit.fonts.title = BrandFont(family: "didone", weight: 700)
        kit.fonts.body = BrandFont(family: "serif", weight: 400)
        return kit
    }

    private func plainDesign() -> Design {
        var design = Design(title: "Poster", width: 1080, height: 1080)
        var title = Element.text("Big news", fontSize: 96, w: 800)
        title.color = "#111111"
        var body = Element.text("Details below", fontSize: 24, w: 800)
        body.color = "#666666"
        design.pages[0].elements = [title, body]
        return design
    }

    func testOnlyAKitWithALookIsOffered() {
        XCTAssertFalse(BrandKit().canStartWith)
        var kit = BrandKit()
        kit.palettes = [BrandPalette(name: "Colours", colors: ["#0a2540"])]
        XCTAssertFalse(kit.canStartWith, "one colour is no palette to map onto")
        XCTAssertTrue(brandedKit().canStartWith)
        var faces = BrandKit()
        faces.fonts.heading = BrandFont(family: "serif", weight: 700)
        XCTAssertTrue(faces.canStartWith)
    }

    /// Document theme's own step: the first palette by lightness, the
    /// roles by size rank.
    func testTheBrandIsDocumentThemesStep() {
        let design = plainDesign()
        let kit = brandedKit()
        let branded = DesignStore.branded(design, kit: kit)
        XCTAssertEqual(branded, DesignStore.themed(design, palette: ["#0a2540", "#f6c90e"], pairing: nil,
                                                   brandFonts: kit.fonts))
        XCTAssertNotEqual(branded, design)
        XCTAssertEqual(branded.pages[0].elements[0].fontWeight, 700)
        XCTAssertEqual(DesignStore.branded(design, kit: BrandKit()), design)
    }

    /// One step, which Undo takes back, and said.
    func testTheBrandIsTheFirstStepAndUndoTakesItBack() {
        let design = plainDesign()
        let store = DesignStore(design: design)
        store.applyBrandKit(brandedKit())
        XCTAssertNotEqual(store.design.pages, design.pages)
        XCTAssertEqual(store.announcement, "Brand kit applied")
        XCTAssertTrue(store.canUndo)
        store.undo()
        XCTAssertEqual(store.design.pages, design.pages)
    }

    func testTheBrandIsAskedForOnce() {
        BrandStart.designId = "doc-1"
        XCTAssertFalse(BrandStart.take("doc-2"))
        XCTAssertTrue(BrandStart.take("doc-1"))
        XCTAssertFalse(BrandStart.take("doc-1"))
        XCTAssertNil(BrandStart.designId)
    }
}
