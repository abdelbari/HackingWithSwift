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
    @State private var exporting = false
    @State private var exportedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
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
                    // "2×" means nothing on its own; the pixel count is the
                    // thing people actually need to match a platform's
                    // requirements. It also gives the size cap somewhere
                    // honest to appear rather than silently under-delivering.
                    Text(sizeNote)
                }
                Section("Format") {
                    exportButton("PNG", subtitle: "Current page, best for sharing", icon: "photo") {
                        try export(.png)
                    }
                    exportButton("JPEG", subtitle: "Current page, smaller file", icon: "photo.fill") {
                        try export(.jpeg)
                    }
                    exportButton("PDF", subtitle: store.design.pages.count > 1
                                 ? "All \(store.design.pages.count) pages, vector"
                                 : "Print-ready document, vector", icon: "doc.richtext") {
                        try exportPDF()
                    }
                    exportButton("SVG", subtitle: "Current page, editable vectors",
                                 icon: "scribble.variable") {
                        try exportSVG()
                    }
                }
                Section {
                    exportButton("MP4 video", subtitle: movieSubtitle, icon: "film") {
                        try await exportMovie()
                    }
                    exportButton("Animated GIF", subtitle: movieSubtitle, icon: "square.stack.3d.down.right") {
                        try exportGIF()
                    }
                } header: {
                    Text("Motion")
                } footer: {
                    Text("Each page holds for \(MovieExporter.Settings().secondsPerPage, specifier: "%.1f")s "
                         + "with a slow push in and a cross-fade between pages.")
                }
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
                set: { if $0 == nil { exportedURL = nil } })) { item in
                ShareSheet(url: item.url)
            }
            .overlay {
                if exporting { ProgressView("Rendering…") }
            }
        }
        .presentationDetents([.medium])
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

    @MainActor
    private func export(_ format: DesignExporter.RasterFormat) throws {
        let url = DesignExporter.fileURL(for: store.design, ext: format.ext)
        try DesignExporter.exportRaster(design: store.design, page: store.page,
                                        format: format, scale: scale, to: url)
        exportedURL = url
    }

    private var movieSubtitle: String {
        let pages = store.design.pages.count
        let seconds = Double(pages) * MovieExporter.Settings().secondsPerPage
        return pages > 1
            ? "All \(pages) pages, \(String(format: "%.0f", seconds))s"
            : "One page, \(String(format: "%.0f", seconds))s"
    }

    @MainActor
    private func exportMovie() async throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "mp4")
        try await MovieExporter.exportMP4(design: store.design, to: url)
        exportedURL = url
    }

    @MainActor
    private func exportGIF() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "gif")
        try MovieExporter.exportGIF(design: store.design, to: url)
        exportedURL = url
    }

    @MainActor
    private func exportSVG() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "svg")
        try DesignExporter.exportSVG(design: store.design, page: store.page, to: url)
        exportedURL = url
    }

    @MainActor
    private func exportPDF() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "pdf")
        try DesignExporter.exportPDF(design: store.design, to: url)
        exportedURL = url
    }
}

private struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
