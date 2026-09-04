// Export sheet: the chooser. PNG / JPEG at 1-3x and multi-page PDF, all
// rendered from the same PageRenderView the canvas uses and handed to the
// system share sheet. The rendering and encoding themselves live in
// DesignExporter.

import SwiftUI
import UIKit

struct ExportSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var scale = 2.0
    @State private var longEdgeText = ""
    @State private var selectionOnly = false
    @State private var copied = false
    @State private var paper = PrintLayout.Options()
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
    /// Fraction done while an export runs; nil when idle. Rasters report a
    /// page at a time, the movie a frame at a time.
    @State private var progress: Double?
    @State private var exportTask: Task<Void, Never>?
    private var exporting: Bool { progress != nil }
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
                if store.design.pages.count > 1 && !selectionOnly { pagesSection }
                transparencySection
                formatSection
                clipboardSection
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
                if let progress { progressCard(progress) }
            }
        }
        .presentationDetents([.medium])
    }

    /// Determinate, with a way out. A spinner with no number is fine for a
    /// PNG; a nine-page 4K video takes long enough that not knowing whether
    /// it is a tenth done or nine tenths, and having no button to press, is
    /// the difference between waiting and force-quitting.
    private func progressCard(_ fraction: Double) -> some View {
        VStack(spacing: 14) {
            ProgressView(value: fraction) {
                Text("Rendering… \(Int((fraction * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold))
            }
            .progressViewStyle(.linear)
            Button("Cancel", role: .cancel) { exportTask?.cancel() }
                .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }

    /// Progress from the movie writer's queue, delivered to the sheet's
    /// state on the main actor.
    private func report(_ fraction: Double) {
        Task { @MainActor in progress = min(1, max(0, fraction)) }
    }

    // MARK: sections

    private var qualitySection: some View {
        Section {
            Picker("Scale", selection: $scale) {
                Text("1×").tag(1.0)
                Text("2×").tag(2.0)
                Text("3×").tag(3.0)
            }
            .pickerStyle(.segmented)
            // The size people are actually told to produce. Typing 1080
            // sets whatever scale puts the long side there.
            HStack {
                Text("Long edge")
                Spacer()
                TextField("px", text: $longEdgeText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .onSubmit(applyLongEdge)
                    .onChange(of: longEdgeText) { applyLongEdge() }
                Text("px").foregroundStyle(.secondary)
                Menu {
                    ForEach(DesignExporter.sizePresets) { preset in
                        Button(preset.name) { longEdgeText = String(Int(preset.longEdge)) }
                    }
                } label: {
                    Image(systemName: "list.bullet").accessibilityLabel("Size presets")
                }
            }
            if !store.selection.isEmpty {
                Toggle("Selection only, cropped to its bounds", isOn: $selectionOnly)
            }
        } header: {
            Text("Size")
        } footer: {
            // "2×" means nothing on its own; the pixel count is the thing
            // people actually need to match a platform's requirements. It also
            // gives the size cap somewhere honest to appear rather than
            // silently under-delivering.
            VStack(alignment: .leading, spacing: 4) {
                Text(sizeNote)
                if let warning = resolutionWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func applyLongEdge() {
        guard let px = Double(longEdgeText.trimmingCharacters(in: .whitespaces)), px >= 16 else { return }
        let next = DesignExporter.scale(forLongEdge: px, design: exportedDesign)
        if abs(next - scale) > 0.0001 { scale = next }
    }

    /// A selection export is a one-page design, so it is always "this page"
    /// of that design.
    private var exportedRange: DesignExporter.PageRange {
        selectionOnly ? .current : pageRange.exportRange
    }

    private var exportedPageIndex: Int { selectionOnly ? 0 : store.pageIndex }

    /// The design that is actually rendered: the whole page, or the selection
    /// as a page of its own.
    private var exportedDesign: Design {
        if selectionOnly,
           let cropped = DesignExporter.selectionDesign(design: store.design, page: store.page,
                                                        ids: store.selection) {
            return cropped
        }
        return store.design
    }

    /// Soft output, said before the export rather than discovered in the
    /// post: a long edge too short for a phone screen, or a photo that will
    /// be stretched past the pixels it has.
    private var resolutionWarning: String? {
        let design = exportedDesign
        let edge = DesignExporter.longEdge(design: design, requested: scale)
        if edge < DesignExporter.softBelowLongEdge {
            return "Only \(Int(edge)) px on the long side — will look soft on most screens."
        }
        let effective = DesignExporter.effectiveScale(design: design, requested: scale)
        let upscaled = DesignExporter.upscaledImages(page: design.pages[0], scale: effective,
                                                     pixelSize: { src in
            PhotoLibrary.resolve(src).map { CGSize(width: $0.size.width * $0.scale,
                                                    height: $0.size.height * $0.scale) }
        })
        guard !upscaled.isEmpty else { return nil }
        return upscaled.count == 1
            ? "One photo has fewer pixels than this size needs and will look blurry."
            : "\(upscaled.count) photos have fewer pixels than this size needs and will look blurry."
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
                design: exportedDesign, range: exportedRange, current: exportedPageIndex,
                format: format, scale: scale, quality: jpegQuality,
                transparent: transparent && format == .png,
                progress: { progress = $0 })
        } else {
            let url = DesignExporter.fileURL(for: store.design, ext: "mp4")
            try await MovieExporter.exportMP4(design: store.design, settings: MovieExporter.Settings(store.design.motion),
                                              to: url, progress: report)
            urls = [url]
        }
        try await PhotoSaver.save(urls)
        savedToPhotos = urls.count == 1 ? "Saved to Photos" : "Saved \(urls.count) photos"
    }

    private var clipboardSection: some View {
        Section {
            exportButton("Canvia design file", subtitle: "The design and its photos, to send or back up",
                         icon: "shippingbox") {
                let url = DesignExporter.fileURL(for: store.design, ext: DesignPackage.ext)
                try DesignPackage.export(store.design).write(to: url)
                sharedURLs = [url]
                exportedURL = url
            }
            exportButton(copied ? "Copied" : "Copy as image",
                         subtitle: "PNG on the clipboard, for Messages, Mail or Notes",
                         icon: copied ? "checkmark.circle" : "doc.on.clipboard") {
                try copyToClipboard()
            }
        }
    }

    @MainActor
    private func copyToClipboard() throws {
        let design = exportedDesign
        guard let cg = DesignExporter.render(design: design, page: design.pages[0],
                                             scale: scale, transparent: transparent)
        else { throw DesignExporter.ExportError.renderFailed }
        UIPasteboard.general.image = UIImage(cgImage: cg)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private var printSection: some View {
        Section {
            exportButton("Send to a printer", subtitle: "AirPrint, on the paper layout below", icon: "printer") {
                try printDesign()
            }
            exportButton("Print-ready PDF", subtitle: "Paper, bleed and crop marks as set", icon: "doc.badge.gearshape") {
                let url = DesignExporter.fileURL(for: store.design, ext: "pdf", suffix: "-print")
                try DesignExporter.exportPrintPDF(design: store.design, range: exportedRange, current: exportedPageIndex,
                                                  options: paper, to: url)
                sharedURLs = [url]
                exportedURL = url
            }
            DisclosureGroup("Paper layout") { paperSettings }
        } header: {
            Text("Print")
        } footer: {
            Text(paperNote)
        }
    }

    private var paperNote: String {
        let pts = PrintLayout.pagePoints(design: exportedDesign, bleed: paper.bleed)
        switch paper.fit {
        case .fit: return "Fitted to \(paper.paper.name)\(paper.landscape ? " landscape" : "")."
        case .actual:
            let fits = pts.width <= paper.printable.width && pts.height <= paper.printable.height
            return fits ? "Prints at actual size, \(String(format: "%.0f × %.0f mm", pts.width / 2.835, pts.height / 2.835))."
                        : "Larger than the sheet at actual size — it will be clipped. Tile it instead."
        case .tile:
            let n = PrintLayout.tiles(page: pts, printable: paper.printable.size, overlap: paper.overlap).count
            return "\(n) sheets of \(paper.paper.name), overlapping by \(Int(paper.overlap)) pt to trim and join."
        }
    }

    private var paperSettings: some View {
        Group {
            Picker("Paper", selection: $paper.paper) {
                ForEach(PrintLayout.papers) { Text($0.name).tag($0) }
            }
            Toggle("Landscape", isOn: $paper.landscape)
            Picker("Placement", selection: $paper.fit) {
                ForEach(PrintLayout.Fit.allCases) { Text($0.name).tag($0) }
            }
            Stepper(value: $paper.bleed, in: 0...36, step: 3) { Text("Bleed \(String(format: "%.0f", paper.bleed / 2.835)) mm") }
            Toggle("Crop marks", isOn: $paper.cropMarks)
        }
    }

    private var motionSection: some View {
        let hold = String(format: "%.1f", MovieExporter.Settings(store.design.motion).secondsPerPage)
        return Section {
            exportButton("MP4 video", subtitle: movieSubtitle, icon: "film") {
                try await exportMovie()
            }
            exportButton("Animated GIF", subtitle: movieSubtitle, icon: "square.stack.3d.down.right") {
                try exportGIF()
            }
            DisclosureGroup("Motion settings") { motionSettings }
        } header: {
            Text("Motion")
        } footer: {
            Text(motionNote(hold: hold))
        }
    }

    private func motionNote(hold: String) -> String {
        let m = store.design.motion ?? MotionSettings()
        var note = "Each page holds for \(hold)s"
        if m.movement { note += " with a slow push in" }
        note += m.crossfade ? " and a cross-fade between pages." : ", cutting between pages."
        return note
    }

    /// Timing, frame rate and the two moves, saved with the design.
    private var motionSettings: some View {
        let binding = Binding<MotionSettings>(
            get: { store.design.motion ?? MotionSettings() },
            set: { next in
                store.apply { $0.motion = next == MotionSettings() ? nil : next }
            })
        return Group {
            Stepper(value: binding.secondsPerPage, in: MotionSettings.secondsRange, step: 0.5) {
                Text("Hold each page \(String(format: "%.1f", binding.wrappedValue.secondsPerPage))s")
            }
            Picker("Frame rate", selection: binding.fps) {
                ForEach(MotionSettings.fpsChoices, id: \.self) { Text("\($0) fps").tag($0) }
            }
            Toggle("Slow push in", isOn: binding.movement)
            Toggle("Cross-fade between pages", isOn: binding.crossfade)
        }
    }

    private func exportButton(_ title: String, subtitle: String, icon: String,
                              action: @escaping @MainActor () async throws -> Void) -> some View {
        Button {
            progress = 0
            errorMessage = nil
            // Render on the main actor after the progress card appears. Async
            // because a video is written frame by frame and takes seconds —
            // the raster paths are synchronous and satisfy this signature
            // unchanged.
            exportTask = Task { @MainActor in
                defer { progress = nil; exportTask = nil }
                do { try await action() }
                catch is CancellationError { /* asked for; nothing to report */ }
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
        let size = DesignExporter.outputSize(design: exportedDesign, requested: scale)
        let dims = "\(Int(size.width)) × \(Int(size.height)) px"
        guard DesignExporter.isClamped(design: exportedDesign, requested: scale) else { return dims }
        return dims + " — reduced from \(String(format: "%.1f", scale))× so the render fits in memory."
    }

    private var estimatedSize: String {
        let bytes = DesignExporter.estimatedJPEGBytes(design: exportedDesign,
                                                      requested: scale, quality: jpegQuality)
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    @MainActor
    private func export(_ format: DesignExporter.RasterFormat) throws {
        let urls = try DesignExporter.exportPages(
            design: exportedDesign, range: exportedRange, current: exportedPageIndex,
            format: format, scale: scale, quality: jpegQuality,
            // JPEG has no alpha channel to be transparent in.
            transparent: transparent && format == .png,
            progress: { progress = $0 })
        sharedURLs = urls
        exportedURL = urls.first
    }

    private var movieSubtitle: String {
        let pages = store.design.pages.count
        let seconds = Double(pages) * MovieExporter.Settings(store.design.motion).secondsPerPage
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
        try DesignExporter.exportPrintPDF(design: store.design, range: exportedRange, current: exportedPageIndex,
                                          options: paper, to: url)

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
        try await MovieExporter.exportMP4(design: store.design, settings: MovieExporter.Settings(store.design.motion),
                                              to: url, progress: report)
        sharedURLs = [url]
        exportedURL = url
    }

    @MainActor
    private func exportGIF() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "gif")
        try MovieExporter.exportGIF(design: store.design, settings: MovieExporter.Settings(store.design.motion),
                                    to: url, progress: { progress = $0 })
        sharedURLs = [url]
        exportedURL = url
    }

    @MainActor
    private func exportSVG() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "svg")
        try DesignExporter.exportSVG(design: exportedDesign,
                                     page: exportedDesign.pages[exportedPageIndex], to: url)
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
