// Export sheet: PNG / JPEG at 1-3x and multi-page PDF, rendered with
// ImageRenderer from the same PageRenderView the canvas uses, shared via
// the system share sheet.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
                Section("Quality") {
                    Picker("Scale", selection: $scale) {
                        Text("1×").tag(1)
                        Text("2×").tag(2)
                        Text("3×").tag(3)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Format") {
                    exportButton("PNG", subtitle: "Current page, best for sharing", icon: "photo") {
                        try exportRaster(format: .png)
                    }
                    exportButton("JPEG", subtitle: "Current page, smaller file", icon: "photo.fill") {
                        try exportRaster(format: .jpeg)
                    }
                    exportButton("PDF", subtitle: store.design.pages.count > 1
                                 ? "All \(store.design.pages.count) pages"
                                 : "Print-ready document", icon: "doc.richtext") {
                        try exportPDF()
                    }
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

    private enum RasterFormat { case png, jpeg }

    private func exportButton(_ title: String, subtitle: String, icon: String,
                              action: @escaping @MainActor () throws -> Void) -> some View {
        Button {
            exporting = true
            errorMessage = nil
            // Render on the main actor after the spinner appears.
            Task { @MainActor in
                defer { exporting = false }
                do { try action() }
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

    @MainActor
    private func renderPage(_ page: Page) throws -> UIImage {
        let renderer = ImageRenderer(content: PageRenderView(design: store.design, page: page))
        renderer.scale = CGFloat(scale)
        renderer.isOpaque = true
        guard let image = renderer.uiImage else {
            throw ExportError.renderFailed
        }
        return image
    }

    @MainActor
    private func exportRaster(format: RasterFormat) throws {
        let image = try renderPage(store.page)
        let data: Data?
        let ext: String
        switch format {
        case .png: data = image.pngData(); ext = "png"
        case .jpeg: data = image.jpegData(compressionQuality: 0.92); ext = "jpg"
        }
        guard let data else { throw ExportError.encodeFailed }
        let url = tempURL(ext: ext)
        try data.write(to: url)
        exportedURL = url
    }

    @MainActor
    private func exportPDF() throws {
        let pxToPt = 72.0 / 96.0
        let bounds = CGRect(x: 0, y: 0,
                            width: store.design.width * pxToPt,
                            height: store.design.height * pxToPt)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        var failure: Error?
        // Render each page inside the loop so only ONE page bitmap is alive
        // at a time. Pre-rendering them all would hold, for a ten-page poster
        // at 3x, well over a gigabyte of pixels at once.
        let data = renderer.pdfData { ctx in
            for page in store.design.pages {
                ctx.beginPage()
                autoreleasepool {
                    if let image = try? renderPage(page) {
                        image.draw(in: bounds)
                    } else if failure == nil {
                        failure = ExportError.renderFailed
                    }
                }
            }
        }
        if let failure { throw failure }
        let url = tempURL(ext: "pdf")
        try data.write(to: url)
        exportedURL = url
    }

    private func tempURL(ext: String) -> URL {
        let name = store.design.title
            .replacingOccurrences(of: "[^\\w\\d-_ ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        let base = name.isEmpty ? "design" : name
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base).\(ext)")
    }

    private enum ExportError: LocalizedError {
        case renderFailed, encodeFailed
        var errorDescription: String? {
            switch self {
            case .renderFailed: return "could not render the page"
            case .encodeFailed: return "could not encode the image"
            }
        }
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
