// Export sheet: the chooser. PNG / JPEG at 1-3x and multi-page PDF, all
// rendered from the same PageRenderView the canvas uses and handed to the
// system share sheet. The rendering and encoding themselves live in
// DesignExporter.

import SwiftUI
import UIKit

struct ExportSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var scale = 2
    @State private var jpegQuality = 0.92
    @State private var transparent = false
    @State private var pageRange = RangeChoice.current
    @State private var sharedURLs: [URL] = []
    @State private var savedToPhotos: String?

    private enum RangeChoice: String, CaseIterable, Identifiable {
        case current, all
        var id: String { rawValue }
        var label: String { self == .current ? "This page" : "All pages" }
        var exportRange: DesignExporter.PageRange { self == .current ? .current : .all }
    }
    @State private var exporting = false
    @State private var exportedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            // One computed property per section. As a single expression the
            // form was past what the type checker will resolve "in reasonable
            // time" — every string interpolation, ternary and `if` adds a
            // branch, and eight sections of them is too many.
            Form {
                qualitySection
                jpegSection
                if store.design.pages.count > 1 { pagesSection }
                transparencySection
                formatSection
                photosSection
                if UIPrintInteractionController.isPrintingAvailable { printSection }
                motionSection
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(item: Binding(
                get: { exportedURL.map(ShareURL.init) },
                set: { if $0 == nil { exportedURL = nil; sharedURLs = [] } })) { item in
                // Every file at once when a range produced several: handing
                // them over one sheet at a time would mean nine dismissals for
                // a nine-page deck.
                ShareSheet(urls: sharedURLs.isEmpty ? [item.url] : sharedURLs)
            }
            .overlay {
                if exporting { ProgressView("Rendering…") }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: sections

    private var qualitySection: some View {
        Section {
            Picker("Scale", selection: $scale) {
                Text("1×").tag(1)
                Text("2×").tag(2)
                Text("3×").tag(3)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Quality")
        } footer: {
            // "2×" means nothing on its own; the pixel count is the thing
            // people actually need to match a platform's requirements. It also
            // gives the size cap somewhere honest to appear rather than
            // silently under-delivering.
            Text(sizeNote)
        }
    }

    private var jpegSection: some View {
        let percent = Int((jpegQuality * 100).rounded())
        return Section {
            Slider(value: $jpegQuality, in: 0.3...1)
        } header: {
            Text("JPEG quality")
        } footer: {
            Text("\(percent)% — about \(estimatedSize). PNG and PDF are lossless and ignore this.")
        }
    }

    private var pagesSection: some View {
        let note = pageRange == .all
            ? "One file per page, numbered — so each can be posted on its own."
            : "Page \(store.pageIndex + 1) only."
        return Section {
            Picker("Pages", selection: $pageRange) {
                ForEach(RangeChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Pages")
        } footer: {
            Text(note)
        }
    }

    private var transparencySection: some View {
        Section {
            Toggle("Transparent background", isOn: $transparent)
        } footer: {
            Text("PNG only. Drops the page's own background rather than "
                 + "flattening it, so the export really has nothing behind it.")
        }
    }

    private var formatSection: some View {
        let pdfSubtitle = store.design.pages.count > 1
            ? "All \(store.design.pages.count) pages, vector"
            : "Print-ready document, vector"
        let jpegSubtitle = "Current page, about \(estimatedSize)"
        return Section("Format") {
            exportButton("PNG", subtitle: "Current page, best for sharing", icon: "photo") {
                try export(.png)
            }
            exportButton("JPEG", subtitle: jpegSubtitle, icon: "photo.fill") {
                try export(.jpeg)
            }
            exportButton("PDF", subtitle: pdfSubtitle, icon: "doc.richtext") {
                try exportPDF()
            }
            exportButton("SVG", subtitle: "Current page, editable vectors",
                         icon: "scribble.variable") {
                try exportSVG()
            }
        }
    }

    private var photosSection: some View {
        Section {
            exportButton("PNG to Photos", subtitle: photosSubtitle, icon: "photo.badge.plus") {
                try await saveToPhotos(.png)
            }
            exportButton("Video to Photos", subtitle: movieSubtitle, icon: "film.stack") {
                try await saveToPhotos(nil)
            }
        } header: {
            Text("Photos")
        } footer: {
            if let savedToPhotos {
                Label(savedToPhotos, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var photosSubtitle: String {
        pageRange == .current || store.design.pages.count == 1
            ? "Current page, straight into your library"
            : "Selected pages, one photo each"
    }

    /// Render, then hand the files to Photos rather than the share sheet.
    /// `nil` means the movie.
    @MainActor
    private func saveToPhotos(_ format: DesignExporter.RasterFormat?) async throws {
        savedToPhotos = nil
        let urls: [URL]
        if let format {
            urls = try DesignExporter.exportPages(
                design: store.design, range: pageRange.exportRange, current: store.pageIndex,
                format: format, scale: scale, quality: jpegQuality,
                transparent: transparent && format == .png)
        } else {
            let url = DesignExporter.fileURL(for: store.design, ext: "mp4")
            try await MovieExporter.exportMP4(design: store.design, to: url)
            urls = [url]
        }
        try await PhotoSaver.save(urls)
        savedToPhotos = urls.count == 1 ? "Saved to Photos" : "Saved \(urls.count) photos"
    }

    private var printSection: some View {
        Section("Print") {
            exportButton("Send to a printer", subtitle: "AirPrint, actual size", icon: "printer") {
                try printDesign()
            }
        }
    }

    private var motionSection: some View {
        let hold = String(format: "%.1f", MovieExporter.Settings().secondsPerPage)
        return Section {
            exportButton("MP4 video", subtitle: movieSubtitle, icon: "film") {
                try await exportMovie()
            }
            exportButton("Animated GIF", subtitle: movieSubtitle, icon: "square.stack.3d.down.right") {
                try exportGIF()
            }
        } header: {
            Text("Motion")
        } footer: {
            Text("Each page holds for \(hold)s with a slow push in and a cross-fade between pages.")
        }
    }

    private func exportButton(_ title: String, subtitle: String, icon: String,
                              action: @escaping @MainActor () async throws -> Void) -> some View {
        Button {
            exporting = true
            errorMessage = nil
            // Render on the main actor after the spinner appears. Async
            // because a video is written frame by frame and takes seconds —
            // the raster paths are synchronous and satisfy this signature
            // unchanged.
            Task { @MainActor in
                defer { exporting = false }
                do { try await action() }
                catch { errorMessage = "Export failed: \(error.localizedDescription)" }
            }
        } label: {
            HStack {
                Image(systemName: icon).frame(width: 30)
                VStack(alignment: .leading) {
                    Text(title).fontWeight(.semibold)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(exporting)
    }

    private var sizeNote: String {
        let size = DesignExporter.outputSize(design: store.design, requested: scale)
        let dims = "\(Int(size.width)) × \(Int(size.height)) px"
        guard DesignExporter.isClamped(design: store.design, requested: scale) else { return dims }
        return dims + " — reduced from \(scale)× so the render fits in memory."
    }

    private var estimatedSize: String {
        let bytes = DesignExporter.estimatedJPEGBytes(design: store.design,
                                                      requested: scale, quality: jpegQuality)
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    @MainActor
    private func export(_ format: DesignExporter.RasterFormat) throws {
        let urls = try DesignExporter.exportPages(
            design: store.design, range: pageRange.exportRange, current: store.pageIndex,
            format: format, scale: scale, quality: jpegQuality,
            // JPEG has no alpha channel to be transparent in.
            transparent: transparent && format == .png)
        sharedURLs = urls
        exportedURL = urls.first
    }

    private var movieSubtitle: String {
        let pages = store.design.pages.count
        let seconds = Double(pages) * MovieExporter.Settings().secondsPerPage
        return pages > 1
            ? "All \(pages) pages, \(String(format: "%.0f", seconds))s"
            : "One page, \(String(format: "%.0f", seconds))s"
    }

    /// Printing goes through the same vector PDF the export does, so what
    /// comes out of the printer is the document rather than a picture of it —
    /// text stays text at the printer's own resolution.
    @MainActor
    private func printDesign() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "pdf")
        try DesignExporter.exportPDF(design: store.design, to: url)

        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = store.design.title.isEmpty ? "Canvia design" : store.design.title
        info.orientation = store.design.width > store.design.height ? .landscape : .portrait

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = url
        // iPad refuses the sheet-less presentation and raises rather than
        // failing quietly, so it gets an anchor rect.
        if let anchor = Self.keyWindow, UIDevice.current.userInterfaceIdiom == .pad {
            controller.present(from: CGRect(x: anchor.bounds.midX, y: anchor.bounds.midY,
                                            width: 1, height: 1),
                               in: anchor, animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    @MainActor
    private func exportMovie() async throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "mp4")
        try await MovieExporter.exportMP4(design: store.design, to: url)
        sharedURLs = [url]
        exportedURL = url
    }

    @MainActor
    private func exportGIF() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "gif")
        try MovieExporter.exportGIF(design: store.design, to: url)
        sharedURLs = [url]
        exportedURL = url
    }

    @MainActor
    private func exportSVG() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "svg")
        try DesignExporter.exportSVG(design: store.design, page: store.page, to: url)
        sharedURLs = [url]
        exportedURL = url
    }

    @MainActor
    private func exportPDF() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "pdf")
        try DesignExporter.exportPDF(design: store.design, range: pageRange.exportRange,
                                     current: store.pageIndex, to: url)
        sharedURLs = [url]
        exportedURL = url
    }
}

private struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
