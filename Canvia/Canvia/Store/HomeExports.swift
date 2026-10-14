// Sharing from Home, without opening the editor: a design's card has
// Share…, Send a copy, Present and Print…, and Select's bar shares several
// at once — PNG, a file a page; PDF, a file a design; or the design files —
// as one job each on the app's ExportQueue, in turn, their files handed to
// one share sheet once the last is done. Each design is read from its file
// off the main thread as its turn comes; one that no longer reads is passed
// over and said ("Couldn't export 1 of 5"). The last export's settings
// (exportLast) are used; nothing is written into a design. The Android
// twin's Home export, word for word.

import Foundation

enum HomeExports {

    /// What several designs can be shared as.
    enum Format: String, CaseIterable, Identifiable {
        case png, pdf, designFiles

        var id: String { rawValue }
    }

    /// The pill's words for part `index` (zero-based) of `total`: "Exporting
    /// 2 of 5 designs"; for one design alone, "Exporting".
    static func label(index: Int, total: Int) -> String {
        total <= 1 ? tr("Exporting") : tr("Exporting %d of %d designs", index + 1, total)
    }

    /// How far along the whole batch is, with part `index` at `fraction`:
    /// the parts done, and this one's share — so the pill's number only
    /// ever climbs, and reads 40% as the second of five ends.
    static func overall(_ fraction: Double, index: Int, total: Int) -> Double {
        let done = Double(min(max(index, 0), max(total, 1))) + min(1, max(0, fraction))
        return min(1, done / Double(max(total, 1)))
    }

    /// "Couldn't export 1 of 5", or nil when every one was.
    static func failureText(failed: Int, total: Int) -> String? {
        failed > 0 ? tr("Couldn't export %d of %d", failed, total) : nil
    }

    /// The last export's settings, as Export left them — or the sheet's
    /// own defaults when it has not kept any: 2×, no long edge, opaque.
    static func settings(_ stored: String) -> ExportLast {
        ExportLast.read(stored) ?? ExportLast(format: "png", scale: 2, longEdge: nil, jpegQuality: 0.92,
                                              transparent: false, pages: "all")
    }

    /// A design read from its file away from the main thread; one that no
    /// longer reads fails its part.
    static func load(_ id: String) async throws -> Design {
        let design = await Task.detached(priority: .userInitiated) { DesignLibrary.load(id: id) }.value
        guard let design else { throw DesignExporter.ExportError.renderFailed }
        return design
    }

    /// Every page not hidden, from the first.
    static func snapshot(_ design: Design) -> ExportSnapshot {
        ExportSnapshot(design, range: .all, current: 0)
    }

    /// A part's files moved into a folder of their own, numbered by its
    /// place in the batch, under their own names: two designs of one title
    /// would otherwise write the same file, the second over the first. One
    /// that will not move is handed over where it is.
    static func setApart(_ urls: [URL], batch: UUID, index: Int) -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("batch-\(batch.uuidString)", isDirectory: true)
            .appendingPathComponent("\(index + 1)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return urls.map { url in
            let target = folder.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            return (try? FileManager.default.moveItem(at: url, to: target)) != nil ? target : url
        }
    }

    /// Part `index` of `total`: the design read when its turn comes, then
    /// made as `format`, reporting the whole batch's progress.
    @MainActor
    static func designWork(id: String, format: Format, settings: ExportLast, batch: UUID,
                           index: Int, total: Int) -> ExportQueue.Work {
        { report in
            let part: @Sendable (Double) -> Void = { fraction in
                report(overall(fraction, index: index, total: total))
            }
            let design = try await load(id)
            let made = Self.snapshot(design)
            let render: ExportQueue.Work
            switch format {
            case .png:
                render = ExportJobs.pictures(made, format: .png, scale: settings.scale,
                                             longEdge: Double(settings.longEdge ?? 0), quality: settings.jpegQuality,
                                             transparent: settings.transparent)
            case .pdf:
                render = ExportJobs.pdf(made, flatten: false, notes: settings.pdfNotes, compress: settings.pdfCompress)
            case .designFiles:
                render = ExportJobs.designFile(made.design)
            }
            var result = try await render(part)
            result.urls = setApart(result.urls, batch: batch, index: index)
            return result
        }
    }

    /// The designs picked, one job each on `queue`, in the order given.
    @MainActor
    static func enqueue(_ ids: [String], as format: Format, settings: ExportLast, queue: ExportQueue) {
        let batch = UUID()
        for (index, id) in ids.enumerated() {
            queue.enqueue(ExportQueue.Job(
                label: label(index: index, total: ids.count), designId: id,
                batch: ExportQueue.Batch(id: batch, index: index, total: ids.count),
                work: designWork(id: id, format: format, settings: settings, batch: batch,
                                 index: index, total: ids.count)))
        }
    }

    // MARK: one design, from its card

    /// Send a copy: the design file of the design as saved, at once — the
    /// share sheet comes up when it is packed.
    @MainActor
    static func sendCopy(_ id: String, queue: ExportQueue) {
        queue.enqueue(ExportQueue.Job(label: tr("Packing the design file"), designId: id, work: { report in
            let design = try await load(id)
            return try await ExportJobs.designFile(design)(report)
        }))
    }

    /// Print…: every page shown, fitted to the paper, its bleed kept, to
    /// the print dialog.
    @MainActor
    static func printDesign(_ id: String, queue: ExportQueue) {
        queue.enqueue(ExportQueue.Job(label: tr("Preparing to print"), designId: id, work: { report in
            let design = try await load(id)
            var options = PrintLayout.Options()
            options.bleed = Bleed.printPoints(design)
            return try await ExportJobs.printPDF(Self.snapshot(design), options: options, flatten: false, printing: true)(report)
        }))
    }
}
